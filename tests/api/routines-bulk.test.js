require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

describe('POST /api/v1/routines/bulk', () => {
  let a, alice, bob, base;
  before(async () => {
    ({ base } = await startApp());
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    bob = await createUser({ username: 'bob', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
  });
  const make = (user, title, extra = {}) => prisma.routine.create({ data: { userId: user.id, title, ...extra } });
  const bulk = (c, action, ids) => c.post('/api/v1/routines/bulk', { json: { action, ids } });
  const active = async (id) => (await prisma.routine.findUnique({ where: { id } })).active;

  it('archives and restores several, and says how many', async () => {
    const [r1, r2] = [await make(alice, 'one'), await make(alice, 'two')];
    let r = await bulk(a, 'archive', [r1.id, r2.id]);
    assert.equal(r.status, 200);
    assert.equal(r.json().count, 2);
    assert.equal(await active(r1.id), false);
    r = await bulk(a, 'restore', [r1.id, r2.id]);
    assert.equal(r.json().count, 2);
    assert.equal(await active(r2.id), true);
  });

  it('only counts the ones the action changes', async () => {
    const archived = await make(alice, 'old', { active: false });
    const live = await make(alice, 'live');
    assert.equal((await bulk(a, 'archive', [archived.id, live.id])).json().count, 1);   // the archived one is left as it was
    const stillLive = await make(alice, 'still live');
    assert.equal((await bulk(a, 'restore', [archived.id, stillLive.id])).json().count, 1);   // the live one needs no restoring
  });

  it('deletes several, with their history', async () => {
    const [r1, r2] = [await make(alice, 'x'), await make(alice, 'y')];
    await prisma.routineCompletion.create({ data: { routineId: r1.id, userId: alice.id, completedDate: new Date('2026-11-01') } });
    const r = await bulk(a, 'delete', [r1.id, r2.id]);
    assert.equal(r.json().count, 2);
    assert.equal(await prisma.routine.count({ where: { id: { in: [r1.id, r2.id] } } }), 0);
    assert.equal(await prisma.routineCompletion.count({ where: { routineId: r1.id } }), 0);
  });

  it("never touches another user's routines", async () => {
    const mine = await make(alice, 'mine'), theirs = await make(bob, 'theirs');
    const r = await bulk(a, 'delete', [mine.id, theirs.id]);
    assert.equal(r.json().count, 1);
    assert.ok(await prisma.routine.findUnique({ where: { id: theirs.id } }));
    assert.equal((await bulk(a, 'archive', [theirs.id])).json().count, 0);
    assert.equal(await active(theirs.id), true);
  });

  it('rejects bad input', async () => {
    assert.equal((await bulk(a, 'explode', [1])).status, 400);
    assert.equal((await bulk(a, 'delete', [])).status, 400);
    assert.equal((await bulk(a, 'delete', 'x')).status, 400);
    assert.equal((await bulk(a, 'delete', Array.from({ length: 501 }, (_, i) => i + 1))).status, 400);
  });

  it('needs sign-in', async () => {
    const anon = new Client(base);
    const r = await bulk(anon, 'delete', [1]);
    assert.ok([401, 403].includes(r.status), `got ${r.status}`);
  });
});
