require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

describe('POST /api/v1/tasks/bulk', () => {
  let a, b, alice, bob;
  before(async () => {
    const { base } = await startApp();
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    bob = await createUser({ username: 'bob', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
    b = new Client(base); await signIn(b, 'bob', PASSWORD);
  });
  const make = (user, title) => prisma.task.create({ data: { userId: user.id, title, status: 'inbox', priority: 'none', notes: '' } });
  const bulk = (c, action, ids) => c.post('/api/v1/tasks/bulk', { json: { action, ids } });

  it('completes, archives, restores and sets priority', async () => {
    const [t1, t2] = [await make(alice, 'one'), await make(alice, 'two')];
    let r = await bulk(a, 'complete', [t1.id, t2.id]);
    assert.equal(r.status, 200); assert.equal(r.json().count, 2);
    assert.deepEqual((await prisma.task.findMany({ where: { id: { in: [t1.id, t2.id] } } })).map((t) => t.status), ['done', 'done']);
    await bulk(a, 'restore', [t1.id, t2.id]);
    assert.equal((await prisma.task.findUnique({ where: { id: t1.id } })).status, 'inbox');
    await bulk(a, 'archive', [t1.id]);
    assert.equal((await prisma.task.findUnique({ where: { id: t1.id } })).status, 'archived');
    await bulk(a, 'high', [t2.id]);
    assert.equal((await prisma.task.findUnique({ where: { id: t2.id } })).priority, 'high');
  });
  it('never touches another user\'s tasks', async () => {
    const mine = await make(alice, 'mine'), theirs = await make(bob, 'theirs');
    const r = await bulk(a, 'archive', [mine.id, theirs.id]);
    assert.equal(r.json().count, 1);
    assert.equal((await prisma.task.findUnique({ where: { id: theirs.id } })).status, 'inbox');
    const r2 = await bulk(a, 'complete', [theirs.id]);
    assert.equal(r2.json().count, 0);
    assert.equal((await prisma.task.findUnique({ where: { id: theirs.id } })).status, 'inbox');
  });
  it('rejects bad input', async () => {
    assert.equal((await bulk(a, 'explode', [1])).status, 400);
    assert.equal((await bulk(a, 'archive', [])).status, 400);
    assert.equal((await bulk(a, 'archive', 'x')).status, 400);
  });
  it('needs sign-in', async () => {
    const { base } = await startApp();
    const anon = new Client(base);
    const r = await bulk(anon, 'archive', [1]);
    assert.ok([401, 403].includes(r.status));
  });
});
