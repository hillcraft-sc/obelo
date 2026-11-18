// Sign-in for the native iOS app. The app runs the normal SSO flow in a system auth sheet
// (/auth/oidc?client=ios); instead of signing that browser in, the callback hands the app a
// short-lived one-time code through the obelo:// URL scheme. The app trades the code for an
// ordinary session (POST /api/v1/auth/exchange), so the app's sign-in follows the same idle and
// absolute limits as the web and shows up under Settings → Signed-in devices.
//
// Codes live in memory: they last two minutes, work once, and only their hash is kept.

const crypto = require('crypto');

const CODE_TTL_MS = 2 * 60 * 1000;
const APP_CALLBACK = 'obelo://auth';

const pending = new Map(); // sha256(code) → { userId, expires }

const hash = (code) => crypto.createHash('sha256').update(code).digest('hex');

function sweep(now = Date.now()) {
  for (const [key, entry] of pending) if (entry.expires <= now) pending.delete(key);
}

function issueCode(userId) {
  sweep();
  const code = crypto.randomBytes(32).toString('base64url');
  pending.set(hash(code), { userId, expires: Date.now() + CODE_TTL_MS });
  return code;
}

// Returns the userId for a valid code and burns it, or null
function redeemCode(code) {
  if (typeof code !== 'string' || code.length < 20 || code.length > 100) return null;
  sweep();
  const key = hash(code);
  const entry = pending.get(key);
  if (!entry) return null;
  pending.delete(key);
  return entry.userId;
}

function callbackUrl(params) {
  return `${APP_CALLBACK}?${new URLSearchParams(params)}`;
}

module.exports = { issueCode, redeemCode, callbackUrl };
