// Require this FIRST in every test file, before anything from src/.
//
// It points the app at the throwaway test database, and refuses anything else. It also blanks every
// variable listed in .env.example: src/app.js loads a real .env on its own, and dotenv never
// overrides a variable that is already set, so an empty value here keeps real keys, SSO and
// notification settings out of the tests. (The project rule is that .env.example lists every
// variable the code reads.)

const fs = require('fs');
const os = require('os');
const path = require('path');

const url = process.env.TEST_DATABASE_URL;
if (!url) {
  throw new Error('TEST_DATABASE_URL is not set. Run the tests with `npm test`.');
}
const dbName = decodeURIComponent(new URL(url).pathname.replace(/^\//, ''));
if (!/_test$/.test(dbName)) {
  throw new Error(`Refusing to run: the test database name must end in _test (got "${dbName}").`);
}

const example = fs.readFileSync(path.join(__dirname, '..', '..', '.env.example'), 'utf8');
for (const line of example.split('\n')) {
  const m = line.match(/^([A-Z][A-Z0-9_]*)=/);
  if (m) process.env[m[1]] = '';
}
// Old SSO names are still read by the server but no longer listed in .env.example.
for (const k of ['ISSUER', 'CLIENT_ID', 'CLIENT_SECRET', 'REDIRECT_URI']) process.env[`AUTHENTIK_${k}`] = '';

Object.assign(process.env, {
  DATABASE_URL: url,
  NODE_ENV: 'test',
  SESSION_SECRET: 'test-session-secret-0123456789abcdef0123456789',
  NOTE_LOCK_SECRET: 'test-note-lock-secret-0123456789abcdef',
  APP_URL: 'http://localhost',
  LOG_LEVEL: 'error',
  UPLOAD_PATH: fs.mkdtempSync(path.join(os.tmpdir(), 'obelo-test-uploads-')),
});

module.exports = { dbName };
