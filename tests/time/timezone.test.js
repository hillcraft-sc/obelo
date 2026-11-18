require('../helpers/env');
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { zonedToUtc, offsetAt } = require('../../src/lib/timezone');
const { buildReminderAt } = require('../../src/routes/reminders');
const { localTimeToUTC } = require('../../src/routes/calendar');

const ZONES = [
  'UTC', 'America/New_York', 'America/Los_Angeles', 'America/Sao_Paulo', 'Europe/London', 'Europe/Berlin',
  'Asia/Tokyo', 'Asia/Kolkata', 'Asia/Kathmandu', 'Australia/Sydney', 'Australia/Lord_Howe',
  'Pacific/Auckland', 'Pacific/Chatham', 'Pacific/Kiritimati', 'Pacific/Honolulu', 'Etc/GMT+12',
];

// What the clock on the wall says in `tz` at instant `ms`, as "YYYY-MM-DD HH:MM"
const wallAt = (ms, tz) => new Date(ms + offsetAt(ms, tz)).toISOString().slice(0, 16).replace('T', ' ');
const MIN = 60000;

describe('zonedToUtc: concrete answers', () => {
  const cases = [
    ['2026-06-15', '09:00', 'America/New_York', '2026-06-15T13:00:00.000Z'],
    ['2026-01-15', '09:00', 'America/New_York', '2026-01-15T14:00:00.000Z'],
    // the cases the old code put on the wrong day
    ['2026-06-15', '01:00', 'America/New_York', '2026-06-15T05:00:00.000Z'],
    ['2026-06-15', '00:30', 'America/Los_Angeles', '2026-06-15T07:30:00.000Z'],
    ['2026-06-15', '23:00', 'Asia/Tokyo', '2026-06-15T14:00:00.000Z'],
    ['2026-06-15', '23:30', 'Australia/Sydney', '2026-06-15T13:30:00.000Z'],
    ['2026-06-15', '00:00', 'Pacific/Kiritimati', '2026-06-14T10:00:00.000Z'],
    ['2026-01-01', '00:00', 'Pacific/Honolulu', '2026-01-01T10:00:00.000Z'],
    // half and quarter hour zones
    ['2026-06-15', '12:00', 'Asia/Kolkata', '2026-06-15T06:30:00.000Z'],
    ['2026-06-15', '12:00', 'Asia/Kathmandu', '2026-06-15T06:15:00.000Z'],
    // New York: clocks go forward 2026-03-08 (02:00 -> 03:00) and back 2026-11-01 (02:00 -> 01:00)
    ['2026-03-08', '01:59', 'America/New_York', '2026-03-08T06:59:00.000Z'],
    ['2026-03-08', '02:30', 'America/New_York', '2026-03-08T07:30:00.000Z'],   // does not exist: 03:30
    ['2026-03-08', '03:30', 'America/New_York', '2026-03-08T07:30:00.000Z'],
    ['2026-11-01', '01:30', 'America/New_York', '2026-11-01T05:30:00.000Z'],   // happens twice: the first
    ['2026-11-01', '02:30', 'America/New_York', '2026-11-01T07:30:00.000Z'],
    // London: forward 2026-03-29, back 2026-10-25
    ['2026-03-29', '01:30', 'Europe/London', '2026-03-29T01:30:00.000Z'],      // does not exist: 02:30 BST
    ['2026-10-25', '01:30', 'Europe/London', '2026-10-25T00:30:00.000Z'],      // happens twice: the first
    // Sydney (southern hemisphere): forward 2026-10-04, back 2026-04-05
    ['2026-10-04', '02:30', 'Australia/Sydney', '2026-10-03T16:30:00.000Z'],
    ['2026-04-05', '02:30', 'Australia/Sydney', '2026-04-04T15:30:00.000Z'],
    ['2026-02-28', '23:59', 'UTC', '2026-02-28T23:59:00.000Z'],
  ];
  for (const [date, time, tz, expected] of cases) {
    it(`${date} ${time} in ${tz} is ${expected}`, () => {
      assert.equal(zonedToUtc(date, time, tz).toISOString(), expected);
    });
  }

  it('reads an ISO timestamp as just its date, and an empty zone as UTC', () => {
    assert.equal(zonedToUtc('2026-06-15T00:00:00.000Z', '09:00', 'America/New_York').toISOString(), '2026-06-15T13:00:00.000Z');
    assert.equal(zonedToUtc('2026-06-15', '09:00', undefined).toISOString(), '2026-06-15T09:00:00.000Z');
  });

  it('throws for a zone that does not exist, so a typo is not silently UTC', () => {
    assert.throws(() => zonedToUtc('2026-06-15', '09:00', 'Mars/Olympus_Mons'));
  });
});

describe('zonedToUtc: the clock on the wall always reads what was asked', () => {
  it('for every day of 2026, at awkward times, in 16 zones', () => {
    const wrong = [];
    for (const tz of ZONES) {
      for (let day = 0; day < 365; day++) {
        const date = new Date(Date.UTC(2026, 0, 1 + day)).toISOString().slice(0, 10);
        for (const time of ['00:00', '00:30', '01:30', '04:59', '09:00', '12:00', '23:30', '23:59']) {
          const ms = zonedToUtc(date, time, tz).getTime();
          const wall = wallAt(ms, tz);
          // Only the hour the clocks skip may differ, and only on a day the offset changes
          if (wall !== `${date} ${time}` && offsetAt(Date.UTC(2026, 0, 1 + day), tz) === offsetAt(Date.UTC(2026, 0, 2 + day), tz)) {
            wrong.push(`${tz} ${date} ${time} -> ${wall}`);
          }
        }
      }
    }
    assert.deepEqual(wrong.slice(0, 10), []);
  });
});

describe('zonedToUtc: agrees with a brute-force search around every clock change in 2026-2027', () => {
  for (const tz of ZONES) {
    it(tz, () => {
      // Find each moment the zone's offset changes, to the minute
      const transitions = [];
      const start = Date.UTC(2026, 0, 1), end = Date.UTC(2028, 0, 1);
      for (let t = start; t < end; t += 3600000) {
        if (offsetAt(t, tz) !== offsetAt(t + 3600000, tz)) {
          let lo = t, hi = t + 3600000;
          while (hi - lo > MIN) { const mid = Math.floor((lo + hi) / 2 / MIN) * MIN; if (offsetAt(mid, tz) === offsetAt(lo, tz)) lo = mid; else hi = mid; }
          transitions.push(hi);
        }
      }
      for (const T of transitions) {
        const before = offsetAt(T - MIN, tz), after = offsetAt(T, tz);
        // every quarter hour from two hours before to two hours after, on the wall clock
        for (let wall = T + before - 120 * MIN; wall <= T + after + 120 * MIN; wall += 15 * MIN) {
          const date = new Date(wall).toISOString().slice(0, 10), time = new Date(wall).toISOString().slice(11, 16);
          // all instants (in a window) whose wall clock reads this
          const matches = [];
          for (let t = T - 6 * 3600000; t <= T + 6 * 3600000; t += MIN) if (wallAt(t, tz) === `${date} ${time}`) matches.push(t);
          let expected;
          if (matches.length) expected = Math.min(...matches);                        // twice: the first
          else expected = T + (wall - (T + before));                                  // skipped: just after the change
          assert.equal(zonedToUtc(date, time, tz).getTime(), expected, `${tz} ${date} ${time}`);
        }
      }
    });
  }
});

describe('the two places that use it', () => {
  it('reminders: the right day for early and late times (the old code was a day out)', () => {
    assert.equal(buildReminderAt('2026-06-15', '01:00', 0, 'America/New_York').toISOString(), '2026-06-15T05:00:00.000Z');
    assert.equal(buildReminderAt('2026-06-15', '23:00', 0, 'Asia/Tokyo').toISOString(), '2026-06-15T14:00:00.000Z');
  });

  it('reminders: "15 minutes before" can cross into the day before', () => {
    assert.equal(buildReminderAt('2026-06-15', '00:10', 15, 'UTC').toISOString(), '2026-06-14T23:55:00.000Z');
  });

  it('reminders: nothing without a date and a time', () => {
    assert.equal(buildReminderAt(null, '09:00', 0, 'UTC'), null);
    assert.equal(buildReminderAt('2026-06-15', '', 0, 'UTC'), null);
  });

  it('reminders: a due date stored as a UTC midnight timestamp is read as that date', () => {
    assert.equal(buildReminderAt(new Date('2026-06-15T00:00:00.000Z'), '09:00', 0, 'America/New_York').toISOString(), '2026-06-15T13:00:00.000Z');
  });

  it('calendar: an event at 3:30 on the day the clocks go forward is not an hour out', () => {
    assert.equal(localTimeToUTC('2026-03-08', '03:30', 'America/New_York').toISOString(), '2026-03-08T07:30:00.000Z');
    assert.equal(localTimeToUTC('2026-06-24', '16:00', 'America/New_York').toISOString(), '2026-06-24T20:00:00.000Z');
  });

  it('the two give the same answer for the same input', () => {
    for (const tz of ZONES) for (const [d, t] of [['2026-03-08', '09:00'], ['2026-11-01', '00:30'], ['2026-07-04', '23:45']]) {
      assert.equal(localTimeToUTC(d, t, tz).getTime(), buildReminderAt(d, t, 0, tz).getTime(), `${tz} ${d} ${t}`);
    }
  });
});
