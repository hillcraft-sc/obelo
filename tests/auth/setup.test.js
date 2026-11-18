require('../helpers/env');
const { describe, it, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

let base;
before(async () => { ({ base } = await startApp()); });
beforeEach(resetDb);

const good = { username: 'admin', displayName: 'Admin', email: '', password: PASSWORD, confirm: PASSWORD };
const users = () => prisma.user.count();

describe('first-run setup', () => {
  it('shows the setup page only while there are no users', async () => {
    const c = new Client(base);
    assert.equal((await c.get('/auth/setup')).status, 200);
    await createUser({ username: 'someone', password: PASSWORD });
    assert.equal((await c.get('/auth/setup')).status, 404);
  });

  it('creates the first account as an admin, signs them in and stores only a bcrypt hash', async () => {
    const c = new Client(base);
    const res = await c.post('/auth/setup', { form: good });
    assert.equal(res.status, 302);
    assert.equal(res.location, '/');
    assert.ok(res.hasCookie());
    const user = await prisma.user.findFirst();
    assert.equal(user.username, 'admin');
    assert.equal(user.role, 'admin');
    assert.match(user.passwordHash, /^\$2[aby]\$12\$/);
    assert.equal((await c.get('/admin')).status, 200, 'the new admin can open the admin pages');
  });

  it('refuses bad input and creates nothing', async () => {
    const bad = [
      [{ ...good, confirm: 'something-else-entirely' }, /two passwords/],
      [{ ...good, password: 'short', confirm: 'short' }, /at least 10/],
      [{ ...good, username: 'Not Valid!' }, /Username/],
      [{ ...good, username: '' }, /Username/],
      [{ ...good, username: 'a'.repeat(31) }, /Username/],
      [{ ...good, email: 'not-an-email' }, /email/],
      [{ ...good, password: 'x'.repeat(73), confirm: 'x'.repeat(73) }, /too long/],
    ];
    for (const [form, message] of bad) {
      const res = await new Client(base).post('/auth/setup', { form });
      assert.equal(res.status, 400, JSON.stringify(form).slice(0, 40));
      assert.match(res.text, message);
    }
    assert.equal(await users(), 0);
  });

  it('keeps what was typed (but not the password) when it refuses', async () => {
    const res = await new Client(base).post('/auth/setup', { form: { ...good, confirm: 'nope' } });
    assert.match(res.text, /value="admin"/);
    assert.doesNotMatch(res.text, new RegExp(PASSWORD));
  });

  it('lowercases the username and accepts an optional email', async () => {
    await new Client(base).post('/auth/setup', { form: { ...good, username: 'Admin', email: 'Admin@Example.com' } });
    const user = await prisma.user.findFirst();
    assert.equal(user.username, 'admin');
    assert.equal(user.email, 'admin@example.com');
  });

  it('is gone after the first account: it cannot add a second admin', async () => {
    await new Client(base).post('/auth/setup', { form: good });
    const res = await new Client(base).post('/auth/setup', { form: { ...good, username: 'intruder' } });
    assert.equal(res.status, 404);
    assert.equal(await users(), 1);
  });

  it('makes exactly one admin when several people submit at the same moment', async () => {
    const attempts = Array.from({ length: 6 }, (_, i) =>
      new Client(base).post('/auth/setup', { form: { ...good, username: `racer${i}` } }));
    const results = await Promise.all(attempts);
    const created = results.filter((r) => r.status === 302).length;
    assert.equal(created, 1, `statuses: ${results.map((r) => r.status)}`);
    assert.equal(await users(), 1);
    assert.equal(results.filter((r) => r.status === 404).length, 5);
  });

  it('sends the login page to setup, and setup is not offered once a user exists', async () => {
    const c = new Client(base);
    assert.equal((await c.get('/auth/login')).location, '/auth/setup');
    await c.post('/auth/setup', { form: good });
    const other = new Client(base);
    assert.equal((await other.get('/auth/login')).status, 200);
    assert.equal((await signIn(other, 'admin', PASSWORD)).status, 302);
  });
});
