require('../helpers/env');
const { describe, it, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { resetDb, prisma } = require('../helpers/app');
const { createUser, PASSWORD } = require('../helpers/users');
const passwords = require('../../src/lib/passwords');

describe('password rules', () => {
  it('needs at least 10 characters', () => {
    assert.match(passwords.checkNewPassword('123456789'), /at least 10/);
    assert.equal(passwords.checkNewPassword('1234567890'), null);
  });

  it('refuses more than 72 bytes, counting bytes and not characters', () => {
    assert.equal(passwords.checkNewPassword('a'.repeat(72)), null);
    assert.match(passwords.checkNewPassword('a'.repeat(73)), /too long/);
    // 37 two-byte characters is 74 bytes but only 37 characters
    assert.match(passwords.checkNewPassword('é'.repeat(37)), /too long/);
  });

  it('refuses anything that is not a string', () => {
    for (const v of [undefined, null, 12345678901, {}, []]) assert.ok(passwords.checkNewPassword(v));
  });

  it('stores a bcrypt hash, never the password', async () => {
    const hash = await passwords.hashPassword(PASSWORD);
    assert.match(hash, /^\$2[aby]\$12\$/);
    assert.ok(!hash.includes(PASSWORD));
  });
});

describe('authenticate', () => {
  beforeEach(resetDb);

  it('accepts the right password by username or by email, in any case', async () => {
    await createUser({ username: 'sam', email: 'Sam@Example.com', password: PASSWORD });
    assert.equal((await passwords.authenticate('sam', PASSWORD)).username, 'sam');
    assert.equal((await passwords.authenticate('SAM', PASSWORD)).username, 'sam');
    assert.equal((await passwords.authenticate('sam@example.com', PASSWORD)).username, 'sam');
    assert.equal((await passwords.authenticate('  sam  ', PASSWORD)).username, 'sam');
  });

  it('refuses a wrong password, an unknown user and an account with no password the same way', async () => {
    await createUser({ username: 'has-pw', password: PASSWORD });
    await createUser({ username: 'sso-only' });
    assert.equal(await passwords.authenticate('has-pw', 'wrong-wrong-wrong'), null);
    assert.equal(await passwords.authenticate('nobody', PASSWORD), null);
    assert.equal(await passwords.authenticate('sso-only', PASSWORD), null);
    assert.equal(await passwords.authenticate('sso-only', ''), null);
  });

  it('refuses empty and oversized input without throwing', async () => {
    assert.equal(await passwords.authenticate('', PASSWORD), null);
    assert.equal(await passwords.authenticate('sam', ''), null);
    assert.equal(await passwords.authenticate('sam', 'x'.repeat(5000)), null);
    assert.equal(await passwords.authenticate(undefined, undefined), null);
  });

  it('locks an account after 10 wrong passwords, even for the right one', async () => {
    await createUser({ username: 'locked-one', password: PASSWORD });
    for (let i = 0; i < 10; i++) assert.equal(await passwords.authenticate('locked-one', `wrong-password-${i}`), null);
    assert.equal(await passwords.authenticate('locked-one', PASSWORD), null);
  });

  it('does not lock an account that stays under the limit, and a good sign-in clears the count', async () => {
    await createUser({ username: 'careful', password: PASSWORD });
    for (let i = 0; i < 9; i++) await passwords.authenticate('careful', `wrong-password-${i}`);
    assert.ok(await passwords.authenticate('careful', PASSWORD));
    for (let i = 0; i < 9; i++) await passwords.authenticate('careful', `wrong-again-${i}`);
    assert.ok(await passwords.authenticate('careful', PASSWORD));
  });
});

describe('changeOwnPassword', () => {
  beforeEach(resetDb);

  it('needs the current password when there is one', async () => {
    const u = await createUser({ username: 'chg', password: PASSWORD });
    assert.match(await passwords.changeOwnPassword(u.id, 'not-it-at-all', 'another-long-pass-2'), /current password is wrong/);
    assert.match(await passwords.changeOwnPassword(u.id, undefined, 'another-long-pass-2'), /current password is wrong/);
    assert.equal(await passwords.changeOwnPassword(u.id, PASSWORD, 'another-long-pass-2'), null);
    assert.ok(await passwords.authenticate('chg', 'another-long-pass-2'));
    assert.equal(await passwords.authenticate('chg', PASSWORD), null);
  });

  it('lets an account with no password (SSO only) add one without a current password', async () => {
    const u = await createUser({ username: 'sso-adds' });
    assert.equal(await passwords.changeOwnPassword(u.id, undefined, 'a-brand-new-password'), null);
    assert.ok(await passwords.authenticate('sso-adds', 'a-brand-new-password'));
  });

  it('checks the new password rules first, and changes nothing when refused', async () => {
    const u = await createUser({ username: 'rules', password: PASSWORD });
    assert.match(await passwords.changeOwnPassword(u.id, PASSWORD, 'short'), /at least 10/);
    assert.ok(await passwords.authenticate('rules', PASSWORD));
  });

  it('locks guessing of the current password after 10 wrong tries', async () => {
    const u = await createUser({ username: 'guessed', password: PASSWORD });
    for (let i = 0; i < 10; i++) await passwords.changeOwnPassword(u.id, `nope-nope-nope-${i}`, 'another-long-pass-2');
    assert.match(await passwords.changeOwnPassword(u.id, PASSWORD, 'another-long-pass-2'), /Too many wrong attempts/);
    assert.ok(await passwords.authenticate('guessed', PASSWORD), 'the old password still works');
  });

  it('reports a missing account instead of throwing', async () => {
    assert.match(await passwords.changeOwnPassword(999999, 'x', 'a-brand-new-password'), /not found/i);
  });
});

describe('the password sign-in switch', () => {
  beforeEach(resetDb);

  it('is on by default', async () => {
    assert.equal(await passwords.passwordLoginEnabled(), true);
  });

  it('can be turned off only while SSO is set up, so nobody gets locked out', async () => {
    await prisma.systemSetting.create({ data: { key: 'password_login', value: 'false' } });
    assert.equal(await passwords.passwordLoginEnabled(), true, 'no SSO: still on');
    Object.assign(process.env, { OIDC_ISSUER: 'https://sso.invalid/', OIDC_CLIENT_ID: 'a', OIDC_CLIENT_SECRET: 'b' });
    try {
      assert.equal(await passwords.passwordLoginEnabled(), false, 'SSO on: off');
    } finally {
      Object.assign(process.env, { OIDC_ISSUER: '', OIDC_CLIENT_ID: '', OIDC_CLIENT_SECRET: '' });
    }
  });
});
