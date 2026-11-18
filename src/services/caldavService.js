const { createDAVClient } = require('tsdav');
const ical = require('node-ical');
const ICalGenerator = require('ical-generator');
const crypto = require('crypto');
const prisma = require('../lib/prisma');

// ── Credential encryption ─────────────────────────────────────────────────────
// See src/lib/credentials.js (AES-256-GCM; legacy AES-256-CBC values still readable)
const { encrypt, decrypt } = require('../lib/credentials');

// ── CalDAV client factory (iCloud / standard CalDAV) ─────────────────────────

async function makeClient(username, password, serverUrl = 'https://caldav.icloud.com') {
  return createDAVClient({
    serverUrl,
    credentials: { username, password },
    authMethod: 'Basic',
    defaultAccountType: 'caldav',
  });
}

function basicAuthHeader(username, password) {
  return 'Basic ' + Buffer.from(`${username}:${password}`).toString('base64');
}

// ── Raw CalDAV REPORT ─────────────────────────────────────────────────────────
// Used for any server where we have an authHeader (Basic or Bearer).

async function rawCalendarReport(calendarUrl, authHeader) {
  const body = `<?xml version="1.0" encoding="utf-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VEVENT"/>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>`;

  const res = await fetch(calendarUrl, {
    method: 'REPORT',
    headers: {
      Authorization: authHeader,
      'Content-Type': 'application/xml; charset=utf-8',
      'Depth': '1',
    },
    body,
  });

  if (!res.ok) throw new Error(`REPORT ${calendarUrl} returned ${res.status} ${res.statusText}`);

  const xml = await res.text();
  const matches = [...xml.matchAll(/<[^:>]*:?calendar-data[^>]*>([\s\S]*?)<\/[^:>]*:?calendar-data>/gi)];
  return matches.map(m => m[1].trim()).filter(Boolean);
}

// ── Parse ICS data into event objects ─────────────────────────────────────────

// ICS property values can be plain strings or { val, params } objects
const icsText = v => (v && typeof v === 'object' ? v.val : v) || null;

// Converts one parsed VEVENT into event rows within [rangeStart, rangeEnd]. Recurring events
// (RRULE) are expanded into one row per occurrence, honouring EXDATE and moved occurrences
// (RECURRENCE-ID) — otherwise only the first occurrence would ever show.
function veventToEvents(comp, rangeStart, rangeEnd, { externalId, calendarUrl, etag }) {
  const base = {
    externalId,
    location:    icsText(comp.location),
    description: icsText(comp.description),
    url:         icsText(comp.url),
    etag,
    calendarUrl,
  };

  if (comp.rrule) {
    let instances = [];
    try {
      instances = ical.expandRecurringEvent(comp, { from: rangeStart, to: rangeEnd, expandOngoing: true });
    } catch (err) {
      console.error(`[caldav] could not expand recurring event ${externalId}: ${err.message}`);
    }
    return instances.map(inst => ({
      ...base,
      title:       icsText(inst.summary) || icsText(comp.summary) || '(No title)',
      location:    icsText(inst.event?.location) || base.location,
      description: icsText(inst.event?.description) || base.description,
      startAt:     inst.start,
      endAt:       inst.end || inst.start,
      allDay:      inst.isFullDay,
    }));
  }

  const startAt = comp.start instanceof Date ? comp.start : new Date(comp.start);
  const endAt   = comp.end   instanceof Date ? comp.end   : new Date(comp.end || startAt);
  if (isNaN(startAt) || startAt > rangeEnd || (!isNaN(endAt) && endAt < rangeStart)) return [];
  return [{
    ...base,
    title:   icsText(comp.summary) || '(No title)',
    startAt,
    endAt:   isNaN(endAt) ? startAt : endAt,
    allDay:  comp.datetype === 'date',
  }];
}

function icsToEvents(icsData, rangeStart, rangeEnd, { fallbackId, calendarUrl, etag }) {
  let parsed;
  try { parsed = ical.sync.parseICS(icsData); } catch { return []; }
  const events = [];
  for (const comp of Object.values(parsed)) {
    // Moved occurrences are applied through their base event's expansion
    if (comp.type !== 'VEVENT' || comp.recurrenceid) continue;
    events.push(...veventToEvents(comp, rangeStart, rangeEnd, { externalId: comp.uid || fallbackId, calendarUrl, etag }));
  }
  return events;
}

function parseIcsEvents(icsDataList, rangeStart, rangeEnd, calendarUrl) {
  return icsDataList.flatMap(icsData =>
    icsToEvents(icsData, rangeStart, rangeEnd, { fallbackId: calendarUrl, calendarUrl }));
}

// ── Google OAuth2 helpers ─────────────────────────────────────────────────────

async function getGoogleAccessToken(source) {
  const creds = source.credentials;
  const now   = Date.now();

  // Return cached token if still valid (60s buffer)
  if (creds.accessToken && creds.expiresAt && now < creds.expiresAt - 60_000) {
    return decrypt(creds.accessToken);
  }

  // Refresh
  const refreshToken = decrypt(creds.refreshToken);
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id:     process.env.GOOGLE_CLIENT_ID,
      client_secret: process.env.GOOGLE_CLIENT_SECRET,
      refresh_token: refreshToken,
      grant_type:    'refresh_token',
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Google token refresh failed: ${err}`);
  }

  const data = await res.json();
  const newExpiresAt = now + data.expires_in * 1000;

  await prisma.calendarSource.update({
    where: { id: source.id },
    data: {
      credentials: {
        ...creds,
        accessToken: encrypt(data.access_token),
        expiresAt:   newExpiresAt,
      },
    },
  });

  return data.access_token;
}

// ── Discover calendars (iCloud / Other CalDAV) ────────────────────────────────

async function discoverCalendars(username, password, serverUrl = 'https://caldav.icloud.com', calendarHomeUrl = null) {
  if (calendarHomeUrl) {
    const authHdr = basicAuthHeader(username, password);
    const probe = await fetch(calendarHomeUrl, {
      method: 'PROPFIND',
      headers: {
        Authorization: authHdr,
        'Depth': '0',
        'Content-Type': 'application/xml',
      },
      body: `<?xml version="1.0"?><D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/></D:prop></D:propfind>`,
    });
    if (probe.status === 401) throw new Error('Invalid credentials — check your username and app-specific password.');
    if (!probe.ok && probe.status !== 207) throw new Error(`Server returned ${probe.status} ${probe.statusText}`);
    return [{ displayName: username, url: calendarHomeUrl, color: '#6366f1' }];
  }

  const client = await makeClient(username, password, serverUrl);
  const calendars = await client.fetchCalendars();
  return calendars.map(c => ({
    displayName: c.displayName || c.url.split('/').filter(Boolean).pop(),
    url:   c.url,
    color: c.calendarColor || '#6366f1',
  }));
}

// ── Discover Google calendars via REST API (called from OAuth callback) ───────

async function discoverGoogleCalendars(accessToken, email) {
  const res = await fetch('https://www.googleapis.com/calendar/v3/users/me/calendarList', {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) throw new Error(`Could not fetch Google calendar list: ${res.status}`);
  const data = await res.json();

  return (data.items || []).map(cal => ({
    displayName: cal.summary || cal.id,
    // Primary calendar uses /events/, others use /cal:{id}/events/
    url: cal.primary
      ? `https://apidata.googleusercontent.com/caldav/v2/${email}/events/`
      : `https://apidata.googleusercontent.com/caldav/v2/${email}/cal:${cal.id}/events/`,
    color: cal.backgroundColor || '#4285f4',
    id:    cal.id,
    primary:    cal.primary || false,
    accessRole: cal.accessRole || null,
  }));
}

// ── Sync a single CalendarSource ─────────────────────────────────────────────

async function syncSource(source) {
  const creds = source.credentials;
  const now      = new Date();
  const rangeStart = new Date(now.getFullYear(), now.getMonth() - 3, 1);
  const rangeEnd   = new Date(now.getFullYear(), now.getMonth() + 6, 0);

  let events = [];

  // ── Google OAuth path (REST API) ───────────────────────────────────────────
  if (source.type === 'google') {
    if (!creds?.refreshToken) throw new Error('Missing Google OAuth credentials');

    const accessToken    = await getGoogleAccessToken(source);
    const discoveredCals = creds.discoveredCalendars || [];
    const selectedUrls   = creds.selectedCalendarUrls || [];

    const calsToSync = selectedUrls.length > 0
      ? discoveredCals.filter(c => selectedUrls.includes(c.url))
      : discoveredCals;

    // Fall back to primary calendar by email if nothing discovered yet
    if (calsToSync.length === 0) {
      calsToSync.push({ id: creds.email, url: '', displayName: 'Primary' });
    }

    for (const cal of calsToSync) {
      const calId = cal.id || creds.email;
      const apiUrl = `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calId)}/events`;
      const params = new URLSearchParams({
        timeMin:      rangeStart.toISOString(),
        timeMax:      rangeEnd.toISOString(),
        singleEvents: 'true',
        maxResults:   '2500',
      });
      const res = await fetch(`${apiUrl}?${params}`, {
        headers: { Authorization: `Bearer ${accessToken}` },
      });
      if (!res.ok) {
        const body = await res.text();
        throw new Error(`Google Calendar REST failed for ${cal.displayName}: ${res.status} ${body}`);
      }
      const data = await res.json();
      console.log(`[google]   got ${(data.items || []).length} items`);
      for (const item of (data.items || [])) {
        if (item.status === 'cancelled') continue;
        const startRaw = item.start?.dateTime || item.start?.date;
        const endRaw   = item.end?.dateTime   || item.end?.date;
        const allDay   = !item.start?.dateTime;
        const startAt  = startRaw ? new Date(startRaw) : new Date();
        const endAt    = endRaw   ? new Date(endRaw)   : startAt;
        events.push({
          externalId:  item.id,
          title:       item.summary     || '(No title)',
          startAt,
          endAt,
          allDay,
          location:    item.location    || null,
          description: item.description || null,
          url:         item.htmlLink    || null,
          calendarUrl: cal.url || calId,
        });
      }
    }

  // ── Direct-URL path (Other CalDAV that needs basic auth without discovery) ─
  } else if (creds?.calendarHomeUrl) {
    if (!creds.username) throw new Error('Missing credentials');
    const password   = creds.passwordEnc ? decrypt(creds.passwordEnc) : creds.password;
    const authHeader = basicAuthHeader(creds.username, password);

    const calUrls = (creds.selectedCalendarUrls?.length > 0)
      ? creds.selectedCalendarUrls
      : [creds.calendarHomeUrl];

    for (const calUrl of calUrls) {
      const icsDataList = await rawCalendarReport(calUrl, authHeader);
      console.log(`[caldav]   got ${icsDataList.length} items`);
      events.push(...parseIcsEvents(icsDataList, rangeStart, rangeEnd, calUrl));
    }

  // ── Standard CalDAV path (iCloud etc. — tsdav handles discovery) ──────────
  } else {
    if (!creds?.username) throw new Error('Missing credentials');
    const password = creds.passwordEnc ? decrypt(creds.passwordEnc) : creds.password;
    const client   = await makeClient(creds.username, password, creds.serverUrl || 'https://caldav.icloud.com');

    const all = await client.fetchCalendars();
    let calendarsToSync = (creds.selectedCalendarUrls?.length > 0)
      ? all.filter(c => creds.selectedCalendarUrls.includes(c.url))
      : all;
    if (calendarsToSync.length === 0) calendarsToSync = all;

    console.log(`[caldav] syncing ${calendarsToSync.length} calendar(s) for source ${source.id}`);

    for (const calendar of calendarsToSync) {
      let objects;
      try {
        objects = await client.fetchCalendarObjects({
          calendar,
          timeRange: { start: rangeStart.toISOString(), end: rangeEnd.toISOString() },
        });
        console.log(`[caldav]    got ${objects.length} objects`);
      } catch (err) {
        const detail = err.cause?.message || err.message;
        throw new Error(`Fetching events from ${calendar.displayName || calendar.url} failed: ${detail}`);
      }

      for (const obj of objects) {
        if (!obj.data) continue;
        events.push(...icsToEvents(obj.data, rangeStart, rangeEnd, {
          fallbackId: obj.url, calendarUrl: calendar.url, etag: obj.etag,
        }));
      }
    }
  }

  // ── Persist ───────────────────────────────────────────────────────────────
  // Build calendarUrl → displayName lookup for tagging synced events
  const calNameMap = {};
  for (const cal of (creds?.discoveredCalendars || [])) {
    if (cal.url) calNameMap[cal.url] = cal.displayName;
    if (cal.id)  calNameMap[cal.id]  = cal.displayName;
  }

  // Events created in Obelo are kept as their own rows. Their copies on the server are
  // skipped (otherwise they'd show twice), and they're pruned only if they fall inside the
  // range we fetched yet weren't returned — i.e. they really were deleted on the server.
  const fetchedUids = new Set(events.map(e => e.externalId).filter(Boolean));
  const vtEvents    = await prisma.calendarEvent.findMany({
    where: { sourceId: source.id, createdInObelo: true, externalId: { not: null } },
    select: { id: true, externalId: true, startAt: true },
  });
  const vtUids = new Set(vtEvents.map(e => e.externalId));
  const deletedOnServer = vtEvents.filter(e =>
    !fetchedUids.has(e.externalId) && e.startAt >= rangeStart && e.startAt <= rangeEnd);

  const syncedAt = new Date();
  const rows = events
    .filter(ev => !vtUids.has(ev.externalId))
    .map(ev => ({
      sourceId:           source.id,
      userId:             source.userId,
      externalId:         ev.externalId,
      title:              ev.title,
      startAt:            ev.startAt,
      endAt:              ev.endAt,
      allDay:             ev.allDay,
      location:           ev.location,
      description:        ev.description,
      url:                ev.url,
      calendarName:       ev.calendarUrl ? (calNameMap[ev.calendarUrl] || null) : null,
      createdInObelo: false,
      syncedAt,
    }));

  // All-or-nothing, so views never see a half-synced calendar and a failure keeps the old events
  await prisma.$transaction([
    prisma.calendarEvent.deleteMany({ where: { sourceId: source.id, createdInObelo: false } }),
    prisma.calendarEvent.deleteMany({ where: { id: { in: deletedOnServer.map(e => e.id) } } }),
    prisma.calendarEvent.createMany({ data: rows }),
    prisma.calendarSource.update({ where: { id: source.id }, data: { lastSynced: syncedAt } }),
  ]);
  if (deletedOnServer.length > 0) {
    console.log(`[caldav] removed ${deletedOnServer.length} event(s) deleted from server`);
  }

  return rows.length;
}

// ── Sync all sources for a user ───────────────────────────────────────────────

async function syncAllForUser(userId) {
  const sources = await prisma.calendarSource.findMany({
    where: { userId, active: true, type: { in: ['caldav', 'google'] } },
  });
  for (const source of sources) {
    try {
      await syncSource(source);
    } catch (err) {
      console.error(`[caldav] sync failed for source ${source.id}:`, err.message);
    }
  }
}

// ── Create an event via CalDAV (iCloud / standard) ───────────────────────────

async function createEvent(source, { title, startAt, endAt, allDay, location, description, targetCalendarUrl, calendarName }) {
  const creds    = source.credentials;
  const password = creds.passwordEnc ? decrypt(creds.passwordEnc) : creds.password;

  const uid = crypto.randomUUID() + '@obelo';
  const cal = ICalGenerator.default({ name: source.name });
  cal.createEvent({
    uid, start: startAt, end: endAt, allDay,
    summary:     title,
    location:    location    || undefined,
    description: description ? `[vT] ${description}` : '[vT]',
  });
  const icsData = cal.toString();

  const calendarUrl = targetCalendarUrl || creds.calendarUrl || null;

  // The event must reach the server: a local-only copy would be removed by the next sync as
  // "deleted on server", so failures are reported to the user instead of swallowed.
  let targetCal;
  try {
    const client = await makeClient(creds.username, password, creds.serverUrl || 'https://caldav.icloud.com');
    const all = await client.fetchCalendars();
    targetCal = all.find(c => c.url === calendarUrl) || all[0];
    if (!targetCal) throw new Error('no calendars found on the server');
    const res = await client.createCalendarObject({ calendar: targetCal, filename: `${uid}.ics`, iCalString: icsData });
    if (res && res.ok === false) throw new Error(`server returned ${res.status} ${res.statusText || ''}`.trim());
  } catch (err) {
    console.error('[caldav] createEvent push failed:', err.message);
    throw new Error(`Couldn't save the event to ${targetCal?.displayName || source.name}: ${err.message}`);
  }

  const saved = await prisma.calendarEvent.create({
    data: {
      sourceId:           source.id,
      userId:             source.userId,
      externalId:         uid,
      title, startAt, endAt,
      allDay:             allDay || false,
      location:           location    || null,
      description:        description || null,
      calendarName:       calendarName || null,
      createdInObelo: true,
      syncedAt:           new Date(),
    },
  });

  return saved;
}

// ── Create an event via Google Calendar REST API ──────────────────────────────

async function createGoogleEvent(source, { title, startAt, endAt, allDay, location, description, calendarId, calendarName }) {
  const accessToken = await getGoogleAccessToken(source);

  const eventBody = {
    summary:     title,
    location:    location || undefined,
    description: description ? `[vT] ${description}` : '[vT]',
    start: allDay
      ? { date: startAt.toISOString().split('T')[0] }
      : { dateTime: startAt.toISOString() },
    end: allDay
      ? { date: endAt.toISOString().split('T')[0] }
      : { dateTime: endAt.toISOString() },
  };

  const res = await fetch(
    `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events`,
    {
      method: 'POST',
      headers: {
        Authorization:  `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(eventBody),
    }
  );

  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`Google Calendar event creation failed (${res.status}): ${errBody}`);
  }

  const data = await res.json();

  const saved = await prisma.calendarEvent.create({
    data: {
      sourceId:           source.id,
      userId:             source.userId,
      externalId:         data.id,
      title, startAt, endAt,
      allDay:             allDay || false,
      location:           location    || null,
      description:        description || null,
      calendarName:       calendarName || null,
      createdInObelo: true,
      syncedAt:           new Date(),
    },
  });

  return saved;
}

module.exports = {
  discoverCalendars, discoverGoogleCalendars, parseIcsEvents,
  syncSource, syncAllForUser,
  createEvent, createGoogleEvent,
  getGoogleAccessToken,
  encrypt, decrypt,
};
