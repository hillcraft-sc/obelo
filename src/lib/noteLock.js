const crypto = require('crypto');

const ALGO = 'aes-256-gcm';

function deriveKey(userId, saltHex) {
  const secret = process.env.NOTE_LOCK_SECRET || process.env.SESSION_SECRET;
  return crypto.createHmac('sha256', secret)
    .update(`note-lock:${userId}:${saltHex}`)
    .digest(); // 32 bytes → AES-256 key
}

// Returns base64 string: [12B iv][16B auth tag][ciphertext]
function encrypt(plaintext, userId, saltHex) {
  const key = deriveKey(userId, saltHex);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ALGO, key, iv);
  const enc = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, enc]).toString('base64');
}

// Throws on corrupted data (auth tag mismatch)
function decrypt(ciphertext, userId, saltHex) {
  const buf = Buffer.from(ciphertext, 'base64');
  const iv = buf.subarray(0, 12);
  const tag = buf.subarray(12, 28);
  const enc = buf.subarray(28);
  const key = deriveKey(userId, saltHex);
  const decipher = crypto.createDecipheriv(ALGO, key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(enc), decipher.final()]).toString('utf8');
}

module.exports = { encrypt, decrypt };
