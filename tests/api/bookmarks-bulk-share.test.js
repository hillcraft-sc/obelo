require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

describe('bookmarks: bulk delete and send to a user (/api/v1)', () => {
  let a, alice, bob;
  before(async () => {
    const { base } = await startApp();
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    bob = await createUser({ username: 'bob', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
  });
  const make = (user, url, extra = {}) => prisma.bookmark.create({ data: { userId: user.id, url, tags: [], ...extra } });

  it('deletes several and says how many', async () => {
    const [b1, b2] = [await make(alice, 'https://a.test'), await make(alice, 'https://b.test')];
    const r = await a.post('/api/v1/bookmarks/bulk-delete', { json: { ids: [b1.id, b2.id] } });
    assert.equal(r.status, 200);
    assert.equal(r.json().count, 2);
    assert.equal(await prisma.bookmark.count({ where: { id: { in: [b1.id, b2.id] } } }), 0);
  });

  it("never deletes another user's bookmarks", async () => {
    const mine = await make(alice, 'https://m.test'), theirs = await make(bob, 'https://t.test');
    const r = await a.post('/api/v1/bookmarks/bulk-delete', { json: { ids: [mine.id, theirs.id] } });
    assert.equal(r.json().count, 1);
    assert.ok(await prisma.bookmark.findUnique({ where: { id: theirs.id } }));
  });

  it('refuses an empty or missing list', async () => {
    assert.equal((await a.post('/api/v1/bookmarks/bulk-delete', { json: { ids: [] } })).status, 400);
    assert.equal((await a.post('/api/v1/bookmarks/bulk-delete', { json: {} })).status, 400);
  });

  it('sends a copy to another user, with title, note and tags', async () => {
    const b = await make(alice, 'https://share.test', { title: 'T', description: 'N', tags: ['x'] });
    const r = await a.post(`/api/v1/bookmarks/${b.id}/share-to-user`, { json: { username: '@bob' } });
    assert.equal(r.status, 200);
    assert.equal(r.json().message, 'Sent to @bob');
    const copy = await prisma.bookmark.findFirst({ where: { userId: bob.id, url: 'https://share.test' } });
    assert.equal(copy.title, 'T'); assert.equal(copy.description, 'N'); assert.deepEqual(copy.tags, ['x']);
  });

  it('says so when they already have it, when the user is unknown, and when it is you', async () => {
    const b = await prisma.bookmark.findFirst({ where: { userId: alice.id, url: 'https://share.test' } });
    const url = `/api/v1/bookmarks/${b.id}/share-to-user`;
    assert.equal((await a.post(url, { json: { username: 'bob' } })).status, 409);
    assert.equal((await a.post(url, { json: { username: 'nobody' } })).status, 404);
    assert.equal((await a.post(url, { json: { username: 'alice' } })).status, 400);
    assert.equal((await a.post(url, { json: { username: '' } })).status, 400);
  });

  it("will not send someone else's bookmark", async () => {
    const theirs = await make(bob, 'https://private.test');
    const r = await a.post(`/api/v1/bookmarks/${theirs.id}/share-to-user`, { json: { username: 'bob' } });
    assert.equal(r.status, 404);
  });
});
