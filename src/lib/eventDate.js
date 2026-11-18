// All-day calendar events (birthdays, holidays, etc.) are stored as a bare UTC-midnight
// timestamp with no real time-of-day (see caldavService.js parsing of ICS VALUE=DATE, and
// calendar.js event creation: `new Date(eventDate + 'T00:00:00.000Z')`). Their calendar day
// must always be read back out in UTC — never shifted through the viewer's local timezone,
// or the event rolls back a day for anyone in a timezone behind UTC.
//
// Timed events carry a real instant and must use the viewer's local timezone so they land
// under the day the viewer actually experiences them.
//
// This distinction is the whole bug class behind the "calendar events on wrong day" issue
// that has recurred more than once (v3.9.2 fixed it for timed events by switching UTC ->
// local-timezone bucketing, which inadvertently broke all-day events the same way in
// reverse). Every place that buckets/displays a CalendarEvent by day must go through this
// helper instead of calling toLocaleDateString directly, so the fix only has to be correct
// in one place.
function eventDayStr(startAt, allDay, tz) {
  const d = new Date(startAt);
  return allDay
    ? d.toISOString().slice(0, 10)
    : d.toLocaleDateString('en-CA', { timeZone: tz || 'UTC' });
}

module.exports = { eventDayStr };
