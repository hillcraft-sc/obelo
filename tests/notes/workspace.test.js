require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

let a, b, alice, bob;
const old = new Date(Date.now() - 400 * 24 * 60 * 60 * 1000);
const mk = (userId, data) => prisma.note.create({ data: { userId, type: 'note', title: 'x', content: 'c', ...data } });

before(async () => {
  const { base } = await startApp();
  await resetDb();
  alice = await createUser({ username: 'alice', password: PASSWORD });
  bob = await createUser({ username: 'bob', password: PASSWORD });
  await signIn(a = new Client(base), 'alice', PASSWORD);
  await signIn(b = new Client(base), 'bob', PASSWORD);
});

describe('Notes workspace: filters', () => {
  let flagged, slipping, journal, plain, bobFlagged;
  before(async () => {
    flagged = await mk(alice.id, { title: 'F-NOTE', flaggedForReview: true });
    journal = await mk(alice.id, { title: 'J-NOTE', type: 'journal' });
    plain = await mk(alice.id, { title: 'P-NOTE' });
    slipping = await mk(alice.id, { title: 'S-NOTE' });
    await prisma.$executeRaw`UPDATE notes SET updated_at = ${old} WHERE id = ${slipping.id}`;
    bobFlagged = await mk(bob.id, { title: 'BOB-FLAGGED', flaggedForReview: true });
  });

  it('flagged shows only your flagged notes', async () => {
    const t = (await a.get('/notes/workspace?filter=flagged')).text;
    assert.match(t, /F-NOTE/);
    assert.doesNotMatch(t, /P-NOTE|J-NOTE|BOB-FLAGGED/);
  });

  it('slipping shows notes not touched for a long time', async () => {
    const t = (await a.get('/notes/workspace?filter=slipping')).text;
    assert.match(t, /S-NOTE/);
    assert.doesNotMatch(t, /P-NOTE|F-NOTE/);
  });

  it('a type shows only that type; an unknown filter is ignored', async () => {
    assert.match((await a.get('/notes/workspace?filter=journal')).text, /J-NOTE/);
    assert.doesNotMatch((await a.get('/notes/workspace?filter=journal')).text, /P-NOTE/);
    assert.match((await a.get('/notes/workspace?filter=nonsense')).text, /P-NOTE/);
  });
});

describe('Notes workspace: bulk actions', () => {
  it('flags and tags only your own notes, and returns to the workspace', async () => {
    const mine = await mk(alice.id, { title: 'BULK-A' });
    const theirs = await mk(bob.id, { title: 'BULK-B' });
    const res = await a.post('/notes/bulk', { form: [['action', 'add-tags'], ['tags', 'Red, blue'], ['ids', mine.id], ['ids', theirs.id]] });
    assert.equal(res.status, 302);
    assert.equal(res.location, '/notes/workspace');
    assert.deepEqual((await prisma.note.findUnique({ where: { id: mine.id } })).tags.sort(), ['blue', 'red']);
    assert.deepEqual((await prisma.note.findUnique({ where: { id: theirs.id } })).tags, []);
    await a.post('/notes/bulk', { form: [['action', 'delete'], ['ids', mine.id], ['ids', theirs.id]] });
    assert.equal(await prisma.note.findUnique({ where: { id: mine.id } }), null);
    assert.ok(await prisma.note.findUnique({ where: { id: theirs.id } }));
  });
});

describe('Notes workspace: old links', () => {
  it('open the workspace, with filters carried over', async () => {
    assert.equal((await a.get('/notes')).location, '/notes/workspace');
    assert.equal((await a.get('/notes?type=flagged&tag=x')).location, '/notes/workspace?filter=flagged&tag=x');
    assert.equal((await a.get('/notes/new')).location, '/notes/workspace');
    const n = await mk(alice.id, { title: 'LINK' });
    assert.equal((await a.get(`/notes/${n.id}`)).location, `/notes/workspace?id=${n.id}`);
    assert.equal((await a.get(`/notes/${n.id}/edit`)).location, `/notes/workspace?id=${n.id}`);
    assert.equal((await a.get('/notes/abc')).status, 404);
  });

  it("another user's note id gives the empty workspace, not the note", async () => {
    const n = await mk(alice.id, { title: 'ALICE-SECRET' });
    const res = await b.get(`/notes/workspace?id=${n.id}`);
    assert.equal(res.status, 200);
    assert.doesNotMatch(res.text, /ALICE-SECRET/);
  });
});
