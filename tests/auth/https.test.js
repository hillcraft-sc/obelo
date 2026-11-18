require('../helpers/env');
const { describe, it, before, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

// In production the session cookie is Secure, so over plain http:// the browser would keep nothing
// and sign-in would silently do nothing. The app says so and refuses. The check reads NODE_ENV on
// each request, so these tests switch it per test.
let base;
before(async () => { ({ base } = await startApp()); });
beforeEach(async () => { await resetDb(); process.env.NODE_ENV = 'production'; });
afterEach(() => { process.env.NODE_ENV = 'test'; });

const BANNER = /using HTTPS/;
const good = { username: 'admin', displayName: 'Admin', email: '', password: PASSWORD, confirm: PASSWORD };

describe('production over plain http://', () => {
  it('shows a warning on the login page', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const page = await new Client(base).get('/auth/login');
    assert.match(page.text, BANNER);
  });

  it('refuses to sign in, and says why', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const c = new Client(base);
    const res = await signIn(c, 'sam', PASSWORD);
    assert.equal(res.status, 200);
    assert.match(res.text, BANNER);
    assert.ok(!res.hasCookie());
  });

  it('refuses first-run setup and does not create the first account', async () => {
    const res = await new Client(base).post('/auth/setup', { form: good });
    assert.equal(res.status, 400);
    assert.match(res.text, BANNER);
    assert.equal(await prisma.user.count(), 0);
  });

  it('gives the apps a clear error on both sign-in endpoints', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const login = await new Client(base).post('/api/v1/auth/login', { json: { username: 'sam', password: PASSWORD } });
    assert.equal(login.status, 400);
    assert.match(login.json().error, /HTTPS/);
    const exchange = await new Client(base).post('/api/v1/auth/exchange', { json: { code: 'x'.repeat(30) } });
    assert.equal(exchange.status, 400);
    assert.match(exchange.json().error, /HTTPS/);
  });
});

describe('production through an HTTPS proxy (X-Forwarded-Proto: https)', () => {
  it('shows no warning and signs in', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const c = new Client(base, { https: true });
    assert.doesNotMatch((await c.get('/auth/login')).text, BANNER);
    const res = await signIn(c, 'sam', PASSWORD);
    assert.equal(res.status, 302);
    assert.ok(res.hasCookie());
  });

  it('creates the first account', async () => {
    const res = await new Client(base, { https: true }).post('/auth/setup', { form: good });
    assert.equal(res.status, 302);
    assert.equal(await prisma.user.count(), 1);
  });

  it('lets the apps sign in', async () => {
    await createUser({ username: 'sam', password: PASSWORD });
    const res = await new Client(base, { https: true }).post('/api/v1/auth/login', { json: { username: 'sam', password: PASSWORD } });
    assert.equal(res.status, 200);
  });
});

describe('outside production', () => {
  it('never shows the warning or refuses, over plain http', async () => {
    process.env.NODE_ENV = 'test';
    await createUser({ username: 'sam', password: PASSWORD });
    const c = new Client(base);
    assert.doesNotMatch((await c.get('/auth/login')).text, BANNER);
    assert.equal((await signIn(c, 'sam', PASSWORD)).status, 302);
  });
});
