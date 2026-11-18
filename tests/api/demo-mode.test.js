require('../helpers/env');
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

// On the public demo (DEMO_MODE=true), calendar accounts and notification channels are refused on the server.
describe('the public demo (DEMO_MODE=true)', () => {
  let a, base;
  before(async () => {
    ({ base } = await startApp());
    await resetDb();
    await createUser({ username: 'demo', password: PASSWORD });
    a = new Client(base);
    await signIn(a, 'demo', PASSWORD);
    process.env.DEMO_MODE = 'true';
  });
  after(() => { delete process.env.DEMO_MODE; });

  it("tells the apps they're on the demo", async () => {
    const me = await a.get('/api/v1/me');
    assert.equal(me.json().demo, true);
  });

  it('refuses to connect a calendar account, from the apps, with a plain sentence', async () => {
    const r = await a.request('POST', '/api/v1/calendar/sources', { json: { username: 'me@example.com', password: 'secret-pass' } });
    assert.equal(r.status, 403);
    assert.match(r.json().error, /isn't available on the demo/);
    assert.ok(!r.text.includes('secret-pass'));
  });

  it('still shows the calendar screen (reading is allowed)', async () => {
    assert.equal((await a.get('/api/v1/calendar/sources')).status, 200);
  });

  it('refuses notification changes and test sends', async () => {
    assert.equal((await a.request('PUT', '/api/v1/settings/notifications', { json: { notifEmail: 'me@example.com', types: {} } })).status, 403);
    assert.equal((await a.request('POST', '/api/v1/settings/notifications/test-email')).status, 403);
    assert.equal((await a.request('POST', '/api/v1/settings/notifications/ntfy-topic')).status, 403);
    assert.equal((await a.get('/api/v1/settings/notifications')).status, 200);
  });

  it('refuses the browser calendar connection and sends the person back with the sentence', async () => {
    const r = await a.get('/calendar/auth/google');
    assert.equal(r.status, 302);
    assert.match(r.location, /^\/calendar\/sources\?error=/);
    assert.ok(!r.location.includes('accounts.google.com'));
  });

  it('local calendars (kept inside Obelo) still work', async () => {
    const r = await a.request('POST', '/api/v1/calendar/local', { json: { name: 'Sample' } });
    assert.equal(r.status, 201);
  });

  it('the web pages show the note and leave out the connect form', async () => {
    const cal = await a.get('/calendar/sources');
    assert.equal(cal.status, 200);
    assert.match(cal.text, /aren't available on the demo/);
    assert.ok(!cal.text.includes('Connect a Calendar'));
    const settings = await a.get('/settings?tab=notifications');
    assert.equal(settings.status, 200);
    assert.match(settings.text, /aren't available on the demo/);
  });

  it('refuses a password change, so the demo login stays demo / demo', async () => {
    const api = await a.request('POST', '/api/v1/settings/password', { json: { currentPassword: PASSWORD, newPassword: 'another-long-password-1' } });
    assert.equal(api.status, 403);
    assert.match(api.json().error, /Changing the password isn't available on the demo/);
    const web = await a.request('POST', '/settings/password', { form: { currentPassword: PASSWORD, newPassword: 'another-long-password-1', confirm: 'another-long-password-1' } });
    assert.equal(web.status, 302);
    assert.match(web.location, /^\/settings\?tab=account&error=/);
    const page = await a.get('/settings?tab=account');
    assert.ok(!page.text.includes('name="newPassword"'));
    // and the old password still works
    const again = new Client(base);
    await signIn(again, 'demo', PASSWORD);
    assert.equal((await again.get('/api/v1/me')).status, 200);
  });
});
