const express = require('express');
const crypto  = require('crypto');
const prisma = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const caldav = require('../services/caldavService');
const calSources = require('../lib/calendarSources');
const { prefsHour12 } = require('../lib/timeFormat');
const { getShareableUsers } = require('../lib/users');
const { eventDayStr } = require('../lib/eventDate');
const { zonedToUtc } = require('../lib/timezone');

const router = express.Router();
router.use(requireAuth);

// ── Date helpers ──────────────────────────────────────────────────────────────

function parseDate(str) {
  // Parse as local midnight — new Date('YYYY-MM-DD') is UTC midnight which shifts
  // day-of-week in negative-offset timezones, breaking week navigation
  const parts = (str || '').split('-').map(Number);
  if (parts.length !== 3 || parts.some(isNaN)) return new Date();
  return new Date(parts[0], parts[1] - 1, parts[2]);
}

// Interpret YYYY-MM-DD + HH:MM as wall-clock time in the given IANA timezone and return a UTC Date.
// Without this, new Date('2026-06-24T16:00:00') treats the time as server-local (UTC in Docker),
// storing 4 PM EDT as 16:00Z instead of 20:00Z — then displaying back as 12 PM.
function localTimeToUTC(dateStr, timeStr, tz) {
  return zonedToUtc(dateStr, timeStr, tz);
}

function weekBounds(anchor) {
  // Week starts Monday
  const d = new Date(anchor);
  const dow = d.getDay(); // 0=Sun
  const monday = new Date(d);
  monday.setDate(d.getDate() - ((dow + 6) % 7));
  monday.setHours(0, 0, 0, 0);
  const sunday = new Date(monday);
  sunday.setDate(monday.getDate() + 6);
  sunday.setHours(23, 59, 59, 999);
  return { start: monday, end: sunday };
}

function monthBounds(anchor) {
  const d = new Date(anchor);
  const start = new Date(d.getFullYear(), d.getMonth(), 1);
  const end   = new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59, 999);
  return { start, end };
}

function addDays(date, n) {
  const d = new Date(date);
  d.setDate(d.getDate() + n);
  return d;
}

function isoDate(d) {
  // Use local date parts so the string matches the day the user sees
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

// Returns a Date at local midnight for today in the given timezone.
// Uses new Date(y, m, d) so all getDate/getDay/getMonth calls (which use server local = UTC)
// operate on the correct user-local date.
function todayLocalDate(tz) {
  const str = new Date().toLocaleDateString('en-CA', { timeZone: tz || 'UTC' });
  const [y, mo, d] = str.split('-').map(Number);
  return new Date(y, mo - 1, d);
}

function formatTime(d, use12h = true, tz = 'UTC') {
  return d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: use12h, timeZone: tz });
}

// Build a calendar grid for month view (6 rows × 7 cols, Mon-first)
function buildMonthGrid(anchor, events, tz = 'UTC') {
  const d = new Date(anchor);
  const year = d.getFullYear();
  const month = d.getMonth();
  const firstDay = new Date(year, month, 1);
  const lastDay  = new Date(year, month + 1, 0);
  // Offset to Monday-first
  const startOffset = (firstDay.getDay() + 6) % 7;
  const gridStart = addDays(firstDay, -startOffset);

  const eventMap = {};
  for (const ev of events) {
    const key = eventDayStr(ev.startAt, ev.allDay, tz);
    if (!eventMap[key]) eventMap[key] = [];
    eventMap[key].push(ev);
  }

  const rows = [];
  let cur = new Date(gridStart);
  for (let row = 0; row < 6; row++) {
    const week = [];
    for (let col = 0; col < 7; col++) {
      week.push({
        date: new Date(cur),
        dateStr: isoDate(cur),
        inMonth: cur.getMonth() === month,
        events: (eventMap[isoDate(cur)] || []).sort((a, b) => new Date(a.startAt) - new Date(b.startAt)),
      });
      cur = addDays(cur, 1);
    }
    rows.push(week);
    if (cur > lastDay && row >= 4) break;
  }
  return rows;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

async function renderSources(req, res, { errors = [], success = null } = {}) {
  const [sources, localCalendars, shareableUsers] = await Promise.all([
    prisma.calendarSource.findMany({ where: { userId: req.user.id }, orderBy: { name: 'asc' } }),
    getLocalCalendarsForUser(req.user.id),
    getShareableUsers(req.user.id),
  ]);
  const { selectable } = await buildSelectableCalendars(req.user.id);
  const defaultCalendarTarget = (req.user.preferences || {}).defaultCalendarTarget || 'local';
  return res.render('calendar/sources', {
    title: 'Calendar Sources',
    sources, localCalendars, shareableUsers,
    selectableCalendars: selectable, defaultCalendarTarget,
    errors, success,
  });
}

async function getMemberCalendarIds(userId) {
  const memberships = await prisma.localCalendarMember.findMany({
    where: { userId },
    select: { calendarId: true },
  });
  return memberships.map(m => m.calendarId);
}

async function getLocalCalendarsForUser(userId) {
  return prisma.localCalendar.findMany({
    where: { userId },
    include: {
      members: {
        include: { user: { select: { id: true, username: true, displayName: true } } },
        orderBy: { addedAt: 'asc' },
      },
    },
    orderBy: { name: 'asc' },
  });
}

// ── Event creation (shared with the app API) ─────────────────────────────────

class EventError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

// Start/end instants for a form's date + times: all-day events are bare UTC dates (see eventDate.js)
function eventTimes(eventDate, startTime, endTime, allDay, tz) {
  return allDay
    ? { startAt: new Date(eventDate + 'T00:00:00.000Z'), endAt: new Date(eventDate + 'T23:59:59.000Z') }
    : { startAt: localTimeToUTC(eventDate, startTime || '09:00', tz), endAt: localTimeToUTC(eventDate, endTime || startTime || '10:00', tz) };
}

// Creates an event on the chosen calendar: "local", "local_calendar|{id}",
// "{sourceId}|caldav|{url}" or "{sourceId}|google|{calId}". Throws EventError (403 no access,
// 502 the calendar server refused it).
async function createEventFor(user, { title, eventDate, startTime, endTime, allDay, location, description, calendarTarget, calendarName }) {
  const userId = user.id;
  const target = calendarTarget || 'local';
  const eventData = {
    title: title.trim(),
    ...eventTimes(eventDate, startTime, endTime, allDay, user.timezone || 'UTC'),
    allDay,
    location: location || null,
    description: description || null,
    calendarName: calendarName || null,
  };

  if (target === 'local') {
    return prisma.calendarEvent.create({ data: { userId, ...eventData, createdInObelo: true } });
  }

  if (target.startsWith('local_calendar|')) {
    const lcId = Number(target.split('|')[1]);
    // Only the calendar's owner or a member with edit access may add events to it
    const canWrite = Number.isInteger(lcId) && await prisma.localCalendar.findFirst({
      where: { id: lcId, OR: [{ userId }, { members: { some: { userId, canEdit: true } } }] },
      select: { id: true },
    });
    if (!canWrite) throw new EventError(403, "You don't have access to add events to that calendar.");
    return prisma.calendarEvent.create({ data: { userId, localCalendarId: lcId, ...eventData, createdInObelo: true } });
  }

  const firstPipe  = target.indexOf('|');
  const secondPipe = target.indexOf('|', firstPipe + 1);
  const srcId = Number(target.substring(0, firstPipe));
  const type  = target.substring(firstPipe + 1, secondPipe);
  const dest  = target.substring(secondPipe + 1);

  const source = await prisma.calendarSource.findFirst({ where: { id: srcId, userId } });
  if (!source) throw new Error('Calendar source not found');

  try {
    if (type === 'caldav') return await caldav.createEvent(source, { ...eventData, targetCalendarUrl: dest || null });
    if (type === 'google') return await caldav.createGoogleEvent(source, { ...eventData, calendarId: dest });
  } catch (err) {
    throw new EventError(502, err.message);
  }
  return null;
}

// ── Index — week or month view ────────────────────────────────────────────────

router.get('/', async (req, res, next) => {
  try {
    const view   = req.query.view || 'week';
    const tz     = req.user.timezone || 'UTC';
    const anchor = req.query.date ? parseDate(req.query.date) : todayLocalDate(tz);

    let rangeStart, rangeEnd;
    if (view === 'month') {
      ({ start: rangeStart, end: rangeEnd } = monthBounds(anchor));
    } else {
      ({ start: rangeStart, end: rangeEnd } = weekBounds(anchor));
    }

    const memberCalendarIds = await getMemberCalendarIds(req.user.id);
    const eventWhere = {
      startAt: { gte: rangeStart, lte: rangeEnd },
      ...(memberCalendarIds.length > 0
        ? { OR: [{ userId: req.user.id }, { localCalendarId: { in: memberCalendarIds } }] }
        : { userId: req.user.id }),
    };

    const [events, sources] = await Promise.all([
      prisma.calendarEvent.findMany({
        where: eventWhere,
        include: {
          source: { select: { name: true, color: true, isFamilyCalendar: true } },
          localCalendar: { select: { name: true, color: true } },
        },
        orderBy: { startAt: 'asc' },
      }),
      prisma.calendarSource.findMany({
        where: { userId: req.user.id, active: true },
        orderBy: { name: 'asc' },
      }),
    ]);

    // Build week day columns
    const weekDays = [];
    if (view === 'week') {
      for (let i = 0; i < 7; i++) {
        const day = addDays(rangeStart, i);
        const dayStr = isoDate(day);
        weekDays.push({
          date: day,
          dateStr: dayStr,
          label: day.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }),
          isToday: dayStr === isoDate(todayLocalDate(tz)),
          events: events
            .filter(e => eventDayStr(e.startAt, e.allDay, tz) === dayStr)
            .sort((a, b) => new Date(a.startAt) - new Date(b.startAt)),
        });
      }
    }

    const monthGrid = view === 'month' ? buildMonthGrid(anchor, events, tz) : null;
    const todayStr  = isoDate(todayLocalDate(tz));

    // Navigation: prev/next week or month
    const prevAnchor = view === 'month'
      ? new Date(anchor.getFullYear(), anchor.getMonth() - 1, 1)
      : addDays(rangeStart, -7);
    const nextAnchor = view === 'month'
      ? new Date(anchor.getFullYear(), anchor.getMonth() + 1, 1)
      : addDays(rangeStart, 7);

    res.render('calendar/index', {
      title: 'Calendar',
      view,
      anchor,
      anchorStr: isoDate(anchor),
      prevAnchorStr: isoDate(prevAnchor),
      nextAnchorStr: isoDate(nextAnchor),
      rangeStart,
      rangeEnd,
      weekDays,
      monthGrid,
      events,
      sources,
      todayStr,
      formatTime: (d) => formatTime(d, prefsHour12(req.user.preferences), tz),
      isoDate,
      rangeLabel: view === 'month'
        ? anchor.toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
        : `${rangeStart.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} – ${rangeEnd.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}`,
    });
  } catch (err) { next(err); }
});

// ── New event form ────────────────────────────────────────────────────────────

async function buildSelectableCalendars(userId) {
  const [sources, ownedLocalCals, memberCals] = await Promise.all([
    prisma.calendarSource.findMany({ where: { userId, active: true } }),
    prisma.localCalendar.findMany({ where: { userId }, orderBy: { name: 'asc' } }),
    prisma.localCalendarMember.findMany({
      where: { userId, canEdit: true },
      include: { calendar: true },
    }),
  ]);

  const selectable = [{ value: 'local', label: 'Local only', color: '#374151' }];

  for (const src of sources) {
    const creds = src.credentials || {};
    const discovered = creds.discoveredCalendars || [];
    const selectedUrls = creds.selectedCalendarUrls || [];
    const calsToShow = selectedUrls.length > 0
      ? discovered.filter(c => selectedUrls.includes(c.url))
      : discovered;

    if (calsToShow.length > 0) {
      for (const cal of calsToShow) {
        if (src.type === 'google' && cal.accessRole &&
            !['owner', 'writer'].includes(cal.accessRole)) continue;
        const value = src.type === 'google'
          ? `${src.id}|google|${cal.id}`
          : `${src.id}|caldav|${cal.url}`;
        selectable.push({ value, label: cal.displayName, color: cal.color || src.color });
      }
    } else {
      selectable.push({ value: `${src.id}|caldav|`, label: src.name, color: src.color });
    }
  }

  for (const lc of ownedLocalCals) {
    selectable.push({ value: `local_calendar|${lc.id}`, label: lc.name, color: lc.color });
  }
  for (const m of memberCals) {
    if (!ownedLocalCals.find(lc => lc.id === m.calendarId)) {
      selectable.push({ value: `local_calendar|${m.calendarId}`, label: m.calendar.name, color: m.calendar.color });
    }
  }

  return { sources, selectable };
}

router.get('/events/new', async (req, res, next) => {
  try {
    const { sources, selectable } = await buildSelectableCalendars(req.user.id);
    const prefillDate = req.query.date || new Date().toLocaleDateString('en-CA', { timeZone: req.user.timezone || 'UTC' });
    const defaultCalendarTarget = (req.user.preferences || {}).defaultCalendarTarget || null;
    res.render('calendar/new', {
      title: 'New Event',
      sources,
      selectableCalendars: selectable,
      prefillDate,
      defaultCalendarTarget,
      errors: [],
    });
  } catch (err) { next(err); }
});

// ── Event detail ──────────────────────────────────────────────────────────────

router.get('/events/:id', async (req, res, next) => {
  try {
    const memberCalendarIds = await getMemberCalendarIds(req.user.id);
    const event = await prisma.calendarEvent.findFirst({
      where: {
        id: Number(req.params.id),
        OR: [
          { userId: req.user.id },
          ...(memberCalendarIds.length > 0 ? [{ localCalendarId: { in: memberCalendarIds } }] : []),
        ],
      },
      include: {
        source: { select: { name: true, color: true } },
        localCalendar: { select: { name: true, color: true } },
      },
    });
    if (!event) return res.status(404).render('error', { title: 'Not found', error: { message: 'Event not found.' } });
    res.render('calendar/show', { title: event.title, event, formatTime: (d) => formatTime(d, prefsHour12(req.user.preferences), req.user.timezone || 'UTC') });
  } catch (err) { next(err); }
});

// ── Create event ──────────────────────────────────────────────────────────────

router.post('/events', async (req, res, next) => {
  try {
    const { title, eventDate, startTime, endTime, allDay, location, description,
            calendarTarget, calendarName } = req.body;

    const userId = req.user.id;

    if (!title?.trim() || !eventDate) {
      const { sources, selectable } = await buildSelectableCalendars(userId);
      return res.render('calendar/new', {
        title: 'New Event',
        sources,
        selectableCalendars: selectable,
        prefillDate: eventDate || new Date().toLocaleDateString('en-CA', { timeZone: req.user.timezone || 'UTC' }),
        errors: ['Title and date are required.'],
      });
    }

    try {
      await createEventFor(req.user, {
        title, eventDate, startTime, endTime, allDay: allDay === 'on', location, description, calendarTarget, calendarName,
      });
    } catch (err) {
      if (!(err instanceof EventError)) throw err;
      const { sources, selectable } = await buildSelectableCalendars(userId);
      return res.status(err.status).render('calendar/new', {
        title: 'New Event',
        sources,
        selectableCalendars: selectable,
        prefillDate: eventDate,
        ...(err.status === 502 ? { defaultCalendarTarget: calendarTarget || 'local' } : {}),
        errors: [err.message],
      });
    }

    res.redirect(`/calendar?view=week&date=${eventDate}`);
  } catch (err) { next(err); }
});

// ── Edit event ────────────────────────────────────────────────────────────────

router.get('/events/:id/edit', async (req, res, next) => {
  try {
    const event = await prisma.calendarEvent.findFirst({
      where: { id: Number(req.params.id), userId: req.user.id, createdInObelo: true },
    });
    if (!event) return res.status(404).render('error', { title: 'Not found', error: { message: 'Event not found or not editable.' } });
    const tz = req.user.timezone || 'UTC';
    const startDate = eventDayStr(event.startAt, event.allDay, tz);
    const startTime = event.allDay ? '09:00' : event.startAt.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tz });
    const endTime   = event.allDay ? '10:00' : event.endAt.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tz });
    res.render('calendar/edit', { title: 'Edit Event', event, startDate, startTime, endTime, errors: [] });
  } catch (err) { next(err); }
});

router.post('/events/:id', async (req, res, next) => {
  try {
    const event = await prisma.calendarEvent.findFirst({
      where: { id: Number(req.params.id), userId: req.user.id, createdInObelo: true },
    });
    if (!event) return res.status(404).render('error', { title: 'Not found', error: { message: 'Event not found or not editable.' } });

    const { title, eventDate, startTime, endTime, allDay, location, description } = req.body;
    if (!title?.trim() || !eventDate) {
      const tz = req.user.timezone || 'UTC';
      const sd = eventDayStr(event.startAt, event.allDay, tz);
      const st = event.allDay ? '09:00' : event.startAt.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tz });
      const et = event.allDay ? '10:00' : event.endAt.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: tz });
      return res.render('calendar/edit', { title: 'Edit Event', event, startDate: sd, startTime: st, endTime: et, errors: ['Title and date are required.'] });
    }

    const isAllDay = allDay === 'on';
    const { startAt, endAt } = eventTimes(eventDate, startTime, endTime, isAllDay, req.user.timezone || 'UTC');

    await prisma.calendarEvent.update({
      where: { id: event.id },
      data: { title: title.trim(), startAt, endAt, allDay: isAllDay, location: location || null, description: description || null },
    });
    res.redirect(`/calendar/events/${event.id}`);
  } catch (err) { next(err); }
});

// ── Delete event ──────────────────────────────────────────────────────────────

router.post('/events/:id/delete', async (req, res, next) => {
  try {
    const event = await prisma.calendarEvent.findFirst({
      where: { id: Number(req.params.id), userId: req.user.id },
    });
    if (event) await prisma.calendarEvent.delete({ where: { id: event.id } });
    res.redirect('/calendar');
  } catch (err) { next(err); }
});

// ── Calendar source management ────────────────────────────────────────────────

router.get('/sources', async (req, res, next) => {
  try {
    const success = req.query.connected === 'google' ? 'Google Calendar connected! Syncing now…' : null;
    const errors  = req.query.error === 'google_denied' ? ['Google Calendar connection was cancelled.'] : [];
    await renderSources(req, res, { errors, success });
  } catch (err) { next(err); }
});

// ── Google OAuth2 ─────────────────────────────────────────────────────────────

router.get('/auth/google', requireAuth, async (req, res) => {
  const state = crypto.randomBytes(16).toString('hex');
  req.session.googleOAuthState = state;
  await new Promise((resolve, reject) => req.session.save(err => err ? reject(err) : resolve()));
  const params = new URLSearchParams({
    client_id:     process.env.GOOGLE_CLIENT_ID,
    redirect_uri:  `${process.env.APP_URL || 'http://localhost:3000'}/calendar/auth/google/callback`,
    response_type: 'code',
    scope:         'https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/calendar.events',
    access_type:   'offline',
    prompt:        'consent',
    state,
  });
  res.redirect(`https://accounts.google.com/o/oauth2/v2/auth?${params}`);
});

router.get('/auth/google/callback', requireAuth, async (req, res, next) => {
  try {
    const { code, state, error } = req.query;
    if (error || !code) return res.redirect('/calendar/sources?error=google_denied');
    if (!state || state !== req.session.googleOAuthState) {
      return res.redirect('/calendar/sources?error=google_denied');
    }
    delete req.session.googleOAuthState;

    // Exchange code for tokens
    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id:     process.env.GOOGLE_CLIENT_ID,
        client_secret: process.env.GOOGLE_CLIENT_SECRET,
        redirect_uri:  `${process.env.APP_URL || 'http://localhost:3000'}/calendar/auth/google/callback`,
        grant_type:    'authorization_code',
      }),
    });

    if (!tokenRes.ok) {
      const err = await tokenRes.text();
      throw new Error(`Token exchange failed: ${err}`);
    }

    const tokens = await tokenRes.json();
    if (!tokens.refresh_token) throw new Error('No refresh token returned — try revoking and reconnecting.');

    const expiresAt = Date.now() + tokens.expires_in * 1000;

    // Get calendar list to discover email and available calendars
    const calListRes = await fetch('https://www.googleapis.com/calendar/v3/users/me/calendarList', {
      headers: { Authorization: `Bearer ${tokens.access_token}` },
    });
    if (!calListRes.ok) {
      const errBody = await calListRes.text();
      throw new Error(`Could not fetch Google calendar list (${calListRes.status}): ${errBody}`);
    }
    const calListData = await calListRes.json();

    const primary = calListData.items?.find(c => c.primary) || calListData.items?.[0];
    const email   = primary?.id || 'unknown';

    const discoveredCalendars = await caldav.discoverGoogleCalendars(tokens.access_token, email);

    const source = await prisma.calendarSource.create({
      data: {
        userId: req.user.id,
        type:   'google',
        name:   `Google (${email})`,
        color:  '#4285f4',
        credentials: {
          email,
          accessToken:  caldav.encrypt(tokens.access_token),
          refreshToken: caldav.encrypt(tokens.refresh_token),
          expiresAt,
          discoveredCalendars,
        },
        active: true,
      },
    });

    // Initial sync in background
    caldav.syncSource(source).catch(err => console.error('[google] initial sync failed:', err.message));

    res.redirect('/calendar/sources?connected=google');
  } catch (err) { next(err); }
});

// POST /calendar/sources — add CalDAV source
router.post('/sources', async (req, res, next) => {
  try {
    const b = req.body;
    try {
      const r = await calSources.connectCaldav(req.user.id, b);
      let msg = `Connected! Found ${r.found} calendar(s).`;
      msg += r.syncError ? ` ${r.syncError}` : ` Synced ${r.synced} event(s).`;
      return renderSources(req, res, { success: msg });
    } catch (err) {
      if (err instanceof calSources.SourceError) return renderSources(req, res, { errors: [err.message] });
      throw err;
    }
  } catch (err) { next(err); }
});

// POST /calendar/sources/:id/sync — force sync (synchronous so we can report result)
router.post('/sources/:id/sync', async (req, res, next) => {
  try {
    try {
      const r = await calSources.syncNow(req.user.id, req.params.id);
      return renderSources(req, res, { success: `Synced ${r.count} event(s) from ${r.name}.` });
    } catch (err) {
      if (err.status === 404) return res.status(404).end();
      if (err instanceof calSources.SourceError) return renderSources(req, res, { errors: [err.message] });
      throw err;
    }
  } catch (err) { next(err); }
});

// POST /calendar/sources/:id/color
router.post('/sources/:id/color', requireAuth, async (req, res, next) => {
  try {
    try { await calSources.setSourceColor(req.user.id, req.params.id, req.body.color); } catch (err) { if (err.status !== 404) throw err; }
    res.redirect('/calendar/sources');
  } catch (err) { next(err); }
});

// POST /calendar/sources/:id/delete
router.post('/sources/:id/delete', async (req, res, next) => {
  try {
    try { await calSources.removeSource(req.user.id, req.params.id); } catch (err) { if (err.status !== 404) throw err; }
    res.redirect('/calendar/sources');
  } catch (err) { next(err); }
});

// POST /calendar/sources/:id/set-calendars — pick which calendars to sync
router.post('/sources/:id/set-calendars', async (req, res, next) => {
  try {
    // calendarUrls may be a string (one checked) or array (multiple) or undefined (none)
    const raw = req.body.calendarUrls;
    const urls = raw ? (Array.isArray(raw) ? raw : [raw]) : [];
    try {
      const r = await calSources.setSelectedCalendars(req.user.id, req.params.id, urls);
      return renderSources(req, res, r.syncError
        ? { errors: [r.syncError] }
        : { success: `Saved. Synced ${r.count} event(s) from ${r.selected || 'all'} calendar(s).` });
    } catch (err) {
      if (err.status === 404) return res.status(404).end();
      throw err;
    }
  } catch (err) { next(err); }
});

// POST /calendar/sources/:id/set-family — designate family calendar
router.post('/sources/:id/set-family', async (req, res, next) => {
  try {
    try { await calSources.setFamilyCalendar(req.user.id, req.params.id, req.body.calendarUrl || null); } catch (err) { if (!(err instanceof calSources.SourceError)) throw err; }
    res.redirect('/calendar/sources');
  } catch (err) { next(err); }
});

// POST /calendar/set-default — save default calendar target to user preferences
router.post('/set-default', async (req, res, next) => {
  try {
    await calSources.setDefaultTarget(req.user.id, req.body.calendarTarget || null);
    res.redirect('/calendar/sources');
  } catch (err) { next(err); }
});

// ── Local Calendar CRUD ───────────────────────────────────────────────────────

router.get('/local-calendars/new', (req, res) => {
  res.render('calendar/local-calendar-form', {
    title: 'New Shared Calendar',
    localCalendar: null,
    errors: [],
  });
});

router.post('/local-calendars', async (req, res, next) => {
  try {
    try {
      await calSources.createLocal(req.user.id, req.body);
    } catch (err) {
      if (!(err instanceof calSources.SourceError)) throw err;
      return res.render('calendar/local-calendar-form', { title: 'New Shared Calendar', localCalendar: null, errors: [err.message] });
    }
    res.redirect('/calendar/sources');
  } catch (err) { next(err); }
});

router.post('/local-calendars/:id', async (req, res, next) => {
  try {
    try { await calSources.updateLocal(req.user.id, req.params.id, req.body); } catch (err) {
      if (err.status === 404) return res.status(404).end();
      throw err;
    }
    res.redirect('/calendar/sources');
  } catch (err) { next(err); }
});

router.post('/local-calendars/:id/color', async (req, res, next) => {
  try {
    const lc = await prisma.localCalendar.findFirst({ where: { id: Number(req.params.id) || 0, userId: req.user.id } });
    if (lc) await calSources.updateLocal(req.user.id, lc.id, { name: lc.name, color: req.body.color });
    res.redirect('/calendar/sources');
  } catch (err) { next(err); }
});

router.post('/local-calendars/:id/delete', async (req, res, next) => {
  try {
    try { await calSources.deleteLocal(req.user.id, req.params.id); } catch (err) { if (err.status !== 404) throw err; }
    res.redirect('/calendar/sources');
  } catch (err) { next(err); }
});

router.post('/local-calendars/:id/members', async (req, res, next) => {
  try {
    try {
      const r = await calSources.addMember(req.user.id, req.params.id, req.body.username);
      return renderSources(req, res, { success: `${r.person} added to "${r.calendar}".` });
    } catch (err) {
      if (!(err instanceof calSources.SourceError)) throw err;
      if (err.status === 404 && err.message === 'Not found') return res.status(404).end();
      return renderSources(req, res, { errors: [err.message] });
    }
  } catch (err) { next(err); }
});

router.post('/local-calendars/:id/members/:userId/remove', async (req, res, next) => {
  try {
    try { await calSources.removeMember(req.user.id, req.params.id, req.params.userId); } catch (err) {
      if (err.status === 404) return res.status(404).end();
      throw err;
    }
    res.redirect('/calendar/sources');
  } catch (err) { next(err); }
});

module.exports = { router, buildSelectableCalendars, createEventFor, eventTimes, localTimeToUTC, EventError };
