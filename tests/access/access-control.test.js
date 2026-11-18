require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');
const { listRoutes } = require('../helpers/routes');
const { seed, snapshot, resetContent } = require('./fixtures');

const { KINDS, EXEMPT, kindsFor, exempt } = require('./kinds');
const CHILD_KINDS = new Set(['subtask', 'attachment', 'attachmentFile', 'thought', 'listItem', 'sharedUser', 'calendarMember']);
const ADMIN_ONLY = /^\/admin\//;


let app, base, routes, A, B, C, a, b, a2, seedA, seedB;

async function setup() {
  await resetDb();
  C = await createUser({ username: 'carol', password: PASSWORD });
  A = await createUser({ username: 'alice', password: PASSWORD });
  B = await createUser({ username: 'bob', password: PASSWORD });
  a = new Client(base); b = new Client(base);
  await signIn(a, 'alice', PASSWORD);
  await signIn(b, 'bob', PASSWORD);
}
// The session id inside a client's cookie
const sidOf = (client) => decodeURIComponent(client.jar.get('connect.sid') || '').replace(/^s:/, '').split('.')[0];

// Alice needs a second device for the "sign out another device" routes
async function reseed({ freshDevice = false } = {}) {
  await resetContent();
  if (freshDevice || !a2) { a2 = new Client(base); await signIn(a2, 'alice', PASSWORD); }
  seedA = await seed(A, C, 'A-SECRET', { currentSid: sidOf(a) });
  seedB = await seed(B, C, 'B-OWN', { currentSid: sidOf(b) });
}

// An answer with the ids that were asked about blanked out, so two answers can be compared
function normalise(res, ...idSets) {
  let out = `${res.status}|${res.location}|${res.text}`;
  for (const v of idSets.flatMap((s) => Object.values(s))) out = out.split(String(encodeURIComponent(v))).join('<id>');
  return out;
}

const fill = (template, ids) => template.replace(/:(\w+)/g, (_, p) => encodeURIComponent(ids[p]));
const BODY = {
  title: 'B-WAS-HERE', name: 'B-WAS-HERE', content: 'B-WAS-HERE', text: 'B-WAS-HERE', description: 'B-WAS-HERE',
  notes: 'B-WAS-HERE', status: 'today', priority: 'high', url: 'https://example.com/b-was-here', username: 'carol',
  pin: '123456', newPin: '654321', currentPin: '123456', dueDate: '2026-12-31', dueTime: '09:00', minutes: 10,
  color: '#ff0000', tags: 'b', date: '2026-12-31', startTime: '09:00', endTime: '10:00', userId: 99999, username2: 'x',
  duration: '15min', index: 0, checked: true,
};

async function call(client, route, ids, extraBody = {}) {
  const url = fill(route.path, ids);
  if (route.method === 'POST' && /\/attachments$/.test(route.path)) return client.upload(url, 'photo', Buffer.from('x'));
  // A checklist toggle must quote the item's text, so use the one in Alice's note
  const special = /\/checklist$/.test(route.path) ? { text: 'A-SECRET step' } : {};
  return client.request(route.method, url, route.method === 'GET' ? {} : { json: { ...BODY, ...special, ...extraBody } });
}

before(async () => {
  // "Sync now" would log in to a calendar server: answer as if it worked
  require('../../src/services/caldavService').syncSource = async () => 0;
  ({ base } = await startApp());
  app = require('../../src/app');
  routes = listRoutes(app).filter((r) => r.params.length);
  await setup();
});

describe('every route that takes an id', () => {
  it('is accounted for: a new route with an id must be added to KINDS (or EXEMPT, with a reason)', () => {
    const unknown = routes.filter((r) => !kindsFor(r) && !exempt(r)).map((r) => `${r.method} ${r.path}`);
    assert.deepEqual(unknown, [], 'these routes take an id but the access-control test does not know what it stands for');
    const missing = routes.filter((r) => kindsFor(r)).flatMap((r) =>
      r.params.filter((p) => !(p in kindsFor(r))).map((p) => `${r.method} ${r.path} :${p}`));
    assert.deepEqual(missing, [], 'a parameter has no kind');
  });

  it('works for the owner (so the fixtures are real and the attack tests mean something)', async () => {
    const notFound = [], errors = [], weak = [];
    for (const route of routes.filter((r) => kindsFor(r) && !ADMIN_ONLY.test(r.path))) {
      await reseed({ freshDevice: kindsFor(route).key === 'sessionKey' });
      const kinds = kindsFor(route);
      const ids = Object.fromEntries(Object.entries(kinds).map(([p, k]) => [p, seedA[k]]));
      const res = await call(a, route, ids, { ids: [seedA.listItem] });
      // 400/409/423 here means the request body was refused, so the attack test below would prove nothing
      if (![200, 201, 204, 302].includes(res.status) || /[?&]error=/.test(res.location || '')) weak.push(`${route.method} ${route.path} -> ${res.status} ${res.location || ''}`);
      if (res.status === 404) notFound.push(`${route.method} ${route.path}`);
      if (res.status >= 500) errors.push(`${route.method} ${route.path} -> ${res.status}`);
    }
    assert.deepEqual(errors, [], 'the owner got a server error');
    assert.deepEqual(notFound, [], 'the owner got 404 on their own things: the fixture does not match the route');
    assert.deepEqual(weak, [], 'the owner\'s own request was refused, so testing someone else against it proves nothing');
  });

  it('gives someone else the same answer as for an id that does not exist, changes nothing and leaks nothing', async () => {
    const problems = [];
    for (const route of routes.filter((r) => kindsFor(r) && !ADMIN_ONLY.test(r.path))) {
      await reseed({ freshDevice: kindsFor(route).key === 'sessionKey' });
      const kinds = kindsFor(route);
      const owned = Object.fromEntries(Object.entries(kinds).map(([p, k]) => [p, seedA[k]]));
      const kindEntries = Object.entries(kinds);
      const nothing = (k) => (k === 'sessionKey' ? 'ffffffffffffffff' : k === 'attachmentFile' ? 'nonexistent.png' : 999999);
      // [label, the ids Bob uses, the same request with ids that do not exist]
      const variants = [[
        'everything is Alice\'s', owned,
        Object.fromEntries(kindEntries.map(([p, k]) => [p, nothing(k)])),
      ]];
      if (kindEntries.length > 1) {
        // Bob's OWN parent, Alice's child: access to the parent in the URL proves nothing about the child
        variants.push([
          'Bob\'s own parent, Alice\'s child',
          Object.fromEntries(kindEntries.map(([p, k], i) => [p, i === 0 ? seedB[k] : seedA[k]])),
          Object.fromEntries(kindEntries.map(([p, k], i) => [p, i === 0 ? seedB[k] : nothing(k)])),
        ]);
      }
      if (/\/items\/reorder$/.test(route.path)) {
        // Bob's own list, but Alice's item ids in the body
        variants.push(['Bob\'s own list, Alice\'s items in the body', { id: seedB.list }, { id: seedB.list }, { ids: [seedA.listItem] }, { ids: [999999] }]);
      }
      for (const [label, ids, ghost, body = { ids: [seedA.listItem] }, ghostBody = { ids: [999999] }] of variants) {
        const before = await snapshot(A.id);
        const res = await call(b, route, ids, body);
        const after = await snapshot(A.id);
        const ref = await call(b, route, ghost, ghostBody);
        const where = `${route.method} ${route.path} (${label})`;
        const same = (r) => normalise(r, ids, ghost);
        if (res.status >= 500) problems.push(`${where}: server error ${res.status}`);
        if (res.status !== ref.status) problems.push(`${where}: answers ${res.status} for Alice's id but ${ref.status} for an id that does not exist`);
        else if (same(res) !== same(ref)) problems.push(`${where}: the answer differs from the one for an id that does not exist`);
        if (before !== after) problems.push(`${where}: CHANGED Alice's data`);
        if (res.text.includes('A-SECRET')) problems.push(`${where}: the answer contains Alice's data`);
      }
    }
    assert.deepEqual(problems, []);
  });
});

// Someone else's id can also arrive in the BODY of a request: moving your own note into another
// person's folder, or making your folder a child of theirs.
describe('someone else\'s id inside a request', () => {
  const asBob = (kind) => ({ folder: seedA.folder, ghost: 999999 })[kind];
  const CASES = [
    ['POST', '/api/v1/notes', () => ({}), (f) => ({ title: 'B-WAS-HERE', content: 'x', folderId: f })],
    ['PUT', '/api/v1/notes/:note', () => ({ note: seedB.note }), (f) => ({ title: 'B-WAS-HERE', content: 'x', folderId: f })],
    ['POST', '/api/v1/notes/:note/move', () => ({ note: seedB.note }), (f) => ({ folderId: f })],
    ['POST', '/api/v1/folders', () => ({}), (f) => ({ name: 'B-WAS-HERE', parentId: f })],
    ['POST', '/notes/workspace/new', () => ({}), (f) => ({ title: 'B-WAS-HERE', folderId: f })],
    ['POST', '/notes/workspace/folders', () => ({}), (f) => ({ name: 'B-WAS-HERE', parentId: f })],
    ['POST', '/notes/workspace/notes/:note/move', () => ({ note: seedB.note }), (f) => ({ folderId: f })],
  ];

  for (const [method, template, ids, body] of CASES) {
    it(`${method} ${template}: Alice's folder is refused exactly like a folder that does not exist`, async () => {
      await reseed();
      const url = template.replace(/:(\w+)/g, (_, k) => ids()[k]);
      const before = await snapshot(A.id);
      const real = await b.request(method, url, { json: body(asBob('folder')) });
      const after = await snapshot(A.id);
      const ghost = await b.request(method, url, { json: body(asBob('ghost')) });
      const clean = (r) => `${r.status}|${r.location}|${r.text}`.split(String(seedA.folder)).join('<id>').split('999999').join('<id>');
      assert.ok(real.status < 500, `server error ${real.status}`);
      assert.equal(clean(real), clean(ghost), 'Alice\'s folder and a missing folder get different answers');
      assert.equal(before, after, 'Alice\'s data changed');
      assert.equal(await prisma.note.count({ where: { userId: B.id, folderId: seedA.folder } }), 0, 'Bob\'s note is now inside Alice\'s folder');
      assert.equal(await prisma.folder.count({ where: { userId: B.id, parentId: seedA.folder } }), 0, 'Bob\'s folder is now inside Alice\'s folder');
    });
  }

  it('Bob can put his own note in his own folder (so the cases above are real refusals)', async () => {
    await reseed();
    const res = await b.post(`/api/v1/notes/${seedB.note}/move`, { json: { folderId: seedB.folder } });
    assert.equal(res.status, 200);
  });
});

// Exports put one person's data in one download: the file must hold only that person's data.
describe('data exports', () => {
  const NAMES = ['json', 'tasks.csv', 'notes.json', 'bookmarks.csv', 'bookmarks.html'];
  for (const name of NAMES) {
    for (const prefix of ['/settings/export', '/api/v1/settings/export']) {
      it(`${prefix}/${name} holds only your own data`, async () => {
        await reseed();
        const mine = await b.get(`${prefix}/${name}`);
        assert.equal(mine.status, 200, `${prefix}/${name}`);
        assert.ok(!mine.text.includes('A-SECRET'), 'Bob\'s export contains Alice\'s data');
        const hers = await a.get(`${prefix}/${name}`);
        assert.equal(hers.status, 200);
        assert.ok(hers.text.includes('A-SECRET'), `Alice's own ${name} lacks her data`);
        assert.ok(!hers.text.includes('B-OWN'), 'Alice\'s export contains Bob\'s data');
      });
    }
  }

  it('an unknown export name is a clean 404 and not a server error', async () => {
    for (const name of ['nope', '..%2F..%2Fetc%2Fpasswd', 'json%00']) {
      const res = await b.get(`/settings/export/${name}`);
      assert.ok([400, 404].includes(res.status), `${name} -> ${res.status}`);
    }
  });
});

// The admin pages and actions are for admins only. A normal user must change nothing there.
describe('admin routes', () => {
  it('refuse a normal user, and change nothing', async () => {
    await reseed();
    const adminRoutes = listRoutes(app).filter((r) => ADMIN_ONLY.test(r.path));
    assert.ok(adminRoutes.length >= 8, 'found the admin routes');
    await prisma.systemSetting.create({ data: { key: 'maintenance_message', value: 'unchanged' } });
    const users = await prisma.user.findMany({ orderBy: { id: 'asc' } });
    const logs = await prisma.appLog.count();
    const problems = [];
    for (const route of adminRoutes) {
      const url = route.path.replace(/:(\w+)/g, () => A.id);
      const res = await b.request(route.method, url, route.method === 'GET' ? {} : { json: { username: 'intruder', password: 'x'.repeat(12), maintenance_message: 'hacked', role: 'admin', email: 'i@example.com' } });
      if (res.status === 200 || res.status >= 500) problems.push(`${route.method} ${route.path} -> ${res.status}`);
      if (/Admin/.test(res.text) && /System Settings|Create User/.test(res.text)) problems.push(`${route.method} ${route.path} showed admin content`);
    }
    assert.deepEqual(problems, []);
    assert.deepEqual(await prisma.user.findMany({ orderBy: { id: 'asc' } }), users, 'a user was changed, added or removed');
    assert.equal((await prisma.systemSetting.findUnique({ where: { key: 'maintenance_message' } })).value, 'unchanged');
    assert.ok((await prisma.appLog.count()) >= logs, 'the log was cleared');
  });

  it('are fine for an admin (so the refusals above are real)', async () => {
    const boss = await createUser({ username: 'boss-for-admin-check', password: PASSWORD, role: 'admin' });
    const c = new Client(base);
    await signIn(c, 'boss-for-admin-check', PASSWORD);
    assert.equal((await c.get('/admin')).status, 200);
    assert.equal((await c.get('/admin/users')).status, 200);
    await prisma.user.delete({ where: { id: boss.id } });
  });
});
