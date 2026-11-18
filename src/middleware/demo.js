const { isDemo, DEMO_MESSAGE, DEMO_PASSWORD_MESSAGE } = require('../lib/demo');

// Where each blocked area is, with the path it returns to in the browser (fixed paths only).
// The app's /api/v1 paths are the same with that prefix. Reading (GET) is allowed, so the screens still open.
const BLOCKED = [
  { prefix: '/settings/notifications', home: '/settings?tab=notifications', anyMethod: false },
  { prefix: '/calendar/sources', home: '/calendar/sources', anyMethod: false },
  { prefix: '/calendar/auth/google', home: '/calendar/sources', anyMethod: true },
  // Everyone signs in with the one demo account, so its password can't change
  { prefix: '/settings/password', home: '/settings?tab=account', anyMethod: false, message: DEMO_PASSWORD_MESSAGE },
];

function demoGuard(req, res, next) {
  if (!isDemo()) return next();
  const path = req.path.replace(/^\/api\/v1(?=\/)/, '');
  const rule = BLOCKED.find((r) => path.startsWith(r.prefix));
  if (!rule || (!rule.anyMethod && req.method === 'GET')) return next();
  const message = rule.message || DEMO_MESSAGE;
  if (req.path.startsWith('/api/v1')) return res.status(403).json({ error: message });
  const sep = rule.home.includes('?') ? '&' : '?';
  return res.redirect(`${rule.home}${sep}error=${encodeURIComponent(message)}`);
}

module.exports = { demoGuard };
