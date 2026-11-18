require('../helpers/env');
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

describe('CSRF tokens', () => {
  let base, a;
  before(async () => {
    ({ base } = await startApp());
    await resetDb();
    await createUser({ username: 'alice', password: PASSWORD });
    a = new Client(base);
    await signIn(a, 'alice', PASSWORD);
  });

  const body = { title: 'csrf-check' };

  it('rejects a write with no token', async () => {
    const r = await a.post('/tasks', { form: body, csrf: false });
    assert.equal(r.status, 403);
  });
  it('rejects a write with a wrong token', async () => {
    const r = await a.post('/tasks', { form: body, headers: { 'X-CSRF-Token': 'nope' } });
    assert.equal(r.status, 403);
  });
  it('rejects another session\'s token', async () => {
    const other = new Client(base);
    const t = await other.csrfToken();
    const r = await a.post('/tasks', { form: body, headers: { 'X-CSRF-Token': t }, csrf: false });
    assert.equal(r.status, 403);
  });
  it('lets the Shortcuts capture address through on its Bearer token alone, and nothing else', async () => {
    const post = (path, headers) => fetch(`${base}${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: '{}' });
    // past the CSRF check: the token is then judged by the route itself (401 for an unknown one)
    assert.equal((await post('/capture/api', { Authorization: 'Bearer not-a-real-token' })).status, 401);
    assert.equal((await post('/capture/api', {})).status, 403, 'no Authorization header: still checked');
    assert.equal((await post('/capture/api', { Authorization: 'Bearer ' })).status, 403, 'an empty token: still checked');
    assert.equal((await post('/tasks', { Authorization: 'Bearer not-a-real-token' })).status, 403, 'only that one address');
  });
  it('accepts the token as a header, a body field and a query parameter', async () => {
    const t = await a.csrfToken();
    for (const r of [
      await a.post('/tasks', { form: body, headers: { 'X-CSRF-Token': t } }),
      await a.post('/tasks', { form: { ...body, _csrf: t }, csrf: false }),
      await a.post('/tasks?_csrf=' + t, { form: body, csrf: false }),
    ]) assert.notEqual(r.status, 403);
  });
  it('answers JSON requests with a JSON 403', async () => {
    const r = await a.post('/tasks', { json: body, csrf: false });
    assert.equal(r.status, 403);
    assert.match(r.json().error, /expired/);
  });
  it('does not touch GET pages or the apps\' /api/v1', async () => {
    assert.equal((await a.get('/privacy')).status, 200);
    const r = await a.post('/api/v1/tasks', { json: body });
    assert.notEqual(r.status, 403);
  });
  it('puts the token in the page and loads the script', async () => {
    const r = await a.get('/privacy');
    assert.match(r.text, /name="csrf-token" content="[0-9a-f]{64}"/);
    assert.match(r.text, /\/js\/csrf\.js/);
  });
  it('sign-in forms are protected too', async () => {
    const c = new Client(base);
    const r = await c.post('/auth/login', { form: { username: 'alice', password: PASSWORD }, csrf: false });
    assert.equal(r.status, 403);
  });
});
