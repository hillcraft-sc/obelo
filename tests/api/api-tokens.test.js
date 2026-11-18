require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

describe('API tokens (the Shortcuts tab) on /api/v1', () => {
  let a, b, alice, bob, base;
  before(async () => {
    ({ base } = await startApp());
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    bob = await createUser({ username: 'bob', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
    b = new Client(base); await signIn(b, 'bob', PASSWORD);
  });

  it('starts with none', async () => {
    const r = await a.get('/api/v1/settings/api-tokens');
    assert.equal(r.status, 200);
    assert.deepEqual(r.json().tokens, []);
  });

  it('creates one, shows the token once, and keeps only its hash', async () => {
    const r = await a.post('/api/v1/settings/api-tokens', { json: { label: '  iPhone Shortcut ' } });
    assert.equal(r.status, 201);
    const t = r.json();
    assert.equal(t.label, 'iPhone Shortcut');
    assert.match(t.token, /^[0-9a-f]{64}$/);
    const row = await prisma.apiToken.findUnique({ where: { id: t.id } });
    assert.equal(row.tokenHash, crypto.createHash('sha256').update(t.token).digest('hex'));
    assert.notEqual(row.tokenHash, t.token);
    const list = await a.get('/api/v1/settings/api-tokens');
    assert.deepEqual(list.json().tokens.map((x) => x.id), [t.id]);
    assert.ok(!JSON.stringify(list.json()).includes(t.token), 'the list never carries the token');
    assert.ok(!JSON.stringify(list.json()).includes(row.tokenHash), 'nor its hash');
    assert.equal(list.json().tokens[0].lastUsed, null);
  });

  it('names an unlabelled token "iOS Shortcut" and cuts a long label to 60 characters', async () => {
    const one = (await a.post('/api/v1/settings/api-tokens', { json: {} })).json();
    assert.equal(one.label, 'iOS Shortcut');
    const long = (await a.post('/api/v1/settings/api-tokens', { json: { label: 'x'.repeat(100) } })).json();
    assert.equal(long.label.length, 60);
  });

  it('a created token is accepted by the capture address (and a made-up one is not)', async () => {
    const t = (await a.post('/api/v1/settings/api-tokens', { json: { label: 'works' } })).json();
    const ok = await fetch(`${base}/capture/api`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${t.token}` }, body: '{}' });
    assert.equal(ok.status, 400, 'past the token check, refused only for the missing text');
    const bad = await fetch(`${base}/capture/api`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer nope' }, body: '{}' });
    assert.equal(bad.status, 401);
  });

  it('lists only your own', async () => {
    const mine = (await b.post('/api/v1/settings/api-tokens', { json: { label: 'bob only' } })).json();
    const alices = (await a.get('/api/v1/settings/api-tokens')).json().tokens;
    assert.ok(!alices.some((x) => x.id === mine.id));
    assert.deepEqual((await b.get('/api/v1/settings/api-tokens')).json().tokens.map((x) => x.id), [mine.id]);
  });

  it('revokes your own, and the token stops working', async () => {
    const t = (await a.post('/api/v1/settings/api-tokens', { json: { label: 'revoke me' } })).json();
    const r = await a.request('DELETE', `/api/v1/settings/api-tokens/${t.id}`);
    assert.equal(r.status, 200);
    assert.equal(await prisma.apiToken.count({ where: { id: t.id } }), 0);
    const after = await fetch(`${base}/capture/api`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${t.token}` }, body: '{}' });
    assert.equal(after.status, 401);
  });

  it("cannot revoke someone else's", async () => {
    const theirs = (await b.post('/api/v1/settings/api-tokens', { json: { label: 'bob again' } })).json();
    const r = await a.request('DELETE', `/api/v1/settings/api-tokens/${theirs.id}`);
    assert.equal(r.status, 200);
    assert.ok(await prisma.apiToken.findUnique({ where: { id: theirs.id } }), 'still there');
  });

  it('needs you to be signed in', async () => {
    const anon = new Client(base);
    assert.equal((await anon.get('/api/v1/settings/api-tokens')).status, 401);
    assert.equal((await anon.post('/api/v1/settings/api-tokens', { json: {} })).status, 401);
  });
});
