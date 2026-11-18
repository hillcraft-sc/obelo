require('../helpers/env');
const { describe, it, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');
const passwords = require('../../src/lib/passwords');

let base;
before(async () => { ({ base } = await startApp()); });
beforeEach(resetDb);

const NEW_PW = 'brand-new-password-2';
const live = async (c) => (await c.get('/settings')).status === 200;
const form = (over = {}) => ({ currentPassword: PASSWORD, newPassword: NEW_PW, confirmPassword: NEW_PW, ...over });

async function twoDevices(username = 'sam') {
  const user = await createUser({ username, password: PASSWORD });
  const here = new Client(base), other = new Client(base);
  await signIn(here, username, PASSWORD);
  await signIn(other, username, PASSWORD);
  return { user, here, other };
}

describe('Settings → Account → Password (web)', () => {
  it('changes the password, keeps this device signed in and signs the others out', async () => {
    const { here, other } = await twoDevices();
    const res = await here.post('/settings/password', { form: form() });
    assert.equal(res.status, 302);
    assert.match(res.location, /success=/);
    assert.ok(await live(here), 'this device was signed out');
    assert.ok(!(await live(other)), 'the other device is still signed in');
    assert.ok(await passwords.authenticate('sam', NEW_PW));
    assert.equal(await passwords.authenticate('sam', PASSWORD), null);
  });

  it('needs the right current password, and changes nothing without it', async () => {
    const { here, other } = await twoDevices();
    for (const currentPassword of ['not-the-password-1', '']) {
      const res = await here.post('/settings/password', { form: form({ currentPassword }) });
      assert.match(res.location, /error=/);
    }
    assert.ok(await passwords.authenticate('sam', PASSWORD));
    assert.ok(await live(other), 'a refused change signed someone out');
  });

  it('refuses a mismatch and a short password', async () => {
    const { here } = await twoDevices();
    assert.match((await here.post('/settings/password', { form: form({ confirmPassword: 'nope' }) })).location, /match/);
    assert.match((await here.post('/settings/password', { form: form({ newPassword: 'short', confirmPassword: 'short' }) })).location, /at%20least%2010/);
    assert.ok(await passwords.authenticate('sam', PASSWORD));
  });

  it('lets an account with no password add one without a current password', async () => {
    await createUser({ username: 'sso-person' });
    const c = new Client(base);
    // no password to sign in with, so give the client a session the way SSO would
    const u = await prisma.user.findUnique({ where: { username: 'sso-person' } });
    await prisma.user.update({ where: { id: u.id }, data: { passwordHash: await passwords.hashPassword(PASSWORD) } });
    await signIn(c, 'sso-person', PASSWORD);
    await prisma.user.update({ where: { id: u.id }, data: { passwordHash: null } });
    const res = await c.post('/settings/password', { form: { newPassword: NEW_PW, confirmPassword: NEW_PW } });
    assert.match(res.location, /success=/);
    assert.ok(await passwords.authenticate('sso-person', NEW_PW));
  });

  it('needs you to be signed in', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const res = await new Client(base).post('/settings/password', { form: form() });
    assert.equal(res.status, 302);
    assert.equal(res.location, '/auth/login');
    assert.ok(await passwords.authenticate('sam', PASSWORD));
  });

  it('shows the password card on the account page', async () => {
    const { here } = await twoDevices();
    const page = await here.get('/settings?tab=account');
    assert.match(page.text, /Current password/);
    assert.match(page.text, /action="\/settings\/password"/);
  });
});

describe('the same thing from the apps', () => {
  it('changes the password and signs the other devices out', async () => {
    const { here, other } = await twoDevices();
    const res = await here.post('/api/v1/settings/password', { json: { currentPassword: PASSWORD, newPassword: NEW_PW } });
    assert.equal(res.status, 200);
    assert.ok(await live(here));
    assert.ok(!(await live(other)));
    assert.ok(await passwords.authenticate('sam', NEW_PW));
  });

  it('refuses a wrong current password and a short new one with a message', async () => {
    const { here } = await twoDevices();
    const wrong = await here.post('/api/v1/settings/password', { json: { currentPassword: 'wrong-wrong-wrong', newPassword: NEW_PW } });
    assert.equal(wrong.status, 400);
    assert.match(wrong.json().error, /current password is wrong/);
    const short = await here.post('/api/v1/settings/password', { json: { currentPassword: PASSWORD, newPassword: 'short' } });
    assert.equal(short.status, 400);
    assert.match(short.json().error, /at least 10/);
  });

  it('needs a signed-in session', async () => {
    const res = await new Client(base).post('/api/v1/settings/password', { json: { currentPassword: PASSWORD, newPassword: NEW_PW } });
    assert.equal(res.status, 401);
  });

  it('is refused when an admin turned passwords off and SSO is on', async () => {
    const { here } = await twoDevices();
    await prisma.systemSetting.create({ data: { key: 'password_login', value: 'false' } });
    Object.assign(process.env, { OIDC_ISSUER: 'https://sso.invalid/', OIDC_CLIENT_ID: 'a', OIDC_CLIENT_SECRET: 'b' });
    try {
      const res = await here.post('/api/v1/settings/password', { json: { currentPassword: PASSWORD, newPassword: NEW_PW } });
      assert.equal(res.status, 403);
    } finally {
      Object.assign(process.env, { OIDC_ISSUER: '', OIDC_CLIENT_ID: '', OIDC_CLIENT_SECRET: '' });
    }
  });

  it('reports whether you have a password and whether password sign-in is on', async () => {
    const { here } = await twoDevices();
    const res = await here.get('/api/v1/settings');
    assert.equal(res.status, 200);
    assert.equal(res.json().account.hasPassword, true);
    assert.equal(res.json().account.passwordLogin, true);
  });
});
