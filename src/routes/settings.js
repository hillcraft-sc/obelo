const express = require('express');
const crypto  = require('crypto');
const bcrypt  = require('bcryptjs');
const multer  = require('multer');
const prisma  = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const { MODULES, SIDEBAR_LAYOUT } = require('../config/modules');
const ai = require('../lib/aiProvider');
const { BUILT_IN_THEMES, VALID_THEME_IDS, NOTE_PAPERS, notePaperChoice } = require('../config/themes');
const emailService = require('../services/emailService');
const { getTagUsageCounts, createTag, renameTag, deleteTag } = require('../lib/tags');
const uploads = require('../lib/uploads');
const userTemplates = require('../lib/userTemplates');
const ntfy = require('../services/ntfyService');
const { recalcStreak } = require('../services/routineStreaks');
const userSessions = require('../lib/userSessions');
const passwords = require('../lib/passwords');
const log = require('../services/logService');

const router = express.Router();

// Held in memory so lib/uploads can encrypt before anything touches disk
const avatarUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    cb(null, file.mimetype.startsWith('image/'));
  },
});

// ── Saving settings (shared with the app API, routes/api.js) ─────────────────

const WIDGET_KEYS = ['focus', 'calendar', 'due_items', 'routines', 'resurfaced', 'review'];

function isValidTimezone(tz) {
  try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); return true; } catch { return false; }
}

// Returns an error message, or null once saved. Fields left undefined are unchanged.
async function saveAccount(user, { displayName, email, timezone, timeFormat }) {
  const data = {};
  if (displayName && displayName.trim()) data.displayName = displayName.trim();
  if (typeof email !== 'undefined' && email !== null) {
    const trimmed = String(email).trim().toLowerCase();
    if (trimmed && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) return 'Invalid email address';
    // Check uniqueness (skip if same user's existing email)
    if (trimmed && trimmed !== (user.email || '')) {
      const existing = await prisma.user.findUnique({ where: { email: trimmed } });
      if (existing) return 'Email already in use';
    }
    data.email = trimmed || null;
  }
  if (timezone && timezone.trim()) {
    // An unknown zone would make every date format throw for this user
    if (!isValidTimezone(timezone.trim())) return 'Unknown timezone';
    data.timezone = timezone.trim();
  }
  if (timeFormat === '12h' || timeFormat === '24h') {
    data.preferences = { ...(user.preferences || {}), timeFormat };
  }
  if (Object.keys(data).length > 0) await prisma.user.update({ where: { id: user.id }, data });
  return null;
}

// enabledKeys: modules to switch on (others off); order: module keys, first to last
async function saveModules(userId, enabledKeys, order) {
  const orderMap = {};
  order.forEach((key, idx) => { orderMap[key] = idx; });
  await Promise.all(MODULES.filter(m => !m.alwaysEnabled).map(m => {
    const enabled  = enabledKeys.includes(m.key);
    const position = orderMap[m.key] != null ? orderMap[m.key] : null;
    return prisma.userModule.upsert({
      where:  { userId_moduleKey: { userId, moduleKey: m.key } },
      update: { enabled, ...(position != null && { position }) },
      create: { userId, moduleKey: m.key, enabled, position },
    });
  }));
}

async function saveAppearance(userId, { theme, customAccent, customBase, statusColors }) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  const prefs = {
    ...(user.preferences || {}),
    theme:        VALID_THEME_IDS.has(theme) ? theme : 'dark',
    // Validate custom accent as a #rrggbb hex
    customAccent: /^#[0-9a-f]{6}$/i.test(customAccent || '') ? customAccent : '#6366f1',
    customBase:   customBase === 'light' ? 'light' : 'dark',
    // Catppuccin themes use Catppuccin's red/yellow/green/blue for status colours unless this is 'tailwind'
    statusColors: statusColors === 'tailwind' ? 'tailwind' : undefined,
  };
  // There's one app icon now; drop the old per-user icon choice
  delete prefs.iconSetDark;
  delete prefs.iconSetLight;
  await prisma.user.update({ where: { id: userId }, data: { preferences: prefs } });
}

// order: widget keys in display order; enabledKeys: the ones shown
async function saveDashboard(userId, order, enabledKeys) {
  const widgets = order
    .filter(k => WIDGET_KEYS.includes(k))
    .map(k => ({ key: k, enabled: enabledKeys.includes(k) }));
  // append any missing keys as disabled
  WIDGET_KEYS.filter(k => !widgets.find(w => w.key === k)).forEach(k => widgets.push({ key: k, enabled: false }));
  const user = await prisma.user.findUnique({ where: { id: userId } });
  const prefs = { ...(user.preferences || {}), dashboardWidgets: widgets };
  await prisma.user.update({ where: { id: userId }, data: { preferences: prefs } });
}

async function saveAvatar(userId, file) {
  const ext = uploads.safeExt(file.originalname);
  const user = await prisma.user.findUnique({ where: { id: userId } });
  const oldExt = (user.preferences || {}).avatarExt;
  await uploads.writeFile(uploads.avatarPath(userId, ext), file.buffer);
  if (oldExt && oldExt !== ext) await uploads.remove(uploads.avatarPath(userId, oldExt));
  const prefs = { ...(user.preferences || {}), avatarExt: ext };
  await prisma.user.update({ where: { id: userId }, data: { preferences: prefs } });
}

async function removeAvatar(userId) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  const prefs = { ...(user.preferences || {}) };
  if (prefs.avatarExt) {
    await uploads.remove(uploads.avatarPath(userId, prefs.avatarExt));
    delete prefs.avatarExt;
    await prisma.user.update({ where: { id: userId }, data: { preferences: prefs } });
  }
}

const NOTIF_TYPES = ['daily_digest', 'slipping_tasks', 'task_due'];
const DEFAULT_SEND_TIMES = { daily_digest: '08:00', slipping_tasks: '09:00', task_due: '00:00' };

// Delivery channels + per-type settings. types: { daily_digest|slipping_tasks|task_due:
// { enabled, sendTime, channels: { pushover, email, ntfy } } }
async function saveNotifications(user, { pushoverKey, pushoverEnabled, ntfyEnabled, notifEmail, types }) {
  const fresh = await prisma.user.findUnique({ where: { id: user.id } });
  const prefs = {
    ...(fresh.preferences || {}),
    pushoverKey:     (pushoverKey || '').trim(),
    pushoverEnabled: !!pushoverEnabled,
    ntfyEnabled:     !!ntfyEnabled,
    // The account email is the default, so it's stored as blank
    notifEmail:      (notifEmail || '').trim().toLowerCase() === (user.email || '').toLowerCase() ? '' : (notifEmail || '').trim(),
  };
  // Each user gets their own unguessable topic the first time ntfy is turned on
  if (prefs.ntfyEnabled && !prefs.ntfyTopic) prefs.ntfyTopic = ntfy.newTopic();
  await prisma.user.update({ where: { id: user.id }, data: { preferences: prefs } });

  for (const type of NOTIF_TYPES) {
    const t = (types || {})[type] || {};
    const sendTime = type === 'task_due' ? '00:00'
      : (/^([01]\d|2[0-3]):[0-5]\d$/.test(t.sendTime || '') ? t.sendTime : DEFAULT_SEND_TIMES[type]);
    const channels = { pushover: !!t.channels?.pushover, email: !!t.channels?.email, ntfy: !!t.channels?.ntfy };
    await prisma.notificationPref.upsert({
      where:  { userId_type: { userId: user.id, type } },
      update: { enabled: !!t.enabled, sendTime, channels },
      create: { userId: user.id, type, enabled: !!t.enabled, sendTime, channels },
    });
  }
}

// Returns an error message, or null when the test push went out
async function sendNtfyTest(user) {
  const prefs = user.preferences || {};
  if (!ntfy.isConfigured()) return "ntfy isn't configured on this server";
  if (!prefs.ntfyTopic) return 'Turn on ntfy and save first';
  const ok = await ntfy.send(prefs.ntfyTopic, {
    title:    'Obelo test',
    message:  'ntfy notifications are working 🎉',
    url:      `${process.env.APP_URL || 'http://localhost:3000'}/settings?tab=notifications`,
    urlTitle: 'Open settings',
  }, { force: true });
  return ok ? null : "Couldn't reach the ntfy server — check the server log";
}

// Replaces the user's ntfy topic (e.g. if it was shared by mistake)
async function newNtfyTopic(userId) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  const topic = ntfy.newTopic();
  await prisma.user.update({ where: { id: userId }, data: { preferences: { ...(user.preferences || {}), ntfyTopic: topic } } });
  return topic;
}

// Sends a sample daily-digest email with made-up data. Returns { emailTo } or { error }.
async function sendTestEmail(user) {
  const prefs = user.preferences || {};
  const emailTo = prefs.notifEmail || user.email;
  if (!emailTo) return { error: 'No email address configured — add one to your profile or notification settings' };
  if (!emailService.isConfigured()) return { error: "Email isn't set up on this server (SMTP_HOST / SMTP_USER in .env)" };

  const name = user.displayName || 'there';
  const appUrl = process.env.APP_URL || 'http://localhost:3000';

  const fakeEvents = [
    { time: '9:00 AM', title: 'Team standup' },
    { time: '11:30 AM', title: 'Lunch with Sarah' },
    { time: '2:00 PM', title: 'Product review — Q3 roadmap' },
    { time: 'All day', title: 'Company offsite planning' },
  ];
  const fakeTasks = [
    { title: 'Review pull requests', due: 'today', priority: 'high' },
    { title: 'Draft Q3 OKRs', due: 'tomorrow', priority: 'high' },
    { title: 'Update project documentation', due: 'this week', priority: 'medium' },
    { title: 'Schedule 1:1s for next month', due: 'this week', priority: 'medium' },
  ];

  const eventsHtml = fakeEvents.map(e => `
    <tr>
      <td style="padding:6px 0;color:#94a3b8;font-size:13px;width:80px;vertical-align:top">${e.time}</td>
      <td style="padding:6px 0;color:#e2e8f0;font-size:13px">${e.title}</td>
    </tr>`).join('');

  const tasksHtml = fakeTasks.map(t => `
    <tr>
      <td style="padding:5px 0;vertical-align:top;width:16px">
        <span style="display:inline-block;width:6px;height:6px;border-radius:50%;background:${t.priority === 'high' ? '#f87171' : '#fb923c'};margin-top:5px"></span>
      </td>
      <td style="padding:5px 0 5px 8px;color:#e2e8f0;font-size:13px">${t.title}
        <span style="color:#64748b;font-size:11px;margin-left:6px">due ${t.due}</span>
      </td>
    </tr>`).join('');

  const html = `<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0f172a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#0f172a;padding:32px 16px">
  <tr><td align="center">
    <table width="100%" style="max-width:520px" cellpadding="0" cellspacing="0">

      <!-- Header -->
      <tr><td style="padding-bottom:24px">
        <p style="margin:0;font-size:13px;color:#6366f1;font-weight:600;letter-spacing:.05em;text-transform:uppercase">Obelo</p>
        <h1 style="margin:4px 0 0;font-size:22px;font-weight:700;color:#f1f5f9">Good morning, ${name} ☀️</h1>
        <p style="margin:4px 0 0;font-size:13px;color:#64748b">Here's what's on your plate today. <span style="color:#475569;font-size:11px">(This is a test email)</span></p>
      </td></tr>

      <!-- Calendar -->
      <tr><td style="background:#1e293b;border-radius:12px;padding:20px;margin-bottom:16px">
        <p style="margin:0 0 12px;font-size:11px;font-weight:600;color:#64748b;text-transform:uppercase;letter-spacing:.08em">📅 Today's Schedule</p>
        <table width="100%" cellpadding="0" cellspacing="0">${eventsHtml}</table>
      </td></tr>

      <tr><td style="height:12px"></td></tr>

      <!-- Tasks -->
      <tr><td style="background:#1e293b;border-radius:12px;padding:20px">
        <p style="margin:0 0 12px;font-size:11px;font-weight:600;color:#64748b;text-transform:uppercase;letter-spacing:.08em">✅ Top Tasks</p>
        <table width="100%" cellpadding="0" cellspacing="0">${tasksHtml}</table>
      </td></tr>

      <tr><td style="height:24px"></td></tr>

      <!-- CTA -->
      <tr><td align="center">
        <a href="${appUrl}" style="display:inline-block;padding:10px 28px;background:#6366f1;color:#ffffff;text-decoration:none;border-radius:8px;font-size:14px;font-weight:600">Open Obelo →</a>
      </td></tr>

      <!-- Footer -->
      <tr><td style="padding-top:24px;text-align:center">
        <p style="margin:0;font-size:11px;color:#334155">Sent by Obelo · <a href="${appUrl}/settings?tab=notifications" style="color:#475569">Manage notifications</a></p>
      </td></tr>

    </table>
  </td></tr>
</table>
</body></html>`;

  const text = `Good morning, ${name}!\n\nToday's schedule:\n${fakeEvents.map(e => `  ${e.time} — ${e.title}`).join('\n')}\n\nTop tasks:\n${fakeTasks.map(t => `  • ${t.title} (due ${t.due})`).join('\n')}\n\n${appUrl}`;

  const sent = await emailService.sendEmail(emailTo, `[Test] Good morning, ${name} ☀️`, text, html, { force: true });
  if (!sent) return { error: "The email couldn't be sent — check the server log" };
  return { emailTo };
}

const AUTOSAVE_DURATIONS = ['immediate', '2min', '5min'];

async function saveNotePrefs(userId, { autosaveEnabled, autosaveDuration, notePaper }) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  const prefs = {
    ...(user.preferences || {}),
    autosaveEnabled: !!autosaveEnabled,
    autosaveDuration: AUTOSAVE_DURATIONS.includes(autosaveDuration) ? autosaveDuration : 'immediate',
  };
  // Only changed when the form sends it (the app's API saves autosave settings without it)
  if (notePaper !== undefined) prefs.notePaper = NOTE_PAPERS.includes(notePaper) ? notePaper : 'theme';
  await prisma.user.update({ where: { id: userId }, data: { preferences: prefs } });
}

// Set, change or remove (action: 'remove') the 4–6 digit note-lock PIN.
// Returns { error } or { message }.
async function setNotePin(userId, { action, currentPin, newPin, confirmPin }) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  const prefs = { ...(user.preferences || {}) };

  if (action === 'remove') {
    if (!prefs.noteLockPin) return { error: 'No PIN is set' };
    const valid = await bcrypt.compare(currentPin || '', prefs.noteLockPin);
    if (!valid) return { error: 'Incorrect PIN' };
    delete prefs.noteLockPin;
    await prisma.user.update({ where: { id: userId }, data: { preferences: prefs } });
    return { message: 'Note lock PIN removed' };
  }

  if (!newPin || !/^[0-9]{4,6}$/.test(newPin)) return { error: 'PIN must be 4–6 digits' };
  if (newPin !== confirmPin) return { error: 'PINs do not match' };
  if (prefs.noteLockPin) {
    const valid = await bcrypt.compare(currentPin || '', prefs.noteLockPin);
    if (!valid) return { error: 'Current PIN is incorrect' };
  }
  prefs.noteLockPin = await bcrypt.hash(newPin, 12);
  await prisma.user.update({ where: { id: userId }, data: { preferences: prefs } });
  return { message: 'Note lock PIN saved' };
}

// GET /settings
router.get('/', requireAuth, async (req, res, next) => {
  try {
    const userId = req.user.id;

    const userModules = await prisma.userModule.findMany({ where: { userId } });
    const moduleMap   = Object.fromEntries(userModules.map(m => [m.moduleKey, m.enabled]));
    const posMap      = Object.fromEntries(userModules.filter(m => m.position != null).map(m => [m.moduleKey, m.position]));
    const defaultOrder = Object.fromEntries(MODULES.map((m, i) => [m.key, i]));

    // Build module list — exclude hidden and alwaysEnabled modules from the toggle UI
    const moduleList = MODULES.filter(m => !m.hidden && (!m.requiresAi || ai.isConfigured())).map(m => ({
      key:          m.key,
      label:        m.label,
      alwaysEnabled: !!m.alwaysEnabled,
      enabled:      m.alwaysEnabled ? true : (moduleMap[m.key] !== false),
      position:     posMap[m.key] != null ? posMap[m.key] : defaultOrder[m.key],
    })).sort((a, b) => {
      if (a.key === 'dashboard') return -1;
      if (b.key === 'dashboard') return 1;
      if (a.key === 'settings')  return 1;
      if (b.key === 'settings')  return -1;
      // Shown in the sidebar's order (the saved order only matters for the phone's bottom bar)
      const layout = SIDEBAR_LAYOUT.flatMap(([, keys]) => keys);
      const ia = layout.indexOf(a.key), ib = layout.indexOf(b.key);
      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.position - b.position;
    });

    const prefs = req.user.preferences || {};

    const notifPrefs = await prisma.notificationPref.findMany({ where: { userId } });
    const notifMap = Object.fromEntries(notifPrefs.map(p => [p.type, p]));

    const fullUser = await prisma.user.findUnique({ where: { id: userId }, select: { preferences: true, passwordHash: true } });
    const fullPrefs = fullUser.preferences || {};

    const tab = req.query.tab || 'account';
    // Calendar accounts and your own calendars are managed on the Calendar module's own page
    if (tab === 'calendars') return res.redirect('/calendar/sources');
    let tagCounts = {};
    if (tab === 'tags') {
      tagCounts = await getTagUsageCounts(userId);
    }
    const sessions = tab === 'account' ? await userSessions.listForUser(userId, req.sessionID) : [];

    let apiTokens = [];
    let newToken = null;
    let newTokenLabel = null;
    if (tab === 'shortcuts') {
      apiTokens = await prisma.apiToken.findMany({
        where:   { userId },
        orderBy: { createdAt: 'desc' },
      });
      const flash = req.session.newApiToken || null;
      if (flash) {
        delete req.session.newApiToken;
        await new Promise((resolve, reject) => req.session.save(err => err ? reject(err) : resolve()));
        newToken = flash.value;
        newTokenLabel = flash.label;
      }
    }

    res.render('settings/index', {
      title:       'Settings',
      tab,
      success:     req.query.success || null,
      error:       req.query.error   || null,
      moduleList,
      hasPassword: !!fullUser.passwordHash,
      passwordEnabled: tab === 'account' ? await passwords.passwordLoginEnabled() : false,
      minPasswordLength: passwords.MIN_LENGTH,
      hasNoteLockPin: !!fullPrefs.noteLockPin,
      userEmail:       req.user.email         || '',
      pushoverKey:     prefs.pushoverKey     || '',
      pushoverEnabled: prefs.pushoverEnabled || false,
      ntfyConfigured:  ntfy.isConfigured(),
      ntfyServer:      ntfy.serverUrl(),
      ntfyEnabled:     prefs.ntfyEnabled || false,
      ntfyTopic:       prefs.ntfyTopic   || '',
      notifEmail:      (prefs.notifEmail && prefs.notifEmail !== (req.user.email || '')) ? prefs.notifEmail : '',
      notifMap,
      BUILT_IN_THEMES,
      currentTheme:    prefs.theme        || 'dark',
      customAccent:    prefs.customAccent || '#6366f1',
      customBase:      prefs.customBase   || 'dark',
      statusColors:    prefs.statusColors === 'tailwind' ? 'tailwind' : 'catppuccin',
      timeFormat:        prefs.timeFormat        || '12h',
      autosaveEnabled:   prefs.autosaveEnabled !== false,
      autosaveDuration:  prefs.autosaveDuration  || 'immediate',
      notePaper:         notePaperChoice(prefs),
      noteTemplates:     userTemplates.forUser(req.user),
      tagCounts,
      sessions,
      apiTokens,
      appUrl:        process.env.APP_URL || 'http://localhost:3000',
      newToken,
      newTokenLabel,
    });
  } catch (err) { next(err); }
});

// ── API tokens for iOS Shortcuts (capture) ───────────────────────────────────

// POST /settings/api-tokens — generate a new API token (raw value shown once)
router.post('/api-tokens', requireAuth, async (req, res, next) => {
  try {
    const label = String(req.body.label || '').trim().slice(0, 60) || 'iOS Shortcut';
    const raw   = crypto.randomBytes(32).toString('hex');
    const hash  = crypto.createHash('sha256').update(raw).digest('hex');
    await prisma.apiToken.create({
      data: { userId: req.user.id, tokenHash: hash, label },
    });
    // Pass the raw token via session flash so it never appears in URLs or logs
    req.session.newApiToken = { value: raw, label };
    await new Promise((resolve, reject) => req.session.save(err => err ? reject(err) : resolve()));
    res.redirect('/settings?tab=shortcuts');
  } catch (err) { next(err); }
});

// POST /settings/api-tokens/:id/delete — revoke a token
router.post('/api-tokens/:id/delete', requireAuth, async (req, res, next) => {
  try {
    await prisma.apiToken.deleteMany({
      where: { id: parseInt(req.params.id), userId: req.user.id },
    });
    res.redirect('/settings?tab=shortcuts');
  } catch (err) { next(err); }
});

// POST /settings/account — update display name, email, timezone, time format
router.post('/account', requireAuth, async (req, res, next) => {
  try {
    const error = await saveAccount(req.user, req.body);
    if (error) return res.redirect(`/settings?tab=account&error=${encodeURIComponent(error)}`);
    res.redirect('/settings?tab=account&success=Account+updated');
  } catch (err) { next(err); }
});

// POST /settings/password: set or change your own password, then sign out your other devices
router.post('/password', requireAuth, async (req, res, next) => {
  try {
    const back = (k, v) => res.redirect(`/settings?tab=account&${k}=${encodeURIComponent(v)}`);
    if (!(await passwords.passwordLoginEnabled())) return back('error', 'Password sign-in is switched off on this server');
    if (req.body.newPassword !== req.body.confirmPassword) return back('error', "The two new passwords don't match");
    const error = await passwords.changeOwnPassword(req.user.id, req.body.currentPassword, req.body.newPassword);
    if (error) return back('error', error);
    const ended = await userSessions.endForUser(req.user.id, req.sessionID);
    log.info('auth', `@${req.user.username} changed their password`, { userId: req.user.id, ended });
    back('success', 'Password saved');
  } catch (err) { next(err); }
});

// POST /settings/sessions/:key/end — sign out one of your other devices
router.post('/sessions/:key/end', requireAuth, async (req, res, next) => {
  try {
    const key = String(req.params.key);
    if (!/^[0-9a-f]{16}$/.test(key)) return res.redirect('/settings?tab=account&error=Unknown+session');
    const ended = await userSessions.endForUser(req.user.id, req.sessionID, [key]);
    if (!ended) return res.redirect('/settings?tab=account&error=That+device+is+already+signed+out');
    log.info('auth', `@${req.user.username} signed out another device`, { userId: req.user.id, ended });
    res.redirect('/settings?tab=account&success=Device+signed+out');
  } catch (err) { next(err); }
});

// POST /settings/sessions/end-others — sign out everywhere except this device
router.post('/sessions/end-others', requireAuth, async (req, res, next) => {
  try {
    const ended = await userSessions.endForUser(req.user.id, req.sessionID);
    log.info('auth', `@${req.user.username} signed out all other devices`, { userId: req.user.id, ended });
    const msg = ended ? `Signed out ${ended} other device${ended === 1 ? '' : 's'}` : 'No other devices were signed in';
    res.redirect(`/settings?tab=account&success=${encodeURIComponent(msg)}`);
  } catch (err) { next(err); }
});

// POST /settings/modules — toggle on/off + save order
router.post('/modules', requireAuth, async (req, res, next) => {
  try {
    let order = [];
    if (req.body.order) {
      try { order = JSON.parse(req.body.order); } catch {}
    }
    const enabledKeys = MODULES.filter(m => req.body[m.key] === 'on').map(m => m.key);
    await saveModules(req.user.id, enabledKeys, Array.isArray(order) ? order : []);
    res.redirect('/settings?tab=modules&success=Modules+updated');
  } catch (err) { next(err); }
});

// POST /settings/notifications — save delivery addresses + per-type prefs with channels
router.post('/notifications', requireAuth, async (req, res, next) => {
  try {
    const b = req.body;
    const ch = (prefix) => ({ pushover: b[`${prefix}_ch_pushover`] === 'on', email: b[`${prefix}_ch_email`] === 'on', ntfy: b[`${prefix}_ch_ntfy`] === 'on' });
    await saveNotifications(req.user, {
      pushoverKey: b.pushoverKey, pushoverEnabled: b.pushoverEnabled === 'on',
      ntfyEnabled: b.ntfyEnabled === 'on', notifEmail: b.notifEmail,
      types: {
        // An unchecked box isn't submitted at all, so "on" is the only true value
        daily_digest:   { enabled: b.digest_enabled === 'on',   sendTime: b.digest_time,   channels: ch('digest') },
        slipping_tasks: { enabled: b.slipping_enabled === 'on', sendTime: b.slipping_time, channels: ch('slipping') },
        task_due:       { enabled: b.taskdue_enabled === 'on',  channels: ch('taskdue') },
      },
    });
    res.redirect('/settings?tab=notifications&success=Notification+settings+saved');
  } catch (err) { next(err); }
});

// POST /settings/notifications/ntfy-test — send a test push to the user's ntfy topic
router.post('/notifications/ntfy-test', requireAuth, async (req, res, next) => {
  try {
    const error = await sendNtfyTest(req.user);
    res.redirect(error
      ? `/settings?tab=notifications&error=${encodeURIComponent(error)}`
      : '/settings?tab=notifications&success=Test+notification+sent+via+ntfy');
  } catch (err) { next(err); }
});

// POST /settings/notifications/ntfy-topic — replace the topic (e.g. if it was shared by mistake)
router.post('/notifications/ntfy-topic', requireAuth, async (req, res, next) => {
  try {
    await newNtfyTopic(req.user.id);
    res.redirect('/settings?tab=notifications&success=New+ntfy+topic+created+%E2%80%94+subscribe+to+it+in+the+ntfy+app');
  } catch (err) { next(err); }
});

// POST /settings/notifications/test — send a test digest email with fake data
router.post('/notifications/test', requireAuth, async (req, res, next) => {
  try {
    const { emailTo, error } = await sendTestEmail(req.user);
    if (error) return res.redirect(`/settings?tab=notifications&error=${encodeURIComponent(error)}`);
    res.redirect(`/settings?tab=notifications&success=${encodeURIComponent(`Test email sent to ${emailTo}`)}`);
  } catch (err) { next(err); }
});

// POST /settings/appearance — save theme + icon set preferences
router.post('/appearance', requireAuth, async (req, res, next) => {
  try {
    await saveAppearance(req.user.id, req.body);
    res.redirect('/settings?tab=appearance&success=Appearance+saved');
  } catch (err) { next(err); }
});

// POST /settings/notes — autosave preferences
router.post('/notes', requireAuth, async (req, res, next) => {
  try {
    await saveNotePrefs(req.user.id, { autosaveEnabled: req.body.autosaveEnabled === 'on', autosaveDuration: req.body.autosaveDuration, notePaper: req.body.notePaper });
    res.redirect('/settings?tab=notes&success=Notes+settings+saved');
  } catch (err) { next(err); }
});

// POST /settings/note-templates… — the person's own note templates (lib/userTemplates.js)
function templateFields(body) {
  return { label: body.label, type: body.type, title: body.title, dateTitle: body.dateTitle === 'on', content: body.content };
}
const templatesBack = (res, { error, success }) =>
  res.redirect('/settings?tab=notes&' + (error ? 'error=' + encodeURIComponent(error) : 'success=' + encodeURIComponent(success)));

router.post('/note-templates', requireAuth, async (req, res, next) => {
  try {
    const r = await userTemplates.mutate(req.user.id, (prefs) => userTemplates.withCreated(prefs, templateFields(req.body)));
    templatesBack(res, r.error ? { error: r.error } : { success: `Added the template "${r.template.label}".` });
  } catch (err) { next(err); }
});

router.post('/note-templates/:id', requireAuth, async (req, res, next) => {
  try {
    const r = await userTemplates.mutate(req.user.id, (prefs) => userTemplates.withUpdated(prefs, req.params.id, templateFields(req.body)));
    templatesBack(res, r.notFound ? { error: 'That template is gone.' } : r.error ? { error: r.error } : { success: `Saved "${r.template.label}".` });
  } catch (err) { next(err); }
});

router.post('/note-templates/:id/delete', requireAuth, async (req, res, next) => {
  try {
    const r = await userTemplates.mutate(req.user.id, (prefs) => userTemplates.withRemoved(prefs, req.params.id));
    templatesBack(res, r.notFound ? { error: 'That template is gone.' } : { success: 'Template deleted.' });
  } catch (err) { next(err); }
});

// POST /settings/dashboard — save widget order + visibility
router.post('/dashboard', requireAuth, async (req, res, next) => {
  try {
    let order = WIDGET_KEYS;
    try { order = JSON.parse(req.body.order || '[]'); } catch {}
    const enabledKeys = WIDGET_KEYS.filter(k => req.body[k] === 'on');
    await saveDashboard(req.user.id, Array.isArray(order) ? order : [], enabledKeys);
    res.redirect('/settings?tab=dashboard&success=Dashboard+saved');
  } catch (err) { next(err); }
});

// GET /settings/avatar — serve the current user's uploaded avatar
router.get('/avatar', requireAuth, async (req, res, next) => {
  try {
    const ext = (req.user.preferences || {}).avatarExt;
    if (!ext) return res.status(404).end();
    const data = await uploads.readFile(uploads.avatarPath(req.user.id, ext));
    if (!data) return res.status(404).end();
    uploads.setServeHeaders(res);
    res.type(ext).send(data);
  } catch (err) { next(err); }
});

// POST /settings/avatar — upload a new avatar
router.post('/avatar', requireAuth, avatarUpload.single('avatar'), async (req, res, next) => {
  try {
    if (!req.file) return res.redirect('/settings?tab=account&error=No+image+received');
    await saveAvatar(req.user.id, req.file);
    res.redirect('/settings?tab=account&success=Avatar+updated');
  } catch (err) { next(err); }
});

// POST /settings/avatar/remove — delete the custom avatar
router.post('/avatar/remove', requireAuth, async (req, res, next) => {
  try {
    await removeAvatar(req.user.id);
    res.redirect('/settings?tab=account&success=Avatar+removed');
  } catch (err) { next(err); }
});

// POST /settings/note-lock-pin — set, change, or remove the 4-6 digit note lock PIN
router.post('/note-lock-pin', requireAuth, async (req, res, next) => {
  try {
    const { error, message } = await setNotePin(req.user.id, req.body);
    res.redirect(error
      ? `/settings?tab=account&error=${encodeURIComponent(error)}`
      : `/settings?tab=account&success=${encodeURIComponent(message)}`);
  } catch (err) { next(err); }
});

// POST /settings/delete-account — user deletes their own account
// ── Import helpers ─────────────────────────────────────────────────────────

const importUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => cb(null, /\.(md|json|csv)$/i.test(file.originalname)),
});

function parseFrontmatter(text) {
  if (!text.startsWith('---')) return { meta: {}, body: text.trim() };
  const end = text.indexOf('\n---', 3);
  if (end === -1) return { meta: {}, body: text.trim() };
  const meta = {};
  for (const line of text.slice(4, end).split('\n')) {
    const colon = line.indexOf(':');
    if (colon === -1) continue;
    meta[line.slice(0, colon).trim()] = line.slice(colon + 1).trim().replace(/^["']|["']$/g, '');
  }
  return { meta, body: text.slice(end + 4).trim() };
}

function parseCSV(text) {
  const lines = text.split(/\r?\n/).filter(l => l.trim());
  if (lines.length < 2) return [];
  function parseLine(line) {
    const cells = []; let cur = '', inQ = false;
    for (let i = 0; i < line.length; i++) {
      const ch = line[i];
      if (ch === '"') { if (inQ && line[i+1] === '"') { cur += '"'; i++; } else inQ = !inQ; }
      else if (ch === ',' && !inQ) { cells.push(cur); cur = ''; }
      else cur += ch;
    }
    cells.push(cur); return cells;
  }
  const headers = parseLine(lines[0]).map(h => h.trim().toLowerCase());
  return lines.slice(1).map(line => {
    const cells = parseLine(line);
    const obj = {};
    headers.forEach((h, i) => { obj[h] = (cells[i] || '').trim(); });
    return obj;
  }).filter(row => Object.values(row).some(v => v));
}

function colVal(row, ...keys) {
  for (const k of keys) {
    const norm = s => s.replace(/[\s_\-]/g, '').toLowerCase();
    const found = Object.keys(row).find(h => norm(h) === norm(k));
    if (found && row[found]) return row[found];
  }
  return '';
}

// ── Data export ────────────────────────────────────────────────────────────

function csvEsc(v) {
  const s = v == null ? '' : String(v);
  return (s.includes(',') || s.includes('"') || s.includes('\n'))
    ? '"' + s.replace(/"/g, '""') + '"'
    : s;
}
function csvRow(cells) { return cells.map(csvEsc).join(',') + '\r\n'; }

// Each export builds { filename, type, body } for a user; the web downloads them from
// /settings/export/<name> and the app from /api/v1/settings/export/<name>.
const today = () => new Date().toISOString().slice(0, 10);

const EXPORTS = {
  // Full data export
  json: async (user) => {
    const uid = user.id;
    const [notes, tasks, reminders, routines, lists, bookmarks] = await Promise.all([
      prisma.note.findMany({ where: { userId: uid }, orderBy: { createdAt: 'asc' }, include: { thoughts: true } }),
      prisma.task.findMany({ where: { userId: uid, parentId: null }, orderBy: { createdAt: 'asc' }, include: { subtasks: true } }),
      prisma.reminder.findMany({ where: { userId: uid }, orderBy: { createdAt: 'asc' } }),
      prisma.routine.findMany({ where: { userId: uid }, orderBy: { createdAt: 'asc' }, include: { completions: { orderBy: { completedDate: 'asc' } } } }),
      prisma.list.findMany({ where: { userId: uid }, orderBy: { createdAt: 'asc' }, include: { items: true } }),
      prisma.bookmark.findMany({ where: { userId: uid }, orderBy: { createdAt: 'asc' } }),
    ]);
    const payload = {
      exportedAt: new Date().toISOString(),
      user: { username: user.username, displayName: user.displayName, email: user.email, timezone: user.timezone },
      notes, tasks, reminders, routines, lists, bookmarks,
    };
    return { filename: `obelo-export-${today()}.json`, type: 'application/json', body: JSON.stringify(payload, null, 2) };
  },

  'tasks.csv': async (user) => {
    const tasks = await prisma.task.findMany({
      where: { userId: user.id, parentId: null },
      orderBy: { createdAt: 'asc' },
    });
    let csv = csvRow(['Title', 'Status', 'Priority', 'Due Date', 'Due Time', 'Tags', 'Notes', 'Recurring', 'Recur Rule', 'Created At', 'Completed At']);
    for (const t of tasks) {
      csv += csvRow([
        t.title, t.status, t.priority,
        t.dueDate ? t.dueDate.toISOString().slice(0,10) : '',
        t.dueTime || '',
        t.tags.join('; '),
        t.notes || '',
        t.recurring ? 'yes' : 'no',
        t.recurRule || '',
        t.createdAt.toISOString(),
        t.completedAt ? t.completedAt.toISOString() : '',
      ]);
    }
    return { filename: `obelo-tasks-${today()}.csv`, type: 'text/csv', body: csv };
  },

  'notes.json': async (user) => {
    const notes = await prisma.note.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: 'asc' },
      select: { id: true, type: true, title: true, content: true, source: true, author: true, tags: true, pinned: true, flaggedForReview: true, createdAt: true, updatedAt: true },
    });
    return { filename: `obelo-notes-${today()}.json`, type: 'application/json', body: JSON.stringify(notes, null, 2) };
  },

  'bookmarks.csv': async (user) => {
    const bookmarks = await prisma.bookmark.findMany({ where: { userId: user.id }, orderBy: { createdAt: 'asc' } });
    let csv = csvRow(['Title', 'URL', 'Description', 'Tags', 'Created At']);
    for (const b of bookmarks) {
      csv += csvRow([b.title || '', b.url, b.description || '', b.tags.join('; '), b.createdAt.toISOString()]);
    }
    return { filename: `obelo-bookmarks-${today()}.csv`, type: 'text/csv', body: csv };
  },

  // Netscape bookmark format (browser-importable)
  'bookmarks.html': async (user) => {
    const bookmarks = await prisma.bookmark.findMany({ where: { userId: user.id }, orderBy: { createdAt: 'asc' } });
    let html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n';
    html += '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">\n';
    html += '<TITLE>Obelo Bookmarks</TITLE>\n<H1>Obelo Bookmarks</H1>\n<DL><p>\n';
    for (const b of bookmarks) {
      const ts = Math.floor(b.createdAt.getTime() / 1000);
      const title = (b.title || b.url).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      const url = b.url.replace(/"/g, '&quot;');
      html += `    <DT><A HREF="${url}" ADD_DATE="${ts}">${title}</A>\n`;
    }
    html += '</DL><p>\n';
    return { filename: `obelo-bookmarks-${today()}.html`, type: 'text/html', body: html };
  },
};

// Sends one of EXPORTS as a download, or 404s for an unknown name
async function sendExport(name, user, res) {
  const build = Object.hasOwn(EXPORTS, name) ? EXPORTS[name] : null;
  if (!build) return res.status(404).end();
  const { filename, type, body } = await build(user);
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  res.setHeader('Content-Type', type);
  res.send(body);
}

// GET /settings/export/json, tasks.csv, notes.json, bookmarks.csv, bookmarks.html
router.get('/export/:name', requireAuth, async (req, res, next) => {
  try { await sendExport(req.params.name, req.user, res); } catch (err) { next(err); }
});

// One or more Markdown files (front matter title/tags supported). Returns { message } or { error }.
async function importNotes(user, files) {
  if (!files || files.length === 0) return { error: 'No files selected' };

  let count = 0;
  for (const file of files) {
    const text = file.buffer.toString('utf8');
    const { meta, body } = parseFrontmatter(text);
    const title = meta.title || file.originalname.replace(/\.md$/i, '') || 'Untitled';
    const tags  = meta.tags ? meta.tags.split(/[,;]+/).map(t => t.trim()).filter(Boolean) : [];
    await prisma.note.create({ data: { userId: user.id, type: 'note', title, content: body || null, tags } });
    count++;
  }
  return { message: `Imported ${count} note${count !== 1 ? 's' : ''}` };
}

// A CSV with flexible column names. Returns { message } or { error }.
async function importTasks(user, file) {
  if (!file) return { error: 'No file selected' };

  const rows = parseCSV(file.buffer.toString('utf8'));
  if (rows.length === 0) return { error: 'No data rows found in CSV' };

  const VALID_STATUSES   = new Set(['inbox','today','in-progress','done','archived']);
  const VALID_PRIORITIES = new Set(['none','low','medium','high']);

  let count = 0, skipped = 0;
  for (const row of rows) {
    const title = colVal(row, 'title', 'name', 'task').trim();
    if (!title) { skipped++; continue; }

    const statusRaw   = colVal(row, 'status').toLowerCase();
    const priorityRaw = colVal(row, 'priority').toLowerCase();
    const dueDateRaw  = colVal(row, 'due date', 'due_date', 'duedate', 'due');
    const dueDate     = dueDateRaw ? (d => isNaN(d.getTime()) ? null : d)(new Date(dueDateRaw)) : null;
    const tags        = colVal(row, 'tags', 'labels').split(/[;,]+/).map(t => t.trim()).filter(Boolean);

    await prisma.task.create({ data: {
      userId:   user.id,
      title,
      status:   VALID_STATUSES.has(statusRaw)   ? statusRaw   : 'inbox',
      priority: VALID_PRIORITIES.has(priorityRaw) ? priorityRaw : 'none',
      dueDate,
      dueTime:  colVal(row, 'due time', 'due_time') || null,
      tags,
      notes:    colVal(row, 'notes', 'note', 'description') || null,
    }});
    count++;
  }

  const msg = skipped > 0
    ? `Imported ${count} task${count !== 1 ? 's' : ''} (${skipped} skipped — no title)`
    : `Imported ${count} task${count !== 1 ? 's' : ''}`;
  return { message: msg };
}

// Restores a Obelo full JSON export. Returns { message } or { error }.
// Items already in the account (same title and creation time; bookmarks by URL) are skipped,
// so restoring the same file twice doesn't duplicate anything.
async function importJson(user, file) {
  if (!file) return { error: 'No file selected' };

  let data;
  try { data = JSON.parse(file.buffer.toString('utf8')); }
  catch { return { error: 'Invalid JSON file' }; }

  const uid = user.id;
  const arr = v => (Array.isArray(v) ? v : []);
  const date = v => { const d = v ? new Date(v) : null; return d && !isNaN(d) ? d : null; };
  const str = v => (typeof v === 'string' && v !== '' ? v : null);
  const oneOf = (v, allowed, fallback) => (allowed.includes(v) ? v : fallback);
  const PRIORITIES = ['none', 'low', 'medium', 'high'];
  const TASK_STATUSES = ['inbox', 'today', 'in-progress', 'done', 'archived'];

  // "title|createdAt" keys of what the account already has, per model
  const keyOf = (title, createdAt) => `${title}|${date(createdAt)?.toISOString() || ''}`;
  const existingKeys = async model => new Set(
    (await prisma[model].findMany({ where: { userId: uid }, select: { title: true, createdAt: true } }))
      .map(r => keyOf(r.title, r.createdAt))
  );

  const counts = { notes: 0, tasks: 0, reminders: 0, routines: 0, lists: 0, bookmarks: 0, skipped: 0 };

  const haveNotes = await existingKeys('note');
  for (const n of arr(data.notes)) {
    if (!n.title) continue;
    if (haveNotes.has(keyOf(n.title, n.createdAt))) { counts.skipped++; continue; }
    await prisma.note.create({ data: {
      userId: uid, type: oneOf(n.type, ['note', 'journal', 'quote'], 'note'), title: n.title,
      content: str(n.content), source: str(n.source), author: str(n.author),
      tags: arr(n.tags), pinned: !!n.pinned, private: !!n.private,
      flaggedForReview: !!n.flaggedForReview, reviewDate: date(n.reviewDate),
      // Locked notes stay encrypted; they open again when restored into the same account
      // on a server with the same NOTE_LOCK_SECRET
      locked: !!(n.locked && n.lockedContent && n.lockSalt),
      lockedContent: n.locked ? str(n.lockedContent) : null,
      lockSalt: n.locked ? str(n.lockSalt) : null,
      hasDrawing: !!(n.hasDrawing && n.drawingData), drawingData: n.hasDrawing ? str(n.drawingData) : null,
      ...(date(n.createdAt) && { createdAt: date(n.createdAt) }),
    }});
    counts.notes++;
  }

  const taskData = t => ({
    userId: uid, title: t.title, notes: str(t.notes),
    status: oneOf(t.status, TASK_STATUSES, 'inbox'), priority: oneOf(t.priority, PRIORITIES, 'none'),
    tags: arr(t.tags), dueDate: date(t.dueDate), dueTime: str(t.dueTime),
    recurring: !!t.recurring, recurRule: str(t.recurRule), completedAt: date(t.completedAt),
    ...(date(t.createdAt) && { createdAt: date(t.createdAt) }),
  });
  const haveTasks = await existingKeys('task');
  for (const t of arr(data.tasks)) {
    if (!t.title) continue;
    if (haveTasks.has(keyOf(t.title, t.createdAt))) { counts.skipped++; continue; }
    const parent = await prisma.task.create({ data: taskData(t) });
    for (const sub of arr(t.subtasks)) {
      if (sub.title) await prisma.task.create({ data: { ...taskData(sub), parentId: parent.id } });
    }
    counts.tasks++;
  }

  const haveReminders = await existingKeys('reminder');
  for (const r of arr(data.reminders)) {
    if (!r.title) continue;
    if (haveReminders.has(keyOf(r.title, r.createdAt))) { counts.skipped++; continue; }
    await prisma.reminder.create({ data: {
      userId: uid, title: r.title, notes: str(r.notes),
      dueDate: date(r.dueDate), dueTime: str(r.dueTime), reminderAt: date(r.reminderAt),
      priority: oneOf(r.priority, PRIORITIES, 'none'), tags: arr(r.tags),
      completed: !!r.completed, completedAt: date(r.completedAt),
      recurring: !!r.recurring, recurRule: str(r.recurRule),
      ...(date(r.createdAt) && { createdAt: date(r.createdAt) }),
    }});
    counts.reminders++;
  }

  const haveRoutines = await existingKeys('routine');
  for (const r of arr(data.routines)) {
    if (!r.title) continue;
    if (haveRoutines.has(keyOf(r.title, r.createdAt))) { counts.skipped++; continue; }
    const routine = await prisma.routine.create({ data: {
      userId: uid, title: r.title, description: str(r.description) || '',
      timeOfDay: oneOf(r.timeOfDay, ['morning', 'afternoon', 'evening', 'anytime'], 'anytime'),
      specificTime: str(r.specificTime),
      frequency: oneOf(r.frequency, ['daily', 'weekdays', 'weekends', 'weekly', 'custom'], 'daily'),
      scheduleDays: arr(r.scheduleDays), tags: arr(r.tags),
      durationDays: Number.isInteger(r.durationDays) ? r.durationDays : null,
      startDate: date(r.startDate), notify: !!r.notify, active: r.active !== false,
      ...(date(r.createdAt) && { createdAt: date(r.createdAt) }),
    }});
    const completions = arr(r.completions).filter(c => date(c.completedDate));
    if (completions.length) {
      await prisma.routineCompletion.createMany({ data: completions.map(c => ({
        routineId: routine.id, userId: uid, completedDate: date(c.completedDate), completedAt: date(c.completedAt),
      })) });
      await recalcStreak(routine, new Date().toLocaleDateString('en-CA', { timeZone: user.timezone || 'UTC' }));
    }
    counts.routines++;
  }

  const haveLists = await existingKeys('list');
  for (const l of arr(data.lists)) {
    if (!l.title) continue;
    if (haveLists.has(keyOf(l.title, l.createdAt))) { counts.skipped++; continue; }
    await prisma.list.create({ data: {
      userId: uid, title: l.title,
      ...(date(l.createdAt) && { createdAt: date(l.createdAt) }),
      items: { create: arr(l.items).filter(i => i.text).map((i, idx) => ({
        text: i.text, checked: !!i.checked, position: Number.isInteger(i.position) ? i.position : idx,
      })) },
    }});
    counts.lists++;
  }

  const haveUrls = new Set((await prisma.bookmark.findMany({ where: { userId: uid }, select: { url: true } })).map(b => b.url));
  for (const b of arr(data.bookmarks)) {
    if (!b.url) continue;
    // Only web addresses: a javascript: or data: bookmark would be a link that runs code
    if (!/^https?:\/\//i.test(String(b.url).trim())) { counts.skipped++; continue; }
    if (haveUrls.has(b.url)) { counts.skipped++; continue; }
    haveUrls.add(b.url);
    await prisma.bookmark.create({ data: {
      userId: uid, url: b.url, title: str(b.title), description: str(b.description), tags: arr(b.tags),
      ...(date(b.createdAt) && { createdAt: date(b.createdAt) }),
    }});
    counts.bookmarks++;
  }

  const parts = ['notes', 'tasks', 'reminders', 'routines', 'lists', 'bookmarks']
    .filter(k => counts[k]).map(k => `${counts[k]} ${counts[k] === 1 ? k.slice(0, -1) : k}`);
  let summary = parts.length ? `Imported ${parts.join(', ')}` : 'Nothing new to import';
  if (counts.skipped) summary += ` (${counts.skipped} already present, skipped)`;
  return { message: summary };
}

// Deletes the account and everything in it, once the typed username matches. Returns false otherwise.
async function deleteAccount(user, confirmUsername) {
  if (confirmUsername !== user.username) return false;
  await uploads.removeUserFiles(user.id);
  await prisma.user.delete({ where: { id: user.id } });
  return true;
}

// ── Data import ────────────────────────────────────────────────────────────

// POST /settings/import/notes — one or more .md files
router.post('/import/notes', requireAuth, importUpload.array('files', 200), async (req, res, next) => {
  try {
    const { message, error } = await importNotes(req.user, req.files);
    res.redirect(`/settings?tab=data&${error ? 'error' : 'success'}=${encodeURIComponent(error || message)}`);
  } catch (err) { next(err); }
});

// POST /settings/import/tasks — CSV with flexible column names
router.post('/import/tasks', requireAuth, importUpload.single('file'), async (req, res, next) => {
  try {
    const { message, error } = await importTasks(req.user, req.file);
    res.redirect(`/settings?tab=data&${error ? 'error' : 'success'}=${encodeURIComponent(error || message)}`);
  } catch (err) { next(err); }
});

// POST /settings/import/json — restore from a Obelo full JSON export
// Items already in the account (same title and creation time; bookmarks by URL) are skipped,
// so restoring the same file twice doesn't duplicate anything.
router.post('/import/json', requireAuth, importUpload.single('file'), async (req, res, next) => {
  try {
    const { message, error } = await importJson(req.user, req.file);
    res.redirect(`/settings?tab=data&${error ? 'error' : 'success'}=${encodeURIComponent(error || message)}`);
  } catch (err) { next(err); }
});

// POST /settings/tags/create
router.post('/tags/create', requireAuth, async (req, res, next) => {
  try {
    const name = (req.body.name || '').trim().toLowerCase();
    if (!name) return res.redirect('/settings?tab=tags&error=Tag+name+cannot+be+empty');
    await createTag(req.user.id, name);
    res.redirect(`/settings?tab=tags&success=${encodeURIComponent(`"${name}" created`)}`);
  } catch (err) { next(err); }
});

// POST /settings/tags/rename
router.post('/tags/rename', requireAuth, async (req, res, next) => {
  try {
    const { oldName, newName } = req.body;
    const trimmed = (newName || '').trim().toLowerCase();
    if (!oldName || !trimmed) return res.redirect('/settings?tab=tags&error=Tag+name+cannot+be+empty');
    if (trimmed === oldName) return res.redirect('/settings?tab=tags');
    await renameTag(req.user.id, oldName, trimmed);
    res.redirect(`/settings?tab=tags&success=${encodeURIComponent(`"${oldName}" renamed to "${trimmed}"`)}`);
  } catch (err) { next(err); }
});

// POST /settings/tags/delete
router.post('/tags/delete', requireAuth, async (req, res, next) => {
  try {
    const { name } = req.body;
    if (!name) return res.redirect('/settings?tab=tags&error=Missing+tag+name');
    await deleteTag(req.user.id, name);
    res.redirect(`/settings?tab=tags&success=${encodeURIComponent(`"${name}" deleted from all items`)}`);
  } catch (err) { next(err); }
});

router.post('/delete-account', requireAuth, async (req, res, next) => {
  try {
    if (!await deleteAccount(req.user, req.body.confirmUsername)) {
      return res.redirect('/settings?tab=account&error=Username+did+not+match');
    }
    req.session.destroy(() => {
      res.redirect('/');
    });
  } catch (err) { next(err); }
});

module.exports = {
  router, avatarUpload, WIDGET_KEYS, isValidTimezone,
  saveAccount, saveModules, saveAppearance, saveDashboard, saveAvatar, removeAvatar,
  NOTIF_TYPES, DEFAULT_SEND_TIMES, AUTOSAVE_DURATIONS, EXPORTS, sendExport, importUpload,
  importNotes, importTasks, importJson, deleteAccount,
  saveNotifications, sendNtfyTest, newNtfyTopic, sendTestEmail, saveNotePrefs, setNotePin,
};
