// One of everything a user can own, for two users, so tests can check who can touch what.
const path = require('path');
const { prisma } = require('../helpers/app');
const uploads = require('../../src/lib/uploads');
const userSessions = require('../../src/lib/userSessions');

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const CONTENT_TABLES = [
  'tasks', 'reminders', 'routines', 'routine_completions', 'routine_streak_history', 'notes', 'note_attachments',
  'note_thoughts', 'folders', 'lists', 'list_items', 'list_shares', 'bookmarks', 'calendar_events', 'calendar_sources',
  'local_calendars', 'local_calendar_members', 'capture_drafts', 'api_tokens',
];

// Empties everything users own, but keeps the users and their sessions
async function resetContent() {
  await prisma.$executeRawUnsafe(`TRUNCATE TABLE ${CONTENT_TABLES.map((t) => `"${t}"`).join(', ')} CASCADE`);
}

// Creates one of each kind for `user`, plus a third user `third` that things are shared with.
// `tag` goes into every title so a leak is easy to spot.
// `otherSid`: the session id to keep OUT of the "another device" key, i.e. the session making the request
async function seed(user, third, tag, { currentSid } = {}) {
  const userId = user.id;
  const task = await prisma.task.create({ data: { userId, title: `${tag} task`, notes: `${tag} notes` } });
  const subtask = await prisma.task.create({ data: { userId, title: `${tag} subtask`, parentId: task.id } });
  const reminder = await prisma.reminder.create({ data: { userId, title: `${tag} reminder` } });
  const routine = await prisma.routine.create({ data: { userId, title: `${tag} routine` } });
  const folder = await prisma.folder.create({ data: { userId, name: `${tag} folder` } });
  const note = await prisma.note.create({ data: { userId, title: `${tag} note`, content: `${tag} body\n- [ ] ${tag} step`, folderId: folder.id, updatedAt: new Date() } });
  const attachmentFile = `${Date.now()}-${tag.replace(/\W/g, '')}.png`;
  await uploads.writeFile(uploads.notePath(note.id, attachmentFile), PNG);
  const attachment = await prisma.noteAttachment.create({ data: { noteId: note.id, filePath: attachmentFile, mimeType: 'image/png' } });
  const thought = await prisma.noteThought.create({ data: { noteId: note.id, userId, content: `${tag} thought` } });
  const list = await prisma.list.create({ data: { userId, title: `${tag} list` } });
  const listItem = await prisma.listItem.create({ data: { listId: list.id, text: `${tag} item` } });
  await prisma.listShare.create({ data: { listId: list.id, userId: third.id } });
  const bookmark = await prisma.bookmark.create({ data: { userId, url: `https://example.com/${tag}`, title: `${tag} bookmark`, updatedAt: new Date() } });
  // One calendar in the account, at the address the access test sends as `url`, so "set the family calendar" is a valid request for the owner
  const source = await prisma.calendarSource.create({ data: { userId, type: 'caldav', name: `${tag} source`, credentials: { discoveredCalendars: [{ url: 'https://example.com/b-was-here', displayName: `${tag} calendar` }] } } });
  const localCalendar = await prisma.localCalendar.create({ data: { userId, name: `${tag} calendar` } });
  await prisma.localCalendarMember.create({ data: { calendarId: localCalendar.id, userId: third.id } });
  const event = await prisma.calendarEvent.create({
    data: { userId, title: `${tag} event`, startAt: new Date('2026-12-01T10:00:00Z'), endAt: new Date('2026-12-01T11:00:00Z'), localCalendarId: localCalendar.id, createdInObelo: true },
  });
  const draft = await prisma.captureDraft.create({ data: { userId, rawInput: `${tag} capture`, aiSuggestion: { type: 'note', title: `${tag} capture`, content: `${tag} capture` } } });
  const apiToken = await prisma.apiToken.create({ data: { userId, tokenHash: `hash-${tag}-${Date.now()}`, label: `${tag} token` } });

  // Note templates live in the person's settings, so seeding one means replacing that list
  const noteTemplate = `t_${tag.replace(/\W/g, '')}`;
  const prefs = (await prisma.user.findUnique({ where: { id: userId }, select: { preferences: true } })).preferences || {};
  await prisma.user.update({ where: { id: userId }, data: { preferences: { ...prefs, noteTemplates: [
    { id: noteTemplate, label: `${tag} template`, type: 'note', title: `${tag} template title`, dateTitle: false, content: `${tag} template text` },
  ] } } });

  const sess = await prisma.$queryRaw`SELECT sid FROM sessions WHERE sess->>'userId' = ${String(userId)}`;
  const other = sess.find((r) => r.sid !== currentSid);
  const sessionKey = other ? userSessions.sessionKey(other.sid) : '0123456789abcdef';

  return {
    task: task.id, subtask: subtask.id, reminder: reminder.id, routine: routine.id, folder: folder.id, note: note.id,
    attachment: attachment.id, attachmentFile, thought: thought.id, list: list.id, listItem: listItem.id,
    sharedUser: third.id, bookmark: bookmark.id, source: source.id, localCalendar: localCalendar.id,
    calendarMember: third.id, event: event.id, draft: draft.id, apiToken: apiToken.id, sessionKey, user: user.id,
    noteTemplate,
  };
}

// Everything `user` owns, as one string, to compare before and after someone else pokes at it
async function snapshot(userId) {
  const own = { where: { userId }, orderBy: { id: 'asc' } };
  const parts = {
    user: await prisma.user.findUnique({ where: { id: userId } }),
    tasks: await prisma.task.findMany(own),
    reminders: await prisma.reminder.findMany(own),
    routines: await prisma.routine.findMany(own),
    routineCompletions: await prisma.routineCompletion.findMany(own),
    folders: await prisma.folder.findMany(own),
    notes: await prisma.note.findMany(own),
    attachments: await prisma.noteAttachment.findMany({ where: { note: { userId } }, orderBy: { id: 'asc' } }),
    thoughts: await prisma.noteThought.findMany({ where: { note: { userId } }, orderBy: { id: 'asc' } }),
    lists: await prisma.list.findMany(own),
    listItems: await prisma.listItem.findMany({ where: { list: { userId } }, orderBy: { id: 'asc' } }),
    listShares: await prisma.listShare.findMany({ where: { list: { userId } }, orderBy: { id: 'asc' } }),
    bookmarks: await prisma.bookmark.findMany(own),
    sources: await prisma.calendarSource.findMany(own),
    localCalendars: await prisma.localCalendar.findMany(own),
    localMembers: await prisma.localCalendarMember.findMany({ where: { calendar: { userId } }, orderBy: { id: 'asc' } }),
    events: await prisma.calendarEvent.findMany(own),
    drafts: await prisma.captureDraft.findMany(own),
    apiTokens: await prisma.apiToken.findMany(own),
    sessions: await prisma.$queryRaw`SELECT count(*)::int AS n FROM sessions WHERE sess->>'userId' = ${String(userId)}`,
  };
  return JSON.stringify(parts);
}

module.exports = { seed, snapshot, resetContent };
