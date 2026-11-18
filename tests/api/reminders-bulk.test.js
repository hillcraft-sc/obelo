require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

describe('POST /api/v1/reminders/bulk', () => {
  let a, alice, bob, base;
  before(async () => {
    ({ base } = await startApp());
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    bob = await createUser({ username: 'bob', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
  });
  const make = (user, title, extra = {}) => prisma.reminder.create({
    data: { userId: user.id, title, dueDate: new Date('2030-01-01'), dueTime: '09:00', ...extra },
  });
  const bulk = (c, action, ids) => c.post('/api/v1/reminders/bulk', { json: { action, ids } });

  it('completes several, and says how many', async () => {
    const [r1, r2] = [await make(alice, 'one'), await make(alice, 'two')];
    const r = await bulk(a, 'complete', [r1.id, r2.id]);
    assert.equal(r.status, 200);
    assert.equal(r.json().count, 2);
    const rows = await prisma.reminder.findMany({ where: { id: { in: [r1.id, r2.id] } } });
    assert.deepEqual(rows.map((x) => x.completed), [true, true]);
  });

  it('skips reminders that are already complete', async () => {
    const done = await make(alice, 'done', { completed: true, completedAt: new Date() });
    const open = await make(alice, 'open');
    const r = await bulk(a, 'complete', [done.id, open.id]);
    assert.equal(r.json().count, 1);
  });

  it('a repeating reminder is completed and its next one is made, as when completed one by one', async () => {
    const rep = await make(alice, 'daily', { recurring: true, recurRule: 'daily' });
    await bulk(a, 'complete', [rep.id]);
    assert.equal((await prisma.reminder.findUnique({ where: { id: rep.id } })).completed, true);
    const next = await prisma.reminder.findFirst({ where: { userId: alice.id, title: 'daily', completed: false } });
    assert.ok(next, 'the next occurrence exists');
    assert.ok(next.dueDate > new Date('2030-01-01'), 'with a later due date');
  });

  it('deletes several', async () => {
    const [r1, r2] = [await make(alice, 'x'), await make(alice, 'y')];
    const r = await bulk(a, 'delete', [r1.id, r2.id]);
    assert.equal(r.json().count, 2);
    assert.equal(await prisma.reminder.count({ where: { id: { in: [r1.id, r2.id] } } }), 0);
  });

  it("never touches another user's reminders", async () => {
    const mine = await make(alice, 'mine'), theirs = await make(bob, 'theirs');
    const r = await bulk(a, 'delete', [mine.id, theirs.id]);
    assert.equal(r.json().count, 1);
    assert.ok(await prisma.reminder.findUnique({ where: { id: theirs.id } }));
    const r2 = await bulk(a, 'complete', [theirs.id]);
    assert.equal(r2.json().count, 0);
    assert.equal((await prisma.reminder.findUnique({ where: { id: theirs.id } })).completed, false);
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
