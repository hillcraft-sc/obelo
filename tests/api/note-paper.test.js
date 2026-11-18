require('../helpers/env');
const { describe, it, before } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb } = require('../helpers/app');
const { Client } = require('../helpers/client');
const { createUser, signIn, PASSWORD } = require('../helpers/users');
const { isPaperDark, notePaperChoice } = require('../../src/config/themes');

describe('handwriting paper: which paper a setting and theme give', () => {
  it('follows the theme by default, and is forced by Dark or White', () => {
    assert.equal(notePaperChoice({}), 'theme');
    assert.equal(notePaperChoice({ notePaper: 'sepia' }), 'theme');
    assert.equal(isPaperDark({ theme: 'dark' }), true);
    assert.equal(isPaperDark({ theme: 'light' }), false);
    assert.equal(isPaperDark({ theme: 'custom', customBase: 'light' }), false);
    assert.equal(isPaperDark({ theme: 'light', notePaper: 'dark' }), true);
    assert.equal(isPaperDark({ theme: 'dark', notePaper: 'white' }), false);
  });
});

describe('/api/v1 handwriting paper setting', () => {
  let a, b;
  before(async () => {
    const { base } = await startApp();
    await resetDb();
    await createUser({ username: 'alice', password: PASSWORD });
    await createUser({ username: 'bob', password: PASSWORD });
    a = new Client(base); await signIn(a, 'alice', PASSWORD);
    b = new Client(base); await signIn(b, 'bob', PASSWORD);
  });
  const notes = async (c) => (await c.get('/api/v1/settings/notes')).json();
  const put = (c, json) => c.request('PUT', '/api/v1/settings/notes', { json });

  it('starts as Match theme, in the settings and in /me', async () => {
    assert.equal((await notes(a)).notePaper, 'theme');
    assert.equal((await a.get('/api/v1/me')).json().notePaper, 'theme');
  });

  it('saves Dark and White per person, and a save without it keeps the choice', async () => {
    assert.equal((await put(a, { autosaveEnabled: true, autosaveDuration: 'immediate', notePaper: 'white' })).status, 200);
    assert.equal((await notes(a)).notePaper, 'white');
    assert.equal((await a.get('/api/v1/me')).json().notePaper, 'white');
    assert.equal((await put(a, { autosaveEnabled: true, autosaveDuration: '5min' })).status, 200);
    const n = await notes(a);
    assert.equal(n.notePaper, 'white');
    assert.equal(n.autosaveDuration, '5min');
    assert.equal((await notes(b)).notePaper, 'theme');
  });

  it('refuses an unknown paper', async () => {
    assert.equal((await put(a, { autosaveEnabled: true, autosaveDuration: 'immediate', notePaper: 'sepia' })).status, 400);
    assert.equal((await notes(a)).notePaper, 'white');
  });
});
