require('../helpers/env');
const { describe, it, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb, prisma } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');
const passwords = require('../../src/lib/passwords');

let base;
before(async () => { ({ base } = await startApp()); });
beforeEach(resetDb);

const NEW_PW = 'chosen-by-the-person-1';
const BAD_CODE = /didn.t work/;
const codeOf = (html) => html.match(/tracking-widest[^>]*>\s*([A-Z2-9]{4}-[A-Z2-9]{4})/)?.[1];
const linkOf = (html) => html.match(/value="(http[^"]*\/auth\/password\/[^"]+)"/)?.[1];

// An admin signs in and issues a link and code for a new account, the way the admin page does
async function adminIssues(username = 'newbie') {
  await createUser({ username: 'boss', password: PASSWORD, role: 'admin' });
  const admin = new Client(base);
  await signIn(admin, 'boss', PASSWORD);
  const created = await admin.post('/admin/users/create', { form: { username, displayName: username, timezone: 'America/New_York' } });
  assert.equal(created.status, 302);
  const page = await admin.get('/admin/users');
  return { admin, code: codeOf(page.text), link: linkOf(page.text), page, username };
}

const redeemByCode = (username, code, newPassword = NEW_PW, client = new Client(base)) =>
  client.post('/api/v1/auth/password-code', { json: { username, code, newPassword } });

describe('admin issues a link and a setup code', () => {
  it('shows both once, for an account created without an email', async () => {
    const { admin, code, link, username } = await adminIssues();
    assert.match(code, /^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    assert.match(link, /\/auth\/password\/[A-Za-z0-9_-]{20,}$/);
    const again = await admin.get('/admin/users');
    assert.equal(codeOf(again.text), undefined, 'the code is shown only once');
    assert.equal(linkOf(again.text), undefined, 'the link is shown only once');
    const user = await prisma.user.findUnique({ where: { username } });
    assert.equal(user.passwordHash, null, 'an admin never sets a password');
  });

  it('stores only hashes of the token and the code', async () => {
    const { code, link } = await adminIssues();
    const token = link.split('/').pop();
    const row = await prisma.passwordToken.findFirst();
    assert.notEqual(row.tokenHash, token);
    assert.match(row.tokenHash, /^[0-9a-f]{64}$/);
    assert.match(row.codeHash, /^\$2[aby]\$/);
    assert.ok(!JSON.stringify(row).includes(code.replace('-', '')));
    assert.ok(!JSON.stringify(row).includes(token));
  });

  it('makes a new code and link for "Reset password", and the old pair stops working', async () => {
    const { admin, code: oldCode, link: oldLink, username } = await adminIssues();
    const user = await prisma.user.findUnique({ where: { username } });
    await admin.post(`/admin/users/${user.id}/password-link`);
    const page = await admin.get('/admin/users');
    const newCode = codeOf(page.text);
    assert.notEqual(newCode, oldCode);
    assert.match((await redeemByCode(username, oldCode)).text, BAD_CODE);
    const oldPage = await new Client(base).get(new URL(oldLink).pathname);
    assert.match(oldPage.text, /expired or was already used/);
    assert.equal((await redeemByCode(username, newCode)).status, 200);
  });

  it('only admins can issue them, and a bad id is a clean refusal', async () => {
    await createUser({ username: 'plain', password: PASSWORD });
    const target = await createUser({ username: 'target' });
    const c = new Client(base);
    await signIn(c, 'plain', PASSWORD);
    const res = await c.post(`/admin/users/${target.id}/password-link`);
    assert.notEqual(res.status, 200);
    assert.equal(await prisma.passwordToken.count(), 0, 'a normal user created a token');

    await createUser({ username: 'boss', password: PASSWORD, role: 'admin' });
    const admin = new Client(base);
    await signIn(admin, 'boss', PASSWORD);
    for (const id of ['abc', '999999', '1.5', '-1']) {
      const r = await admin.post(`/admin/users/${id}/password-link`);
      assert.equal(r.status, 302, id);
      assert.match(r.location, /error=/);
    }
  });

  it('has no way for an admin to choose someone else\'s password', async () => {
    const { admin, username } = await adminIssues();
    const user = await prisma.user.findUnique({ where: { username } });
    for (const path of [`/admin/users/${user.id}/password`, `/admin/users/${user.id}/set-password`]) {
      const res = await admin.post(path, { form: { password: 'admin-chosen-pass-1' } });
      assert.equal(res.status, 404, path);
    }
    assert.equal((await prisma.user.findUnique({ where: { id: user.id } })).passwordHash, null);
  });
});

describe('choosing a password with a setup code (the apps and the login page)', () => {
  it('sets the password and the person can sign in', async () => {
    const { code, username } = await adminIssues();
    const res = await redeemByCode(username, code);
    assert.equal(res.status, 200);
    const c = new Client(base);
    assert.equal((await signIn(c, username, NEW_PW)).status, 302);
  });

  it('accepts the code in lowercase, without the dash, with spaces, and the username in any case', async () => {
    const { code, username } = await adminIssues();
    const typed = ` ${code.toLowerCase().replace('-', ' ')} `;
    assert.equal((await redeemByCode(username.toUpperCase(), typed)).status, 200);
  });

  it('works only once', async () => {
    const { code, username } = await adminIssues();
    assert.equal((await redeemByCode(username, code)).status, 200);
    const again = await redeemByCode(username, code, 'something-else-entirely-2');
    assert.equal(again.status, 400);
    assert.match(again.text, BAD_CODE);
    assert.ok(await passwords.authenticate(username, NEW_PW), 'the first password is still the one in force');
  });

  it('burns the link too, and the link burns the code', async () => {
    const first = await adminIssues('byCode');
    await redeemByCode(first.username, first.code);
    const linkPage = await new Client(base).get(new URL(first.link).pathname);
    assert.match(linkPage.text, /expired or was already used/);

    const second = await adminIssues2('byLink');
    const path = new URL(second.link).pathname;
    const res = await new Client(base).post(path, { form: { password: NEW_PW, confirm: NEW_PW } });
    assert.equal(res.status, 302);
    assert.match((await redeemByCode(second.username, second.code)).text, BAD_CODE);
  });

  it('refuses a wrong code, an unknown user and a user with no code, all with the same message', async () => {
    const { username } = await adminIssues();
    await createUser({ username: 'nocode' });
    const answers = new Set();
    for (const [u, code] of [[username, 'AAAA-AAAA'], ['nobody', 'AAAA-AAAA'], ['nocode', 'AAAA-AAAA'], [username, 'short'], [username, '']]) {
      const res = await redeemByCode(u, code);
      assert.equal(res.status, 400, `${u} ${code}`);
      answers.add(res.text);
    }
    assert.equal(answers.size, 1, 'the answers differ, which would reveal which usernames exist');
  });

  it('checks the new password before using up the code', async () => {
    const { code, username } = await adminIssues();
    const short = await redeemByCode(username, code, 'short');
    assert.equal(short.status, 400);
    assert.match(short.text, /at least 10/);
    assert.equal((await redeemByCode(username, code)).status, 200, 'the code was not burned');
  });

  it('refuses an expired code', async () => {
    const { code, username } = await adminIssues();
    await prisma.passwordToken.updateMany({ data: { expiresAt: new Date(Date.now() - 1000) } });
    assert.match((await redeemByCode(username, code)).text, BAD_CODE);
  });

  it('locks the account\'s code after 10 wrong tries, even for the right code', async () => {
    const { code, username } = await adminIssues('guessme');
    for (let i = 0; i < 10; i++) await redeemByCode(username, `ZZZZ-ZZ${(i % 8) + 2}${(i % 7) + 2}`);
    const res = await redeemByCode(username, code);
    assert.equal(res.status, 400);
    assert.match(res.text, BAD_CODE);
  });

  it('signs the person out everywhere when they set a password', async () => {
    const { code, username } = await adminIssues();
    const user = await prisma.user.findUnique({ where: { username } });
    // they already have a session on some device
    await prisma.user.update({ where: { id: user.id }, data: { passwordHash: await passwords.hashPassword(PASSWORD) } });
    const device = new Client(base);
    await signIn(device, username, PASSWORD);
    assert.equal((await device.get('/settings')).status, 200);
    await redeemByCode(username, code);
    assert.equal((await device.get('/settings')).status, 302, 'the old session should be gone');
  });

  it('does not work while an admin has switched passwords off and SSO is on', async () => {
    const { code, username } = await adminIssues();
    await prisma.systemSetting.create({ data: { key: 'password_login', value: 'false' } });
    Object.assign(process.env, { OIDC_ISSUER: 'https://sso.invalid/', OIDC_CLIENT_ID: 'a', OIDC_CLIENT_SECRET: 'b' });
    try {
      assert.equal((await redeemByCode(username, code)).status, 403);
    } finally {
      Object.assign(process.env, { OIDC_ISSUER: '', OIDC_CLIENT_ID: '', OIDC_CLIENT_SECRET: '' });
    }
    assert.equal((await prisma.user.findUnique({ where: { username } })).passwordHash, null);
  });

  it('works from the login page\'s "Have a setup code?" form too', async () => {
    const { code, username } = await adminIssues();
    const c = new Client(base);
    assert.equal((await c.get('/auth/code')).status, 200);
    const mismatch = await c.post('/auth/code', { form: { username, code, password: NEW_PW, confirm: 'nope' } });
    assert.equal(mismatch.status, 400);
    const res = await c.post('/auth/code', { form: { username, code, password: NEW_PW, confirm: NEW_PW } });
    assert.equal(res.status, 302);
    assert.match(res.location, /\/auth\/login/);
    assert.equal((await signIn(new Client(base), username, NEW_PW)).status, 302);
  });
});

describe('choosing a password from the one-time link', () => {
  it('shows the form for a good link and a polite page for a bad one', async () => {
    const { link } = await adminIssues();
    const good = await new Client(base).get(new URL(link).pathname);
    assert.match(good.text, /Choose your password/);
    const bad = await new Client(base).get('/auth/password/not-a-real-token-at-all-0123456789');
    assert.equal(bad.status, 200);
    assert.match(bad.text, /expired or was already used/);
  });

  it('refuses a mismatch, a short password and a replay, and works once', async () => {
    const { link, username } = await adminIssues();
    const path = new URL(link).pathname;
    const c = new Client(base);
    assert.equal((await c.post(path, { form: { password: NEW_PW, confirm: 'nope' } })).status, 400);
    assert.equal((await c.post(path, { form: { password: 'short', confirm: 'short' } })).status, 400);
    const ok = await c.post(path, { form: { password: NEW_PW, confirm: NEW_PW } });
    assert.equal(ok.status, 302);
    assert.equal((await c.post(path, { form: { password: 'again-again-again-1', confirm: 'again-again-again-1' } })).status, 400);
    assert.ok(await passwords.authenticate(username, NEW_PW));
  });

  it('refuses two submissions at the same moment from using the link twice', async () => {
    const { link, username } = await adminIssues();
    const path = new URL(link).pathname;
    const results = await Promise.all([
      new Client(base).post(path, { form: { password: 'first-choice-pass-1', confirm: 'first-choice-pass-1' } }),
      new Client(base).post(path, { form: { password: 'second-choice-pass-1', confirm: 'second-choice-pass-1' } }),
    ]);
    assert.equal(results.filter((r) => r.status === 302).length, 1, results.map((r) => r.status).join());
    const winners = ['first-choice-pass-1', 'second-choice-pass-1'];
    const works = (await Promise.all(winners.map((p) => passwords.authenticate(username, p)))).filter(Boolean);
    assert.equal(works.length, 1, 'exactly one of the two passwords is in force');
  });
});

// A second admin run in the same test: the admin and the user are made separately from the first
async function adminIssues2(username) {
  const admin = new Client(base);
  await signIn(admin, 'boss', PASSWORD);
  await admin.post('/admin/users/create', { form: { username, displayName: username, timezone: 'America/New_York' } });
  const page = await admin.get('/admin/users');
  return { admin, code: codeOf(page.text), link: linkOf(page.text), username };
}
