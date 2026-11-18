require('../helpers/env');
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startApp, resetDb } = require('../helpers/app');
const { createUser, PASSWORD } = require('../helpers/users');
const ai = require('../../src/lib/aiProvider');
const aiChat = require('../../src/services/aiChatService');

// The chat only reads. A model that isn't told so will answer "go ahead and set it up" with "Done!" and a
// list of things it never created (seen in real use), so the instructions must say what it cannot do.
describe('AI chat: told that it is read-only', () => {
  let alice;
  const real = { complete: ai.complete, isConfigured: ai.isConfigured };
  let sent;

  before(async () => {
    await startApp();
    await resetDb();
    alice = await createUser({ username: 'alice', password: PASSWORD });
    ai.isConfigured = () => true;
    ai.complete = async (args) => { sent = args; return 'ok'; };
  });
  after(() => { ai.complete = real.complete; ai.isConfigured = real.isConfigured; });

  it('puts the rule in the instructions sent to the model, ahead of the data', async () => {
    await aiChat.chat([{ role: 'user', content: 'Go ahead and set those routines up for me' }], alice.id, { displayName: 'Alice', timezone: 'UTC' });
    assert.equal(sent.feature, 'chat');
    assert.ok(sent.system.includes(aiChat.READ_ONLY_RULE));
    assert.ok(sent.system.includes("cannot create, change, complete, move or delete anything"));
    assert.ok(sent.system.indexOf(aiChat.READ_ONLY_RULE) < sent.system.indexOf('Today:'), 'before the date and the data');
  });

  it('tells the model to hand over the details instead of claiming it did the work', () => {
    const p = aiChat.buildSystemPrompt('Alice', 'Sunday', 'CONTEXT');
    assert.match(p, /do not say or imply that you did/);
    assert.match(p, /exact details \(title, day, time, how often\) so they can add it themselves/);
    assert.ok(p.endsWith('CONTEXT'));
  });
});
