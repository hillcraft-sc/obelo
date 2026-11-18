require('../helpers/env');
const { describe, it, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { resetDb, prisma } = require('../helpers/app');
const { createUser, PASSWORD } = require('../helpers/users');
const { isScheduledDay, hasScheduledDayBetweenExclusive, recalcStreak } = require('../../src/services/routineStreaks');
const { isDueToday, buildHeatmapData, buildWeeklyStats } = require('../../src/routes/routines');

const d = (s) => new Date(`${s}T00:00:00.000Z`);
// 2026-11-09 is a Monday
const WEEK = ['2026-11-08', '2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13', '2026-11-14'];   // Sun..Sat

describe('which days a routine runs', () => {
  const days = (routine) => WEEK.map((s) => (isScheduledDay(routine, d(s)) ? 1 : 0)).join('');

  it('daily: every day', () => assert.equal(days({ frequency: 'daily' }), '1111111'));
  it('weekdays: Monday to Friday', () => assert.equal(days({ frequency: 'weekdays' }), '0111110'));
  it('weekends: Saturday and Sunday', () => assert.equal(days({ frequency: 'weekends' }), '1000001'));
  it('weekly and custom: the chosen days', () => {
    assert.equal(days({ frequency: 'weekly', scheduleDays: ['Mon'] }), '0100000');
    assert.equal(days({ frequency: 'custom', scheduleDays: ['Tue', 'Thu', 'Sat'] }), '0010101');
    assert.equal(days({ frequency: 'custom', scheduleDays: [] }), '0000000');
    assert.equal(days({ frequency: 'weekly' }), '0000000', 'no days chosen yet');
  });
  it('anything unknown counts as every day', () => assert.equal(days({ frequency: 'whenever' }), '1111111'));
});

describe('a missed day between two dates', () => {
  const daily = { frequency: 'daily' };
  const weekdays = { frequency: 'weekdays' };
  it('is looked for strictly between, so neighbouring days are fine', () => {
    assert.equal(hasScheduledDayBetweenExclusive(daily, '2026-11-10', '2026-11-11'), false);
    assert.equal(hasScheduledDayBetweenExclusive(daily, '2026-11-10', '2026-11-10'), false);
    assert.equal(hasScheduledDayBetweenExclusive(daily, '2026-11-10', '2026-11-12'), true);
  });
  it('ignores days the routine does not run', () => {
    assert.equal(hasScheduledDayBetweenExclusive(weekdays, '2026-11-13', '2026-11-16'), false, 'Friday to Monday');
    assert.equal(hasScheduledDayBetweenExclusive(weekdays, '2026-11-12', '2026-11-16'), true, 'Friday missed');
  });
  it('is not confused by daylight saving, month ends, leap days or year ends', () => {
    assert.equal(hasScheduledDayBetweenExclusive(daily, '2026-03-07', '2026-03-09'), true);
    assert.equal(hasScheduledDayBetweenExclusive(daily, '2026-03-08', '2026-03-09'), false);
    assert.equal(hasScheduledDayBetweenExclusive(daily, '2026-11-01', '2026-11-02'), false);
    assert.equal(hasScheduledDayBetweenExclusive(daily, '2028-02-28', '2028-03-01'), true, 'Feb 29 in between');
    assert.equal(hasScheduledDayBetweenExclusive(daily, '2026-12-31', '2027-01-01'), false);
    assert.equal(hasScheduledDayBetweenExclusive(daily, '2026-12-30', '2027-01-01'), true);
  });
});

describe('is a routine due today', () => {
  const base = { active: true, frequency: 'weekdays', scheduleDays: [], startDate: null };
  it('depends on the day', () => {
    assert.equal(isDueToday(base, '2026-11-13'), true);
    assert.equal(isDueToday(base, '2026-11-14'), false);
  });
  it('never when archived', () => assert.equal(isDueToday({ ...base, active: false }, '2026-11-13'), false));
  it('not before its start date, and on it', () => {
    assert.equal(isDueToday({ ...base, startDate: d('2026-11-16') }, '2026-11-13'), false);
    assert.equal(isDueToday({ ...base, startDate: d('2026-11-13') }, '2026-11-13'), true);
    assert.equal(isDueToday({ ...base, startDate: d('2026-11-01') }, '2026-11-13'), true);
  });
});

describe('the 12-week grid and weekly rates', () => {
  const done = (...dates) => dates.map((s) => ({ completedDate: d(s) }));
  const routine = { frequency: 'weekdays', scheduleDays: [], startDate: null };

  it('is 12 weeks of 7 days, Sunday first, ending in the week of today', () => {
    const weeks = buildHeatmapData([], routine, '2026-11-12');   // a Thursday
    assert.equal(weeks.length, 12);
    assert.ok(weeks.every((w) => w.length === 7));
    assert.equal(weeks[11][0].dateStr, '2026-11-08', 'this week starts on Sunday');
    assert.equal(weeks[0][0].dateStr, '2026-08-23', 'eleven weeks earlier');
    assert.equal(weeks[11][4].dateStr, '2026-11-12');
  });

  it('marks the future, days the routine does not run, days before it started, and done days', () => {
    const r = { ...routine, startDate: d('2026-11-10') };
    const weeks = buildHeatmapData(done('2026-11-10', '2026-11-11', '2026-11-09'), r, '2026-11-12');
    const cell = (s) => weeks.flat().find((c) => c.dateStr === s);
    assert.equal(cell('2026-11-13').isFuture, true);
    assert.equal(cell('2026-11-14').isFuture, true);
    assert.equal(cell('2026-11-08').notApplicable, true, 'Sunday');
    assert.equal(cell('2026-11-09').notApplicable, true, 'before the start date');
    assert.equal(cell('2026-11-09').completed, false, 'a completion before the start does not show');
    assert.equal(cell('2026-11-10').completed, true);
    assert.equal(cell('2026-11-11').completed, true);
    assert.equal(cell('2026-11-12').completed, false, 'today, not done yet');
    assert.equal(cell('2026-11-12').notApplicable, false);
  });

  it('works across a year end and a leap day', () => {
    const jan = buildHeatmapData([], routine, '2027-01-02');
    assert.equal(jan[11][0].dateStr, '2026-12-27');
    assert.ok(jan.flat().some((c) => c.dateStr === '2026-12-31') && jan.flat().some((c) => c.dateStr === '2027-01-01'));
    const leap = buildHeatmapData([], routine, '2028-03-01').flat().map((c) => c.dateStr);
    assert.ok(leap.includes('2028-02-29'));
    assert.equal(new Set(leap).size, 84, 'no day twice, none missing');
  });

  it('weekly rates: the share of scheduled days done, up to today', () => {
    const stats = buildWeeklyStats(done('2026-11-09', '2026-11-10', '2026-11-11'), routine, '2026-11-12');
    assert.equal(stats.length, 12);
    const thisWeek = stats[11];
    assert.equal(thisWeek.dayCount, 4, 'Mon to Thu so far');
    assert.equal(thisWeek.completionCount, 3);
    assert.equal(thisWeek.rate, 75);
    assert.equal(stats[10].dayCount, 5);
    assert.equal(stats[10].rate, 0);
    assert.equal(stats[0].label, 'Aug 23');
  });

  it('weekly rates: no days scheduled yet means 0, not a division error', () => {
    const stats = buildWeeklyStats([], { frequency: 'weekdays', scheduleDays: [], startDate: d('2026-11-30') }, '2026-11-12');
    assert.ok(stats.every((s) => s.rate === 0 && s.dayCount === 0));
  });
});

// ── streaks (these use the database) ──
describe('streaks', () => {
  let user;
  before(async () => { await resetDb(); });
  beforeEach(async () => {
    await resetDb();
    user = await createUser({ username: 'sam', password: PASSWORD });
  });

  async function routine(over = {}) {
    return prisma.routine.create({ data: { userId: user.id, title: 'Stretch', frequency: 'daily', ...over } });
  }
  async function complete(r, ...dates) {
    for (const s of dates) await prisma.routineCompletion.create({ data: { routineId: r.id, userId: user.id, completedDate: d(s) } });
  }
  const streak = async (r, today) => {
    const current = await recalcStreak(r, today);
    const row = await prisma.routine.findUnique({ where: { id: r.id } });
    const history = await prisma.routineStreakHistory.findMany({ where: { routineId: r.id }, orderBy: { startDate: 'asc' } });
    return { current, row, history };
  };

  it('no completions: zero, and no history', async () => {
    const r = await routine();
    const { current, row, history } = await streak(r, '2026-11-13');
    assert.equal(current, 0);
    assert.equal(row.streakCurrent, 0);
    assert.equal(history.length, 0);
  });

  it('counts days in a row, and today not being done yet does not break it', async () => {
    const r = await routine();
    await complete(r, '2026-11-10', '2026-11-11', '2026-11-12');
    const { current, row, history } = await streak(r, '2026-11-13');
    assert.equal(current, 3);
    assert.equal(row.streakBest, 3);
    assert.deepEqual(history.map((h) => [h.length, h.isActive]), [[3, true]]);
  });

  it('counts today when it is done', async () => {
    const r = await routine();
    await complete(r, '2026-11-11', '2026-11-12', '2026-11-13');
    assert.equal((await streak(r, '2026-11-13')).current, 3);
  });

  it('a missed day ends the current streak but keeps the best one', async () => {
    const r = await routine();
    await complete(r, '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08', '2026-11-10', '2026-11-11');
    const { current, row, history } = await streak(r, '2026-11-13');   // 12th was missed
    assert.equal(current, 0);
    assert.equal(row.streakBest, 4);
    assert.deepEqual(history.map((h) => [h.length, h.isActive]), [[4, false], [2, false]]);
  });

  it('a gap of exactly one missed day splits the runs', async () => {
    const r = await routine();
    await complete(r, '2026-11-10', '2026-11-12');
    const { history } = await streak(r, '2026-11-12');
    assert.deepEqual(history.map((h) => h.length), [1, 1]);
  });

  it('weekdays: a weekend between Friday and Monday is not a gap', async () => {
    const r = await routine({ frequency: 'weekdays' });
    await complete(r, '2026-11-12', '2026-11-13', '2026-11-16');
    assert.equal((await streak(r, '2026-11-17')).current, 3);
  });

  it('weekdays: a missed Friday is a gap', async () => {
    const r = await routine({ frequency: 'weekdays' });
    await complete(r, '2026-11-12', '2026-11-16');
    const { current, row } = await streak(r, '2026-11-16');
    assert.equal(current, 1);
    assert.equal(row.streakBest, 1);
  });

  it('chosen days: Monday and Wednesday only', async () => {
    const r = await routine({ frequency: 'custom', scheduleDays: ['Mon', 'Wed'] });
    await complete(r, '2026-11-09', '2026-11-11', '2026-11-16');
    assert.equal((await streak(r, '2026-11-17')).current, 3, 'Tuesday is not a scheduled day');
    assert.equal((await streak(r, '2026-11-18')).current, 3, 'Wednesday is today and still open');
    assert.equal((await streak(r, '2026-11-19')).current, 0, 'Wednesday the 18th was missed');
  });

  it('crosses a daylight-saving change, a month end, a leap day and a year end without losing a day', async () => {
    for (const [dates, today] of [
      [['2026-03-06', '2026-03-07', '2026-03-08', '2026-03-09', '2026-03-10'], '2026-03-11'],
      [['2026-10-30', '2026-10-31', '2026-11-01', '2026-11-02'], '2026-11-03'],
      [['2028-02-27', '2028-02-28', '2028-02-29', '2028-03-01'], '2028-03-02'],
      [['2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02'], '2027-01-03'],
    ]) {
      const r = await routine();
      await complete(r, ...dates);
      assert.equal((await streak(r, today)).current, dates.length, dates[0]);
    }
  });

  it('is the same however often it is worked out', async () => {
    const r = await routine();
    await complete(r, '2026-11-11', '2026-11-12');
    const a = await streak(r, '2026-11-13');
    const b = await streak(r, '2026-11-13');
    assert.deepEqual(a.history.map((h) => [h.length, h.isActive]), b.history.map((h) => [h.length, h.isActive]));
    assert.equal(a.current, b.current);
  });

  it('only the last run can be active', async () => {
    const r = await routine();
    await complete(r, '2026-11-01', '2026-11-02', '2026-11-12');
    const { history } = await streak(r, '2026-11-13');
    assert.deepEqual(history.map((h) => h.isActive), [false, true]);
  });
});
