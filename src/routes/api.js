// JSON API for the native iOS app, mounted at /api/v1.
//
// Auth is the ordinary session cookie, obtained through the app sign-in flow (lib/appLogin.js),
// so sign-in limits and "Signed-in devices" apply exactly as on the web. Every request must carry
// the X-Obelo-Client header: a custom header can't be sent cross-site without a CORS preflight
// (which this server never grants), so together with the SameSite=Lax cookie this rules out CSRF.
//
// Business rules live in the web routes and are reused from there (recurrence, streaks,
// completion, dashboard), so the app and the web always agree.

const { isDemo } = require('../lib/demo');
const crypto  = require('crypto');
const express = require('express');
const bcrypt  = require('bcryptjs');
const { rateLimit } = require('express-rate-limit');
const prisma  = require('../lib/prisma');
const log     = require('../services/logService');
const appLogin = require('../lib/appLogin');
const passwords = require('../lib/passwords');
const { markSignedIn } = require('../lib/sessionLifetime');
const userSessions = require('../lib/userSessions');
const { parseTags, getAllUserTags } = require('../lib/tags');
const { prefsHour12 } = require('../lib/timeFormat');
const { eventDayStr } = require('../lib/eventDate');
const { isDarkTheme, VALID_THEME_IDS, NOTE_PAPERS, notePaperChoice } = require('../config/themes');
const { decrypt: decryptNote, encrypt: encryptNote } = require('../lib/noteLock');
const { recalcStreak, DAYS } = require('../services/routineStreaks');
const capture = require('../services/captureService');
const folders = require('../services/folders');
const aiChat = require('../services/aiChatService');
const { AiError } = require('../lib/aiProvider');
const { getShareableUsers } = require('../lib/users');
const { shareBookmarkToUser } = require('../lib/bookmarkShare');
const uploads = require('../lib/uploads');

const tasksLib     = require('./tasks');
const remindersLib = require('./reminders');
const routinesLib  = require('./routines');
const { loadDashboard } = require('./dashboard');
const { noteSlipCutoff, upload: noteUpload, saveAttachment, removeAttachment } = require('./notes');
const { computeAnalytics } = require('./analytics');
const { refineWithAi } = require('../services/analyticsInsights');
const aiProvider = require('../lib/aiProvider');
const calendarLib = require('./calendar');
const calSources = require('../lib/calendarSources');
const settingsLib = require('./settings');
const { MODULES } = require('../config/modules');
const ntfy = require('../services/ntfyService');
const { getTagUsageCounts, createTag, renameTag, deleteTag } = require('../lib/tags');

const router = express.Router();

// ── Guards ──────────────────────────────────────────────────────────────────

router.use((req, res, next) => {
  // X-VibeTrack-Client: app builds from before the rename
  if (!req.get('x-obelo-client') && !req.get('x-vibetrack-client')) return res.status(400).json({ error: 'Missing X-Obelo-Client header' });
  next();
});

const requireApiAuth = (req, res, next) => {
  if (!req.session.userId || !req.user) return res.status(401).json({ error: 'Not signed in' });
  next();
};

// Production cookies are Secure: over plain http:// the app would sign in but never keep the session
const needsHttps = (req) => process.env.NODE_ENV === 'production' && !req.secure;
const HTTPS_ERROR = "This server's address isn't using HTTPS, so signing in can't work. Use the https:// address.";

const exchangeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 20, standardHeaders: true, legacyHeaders: false,
  message: { error: 'Too many attempts — please try again later.' },
  skip: () => process.env.NODE_ENV === 'development',
});
const pinLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 10, standardHeaders: true, legacyHeaders: false,
  message: { error: 'Too many attempts — please try again later.' },
  skip: () => process.env.NODE_ENV === 'development',
});

// Async handler wrapper: errors become JSON instead of the HTML error page
const h = (fn) => (req, res) => Promise.resolve(fn(req, res)).catch((err) => {
  if (err instanceof AiError) return res.status(err.status).json({ error: err.message });
  log.error('api', `${req.method} ${req.path}: ${err.message}`, { stack: err.stack?.split('\n')[1]?.trim() });
  res.status(500).json({ error: 'Something went wrong. Please try again.' });
});

const notFound = (res, what = 'Not found') => res.status(404).json({ error: what });
const bad = (res, msg) => res.status(400).json({ error: msg });
const intId = (v) => { const n = Number(v); return Number.isInteger(n) && n > 0 ? n : null; };

// ── Date helpers ────────────────────────────────────────────────────────────

const ymd = (d) => (d ? new Date(d).toISOString().slice(0, 10) : null);
const isYmd = (s) => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s);
const isHHMM = (s) => typeof s === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(s);
const tzOf = (req) => req.user.timezone || 'UTC';
const todayStr = (tz) => new Date().toLocaleDateString('en-CA', { timeZone: tz });
const nowHHMM = (tz) => {
  const s = new Date().toLocaleTimeString('en-US', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false });
  return s === '24:00' ? '00:00' : s;
};

// The UTC instant of local midnight on dateStr in tz
function localMidnightUTC(dateStr, tz) {
  const noon = new Date(dateStr + 'T12:00:00Z');
  const local = noon.toLocaleTimeString('en-US', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false });
  const [hh, mm] = (local === '24:00' ? '00:00' : local).split(':').map(Number);
  const offsetMs = (hh * 60 + mm - 12 * 60) * 60000;
  return new Date(new Date(dateStr + 'T00:00:00Z').getTime() - offsetMs);
}

// 'overdue' | 'today' | null, the same rule the web lists colour by
function dueState(dueDate, dueTime, tz, done = false) {
  if (!dueDate || done) return null;
  const due = ymd(dueDate);
  const today = todayStr(tz);
  if (due < today) return 'overdue';
  if (due === today) return dueTime && dueTime < nowHHMM(tz) ? 'overdue' : 'today';
  return null;
}

// ── Serializers ─────────────────────────────────────────────────────────────

function taskJson(t, tz) {
  return {
    id: t.id, title: t.title, notes: t.notes || '', status: t.status, priority: t.priority,
    dueDate: ymd(t.dueDate), dueTime: t.dueTime, tags: t.tags,
    recurring: t.recurring, recurRule: t.recurRule, parentId: t.parentId,
    createdAt: t.createdAt, updatedAt: t.updatedAt, completedAt: t.completedAt,
    dueState: dueState(t.dueDate, t.dueTime, tz, t.status === 'done' || t.status === 'archived'),
    subtasks: t.subtasks ? t.subtasks.map((s) => ({ id: s.id, title: s.title, done: s.status === 'done' })) : undefined,
  };
}

function reminderJson(r, tz) {
  return {
    id: r.id, title: r.title, notes: r.notes || '', dueDate: ymd(r.dueDate), dueTime: r.dueTime,
    reminderAt: r.reminderAt, priority: r.priority, tags: r.tags, completed: r.completed,
    recurring: r.recurring, recurRule: r.recurRule, recurLabel: remindersLib.recurRuleLabel(r.recurRule),
    createdAt: r.createdAt, completedAt: r.completedAt,
    dueState: dueState(r.dueDate, r.dueTime, tz, r.completed),
  };
}

function routineJson(r, extra = {}) {
  return {
    id: r.id, title: r.title, description: r.description || '', timeOfDay: r.timeOfDay,
    specificTime: r.specificTime, frequency: r.frequency, scheduleDays: r.scheduleDays,
    durationDays: r.durationDays, startDate: ymd(r.startDate), streakCurrent: r.streakCurrent,
    streakBest: r.streakBest, tags: r.tags, notify: r.notify, active: r.active,
    completionCount: r._count?.completions ?? extra.completionCount ?? 0,
    completedToday: false, dueToday: false, createdAt: r.createdAt,
    ...extra,
  };
}

function noteSummaryJson(n) {
  return {
    id: n.id, type: n.type, title: n.title,
    preview: n.locked ? '' : (n.content || '').slice(0, 240),
    tags: n.tags, pinned: n.pinned, flaggedForReview: n.flaggedForReview, locked: n.locked,
    hasDrawing: n.hasDrawing, private: n.private, folderId: n.folderId ?? null,
    createdAt: n.createdAt, updatedAt: n.updatedAt,
  };
}

function noteJson(n, content) {
  return {
    ...noteSummaryJson(n),
    content: content ?? (n.locked ? null : (n.content || '')),
    // Handwriting, in the web canvas's JSON format: { v, w, h, strokes: [{ color, width, eraser, points: [{ x, y, p }] }] }
    drawingData: n.hasDrawing && !n.locked ? (n.drawingData || null) : null,
    source: n.source, author: n.author, reviewDate: ymd(n.reviewDate),
    attachments: (n.attachments || []).map((a) => ({
      id: a.id, mimeType: a.mimeType, url: `/notes/${n.id}/attachments/${encodeURIComponent(a.filePath)}`,
    })),
    thoughts: (n.thoughts || []).map((t) => ({
      id: t.id, content: t.content, createdAt: t.createdAt, author: t.user?.displayName || '',
    })),
  };
}

const hhmmIn = (d, tz) => {
  const s = new Date(d).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tz });
  return s.startsWith('24') ? '00' + s.slice(2) : s;
};

function eventJson(e, tz, userId) {
  return {
    id: e.id, title: e.title, startAt: e.startAt, endAt: e.endAt, allDay: e.allDay,
    // Same rules as the web: only events you made in Obelo can be edited; any of your own can be deleted
    editable: e.userId === userId && e.createdInObelo,
    deletable: e.userId === userId,
    startTime: e.allDay ? null : hhmmIn(e.startAt, tz),
    endTime: e.allDay ? null : hhmmIn(e.endAt, tz),
    location: e.location, description: e.description, url: e.url,
    calendarName: e.localCalendar?.name || e.calendarName || e.source?.name || null,
    color: e.localCalendar?.color || e.source?.color || '#6366f1',
    day: eventDayStr(e.startAt, e.allDay, tz),
  };
}

const bookmarkJson = (b) => ({
  id: b.id, url: b.url, title: b.title, description: b.description, tags: b.tags,
  createdAt: b.createdAt, updatedAt: b.updatedAt,
});

const tagsFrom = (v) => (Array.isArray(v) ? parseTags(v.join(',')) : parseTags(v || ''));

// ── Auth ────────────────────────────────────────────────────────────────────

// POST /auth/exchange { code } — trade the one-time SSO code for a session cookie
router.post('/auth/exchange', exchangeLimiter, h(async (req, res) => {
  if (needsHttps(req)) return res.status(400).json({ error: HTTPS_ERROR });
  const userId = appLogin.redeemCode(req.body?.code);
  if (!userId) return res.status(401).json({ error: 'That sign-in link has expired. Please try again.' });
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) return res.status(401).json({ error: 'Account not found.' });
  await new Promise((resolve, reject) => req.session.regenerate((err) => (err ? reject(err) : resolve())));
  req.session.userId = user.id;
  markSignedIn(req.session, { app: true });
  userSessions.recordDevice(req.session, req);
  await new Promise((resolve, reject) => req.session.save((err) => (err ? reject(err) : resolve())));
  await prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } }).catch(() => {});
  log.info('auth', `App sign-in: @${user.username}`, { userId: user.id });
  res.json({ ok: true });
}));

// POST /auth/login { username, password } — password sign-in for the apps (same session as the web)
router.post('/auth/login', exchangeLimiter, h(async (req, res) => {
  if (needsHttps(req)) return res.status(400).json({ error: HTTPS_ERROR });
  if (!(await passwords.passwordLoginEnabled())) {
    return res.status(403).json({ error: 'Password sign-in is switched off on this server.' });
  }
  const user = await passwords.authenticate(req.body?.username, req.body?.password);
  if (!user) {
    log.warn('auth', 'App password sign-in failed');
    return res.status(401).json({ error: 'Wrong username or password.' });
  }
  await new Promise((resolve, reject) => req.session.regenerate((err) => (err ? reject(err) : resolve())));
  req.session.userId = user.id;
  markSignedIn(req.session, { app: true });
  userSessions.recordDevice(req.session, req);
  await new Promise((resolve, reject) => req.session.save((err) => (err ? reject(err) : resolve())));
  await prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } }).catch(() => {});
  log.info('auth', `App password sign-in: @${user.username}`, { userId: user.id });
  res.json({ ok: true });
}));

// POST /auth/password-code { username, code, newPassword } — choose a password with the setup code an
// admin gave you (the in-app version of the one-time link). The app then signs in as usual.
router.post('/auth/password-code', exchangeLimiter, h(async (req, res) => {
  if (!(await passwords.passwordLoginEnabled())) {
    return res.status(403).json({ error: 'Password sign-in is switched off on this server.' });
  }
  const out = await passwords.redeemCode(req.body?.username, req.body?.code, req.body?.newPassword);
  if (out.error) return res.status(400).json({ error: out.error });
  const ended = await userSessions.endForUser(out.user.id, null);
  log.info('auth', `Password set from a setup code: @${out.user.username}`, { userId: out.user.id, ended });
  res.json({ ok: true });
}));

// POST /settings/password { currentPassword?, newPassword } — set or change your own password
router.post('/settings/password', requireApiAuth, pinLimiter, h(async (req, res) => {
  if (!(await passwords.passwordLoginEnabled())) {
    return res.status(403).json({ error: 'Password sign-in is switched off on this server.' });
  }
  const error = await passwords.changeOwnPassword(req.user.id, req.body?.currentPassword, req.body?.newPassword);
  if (error) return res.status(400).json({ error });
  const ended = await userSessions.endForUser(req.user.id, req.sessionID);
  log.info('auth', `@${req.user.username} changed their password (app)`, { userId: req.user.id, ended });
  res.json({ ok: true });
}));

// POST /auth/dev — local development only: sign the app in as DEV_APP_LOGIN_USER without SSO
router.post('/auth/dev', h(async (req, res) => {
  const username = process.env.DEV_APP_LOGIN_USER;
  if (process.env.NODE_ENV !== 'development' || !username) return notFound(res);
  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) return notFound(res, `No user @${username}`);
  await new Promise((resolve, reject) => req.session.regenerate((err) => (err ? reject(err) : resolve())));
  req.session.userId = user.id;
  markSignedIn(req.session, { app: true });
  userSessions.recordDevice(req.session, req);
  await new Promise((resolve, reject) => req.session.save((err) => (err ? reject(err) : resolve())));
  log.warn('auth', `DEV app sign-in without SSO: @${user.username}`, { userId: user.id });
  res.json({ ok: true });
}));

router.post('/auth/logout', (req, res) => {
  const userId = req.session.userId;
  req.session.destroy(() => {
    if (userId) log.info('auth', 'App sign-out', { userId });
    res.json({ ok: true });
  });
});

router.use(requireApiAuth);

// ── Me ──────────────────────────────────────────────────────────────────────

router.get('/me', h(async (req, res) => {
  const prefs = req.user.preferences || {};
  const theme = prefs.theme || 'dark';
  const modules = (res.locals.enabledModules || []).map((m) => ({ key: m.key, label: m.label, beta: !!m.beta }));
  res.json({
    // The public demo: the apps hide calendar accounts and notification channels (the server refuses them too)
    demo: isDemo(),
    user: {
      id: req.user.id, username: req.user.username, displayName: req.user.displayName,
      email: req.user.email, role: req.user.role, timezone: req.user.timezone,
    },
    appearance: {
      theme, isDark: isDarkTheme(theme, prefs.customBase),
      customAccent: prefs.customAccent || '#6366f1', customBase: prefs.customBase === 'light' ? 'light' : 'dark',
      statusColors: prefs.statusColors === 'tailwind' ? 'tailwind' : 'catppuccin',
    },
    notePaper: notePaperChoice(prefs),
    hour12: prefsHour12(prefs),
    avatarUrl: res.locals._avatarUrl || null,
    hasCustomAvatar: !!res.locals._hasCustomAvatar,
    modules,
    mobileNav: (res.locals.mobileNavModules || []).map((m) => m.key),
    aiEnabled: !!res.locals.aiEnabled,
    canLockNotes: !!prefs.noteLockPin,
    version: res.locals._version,
  });
}));

// Theme, custom accent, base and status colours. Values not sent keep their saved value.
async function updateAppearance(req, res) {
  const body = req.body || {};
  if (body.theme !== undefined && !VALID_THEME_IDS.has(body.theme)) return bad(res, 'Unknown theme');
  if (body.customAccent !== undefined && !/^#[0-9a-f]{6}$/i.test(body.customAccent)) return bad(res, 'Accent must be a colour like #6366f1');
  if (body.statusColors !== undefined && !['catppuccin', 'tailwind'].includes(body.statusColors)) return bad(res, 'Status colours must be catppuccin or tailwind');
  const p = req.user.preferences || {};
  await settingsLib.saveAppearance(req.user.id, {
    theme: body.theme ?? p.theme ?? 'dark',
    customAccent: body.customAccent ?? p.customAccent,
    customBase: body.customBase ?? p.customBase,
    statusColors: body.statusColors ?? p.statusColors,
  });
  res.json({ ok: true });
}
router.post('/me/appearance', h(updateAppearance));

router.get('/tags', h(async (req, res) => res.json({ tags: await getAllUserTags(req.user.id) })));

// Signed-in devices
router.get('/sessions', h(async (req, res) => {
  res.json({ sessions: await userSessions.listForUser(req.user.id, req.sessionID) });
}));
router.post('/sessions/:key/end', h(async (req, res) => {
  const key = String(req.params.key);
  if (!/^[0-9a-f]{16}$/.test(key)) return bad(res, 'Unknown session');
  const ended = await userSessions.endForUser(req.user.id, req.sessionID, [key]);
  res.json({ ended });
}));

// ── Settings ────────────────────────────────────────────────────────────────

const WIDGET_LABELS = {
  focus: ['My Focus', 'Tasks set to "Today" status'],
  calendar: ['Calendar', "Today's events from your calendars"],
  due_items: ['Due Today & Overdue', 'Open tasks and reminders that are due'],
  routines: ['Routines', "Today's habits and streaks"],
  resurfaced: ['Resurfacing', 'A past note surfaced daily for reflection'],
  review: ['Needs Review', 'Notes flagged for review'],
};

// Everything the app's Settings screen edits (Account, Modules, Appearance, Dashboard)
router.get('/settings', h(async (req, res) => {
  const userId = req.user.id;
  const prefs = req.user.preferences || {};
  const userModules = await prisma.userModule.findMany({ where: { userId } });
  const enabledMap = Object.fromEntries(userModules.map((m) => [m.moduleKey, m.enabled]));
  const posMap = Object.fromEntries(userModules.filter((m) => m.position != null).map((m) => [m.moduleKey, m.position]));
  const defaultOrder = Object.fromEntries(MODULES.map((m, i) => [m.key, i]));
  // Same list and order as the web's Modules tab
  const modules = MODULES.filter((m) => !m.hidden).map((m) => ({
    key: m.key, label: m.label, alwaysEnabled: !!m.alwaysEnabled,
    enabled: m.alwaysEnabled ? true : enabledMap[m.key] !== false,
    position: posMap[m.key] != null ? posMap[m.key] : defaultOrder[m.key],
  })).sort((a, b) => {
    if (a.key === 'dashboard') return -1;
    if (b.key === 'dashboard') return 1;
    if (a.key === 'settings') return 1;
    if (b.key === 'settings') return -1;
    return a.position - b.position;
  }).map(({ position, ...m }) => m);
  const saved = Array.isArray(prefs.dashboardWidgets) && prefs.dashboardWidgets.length
    ? prefs.dashboardWidgets : settingsLib.WIDGET_KEYS.map((key) => ({ key, enabled: true }));
  const pwRow = await prisma.user.findUnique({ where: { id: userId }, select: { passwordHash: true } });
  const passwordLogin = await passwords.passwordLoginEnabled();
  res.json({
    account: {
      hasPassword: !!pwRow?.passwordHash, passwordLogin,
      displayName: req.user.displayName, username: req.user.username, email: req.user.email || '',
      timezone: req.user.timezone || 'America/New_York', timeFormat: prefs.timeFormat === '24h' ? '24h' : '12h',
      avatarUrl: res.locals._avatarUrl || null, hasCustomAvatar: !!res.locals._hasCustomAvatar,
    },
    modules,
    appearance: {
      theme: prefs.theme || 'dark', customAccent: prefs.customAccent || '#6366f1', customBase: prefs.customBase === 'light' ? 'light' : 'dark',
      statusColors: prefs.statusColors === 'tailwind' ? 'tailwind' : 'catppuccin',
    },
    dashboard: saved.filter((w) => WIDGET_LABELS[w.key]).map((w) => ({
      key: w.key, enabled: !!w.enabled, label: WIDGET_LABELS[w.key][0], description: WIDGET_LABELS[w.key][1],
    })),
  });
}));

// ── Settings round two: Notifications, Notes, Tags ──────────────────────────

router.get('/settings/notifications', h(async (req, res) => {
  const prefs = req.user.preferences || {};
  const rows = await prisma.notificationPref.findMany({ where: { userId: req.user.id } });
  const byType = Object.fromEntries(rows.map((r) => [r.type, r]));
  const types = Object.fromEntries(settingsLib.NOTIF_TYPES.map((type) => {
    const r = byType[type];
    return [type, {
      enabled: !!r?.enabled,
      sendTime: r?.sendTime || settingsLib.DEFAULT_SEND_TIMES[type],
      channels: { pushover: !!r?.channels?.pushover, email: !!r?.channels?.email, ntfy: !!r?.channels?.ntfy },
    }];
  }));
  res.json({
    pushoverAvailable: !!process.env.PUSHOVER_APP_TOKEN,
    pushoverKey: prefs.pushoverKey || '', pushoverEnabled: !!prefs.pushoverEnabled,
    ntfyAvailable: ntfy.isConfigured(), ntfyServer: ntfy.serverUrl(),
    ntfyEnabled: !!prefs.ntfyEnabled, ntfyTopic: prefs.ntfyTopic || '',
    emailAvailable: require('../services/emailService').isConfigured(),
    accountEmail: req.user.email || '',
    notifEmail: prefs.notifEmail && prefs.notifEmail !== (req.user.email || '') ? prefs.notifEmail : '',
    types,
  });
}));

router.put('/settings/notifications', h(async (req, res) => {
  const b = req.body || {};
  if (b.notifEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(b.notifEmail).trim())) return bad(res, 'Invalid email address');
  await settingsLib.saveNotifications(req.user, {
    pushoverKey: b.pushoverKey, pushoverEnabled: b.pushoverEnabled, ntfyEnabled: b.ntfyEnabled, notifEmail: b.notifEmail, types: b.types,
  });
  res.json({ ok: true });
}));

router.post('/settings/notifications/test-ntfy', h(async (req, res) => {
  const error = await settingsLib.sendNtfyTest(req.user);
  if (error) return bad(res, error);
  res.json({ message: 'Test notification sent via ntfy' });
}));

router.post('/settings/notifications/test-email', h(async (req, res) => {
  const { emailTo, error } = await settingsLib.sendTestEmail(req.user);
  if (error) return bad(res, error);
  res.json({ message: `Test email sent to ${emailTo}` });
}));

router.post('/settings/notifications/ntfy-topic', h(async (req, res) => {
  res.json({ ntfyTopic: await settingsLib.newNtfyTopic(req.user.id) });
}));

router.get('/settings/notes', h(async (req, res) => {
  const user = await prisma.user.findUnique({ where: { id: req.user.id }, select: { preferences: true } });
  const prefs = user.preferences || {};
  res.json({ autosaveEnabled: prefs.autosaveEnabled !== false, autosaveDuration: prefs.autosaveDuration || 'immediate', hasPin: !!prefs.noteLockPin, notePaper: notePaperChoice(prefs) });
}));

router.put('/settings/notes', h(async (req, res) => {
  const paper = req.body?.notePaper;
  if (paper !== undefined && !NOTE_PAPERS.includes(paper)) return bad(res, 'Handwriting paper must be theme, dark or white');
  await settingsLib.saveNotePrefs(req.user.id, { autosaveEnabled: req.body?.autosaveEnabled, autosaveDuration: req.body?.autosaveDuration, notePaper: paper });
  res.json({ ok: true });
}));

// { action: 'remove', currentPin } or { currentPin?, newPin, confirmPin }
router.post('/settings/note-pin', pinLimiter, h(async (req, res) => {
  const b = req.body || {};
  const { error, message } = await settingsLib.setNotePin(req.user.id, {
    action: b.action, currentPin: String(b.currentPin || ''), newPin: String(b.newPin || ''), confirmPin: String(b.confirmPin || ''),
  });
  if (error) return bad(res, error);
  res.json({ message });
}));

router.get('/settings/tags', h(async (req, res) => {
  const counts = await getTagUsageCounts(req.user.id);
  res.json({ tags: Object.entries(counts).sort(([a], [b]) => a.localeCompare(b)).map(([name, count]) => ({ name, count })) });
}));

router.post('/settings/tags', h(async (req, res) => {
  const name = String(req.body?.name || '').trim().toLowerCase();
  if (!name) return bad(res, 'Tag name cannot be empty');
  await createTag(req.user.id, name);
  res.status(201).json({ ok: true });
}));

router.put('/settings/tags/rename', h(async (req, res) => {
  const oldName = String(req.body?.oldName || '');
  const newName = String(req.body?.newName || '').trim().toLowerCase();
  if (!oldName || !newName) return bad(res, 'Tag name cannot be empty');
  if (newName !== oldName) await renameTag(req.user.id, oldName, newName);
  res.json({ ok: true });
}));

router.post('/settings/tags/delete', h(async (req, res) => {
  const name = String(req.body?.name || '');
  if (!name) return bad(res, 'Missing tag name');
  await deleteTag(req.user.id, name);
  res.json({ ok: true });
}));

// ── Data: export, import, delete account (same code as the web's Data tab) ───

// GET /settings/export/json | tasks.csv | notes.json | bookmarks.csv | bookmarks.html — a file download
router.get('/settings/export/:name', h(async (req, res) => {
  await settingsLib.sendExport(req.params.name, req.user, res);
}));

// Multipart uploads: notes take "files" (several .md), tasks and json take "file"
function importRoute(field, many, run) {
  const upload = many ? settingsLib.importUpload.array(field, 200) : settingsLib.importUpload.single(field);
  return (req, res) => upload(req, res, (err) => {
    if (err) {
      const tooBig = err.code === 'LIMIT_FILE_SIZE';
      return res.status(tooBig ? 413 : 400).json({ error: tooBig ? 'That file is over the 10 MB limit.' : 'Upload failed.' });
    }
    h(async () => {
      const { message, error } = await run(req);
      if (error) return bad(res, error);
      res.json({ message });
    })(req, res);
  });
}
router.post('/settings/import/notes', importRoute('files', true, (req) => settingsLib.importNotes(req.user, req.files)));
router.post('/settings/import/tasks', importRoute('file', false, (req) => settingsLib.importTasks(req.user, req.file)));
router.post('/settings/import/json', importRoute('file', false, (req) => settingsLib.importJson(req.user, req.file)));

// { confirmUsername } — deletes the account and everything in it, then signs this device out
router.post('/settings/delete-account', h(async (req, res) => {
  const username = req.user.username;
  if (!await settingsLib.deleteAccount(req.user, String(req.body?.confirmUsername || ''))) {
    return bad(res, "That doesn't match your username.");
  }
  log.warn('auth', `Account deleted from the app: @${username}`);
  req.session.destroy(() => res.json({ ok: true }));
}));

router.put('/settings/account', h(async (req, res) => {
  const b = req.body || {};
  const error = await settingsLib.saveAccount(req.user, {
    displayName: b.displayName, email: b.email, timezone: b.timezone, timeFormat: b.timeFormat,
  });
  if (error) return bad(res, error);
  res.json({ ok: true });
}));

// { modules: [{ key, enabled }] } in display order
router.put('/settings/modules', h(async (req, res) => {
  const list = Array.isArray(req.body?.modules) ? req.body.modules : null;
  if (!list) return bad(res, 'modules required');
  const known = new Set(MODULES.map((m) => m.key));
  const clean = list.filter((m) => m && known.has(m.key));
  await settingsLib.saveModules(req.user.id, clean.filter((m) => m.enabled).map((m) => m.key), clean.map((m) => m.key));
  res.json({ ok: true });
}));

router.put('/settings/appearance', h(updateAppearance));

// { widgets: [{ key, enabled }] } in display order
router.put('/settings/dashboard', h(async (req, res) => {
  const list = Array.isArray(req.body?.widgets) ? req.body.widgets : null;
  if (!list) return bad(res, 'widgets required');
  await settingsLib.saveDashboard(req.user.id, list.map((w) => w?.key), list.filter((w) => w?.enabled).map((w) => w.key));
  res.json({ ok: true });
}));

// Profile photo (multipart, field "avatar", images up to 5 MB like the web)
router.post('/settings/avatar', (req, res) => {
  settingsLib.avatarUpload.single('avatar')(req, res, (err) => {
    if (err) {
      const tooBig = err.code === 'LIMIT_FILE_SIZE';
      return res.status(tooBig ? 413 : 400).json({ error: tooBig ? 'That photo is over the 5 MB limit.' : 'Upload failed.' });
    }
    h(async () => {
      if (!req.file) return bad(res, 'Choose an image.');
      await settingsLib.saveAvatar(req.user.id, req.file);
      res.json({ ok: true });
    })(req, res);
  });
});

router.delete('/settings/avatar', h(async (req, res) => {
  await settingsLib.removeAvatar(req.user.id);
  res.json({ ok: true });
}));

router.post('/sessions/end-others', h(async (req, res) => {
  const ended = await userSessions.endForUser(req.user.id, req.sessionID);
  log.info('auth', `@${req.user.username} signed out all other devices (app)`, { userId: req.user.id, ended });
  res.json({ ended });
}));

// ── API tokens (the Shortcuts tab): for iOS Shortcuts to send captures to your account ──

const tokenJson = (t) => ({ id: t.id, label: t.label, createdAt: t.createdAt, lastUsed: t.lastUsed });

router.get('/settings/api-tokens', h(async (req, res) => {
  const tokens = await prisma.apiToken.findMany({ where: { userId: req.user.id }, orderBy: { createdAt: 'desc' } });
  res.json({ tokens: tokens.map(tokenJson) });
}));

// The token itself is in this one answer only; only its hash is kept, so it can never be shown again
router.post('/settings/api-tokens', h(async (req, res) => {
  const label = String(req.body?.label || '').trim().slice(0, 60) || 'iOS Shortcut';
  const raw = crypto.randomBytes(32).toString('hex');
  const hash = crypto.createHash('sha256').update(raw).digest('hex');
  const t = await prisma.apiToken.create({ data: { userId: req.user.id, tokenHash: hash, label } });
  log.info('auth', `@${req.user.username} created an API token "${label}" (app)`, { userId: req.user.id });
  res.status(201).json({ ...tokenJson(t), token: raw });
}));

router.delete('/settings/api-tokens/:id', h(async (req, res) => {
  await prisma.apiToken.deleteMany({ where: { id: intId(req.params.id) || 0, userId: req.user.id } });
  res.json({ ok: true });
}));

// ── Today ───────────────────────────────────────────────────────────────────

router.get('/dashboard', h(async (req, res) => {
  const tz = tzOf(req);
  const d = await loadDashboard(req);
  const [completionCounts] = await Promise.all([
    prisma.routineCompletion.groupBy({
      by: ['routineId'], where: { routineId: { in: d.dueRoutines.map((r) => r.id) } }, _count: true,
    }),
  ]);
  const countById = Object.fromEntries(completionCounts.map((c) => [c.routineId, c._count]));
  res.json({
    widgets: d.dashWidgets,
    slippingCount: d.slippingCount,
    focusTasks: d.focusTasks.map((t) => taskJson(t, tz)),
    events: d.calendarEvents.map((e) => eventJson(e, tz, req.user.id)),
    due: d.combined.map(({ item, type, overdue }) => ({
      type,
      overdue,
      task: type === 'task' ? taskJson(item, tz) : undefined,
      reminder: type === 'reminder' ? reminderJson(item, tz) : undefined,
    })),
    routines: d.dueRoutines.map((r) => routineJson(r, {
      completedToday: d.completedTodayIds.has(r.id), dueToday: true, completionCount: countById[r.id] || 0,
    })),
    resurfaced: d.resurfaceNote ? {
      id: d.resurfaceNote.id, title: d.resurfaceNote.title, type: d.resurfaceNote.type,
      createdAt: d.resurfaceNote.createdAt, preview: (d.resurfaceNote.content || '').slice(0, 200),
    } : null,
    review: d.reviewItems.map((n) => ({ id: n.id, title: n.title || (n.content || '').slice(0, 60) || 'Untitled', reviewDate: ymd(n.reviewDate) })),
    stale: d.slippingNotes.map((n) => ({
      id: n.id, title: n.title || (n.content || '').slice(0, 60) || 'Untitled',
      daysAgo: Math.floor((Date.now() - new Date(n.updatedAt)) / 86400000),
    })),
  });
}));

// ── Tasks ───────────────────────────────────────────────────────────────────

const TASK_VIEWS = ['inbox', 'today', 'upcoming', 'all', 'completed', 'archived', 'slipping'];
const PRIORITIES = ['none', 'low', 'medium', 'high'];

router.get('/tasks', h(async (req, res) => {
  const tz = tzOf(req);
  const view = TASK_VIEWS.includes(req.query.view) ? req.query.view : 'inbox';
  const where = tasksLib.buildWhere(req.user.id, view, tz);
  if (req.query.tag) where.tags = { has: String(req.query.tag) };
  if (req.query.search) {
    const q = String(req.query.search);
    where.OR = [{ title: { contains: q, mode: 'insensitive' } }, { notes: { contains: q, mode: 'insensitive' } }];
  }
  const { end, slipCut } = tasksLib.dayBounds(tz);
  const uid = req.user.id;
  const [tasks, tags, today, inbox, slipping] = await Promise.all([
    prisma.task.findMany({ where, orderBy: tasksLib.buildOrder(view) }).then((t) => tasksLib.sortByPriority(t, view)),
    getAllUserTags(uid),
    prisma.task.count({ where: { userId: uid, status: { notIn: ['done', 'archived'] }, dueDate: { lt: end } } }),
    prisma.task.count({ where: { userId: uid, status: { notIn: ['done', 'archived'] }, dueDate: null } }),
    prisma.task.count({ where: { userId: uid, status: { in: ['inbox', 'today', 'in-progress'] }, updatedAt: { lt: slipCut } } }),
  ]);
  res.json({ view, tasks: tasks.map((t) => taskJson(t, tz)), tags, counts: { today, inbox, slipping } });
}));

function taskData(body) {
  const data = {};
  if (body.title !== undefined) data.title = String(body.title).trim();
  if (body.notes !== undefined) data.notes = String(body.notes || '');
  if (body.status !== undefined) data.status = tasksLib.STATUSES.includes(body.status) ? body.status : 'inbox';
  if (body.priority !== undefined) data.priority = PRIORITIES.includes(body.priority) ? body.priority : 'none';
  if (body.dueDate !== undefined) data.dueDate = isYmd(body.dueDate) ? new Date(body.dueDate) : null;
  if (body.dueTime !== undefined) data.dueTime = isHHMM(body.dueTime) ? body.dueTime : null;
  if (body.tags !== undefined) data.tags = tagsFrom(body.tags);
  if (body.recurring !== undefined) {
    data.recurring = !!body.recurring;
    data.recurRule = body.recurring ? (String(body.recurRule || '') || 'daily') : null;
  }
  return data;
}

router.post('/tasks', h(async (req, res) => {
  const data = taskData(req.body || {});
  if (!data.title) return bad(res, 'Title is required.');
  const task = await prisma.task.create({ data: { status: 'inbox', priority: 'none', notes: '', ...data, userId: req.user.id } });
  res.status(201).json({ task: taskJson(task, tzOf(req)) });
}));

// Several tasks at once, same actions as the web's bulk bar. Only the caller's own tasks are touched.
const BULK_ACTIONS = ['complete', 'archive', 'restore', 'high', 'medium', 'low', 'none'];
router.post('/tasks/bulk', h(async (req, res) => {
  const { action } = req.body || {};
  if (!BULK_ACTIONS.includes(action)) return bad(res, 'Unknown action.');
  const ids = (Array.isArray(req.body.ids) ? req.body.ids : []).map(Number).filter((n) => Number.isInteger(n) && n > 0);
  if (!ids.length) return bad(res, 'Pick at least one task.');
  if (ids.length > 500) return bad(res, 'Too many tasks at once.');
  const where = { id: { in: ids }, userId: req.user.id };
  let count = 0;
  if (action === 'complete') {
    const tasks = await prisma.task.findMany({ where: { ...where, status: { not: 'done' } } });
    for (const t of tasks) await tasksLib.completeTask(t);
    count = tasks.length;
  } else {
    const data = action === 'archive' ? { status: 'archived' }
      : action === 'restore' ? { status: 'inbox', completedAt: null }
      : { priority: action };
    count = (await prisma.task.updateMany({ where, data })).count;
  }
  res.json({ ok: true, count });
}));

const findTask = (req) => {
  const id = intId(req.params.id);
  return id && prisma.task.findFirst({ where: { id, userId: req.user.id } });
};

router.get('/tasks/:id', h(async (req, res) => {
  const id = intId(req.params.id);
  const task = id && await prisma.task.findFirst({
    where: { id, userId: req.user.id }, include: { subtasks: { orderBy: { createdAt: 'asc' } } },
  });
  if (!task) return notFound(res, 'Task not found.');
  res.json({ task: taskJson(task, tzOf(req)) });
}));

router.patch('/tasks/:id', h(async (req, res) => {
  const existing = await findTask(req);
  if (!existing) return notFound(res, 'Task not found.');
  const data = taskData(req.body || {});
  if (data.title !== undefined && !data.title) return bad(res, 'Title is required.');
  const becameDone = data.status === 'done' && existing.status !== 'done';
  if (data.status && data.status !== 'done') data.completedAt = null;
  if (becameDone) data.completedAt = new Date();
  const updated = await prisma.task.update({ where: { id: existing.id }, data });
  if (becameDone) await tasksLib.createNextOccurrence(updated);
  res.json({ task: taskJson(updated, tzOf(req)) });
}));

router.delete('/tasks/:id', h(async (req, res) => {
  const task = await findTask(req);
  if (task) await prisma.task.delete({ where: { id: task.id } });
  res.json({ ok: true });
}));

router.post('/tasks/:id/complete', h(async (req, res) => {
  const task = await findTask(req);
  if (!task) return notFound(res, 'Task not found.');
  if (task.status !== 'done') await tasksLib.completeTask(task);
  res.json({ ok: true });
}));

router.post('/tasks/:id/restore', h(async (req, res) => {
  const task = await findTask(req);
  if (!task) return notFound(res, 'Task not found.');
  await prisma.task.update({ where: { id: task.id }, data: { status: 'inbox', completedAt: null } });
  res.json({ ok: true });
}));

router.post('/tasks/:id/subtasks', h(async (req, res) => {
  const parent = await findTask(req);
  if (!parent) return notFound(res, 'Task not found.');
  const title = String(req.body?.title || '').trim();
  if (!title) return bad(res, 'Title is required.');
  await prisma.task.create({ data: { userId: req.user.id, title, parentId: parent.id, status: 'inbox' } });
  res.status(201).json({ ok: true });
}));

router.post('/tasks/:id/subtasks/:sid/toggle', h(async (req, res) => {
  const sub = await prisma.task.findFirst({ where: { id: intId(req.params.sid) || 0, parentId: intId(req.params.id) || 0, userId: req.user.id } });
  if (!sub) return notFound(res, 'Subtask not found.');
  const done = sub.status === 'done';
  await prisma.task.update({ where: { id: sub.id }, data: { status: done ? 'inbox' : 'done', completedAt: done ? null : new Date() } });
  res.json({ done: !done });
}));

router.delete('/tasks/:id/subtasks/:sid', h(async (req, res) => {
  await prisma.task.deleteMany({ where: { id: intId(req.params.sid) || 0, parentId: intId(req.params.id) || 0, userId: req.user.id } });
  res.json({ ok: true });
}));

// ── Reminders ───────────────────────────────────────────────────────────────

router.get('/reminders', h(async (req, res) => {
  const tz = tzOf(req);
  const uid = req.user.id;
  const view = ['upcoming', 'today', 'overdue', 'completed'].includes(req.query.view) ? req.query.view : 'upcoming';
  const tagFilter = req.query.tag ? { tags: { has: String(req.query.tag) } } : {};
  const t = todayStr(tz);
  const start = new Date(t + 'T00:00:00.000Z');
  const end = new Date(t + 'T23:59:59.999Z');
  const overdueWhere = {
    userId: uid, completed: false, ...tagFilter,
    OR: [{ dueDate: { lt: start } }, { dueDate: { gte: start, lte: end }, dueTime: { lt: nowHHMM(tz), not: null } }],
  };
  const whereMap = {
    upcoming:  { userId: uid, completed: false, dueDate: { gte: start }, ...tagFilter },
    today:     { userId: uid, completed: false, dueDate: { gte: start, lte: end }, ...tagFilter },
    overdue:   overdueWhere,
    completed: { userId: uid, completed: true, ...tagFilter },
  };
  const order = view === 'completed' ? [{ completedAt: 'desc' }] : [{ dueDate: 'asc' }, { dueTime: 'asc' }];
  const [reminders, overdue, today, tagRows] = await Promise.all([
    prisma.reminder.findMany({ where: whereMap[view], orderBy: order, take: view === 'completed' ? 200 : undefined }),
    prisma.reminder.count({ where: overdueWhere }),
    prisma.reminder.count({ where: { userId: uid, completed: false, dueDate: { gte: start, lte: end } } }),
    prisma.reminder.findMany({ where: { userId: uid }, select: { tags: true } }),
  ]);
  res.json({
    view, reminders: reminders.map((r) => reminderJson(r, tz)),
    tags: [...new Set(tagRows.flatMap((r) => r.tags))].sort(),
    counts: { overdue, today },
  });
}));

function reminderData(body, tz) {
  const title = String(body.title || '').trim();
  if (!title) return { error: 'Title is required.' };
  if (!isYmd(body.dueDate) || !isHHMM(body.dueTime)) return { error: 'Due date and time are required.' };
  const offset = parseInt(body.reminderOffset, 10) || 0;
  return {
    data: {
      title, notes: String(body.notes || ''),
      dueDate: new Date(body.dueDate), dueTime: body.dueTime,
      reminderAt: remindersLib.buildReminderAt(body.dueDate, body.dueTime, offset, tz),
      priority: PRIORITIES.includes(body.priority) ? body.priority : 'none',
      tags: tagsFrom(body.tags),
      recurring: !!body.recurring,
      recurRule: body.recurring ? (String(body.recurRule || '') || 'daily') : null,
    },
  };
}

// Several reminders at once, same actions as the web's bulk bar (Mark complete, Delete). Only the
// caller's own reminders are touched; the answer says how many were.
const REMINDER_BULK_ACTIONS = ['complete', 'delete'];
router.post('/reminders/bulk', h(async (req, res) => {
  const { action } = req.body || {};
  if (!REMINDER_BULK_ACTIONS.includes(action)) return bad(res, 'Unknown action.');
  const ids = (Array.isArray(req.body.ids) ? req.body.ids : []).map(Number).filter((n) => Number.isInteger(n) && n > 0);
  if (!ids.length) return bad(res, 'Pick at least one reminder.');
  if (ids.length > 500) return bad(res, 'Too many reminders at once.');
  const where = { id: { in: ids }, userId: req.user.id };
  let count = 0;
  if (action === 'complete') {
    const reminders = await prisma.reminder.findMany({ where: { ...where, completed: false } });
    for (const r of reminders) await remindersLib.completeReminder(r, tzOf(req));
    count = reminders.length;
  } else {
    count = (await prisma.reminder.deleteMany({ where })).count;
  }
  res.json({ ok: true, count });
}));

router.post('/reminders', h(async (req, res) => {
  const { data, error } = reminderData(req.body || {}, tzOf(req));
  if (error) return bad(res, error);
  const r = await prisma.reminder.create({ data: { ...data, userId: req.user.id } });
  res.status(201).json({ reminder: reminderJson(r, tzOf(req)) });
}));

const findReminder = (req) => {
  const id = intId(req.params.id);
  return id && prisma.reminder.findFirst({ where: { id, userId: req.user.id } });
};

router.get('/reminders/:id', h(async (req, res) => {
  const r = await findReminder(req);
  if (!r) return notFound(res, 'Reminder not found.');
  const offset = r.reminderAt && r.dueDate && r.dueTime
    ? Math.round((remindersLib.buildReminderAt(ymd(r.dueDate), r.dueTime, 0, tzOf(req)) - r.reminderAt) / 60000)
    : 0;
  res.json({ reminder: { ...reminderJson(r, tzOf(req)), reminderOffset: Math.max(0, offset) } });
}));

router.put('/reminders/:id', h(async (req, res) => {
  const existing = await findReminder(req);
  if (!existing) return notFound(res, 'Reminder not found.');
  const { data, error } = reminderData(req.body || {}, tzOf(req));
  if (error) return bad(res, error);
  const r = await prisma.reminder.update({ where: { id: existing.id }, data });
  res.json({ reminder: reminderJson(r, tzOf(req)) });
}));

router.delete('/reminders/:id', h(async (req, res) => {
  const r = await findReminder(req);
  if (r) await prisma.reminder.delete({ where: { id: r.id } });
  res.json({ ok: true });
}));

router.post('/reminders/:id/complete', h(async (req, res) => {
  const r = await findReminder(req);
  if (!r) return notFound(res, 'Reminder not found.');
  if (!r.completed) await remindersLib.completeReminder(r, tzOf(req));
  res.json({ ok: true });
}));

router.post('/reminders/:id/restore', h(async (req, res) => {
  const r = await findReminder(req);
  if (!r) return notFound(res, 'Reminder not found.');
  await prisma.reminder.update({ where: { id: r.id }, data: { completed: false, completedAt: null } });
  res.json({ ok: true });
}));

router.post('/reminders/:id/snooze', h(async (req, res) => {
  const r = await findReminder(req);
  if (!r) return notFound(res, 'Reminder not found.');
  const tz = tzOf(req);
  const now = new Date();
  const base = r.reminderAt && r.reminderAt > now ? new Date(r.reminderAt) : now;
  const duration = req.body?.duration;
  let data;
  if (duration === '15min') data = { reminderAt: new Date(base.getTime() + 15 * 60000) };
  else if (duration === '1hour') data = { reminderAt: new Date(base.getTime() + 60 * 60000) };
  else if (duration === 'tomorrow') {
    const tomorrow = new Date(todayStr(tz) + 'T00:00:00.000Z');
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    const dueTime = r.dueTime || '09:00';
    data = { dueDate: tomorrow, dueTime, reminderAt: remindersLib.buildReminderAt(ymd(tomorrow), dueTime, 0, tz) };
  } else return bad(res, 'Unknown snooze duration');
  const updated = await prisma.reminder.update({ where: { id: r.id }, data });
  res.json({ reminder: reminderJson(updated, tz) });
}));

// ── Routines ────────────────────────────────────────────────────────────────

const FREQUENCIES = ['daily', 'weekdays', 'weekends', 'weekly', 'custom'];

router.get('/routines', h(async (req, res) => {
  const uid = req.user.id;
  const view = req.query.view === 'archived' ? 'archived' : 'today';
  const tag = req.query.tag ? { tags: { has: String(req.query.tag) } } : {};
  const today = routinesLib.todayDate(req);
  const localToday = routinesLib.localDateStr(req);
  const [routines, completions, tagRows] = await Promise.all([
    prisma.routine.findMany({
      where: { userId: uid, active: view !== 'archived', ...tag },
      orderBy: view === 'archived' ? { createdAt: 'desc' } : [{ timeOfDay: 'asc' }, { title: 'asc' }],
      include: { _count: { select: { completions: true } } },
    }),
    prisma.routineCompletion.findMany({ where: { userId: uid, completedDate: today } }),
    prisma.routine.findMany({ where: { userId: uid }, select: { tags: true } }),
  ]);
  const doneIds = new Set(completions.map((c) => c.routineId));
  res.json({
    view,
    routines: routines.map((r) => routineJson(r, {
      completedToday: doneIds.has(r.id), dueToday: routinesLib.isDueToday(r, localToday),
      finishedChallenge: !!(r.durationDays && r._count.completions >= r.durationDays),
    })),
    tags: [...new Set(tagRows.flatMap((r) => r.tags))].sort(),
  });
}));

function routineData(body) {
  const title = String(body.title || '').trim();
  if (!title) return { error: 'Title is required.' };
  const days = (Array.isArray(body.scheduleDays) ? body.scheduleDays : []).filter((d) => DAYS.includes(d));
  return {
    data: {
      title, description: String(body.description || ''),
      timeOfDay: routinesLib.TIME_OF_DAY.includes(body.timeOfDay) ? body.timeOfDay : 'anytime',
      specificTime: isHHMM(body.specificTime) ? body.specificTime : null,
      frequency: FREQUENCIES.includes(body.frequency) ? body.frequency : 'daily',
      scheduleDays: days, tags: tagsFrom(body.tags),
      durationDays: parseInt(body.durationDays, 10) > 0 ? parseInt(body.durationDays, 10) : null,
      startDate: isYmd(body.startDate) ? new Date(body.startDate + 'T00:00:00.000Z') : null,
      notify: !!body.notify,
    },
  };
}

// Several routines at once, same actions as the web's bulk bar (Archive, Restore, Delete). Only the
// caller's own routines are touched; deleting a routine deletes its history with it. The answer says
// how many were changed.
const ROUTINE_BULK_ACTIONS = ['archive', 'restore', 'delete'];
router.post('/routines/bulk', h(async (req, res) => {
  const { action } = req.body || {};
  if (!ROUTINE_BULK_ACTIONS.includes(action)) return bad(res, 'Unknown action.');
  const ids = (Array.isArray(req.body.ids) ? req.body.ids : []).map(Number).filter((n) => Number.isInteger(n) && n > 0);
  if (!ids.length) return bad(res, 'Pick at least one routine.');
  if (ids.length > 500) return bad(res, 'Too many routines at once.');
  const where = { id: { in: ids }, userId: req.user.id };
  const result = action === 'delete'
    ? await prisma.routine.deleteMany({ where })
    : await prisma.routine.updateMany({ where: { ...where, active: action === 'restore' ? false : true }, data: { active: action === 'restore' } });
  res.json({ ok: true, count: result.count });
}));

router.post('/routines', h(async (req, res) => {
  const { data, error } = routineData(req.body || {});
  if (error) return bad(res, error);
  const r = await prisma.routine.create({ data: { ...data, userId: req.user.id } });
  res.status(201).json({ routine: routineJson(r) });
}));

const findRoutine = (req) => {
  const id = intId(req.params.id);
  return id && prisma.routine.findFirst({ where: { id, userId: req.user.id } });
};

router.get('/routines/:id', h(async (req, res) => {
  const routine = await findRoutine(req);
  if (!routine) return notFound(res, 'Routine not found.');
  const localToday = routinesLib.localDateStr(req);
  const completions = await prisma.routineCompletion.findMany({ where: { routineId: routine.id }, orderBy: { completedDate: 'desc' } });
  const todayYmd = ymd(routinesLib.todayDate(req));
  res.json({
    routine: routineJson(routine, {
      completionCount: completions.length,
      completedToday: completions.some((c) => ymd(c.completedDate) === todayYmd),
      dueToday: routinesLib.isDueToday(routine, localToday),
    }),
    heatmap: routinesLib.buildHeatmapData(completions, routine, localToday),
    weeklyStats: routinesLib.buildWeeklyStats(completions, routine, localToday),
  });
}));

router.put('/routines/:id', h(async (req, res) => {
  const existing = await findRoutine(req);
  if (!existing) return notFound(res, 'Routine not found.');
  const { data, error } = routineData(req.body || {});
  if (error) return bad(res, error);
  const r = await prisma.routine.update({ where: { id: existing.id }, data });
  await recalcStreak({ ...existing, frequency: data.frequency, scheduleDays: data.scheduleDays }, routinesLib.localDateStr(req));
  res.json({ routine: routineJson(r) });
}));

router.delete('/routines/:id', h(async (req, res) => {
  const r = await findRoutine(req);
  if (r) {
    await prisma.routineCompletion.deleteMany({ where: { routineId: r.id } });
    await prisma.routine.delete({ where: { id: r.id } });
  }
  res.json({ ok: true });
}));

router.post('/routines/:id/archive', h(async (req, res) => {
  const r = await findRoutine(req);
  if (!r) return notFound(res, 'Routine not found.');
  await prisma.routine.update({ where: { id: r.id }, data: { active: !r.active } });
  res.json({ active: !r.active });
}));

// Toggle today's completion (same rules as POST /routines/:id/complete on the web)
router.post('/routines/:id/complete', h(async (req, res) => {
  const routine = await findRoutine(req);
  if (!routine) return notFound(res, 'Routine not found.');
  const today = routinesLib.todayDate(req);
  const localToday = routinesLib.localDateStr(req);
  const existing = await prisma.routineCompletion.findFirst({ where: { routineId: routine.id, userId: req.user.id, completedDate: today } });
  let completedToday;
  if (existing) {
    await prisma.routineCompletion.delete({ where: { id: existing.id } });
    completedToday = false;
  } else {
    if (!routinesLib.isDueToday(routine, localToday)) return res.status(409).json({ error: 'This routine isn’t scheduled today.' });
    await prisma.routineCompletion.create({ data: { routineId: routine.id, userId: req.user.id, completedDate: today, completedAt: new Date() } });
    completedToday = true;
    if (routine.active && routine.durationDays) {
      const count = await prisma.routineCompletion.count({ where: { routineId: routine.id } });
      if (count === routine.durationDays) await prisma.routine.update({ where: { id: routine.id }, data: { active: false } });
    }
  }
  await recalcStreak(routine, localToday);
  const [refreshed, completionCount] = await Promise.all([
    prisma.routine.findUnique({ where: { id: routine.id } }),
    prisma.routineCompletion.count({ where: { routineId: routine.id } }),
  ]);
  res.json({ routine: routineJson(refreshed, { completedToday, completionCount, dueToday: routinesLib.isDueToday(refreshed, localToday) }) });
}));

// ── Notes ───────────────────────────────────────────────────────────────────

const NOTE_TYPES = ['note', 'journal', 'quote'];

router.get('/notes', h(async (req, res) => {
  const { type, tag, search } = req.query;
  const slipCut = noteSlipCutoff();
  const where = { userId: req.user.id };
  if (type === 'slipping') where.updatedAt = { lt: slipCut };
  else if (type === 'flagged') where.flaggedForReview = true;
  else if (NOTE_TYPES.includes(type)) where.type = type;
  if (tag) where.tags = { has: String(tag) };
  if (search) {
    const q = String(search);
    where.OR = [{ title: { contains: q, mode: 'insensitive' } }, { content: { contains: q, mode: 'insensitive' } }];
  }
  const [notes, tags, slippingCount] = await Promise.all([
    prisma.note.findMany({
      where, orderBy: type === 'slipping' ? [{ updatedAt: 'asc' }] : [{ pinned: 'desc' }, { updatedAt: 'desc' }],
      select: {
        id: true, type: true, title: true, content: true, tags: true, pinned: true, flaggedForReview: true,
        locked: true, hasDrawing: true, private: true, folderId: true, createdAt: true, updatedAt: true,
      },
    }),
    getAllUserTags(req.user.id),
    prisma.note.count({ where: { userId: req.user.id, updatedAt: { lt: slipCut } } }),
  ]);
  res.json({ notes: notes.map(noteSummaryJson), tags, slippingCount });
}));

// A drawing must be the web canvas's JSON (so both can open it); returns the string or null
function validDrawing(raw) {
  if (typeof raw !== 'string' || !raw.trim() || raw.length > 4 * 1024 * 1024) return null;
  try {
    const d = JSON.parse(raw);
    if (!d || !Array.isArray(d.strokes) || d.strokes.length === 0 || d.strokes.length > 500) return null;
    if (!(Number(d.w) > 0) || !(Number(d.h) > 0)) return null;
    const ok = d.strokes.every((s) => s && typeof s.color === 'string' && Number(s.width) > 0 && Array.isArray(s.points)
      && s.points.every((p) => p && Number.isFinite(p.x) && Number.isFinite(p.y)));
    return ok ? raw.trim() : null;
  } catch { return null; }
}

function noteData(body) {
  const title = String(body.title || '').trim();
  if (!title) return { error: 'Title is required.' };
  const flagged = !!body.flaggedForReview;
  // Same rule as the web form: noteMode "draw" with a drawing makes a handwritten note
  let drawing = { hasDrawing: false, drawingData: null };
  if (body.noteMode === 'draw') {
    const drawingData = validDrawing(body.drawingData);
    if (!drawingData) return { error: 'Draw something first.' };
    drawing = { hasDrawing: true, drawingData };
  }
  return {
    drawing,
    data: {
      type: NOTE_TYPES.includes(body.type) ? body.type : 'note',
      title,
      source: String(body.source || '').trim() || null,
      author: String(body.author || '').trim() || null,
      tags: tagsFrom(body.tags),
      pinned: !!body.pinned, private: !!body.private,
      flaggedForReview: flagged,
      reviewDate: flagged && isYmd(body.reviewDate) ? new Date(body.reviewDate) : null,
    },
    content: String(body.content || ''),
  };
}

const findNote = (req, include) => {
  const id = intId(req.params.id);
  return id && prisma.note.findFirst({ where: { id, userId: req.user.id }, include });
};
const NOTE_INCLUDE = {
  attachments: { orderBy: { createdAt: 'asc' } },
  thoughts: { orderBy: { createdAt: 'asc' }, include: { user: { select: { displayName: true } } } },
};

router.post('/notes', h(async (req, res) => {
  const { data, content, drawing, error } = noteData(req.body || {});
  if (error) return bad(res, error);
  const folderId = await folders.ownFolderId(req.body?.folderId, req.user.id);
  if (folderId === undefined) return bad(res, 'Unknown folder.');
  const note = await prisma.note.create({
    data: { ...data, ...drawing, content: drawing.hasDrawing ? null : content, userId: req.user.id, folderId },
  });
  res.status(201).json({ note: noteJson(note) });
}));

router.get('/notes/:id', h(async (req, res) => {
  const note = await findNote(req, NOTE_INCLUDE);
  if (!note) return notFound(res, 'Note not found.');
  if (note.locked && req.session.unlockedNotes?.[note.id]) {
    try { return res.json({ note: noteJson(note, decryptNote(note.lockedContent, req.user.id, note.lockSalt)) }); } catch { /* fall through: stays locked */ }
  }
  res.json({ note: noteJson(note) });
}));

router.put('/notes/:id', h(async (req, res) => {
  const existing = await findNote(req);
  if (!existing) return notFound(res, 'Note not found.');
  if (existing.locked && !req.session.unlockedNotes?.[existing.id]) return res.status(423).json({ error: 'Unlock this note first.' });
  const { data, content, drawing, error } = noteData(req.body || {});
  if (error) return bad(res, error);
  if (existing.locked && drawing.hasDrawing) return res.status(409).json({ error: "Locked notes can't be handwritten." });
  const contentData = existing.locked
    ? { lockedContent: encryptNote(content, req.user.id, existing.lockSalt), content: null }
    : { ...drawing, content: drawing.hasDrawing ? null : content };
  // The folder is changed only when the body sends one, so older clients leave it alone
  let folderData = {};
  if (req.body && 'folderId' in req.body) {
    const folderId = await folders.ownFolderId(req.body.folderId, req.user.id);
    if (folderId === undefined) return bad(res, 'Unknown folder.');
    folderData = { folderId };
  }
  const note = await prisma.note.update({ where: { id: existing.id }, data: { ...data, ...contentData, ...folderData }, include: NOTE_INCLUDE });
  res.json({ note: noteJson(note, existing.locked ? content : undefined) });
}));

router.delete('/notes/:id', h(async (req, res) => {
  const note = await findNote(req);
  if (note) {
    await uploads.remove(uploads.noteDir(note.id));
    await prisma.note.delete({ where: { id: note.id } });
  }
  res.json({ ok: true });
}));

// Moves a note to a folder, or to the top level with folderId null
router.post('/notes/:id/move', h(async (req, res) => {
  const note = await findNote(req);
  if (!note) return notFound(res, 'Note not found.');
  const folderId = await folders.ownFolderId(req.body?.folderId, req.user.id);
  if (folderId === undefined) return bad(res, 'Unknown folder.');
  await prisma.note.update({ where: { id: note.id }, data: { folderId } });
  res.json({ ok: true, folderId });
}));

// ── Note templates ──────────────────────────────────────────────────────────
// The person's own list (lib/userTemplates.js): the starters until they change something. A note is
// started from a template by sending its type, title and text to POST /notes.

const userTemplates = require('../lib/userTemplates');
const templateJson = (user, prefs, id) => userTemplates.findFor({ ...user, preferences: prefs }, id);

router.get('/note-templates', h(async (req, res) => {
  res.json({ templates: userTemplates.forUser(req.user) });
}));

router.post('/note-templates', h(async (req, res) => {
  const r = await userTemplates.mutate(req.user.id, (prefs) => userTemplates.withCreated(prefs, req.body));
  if (r.error) return bad(res, r.error);
  res.json({ template: templateJson(req.user, r.prefs, r.template.id) });
}));

router.patch('/note-templates/:id', h(async (req, res) => {
  const r = await userTemplates.mutate(req.user.id, (prefs) => userTemplates.withUpdated(prefs, String(req.params.id), req.body));
  if (r.notFound) return notFound(res, 'Template not found.');
  if (r.error) return bad(res, r.error);
  res.json({ template: templateJson(req.user, r.prefs, r.template.id) });
}));

router.delete('/note-templates/:id', h(async (req, res) => {
  const r = await userTemplates.mutate(req.user.id, (prefs) => userTemplates.withRemoved(prefs, String(req.params.id)));
  if (r.notFound) return notFound(res, 'Template not found.');
  res.json({ ok: true });
}));

// ── Note folders ────────────────────────────────────────────────────────────

// Every folder with its full path ("Work / Projects"); the app builds the tree from parentId
router.get('/folders', h(async (req, res) => {
  const list = await prisma.folder.findMany({ where: { userId: req.user.id }, orderBy: { name: 'asc' } });
  folders.folderPaths(list);
  res.json({ folders: list.map((f) => ({ id: f.id, name: f.name, parentId: f.parentId, path: f.path })) });
}));

router.post('/folders', h(async (req, res) => {
  const name = String(req.body?.name || '').trim().slice(0, 80);
  if (!name) return bad(res, 'Name is required.');
  const parentId = await folders.ownFolderId(req.body?.parentId, req.user.id);
  if (parentId === undefined) return bad(res, 'Unknown folder.');
  const f = await prisma.folder.create({ data: { userId: req.user.id, name, parentId } });
  res.status(201).json({ folder: { id: f.id, name: f.name, parentId: f.parentId } });
}));

router.patch('/folders/:id', h(async (req, res) => {
  const id = intId(req.params.id);
  const folder = id && await prisma.folder.findFirst({ where: { id, userId: req.user.id } });
  if (!folder) return notFound(res, 'Folder not found.');
  const name = String(req.body?.name || '').trim().slice(0, 80);
  if (!name) return bad(res, 'Name is required.');
  const f = await prisma.folder.update({ where: { id: folder.id }, data: { name } });
  res.json({ folder: { id: f.id, name: f.name, parentId: f.parentId } });
}));

// Notes and subfolders move up one level; nothing is deleted
router.delete('/folders/:id', h(async (req, res) => {
  const id = intId(req.params.id);
  const folder = id && await prisma.folder.findFirst({ where: { id, userId: req.user.id } });
  if (!folder) return notFound(res, 'Folder not found.');
  await folders.deleteFolderKeepContents(folder, req.user.id);
  res.json({ ok: true });
}));

router.post('/notes/:id/pin', h(async (req, res) => {
  const note = await findNote(req);
  if (!note) return notFound(res, 'Note not found.');
  const u = await prisma.note.update({ where: { id: note.id }, data: { pinned: !note.pinned } });
  res.json({ pinned: u.pinned });
}));

router.post('/notes/:id/flag', h(async (req, res) => {
  const note = await findNote(req);
  if (!note) return notFound(res, 'Note not found.');
  const u = await prisma.note.update({ where: { id: note.id }, data: { flaggedForReview: !note.flaggedForReview } });
  res.json({ flaggedForReview: u.flaggedForReview });
}));

router.post('/notes/:id/unlock', pinLimiter, h(async (req, res) => {
  const note = await findNote(req, NOTE_INCLUDE);
  if (!note) return notFound(res, 'Note not found.');
  if (!note.locked) return res.json({ note: noteJson(note) });
  const user = await prisma.user.findUnique({ where: { id: req.user.id }, select: { preferences: true } });
  const pinHash = user.preferences?.noteLockPin;
  if (!pinHash || !await bcrypt.compare(String(req.body?.pin || ''), pinHash)) return res.status(403).json({ error: 'Incorrect PIN.' });
  let content;
  try { content = decryptNote(note.lockedContent, req.user.id, note.lockSalt); } catch {
    return res.status(500).json({ error: 'Failed to decrypt — the note data may be corrupted.' });
  }
  req.session.unlockedNotes = { ...(req.session.unlockedNotes || {}), [note.id]: true };
  res.json({ note: noteJson(note, content) });
}));

router.post('/notes/:id/lock', h(async (req, res) => {
  const note = await findNote(req);
  if (!note) return notFound(res, 'Note not found.');
  // The web doesn't offer locking for handwritten notes either: only text is encrypted
  if (note.hasDrawing) return res.status(409).json({ error: "Handwritten notes can't be locked." });
  if (!note.locked) {
    const salt = crypto.randomBytes(16).toString('hex');
    await prisma.note.update({
      where: { id: note.id },
      data: { locked: true, lockedContent: encryptNote(note.content || '', req.user.id, salt), lockSalt: salt, content: null },
    });
    if (req.session.unlockedNotes) delete req.session.unlockedNotes[note.id];
  }
  res.json({ ok: true });
}));

// Photo / file attachments (multipart, field "photo"), same limits as the web: images, PDF or
// plain text, up to 20 MB
const addAttachment = h(async (req, res) => {
  const note = await findNote(req);
  if (!note) return notFound(res, 'Note not found.');
  if (!req.file) return bad(res, 'Choose an image, PDF or text file.');
  const a = await saveAttachment(note.id, req.file);
  res.status(201).json({
    attachment: { id: a.id, mimeType: a.mimeType, url: `/notes/${note.id}/attachments/${encodeURIComponent(a.filePath)}` },
  });
});

router.post('/notes/:id/attachments', (req, res) => {
  noteUpload.single('photo')(req, res, (err) => {
    if (err) {
      const tooBig = err.code === 'LIMIT_FILE_SIZE';
      return res.status(tooBig ? 413 : 400).json({ error: tooBig ? 'That file is over the 20 MB limit.' : 'Upload failed.' });
    }
    addAttachment(req, res);
  });
});

router.delete('/notes/:id/attachments/:aid', h(async (req, res) => {
  const note = await findNote(req);
  if (!note) return notFound(res, 'Note not found.');
  await removeAttachment(note.id, intId(req.params.aid) || 0);
  res.json({ ok: true });
}));

router.post('/notes/:id/thoughts', h(async (req, res) => {
  const note = await findNote(req);
  if (!note) return notFound(res, 'Note not found.');
  const content = String(req.body?.content || '').trim();
  if (!content) return bad(res, 'Write something first.');
  const t = await prisma.noteThought.create({
    data: { noteId: note.id, userId: req.user.id, content }, include: { user: { select: { displayName: true } } },
  });
  res.status(201).json({ thought: { id: t.id, content: t.content, createdAt: t.createdAt, author: t.user.displayName } });
}));

router.delete('/notes/:id/thoughts/:tid', h(async (req, res) => {
  await prisma.noteThought.deleteMany({ where: { id: intId(req.params.tid) || 0, userId: req.user.id } });
  res.json({ ok: true });
}));

// People you can share a list (or anything else) with: everyone but you
router.get('/users/shareable', h(async (req, res) => {
  res.json({ users: await getShareableUsers(req.user.id) });
}));

// ── Lists ───────────────────────────────────────────────────────────────────

const accessibleList = (listId, userId) => (Number.isInteger(listId)
  ? prisma.list.findFirst({ where: { id: listId, OR: [{ userId }, { shares: { some: { userId } } }] } })
  : null);

const listSummary = (l, userId) => ({
  id: l.id, title: l.title, createdAt: l.createdAt, isOwner: l.userId === userId,
  owner: l.user ? l.user.displayName : null,
  itemCount: l._count?.items ?? 0, openCount: l.items?.length ?? 0,
});

router.get('/lists', h(async (req, res) => {
  const uid = req.user.id;
  const inc = { _count: { select: { items: true } }, items: { where: { checked: false }, select: { id: true } } };
  const [lists, shares] = await Promise.all([
    prisma.list.findMany({ where: { userId: uid }, orderBy: { createdAt: 'desc' }, include: inc }),
    prisma.listShare.findMany({
      where: { userId: uid }, orderBy: { createdAt: 'desc' },
      include: { list: { include: { ...inc, user: { select: { displayName: true } } } } },
    }),
  ]);
  res.json({ lists: lists.map((l) => listSummary(l, uid)), shared: shares.map((s) => listSummary(s.list, uid)) });
}));

router.post('/lists', h(async (req, res) => {
  const title = String(req.body?.title || '').trim();
  if (!title) return bad(res, 'Title is required.');
  const list = await prisma.list.create({ data: { userId: req.user.id, title } });
  res.status(201).json({ list: listSummary(list, req.user.id) });
}));

router.get('/lists/:id', h(async (req, res) => {
  const id = intId(req.params.id);
  const uid = req.user.id;
  const list = id && await prisma.list.findFirst({
    where: { id, OR: [{ userId: uid }, { shares: { some: { userId: uid } } }] },
    include: {
      items: { orderBy: { position: 'asc' } },
      shares: { include: { user: { select: { id: true, username: true, displayName: true } } } },
      user: { select: { displayName: true } },
    },
  });
  if (!list) return notFound(res, 'List not found.');
  res.json({
    list: {
      ...listSummary(list, uid),
      items: list.items.map((i) => ({ id: i.id, text: i.text, checked: i.checked, position: i.position })),
      sharedWith: list.shares.map((s) => ({ id: s.user.id, username: s.user.username, displayName: s.user.displayName })),
    },
  });
}));

router.patch('/lists/:id', h(async (req, res) => {
  const title = String(req.body?.title || '').trim();
  if (!title) return bad(res, 'Title is required.');
  const { count } = await prisma.list.updateMany({ where: { id: intId(req.params.id) || 0, userId: req.user.id }, data: { title } });
  if (!count) return notFound(res, 'List not found.');
  res.json({ ok: true, title });
}));

router.delete('/lists/:id', h(async (req, res) => {
  await prisma.list.deleteMany({ where: { id: intId(req.params.id) || 0, userId: req.user.id } });
  res.json({ ok: true });
}));

// Sharing (owner only), same rules as POST /lists/:id/share on the web
router.post('/lists/:id/share', h(async (req, res) => {
  const listId = intId(req.params.id);
  const list = listId && await prisma.list.findFirst({ where: { id: listId, userId: req.user.id } });
  if (!list) return notFound(res, 'List not found.');
  const username = String(req.body?.username || '').trim().replace(/^@/, '');
  if (!username) return bad(res, 'Username is required.');
  const target = await prisma.user.findFirst({ where: { username: { equals: username, mode: 'insensitive' } } });
  if (!target) return notFound(res, `User "${username}" not found`);
  if (target.id === req.user.id) return bad(res, 'Cannot share with yourself');
  await prisma.listShare.upsert({ where: { listId_userId: { listId, userId: target.id } }, create: { listId, userId: target.id }, update: {} });
  res.json({ ok: true });
}));

router.delete('/lists/:id/share/:userId', h(async (req, res) => {
  const listId = intId(req.params.id);
  const list = listId && await prisma.list.findFirst({ where: { id: listId, userId: req.user.id } });
  if (!list) return notFound(res, 'List not found.');
  await prisma.listShare.deleteMany({ where: { listId, userId: intId(req.params.userId) || 0 } });
  res.json({ ok: true });
}));

router.post('/lists/:id/items', h(async (req, res) => {
  const listId = intId(req.params.id);
  const text = String(req.body?.text || '').trim();
  if (!text) return bad(res, 'Text is required.');
  if (!await accessibleList(listId, req.user.id)) return notFound(res, 'List not found.');
  const count = await prisma.listItem.count({ where: { listId } });
  const item = await prisma.listItem.create({ data: { listId, text, position: count } });
  res.status(201).json({ item: { id: item.id, text: item.text, checked: false, position: item.position } });
}));

router.post('/lists/:id/items/reorder', h(async (req, res) => {
  const listId = intId(req.params.id);
  if (!await accessibleList(listId, req.user.id)) return notFound(res, 'List not found.');
  const ids = Array.isArray(req.body?.ids) ? req.body.ids.map(Number).filter(Number.isInteger) : [];
  if (!ids.length) return bad(res, 'ids required');
  await prisma.$transaction(ids.map((id, position) => prisma.listItem.updateMany({ where: { id, listId }, data: { position } })));
  res.json({ ok: true });
}));

router.post('/lists/:id/items/:itemId/toggle', h(async (req, res) => {
  const listId = intId(req.params.id);
  if (!await accessibleList(listId, req.user.id)) return notFound(res, 'List not found.');
  const item = await prisma.listItem.findFirst({ where: { id: intId(req.params.itemId) || 0, listId } });
  if (!item) return notFound(res);
  const u = await prisma.listItem.update({ where: { id: item.id }, data: { checked: !item.checked } });
  res.json({ checked: u.checked });
}));

router.patch('/lists/:id/items/:itemId', h(async (req, res) => {
  const listId = intId(req.params.id);
  const text = String(req.body?.text || '').trim();
  if (!text) return bad(res, 'Text is required.');
  if (!await accessibleList(listId, req.user.id)) return notFound(res, 'List not found.');
  const { count } = await prisma.listItem.updateMany({ where: { id: intId(req.params.itemId) || 0, listId }, data: { text } });
  if (!count) return notFound(res);
  res.json({ ok: true });
}));

router.delete('/lists/:id/items/:itemId', h(async (req, res) => {
  const listId = intId(req.params.id);
  if (!await accessibleList(listId, req.user.id)) return notFound(res, 'List not found.');
  await prisma.listItem.deleteMany({ where: { id: intId(req.params.itemId) || 0, listId } });
  res.json({ ok: true });
}));

// ── Bookmarks ───────────────────────────────────────────────────────────────

router.get('/bookmarks', h(async (req, res) => {
  const where = { userId: req.user.id };
  if (req.query.tag) where.tags = { has: String(req.query.tag) };
  if (req.query.search) {
    const q = String(req.query.search);
    where.OR = ['title', 'url', 'description'].map((f) => ({ [f]: { contains: q, mode: 'insensitive' } }));
  }
  const [bookmarks, all] = await Promise.all([
    prisma.bookmark.findMany({ where, orderBy: { createdAt: 'desc' } }),
    prisma.bookmark.findMany({ where: { userId: req.user.id }, select: { tags: true } }),
  ]);
  res.json({ bookmarks: bookmarks.map(bookmarkJson), tags: [...new Set(all.flatMap((b) => b.tags))].sort() });
}));

function bookmarkData(body) {
  let url = String(body.url || '').trim();
  if (!url) return { error: 'URL is required.' };
  if (!/^https?:\/\//i.test(url)) url = 'https://' + url;
  return {
    data: {
      url,
      title: String(body.title || '').trim() || null,
      description: String(body.description || '').trim() || null,
      tags: tagsFrom(body.tags),
    },
  };
}

router.post('/bookmarks', h(async (req, res) => {
  const { data, error } = bookmarkData(req.body || {});
  if (error) return bad(res, error);
  const b = await prisma.bookmark.create({ data: { ...data, userId: req.user.id } });
  res.status(201).json({ bookmark: bookmarkJson(b) });
}));

router.put('/bookmarks/:id', h(async (req, res) => {
  const { data, error } = bookmarkData(req.body || {});
  if (error) return bad(res, error);
  const { count } = await prisma.bookmark.updateMany({ where: { id: intId(req.params.id) || 0, userId: req.user.id }, data });
  if (!count) return notFound(res, 'Bookmark not found.');
  res.json({ ok: true });
}));

// Several bookmarks at once, as the web's "Delete selected". Only the caller's own are touched.
router.post('/bookmarks/bulk-delete', h(async (req, res) => {
  const ids = (Array.isArray(req.body?.ids) ? req.body.ids : []).map(Number).filter((n) => Number.isInteger(n) && n > 0);
  if (!ids.length) return bad(res, 'Pick at least one bookmark.');
  if (ids.length > 500) return bad(res, 'Too many bookmarks at once.');
  const { count } = await prisma.bookmark.deleteMany({ where: { id: { in: ids }, userId: req.user.id } });
  res.json({ ok: true, count });
}));

// Send a copy of one of your bookmarks to another user (the web's Share ▸ Send to Obelo user)
router.post('/bookmarks/:id/share-to-user', h(async (req, res) => {
  const r = await shareBookmarkToUser(req.user.id, intId(req.params.id) || 0, req.body?.username);
  res.status(r.status).json(r.body);
}));

router.delete('/bookmarks/:id', h(async (req, res) => {
  await prisma.bookmark.deleteMany({ where: { id: intId(req.params.id) || 0, userId: req.user.id } });
  res.json({ ok: true });
}));

// ── Calendar (read-only) ────────────────────────────────────────────────────

// GET /calendar?from=YYYY-MM-DD&days=N — events on those local days, bucketed by `day`
router.get('/calendar', h(async (req, res) => {
  const tz = tzOf(req);
  const from = isYmd(req.query.from) ? req.query.from : todayStr(tz);
  const days = Math.min(Math.max(parseInt(req.query.days, 10) || 7, 1), 62);
  const toStr = ymd(new Date(new Date(from + 'T00:00:00Z').getTime() + days * 86400000));
  const memberships = await prisma.localCalendarMember.findMany({ where: { userId: req.user.id }, select: { calendarId: true } });
  const owner = memberships.length
    ? { OR: [{ userId: req.user.id }, { localCalendarId: { in: memberships.map((m) => m.calendarId) } }] }
    : { userId: req.user.id };
  const events = await prisma.calendarEvent.findMany({
    where: {
      AND: [owner, {
        OR: [
          { allDay: true, startAt: { lt: new Date(toStr + 'T00:00:00Z') }, endAt: { gt: new Date(from + 'T00:00:00Z') } },
          { allDay: false, startAt: { lt: localMidnightUTC(toStr, tz) }, endAt: { gt: localMidnightUTC(from, tz) } },
        ],
      }],
    },
    include: { source: { select: { name: true, color: true } }, localCalendar: { select: { name: true, color: true } } },
    orderBy: [{ startAt: 'asc' }],
  });
  // The calendars you have connected, for the legend and the "No calendars connected" notice (as on the web page)
  const sources = await prisma.calendarSource.findMany({
    where: { userId: req.user.id, active: true }, orderBy: { name: 'asc' }, select: { name: true, color: true, lastSynced: true },
  });
  res.json({ from, days, today: todayStr(tz), events: events.map((e) => eventJson(e, tz, req.user.id)), sources });
}));

router.get('/calendar/events/:id', h(async (req, res) => {
  const tz = tzOf(req);
  const memberships = await prisma.localCalendarMember.findMany({ where: { userId: req.user.id }, select: { calendarId: true } });
  const e = await prisma.calendarEvent.findFirst({
    where: {
      id: intId(req.params.id) || 0,
      OR: [{ userId: req.user.id }, { localCalendarId: { in: memberships.map((m) => m.calendarId) } }],
    },
    include: { source: { select: { name: true, color: true } }, localCalendar: { select: { name: true, color: true } } },
  });
  if (!e) return notFound(res, 'Event not found.');
  res.json({ event: eventJson(e, tz, req.user.id) });
}));

// ── Analytics ───────────────────────────────────────────────────────────────

// GET /analytics?range=30|90|all — the same numbers as the web Analytics page
router.get('/analytics', h(async (req, res) => {
  const a = await computeAnalytics(req.user.id, req.user.timezone || 'America/New_York', req.query.range);
  // "What stands out" is worded by AI when it's set up, as on the web page
  res.json({ ...a, standsOut: await refineWithAi(a.standsOut), standsOutByAi: aiProvider.isConfigured() });
}));

// ── AI chat ─────────────────────────────────────────────────────────────────
// Same conversation store as the web's /ai (the session), so each signed-in device has its
// own thread. Read-only: the assistant never changes data.

router.get('/ai', (req, res) => {
  res.json({ messages: req.session.aiMessages || [] });
});

router.post('/ai/message', h(async (req, res) => {
  const input = String(req.body?.message || '').trim();
  if (!input) return bad(res, 'Type a message first.');
  const history = [...(req.session.aiMessages || []), { role: 'user', content: input }].slice(-40);
  let result;
  try {
    result = await aiChat.chat(history, req.user.id, req.user);
  } catch (err) {
    // Nothing is saved on failure, so the thread never ends on an unanswered message
    return res.status(err.status || 503).json({ error: err.message });
  }
  req.session.aiMessages = [...history, { role: 'assistant', content: result.reply }];
  await new Promise((resolve) => req.session.save(resolve));
  res.json({ reply: result.reply, remaining: result.remaining });
}));

router.post('/ai/clear', (req, res) => {
  req.session.aiMessages = [];
  req.session.save(() => res.json({ ok: true }));
});

// Calendars you can add events to, as on the web's New Event form
router.get('/calendar/calendars', h(async (req, res) => {
  const { selectable } = await calendarLib.buildSelectableCalendars(req.user.id);
  res.json({
    calendars: selectable.map((c) => ({ value: c.value, label: c.label, color: c.color })),
    defaultTarget: (req.user.preferences || {}).defaultCalendarTarget || 'local',
  });
}));

// ── Calendar accounts and your own calendars (Settings ▸ Calendars in the apps) ──
// The same functions the web's Calendar Sources page uses (src/lib/calendarSources.js). Nothing here
// returns a password or token. A wrong or someone else's id is a plain 404.
const calH = (fn) => h(async (req, res) => {
  try { await fn(req, res); } catch (err) {
    if (err instanceof calSources.SourceError) return res.status(err.status).json({ error: err.message });
    throw err;
  }
});

router.get('/calendar/sources', calH(async (req, res) => {
  const data = await calSources.overview(req.user.id);
  const { selectable } = await calendarLib.buildSelectableCalendars(req.user.id);
  res.json({
    ...data,
    defaultTarget: (req.user.preferences || {}).defaultCalendarTarget || 'local',
    targets: selectable.map((c) => ({ value: c.value, label: c.label, color: c.color })),
    // Connecting a Google account from an app comes in a later version; the app only needs to know it is possible
    googleConfigured: !!(process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET),
  });
}));

router.post('/calendar/sources', calH(async (req, res) => {
  const b = req.body || {};
  const r = await calSources.connectCaldav(req.user.id, {
    name: b.name, provider: b.provider, username: b.username, password: b.password,
    serverUrl: b.serverUrl, calendarHomeUrl: b.calendarHomeUrl, color: b.color,
  });
  res.status(201).json(r);
}));

router.post('/calendar/sources/:id/sync', calH(async (req, res) => {
  res.json(await calSources.syncNow(req.user.id, req.params.id));
}));

router.put('/calendar/sources/:id', calH(async (req, res) => {
  await calSources.setSourceColor(req.user.id, req.params.id, (req.body || {}).color);
  res.json({ ok: true });
}));

router.delete('/calendar/sources/:id', calH(async (req, res) => {
  await calSources.removeSource(req.user.id, req.params.id);
  res.json({ ok: true });
}));

router.put('/calendar/sources/:id/calendars', calH(async (req, res) => {
  res.json(await calSources.setSelectedCalendars(req.user.id, req.params.id, (req.body || {}).urls));
}));

router.put('/calendar/sources/:id/family', calH(async (req, res) => {
  await calSources.setFamilyCalendar(req.user.id, req.params.id, (req.body || {}).url || null);
  res.json({ ok: true });
}));

router.put('/calendar/default', calH(async (req, res) => {
  const target = String((req.body || {}).target || '');
  const { selectable } = await calendarLib.buildSelectableCalendars(req.user.id);
  if (target && !selectable.some((c) => c.value === target)) return res.status(400).json({ error: 'Choose one of your calendars.' });
  await calSources.setDefaultTarget(req.user.id, target || null);
  res.json({ ok: true });
}));

router.post('/calendar/local', calH(async (req, res) => {
  const b = req.body || {};
  res.status(201).json({ id: await calSources.createLocal(req.user.id, { name: b.name, color: b.color }) });
}));

router.put('/calendar/local/:id', calH(async (req, res) => {
  const b = req.body || {};
  await calSources.updateLocal(req.user.id, req.params.id, { name: b.name, color: b.color });
  res.json({ ok: true });
}));

router.delete('/calendar/local/:id', calH(async (req, res) => {
  await calSources.deleteLocal(req.user.id, req.params.id);
  res.json({ ok: true });
}));

router.post('/calendar/local/:id/members', calH(async (req, res) => {
  res.status(201).json(await calSources.addMember(req.user.id, req.params.id, (req.body || {}).username));
}));

router.delete('/calendar/local/:id/members/:userId', calH(async (req, res) => {
  await calSources.removeMember(req.user.id, req.params.id, req.params.userId);
  res.json({ ok: true });
}));

function eventFields(body) {
  const title = String(body.title || '').trim();
  if (!title) return { error: 'Title is required.' };
  if (!isYmd(body.date)) return { error: 'Date is required.' };
  const allDay = !!body.allDay;
  if (!allDay && (!isHHMM(body.startTime) || (body.endTime && !isHHMM(body.endTime)))) return { error: 'Choose a start and end time.' };
  if (!allDay && body.endTime && body.endTime < body.startTime) return { error: 'The event ends before it starts.' };
  return {
    fields: {
      title, eventDate: body.date, allDay,
      startTime: allDay ? null : body.startTime, endTime: allDay ? null : (body.endTime || null),
      location: String(body.location || '').trim() || null,
      description: String(body.description || '').trim() || null,
    },
  };
}

router.post('/calendar/events', h(async (req, res) => {
  const { fields, error } = eventFields(req.body || {});
  if (error) return bad(res, error);
  const target = String(req.body.calendarTarget || 'local');
  const { selectable } = await calendarLib.buildSelectableCalendars(req.user.id);
  const chosen = selectable.find((c) => c.value === target);
  if (!chosen) return bad(res, 'Choose a calendar.');
  try {
    await calendarLib.createEventFor(req.user, { ...fields, calendarTarget: target, calendarName: chosen.label });
  } catch (err) {
    if (err instanceof calendarLib.EventError) return res.status(err.status).json({ error: err.message });
    throw err;
  }
  res.status(201).json({ ok: true });
}));

router.put('/calendar/events/:id', h(async (req, res) => {
  const event = await prisma.calendarEvent.findFirst({ where: { id: intId(req.params.id) || 0, userId: req.user.id, createdInObelo: true } });
  if (!event) return notFound(res, 'Event not found or not editable.');
  const { fields, error } = eventFields(req.body || {});
  if (error) return bad(res, error);
  const tz = tzOf(req);
  const updated = await prisma.calendarEvent.update({
    where: { id: event.id },
    data: {
      title: fields.title, allDay: fields.allDay, location: fields.location, description: fields.description,
      ...calendarLib.eventTimes(fields.eventDate, fields.startTime, fields.endTime, fields.allDay, tz),
    },
    include: { source: { select: { name: true, color: true } }, localCalendar: { select: { name: true, color: true } } },
  });
  res.json({ event: eventJson(updated, tz, req.user.id) });
}));

router.delete('/calendar/events/:id', h(async (req, res) => {
  await prisma.calendarEvent.deleteMany({ where: { id: intId(req.params.id) || 0, userId: req.user.id } });
  res.json({ ok: true });
}));

// ── Capture ─────────────────────────────────────────────────────────────────

router.post('/capture', h(async (req, res) => {
  const raw = String(req.body?.raw || '').trim();
  if (!raw) return bad(res, 'Type something to capture.');
  // `type` is optional: a type the person chose before processing (the Mac app's type row)
  const suggestion = await capture.processCapture(raw, req.user, req.body?.type);
  const draft = await prisma.captureDraft.create({ data: { userId: req.user.id, rawInput: raw, aiSuggestion: suggestion, status: 'pending' } });
  res.json({ draftId: draft.id, suggestion });
}));

router.post('/capture/:id/confirm', h(async (req, res) => {
  const b = req.body || {};
  const edits = {};
  for (const k of ['type', 'title', 'dueDate', 'dueTime', 'priority', 'source', 'author']) if (b[k]) edits[k] = String(b[k]);
  if (b.content !== undefined) edits.content = b.content || null;
  if (b.url !== undefined) edits.url = b.url || null;
  if (b.tags !== undefined) edits.tags = tagsFrom(b.tags);
  if (Array.isArray(b.items)) edits.items = b.items.map((i) => String(i).trim()).filter(Boolean);
  const draftId = intId(req.params.id);
  if (!draftId) return notFound(res, 'Draft not found');
  let confirmed;
  try {
    confirmed = await capture.confirmCapture(draftId, req.user.id, edits);
  } catch (err) {
    if (err.status === 404) return notFound(res, 'Draft not found');
    throw err;
  }
  res.json({ type: confirmed.type, id: confirmed.saved.id });
}));

router.post('/capture/:id/reject', h(async (req, res) => {
  await prisma.captureDraft.updateMany({ where: { id: intId(req.params.id) || 0, userId: req.user.id }, data: { status: 'rejected' } });
  res.json({ ok: true });
}));

// ── Help ────────────────────────────────────────────────────────────────────

// The web's help page content (views/help/index.ejs) for the app to show in its own styling,
// so there's one copy of the help text. Keyboard shortcuts are left out (no keyboard on a phone).
router.get('/help', h(async (req, res) => {
  const page = await new Promise((resolve, reject) =>
    req.app.render('help/index', { ...res.locals, layout: false, title: 'Help' }, (err, html) => (err ? reject(err) : resolve(html))));
  const start = page.indexOf('<div class="space-y-10 help-content">');
  const end = page.indexOf('</div><!-- end help-content -->');
  if (start < 0 || end < 0) throw new Error('Help page layout changed');
  const content = page.slice(page.indexOf('>', start) + 1, end).replace(/<section id="shortcuts">[\s\S]*?<\/section>/, '');
  // Each section is <section id="…"><div class="…card…"><h2>Title</h2>…
  const sections = [...content.matchAll(/<section id="([^"]+)">[\s\S]*?<h2[^>]*>([\s\S]*?)<\/h2>/g)]
    .map((m) => ({ id: m[1], title: m[2].replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').trim() }));
  res.json({ sections, html: content });
}));

// Global search: the web's JSON search endpoint, unchanged
router.use('/search', require('./search'));

router.use((req, res) => notFound(res));

module.exports = router;
