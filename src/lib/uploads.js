const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// All user-uploaded files (note attachments, avatars) go through here.
// When UPLOADS_ENCRYPTION_KEY is set, files are encrypted at rest with AES-256-GCM, so the
// storage location (a Docker volume or a NAS share) only ever holds ciphertext. The key
// lives in the server's .env, so this protects against anyone who can read the storage but
// not the server — it does not hide files from whoever runs the server.
//
// Encrypted file layout: "VTE1" magic (4B) | IV (12B) | auth tag (16B) | ciphertext.
// The file's path relative to UPLOAD_BASE is bound in as additional authenticated data,
// so an encrypted file can't be swapped in under another user's name.

const UPLOAD_BASE = path.resolve(process.env.UPLOAD_PATH || path.join(__dirname, '../../uploads'));
const MAGIC = Buffer.from('VTE1');
const ALGO = 'aes-256-gcm';

let cachedKey;
function getKey() {
  if (cachedKey !== undefined) return cachedKey;
  const secret = (process.env.UPLOADS_ENCRYPTION_KEY || '').trim();
  cachedKey = secret
    ? Buffer.from(crypto.hkdfSync('sha256', secret, Buffer.alloc(0), 'vibetrack-uploads-v1', 32))
    : null;
  return cachedKey;
}

function isEncryptionEnabled() {
  return getKey() !== null;
}

// Resolves a path under UPLOAD_BASE, refusing anything that escapes it
function resolve(...parts) {
  const full = path.resolve(UPLOAD_BASE, ...parts.map(String));
  if (!full.startsWith(UPLOAD_BASE + path.sep)) throw new Error('Invalid upload path');
  return full;
}

// Keeps only a short alphanumeric extension from a client-supplied filename
function safeExt(originalName, fallback = '.jpg') {
  const ext = path.extname(originalName || '').toLowerCase();
  return /^\.[a-z0-9]{1,5}$/.test(ext) ? ext : fallback;
}

const noteDir    = noteId => resolve('notes', noteId);
const notePath   = (noteId, filename) => resolve('notes', noteId, path.basename(filename));
const avatarPath = (userId, ext) => resolve('avatars', `${userId}${ext}`);

function encrypt(plain, aad) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ALGO, getKey(), iv);
  cipher.setAAD(aad);
  const enc = Buffer.concat([cipher.update(plain), cipher.final()]);
  return Buffer.concat([MAGIC, iv, cipher.getAuthTag(), enc]);
}

function decrypt(data, aad) {
  const key = getKey();
  if (!key) throw new Error('File is encrypted but UPLOADS_ENCRYPTION_KEY is not set');
  const iv  = data.subarray(4, 16);
  const tag = data.subarray(16, 32);
  const decipher = crypto.createDecipheriv(ALGO, key, iv);
  decipher.setAAD(aad);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data.subarray(32)), decipher.final()]);
}

const aadFor = fullPath => Buffer.from(path.relative(UPLOAD_BASE, fullPath).split(path.sep).join('/'));
const isEncrypted = data => data.length >= 32 && data.subarray(0, 4).equals(MAGIC);

// Write to a temp file then rename, so a crash or network hiccup never leaves a partial file
async function writeFile(fullPath, buffer) {
  await fs.promises.mkdir(path.dirname(fullPath), { recursive: true });
  const data = isEncryptionEnabled() ? encrypt(buffer, aadFor(fullPath)) : buffer;
  const tmp = `${fullPath}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  await fs.promises.writeFile(tmp, data);
  await fs.promises.rename(tmp, fullPath);
}

// Returns the plaintext contents, or null if the file doesn't exist.
// Files written before encryption was enabled are returned as-is.
async function readFile(fullPath) {
  let data;
  try {
    data = await fs.promises.readFile(fullPath);
  } catch (err) {
    if (err.code === 'ENOENT') return null;
    throw err;
  }
  return isEncrypted(data) ? decrypt(data, aadFor(fullPath)) : data;
}

async function remove(fullPath) {
  await fs.promises.rm(fullPath, { force: true, recursive: true });
}

// Encrypts any plaintext files already in storage (used after enabling encryption)
async function encryptExisting(dir = UPLOAD_BASE) {
  const counts = { encrypted: 0, skipped: 0 };
  let entries;
  try {
    entries = await fs.promises.readdir(dir, { withFileTypes: true });
  } catch (err) {
    if (err.code === 'ENOENT') return counts;
    throw err;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const sub = await encryptExisting(full);
      counts.encrypted += sub.encrypted;
      counts.skipped   += sub.skipped;
    } else if (entry.isFile() && !entry.name.endsWith('.tmp')) {
      const data = await fs.promises.readFile(full);
      if (isEncrypted(data)) { counts.skipped++; continue; }
      await writeFile(full, data);
      counts.encrypted++;
    }
  }
  return counts;
}

// Deletes every file belonging to a user; call before deleting the user row
async function removeUserFiles(userId) {
  const prisma = require('./prisma');
  const [user, notes] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { preferences: true } }),
    prisma.note.findMany({ where: { userId }, select: { id: true } }),
  ]);
  for (const n of notes) await remove(noteDir(n.id));
  const ext = user?.preferences?.avatarExt;
  if (ext) await remove(avatarPath(userId, ext));
}

// Headers for serving an uploaded file. The type comes from the uploader's browser, so an SVG
// (or anything mislabelled) must never be able to run script on this origin if opened directly.
function setServeHeaders(res) {
  res.set({
    'Cache-Control': 'private, max-age=86400',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': "default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'; sandbox",
  });
}

function describe() {
  return `Uploads: ${UPLOAD_BASE} (${isEncryptionEnabled() ? 'encrypted at rest' : 'NOT encrypted — set UPLOADS_ENCRYPTION_KEY'})`;
}

module.exports = {
  UPLOAD_BASE,
  safeExt, noteDir, notePath, avatarPath,
  writeFile, readFile, remove,
  removeUserFiles, encryptExisting, isEncryptionEnabled, setServeHeaders, describe,
};
