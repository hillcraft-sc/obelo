// Converting a wall-clock time in a time zone ("2026-06-15 09:00 in New York") to the real moment.
// This is the one place that does it. Two copies of it elsewhere were each wrong in a different
// way: one moved a reminder a whole day for early-morning times behind UTC and late-evening times
// ahead of it, the other was an hour out around daylight-saving changes.

const formatters = new Map();
function formatter(tz) {
  if (!formatters.has(tz)) {
    formatters.set(tz, new Intl.DateTimeFormat('en-US', {
      timeZone: tz, hourCycle: 'h23',
      year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric',
    }));
  }
  return formatters.get(tz);
}

// How far the zone's clock is ahead of UTC at this moment, in milliseconds (New York in June: -4 h)
function offsetAt(ms, tz) {
  const p = {};
  for (const { type, value } of formatter(tz).formatToParts(new Date(ms))) p[type] = Number(value);
  const shown = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  return shown - Math.floor(ms / 1000) * 1000;
}

// The moment when the wall clock in `tz` reads `dateStr` ("YYYY-MM-DD") at `hhmm` ("HH:MM").
//   - A time that happens twice (the hour the clocks go back) gives the first one.
//   - A time that never happens (the hour the clocks go forward) gives the moment just after the
//     change, so 02:30 becomes 03:30.
// An unknown zone throws, like Intl does.
function zonedToUtc(dateStr, hhmm, tz) {
  const [y, mo, d] = String(dateStr).slice(0, 10).split('-').map(Number);
  const [h, m] = String(hhmm).split(':').map(Number);
  const wall = Date.UTC(y, mo - 1, d, h, m);
  if (!tz || tz === 'UTC') return new Date(wall);

  // The offset a day before and a day after bracket any single clock change
  const before = offsetAt(wall - 86400000, tz);
  const after = offsetAt(wall + 86400000, tz);
  const candidates = [wall - before, wall - after].filter((ms, i) => offsetAt(ms, tz) === (i === 0 ? before : after));
  if (candidates.length === 2) return new Date(Math.min(...candidates));
  if (candidates.length === 1) return new Date(candidates[0]);
  return new Date(Math.max(wall - before, wall - after));   // the clocks skipped this time
}

module.exports = { zonedToUtc, offsetAt };
