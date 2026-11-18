require('../helpers/env');
const { describe, it, beforeEach, afterEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const { resetDb, prisma } = require('../helpers/app');
const ntfy = require('../../src/services/ntfyService');
const { tick } = require('../../src/services/cronService');
const { buildReminderAt } = require('../../src/routes/reminders');

const MIN = 60000;
const KEY = 'scheduler_last_minute';
const NY = 'America/New_York';

let sent, user;
const T0 = Date.parse('2026-06-15T12:00:00Z');   // a minute boundary
const at = (ms) => { mock.timers.reset(); mock.timers.enable({ apis: ['Date'], now: ms }); };
const watermark = async () => (await prisma.systemSetting.findUnique({ where: { key: KEY } }))?.value ?? null;
const setWatermark = (ms) => prisma.systemSetting.upsert({ where: { key: KEY }, update: { value: new Date(ms).toISOString() }, create: { key: KEY, value: new Date(ms).toISOString() } });
const remindAt = (title, ms, over = {}) => prisma.reminder.create({ data: { userId: user.id, title, reminderAt: new Date(ms), ...over } });
const titles = () => sent.map((s) => s.title);

beforeEach(async () => {
  await resetDb();
  user = await prisma.user.create({
    data: { username: 'sam', displayName: 'Sam', timezone: NY, preferences: { ntfyEnabled: true, ntfyTopic: 'sam-topic' } },
  });
  sent = [];
  mock.method(ntfy, 'send', async (topic, push) => { sent.push({ topic, ...push }); });
});
afterEach(() => { mock.timers.reset(); mock.restoreAll(); });

describe('the scheduler', () => {
  it('on its very first run only looks at the current minute', async () => {
    await remindAt('long ago', T0 - 3 * MIN);
    await remindAt('now', T0 + 6 * MIN + 10 * 1000);
    at(T0 + 6 * MIN + 20 * 1000);
    await tick();
    assert.deepEqual(titles(), ['now']);
    assert.equal(await watermark(), new Date(T0 + 6 * MIN).toISOString());
  });

  it('after a restart it catches up the minutes it missed, each reminder once', async () => {
    await setWatermark(T0);
    await remindAt('missed at +3', T0 + 3 * MIN);
    await remindAt('missed at +5', T0 + 5 * MIN);
    await remindAt('now', T0 + 6 * MIN);
    await remindAt('next minute', T0 + 7 * MIN);
    at(T0 + 6 * MIN + 5000);
    await tick();
    assert.deepEqual(titles().sort(), ['missed at +3', 'missed at +5', 'now']);
    assert.equal(await watermark(), new Date(T0 + 6 * MIN).toISOString());
  });

  it('catches up in order', async () => {
    await setWatermark(T0);
    await remindAt('second', T0 + 4 * MIN);
    await remindAt('first', T0 + 2 * MIN);
    await remindAt('third', T0 + 5 * MIN);
    at(T0 + 5 * MIN);
    await tick();
    assert.deepEqual(titles(), ['first', 'second', 'third']);
  });

  it('does not send anything twice, however often it runs in the same minute', async () => {
    await setWatermark(T0);
    await remindAt('once', T0 + 2 * MIN);
    at(T0 + 3 * MIN);
    await tick(); await tick(); await tick();
    assert.deepEqual(titles(), ['once']);
    at(T0 + 4 * MIN);
    await tick();
    assert.deepEqual(titles(), ['once']);
  });

  it('two runs at the same moment do not both send', async () => {
    await setWatermark(T0);
    await remindAt('once', T0 + 1 * MIN);
    at(T0 + 2 * MIN);
    await Promise.all([tick(), tick()]);
    assert.deepEqual(titles(), ['once']);
  });

  it('after a long outage it skips what is older than 15 minutes and sends the rest', async () => {
    await setWatermark(T0);
    await remindAt('too old', T0 + 3 * MIN);
    await remindAt('still fresh', T0 + 10 * MIN);
    await remindAt('now', T0 + 20 * MIN);
    at(T0 + 20 * MIN);
    await tick();
    assert.deepEqual(titles(), ['still fresh', 'now']);
    assert.equal(await watermark(), new Date(T0 + 20 * MIN).toISOString());
  });

  it('a reminder that is done is not sent', async () => {
    await setWatermark(T0);
    await remindAt('done', T0 + 2 * MIN, { completed: true });
    await remindAt('open', T0 + 2 * MIN);
    at(T0 + 3 * MIN);
    await tick();
    assert.deepEqual(titles(), ['open']);
  });

  it('only sends to people who turned a channel on', async () => {
    await prisma.user.update({ where: { id: user.id }, data: { preferences: {} } });
    await setWatermark(T0);
    await remindAt('quiet', T0 + 2 * MIN);
    at(T0 + 3 * MIN);
    await tick();
    assert.deepEqual(titles(), []);
    assert.equal(await watermark(), new Date(T0 + 3 * MIN).toISOString(), 'it still moves on');
  });

  it('a failed send does not stop the later minutes, or leave the scheduler stuck', async () => {
    mock.restoreAll();
    let calls = 0;
    mock.method(ntfy, 'send', async (topic, push) => { calls++; if (calls === 1) throw new Error('ntfy is down'); sent.push({ topic, ...push }); });
    await setWatermark(T0);
    await remindAt('fails', T0 + 1 * MIN);
    await remindAt('works', T0 + 2 * MIN);
    at(T0 + 3 * MIN);
    await tick();
    assert.deepEqual(titles(), ['works']);
    assert.equal(await watermark(), new Date(T0 + 3 * MIN).toISOString());
    at(T0 + 4 * MIN);
    await remindAt('later', T0 + 4 * MIN);
    await tick();
    assert.ok(titles().includes('later'), 'the next run still works');
  });

  it('a reminder is sent in the minute it is due, not in the minute before or after', async () => {
    await setWatermark(T0 + 4 * MIN);
    await remindAt('due', T0 + 5 * MIN);
    at(T0 + 5 * MIN - 1000);   // just before the minute: nothing new is due
    await tick();
    assert.deepEqual(titles(), []);
    at(T0 + 5 * MIN + 59 * 1000);
    await tick();
    assert.deepEqual(titles(), ['due']);
    at(T0 + 6 * MIN);
    await tick();
    assert.deepEqual(titles(), ['due']);
  });
});

describe('reminders fire at the right clock time around daylight saving', () => {
  const dueOn = async (date, time, tz = NY) => remindAt(`${date} ${time}`, buildReminderAt(date, time, 0, tz).getTime(), { dueDate: new Date(`${date}T00:00:00Z`), dueTime: time });
  const runMinute = async (iso) => { await setWatermark(Date.parse(iso) - MIN); at(Date.parse(iso)); await tick(); };

  it('9:00 on the day the clocks go forward fires at 13:00 UTC, and not an hour later', async () => {
    await dueOn('2026-03-08', '09:00');
    await runMinute('2026-03-08T14:00:00Z');   // 10:00 on the new clock
    assert.deepEqual(titles(), []);
    await runMinute('2026-03-08T13:00:00Z');
    assert.deepEqual(titles(), ['2026-03-08 09:00']);
  });

  it('9:00 on the day the clocks go back fires at 14:00 UTC', async () => {
    await dueOn('2026-11-01', '09:00');
    await runMinute('2026-11-01T13:00:00Z');
    assert.deepEqual(titles(), []);
    await runMinute('2026-11-01T14:00:00Z');
    assert.deepEqual(titles(), ['2026-11-01 09:00']);
  });

  it('1:00 in the morning fires that morning, not the day before', async () => {
    await dueOn('2026-06-15', '01:00');
    await runMinute('2026-06-14T05:00:00Z');
    assert.deepEqual(titles(), []);
    await runMinute('2026-06-15T05:00:00Z');
    assert.deepEqual(titles(), ['2026-06-15 01:00']);
  });
});

describe('routine reminders', () => {
  const routine = (over = {}) => prisma.routine.create({
    data: { userId: user.id, title: 'Stretch', frequency: 'daily', notify: true, specificTime: '09:00', ...over },
  });
  const runAt = async (iso) => { await setWatermark(Date.parse(iso) - MIN); at(Date.parse(iso)); sent.length = 0; await tick(); };

  it('arrive at the person\'s local time, on both sides of a daylight-saving change', async () => {
    await routine();
    await runAt('2026-03-07T14:00:00Z');   // 09:00 EST
    assert.deepEqual(titles(), ['Routine: Stretch']);
    await runAt('2026-03-08T13:00:00Z');   // 09:00 EDT, the day the clocks went forward
    assert.deepEqual(titles(), ['Routine: Stretch']);
    await runAt('2026-03-08T14:00:00Z');   // 10:00 EDT
    assert.deepEqual(titles(), []);
    await runAt('2026-11-01T14:00:00Z');   // 09:00 EST, the day the clocks went back
    assert.deepEqual(titles(), ['Routine: Stretch']);
  });

  it('only on the days the routine runs, by the person\'s local day', async () => {
    await routine({ frequency: 'weekdays' });
    await runAt('2026-11-14T14:00:00Z');   // Saturday 09:00 in New York
    assert.deepEqual(titles(), []);
    await runAt('2026-11-13T14:00:00Z');   // Friday
    assert.deepEqual(titles(), ['Routine: Stretch']);
  });

  it('not when it is already done today, and not when notifications are off', async () => {
    const done = await routine();
    await prisma.routineCompletion.create({ data: { routineId: done.id, userId: user.id, completedDate: new Date('2026-06-15T00:00:00Z') } });
    await routine({ title: 'Silent', notify: false });
    await runAt('2026-06-15T13:00:00Z');
    assert.deepEqual(titles(), []);
  });

  it('not before its start date', async () => {
    await routine({ startDate: new Date('2026-06-20T00:00:00Z') });
    await runAt('2026-06-15T13:00:00Z');
    assert.deepEqual(titles(), [], 'a routine that has not started yet sent a reminder');
  });
});
