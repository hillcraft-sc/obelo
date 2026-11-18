// CSRF protection for the web UI: one random token per session, sent back as the
// X-CSRF-Token header, a `_csrf` body field, or a `_csrf` query parameter (upload
// forms, whose body isn't parsed yet when this runs). The apps use /api/v1, which
// requires a custom header a cross-site page can't send, so it is exempt.
const crypto = require('crypto');

const SAFE = new Set(['GET', 'HEAD', 'OPTIONS']);

function tokenFor(req) {
  if (!req.session) return '';
  if (!req.session.csrfToken) req.session.csrfToken = crypto.randomBytes(32).toString('hex');
  return req.session.csrfToken;
}

function matches(sent, expected) {
  if (typeof sent !== 'string' || !expected) return false;
  const a = Buffer.from(sent), b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function csrf(req, res, next) {
  // Created only when a page renders it, so API calls and static files don't make sessions
  Object.defineProperty(res.locals, 'csrfToken', { configurable: true, enumerable: true, get: () => tokenFor(req) });
  if (SAFE.has(req.method) || req.path.startsWith('/api/v1/') || req.path === '/api/v1') return next();
  // The Shortcuts capture address is signed in by its Bearer token alone (a browser never adds that header by
  // itself, and the route ignores the session), so there is nothing here for a forged page to ride on.
  // Without this, every Shortcut got 403 from 3.46.9 on.
  if (req.path === '/capture/api' && /^Bearer\s+\S/i.test(req.get('authorization') || '')) return next();

  const sent = req.get('x-csrf-token') || req.body?._csrf || req.query?._csrf;
  if (matches(sent, req.session?.csrfToken)) return next();

  const wantsJson = req.is('json') || (req.get('accept') || '').includes('application/json') || req.get('hx-request');
  if (wantsJson) return res.status(403).json({ error: 'Your session expired. Reload the page and try again.' });
  return res.status(403).render('error', {
    layout: 'layouts/auth', // runs before the theme is loaded, so the plain layout
    title: 'Please reload', error: { message: 'Your session expired. Reload the page and try again.' },
  });
}

module.exports = csrf;
