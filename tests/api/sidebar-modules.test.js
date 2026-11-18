require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');
const { MODULES, SIDEBAR_LAYOUT, sidebarGroupsFor } = require('../../src/config/modules');

const mods = (...keys) => keys.map((k) => MODULES.find((m) => m.key === k));

describe('the sidebar: fixed groups, whatever order was saved', () => {
  it('puts modules in the groups and order of the layout', () => {
    const groups = sidebarGroupsFor(mods('dashboard', 'capture', 'notes', 'tasks', 'lists', 'reminders', 'routines', 'calendar', 'bookmarks', 'analytics', 'settings'));
    assert.deepEqual(groups.map((g) => g.title), [null, 'Do', 'Write', 'Plan', 'See']);
    assert.deepEqual(groups[1].modules.map((m) => m.key), ['tasks', 'reminders', 'routines']);
    assert.deepEqual(groups[2].modules.map((m) => m.key), ['notes', 'lists', 'bookmarks']);
  });

  it('is the same for a shuffled saved order', () => {
    const a = sidebarGroupsFor(mods('dashboard', 'lists', 'notes', 'routines', 'tasks', 'reminders', 'capture', 'bookmarks', 'calendar', 'analytics', 'ai', 'settings'));
    const b = sidebarGroupsFor(mods('dashboard', 'capture', 'tasks', 'reminders', 'routines', 'notes', 'lists', 'bookmarks', 'calendar', 'analytics', 'ai', 'settings'));
    assert.deepEqual(a.map((g) => [g.title, g.modules.map((m) => m.key)]), b.map((g) => [g.title, g.modules.map((m) => m.key)]));
  });

  it('leaves out Settings and modules that are off, and drops empty groups', () => {
    const groups = sidebarGroupsFor(mods('dashboard', 'tasks', 'settings'));
    assert.deepEqual(groups.map((g) => [g.title, g.modules.map((m) => m.key)]), [[null, ['dashboard']], ['Do', ['tasks']]]);
  });

  it('gives a module the layout does not place a "More" group', () => {
    const groups = sidebarGroupsFor([...mods('dashboard'), { key: 'journal', label: 'Journal', route: '/journal', icon: '' }]);
    assert.equal(groups.at(-1).title, 'More');
    assert.deepEqual(groups.at(-1).modules.map((m) => m.key), ['journal']);
  });

  it('places every module that is not Settings', () => {
    const placed = new Set(SIDEBAR_LAYOUT.flatMap(([, keys]) => keys));
    for (const m of MODULES.filter((x) => x.key !== 'settings')) assert.ok(placed.has(m.key), `${m.key} needs a place in SIDEBAR_LAYOUT`);
  });
});

describe('web: the sidebar and the Modules tab', () => {
  let a, alice;
  before(async () => {
    const { base } = await startApp();
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
  });

  it('shows the group names and the profile block as the way to Settings', async () => {
    const page = (await a.get('/bookmarks')).text;
    const nav = page.slice(page.indexOf('<nav class="flex-1 min-h-0'), page.indexOf('</nav>', page.indexOf('<nav class="flex-1 min-h-0')));
    for (const title of ['Do', 'Write', 'Plan', 'See']) assert.ok(nav.includes(`>${title}</p>`), `group ${title}`);
    assert.ok(!nav.includes('href="/settings"'), 'Settings is no longer in the list of modules');
    assert.ok(page.includes('href="/settings" title="Settings"'), 'the profile block opens Settings');
    assert.ok(nav.indexOf('>Tasks<') < nav.indexOf('>Reminders<') && nav.indexOf('>Reminders<') < nav.indexOf('>Routines<'), 'Do is in its fixed order');
  });

  it('has no drag handles or bottom-bar badges on the Modules tab, and says where the phone order is set', async () => {
    const page = (await a.get('/settings?tab=modules')).text;
    assert.ok(!page.includes('drag-handle') && !page.includes('bar-badge') && !page.includes('module-order-input'));
    assert.ok(page.includes('Switch modules on or off'));
    assert.ok(page.includes("set in the iPhone app"));
  });

  it("saving the tab switches modules on and off but leaves the phone's saved order alone", async () => {
    await prisma.userModule.createMany({ data: [
      { userId: alice.id, moduleKey: 'tasks', enabled: true, position: 7 },
      { userId: alice.id, moduleKey: 'notes', enabled: true, position: 3 },
    ] });
    const r = await a.post('/settings/modules', { form: { tasks: 'on' } });
    assert.equal(r.status, 302);
    const rows = Object.fromEntries((await prisma.userModule.findMany({ where: { userId: alice.id } })).map((m) => [m.moduleKey, m]));
    assert.equal(rows.tasks.position, 7);
    assert.equal(rows.notes.position, 3);
    assert.equal(rows.tasks.enabled, true);
    assert.equal(rows.notes.enabled, false);
  });
});
