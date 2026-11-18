require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');
const { listRoutes } = require('../helpers/routes');
const { seed, resetContent } = require('../access/fixtures');
const { kindsFor } = require('../access/kinds');

// Things a person can type into any title, name, note or tag. None may ever reach a page as live HTML.
const P1 = '</script><script>window.__x1=1</script>';
const P2 = `'"><img src=x onerror=alert(2)>`;
const P3 = '<svg onload=alert(3)>';
const TAG = `${P1}${P2}`;
// Raw (unescaped) attack text, or a link that runs code. Escaped text has no raw < or >.
const BAD = [
  /<script>window\.__x/, /<\/script><script>window/, /<img src=x onerror/, /<svg onload/,
  /<[a-z][^>]*\s(href|src|action|formaction)=["']?\s*javascript:/i,
];
// Rendered markdown has no legitimate event handlers, so any handler on any tag is an attack
const BAD_MD = [...BAD, /<[a-z][^>]*\son[a-z]+\s*=/i, /<(iframe|style|form|object|embed)\b/i];
const leaks = (html, list = BAD) => list.filter((re) => re.test(html)).map(String);

let base, a, seedA;
before(async () => {
  ({ base } = await startApp());
  await resetDb();
  const C = await createUser({ username: 'carol', password: PASSWORD });
  const A = await createUser({ username: 'alice', password: PASSWORD, role: 'admin', displayName: `Alice ${P2}` });
  await signIn(a = new Client(base), 'alice', PASSWORD);
  await resetContent();
  seedA = await seed(A, C, `${P1} ${P2} ${P3}`);
  // tags, markdown and links with attack text everywhere the app takes text from a person
  await prisma.task.updateMany({ data: { tags: [TAG], notes: `${P2} ${P1}` } });
  await prisma.reminder.updateMany({ data: { tags: [TAG], notes: P3 } });
  await prisma.routine.updateMany({ data: { tags: [TAG], description: P2 } });
  await prisma.bookmark.updateMany({ data: { tags: [TAG], description: P1, url: 'javascript:alert(7)' } });
  await prisma.note.update({ where: { id: seedA.note }, data: { tags: [TAG], content: [
    `# ${P1}`, P2, P3, `[click](javascript:alert(4))`, `![x](x" onerror="alert(5))`, '<a href="javascript:alert(6)">x</a>',
    '```\n</script><script>window.__x1=1</script>\n```', `- [ ] ${P2}`,
  ].join('\n\n') } });
  await prisma.calendarEvent.updateMany({ data: { location: P2, description: P1, url: 'javascript:alert(8)' } });
  await prisma.user.update({ where: { id: A.id }, data: { preferences: { theme: 'dark' } } });
});

const SKIP = /^\/(auth\/oidc|calendar\/auth\/google|settings\/avatar|admin\/logs\/export|js\/|manifest\.json|notes\/tags\.json|api\/)/;

async function page(path) {
  const res = await a.get(path);
  const type = res.text.startsWith('<!DOCTYPE') || res.text.includes('<html') ? 'html' : 'other';
  return { res, type };
}

describe('pages: attack text typed by a person is shown as text, never run', () => {
  it('every list and form page, as an admin who owns the attack data', async () => {
    const routes = listRoutes(require('../../src/app')).filter((r) => r.method === 'GET' && !r.params.length && !SKIP.test(r.path));
    const bad = [];
    for (const r of routes) {
      const { res, type } = await page(r.path);
      if (res.status >= 500) bad.push(`${r.path} -> ${res.status}`);
      if (type === 'html') for (const l of leaks(res.text)) bad.push(`${r.path}: ${l}`);
    }
    assert.ok(routes.length > 25, `swept ${routes.length} pages`);
    assert.deepEqual(bad, []);
  });

  it('every page that shows one thing, for one of each kind', async () => {
    const routes = listRoutes(require('../../src/app')).filter((r) => r.method === 'GET' && r.params.length && kindsFor(r) && !SKIP.test(r.path) && !/attachments\/:filename/.test(r.path) && !/^\/admin/.test(r.path));
    const bad = [];
    for (const r of routes) {
      const url = r.path.replace(/:(\w+)/g, (_, p) => seedA[kindsFor(r)[p]]);
      const { res, type } = await page(url);
      if (res.status >= 500) bad.push(`${url} -> ${res.status}`);
      if (type === 'html') for (const l of leaks(res.text)) bad.push(`${url}: ${l}`);
    }
    assert.ok(routes.length >= 10, `swept ${routes.length} pages`);
    assert.deepEqual(bad, []);
  });

  it('the pages with tabs, filters and views', async () => {
    const q = encodeURIComponent(`${P1}${P2}${P3}`);
    const paths = [
      ...['account', 'modules', 'appearance', 'notifications', 'notes', 'tags', 'dashboard', 'data', 'shortcuts', 'security'].map((t) => `/settings?tab=${t}`),
      ...['today', 'upcoming', 'all', 'inbox', 'completed', 'archived', 'slipping'].map((v) => `/tasks?view=${v}`),
      ...['upcoming', 'overdue', 'completed', 'all'].map((v) => `/reminders?view=${v}`),
      ...['today', 'all', 'archived'].map((v) => `/routines?view=${v}`),
      `/tasks?tag=${q}`, `/notes?tag=${q}`, `/notes?q=${q}`, `/notes/workspace?id=${seedA.note}`, `/notes/workspace?folder=${seedA.folder}`,
      `/reminders?tag=${q}`, `/routines?tag=${q}`, `/bookmarks?tag=${q}`, `/bookmarks?q=${q}`, `/lists?q=${q}`,
      `/search?q=${q}`, `/search/?q=${q}`, `/calendar/?date=2026-12-01`, `/calendar/?view=month&date=2026-12-01`, `/analytics/`,
      `/admin/users?error=${q}&success=${q}`, `/admin/?error=${q}`, `/settings?tab=account&error=${q}&success=${q}`, `/auth/login?error=${q}`,
    ];
    const bad = [];
    for (const path of paths) {
      const { res, type } = await page(path);
      if (res.status >= 500) bad.push(`${path} -> ${res.status}`);
      if (type === 'html') for (const l of leaks(res.text)) bad.push(`${path}: ${l}`);
    }
    assert.deepEqual(bad, []);
  });

  it('search returns the attack text as JSON data, which the page then draws with escaping', async () => {
    const res = await a.get(`/search/?q=${encodeURIComponent('window.__x1')}`);
    assert.equal(res.status, 200);
    assert.ok(res.json().results.length > 0, 'search found the attack data');
  });

  it('the JSON the apps read keeps the text exactly as typed (the apps draw it as text)', async () => {
    const tasks = await a.get('/api/v1/tasks?view=all');
    assert.equal(tasks.status, 200);
    assert.match(tasks.headers?.['content-type'] ?? 'application/json', /json/);
    assert.ok(tasks.json().tasks.some((t) => t.title.includes(P2)), 'the title was changed on the way out');
    const bm = await a.get('/api/v1/bookmarks');
    assert.ok(bm.json().bookmarks.length > 0);
  });
});

describe('markdown a person writes in a note', () => {
  const preview = async (md) => (await a.post('/notes/workspace/preview', { json: { content: md } })).text;
  const workspacePreview = async (md) => (await a.post('/notes/workspace/preview', { json: { content: md } })).text;

  const attacks = {
    'script tag': '<script>window.__x1=1</script>',
    'script tag in a code fence': '```\n<script>window.__x1=1</script>\n```',
    'image with an event handler': '<img src=x onerror=alert(2)>',
    'markdown image that breaks out of its attribute': '![x](x" onerror="alert(5))',
    'javascript link': '[click](javascript:alert(4))',
    'javascript link, mixed case and spaces': '[click]( JaVaScRiPt:alert(4))',
    'data link': '[click](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)',
    'raw anchor': '<a href="javascript:alert(6)">x</a>',
    'iframe': '<iframe src="javascript:alert(9)"></iframe>',
    'svg': '<svg onload=alert(3)>',
    'style with a script url': '<style>@import "javascript:alert(1)";</style>',
    'form': '<form action="javascript:alert(1)"><button>x</button></form>',
    'html comment tricks': '<!--><script>window.__x1=1</script>-->',
    'a heading made of attack text': `# ${P1}`,
    'a table cell': `| a |\n|---|\n| ${P2} |`,
    'a task item': `- [ ] ${P2}`,
  };
  for (const [name, md] of Object.entries(attacks)) {
    it(`${name} is made harmless`, async () => {
      for (const html of [await preview(md), await workspacePreview(md)]) {
        assert.deepEqual(leaks(html, BAD_MD), [], html.slice(0, 200));
      }
    });
  }

  it('ordinary markdown still works (so the checks above are not just stripping everything)', async () => {
    const html = await preview('# Title\n\n**bold** and _italic_ and `code`\n\n- one\n- two\n\n[link](https://example.com)');
    assert.match(html, /<h1[^>]*>Title/);
    assert.match(html, /<strong>bold<\/strong>/);
    assert.match(html, /<li>one<\/li>/);
    assert.match(html, /href="https:\/\/example\.com/);
  });
});

describe('links that come from outside', () => {
  it('a bookmark or an event with a javascript: address is not a link', async () => {
    for (const path of ['/bookmarks/', `/calendar/events/${seedA.event}`, '/calendar/?date=2026-12-01']) {
      const res = await a.get(path);
      assert.doesNotMatch(res.text, /href="javascript:/i, path);
    }
    // and the import will not bring one in
    const json = JSON.stringify({ bookmarks: [{ url: 'javascript:alert(1)', title: 'bad' }, { url: 'data:text/html,x', title: 'bad2' }, { url: 'https://example.com/ok', title: 'fine' }] });
    const body = new FormData(); body.append('file', new Blob([json], { type: 'application/json' }), 'x.json');
    await fetch(`${base}/settings/import/json?_csrf=${await a.csrfToken()}`, { method: 'POST', headers: { Cookie: [...a.jar].map(([k, v]) => `${k}=${v}`).join('; '), 'X-Forwarded-For': a.ip }, body, redirect: 'manual' });
    const urls = (await prisma.bookmark.findMany({ select: { url: true } })).map((b) => b.url);
    assert.ok(urls.includes('https://example.com/ok'), 'the good one was imported');
    assert.ok(!urls.includes('data:text/html,x'), 'an import added a data: bookmark');
    assert.equal(urls.filter((u) => u.startsWith('javascript:')).length, 1, 'only the one seeded straight into the database; the import added none');
  });
});
