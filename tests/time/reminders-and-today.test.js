require('../helpers/env');
const { describe, it, afterEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const { nextOccurrence, buildReminderAt, todayLocalStr, nowLocalHHMM, recurRuleLabel } = require('../../src/routes/reminders');
const { dayBounds } = require('../../src/routes/tasks');
const { localDateStr, todayDate, isDueToday } = require('../../src/routes/routines');
const { eventDayStr } = require('../../src/lib/eventDate');
const { fmtHHMM, prefsHour12 } = require('../../src/lib/timeFormat');

const NY = 'America/New_York';
const d = (s) => new Date(`${s}T00:00:00.000Z`);
const at = (iso) => { mock.timers.reset(); mock.timers.enable({ apis: ['Date'], now: Date.parse(iso) }); };
afterEach(() => mock.timers.reset());

// a reminder as the app stores it: dueDate = UTC midnight of the local date, reminderAt = the real moment
const reminder = (date, time, tz, rule, offsetMinutes = 0) => ({
  dueDate: d(date), dueTime: time, recurRule: rule, recurring: true,
  reminderAt: buildReminderAt(date, time, offsetMinutes, tz),
});
const clock = (date, tz) => date.toLocaleTimeString('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false });
const localDay = (date, tz) => date.toLocaleDateString('en-CA', { timeZone: tz });

describe('recurring reminders keep the same time on the clock when daylight saving changes', () => {
  it('daily at 9:00 in New York, the day the clocks go forward (2026-03-08)', () => {
    const next = nextOccurrence(reminder('2026-03-07', '09:00', NY, 'daily'), NY);
    assert.equal(next.dueDate.toISOString().slice(0, 10), '2026-03-08');
    assert.equal(next.reminderAt.toISOString(), '2026-03-08T13:00:00.000Z', 'was 14:00Z, which is 10:00 on the new clock');
    assert.equal(clock(next.reminderAt, NY), '09:00');
  });

  it('daily at 9:00 in New York, the day the clocks go back (2026-11-01)', () => {
    const next = nextOccurrence(reminder('2026-10-31', '09:00', NY, 'daily'), NY);
    assert.equal(next.reminderAt.toISOString(), '2026-11-01T14:00:00.000Z');
    assert.equal(clock(next.reminderAt, NY), '09:00');
  });

  it('weekly across the change, and in the southern hemisphere', () => {
    const w = nextOccurrence(reminder('2026-03-01', '07:30', NY, 'weekly'), NY);
    assert.equal(w.dueDate.toISOString().slice(0, 10), '2026-03-08');
    assert.equal(clock(w.reminderAt, NY), '07:30');
    const s = nextOccurrence(reminder('2026-09-27', '08:00', 'Australia/Sydney', 'weekly'), 'Australia/Sydney');
    assert.equal(s.dueDate.toISOString().slice(0, 10), '2026-10-04');
    assert.equal(clock(s.reminderAt, 'Australia/Sydney'), '08:00');
  });

  it('keeps a "15 minutes before" heads-up 15 minutes before', () => {
    const next = nextOccurrence(reminder('2026-03-07', '09:00', NY, 'daily', 15), NY);
    assert.equal(clock(next.reminderAt, NY), '08:45');
    assert.equal(next.dueTime, '09:00');
  });

  it('keeps a heads-up that crosses midnight on the right day', () => {
    // due 00:10, told 30 minutes before: 23:40 the evening before
    const next = nextOccurrence(reminder('2026-06-15', '00:10', NY, 'daily', 30), NY);
    assert.equal(localDay(next.reminderAt, NY), '2026-06-15');
    assert.equal(clock(next.reminderAt, NY), '23:40');
  });

  it('early-morning and late-evening reminders land on the right day', () => {
    const early = nextOccurrence(reminder('2026-06-15', '01:00', NY, 'daily'), NY);
    assert.equal(localDay(early.reminderAt, NY), '2026-06-16');
    const late = nextOccurrence(reminder('2026-06-15', '23:00', 'Asia/Tokyo', 'daily'), 'Asia/Tokyo');
    assert.equal(localDay(late.reminderAt, 'Asia/Tokyo'), '2026-06-16');
  });

  it('hourly moves the heads-up on by exactly an hour', () => {
    const r = reminder('2026-06-15', '09:00', NY, 'hourly');
    const next = nextOccurrence(r, NY);
    assert.equal(next.dueTime, '10:00');
    assert.equal(next.reminderAt.getTime() - r.reminderAt.getTime(), 3600000);
  });

  it('monthly from the 31st stops at the end of February, with the clock time kept', () => {
    const next = nextOccurrence(reminder('2026-01-31', '09:00', NY, 'monthly'), NY);
    assert.equal(next.dueDate.toISOString().slice(0, 10), '2026-02-28');
    assert.equal(clock(next.reminderAt, NY), '09:00');
  });

  it('without a time zone it falls back to the old fixed distance, and does not crash', () => {
    const r = { dueDate: d('2026-03-07'), dueTime: '09:00', recurRule: 'daily', reminderAt: new Date('2026-03-07T14:00:00Z') };
    assert.equal(nextOccurrence(r).reminderAt.toISOString(), '2026-03-08T14:00:00.000Z');
  });

  it('a reminder with no time of its own gets its next heads-up at the due time in the zone', () => {
    const next = nextOccurrence({ dueDate: d('2026-06-15'), dueTime: '09:00', recurRule: 'daily', reminderAt: null }, NY);
    assert.equal(clock(next.reminderAt, NY), '09:00');
  });

  it('a rule that does not recur gives nothing', () => {
    assert.equal(nextOccurrence({ dueDate: d('2026-06-15'), dueTime: '09:00', recurRule: '', reminderAt: null }, NY), null);
  });
});

describe('"today" depends on whose clock it is', () => {
  it('at 03:30 UTC on Nov 14 it is still Nov 13 in New York and Nov 14 in Tokyo', () => {
    at('2026-11-14T03:30:00Z');
    assert.equal(todayLocalStr(NY), '2026-11-13');
    assert.equal(todayLocalStr('Asia/Tokyo'), '2026-11-14');
    assert.equal(todayLocalStr('UTC'), '2026-11-14');
    assert.equal(todayLocalStr(undefined), '2026-11-14');
    assert.equal(localDateStr({ user: { timezone: NY } }), '2026-11-13');
    assert.equal(localDateStr({ user: {} }), '2026-11-14');
    assert.equal(todayDate({ user: { timezone: NY } }).toISOString(), '2026-11-13T00:00:00.000Z');
  });

  it('the clock reads midnight as 00:00, never 24:00', () => {
    at('2026-11-14T05:00:00Z');   // midnight in New York
    assert.equal(nowLocalHHMM(NY), '00:00');
    at('2026-11-14T15:05:00Z');
    assert.equal(nowLocalHHMM(NY), '10:05');
    assert.equal(nowLocalHHMM('Asia/Kolkata'), '20:35');
  });

  it('on the day the clocks go forward, the local day still has the right date at both ends', () => {
    at('2026-03-08T04:59:00Z');   // 23:59 on Mar 7 in New York
    assert.equal(todayLocalStr(NY), '2026-03-07');
    at('2026-03-08T05:00:00Z');   // 00:00 on Mar 8 in New York
    assert.equal(todayLocalStr(NY), '2026-03-08');
    at('2026-03-09T03:59:00Z');   // 23:59 on Mar 8, a 23-hour day
    assert.equal(todayLocalStr(NY), '2026-03-08');
    at('2026-03-09T04:00:00Z');
    assert.equal(todayLocalStr(NY), '2026-03-09');
  });

  it('tasks: the day bounds are whole days for the person, and a day is 24 hours of dates even on a daylight-saving day', () => {
    at('2026-03-08T12:00:00Z');
    const { start, end, weekEnd } = dayBounds(NY);
    assert.equal(start.toISOString(), '2026-03-08T00:00:00.000Z');
    assert.equal(end.toISOString(), '2026-03-09T00:00:00.000Z');
    assert.equal(weekEnd.toISOString(), '2026-03-15T00:00:00.000Z');
    at('2026-11-14T03:30:00Z');
    assert.equal(dayBounds(NY).start.toISOString(), '2026-11-13T00:00:00.000Z');
    assert.equal(dayBounds('Asia/Tokyo').start.toISOString(), '2026-11-14T00:00:00.000Z');
  });

  it('routines are due on the person\'s local day', () => {
    const daily = { active: true, frequency: 'weekdays', startDate: null, scheduleDays: [] };
    at('2026-11-14T03:30:00Z');   // Saturday in Tokyo, still Friday evening in New York
    assert.equal(isDueToday(daily, localDateStr({ user: { timezone: NY } })), true);
    assert.equal(isDueToday(daily, localDateStr({ user: { timezone: 'Asia/Tokyo' } })), false);
  });
});

describe('which day does a calendar event belong to', () => {
  it('an all-day event is on its own date for everyone, whatever their zone', () => {
    const birthday = '2026-06-15T00:00:00.000Z';
    for (const tz of [NY, 'Asia/Tokyo', 'Pacific/Kiritimati', 'Pacific/Honolulu', 'UTC', undefined]) {
      assert.equal(eventDayStr(birthday, true, tz), '2026-06-15', String(tz));
    }
  });

  it('a timed event is on the day the person lives it', () => {
    const lateEvening = '2026-06-16T02:30:00.000Z';   // 22:30 on the 15th in New York
    assert.equal(eventDayStr(lateEvening, false, NY), '2026-06-15');
    assert.equal(eventDayStr(lateEvening, false, 'Asia/Tokyo'), '2026-06-16');
    assert.equal(eventDayStr(lateEvening, false, undefined), '2026-06-16');
  });

  it('a timed event at local midnight belongs to the new day', () => {
    assert.equal(eventDayStr('2026-06-15T04:00:00.000Z', false, NY), '2026-06-15');
    assert.equal(eventDayStr('2026-06-15T03:59:00.000Z', false, NY), '2026-06-14');
  });
});

describe('times of day', () => {
  it('12-hour clock', () => {
    assert.equal(fmtHHMM('00:00'), '12:00 AM');
    assert.equal(fmtHHMM('00:05'), '12:05 AM');
    assert.equal(fmtHHMM('09:30'), '9:30 AM');
    assert.equal(fmtHHMM('12:00'), '12:00 PM');
    assert.equal(fmtHHMM('12:59'), '12:59 PM');
    assert.equal(fmtHHMM('13:05'), '1:05 PM');
    assert.equal(fmtHHMM('23:59'), '11:59 PM');
  });

  it('24-hour clock keeps the text, and no time is nothing', () => {
    assert.equal(fmtHHMM('09:30', false), '09:30');
    assert.equal(fmtHHMM('', true), '');
    assert.equal(fmtHHMM(null, false), '');
  });

  it('12-hour is the default unless the person chose 24', () => {
    assert.equal(prefsHour12(undefined), true);
    assert.equal(prefsHour12({}), true);
    assert.equal(prefsHour12({ timeFormat: '12h' }), true);
    assert.equal(prefsHour12({ timeFormat: '24h' }), false);
  });

  it('names the recurrence rules', () => {
    assert.equal(recurRuleLabel('daily'), 'Daily');
    assert.equal(recurRuleLabel('every3months'), 'Every 3 Months');
    assert.equal(recurRuleLabel(''), '');
    assert.equal(recurRuleLabel('custom:daily:3'), 'Every 3 days');
    assert.equal(recurRuleLabel('custom:weekly:1'), 'Every 1 week');
    assert.match(recurRuleLabel('custom:monthly:1:each:15'), /Every 1 month.*day 15/);
  });
});
