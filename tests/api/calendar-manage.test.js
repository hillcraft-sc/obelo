require('../helpers/env');
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');
const caldav = require('../../src/services/caldavService');

// The CalDAV calls are replaced: no network. Each test says what the "server" answers.
const real = { discover: caldav.discoverCalendars, sync: caldav.syncSource };
let discoverResult, syncResult;
const calls = [];

describe('managing calendars from the apps (/api/v1/calendar/sources and /local)', () => {
  let a, b, alice, bob;
  const j = (r) => r.json();

  before(async () => {
    const { base } = await startApp();
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    bob = await createUser({ username: 'bob', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
    b = new Client(base); await signIn(b, 'bob', PASSWORD);
    caldav.discoverCalendars = async (...args) => { calls.push(['discover', ...args]); if (discoverResult instanceof Error) throw discoverResult; return discoverResult; };
    caldav.syncSource = async (src) => { calls.push(['sync', src.id]); if (syncResult instanceof Error) throw syncResult; return syncResult; };
  });
  after(() => { caldav.discoverCalendars = real.discover; caldav.syncSource = real.sync; });

  const WORK = [{ url: 'https://dav.example/work/', displayName: 'Work', color: '#aa0000' }, { url: 'https://dav.example/home/', displayName: 'Home' }];
  let sourceId;

  it('adds a CalDAV account, finds its calendars, syncs, and never shows the password', async () => {
    discoverResult = WORK; syncResult = 7;
    const r = await a.request('POST', '/api/v1/calendar/sources', { json: { provider: 'other', username: 'al', password: 'hunter2-secret', serverUrl: 'https://dav.example', color: '#112233' } });
    assert.equal(r.status, 201);
    assert.equal(j(r).found, 2);
    assert.equal(j(r).synced, 7);
    sourceId = j(r).source.id;
    assert.ok(!r.text.includes('hunter2'), 'the password must never come back');
    const stored = await prisma.calendarSource.findUnique({ where: { id: sourceId } });
    assert.ok(!JSON.stringify(stored.credentials).includes('hunter2'), 'and it is stored encrypted');
    const list = j(await a.get('/api/v1/calendar/sources'));
    assert.equal(list.sources.length, 1);
    assert.deepEqual(list.sources[0].calendars.map((c) => [c.name, c.selected]), [['Work', true], ['Home', true]]);
    assert.ok(!JSON.stringify(list).match(/hunter2|passwordEnc|credentials/));
    assert.equal(typeof list.googleConfigured, 'boolean');
  });

  it('says why it could not connect, and adds nothing', async () => {
    discoverResult = new Error('401 Unauthorized');
    const before = await prisma.calendarSource.count();
    const r = await a.request('POST', '/api/v1/calendar/sources', { json: { username: 'al', password: 'wrong' } });
    assert.equal(r.status, 422);
    assert.match(j(r).error, /Could not connect: 401 Unauthorized/);
    assert.equal(await prisma.calendarSource.count(), before);
    assert.equal((await a.request('POST', '/api/v1/calendar/sources', { json: { username: 'al' } })).status, 400);
  });

  it('keeps the account when only the first sync fails, and says so', async () => {
    discoverResult = WORK; syncResult = new Error('timeout');
    const r = await a.request('POST', '/api/v1/calendar/sources', { json: { username: 'al2', password: 'pw' } });
    assert.equal(r.status, 201);
    assert.match(j(r).syncError, /Initial sync failed: timeout/);
    await a.request('DELETE', `/api/v1/calendar/sources/${j(r).source.id}`);
  });

  it('syncs now, and reports a failure as a plain sentence', async () => {
    syncResult = 3;
    assert.equal(j(await a.request('POST', `/api/v1/calendar/sources/${sourceId}/sync`)).count, 3);
    syncResult = new Error('boom');
    const bad = await a.request('POST', `/api/v1/calendar/sources/${sourceId}/sync`);
    assert.equal(bad.status, 422);
    assert.match(j(bad).error, /^Sync failed: boom/);
  });

  it('changes the colour (a hex colour only)', async () => {
    await a.request('PUT', `/api/v1/calendar/sources/${sourceId}`, { json: { color: '#00ff00' } });
    assert.equal((await prisma.calendarSource.findUnique({ where: { id: sourceId } })).color, '#00ff00');
    await a.request('PUT', `/api/v1/calendar/sources/${sourceId}`, { json: { color: 'red; evil' } });
    assert.equal((await prisma.calendarSource.findUnique({ where: { id: sourceId } })).color, '#6366f1');
  });

  it('picks which calendars to show (unknown ones are ignored), then syncs again', async () => {
    syncResult = 2;
    const r = await a.request('PUT', `/api/v1/calendar/sources/${sourceId}/calendars`, { json: { urls: ['https://dav.example/work/', 'https://evil.example/x'] } });
    assert.equal(j(r).selected, 1);
    const cals = j(await a.get('/api/v1/calendar/sources')).sources[0].calendars;
    assert.deepEqual(cals.map((c) => c.selected), [true, false]);
    await a.request('PUT', `/api/v1/calendar/sources/${sourceId}/calendars`, { json: { urls: [] } });
    assert.ok(j(await a.get('/api/v1/calendar/sources')).sources[0].calendars.every((c) => c.selected), 'none picked means all');
  });

  it('sets and clears the family calendar, only from the account\'s own calendars', async () => {
    assert.equal((await a.request('PUT', `/api/v1/calendar/sources/${sourceId}/family`, { json: { url: 'https://evil.example/' } })).status, 400);
    await a.request('PUT', `/api/v1/calendar/sources/${sourceId}/family`, { json: { url: 'https://dav.example/home/' } });
    let src = j(await a.get('/api/v1/calendar/sources')).sources[0];
    assert.equal(src.isFamily, true);
    assert.deepEqual(src.calendars.map((c) => c.isFamily), [false, true]);
    await a.request('PUT', `/api/v1/calendar/sources/${sourceId}/family`, { json: {} });
    src = j(await a.get('/api/v1/calendar/sources')).sources[0];
    assert.equal(src.isFamily, false);
  });

  it("someone else's account is a 404, the same as a missing one, and nothing changes", async () => {
    const before = JSON.stringify(await prisma.calendarSource.findMany({ orderBy: { id: 'asc' } }));
    for (const [m, p, body] of [['POST', 'sync'], ['PUT', '', { color: '#ff0000' }], ['DELETE', ''], ['PUT', 'calendars', { urls: [] }], ['PUT', 'family', { url: 'https://dav.example/home/' }]]) {
      const url = (id) => `/api/v1/calendar/sources/${id}${p ? '/' + p : ''}`;
      const theirs = await b.request(m, url(sourceId), body ? { json: body } : {});
      const missing = await b.request(m, url(999999), body ? { json: body } : {});
      assert.equal(theirs.status, 404, `${m} ${p}`);
      assert.equal(theirs.text, missing.text);
    }
    assert.equal((await b.request('PUT', '/api/v1/calendar/sources/abc', { json: {} })).status, 404);
    assert.equal(JSON.stringify(await prisma.calendarSource.findMany({ orderBy: { id: 'asc' } })), before);
    assert.deepEqual(j(await b.get('/api/v1/calendar/sources')).sources, []);
  });

  it('manages your own calendars and who shares them', async () => {
    const created = await a.request('POST', '/api/v1/calendar/local', { json: { name: ' Family ', color: '#abcdef' } });
    assert.equal(created.status, 201);
    const id = j(created).id;
    assert.equal((await a.request('POST', '/api/v1/calendar/local', { json: { name: '  ' } })).status, 400);
    await a.request('PUT', `/api/v1/calendar/local/${id}`, { json: { name: 'Household', color: '#123456' } });
    assert.equal((await a.request('POST', `/api/v1/calendar/local/${id}/members`, { json: { username: 'nobody' } })).status, 404);
    assert.equal((await a.request('POST', `/api/v1/calendar/local/${id}/members`, { json: { username: 'alice' } })).status, 400);
    const added = await a.request('POST', `/api/v1/calendar/local/${id}/members`, { json: { username: 'bob' } });
    assert.equal(added.status, 201);
    let list = j(await a.get('/api/v1/calendar/sources'));
    assert.deepEqual(list.localCalendars.map((l) => [l.name, l.color, l.members.map((m) => m.username)]), [['Household', '#123456', ['bob']]]);
    assert.ok(list.shareableUsers.some((u) => u.username === 'bob'));

    // Bob can use it, but cannot change it, rename it, or add people
    assert.ok(j(await b.get('/api/v1/calendar/calendars')).calendars.some((c) => c.value === `local_calendar|${id}`));
    for (const [m, p, body] of [['PUT', '', { name: 'X' }], ['DELETE', ''], ['POST', '/members', { username: 'carol' }], ['DELETE', `/members/${alice.id}`]]) {
      assert.equal((await b.request(m, `/api/v1/calendar/local/${id}${p}`, body ? { json: body } : {})).status, 404, `${m} ${p}`);
    }
    await a.request('DELETE', `/api/v1/calendar/local/${id}/members/${bob.id}`);
    assert.deepEqual(j(await a.get('/api/v1/calendar/sources')).localCalendars[0].members, []);
    // Deleting keeps the events
    const ev = await prisma.calendarEvent.create({ data: { userId: alice.id, localCalendarId: id, title: 'Dinner', startAt: new Date(), endAt: new Date() } });
    assert.equal(j(await a.request('DELETE', `/api/v1/calendar/local/${id}`)).ok, true);
    assert.ok(await prisma.calendarEvent.findUnique({ where: { id: ev.id } }));
  });

  it('sets the default calendar (one of yours, or none) and removes an account with its events', async () => {
    assert.equal((await a.request('PUT', '/api/v1/calendar/default', { json: { target: 'local_calendar|424242' } })).status, 400);
    assert.equal((await a.request('PUT', '/api/v1/calendar/default', { json: { target: 'local' } })).status, 200);
    assert.equal(j(await a.get('/api/v1/calendar/sources')).defaultTarget, 'local');
    await prisma.calendarEvent.create({ data: { userId: alice.id, sourceId, title: 'Synced', startAt: new Date(), endAt: new Date() } });
    assert.equal(j(await a.request('DELETE', `/api/v1/calendar/sources/${sourceId}`)).ok, true);
    assert.equal(await prisma.calendarEvent.count({ where: { sourceId } }), 0);
    assert.equal(await prisma.calendarSource.count({ where: { userId: alice.id } }), 0);
  });
});
