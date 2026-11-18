// A user's signed-in sessions ("Signed-in devices" in Settings). Sessions live in the
// connect-pg-simple `sessions` table (sid, sess json, expire). Every query is scoped to the
// userId inside the session data, so one user can never see or end another user's sessions.
// Raw session IDs never leave the server: the browser only sees sessionKey(sid).

const crypto = require('crypto');
const prisma = require('./prisma');

const SEEN_EVERY_MS = 5 * 60 * 1000; // how often lastSeenAt is refreshed (each refresh is a store write)

function sessionKey(sid) {
  return crypto.createHash('sha256').update(sid).digest('hex').slice(0, 16);
}

// "Chrome on Mac", "Safari on iPhone"; good enough to recognise your own devices
function deviceName(ua) {
  if (!ua) return 'Unknown device';
  const os =
    /iPhone/.test(ua)                 ? 'iPhone'   :
    /iPad/.test(ua)                   ? 'iPad'     :
    /Android/.test(ua)                ? 'Android'  :
    /CrOS/.test(ua)                   ? 'ChromeOS' :
    /Macintosh|Mac OS X/.test(ua)     ? 'Mac'      :
    /Windows/.test(ua)                ? 'Windows'  :
    /Linux/.test(ua)                  ? 'Linux'    : null;
  const browser =
    /(Obelo|vibeTrack)-iOS\//.test(ua)        ? 'Obelo app' :
    /Edg(e|A|iOS)?\//.test(ua)        ? 'Edge'     :
    /OPR\/|Opera/.test(ua)            ? 'Opera'    :
    /Firefox\/|FxiOS\//.test(ua)      ? 'Firefox'  :
    /SamsungBrowser\//.test(ua)       ? 'Samsung Internet' :
    /Chrome\/|CriOS\//.test(ua)       ? 'Chrome'   :
    /Version\/.*Safari\//.test(ua)    ? 'Safari'   :
    // iOS in-app web views have no Safari token
    /AppleWebKit/.test(ua) && /iPhone|iPad/.test(ua) ? 'App' : null;
  if (browser && os) return `${browser} on ${os}`;
  return browser || os || 'Unknown device';
}

// Call right after a sign-in's session.regenerate()
function recordDevice(session, req) {
  session.userAgent  = (req.get('user-agent') || '').slice(0, 300);
  session.ip         = req.ip; // display only; resolved through `trust proxy`, never used for access decisions
  session.lastSeenAt = Date.now();
}

// Middleware: keeps lastSeenAt roughly current without saving the session on every request
function trackActivity(req, res, next) {
  const s = req.session;
  if (s?.userId && Date.now() - (s.lastSeenAt || 0) > SEEN_EVERY_MS) s.lastSeenAt = Date.now();
  next();
}

async function listForUser(userId, currentSid) {
  const rows = await prisma.$queryRaw`
    SELECT sid, sess FROM sessions
    WHERE sess->>'userId' = ${String(userId)} AND expire > now()`;
  return rows
    .map(({ sid, sess }) => ({
      key:        sessionKey(sid),
      current:    sid === currentSid,
      device:     deviceName(sess.userAgent),
      ip:         sess.ip || null,
      signedInAt: sess.signedInAt ? new Date(sess.signedInAt) : null,
      lastSeenAt: sess.lastSeenAt ? new Date(sess.lastSeenAt) : null,
    }))
    .sort((a, b) => (b.current - a.current) || ((b.lastSeenAt || 0) - (a.lastSeenAt || 0)));
}

// Ends the user's sessions whose key is in `keys` (or all of them when keys is null), never
// the current one. Returns how many were ended.
async function endForUser(userId, currentSid, keys = null) {
  const rows = await prisma.$queryRaw`
    SELECT sid FROM sessions WHERE sess->>'userId' = ${String(userId)}`;
  const sids = rows
    .map(r => r.sid)
    .filter(sid => sid !== currentSid && (!keys || keys.includes(sessionKey(sid))));
  if (!sids.length) return 0;
  // userId is checked again in the DELETE itself
  return prisma.$executeRaw`
    DELETE FROM sessions WHERE sid = ANY(${sids}) AND sess->>'userId' = ${String(userId)}`;
}

module.exports = { sessionKey, deviceName, recordDevice, trackActivity, listForUser, endForUser };
