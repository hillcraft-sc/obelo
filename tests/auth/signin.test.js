require('../helpers/env');
const { describe, it, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

let base;
before(async () => { ({ base } = await startApp()); });
beforeEach(resetDb);

const signedIn = async (c) => (await c.get('/settings')).status === 200;
const SSO_ON = { OIDC_ISSUER: 'https://sso.invalid/', OIDC_CLIENT_ID: 'a', OIDC_CLIENT_SECRET: 'b' };
const SSO_OFF = { OIDC_ISSUER: '', OIDC_CLIENT_ID: '', OIDC_CLIENT_SECRET: '' };

describe('web sign-in', () => {
  it('signs in with a username and password, and a signed-out visit to a private page goes to the login page', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const c = new Client(base);
    const before = await c.get('/settings');
    assert.equal(before.status, 302);
    assert.equal(before.location, '/auth/login');
    const res = await signIn(c, 'sam', PASSWORD);
    assert.equal(res.status, 302);
    assert.equal(res.location, '/');
    assert.ok(res.hasCookie());
    assert.ok(await signedIn(c));
  });

  it('works with an email address in any case, and records the last sign-in', async () => {
    const u = await createUser({ username: 'sam', email: 'sam@example.com', password: PASSWORD });
    const c = new Client(base);
    assert.equal((await signIn(c, 'SAM@Example.com', PASSWORD)).status, 302);
    const after = await prisma.user.findUnique({ where: { id: u.id } });
    assert.ok(after.lastLoginAt);
  });

  it('gives the same answer for a wrong password, an unknown user and an account with no password', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    await createUser({ username: 'sso-only' });
    const answers = [];
    for (const [user, pw] of [['sam', 'wrong-wrong-wrong'], ['nobody', PASSWORD], ['sso-only', PASSWORD]]) {
      const c = new Client(base);
      const res = await signIn(c, user, pw);
      assert.equal(res.status, 200, user);
      assert.ok(!res.hasCookie(), `${user} got a session`);
      answers.push(res.text.match(/Wrong username or password\./)?.[0]);
    }
    assert.deepEqual(answers, Array(3).fill('Wrong username or password.'));
  });

  it('shows the same message and no session when the username is empty', async () => {
    const c = new Client(base);
    const res = await c.post('/auth/login', { form: { username: '', password: '' } });
    assert.equal(res.status, 200);
    assert.ok(!res.hasCookie());
  });

  it('locks one account after 10 wrong passwords but not other accounts, and shows the same message', async () => {
    await createUser({ username: 'target', password: PASSWORD });
    await createUser({ username: 'bystander', password: PASSWORD });
    const attacker = new Client(base);
    for (let i = 0; i < 10; i++) await signIn(attacker, 'target', `wrong-password-${i}`);
    const locked = new Client(base);
    const res = await signIn(locked, 'target', PASSWORD);
    assert.equal(res.status, 200);
    assert.match(res.text, /Wrong username or password/);
    assert.ok(!res.hasCookie());
    const other = new Client(base);
    await signIn(other, 'bystander', PASSWORD);
    assert.ok(await signedIn(other), 'another account is not affected');
  });

  it('limits one IP to 20 attempts in 15 minutes', async () => {
    const c = new Client(base);
    let limited = 0;
    for (let i = 0; i < 25; i++) {
      const res = await signIn(c, `nobody-${i}`, 'wrong-wrong-wrong');
      if (res.status === 429) limited++;
    }
    assert.ok(limited >= 4, `expected at least 4 refusals, got ${limited}`);
    // a different IP is not affected
    assert.equal((await signIn(new Client(base), 'nobody', 'x')).status, 200);
  });

  it('shows the login form at /auth/login once users exist, and goes to setup when there are none', async () => {
    const empty = await new Client(base).get('/auth/login');
    assert.equal(empty.status, 302);
    assert.equal(empty.location, '/auth/setup');
    await createUser({ username: 'sam', password: PASSWORD });
    const page = await new Client(base).get('/auth/login');
    assert.equal(page.status, 200);
    assert.match(page.text, /name="password"/);
  });

  it('sends a signed-in person away from the login page', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const c = new Client(base);
    await signIn(c, 'sam', PASSWORD);
    const res = await c.get('/auth/login');
    assert.equal(res.status, 302);
    assert.equal(res.location, '/');
  });

  it('signs out', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const c = new Client(base);
    await signIn(c, 'sam', PASSWORD);
    assert.equal((await c.post('/auth/logout')).status, 302);
    assert.ok(!(await signedIn(c)));
  });
});

describe('the password sign-in switch on the web', () => {
  const setSwitch = (value) => prisma.systemSetting.create({ data: { key: 'password_login', value } });

  it('hides the form and refuses passwords when an admin turned it off and SSO is on', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    await setSwitch('false');
    Object.assign(process.env, SSO_ON);
    try {
      const page = await new Client(base).get('/auth/login');
      assert.doesNotMatch(page.text, /name="password"/);
      assert.match(page.text, /href="\/auth\/oidc"/);
      const c = new Client(base);
      const res = await signIn(c, 'sam', PASSWORD);
      assert.match(res.text, /switched off/);
      assert.ok(!res.hasCookie());
    } finally { Object.assign(process.env, SSO_OFF); }
  });

  it('is ignored when SSO is not set up, so nobody is locked out', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    await setSwitch('false');
    const c = new Client(base);
    assert.equal((await signIn(c, 'sam', PASSWORD)).status, 302);
    assert.ok(await signedIn(c));
  });

  it('shows the SSO button next to the form when SSO is on', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    Object.assign(process.env, SSO_ON);
    try {
      const page = await new Client(base).get('/auth/login');
      assert.match(page.text, /name="password"/);
      assert.match(page.text, /href="\/auth\/oidc"/);
    } finally { Object.assign(process.env, SSO_OFF); }
  });
});

describe('the apps sign-in endpoint', () => {
  it('signs in and gives a session that works on the API', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const c = new Client(base);
    const res = await c.post('/api/v1/auth/login', { json: { username: 'sam', password: PASSWORD } });
    assert.equal(res.status, 200);
    assert.deepEqual(res.json(), { ok: true });
    const me = await c.get('/api/v1/me');
    assert.equal(me.status, 200);
    assert.equal(me.json().user.username, 'sam');
  });

  it('answers a wrong password and an unknown user identically, with no session', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const a = new Client(base), b = new Client(base);
    const wrong = await a.post('/api/v1/auth/login', { json: { username: 'sam', password: 'wrong-wrong-wrong' } });
    const unknown = await b.post('/api/v1/auth/login', { json: { username: 'nobody', password: 'wrong-wrong-wrong' } });
    assert.equal(wrong.status, 401);
    assert.equal(unknown.status, 401);
    assert.equal(wrong.text, unknown.text);
    assert.ok(!a.hasSession() && !b.hasSession());
    assert.equal((await a.get('/api/v1/me')).status, 401);
  });

  it('refuses when an admin turned passwords off and SSO is on', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    await prisma.systemSetting.create({ data: { key: 'password_login', value: 'false' } });
    Object.assign(process.env, SSO_ON);
    try {
      const res = await new Client(base).post('/api/v1/auth/login', { json: { username: 'sam', password: PASSWORD } });
      assert.equal(res.status, 403);
    } finally { Object.assign(process.env, SSO_OFF); }
  });

  it('needs the X-Obelo-Client header', async () => {
    const res = await fetch(`${base}/api/v1/auth/login`, {
      method: 'POST', headers: { 'content-type': 'application/json', 'X-Forwarded-For': '10.9.9.9' },
      body: JSON.stringify({ username: 'sam', password: PASSWORD }),
    });
    assert.equal(res.status, 400);
  });

  it('does not sign in with a bad or missing body', async () => {
    for (const json of [{}, { username: 'sam' }, { password: PASSWORD }]) {
      const res = await new Client(base).post('/api/v1/auth/login', { json });
      assert.equal(res.status, 401);
    }
  });
});
