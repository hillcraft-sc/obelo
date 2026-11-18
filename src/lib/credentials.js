const crypto = require('crypto');

// Encryption for stored third-party credentials: CalDAV passwords and Google OAuth tokens.
//
// Format: "v2:" + base64( IV (12B) | GCM auth tag (16B) | ciphertext ), AES-256-GCM, so
// tampered or wrongly-keyed values fail loudly instead of decrypting to garbage.
// Key: HKDF from CREDENTIALS_ENCRYPTION_KEY, falling back to SESSION_SECRET.
//
// Values written before v2 ("ivhex:cipherhex", AES-256-CBC with a scrypt key from
// SESSION_SECRET) are still readable; upgradeStoredCredentials() re-encrypts them.

const PREFIX = 'v2:';

function hkdf(secret) {
  return Buffer.from(crypto.hkdfSync('sha256', secret, Buffer.alloc(0), 'vibetrack-credentials-v2', 32));
}

let cachedKeys;
function keys() {
  if (cachedKeys) return cachedKeys;
  const dedicated = (process.env.CREDENTIALS_ENCRYPTION_KEY || '').trim();
  const session   = process.env.SESSION_SECRET || '';
  const candidates = [dedicated, session].filter(Boolean);
  cachedKeys = {
    current:  hkdf(candidates[0] || 'vibetrack-default'),
    // Also accepted when reading, so setting CREDENTIALS_ENCRYPTION_KEY later doesn't lock
    // out credentials that were encrypted under SESSION_SECRET
    readable: [...new Set(candidates)].map(hkdf),
    legacy:   crypto.scryptSync(session || 'vibetrack-default', 'caldav-v1', 32),
  };
  return cachedKeys;
}

function encrypt(text) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', keys().current, iv);
  const enc = Buffer.concat([cipher.update(String(text), 'utf8'), cipher.final()]);
  return PREFIX + Buffer.concat([iv, cipher.getAuthTag(), enc]).toString('base64');
}

const isCurrent = value => typeof value === 'string' && value.startsWith(PREFIX);
const isLegacy  = value => typeof value === 'string' && /^[0-9a-f]{32}:[0-9a-f]+$/i.test(value);

function decryptLegacy(value) {
  const [ivHex, encHex] = value.split(':');
  const decipher = crypto.createDecipheriv('aes-256-cbc', keys().legacy, Buffer.from(ivHex, 'hex'));
  return Buffer.concat([decipher.update(Buffer.from(encHex, 'hex')), decipher.final()]).toString('utf8');
}

class CredentialError extends Error {}

function decrypt(value) {
  if (isCurrent(value)) {
    const data = Buffer.from(value.slice(PREFIX.length), 'base64');
    for (const key of keys().readable) {
      try {
        const decipher = crypto.createDecipheriv('aes-256-gcm', key, data.subarray(0, 12));
        decipher.setAuthTag(data.subarray(12, 28));
        return Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]).toString('utf8');
      } catch { /* try the next key */ }
    }
  } else if (isLegacy(value)) {
    try { return decryptLegacy(value); } catch { /* fall through */ }
  }
  throw new CredentialError(
    'Stored calendar credentials could not be decrypted (was SESSION_SECRET or CREDENTIALS_ENCRYPTION_KEY changed?). Remove and reconnect this calendar.'
  );
}

// Re-encrypts credentials that are in the legacy format, under a no-longer-current key,
// or stored as plaintext. Safe to run on every start.
async function upgradeStoredCredentials(prisma, log = console) {
  const sources = await prisma.calendarSource.findMany({ select: { id: true, name: true, credentials: true } });
  let upgraded = 0;
  for (const source of sources) {
    const creds = { ...(source.credentials || {}) };
    let changed = false;
    try {
      for (const field of ['passwordEnc', 'accessToken', 'refreshToken']) {
        const value = creds[field];
        if (!value) continue;
        const plain = decrypt(value);
        // Rewrite unless it's already current-format under the current key
        if (!isCurrent(value) || !canDecryptWith(value, keys().current)) {
          creds[field] = encrypt(plain);
          changed = true;
        }
      }
      if (creds.password) {                       // plaintext from very old installs
        creds.passwordEnc = encrypt(creds.password);
        delete creds.password;
        changed = true;
      }
    } catch (err) {
      log.warn?.('calendar', `Credentials for "${source.name}" (source ${source.id}) could not be upgraded: ${err.message}`);
      continue;
    }
    if (changed) {
      await prisma.calendarSource.update({ where: { id: source.id }, data: { credentials: creds } });
      upgraded++;
    }
  }
  return upgraded;
}

function canDecryptWith(value, key) {
  try {
    const data = Buffer.from(value.slice(PREFIX.length), 'base64');
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, data.subarray(0, 12));
    decipher.setAuthTag(data.subarray(12, 28));
    decipher.update(data.subarray(28));
    decipher.final();
    return true;
  } catch {
    return false;
  }
}

module.exports = { encrypt, decrypt, upgradeStoredCredentials, CredentialError };
