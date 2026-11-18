// Password sign-in. The only place passwords are hashed, checked or chosen.
//
// - bcrypt (bcryptjs), cost 12. bcrypt only reads the first 72 bytes, so longer passwords are
//   refused rather than silently cut.
// - Unknown users and accounts without a password cost the same time as a wrong password, and
//   all three give the same answer.
// - One-time links ("setup" for a new account, "reset" for an existing one): 256-bit random,
//   only the SHA-256 is stored, single use, 24 hours.
// - Failed sign-ins are counted per account name in memory (a restart clears them); per-IP
//   limits sit in app.js and api.js.

const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const prisma = require('./prisma');
const oidc   = require('../services/oidcService');

const COST = 12;
const MIN_LENGTH = 10;
const MAX_BYTES = 72;
const TOKEN_TTL_MS = 24 * 60 * 60 * 1000;

const FAIL_LIMIT = 10;
const FAIL_WINDOW_MS = 15 * 60 * 1000;

// Compared against when there is nothing real to compare, so timing doesn't reveal accounts
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password', COST);

// Returns an error message, or null when the password is acceptable
function checkNewPassword(password) {
  if (typeof password !== 'string') return 'Enter a password';
  if (password.length < MIN_LENGTH) return `Use at least ${MIN_LENGTH} characters`;
  if (Buffer.byteLength(password, 'utf8') > MAX_BYTES) return 'That password is too long (72 bytes at most)';
  return null;
}

const hashPassword = (password) => bcrypt.hash(password, COST);

// ── Failed-attempt counting ────────────────────────────────────────────────
const failures = new Map(); // lowercased account name → { count, first }

function isLocked(name, now = Date.now()) {
  const f = failures.get(name);
  if (!f) return false;
  if (now - f.first > FAIL_WINDOW_MS) { failures.delete(name); return false; }
  return f.count >= FAIL_LIMIT;
}
function noteFailure(name, now = Date.now()) {
  const f = failures.get(name);
  if (!f || now - f.first > FAIL_WINDOW_MS) failures.set(name, { count: 1, first: now });
  else f.count++;
  if (failures.size > 5000) for (const [k, v] of failures) if (now - v.first > FAIL_WINDOW_MS) failures.delete(k);
}

// ── Setting: can people sign in with a password? ───────────────────────────
// On unless an admin turned it off. It can only be off while SSO is configured, so turning it
// off can never lock everyone out.
async function passwordLoginEnabled() {
  if (!oidc.isConfigured()) return true;
  const row = await prisma.systemSetting.findUnique({ where: { key: 'password_login' } });
  return row?.value !== 'false';
}

// ── Check a username (or email) and password. Returns the user or null. ─────
async function authenticate(identifier, password) {
  const name = String(identifier || '').trim().toLowerCase().slice(0, 254);
  const pw = typeof password === 'string' ? password : '';
  if (!name || !pw || Buffer.byteLength(pw, 'utf8') > 1024) { await bcrypt.compare('x', DUMMY_HASH); return null; }
  if (isLocked(name)) { await bcrypt.compare(pw, DUMMY_HASH); return null; }

  const user = await prisma.user.findFirst({
    where: { OR: [
      { username: { equals: name, mode: 'insensitive' } },
      { email:    { equals: name, mode: 'insensitive' } },
    ] },
  });
  const ok = await bcrypt.compare(pw, user?.passwordHash || DUMMY_HASH);
  if (!user?.passwordHash || !ok) { noteFailure(name); return null; }
  failures.delete(name);
  return user;
}

// Changes your own password. `current` is required when you already have one.
// Returns an error message or null.
async function changeOwnPassword(userId, current, next) {
  const bad = checkNewPassword(next);
  if (bad) return bad;
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) return 'Account not found';
  if (user.passwordHash) {
    const key = `change:${userId}`;
    if (isLocked(key)) return 'Too many wrong attempts. Try again in a few minutes';
    const ok = typeof current === 'string' && await bcrypt.compare(current, user.passwordHash);
    if (!ok) { noteFailure(key); return 'Your current password is wrong'; }
    failures.delete(key);
  }
  await prisma.user.update({ where: { id: userId }, data: { passwordHash: await hashPassword(next) } });
  return null;
}

// ── One-time links ──────────────────────────────────────────────────────────
const sha = (t) => crypto.createHash('sha256').update(t).digest('hex');

// Setup codes: 8 characters, no look-alikes (no 0/O, 1/I/L), shown as XXXX-XXXX. About 40 bits,
// so they are only ever checked together with the username, with the per-account lockout, and
// are stored as a bcrypt hash.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 8;
const CODE_COST = 10;
const DUMMY_CODE_HASH = bcrypt.hashSync('ABCDEFGH', CODE_COST);

function makeCode() {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i++) code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  return code;
}
const formatCode = (code) => `${code.slice(0, 4)}-${code.slice(4)}`;
// Forgiving typing: any case, with or without the dash or spaces
const normalizeCode = (raw) => String(raw || '').toUpperCase().replace(/[^A-Z0-9]/g, '');

// Issues a link token and a setup code for the user (older unused ones stop working).
// Either one sets the password, and using one burns both. Returns { token, code }.
async function issueToken(userId, purpose) {
  const token = crypto.randomBytes(32).toString('base64url');
  const code = makeCode();
  const codeHash = await bcrypt.hash(code, CODE_COST);
  await prisma.$transaction([
    prisma.passwordToken.deleteMany({ where: { userId, usedAt: null } }),
    prisma.passwordToken.create({
      data: { userId, purpose, tokenHash: sha(token), codeHash, expiresAt: new Date(Date.now() + TOKEN_TTL_MS) },
    }),
  ]);
  return { token, code: formatCode(code) };
}

// The unused, unexpired token row for this token string, with its user, or null
async function findToken(token) {
  if (typeof token !== 'string' || token.length < 20 || token.length > 100) return null;
  return prisma.passwordToken.findFirst({
    where: { tokenHash: sha(token), usedAt: null, expiresAt: { gt: new Date() } },
    include: { user: true },
  });
}

// Sets the password for a valid token and burns it. Returns { user } or { error }.
async function redeemToken(token, password) {
  const bad = checkNewPassword(password);
  if (bad) return { error: bad };
  const row = await findToken(token);
  if (!row) return { error: 'This link has expired or was already used. Ask your admin for a new one' };
  const passwordHash = await hashPassword(password);
  // updateMany on usedAt: null makes the burn atomic, so a double submit can't use it twice
  const burned = await prisma.passwordToken.updateMany({ where: { id: row.id, usedAt: null }, data: { usedAt: new Date() } });
  if (!burned.count) return { error: 'This link has expired or was already used. Ask your admin for a new one' };
  await prisma.user.update({ where: { id: row.userId }, data: { passwordHash } });
  return { user: row.user };
}

// Sets the password from a username and setup code (the apps' way in). Returns { user } or { error }.
const BAD_CODE = "That code didn't work. Check the username and code, or ask your admin for a new one";
async function redeemCode(identifier, rawCode, password) {
  const bad = checkNewPassword(password);
  if (bad) return { error: bad };
  const name = String(identifier || '').trim().toLowerCase().slice(0, 254);
  const code = normalizeCode(rawCode);
  const key = `code:${name}`;
  const fail = async () => { if (name) noteFailure(key); return { error: BAD_CODE }; };
  if (!name || code.length !== CODE_LENGTH || isLocked(key)) { await bcrypt.compare('ABCDEFGH', DUMMY_CODE_HASH); return { error: BAD_CODE }; }

  const user = await prisma.user.findFirst({
    where: { OR: [
      { username: { equals: name, mode: 'insensitive' } },
      { email:    { equals: name, mode: 'insensitive' } },
    ] },
  });
  const row = user && await prisma.passwordToken.findFirst({
    where: { userId: user.id, usedAt: null, codeHash: { not: null }, expiresAt: { gt: new Date() } },
    orderBy: { createdAt: 'desc' },
  });
  const ok = await bcrypt.compare(code, row?.codeHash || DUMMY_CODE_HASH);
  if (!row || !ok) return fail();

  const passwordHash = await hashPassword(password);
  const burned = await prisma.passwordToken.updateMany({ where: { id: row.id, usedAt: null }, data: { usedAt: new Date() } });
  if (!burned.count) return { error: BAD_CODE };
  await prisma.user.update({ where: { id: user.id }, data: { passwordHash } });
  failures.delete(key);
  return { user };
}

module.exports = {
  MIN_LENGTH, checkNewPassword, hashPassword, authenticate, changeOwnPassword,
  passwordLoginEnabled, issueToken, findToken, redeemToken, redeemCode,
};
