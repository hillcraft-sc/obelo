// Encrypts any unencrypted files in the uploads folder with UPLOADS_ENCRYPTION_KEY.
// Run once after turning encryption on:  docker compose exec app node scripts/encrypt-uploads.js
// Safe to re-run: already-encrypted files are skipped.
require('dotenv').config();
const uploads = require('../src/lib/uploads');

if (!uploads.isEncryptionEnabled()) {
  console.error('UPLOADS_ENCRYPTION_KEY is not set — nothing to do.');
  process.exit(1);
}

uploads.encryptExisting()
  .then(({ encrypted, skipped }) => {
    console.log(`✓ ${uploads.UPLOAD_BASE}: encrypted ${encrypted} file(s), ${skipped} already encrypted`);
  })
  .catch(err => { console.error(err); process.exit(1); });
