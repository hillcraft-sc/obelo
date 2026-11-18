require('../helpers/env');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const t = require('../../src/lib/userTemplates');

const make = (extra = {}) => ({ label: 'Standup', type: 'note', title: 'Standup — ', content: '## Done\n- \n', ...extra });

describe('Note templates: the starters', () => {
  it('are the four starters, without Book Review', () => {
    const labels = t.starterList().map((x) => x.label);
    assert.deepEqual(labels, ['Meeting Notes', 'Weekly Review', 'Project Plan', 'Journal Entry']);
    assert.ok(!labels.includes('Book Review'));
  });

  it('are what a person sees until they change something, and an emptied list stays empty', () => {
    assert.equal(t.listFrom(undefined).length, 4);
    assert.equal(t.listFrom({}).length, 4);
    assert.equal(t.listFrom({ timeFormat: '24h' }).length, 4);
    assert.deepEqual(t.listFrom({ noteTemplates: [] }), []);
  });
});

describe('Note templates: cleaning what was typed', () => {
  it('needs a name, trims it and limits its length', () => {
    assert.match(t.clean({ label: '   ' }).error, /name/);
    assert.match(t.clean({}).error, /name/);
    assert.equal(t.clean({ label: '  Standup ' }).value.label, 'Standup');
    assert.match(t.clean({ label: 'x'.repeat(61) }).error, /at most 60/);
  });

  it('accepts note, journal and quote and defaults to note', () => {
    for (const type of ['note', 'journal', 'quote']) assert.equal(t.clean(make({ type })).value.type, type);
    assert.equal(t.clean({ label: 'A' }).value.type, 'note');
    assert.match(t.clean(make({ type: 'task' })).error, /note, journal or quote/);
  });

  it('limits the starting title and the starting text and wants text', () => {
    assert.match(t.clean(make({ title: 'x'.repeat(121) })).error, /at most 120/);
    assert.match(t.clean(make({ content: 'x'.repeat(20001) })).error, /at most 20000/);
    assert.match(t.clean(make({ content: 5 })).error, /text/);
    assert.equal(t.clean({ label: 'A' }).value.content, '');
  });

  it('reads the date-title switch from a form checkbox or from JSON', () => {
    assert.equal(t.clean(make({ dateTitle: 'on' })).value.dateTitle, true);
    assert.equal(t.clean(make({ dateTitle: true })).value.dateTitle, true);
    assert.equal(t.clean(make({ dateTitle: false })).value.dateTitle, false);
    assert.equal(t.clean(make()).value.dateTitle, false);
  });

  it('leaves out what an edit did not send', () => {
    assert.deepEqual(t.clean({ label: 'New name' }, { partial: true }).value, { label: 'New name' });
    assert.match(t.clean({ label: '' }, { partial: true }).error, /name/);
  });
});

describe('Note templates: changing a list', () => {
  it('the first change copies the starters, then adds the new template', () => {
    const r = t.withCreated({ timeFormat: '12h' }, make(), () => 't_fixed');
    assert.equal(r.template.id, 't_fixed');
    assert.equal(r.prefs.noteTemplates.length, 5);
    assert.equal(r.prefs.timeFormat, '12h');
    assert.equal(r.prefs.noteTemplates.at(-1).label, 'Standup');
  });

  it('does not change the preferences it was given', () => {
    const prefs = { a: 1 };
    t.withCreated(prefs, make());
    assert.deepEqual(prefs, { a: 1 });
  });

  it('stops at twenty templates', () => {
    let prefs = { noteTemplates: Array.from({ length: 20 }, (_, i) => ({ id: 't' + i, label: 'T' + i, type: 'note', title: '', dateTitle: false, content: '' })) };
    assert.match(t.withCreated(prefs, make()).error, /at most 20/);
    prefs = { noteTemplates: prefs.noteTemplates.slice(0, 19) };
    assert.ok(t.withCreated(prefs, make()).prefs);
  });

  it('gives every new template its own id', () => {
    const a = t.withCreated({}, make());
    const b = t.withCreated(a.prefs, make());
    assert.notEqual(a.template.id, b.template.id);
    assert.match(a.template.id, /^t_[0-9a-f]{12}$/);
  });

  it('edits one template and keeps the rest', () => {
    const r = t.withUpdated({}, 'meeting', { label: 'Team meeting' });
    assert.equal(r.template.label, 'Team meeting');
    assert.equal(r.template.content, t.starterList()[0].content);
    assert.equal(r.prefs.noteTemplates.length, 4);
    assert.equal(r.prefs.noteTemplates[1].label, 'Weekly Review');
  });

  it('says when a template is not there, and refuses a bad edit', () => {
    assert.equal(t.withUpdated({}, 'nope', { label: 'x' }).notFound, true);
    assert.equal(t.withRemoved({}, 'nope').notFound, true);
    assert.match(t.withUpdated({}, 'meeting', { label: '' }).error, /name/);
  });

  it('removes a starter for good, and removing all of them leaves none', () => {
    let r = t.withRemoved({}, 'meeting');
    assert.deepEqual(t.listFrom(r.prefs).map((x) => x.id), ['weekly', 'project', 'journal']);
    for (const id of ['weekly', 'project', 'journal']) r = t.withRemoved(r.prefs, id);
    assert.deepEqual(t.listFrom(r.prefs), []);
  });
});

describe('Note templates: as the pages and apps get them', () => {
  it('resolves the date title for the persons time zone and keeps what they typed', () => {
    const list = t.forUser({ timezone: 'UTC', preferences: {} });
    const journal = list.find((x) => x.id === 'journal');
    assert.match(journal.startTitle, /^[A-Z][a-z]+ \d{1,2}, \d{4} — $/);
    assert.equal(journal.title, '');
    assert.equal(journal.dateTitle, true);
    assert.equal(list.find((x) => x.id === 'meeting').startTitle, 'Meeting — ');
  });

  it('finds a template by id for that person only', () => {
    const user = { timezone: 'UTC', preferences: { noteTemplates: [{ id: 't_a', label: 'Mine', type: 'note', title: 'Mine', dateTitle: false, content: 'x' }] } };
    assert.equal(t.findFor(user, 't_a').label, 'Mine');
    assert.equal(t.findFor(user, 'meeting'), null);
  });
});
