// What each id in a route's path stands for, shared by the access-control and escaping tests.
// The FIRST match wins, so keep specific patterns first.
// "owned child" parameters are the ones checked with the person's OWN parent and someone else's child.
const KINDS = [
  [/^\/(api\/v1\/)?tasks\/:id\/subtasks\/:sid/, { id: 'task', sid: 'subtask' }],
  [/^\/(api\/v1\/)?tasks\/:id/, { id: 'task' }],
  [/^\/(api\/v1\/)?reminders\/:id/, { id: 'reminder' }],
  [/^\/(api\/v1\/)?routines\/:id/, { id: 'routine' }],
  [/^\/(api\/v1\/)?notes\/:id\/attachments\/:aid/, { id: 'note', aid: 'attachment' }],
  [/^\/notes\/:id\/attachments\/:filename/, { id: 'note', filename: 'attachmentFile' }],
  [/^\/(api\/v1\/)?notes\/:id\/thoughts\/:tid/, { id: 'note', tid: 'thought' }],
  [/^\/notes\/workspace\/folders\/:id/, { id: 'folder' }],
  [/^\/notes\/workspace\/notes\/:id/, { id: 'note' }],
  [/^\/notes\/workspace\/:id/, { id: 'note' }],
  [/^\/api\/v1\/folders\/:id/, { id: 'folder' }],
  [/^\/(api\/v1\/)?notes\/:id/, { id: 'note' }],
  [/^\/(api\/v1\/)?lists\/:id\/(share|unshare)\/:userId/, { id: 'list', userId: 'sharedUser' }],
  [/^\/(api\/v1\/)?lists\/:id\/items\/:itemId/, { id: 'list', itemId: 'listItem' }],
  [/^\/(api\/v1\/)?lists\/:id/, { id: 'list' }],
  [/^\/(api\/v1\/)?bookmarks\/:id/, { id: 'bookmark' }],
  [/^\/(api\/v1\/)?calendar\/events\/:id/, { id: 'event' }],
  [/^\/(api\/v1\/)?calendar\/sources\/:id/, { id: 'source' }],
  [/^\/(api\/v1\/)?calendar\/local(-calendars)?\/:id\/members\/:userId/, { id: 'localCalendar', userId: 'calendarMember' }],
  [/^\/(api\/v1\/)?calendar\/local(-calendars)?\/:id/, { id: 'localCalendar' }],
  [/^\/(api\/v1\/)?capture\/:id/, { id: 'draft' }],
  // A template is kept in its owner's settings (user.preferences.noteTemplates), not in a table
  [/^\/(api\/v1\/|settings\/)note-templates\/:id/, { id: 'noteTemplate' }],
  [/^\/(api\/v1\/)?settings\/api-tokens\/:id/, { id: 'apiToken' }],
  [/^\/(api\/v1\/)?(settings\/)?sessions\/:key/, { key: 'sessionKey' }],
  [/^\/admin\/users\/:id/, { id: 'user' }],
];
// Ids that are not something one person owns. Each needs a reason.
const EXEMPT = [
  [/^\/auth\/password\/:token/, 'a one-time link is the credential itself (see links-and-codes.test.js)'],
  [/^\/(api\/v1\/)?settings\/export\/:name/, ':name is a kind of export, not an id; it only ever exports your own data (tested below)'],
];

const kindsFor = (route) => KINDS.find(([re]) => re.test(route.path))?.[1];
const exempt = (route) => EXEMPT.some(([re]) => re.test(route.path));

module.exports = { KINDS, EXEMPT, kindsFor, exempt };
