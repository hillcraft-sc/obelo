// "When is the next one?" for recurring tasks and reminders. Both used to carry their own copy of
// this, with the same flaw: adding a month with setUTCMonth() runs over the end of short months,
// so Jan 31 + 1 month became Mar 3 (not Feb 28), and Feb 29 + 1 year became Mar 1.
//
// Dates here are what the app stores for a due date: UTC midnight of the user's local date.

const WEEKDAY_NUM = { sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6 };
const ORDINAL_NUM = { first: 1, second: 2, third: 3, fourth: 4 };

const daysInMonth = (year, month0) => new Date(Date.UTC(year, month0 + 1, 0)).getUTCDate();

// Same day of the month, `n` months later; if that month is shorter, the last day of it
function addMonths(date, n) {
  const out = new Date(date);
  const total = out.getUTCFullYear() * 12 + out.getUTCMonth() + n;
  const year = Math.floor(total / 12), month0 = ((total % 12) + 12) % 12;
  out.setUTCFullYear(year, month0, Math.min(out.getUTCDate(), daysInMonth(year, month0)));
  return out;
}

const addYears = (date, n) => addMonths(date, 12 * n);

// The day of the month of the Nth weekday ("second Tuesday", or "last Friday") of a month (0-based)
function nthWeekdayOfMonth(year, month0, ordinal, weekdayName) {
  const targetDay = WEEKDAY_NUM[weekdayName] ?? 0;
  if (ordinal === 'last') {
    const d = new Date(Date.UTC(year, month0 + 1, 0));
    while (d.getUTCDay() !== targetDay) d.setUTCDate(d.getUTCDate() - 1);
    return d.getUTCDate();
  }
  const n = ORDINAL_NUM[ordinal] || 1;
  const first = new Date(Date.UTC(year, month0, 1));
  const offset = (targetDay - first.getUTCDay() + 7) % 7;
  return 1 + offset + (n - 1) * 7;
}

// The next due date after `base` (a Date, or null for "now") for a rule such as "daily",
// "weekdays", "monthly" or "custom:monthly:2:each:15". Returns { dueDate, dueTime, hourly }, or null
// when the rule means no recurrence. `hourly` is true for the hourly rule, which moves the time of
// day and not the date (unless it passes midnight).
//
// `rule` is set when the repeat has to change to stay right: a monthly repeat that landed on a
// shorter month (Jan 31 -> Feb 28) becomes "every N months on day 31", so it goes back to the 31st
// in the next long month instead of staying on the 28th.
function nextRecurrence(base, rule, dueTime) {
  const next = new Date(base || Date.now());
  rule = rule || '';
  let newDueTime = dueTime;
  let hourly = false;
  let result = next;
  let newRule;
  const baseDay = next.getUTCDate();
  // monthly-style repeats remember the day they were set on once a short month has cut it
  const monthly = (n) => {
    result = addMonths(next, n);
    if (result.getUTCDate() < baseDay) newRule = `custom:monthly:${n}:each:${baseDay}`;
  };

  if (rule.startsWith('custom:')) {
    const parts = rule.split(':');
    const freq = parts[1];
    const interval = parseInt(parts[2]) || 1;
    switch (freq) {
      case 'daily': next.setUTCDate(next.getUTCDate() + interval); break;
      case 'weekly': next.setUTCDate(next.getUTCDate() + interval * 7); break;
      case 'monthly': {
        result = addMonths(next, interval);
        const dayType = parts[3];
        if (dayType === 'each') {
          const dom = parseInt(parts[4]) || 1;
          result.setUTCDate(Math.min(dom, daysInMonth(result.getUTCFullYear(), result.getUTCMonth())));
        } else if (dayType === 'onthe') {
          result.setUTCDate(nthWeekdayOfMonth(result.getUTCFullYear(), result.getUTCMonth(), parts[4], parts[5]));
        }
        break;
      }
      case 'yearly': result = addYears(next, interval); break;
      default: return null;
    }
  } else {
    switch (rule) {
      case 'hourly': {
        const [h, m] = (dueTime || '09:00').split(':').map(Number);
        hourly = true;
        if (h + 1 >= 24) {
          next.setUTCDate(next.getUTCDate() + 1);
          newDueTime = `00:${String(m).padStart(2, '0')}`;
        } else {
          newDueTime = `${String(h + 1).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
        }
        break;
      }
      case 'daily': next.setUTCDate(next.getUTCDate() + 1); break;
      case 'weekdays':
        next.setUTCDate(next.getUTCDate() + 1);
        while ([0, 6].includes(next.getUTCDay())) next.setUTCDate(next.getUTCDate() + 1);
        break;
      case 'weekends':
        next.setUTCDate(next.getUTCDate() + 1);
        while (![0, 6].includes(next.getUTCDay())) next.setUTCDate(next.getUTCDate() + 1);
        break;
      case 'weekly': next.setUTCDate(next.getUTCDate() + 7); break;
      case 'biweekly': next.setUTCDate(next.getUTCDate() + 14); break;
      case 'monthly': monthly(1); break;
      case 'every3months': monthly(3); break;
      case 'every6months': monthly(6); break;
      case 'yearly': result = addYears(next, 1); break;
      default: return null;
    }
  }
  return { dueDate: result, dueTime: newDueTime, hourly, rule: newRule };
}

module.exports = { addMonths, addYears, daysInMonth, nthWeekdayOfMonth, nextRecurrence };
