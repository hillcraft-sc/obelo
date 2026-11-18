const express = require('express');
const crypto  = require('crypto');
const prisma  = require('../lib/prisma');
const log     = require('../services/logService');
const oidc    = require('../services/oidcService');
const { markSignedIn } = require('../lib/sessionLifetime');
const { recordDevice } = require('../lib/userSessions');
const appLogin = require('../lib/appLogin');
const passwords = require('../lib/passwords');
const userSessions = require('../lib/userSessions');
const { rateLimit } = require('express-rate-limit');

const router = express.Router();

// In production the session cookie is Secure, so over plain http:// the browser never keeps it
// and signing in silently does nothing. Say so, and refuse to sign in or create the first account.
const needsHttps = (req) => process.env.NODE_ENV === 'production' && !req.secure;
const HTTPS_MESSAGE = "This address isn't using HTTPS, so signing in can't work here. Open Obelo through your HTTPS address (your reverse proxy), or, to try it on a local network, set NODE_ENV=development in .env.";
router.use((req, res, next) => { res.locals.needsHttps = needsHttps(req); next(); });

function clientIp(req) {
  return req.headers['x-forwarded-for']?.split(',')[0].trim() || req.socket.remoteAddress;
}

// ── Login page ─────────────────────────────────────────────────────────────
// Username and password, plus the SSO button when SSO is configured. A server with no users
// yet goes to the one-time setup page instead.
async function renderLogin(res, error = null, extra = {}) {
  const oidcEnabled = oidc.isConfigured();
  const passwordEnabled = await passwords.passwordLoginEnabled();
  res.render('auth/login', {
    layout: 'layouts/auth',
    error: error || (!oidcEnabled && !passwordEnabled ? 'Sign-in is switched off on this server. Ask the admin.' : null),
    notice: null,
    username: '',
    oidcEnabled,
    passwordEnabled,
    ...extra,
  });
}

const passwordLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, max: 20, standardHeaders: true, legacyHeaders: false,
  message: 'Too many attempts — please try again later.',
  skip: () => process.env.NODE_ENV === 'development',
});

router.get('/login', async (req, res, next) => {
  try {
    if (req.session.userId) return res.redirect('/');
    if (await prisma.user.count() === 0) return res.redirect('/auth/setup');
    const notice = req.query.reset === '1' ? 'Password saved. You can sign in now.' : null;
    await renderLogin(res, null, { notice });
  } catch (err) { next(err); }
});

router.post('/login', passwordLimiter, async (req, res, next) => {
  const ip = clientIp(req);
  try {
    if (needsHttps(req)) return renderLogin(res, HTTPS_MESSAGE, { username: String(req.body.username || '').slice(0, 254) });
    const username = String(req.body.username || '').trim().slice(0, 254);
    if (!(await passwords.passwordLoginEnabled())) {
      return renderLogin(res, 'Password sign-in is switched off on this server.', { username });
    }
    const user = await passwords.authenticate(username, req.body.password);
    if (!user) {
      log.warn('auth', 'Password sign-in failed', { ip });
      return renderLogin(res, 'Wrong username or password.', { username });
    }
    req.session.regenerate((regenErr) => {
      if (regenErr) return next(regenErr);
      req.session.userId = user.id;
      markSignedIn(req.session);
      recordDevice(req.session, req);
      req.session.save(async () => {
        await prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } }).catch(() => {});
        log.info('auth', `Password login: @${user.username}`, { userId: user.id, ip });
        res.redirect('/');
      });
    });
  } catch (err) { next(err); }
});

// ── Choose a password with a setup code (same as the apps' "Have a setup code?") ─
router.get('/code', async (req, res, next) => {
  try {
    if (req.session.userId) return res.redirect('/');
    res.render('auth/code', { layout: 'layouts/auth', valid: await passwords.passwordLoginEnabled(), error: null, form: {}, minLength: passwords.MIN_LENGTH });
  } catch (err) { next(err); }
});

router.post('/code', passwordLimiter, async (req, res, next) => {
  try {
    const form = { username: String(req.body.username || '').trim().slice(0, 254), code: String(req.body.code || '').trim().slice(0, 20) };
    const again = (error) => res.status(400).render('auth/code', { layout: 'layouts/auth', valid: true, error, form, minLength: passwords.MIN_LENGTH });
    if (!(await passwords.passwordLoginEnabled())) return again('Password sign-in is switched off on this server.');
    if (req.body.password !== req.body.confirm) return again("The two passwords don't match");
    const out = await passwords.redeemCode(form.username, form.code, req.body.password);
    if (out.error) return again(out.error);
    const ended = await userSessions.endForUser(out.user.id, null);
    log.info('auth', `Password set from a setup code: @${out.user.username}`, { userId: out.user.id, ended });
    res.redirect('/auth/login?reset=1');
  } catch (err) { next(err); }
});

// ── First-run setup: the first account, an admin ──────────────────────────
// Only exists while the server has no users at all
router.get('/setup', async (req, res, next) => {
  try {
    if (await prisma.user.count() > 0) return res.status(404).render('error', { layout: 'layouts/auth', title: 'Not Found', error: { status: 404, message: 'Page not found.' } });
    res.render('auth/setup', { layout: 'layouts/auth', error: null, form: {}, minLength: passwords.MIN_LENGTH });
  } catch (err) { next(err); }
});

router.post('/setup', passwordLimiter, async (req, res, next) => {
  try {
    const form = {
      username: String(req.body.username || '').trim().toLowerCase(),
      displayName: String(req.body.displayName || '').trim().slice(0, 100),
      email: String(req.body.email || '').trim().toLowerCase().slice(0, 254),
    };
    const fail = (error) => res.status(400).render('auth/setup', { layout: 'layouts/auth', error, form, minLength: passwords.MIN_LENGTH });

    if (needsHttps(req)) return fail(HTTPS_MESSAGE);

    if (!/^[a-z0-9_-]{1,30}$/.test(form.username)) return fail('Username: 1–30 letters, numbers, underscores or hyphens');
    if (form.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email)) return fail('That email address doesn\'t look right');
    if (req.body.password !== req.body.confirm) return fail('The two passwords don\'t match');
    const bad = passwords.checkNewPassword(req.body.password);
    if (bad) return fail(bad);
    const passwordHash = await passwords.hashPassword(req.body.password);

    // The lock makes "no users yet" and "create the first one" a single step, so two people
    // submitting at once can't both become admin
    const user = await prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(7340211)`;
      if (await tx.user.count() > 0) return null;
      return tx.user.create({
        data: { username: form.username, displayName: form.displayName || form.username,
                email: form.email || null, role: 'admin', passwordHash },
      });
    });
    if (!user) return res.status(404).render('error', { layout: 'layouts/auth', title: 'Not Found', error: { status: 404, message: 'Page not found.' } });

    log.info('auth', `First-run setup: admin @${user.username} created`, { userId: user.id, ip: clientIp(req) });
    req.session.regenerate((regenErr) => {
      if (regenErr) return next(regenErr);
      req.session.userId = user.id;
      markSignedIn(req.session);
      recordDevice(req.session, req);
      req.session.save(() => res.redirect('/'));
    });
  } catch (err) { next(err); }
});

// ── Choose a password from a one-time link (new account or reset) ─────────
router.get('/password/:token', async (req, res, next) => {
  try {
    const row = await passwords.findToken(req.params.token);
    res.render('auth/password', {
      layout: 'layouts/auth', valid: !!row && await passwords.passwordLoginEnabled(),
      error: null, minLength: passwords.MIN_LENGTH, token: req.params.token,
      name: row?.user.displayName || '', isNew: row?.purpose === 'setup',
    });
  } catch (err) { next(err); }
});

router.post('/password/:token', passwordLimiter, async (req, res, next) => {
  try {
    const again = async (error) => {
      const row = await passwords.findToken(req.params.token);
      res.status(400).render('auth/password', {
        layout: 'layouts/auth', valid: !!row, error, minLength: passwords.MIN_LENGTH,
        token: req.params.token, name: row?.user.displayName || '', isNew: row?.purpose === 'setup',
      });
    };
    if (!(await passwords.passwordLoginEnabled())) return again('Password sign-in is switched off on this server.');
    if (req.body.password !== req.body.confirm) return again('The two passwords don\'t match');
    const out = await passwords.redeemToken(req.params.token, req.body.password);
    if (out.error) return again(out.error);
    // A reset may be because someone else had the old password: end every session
    const ended = await userSessions.endForUser(out.user.id, null);
    log.info('auth', `Password set from a link: @${out.user.username}`, { userId: out.user.id, ended });
    res.redirect('/auth/login?reset=1');
  } catch (err) { next(err); }
});

// ── Logout ────────────────────────────────────────────────────────────────
router.post('/logout', (req, res) => {
  const userId = req.session.userId;
  const username = req.user?.username;
  req.session.destroy(() => {
    log.info('auth', `Logout: @${username || '?'}`, { userId });
    res.redirect('/auth/login');
  });
});

// ── OIDC — start ──────────────────────────────────────────────────────────
router.get('/oidc', async (req, res, next) => {
  if (!oidc.isConfigured()) return res.redirect('/auth/login');
  try {
    const state = crypto.randomBytes(16).toString('hex');
    const nonce = crypto.randomBytes(16).toString('hex');
    req.session.oidcState = state;
    req.session.oidcNonce = nonce;
    // Started from the iOS app: the callback hands the app a one-time code instead of signing in here
    req.session.appLogin = req.query.client === 'ios';
    await new Promise((resolve, reject) =>
      req.session.save(err => (err ? reject(err) : resolve()))
    );
    const url = await oidc.buildAuthUrl(state, nonce);
    log.info('auth', 'OIDC flow started', { ip: clientIp(req) });
    res.redirect(url);
  } catch (err) {
    log.error('auth', `OIDC start failed: ${err.message}`);
    next(err);
  }
});

// ── OIDC — callback ───────────────────────────────────────────────────────
router.get('/oidc/callback', async (req, res, next) => {
  if (!oidc.isConfigured()) return res.redirect('/auth/login');
  const ip = clientIp(req);

  try {
    const { code, state, error, error_description } = req.query;

    if (error) {
      log.warn('auth', `OIDC provider error: ${error}`, { ip, description: error_description });
      return renderLogin(res, 'Authentication failed — the provider rejected the request.');
    }

    if (!code || state !== req.session.oidcState) {
      log.warn('auth', 'OIDC state mismatch — possible CSRF or expired session', { ip });
      return renderLogin(res, 'Authentication failed — please try again.');
    }

    const tokens   = await oidc.exchangeCode(code);
    const userInfo = await oidc.getUserInfo(tokens.access_token);

    if (!userInfo.nonce || userInfo.nonce !== req.session.oidcNonce) {
      log.warn('auth', 'OIDC nonce missing or mismatch — possible token replay', { ip });
      return renderLogin(res, 'Authentication failed — please try again.');
    }

    const sub         = userInfo.sub;
    const email       = userInfo.email || null;
    const displayName = userInfo.name || userInfo.preferred_username || email?.split('@')[0] || sub;
    const rawUsername = (userInfo.preferred_username || email?.split('@')[0] || sub)
      .replace(/[^a-zA-Z0-9_-]/g, '_')
      .slice(0, 30);

    // 1. Look up by OIDC subject
    let user = await prisma.user.findUnique({ where: { oidcSub: sub } });

    // 2. Match by email and link
    // Case-insensitive: identity providers and admins don't always agree on capitalisation
    if (!user && email) {
      user = await prisma.user.findFirst({ where: { email: { equals: email, mode: 'insensitive' } } });
      if (user) {
        await prisma.user.update({ where: { id: user.id }, data: { oidcSub: sub } });
        log.info('auth', `OIDC linked to existing account @${user.username}`, { userId: user.id });
      }
    }

    // 3. Create new user — only if the admin allows it (Admin → System Settings, off by default)
    if (!user) {
      const setting = await prisma.systemSetting.findUnique({ where: { key: 'sso_create_accounts' } });
      if (setting?.value !== 'true') {
        log.warn('auth', 'OIDC sign-in refused: no matching account and SSO account creation is off',
          { ip, email, preferredUsername: userInfo.preferred_username || null });
        return renderLogin(res, "There's no Obelo account for your sign-in yet. Ask the admin to create one using the same email address.");
      }
      let username = rawUsername;
      let suffix   = 1;
      while (await prisma.user.findFirst({ where: { username } })) {
        username = `${rawUsername}_${suffix++}`;
      }
      user = await prisma.user.create({
        data: { username, displayName, email, oidcSub: sub },
      });
      log.info('auth', `New user created via OIDC: @${user.username}`, { userId: user.id });
    }

    // iOS app sign-in: hand the app a one-time code; this browser session stays signed out
    if (req.session.appLogin) {
      delete req.session.oidcState;
      delete req.session.oidcNonce;
      delete req.session.appLogin;
      log.info('auth', `OIDC app sign-in code issued: @${user.username}`, { userId: user.id, ip });
      return req.session.save(() => res.redirect(appLogin.callbackUrl({ code: appLogin.issueCode(user.id) })));
    }

    // Regenerate session ID after auth to prevent session fixation attacks
    const userId = user.id;
    const username = user.username;
    req.session.regenerate((regenErr) => {
      if (regenErr) {
        log.error('auth', `OIDC session regeneration failed: ${regenErr.message}`, { ip });
        return next(regenErr);
      }
      req.session.userId = userId;
      markSignedIn(req.session);
      recordDevice(req.session, req);
      req.session.save(async () => {
        await prisma.user.update({ where: { id: userId }, data: { lastLoginAt: new Date() } }).catch(() => {});
        log.info('auth', `OIDC login: @${username}`, { userId, ip });
        res.redirect('/');
      });
    });
  } catch (err) {
    log.error('auth', `OIDC callback error: ${err.message}`, { ip });
    next(err);
  }
});

module.exports = router;
