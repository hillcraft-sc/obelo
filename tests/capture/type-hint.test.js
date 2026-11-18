require('../helpers/env');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { typeHint, hintInstruction, applyTypeHint } = require('../../src/services/captureService');

describe('Capture: a type chosen before processing', () => {
  it('accepts each real type, in any case or with spaces', () => {
    for (const t of ['task', 'reminder', 'note', 'journal', 'quote', 'list', 'bookmark']) assert.equal(typeHint(t), t);
    assert.equal(typeHint('  Task '), 'task');
    assert.equal(typeHint('REMINDER'), 'reminder');
  });

  it('treats auto, empty, missing and unknown values as no choice', () => {
    for (const v of ['auto', 'Auto', '', '  ', undefined, null, 'todo', 'tasks', 42, {}, ['task']]) assert.equal(typeHint(v), null, String(v));
  });

  it('tells the model the type, and that a task may have a time', () => {
    const line = hintInstruction('task');
    assert.match(line, /"task"/);
    assert.match(line, /due time/);
    assert.equal(hintInstruction(null), '');
  });

  it('returns the chosen type whatever the model answered, and keeps its other fields', () => {
    const answered = { type: 'reminder', title: 'Take out the trash', dueDate: '2026-11-16', dueTime: '10:00', tags: ['home'], confidence: 'high' };
    const result = applyTypeHint(answered, 'task');
    assert.equal(result.type, 'task');
    assert.equal(result.dueTime, '10:00');
    assert.equal(result.title, 'Take out the trash');
    assert.equal(answered.type, 'reminder', 'the original is not changed');
  });

  it('leaves the suggestion alone when no type was chosen', () => {
    const answered = { type: 'reminder', title: 'x' };
    assert.equal(applyTypeHint(answered, null), answered);
  });
});
