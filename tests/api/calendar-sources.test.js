require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');

describe('GET /api/v1/calendar: connected calendars', () => {
  let a, alice, bob;
  before(async () => {
    const { base } = await startApp();
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    bob = await createUser({ username: 'bob', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
  });
  const get = () => a.get('/api/v1/calendar?from=2030-01-01&days=7');

  it('says there are none when nothing is connected', async () => {
    const r = await get();
    assert.equal(r.status, 200);
    assert.deepEqual(r.json().sources, []);
  });

  it("lists your active calendars by name, with colour and when they last synced, and no one else's", async () => {
    const synced = new Date('2030-01-01T15:05:00Z');
    await prisma.calendarSource.create({ data: { userId: alice.id, type: 'caldav', name: 'Work', color: '#112233', lastSynced: synced, credentials: { password: 'secret' } } });
    await prisma.calendarSource.create({ data: { userId: alice.id, type: 'google', name: 'Home', color: '#445566' } });
    await prisma.calendarSource.create({ data: { userId: alice.id, type: 'caldav', name: 'Old', active: false } });
    await prisma.calendarSource.create({ data: { userId: bob.id, type: 'caldav', name: 'Bobs' } });
    const { sources } = (await get()).json();
    assert.deepEqual(sources.map((s) => s.name), ['Home', 'Work']);
    assert.equal(sources[1].color, '#112233');
    assert.equal(new Date(sources[1].lastSynced).getTime(), synced.getTime());
    assert.equal(sources[0].lastSynced, null);
  });

  it('never includes credentials', async () => {
    const text = JSON.stringify((await get()).json());
    assert.ok(!text.includes('secret') && !text.includes('credentials'));
  });
});
