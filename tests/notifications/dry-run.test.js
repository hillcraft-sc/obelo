// Notifications: a dry run sends nothing; a live run sends. Email goes to a tiny fake SMTP server,
// so this also proves a message really leaves through nodemailer.
require('../helpers/env');
const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const net = require('node:net');

const notifyMode = require('../../src/lib/notifyMode');
const ntfy = require('../../src/services/ntfyService');
const pushover = require('../../src/services/pushoverService');
const email = require('../../src/services/emailService');

const received = [];
let smtp;

function startFakeSmtp() {
  return new Promise((resolve) => {
    smtp = net.createServer((sock) => {
      let data = false, buf = '', msg = '';
      sock.write('220 fake ESMTP\r\n');
      sock.on('data', (chunk) => {
        if (data) {
          msg += chunk.toString();
          if (msg.endsWith('\r\n.\r\n')) { received.push(msg); data = false; msg = ''; sock.write('250 queued\r\n'); }
          return;
        }
        buf += chunk.toString();
        let i;
        while ((i = buf.indexOf('\r\n')) >= 0) {
          const line = buf.slice(0, i); buf = buf.slice(i + 2);
          const cmd = line.split(' ')[0].toUpperCase();
          if (cmd === 'EHLO' || cmd === 'HELO') sock.write('250-fake\r\n250 AUTH PLAIN\r\n');
          else if (cmd === 'AUTH') sock.write('235 ok\r\n');
          else if (cmd === 'DATA') { data = true; sock.write('354 go\r\n'); }
          else if (cmd === 'QUIT') { sock.write('221 bye\r\n'); sock.end(); }
          else sock.write('250 ok\r\n');
        }
      });
    });
    smtp.listen(0, '127.0.0.1', () => resolve(smtp.address().port));
  });
}

const realFetch = global.fetch;
let fetchCalls;
const saved = {};
const KEYS = ['NOTIFICATIONS_DRY_RUN', 'NODE_ENV', 'NTFY_URL', 'PUSHOVER_APP_TOKEN', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS'];

before(async () => {
  for (const k of KEYS) saved[k] = process.env[k];
  const port = await startFakeSmtp();
  Object.assign(process.env, { SMTP_HOST: '127.0.0.1', SMTP_PORT: String(port), SMTP_USER: 'obelo@example.test', SMTP_PASS: 'x', NTFY_URL: 'https://ntfy.invalid', PUSHOVER_APP_TOKEN: 'tok' });
});
after(() => {
  global.fetch = realFetch;
  for (const k of KEYS) { if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k]; }
  smtp.close();
});
beforeEach(() => {
  received.length = 0;
  fetchCalls = [];
  global.fetch = async (url) => { fetchCalls.push(String(url)); return { ok: true, json: async () => ({ status: 1 }), text: async () => '' }; };
});

describe('the dry-run setting', () => {
  const mode = (env) => { Object.assign(process.env, { NOTIFICATIONS_DRY_RUN: '', NODE_ENV: 'test' }, env); return notifyMode.isDryRun(); };

  it('is on by default outside production, off in production', () => {
    assert.equal(mode({}), true);
    assert.equal(mode({ NODE_ENV: 'development' }), true);
    assert.equal(mode({ NODE_ENV: 'production' }), false);
  });
  it('can be forced either way', () => {
    assert.equal(mode({ NODE_ENV: 'production', NOTIFICATIONS_DRY_RUN: 'true' }), true);
    assert.equal(mode({ NODE_ENV: 'test', NOTIFICATIONS_DRY_RUN: 'false' }), false);
  });
});

describe('with the dry run on, nothing leaves', () => {
  beforeEach(() => { process.env.NOTIFICATIONS_DRY_RUN = 'true'; });

  it('ntfy and Pushover make no request', async () => {
    assert.equal(await ntfy.send('topic', { title: 'T', message: 'M' }), true);
    assert.ok(await pushover.send('userkey', { title: 'T', message: 'M' }));
    assert.deepEqual(fetchCalls, []);
  });
  it('email is not sent', async () => {
    assert.equal(await email.sendEmail('sam@example.test', 'Hello', 'body'), true);
    await new Promise(r => setTimeout(r, 200));
    assert.equal(received.length, 0);
  });
});

describe('a button pressed on purpose still sends', () => {
  beforeEach(() => { process.env.NOTIFICATIONS_DRY_RUN = 'true'; });

  it('ntfy and email with force', async () => {
    assert.equal(await ntfy.send('topic', { title: 'T', message: 'M' }, { force: true }), true);
    assert.equal(fetchCalls.length, 1);
    assert.equal(await email.sendEmail('sam@example.test', 'Forced', 'body', null, { force: true }), true);
    assert.equal(received.length, 1);
  });
});

describe('with the dry run off, they are sent', () => {
  beforeEach(() => { process.env.NOTIFICATIONS_DRY_RUN = 'false'; });

  it('ntfy, Pushover and email', async () => {
    assert.equal(await ntfy.send('topic', { title: 'T', message: 'M' }), true);
    await pushover.send('userkey', { title: 'T', message: 'M' });
    assert.equal(fetchCalls.length, 2);
    assert.equal(await email.sendEmail('sam@example.test', 'Live', 'the body'), true);
    assert.equal(received.length, 1);
    assert.match(received[0], /Subject: Live/);
    assert.match(received[0], /the body/);
  });
});
