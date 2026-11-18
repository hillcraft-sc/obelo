// Sign-in lifetime: a session ends after SESSION_IDLE_HOURS without use (rolling cookie and
// store expiry) or SESSION_MAX_DAYS after sign-in, whichever comes first. Activity never
// extends the absolute limit: it's measured from signedInAt, which is only set at sign-in.
// iOS app sign-ins (session.app) use APP_SESSION_DAYS for both limits instead: the phone is
// already locked by Face ID or a passcode, and signing in again every week was a chore.

const HOUR = 60 * 60 * 1000;
const DAY  = 24 * HOUR;

function positive(value, fallback) {
  const n = parseFloat(value);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

const idleMs = positive(process.env.SESSION_IDLE_HOURS, 12) * HOUR;
const maxMs  = positive(process.env.SESSION_MAX_DAYS, 7) * DAY;
const appMs  = positive(process.env.APP_SESSION_DAYS, 90) * DAY;

const idleFor = (session) => (session.app ? appMs : idleMs);
const maxFor  = (session) => (session.app ? appMs : maxMs);

// Call right after a sign-in's session.regenerate(); { app: true } for the iOS app
function markSignedIn(session, { app = false } = {}, now = Date.now()) {
  session.signedInAt = now;
  if (app) session.app = true;
  session.cookie.maxAge = idleFor(session);
}

// When the session must end regardless of activity. Sessions from before this existed have no
// signedInAt; they get one full maximum from the first request that sees them (legacyUntil).
function deadline(session, now = Date.now()) {
  if (session.signedInAt) return session.signedInAt + maxFor(session);
  if (!session.legacyUntil) session.legacyUntil = now + maxFor(session);
  return session.legacyUntil;
}

function describe() {
  return `Sessions: sign out after ${idleMs / HOUR}h idle, ${maxMs / DAY}d max (iOS app: ${appMs / DAY}d)`;
}

// Middleware: runs after express-session, before loadUser
function enforce(req, res, next) {
  const session = req.session;
  if (!session?.userId) return next();

  const now = Date.now();
  const remaining = deadline(session, now) - now;
  if (remaining <= 0) {
    return session.destroy(() => (req.originalUrl.startsWith('/api/')
      ? res.status(401).json({ error: 'Signed out' })
      : res.redirect('/auth/login')));
  }
  // Rolling idle expiry, capped at the deadline. Setting maxAge every request also moves
  // sessions created with the old 30-day cookie onto the new idle timeout.
  session.cookie.maxAge = Math.min(idleFor(session), remaining);
  next();
}

module.exports = { idleMs, maxMs, markSignedIn, deadline, describe, enforce };
