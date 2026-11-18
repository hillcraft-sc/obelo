const express  = require('express');
const crypto   = require('crypto');
const prisma   = require('../lib/prisma');
const uploads = require('../lib/uploads');

function gravatarUrl(email) {
  const hash = crypto.createHash('md5').update(email.trim().toLowerCase()).digest('hex');
  return `https://www.gravatar.com/avatar/${hash}?s=64&d=404`;
}
const { requireAdmin } = require('../middleware/auth');
const log = require('../services/logService');
const oidc = require('../services/oidcService');
const passwords = require('../lib/passwords');
const ai = require('../lib/aiProvider');
const emailService = require('../services/emailService');
const ntfy = require('../services/ntfyService');

// What this server has set up. Required items block sign-in or data safety; the rest are optional features.
function setupChecklist(settings = {}) {
  const sessionSecret = process.env.SESSION_SECRET || '';
  return [
    { label: 'Password sign-in', required: true, ok: !oidc.isConfigured() || settings.password_login !== 'false',
      hint: 'Password sign-in is switched off. Turn on "Allow password sign-in" in System Settings below, or people can only sign in with SSO.' },
    { label: 'Session secret', required: true, ok: sessionSecret.length >= 32,
      hint: 'Set SESSION_SECRET to a long random value (at least 32 characters).' },
    { label: 'Upload encryption', required: true, ok: Boolean(process.env.UPLOADS_ENCRYPTION_KEY),
      hint: 'Set UPLOADS_ENCRYPTION_KEY so note images and files are encrypted at rest.' },
    { label: 'Backups', required: true, ok: null,
      hint: 'Backups run from cron on the host, so the app cannot check them. See the Backups section of the README.' },
    { label: 'Single sign-on', required: false, ok: oidc.isConfigured(),
      hint: 'Optional. Adds a single sign-on button to the login page: set OIDC_ISSUER, OIDC_CLIENT_ID and OIDC_CLIENT_SECRET (OIDC_REDIRECT_URI only to override the default).' },
    { label: 'AI features', required: false, ok: ai.isConfigured(),
      hint: 'Optional. Set AI_PROVIDER and AI_API_KEY, or AI_BASE_URL for a local model, to enable Capture processing and AI Chat.' },
    { label: 'Email reminders', required: false, ok: emailService.isConfigured(),
      hint: 'Optional. Set the SMTP_* variables to send reminder emails.' },
    { label: 'Push notifications', required: false, ok: Boolean(process.env.PUSHOVER_APP_TOKEN) || ntfy.isConfigured(),
      hint: 'Optional. Set PUSHOVER_APP_TOKEN, or NTFY_URL and NTFY_TOKEN.' },
    { label: 'Google Calendar', required: false, ok: Boolean(process.env.GOOGLE_CLIENT_ID),
      hint: 'Optional. Calendars can also connect over CalDAV without this.' },
  ];
}

const router = express.Router();
router.use(requireAdmin);

const PAGE_SIZE = 100;

async function getSettings() {
  const rows = await prisma.systemSetting.findMany();
  return Object.fromEntries(rows.map(r => [r.key, r.value]));
}

// ── Dashboard ──────────────────────────────────────────────────────────────
router.get('/', async (req, res, next) => {
  try {
    const [userCount, noteCount, taskCount, reminderCount, recentUsers] = await Promise.all([
      prisma.user.count(),
      prisma.note.count(),
      prisma.task.count(),
      prisma.reminder.count(),
      prisma.user.findMany({
        orderBy: { createdAt: 'desc' },
        take: 5,
        select: { id: true, username: true, displayName: true, email: true, role: true, createdAt: true },
      }),
    ]);

    const settings = await getSettings();
    const recentGravatars = Object.fromEntries(
      recentUsers.filter(u => u.email).map(u => [u.id, gravatarUrl(u.email)])
    );

    res.render('admin/index', {
      title: 'Admin',
      stats: { userCount, noteCount, taskCount, reminderCount },
      recentUsers,
      recentGravatars,
      settings,
      setup: setupChecklist(settings),
      oidcConfigured: oidc.isConfigured(),
      success: req.query.success || null,
      error:   req.query.error   || null,
    });
  } catch (err) { next(err); }
});

// ── Users list ─────────────────────────────────────────────────────────────
router.get('/users', async (req, res, next) => {
  try {
    const users = await prisma.user.findMany({
      orderBy: { createdAt: 'asc' },
      select: {
        id: true, username: true, displayName: true, email: true,
        role: true, createdAt: true, lastLoginAt: true, preferences: true,
        oidcSub: true, passwordHash: true,
        _count: { select: { notes: true, tasks: true } },
      },
    }).then(list => list.map(({ oidcSub, passwordHash, ...u }) => ({ ...u, ssoLinked: !!oidcSub, hasPassword: !!passwordHash })));
    const passwordLink = req.session.passwordLink
      ? { ...req.session.passwordLink, url: `${req.protocol}://${req.get('host')}${req.session.passwordLink.path}` } : null;
    delete req.session.passwordLink;
    const gravatars = Object.fromEntries(
      users.filter(u => u.email).map(u => [u.id, gravatarUrl(u.email)])
    );
    res.render('admin/users', {
      title: 'Admin — Users',
      users,
      gravatars,
      oidcConfigured: oidc.isConfigured(),
      passwordLink,
      success: req.query.success || null,
      error: req.query.error || null,
    });
  } catch (err) { next(err); }
});

// ── Create user ────────────────────────────────────────────────────────────
router.post('/users/create', async (req, res, next) => {
  try {
    const username    = (req.body.username    || '').trim().toLowerCase();
    const displayName = (req.body.displayName || '').trim();
    const email       = (req.body.email       || '').trim().toLowerCase() || null;
    const timezone    = (req.body.timezone    || 'America/New_York').trim();
    const role        = req.body.role === 'admin' ? 'admin' : 'user';
    const fail = msg => res.redirect(`/admin/users?error=${encodeURIComponent(msg)}`);

    if (!username) return fail('Username is required');
    if (!/^[a-z0-9_-]+$/.test(username)) {
      return fail('Username may only contain letters, numbers, underscores, and hyphens');
    }
    // No email: they sign in with a password, chosen from a one-time link shown below.
    // With an email: their first SSO sign-in also links to this account by email
    // (see the OIDC callback in routes/auth.js)
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return fail("That email address doesn't look right");

    const existing = await prisma.user.findUnique({ where: { username } });
    if (existing) return fail(`Username "${username}" is already taken`);
    if (email && await prisma.user.findFirst({ where: { email: { equals: email, mode: 'insensitive' } } })) {
      return fail(`Another account already uses ${email}`);
    }

    const ALL_MODULE_KEYS = [
      'dashboard','capture','notes','tasks','lists',
      'reminders','routines','calendar','ai','settings',
    ];

    const user = await prisma.user.create({
      data: {
        username,
        displayName: displayName || username,
        email,
        timezone,
        role,
        modules: {
          create: ALL_MODULE_KEYS.map(key => ({ moduleKey: key, enabled: true })),
        },
      },
    });

    log.info('admin', `User created: @${user.username}`, { targetUserId: user.id, by: req.user.id });
    // Shown once on the next page: the person opens it to choose their own password
    if (await passwords.passwordLoginEnabled()) {
      { const t = await passwords.issueToken(user.id, 'setup');
        req.session.passwordLink = { userId: user.id, name: user.displayName, path: `/auth/password/${t.token}`, code: t.code, username: user.username }; }
      log.info('admin', `Password setup link issued for @${user.username}`, { targetUserId: user.id, by: req.user.id });
    }
    res.redirect(`/admin/users?success=${encodeURIComponent(`User ${user.displayName} (@${user.username}) created`)}`);
  } catch (err) { next(err); }
});

// ── One-time link to choose a new password ─────────────────────────────────
// Admins never see or set anyone's password; the person opens the link and picks their own
router.post('/users/:id/password-link', async (req, res, next) => {
  try {
    // Whole numbers only: parseInt would read "1.5" or "1abc" as user 1
    const id = /^\d{1,9}$/.test(req.params.id) ? parseInt(req.params.id, 10) : null;
    const user = id ? await prisma.user.findUnique({ where: { id } }) : null;
    if (!user) return res.redirect('/admin/users?error=User+not+found');
    if (!(await passwords.passwordLoginEnabled())) return res.redirect('/admin/users?error=Password+sign-in+is+switched+off');
    const purpose = user.passwordHash ? 'reset' : 'setup';
    const t = await passwords.issueToken(user.id, purpose);
    req.session.passwordLink = { userId: user.id, name: user.displayName, path: `/auth/password/${t.token}`, code: t.code, username: user.username };
    log.info('admin', `Password ${purpose} link issued for @${user.username}`, { targetUserId: user.id, by: req.user.id });
    res.redirect('/admin/users');
  } catch (err) { next(err); }
});

// ── Toggle admin role ──────────────────────────────────────────────────────
router.post('/users/:id/toggle-admin', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id);
    if (id === req.user.id) {
      return res.redirect('/admin/users?error=Cannot+change+your+own+role');
    }
    const user = await prisma.user.findUnique({ where: { id } });
    if (!user) return res.redirect('/admin/users?error=User+not+found');
    const newRole = user.role === 'admin' ? 'user' : 'admin';
    await prisma.user.update({ where: { id }, data: { role: newRole } });
    log.info('admin', `Role changed: @${user.username} → ${newRole}`, { targetUserId: id, by: req.user.id });
    res.redirect(`/admin/users?success=${encodeURIComponent(`${user.displayName} is now ${newRole}`)}`);
  } catch (err) { next(err); }
});

// ── Delete user ────────────────────────────────────────────────────────────
router.post('/users/:id/delete', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id);
    if (id === req.user.id) {
      return res.redirect('/admin/users?error=Cannot+delete+your+own+account');
    }
    const user = await prisma.user.findUnique({ where: { id } });
    if (!user) return res.redirect('/admin/users?error=User+not+found');
    await uploads.removeUserFiles(id);
    await prisma.user.delete({ where: { id } });
    log.warn('admin', `User deleted: @${user.username}`, { targetUserId: id, by: req.user.id });
    res.redirect(`/admin/users?success=${encodeURIComponent(`${user.displayName} deleted`)}`);
  } catch (err) { next(err); }
});

// ── System settings ────────────────────────────────────────────────────────
router.post('/settings', async (req, res, next) => {
  try {
    const { sso_create_accounts, password_login, maintenance_message } = req.body;
    const updates = [
      { key: 'sso_create_accounts', value: sso_create_accounts === 'on' ? 'true' : 'false' },
      { key: 'password_login', value: password_login === 'on' || !oidc.isConfigured() ? 'true' : 'false' },
      { key: 'maintenance_message', value: (maintenance_message || '').trim() },
    ];
    // Replaced by sso_create_accounts; the old toggle never controlled anything
    await prisma.systemSetting.deleteMany({ where: { key: 'allow_registration' } });
    for (const u of updates) {
      await prisma.systemSetting.upsert({
        where:  { key: u.key },
        update: { value: u.value },
        create: { key: u.key, value: u.value },
      });
    }
    log.info('admin', 'System settings updated', { by: req.user.id, keys: updates.map(u => u.key) });
    res.redirect('/admin?success=System+settings+saved');
  } catch (err) { next(err); }
});

// ── Logs viewer ────────────────────────────────────────────────────────────
router.get('/logs', async (req, res, next) => {
  try {
    const { level, category, q, page = '1' } = req.query;
    const pageNum = Math.max(1, parseInt(page) || 1);

    const where = {};
    if (level)    where.level    = level;
    if (category) where.category = category;
    if (q)        where.message  = { contains: q, mode: 'insensitive' };

    const [total, logs] = await Promise.all([
      prisma.appLog.count({ where }),
      prisma.appLog.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take: PAGE_SIZE,
        skip: (pageNum - 1) * PAGE_SIZE,
      }),
    ]);

    const categories = await prisma.appLog.findMany({
      distinct: ['category'],
      select: { category: true },
      orderBy: { category: 'asc' },
    });

    res.render('admin/logs', {
      title: 'Admin — Logs',
      logs,
      total,
      page: pageNum,
      pageSize: PAGE_SIZE,
      totalPages: Math.ceil(total / PAGE_SIZE),
      filters: { level: level || '', category: category || '', q: q || '' },
      categories: categories.map(c => c.category),
      success: req.query.success || null,
      error:   req.query.error   || null,
    });
  } catch (err) { next(err); }
});

// ── Logs export (CSV) ──────────────────────────────────────────────────────
router.get('/logs/export', async (req, res, next) => {
  try {
    const { level, category, q } = req.query;
    const where = {};
    if (level)    where.level    = level;
    if (category) where.category = category;
    if (q)        where.message  = { contains: q, mode: 'insensitive' };

    const rows = await prisma.appLog.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: 50000,
    });

    const escape = s => `"${String(s ?? '').replace(/"/g, '""')}"`;
    const lines = [
      'timestamp,level,category,message,meta',
      ...rows.map(r => [
        r.createdAt.toISOString(),
        r.level,
        r.category,
        escape(r.message),
        r.meta ? escape(JSON.stringify(r.meta)) : '',
      ].join(',')),
    ];

    log.info('admin', `Logs exported (${rows.length} rows)`, { by: req.user.id });
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="obelo-logs.csv"');
    res.send(lines.join('\n'));
  } catch (err) { next(err); }
});

// ── Logs clear ─────────────────────────────────────────────────────────────
router.post('/logs/clear', async (req, res, next) => {
  try {
    const { count } = await prisma.appLog.deleteMany({});
    log.warn('admin', `Logs cleared (${count} entries deleted)`, { by: req.user.id });
    res.redirect('/admin/logs?success=' + encodeURIComponent(`${count} log entries cleared`));
  } catch (err) { next(err); }
});

module.exports = router;
