require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

describe('/api/v1/note-templates', () => {
  let a, b, alice, base;
  before(async () => {
    ({ base } = await startApp());
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    await createUser({ username: 'bob', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
    b = new Client(base); await signIn(b, 'bob', PASSWORD);
  });
  const list = async (c) => (await c.get('/api/v1/note-templates')).json().templates;
  const create = (c, json) => c.post('/api/v1/note-templates', { json });
  const mine = { label: 'Standup', type: 'note', title: 'Standup — ', content: '## Done\n- \n' };

  it('starts with the four starters, without Book Review, with the journal title worked out', async () => {
    const t = await list(a);
    assert.deepEqual(t.map((x) => x.label), ['Meeting Notes', 'Weekly Review', 'Project Plan', 'Journal Entry']);
    assert.match(t.find((x) => x.id === 'journal').startTitle, /\d{4} — $/);
    assert.equal(t.find((x) => x.id === 'meeting').startTitle, 'Meeting — ');
  });

  it('adds a template after copying the starters, and keeps it per person', async () => {
    const r = await create(a, mine);
    assert.equal(r.status, 200);
    const made = r.json().template;
    assert.match(made.id, /^t_/);
    assert.equal(made.startTitle, 'Standup — ');
    assert.equal((await list(a)).length, 5);
    assert.equal((await list(b)).length, 4);                 // bob still has the starters only
  });

  it('edits one template and says when it is gone', async () => {
    const id = (await list(a)).find((x) => x.label === 'Standup').id;
    const r = await a.request('PATCH', `/api/v1/note-templates/${id}`, { json: { label: 'Daily standup', dateTitle: true } });
    assert.equal(r.status, 200);
    assert.equal(r.json().template.label, 'Daily standup');
    assert.equal(r.json().template.content, mine.content);
    assert.match(r.json().template.startTitle, /\d{4} — $/);
    assert.equal((await a.request('PATCH', '/api/v1/note-templates/nope', { json: { label: 'x' } })).status, 404);
    assert.equal((await a.request('PATCH', `/api/v1/note-templates/${id}`, { json: { label: '' } })).status, 400);
  });

  it('refuses bad input', async () => {
    assert.equal((await create(a, { ...mine, label: '' })).status, 400);
    assert.equal((await create(a, { ...mine, type: 'task' })).status, 400);
    assert.equal((await create(a, { ...mine, content: 'x'.repeat(20001) })).status, 400);
  });

  it('deletes a starter for good, and an emptied list stays empty', async () => {
    assert.equal((await a.request('DELETE', '/api/v1/note-templates/meeting')).status, 200);
    assert.ok(!(await list(a)).some((x) => x.id === 'meeting'));
    for (const t of await list(a)) await a.request('DELETE', `/api/v1/note-templates/${t.id}`);
    assert.deepEqual(await list(a), []);
    assert.equal((await a.request('DELETE', '/api/v1/note-templates/meeting')).status, 404);
  });

  it('stops at twenty templates', async () => {
    // bob has the four starters, so sixteen more fit
    for (let i = 0; i < 16; i++) assert.equal((await create(b, { ...mine, label: 'T' + i })).status, 200);
    assert.equal((await create(b, mine)).status, 400);
    assert.equal((await list(b)).length, 20);
  });

  it('needs sign-in', async () => {
    const anon = new Client(base);
    assert.ok([401, 403].includes((await anon.get('/api/v1/note-templates')).status));
  });

  it('a note started from a template through the web workspace gets its type, title and text', async () => {
    const c = new Client(base); await signIn(c, 'bob', PASSWORD);
    const first = (await list(c))[0];
    const r = await c.post('/notes/workspace/new', { form: { template: first.id } });
    assert.ok([302, 303].includes(r.status));
    const note = await prisma.note.findFirst({ where: { userId: (await prisma.user.findUnique({ where: { username: 'bob' } })).id }, orderBy: { id: 'desc' } });
    assert.equal(note.title, first.startTitle);
    assert.equal(note.content, first.content);
  });
});
