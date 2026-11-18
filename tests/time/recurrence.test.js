require('../helpers/env');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { addMonths, addYears, daysInMonth, nthWeekdayOfMonth, nextRecurrence } = require('../../src/lib/recurrence');
const { nextDueDate } = require('../../src/routes/tasks');
const { nextOccurrence } = require('../../src/routes/reminders');

const d = (s) => new Date(`${s}T00:00:00.000Z`);
const day = (date) => date.toISOString().slice(0, 10);
const next = (from, rule, time = '09:00') => nextRecurrence(d(from), rule, time);
const nextDay = (from, rule) => day(next(from, rule).dueDate);

describe('adding months and years', () => {
  it('keeps the day of the month when the month is long enough', () => {
    assert.equal(day(addMonths(d('2026-01-15'), 1)), '2026-02-15');
    assert.equal(day(addMonths(d('2026-01-31'), 2)), '2026-03-31');
  });

  it('stops at the last day of a shorter month and does not run over into the next one', () => {
    assert.equal(day(addMonths(d('2026-01-31'), 1)), '2026-02-28');
    assert.equal(day(addMonths(d('2028-01-31'), 1)), '2028-02-29', 'leap year');
    assert.equal(day(addMonths(d('2026-03-31'), 1)), '2026-04-30');
    assert.equal(day(addMonths(d('2026-08-31'), 6)), '2027-02-28');
    assert.equal(day(addMonths(d('2026-12-31'), 2)), '2027-02-28');
  });

  it('crosses year ends, in both directions', () => {
    assert.equal(day(addMonths(d('2026-11-15'), 3)), '2027-02-15');
    assert.equal(day(addMonths(d('2026-12-15'), 1)), '2027-01-15');
    assert.equal(day(addMonths(d('2026-01-15'), -1)), '2025-12-15');
    assert.equal(day(addMonths(d('2026-03-31'), -1)), '2026-02-28');
    assert.equal(day(addMonths(d('2026-01-15'), 24)), '2028-01-15');
  });

  it('does not change the date it is given', () => {
    const original = d('2026-01-31');
    addMonths(original, 1);
    assert.equal(day(original), '2026-01-31');
  });

  it('adds years, with Feb 29 landing on Feb 28 in a year with no leap day', () => {
    assert.equal(day(addYears(d('2028-02-29'), 1)), '2029-02-28');
    assert.equal(day(addYears(d('2028-02-29'), 4)), '2032-02-29');
    assert.equal(day(addYears(d('2026-06-15'), 2)), '2028-06-15');
  });

  it('knows how long every month is', () => {
    assert.deepEqual([0, 1, 2, 3, 11].map((m) => daysInMonth(2026, m)), [31, 28, 31, 30, 31]);
    assert.equal(daysInMonth(2028, 1), 29);
    assert.equal(daysInMonth(1900, 1), 28, 'not a leap year');
    assert.equal(daysInMonth(2000, 1), 29, 'a leap year');
  });
});

describe('simple rules', () => {
  it('daily and weekly move by whole days', () => {
    assert.equal(nextDay('2026-12-31', 'daily'), '2027-01-01');
    assert.equal(nextDay('2026-02-28', 'daily'), '2026-03-01');
    assert.equal(nextDay('2028-02-28', 'daily'), '2028-02-29');
    assert.equal(nextDay('2026-06-15', 'weekly'), '2026-06-22');
    assert.equal(nextDay('2026-12-28', 'weekly'), '2027-01-04');
    assert.equal(nextDay('2026-06-15', 'biweekly'), '2026-06-29');
  });

  it('weekdays skip the weekend', () => {
    assert.equal(nextDay('2026-11-12', 'weekdays'), '2026-11-13');   // Thursday -> Friday
    assert.equal(nextDay('2026-11-13', 'weekdays'), '2026-11-16');   // Friday -> Monday
    assert.equal(nextDay('2026-11-14', 'weekdays'), '2026-11-16');   // Saturday -> Monday
    assert.equal(nextDay('2026-11-15', 'weekdays'), '2026-11-16');   // Sunday -> Monday
  });

  it('weekends go Friday to Saturday, Saturday to Sunday, Sunday to Saturday', () => {
    assert.equal(nextDay('2026-11-13', 'weekends'), '2026-11-14');
    assert.equal(nextDay('2026-11-14', 'weekends'), '2026-11-15');
    assert.equal(nextDay('2026-11-15', 'weekends'), '2026-11-21');
    assert.equal(nextDay('2026-11-11', 'weekends'), '2026-11-14');   // midweek -> Saturday
  });

  it('monthly, every 3 and every 6 months stay on the day, and stop at the end of a short month', () => {
    assert.equal(nextDay('2026-01-15', 'monthly'), '2026-02-15');
    assert.equal(nextDay('2026-01-31', 'monthly'), '2026-02-28', 'was March 3');
    assert.equal(nextDay('2026-03-31', 'monthly'), '2026-04-30');
    assert.equal(nextDay('2026-11-30', 'every3months'), '2027-02-28');
    assert.equal(nextDay('2026-08-31', 'every6months'), '2027-02-28');
    assert.equal(nextDay('2026-12-31', 'monthly'), '2027-01-31');
  });

  it('yearly: Feb 29 goes to Feb 28 in a year with no leap day', () => {
    assert.equal(nextDay('2028-02-29', 'yearly'), '2029-02-28', 'was March 1');
    assert.equal(nextDay('2026-06-15', 'yearly'), '2027-06-15');
  });

  it('a short month does not drag later months down: the repeat goes back to the 31st', () => {
    // Jan 31, repeating monthly: Feb 28, then Mar 31, Apr 30, May 31, Jun 30 ... and in a leap year Feb 29
    const chain = (start, rule, steps) => {
      let date = d(start), current = rule; const out = [];
      for (let i = 0; i < steps; i++) { const r = nextRecurrence(date, current, '09:00'); out.push(day(r.dueDate)); date = r.dueDate; current = r.rule || current; }
      return { out, current };
    };
    const a = chain('2026-01-31', 'monthly', 6);
    assert.deepEqual(a.out, ['2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31', '2026-06-30', '2026-07-31']);
    assert.equal(a.current, 'custom:monthly:1:each:31');
    assert.equal(chain('2028-01-31', 'monthly', 2).out[0], '2028-02-29');
    assert.deepEqual(chain('2026-01-30', 'monthly', 3).out, ['2026-02-28', '2026-03-30', '2026-04-30']);
    assert.deepEqual(chain('2026-08-31', 'every6months', 3).out, ['2027-02-28', '2027-08-31', '2028-02-29']);
    assert.deepEqual(chain('2026-11-30', 'every3months', 3).out, ['2027-02-28', '2027-05-30', '2027-08-30']);
  });

  it('only changes the repeat when a short month actually cut the day', () => {
    assert.equal(next('2026-01-15', 'monthly').rule, undefined);
    assert.equal(next('2026-02-28', 'monthly').rule, undefined, 'a real 28th stays a plain monthly repeat');
    assert.equal(next('2026-01-31', 'monthly').rule, 'custom:monthly:1:each:31');
    assert.equal(next('2026-01-31', 'every3months').rule, 'custom:monthly:3:each:31');
    assert.equal(next('2026-01-31', 'daily').rule, undefined);
    assert.equal(next('2026-01-31', 'custom:monthly:1:each:31').rule, undefined);
  });

  it('no rule, an empty rule and an unknown rule mean "does not recur"', () => {
    for (const rule of [undefined, null, '', 'fortnightly', 'custom:decadely:1']) assert.equal(next('2026-06-15', rule), null, String(rule));
  });
});

describe('hourly', () => {
  it('moves the time on by an hour and keeps the date', () => {
    const r = next('2026-06-15', 'hourly', '09:30');
    assert.equal(day(r.dueDate), '2026-06-15');
    assert.equal(r.dueTime, '10:30');
    assert.equal(r.hourly, true);
  });

  it('rolls over midnight to the next date', () => {
    const r = next('2026-12-31', 'hourly', '23:15');
    assert.equal(day(r.dueDate), '2027-01-01');
    assert.equal(r.dueTime, '00:15');
  });

  it('starts from 09:00 when there is no time', () => {
    assert.equal(nextRecurrence(d('2026-06-15'), 'hourly', null).dueTime, '10:00');
  });

  it('is the only rule that is hourly', () => {
    assert.equal(next('2026-06-15', 'daily').hourly, false);
  });
});

describe('custom rules', () => {
  it('every N days and weeks', () => {
    assert.equal(nextDay('2026-06-15', 'custom:daily:3'), '2026-06-18');
    assert.equal(nextDay('2026-12-30', 'custom:daily:5'), '2027-01-04');
    assert.equal(nextDay('2026-06-15', 'custom:weekly:2'), '2026-06-29');
  });

  it('an interval that is missing, zero or not a number means every 1', () => {
    for (const rule of ['custom:daily', 'custom:daily:', 'custom:daily:0', 'custom:daily:x']) assert.equal(nextDay('2026-06-15', rule), '2026-06-16', rule);
  });

  it('every N months on a given day, stopping at the end of a short month', () => {
    assert.equal(nextDay('2026-01-15', 'custom:monthly:1:each:15'), '2026-02-15');
    assert.equal(nextDay('2026-01-31', 'custom:monthly:1:each:31'), '2026-02-28', 'was March 31');
    assert.equal(nextDay('2028-01-31', 'custom:monthly:1:each:31'), '2028-02-29');
    assert.equal(nextDay('2026-02-28', 'custom:monthly:1:each:31'), '2026-03-31');
    assert.equal(nextDay('2026-01-31', 'custom:monthly:2:each:30'), '2026-03-30');
    assert.equal(nextDay('2026-06-10', 'custom:monthly:1:each:0'), '2026-07-01', 'day 0 reads as day 1');
  });

  it('every N months on the Nth weekday', () => {
    assert.equal(nextDay('2026-01-13', 'custom:monthly:1:onthe:second:tuesday'), '2026-02-10');
    assert.equal(nextDay('2026-01-30', 'custom:monthly:1:onthe:last:friday'), '2026-02-27');
    assert.equal(nextDay('2026-02-27', 'custom:monthly:1:onthe:last:friday'), '2026-03-27');
    assert.equal(nextDay('2026-01-31', 'custom:monthly:1:onthe:first:monday'), '2026-02-02', 'was March, skipping February');
    assert.equal(nextDay('2026-11-05', 'custom:monthly:3:onthe:first:thursday'), '2027-02-04');
  });

  it('every N years', () => {
    assert.equal(nextDay('2026-06-15', 'custom:yearly:2'), '2028-06-15');
    assert.equal(nextDay('2028-02-29', 'custom:yearly:1'), '2029-02-28');
  });

  it('the Nth weekday of a month: first, second, third, fourth, last', () => {
    // November 2026 starts on a Sunday
    assert.equal(nthWeekdayOfMonth(2026, 10, 'first', 'sunday'), 1);
    assert.equal(nthWeekdayOfMonth(2026, 10, 'first', 'monday'), 2);
    assert.equal(nthWeekdayOfMonth(2026, 10, 'second', 'tuesday'), 10);
    assert.equal(nthWeekdayOfMonth(2026, 10, 'third', 'friday'), 20);
    assert.equal(nthWeekdayOfMonth(2026, 10, 'fourth', 'thursday'), 26);
    assert.equal(nthWeekdayOfMonth(2026, 10, 'last', 'monday'), 30);
    assert.equal(nthWeekdayOfMonth(2026, 10, 'last', 'sunday'), 29);
    assert.equal(nthWeekdayOfMonth(2028, 1, 'last', 'tuesday'), 29, 'leap February');
  });
});

describe('tasks and reminders agree', () => {
  const rules = ['hourly', 'daily', 'weekdays', 'weekends', 'weekly', 'biweekly', 'monthly', 'every3months', 'every6months', 'yearly',
    'custom:daily:3', 'custom:weekly:2', 'custom:monthly:1:each:31', 'custom:monthly:2:onthe:last:friday', 'custom:yearly:1', 'nonsense'];
  const starts = ['2026-01-31', '2026-02-28', '2028-02-29', '2026-03-08', '2026-11-01', '2026-12-31', '2026-06-15'];

  it('give the same next date and time for every rule and start date', () => {
    for (const rule of rules) for (const start of starts) {
      const task = nextDueDate({ dueDate: d(start), recurRule: rule, dueTime: '09:00' });
      const reminder = nextOccurrence({ dueDate: d(start), recurRule: rule, dueTime: '09:00', reminderAt: null }, 'UTC');
      if (task === null) { assert.equal(reminder, null, `${rule} ${start}`); continue; }
      assert.equal(day(reminder.dueDate), day(task.dueDate), `${rule} from ${start}`);
      assert.equal(reminder.dueTime, task.dueTime, `${rule} from ${start}`);
      assert.equal(reminder.rule, task.rule, `${rule} from ${start}`);
    }
  });
});

describe('a saved recurring task or reminder remembers the day', () => {
  const { resetDb, prisma } = require('../helpers/app');
  const { before } = require('node:test');
  const { createNextOccurrence } = require('../../src/routes/tasks');
  const { completeReminder } = require('../../src/routes/reminders');

  it('task: Jan 31 monthly becomes Feb 28 with a repeat that returns to the 31st', async () => {
    await resetDb();
    const user = await prisma.user.create({ data: { username: 'sam', displayName: 'Sam' } });
    const task = await prisma.task.create({ data: { userId: user.id, title: 'Rent', dueDate: d('2026-01-31'), recurring: true, recurRule: 'monthly' } });
    await createNextOccurrence(task);
    const second = await prisma.task.findFirst({ where: { userId: user.id, id: { not: task.id } } });
    assert.equal(day(second.dueDate), '2026-02-28');
    assert.equal(second.recurRule, 'custom:monthly:1:each:31');
    await createNextOccurrence(second);
    const third = await prisma.task.findFirst({ where: { userId: user.id, id: { notIn: [task.id, second.id] } } });
    assert.equal(day(third.dueDate), '2026-03-31');
  });

  it('reminder: the same', async () => {
    await resetDb();
    const user = await prisma.user.create({ data: { username: 'sam', displayName: 'Sam', timezone: 'America/New_York' } });
    const r = await prisma.reminder.create({ data: { userId: user.id, title: 'Bills', dueDate: d('2026-01-31'), dueTime: '09:00', recurring: true, recurRule: 'monthly' } });
    await completeReminder(r, 'America/New_York');
    const second = await prisma.reminder.findFirst({ where: { userId: user.id, completed: false } });
    assert.equal(day(second.dueDate), '2026-02-28');
    assert.equal(second.recurRule, 'custom:monthly:1:each:31');
    await completeReminder(second, 'America/New_York');
    const third = await prisma.reminder.findFirst({ where: { userId: user.id, completed: false } });
    assert.equal(day(third.dueDate), '2026-03-31');
  });
});
