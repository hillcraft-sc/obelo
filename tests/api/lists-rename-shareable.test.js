require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

describe('list rename and shareable users', () => {
  let a, b, alice, bob, base;
  before(async () => {
    ({ base } = await startApp());
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    bob = await createUser({ username: 'bob', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
    b = new Client(base); await signIn(b, 'bob', PASSWORD);
  });
  const title = async (id) => (await prisma.list.findUnique({ where: { id } })).title;

  it('GET /users/shareable lists everyone but you', async () => {
    const r = await a.get('/api/v1/users/shareable');
    assert.equal(r.status, 200);
    assert.deepEqual(r.json().users.map((u) => u.username), ['bob']);
    assert.equal(r.json().users[0].id, bob.id);
  });

  it('API: the owner renames, trimmed; empty is refused', async () => {
    const l = await prisma.list.create({ data: { userId: alice.id, title: 'Old' } });
    let r = await a.request('PATCH', `/api/v1/lists/${l.id}`, { json: { title: '  New  ' } });
    assert.equal(r.status, 200);
    assert.equal(await title(l.id), 'New');
    r = await a.request('PATCH', `/api/v1/lists/${l.id}`, { json: { title: '  ' } });
    assert.equal(r.status, 400);
    assert.equal(await title(l.id), 'New');
  });

  it('API: someone else, even with a share, cannot rename', async () => {
    const l = await prisma.list.create({ data: { userId: alice.id, title: 'Mine' } });
    await prisma.listShare.create({ data: { listId: l.id, userId: bob.id } });
    assert.equal((await b.request('PATCH', `/api/v1/lists/${l.id}`, { json: { title: 'Hijack' } })).status, 404);
    assert.equal(await title(l.id), 'Mine');
  });

  it('web: the owner renames, others cannot', async () => {
    const l = await prisma.list.create({ data: { userId: alice.id, title: 'Web' } });
    assert.equal((await b.post(`/lists/${l.id}/rename`, { form: { title: 'x' } })).status, 404);
    const r = await a.post(`/lists/${l.id}/rename`, { form: { title: 'Web 2' } });
    assert.equal(r.status, 200);
    assert.equal(await title(l.id), 'Web 2');
  });
});
