// Managing calendar sources and your own shared calendars. One set of functions for the web's
// Calendar Sources page (src/routes/calendar.js) and the apps (src/routes/api.js), so both behave
// the same. Every function takes the signed-in user's id and only ever touches that user's rows
// (or, for a shared calendar, the owner's). Credentials never leave this file: serialize() is the
// only way a source is shown to a client, and it leaves them out.
const prisma = require('./prisma');
const caldav = require('../services/caldavService');
const { getShareableUsers } = require('./users');

class SourceError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

const HEX = /^#[0-9a-fA-F]{6}$/;
const colorOr = (value, fallback = '#6366f1') => (HEX.test(String(value || '')) ? String(value) : fallback);
const detailOf = (err) => err.cause?.message || err.message;

async function ownSource(userId, id) {
  const n = Number(id);
  const source = Number.isInteger(n) ? await prisma.calendarSource.findFirst({ where: { id: n, userId } }) : null;
  if (!source) throw new SourceError(404, 'Not found');
  return source;
}

async function ownLocal(userId, id) {
  const n = Number(id);
  const lc = Number.isInteger(n) ? await prisma.localCalendar.findFirst({ where: { id: n, userId } }) : null;
  if (!lc) throw new SourceError(404, 'Not found');
  return lc;
}

// ── Reading ───────────────────────────────────────────────────────────────────

function serialize(src) {
  const creds = src.credentials || {};
  const discovered = creds.discoveredCalendars || [];
  const selected = creds.selectedCalendarUrls || [];
  return {
    id: src.id,
    type: src.type,
    name: src.name,
    color: src.color,
    active: src.active,
    lastSynced: src.lastSynced,
    isFamily: !!src.isFamilyCalendar,
    // No selection saved means "all of them"
    calendars: discovered.map((c) => ({
      url: c.url,
      name: c.displayName || c.url,
      color: c.color || null,
      selected: selected.length === 0 || selected.includes(c.url),
      isFamily: !!src.isFamilyCalendar && creds.familyCalendarUrl === c.url,
    })),
  };
}

async function overview(userId) {
  const [sources, local, shareableUsers] = await Promise.all([
    prisma.calendarSource.findMany({ where: { userId }, orderBy: { name: 'asc' } }),
    prisma.localCalendar.findMany({
      where: { userId },
      include: { members: { include: { user: { select: { id: true, username: true, displayName: true } } }, orderBy: { addedAt: 'asc' } } },
      orderBy: { name: 'asc' },
    }),
    getShareableUsers(userId),
  ]);
  return {
    sources: sources.map(serialize),
    localCalendars: local.map((lc) => ({
      id: lc.id, name: lc.name, color: lc.color,
      members: lc.members.map((m) => ({ userId: m.user.id, username: m.user.username, displayName: m.user.displayName, canEdit: m.canEdit })),
    })),
    shareableUsers,
  };
}

// ── CalDAV accounts ───────────────────────────────────────────────────────────

async function connectCaldav(userId, { name, provider, username, password, serverUrl, calendarHomeUrl, color } = {}) {
  const defaultNames = { apple: 'iCloud Calendar', google: 'Google Calendar', other: username };
  const displayName = String(name || '').trim() || defaultNames[provider] || username;
  if (!username || !password) throw new SourceError(400, 'Username and password are required.');

  const server = String(serverUrl || '').trim() || 'https://caldav.icloud.com';
  const homeUrl = String(calendarHomeUrl || '').trim() || null;

  let discovered;
  try {
    discovered = await caldav.discoverCalendars(username, password, server, homeUrl);
  } catch (err) {
    throw new SourceError(422, `Could not connect: ${detailOf(err)}`);
  }

  const source = await prisma.calendarSource.create({
    data: {
      userId, type: 'caldav', name: displayName, color: colorOr(color), active: true,
      credentials: {
        username, passwordEnc: caldav.encrypt(password),
        serverUrl: server, calendarHomeUrl: homeUrl, discoveredCalendars: discovered,
      },
    },
  });

  let synced = null, syncError = null;
  try { synced = await caldav.syncSource(source); } catch (err) { syncError = `Initial sync failed: ${detailOf(err)}`; console.error('[caldav] initial sync failed:', detailOf(err)); }
  return { source: serialize(await prisma.calendarSource.findUnique({ where: { id: source.id } })), found: discovered.length, synced, syncError };
}

// Forces a sync and reports the result
async function syncNow(userId, id) {
  const source = await ownSource(userId, id);
  try {
    const count = await caldav.syncSource(source);
    return { count, name: source.name };
  } catch (err) {
    console.error('[caldav] sync error:', detailOf(err));
    throw new SourceError(422, `Sync failed: ${detailOf(err)}`);
  }
}

async function setSourceColor(userId, id, color) {
  const source = await ownSource(userId, id);
  await prisma.calendarSource.updateMany({ where: { id: source.id, userId }, data: { color: colorOr(color) } });
}

async function removeSource(userId, id) {
  const source = await ownSource(userId, id);
  await prisma.calendarEvent.deleteMany({ where: { sourceId: source.id, userId } });
  await prisma.calendarSource.deleteMany({ where: { id: source.id, userId } });
}

// Which of the account's calendars to sync (an empty list means all), then syncs again
async function setSelectedCalendars(userId, id, urls) {
  const source = await ownSource(userId, id);
  const creds = source.credentials || {};
  const known = new Set((creds.discoveredCalendars || []).map((c) => c.url));
  const selected = (Array.isArray(urls) ? urls : []).map(String).filter((u) => known.has(u));
  await prisma.calendarSource.updateMany({ where: { id: source.id, userId }, data: { credentials: { ...creds, selectedCalendarUrls: selected } } });
  const updated = await prisma.calendarSource.findUnique({ where: { id: source.id } });
  try {
    return { selected: selected.length, count: await caldav.syncSource(updated), syncError: null };
  } catch (err) {
    return { selected: selected.length, count: null, syncError: `Selection saved but sync failed: ${detailOf(err)}` };
  }
}

// The family calendar: one of the account's calendars, or none (url null)
async function setFamilyCalendar(userId, id, url) {
  const source = await ownSource(userId, id);
  const creds = source.credentials || {};
  if (url) {
    if (!(creds.discoveredCalendars || []).some((c) => c.url === url)) throw new SourceError(400, 'That calendar is not in this account.');
    await prisma.calendarSource.updateMany({ where: { id: source.id, userId }, data: { isFamilyCalendar: true, credentials: { ...creds, familyCalendarUrl: url } } });
  } else {
    const { familyCalendarUrl, ...rest } = creds; // eslint-disable-line no-unused-vars
    await prisma.calendarSource.updateMany({ where: { id: source.id, userId }, data: { isFamilyCalendar: false, credentials: rest } });
  }
}

async function setDefaultTarget(userId, target) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  await prisma.user.update({ where: { id: userId }, data: { preferences: { ...(user.preferences || {}), defaultCalendarTarget: target || null } } });
}

// ── Your own (local, shareable) calendars ────────────────────────────────────

async function createLocal(userId, { name, color }) {
  const clean = String(name || '').trim();
  if (!clean) throw new SourceError(400, 'Name is required.');
  const lc = await prisma.localCalendar.create({ data: { userId, name: clean, color: colorOr(color) } });
  return lc.id;
}

async function updateLocal(userId, id, { name, color }) {
  const lc = await ownLocal(userId, id);
  await prisma.localCalendar.updateMany({
    where: { id: lc.id, userId },
    data: { name: String(name || '').trim() || lc.name, color: colorOr(color, lc.color) },
  });
}

// The events stay (onDelete: SetNull on their calendar)
async function deleteLocal(userId, id) {
  const lc = await ownLocal(userId, id);
  await prisma.localCalendar.deleteMany({ where: { id: lc.id, userId } });
}

async function addMember(userId, id, username) {
  const lc = await ownLocal(userId, id);
  const target = await prisma.user.findFirst({ where: { username: String(username || '').trim() } });
  if (!target) throw new SourceError(404, `User "${String(username || '').trim()}" not found.`);
  if (target.id === userId) throw new SourceError(400, 'You already have access as the owner.');
  await prisma.localCalendarMember.upsert({
    where: { calendarId_userId: { calendarId: lc.id, userId: target.id } },
    create: { calendarId: lc.id, userId: target.id, canEdit: true },
    update: {},
  });
  return { calendar: lc.name, person: target.displayName || target.username };
}

async function removeMember(userId, id, memberUserId) {
  const lc = await ownLocal(userId, id);
  await prisma.localCalendarMember.deleteMany({ where: { calendarId: lc.id, userId: Number(memberUserId) || 0 } });
}

module.exports = {
  SourceError, overview, serialize, colorOr,
  connectCaldav, syncNow, setSourceColor, removeSource, setSelectedCalendars, setFamilyCalendar, setDefaultTarget,
  createLocal, updateLocal, deleteLocal, addMember, removeMember,
};
