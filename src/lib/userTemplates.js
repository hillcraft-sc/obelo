// A person's note templates. They are kept with their other settings (user.preferences.noteTemplates),
// so there is no table. Until they change anything they see the starters (config/noteTemplates.js);
// the first change copies the starters into their own list and applies the change, so a deleted
// starter stays deleted. The functions that change a list are pure: they take the preferences object
// and return a new one (or an error), and the routes save it.

const crypto = require('crypto');
const prisma = require('./prisma');
const { STARTERS, templateTitle } = require('../config/noteTemplates');

const TYPES = ['note', 'journal', 'quote'];
const LIMITS = { count: 20, label: 60, title: 120, content: 20000 };

function starterList() {
  return STARTERS.map((t) => ({
    id: t.key, label: t.label, type: t.type, title: t.title || '', dateTitle: !!t.dateTitle, content: t.content,
  }));
}

// The saved list, or the starters when the person has not changed anything yet
function listFrom(prefs) {
  const saved = prefs && prefs.noteTemplates;
  return Array.isArray(saved) ? saved : starterList();
}

// Cleans what the person typed. Returns { value } or { error }. `partial` allows leaving fields out (edits).
function clean(input, { partial = false } = {}) {
  const src = input || {};
  const out = {};
  if (!partial || src.label !== undefined) {
    const label = typeof src.label === 'string' ? src.label.trim() : '';
    if (!label) return { error: 'Give the template a name.' };
    if (label.length > LIMITS.label) return { error: `The name can be at most ${LIMITS.label} characters.` };
    out.label = label;
  }
  if (!partial || src.type !== undefined) {
    const type = src.type === undefined || src.type === '' ? 'note' : src.type;
    if (!TYPES.includes(type)) return { error: 'The type must be note, journal or quote.' };
    out.type = type;
  }
  if (!partial || src.title !== undefined) {
    const title = src.title === undefined || src.title === null ? '' : src.title;
    if (typeof title !== 'string') return { error: 'The starting title must be text.' };
    if (title.length > LIMITS.title) return { error: `The starting title can be at most ${LIMITS.title} characters.` };
    out.title = title;
  }
  if (!partial || src.dateTitle !== undefined) out.dateTitle = src.dateTitle === true || src.dateTitle === 'true' || src.dateTitle === 'on';
  if (!partial || src.content !== undefined) {
    const content = src.content === undefined || src.content === null ? '' : src.content;
    if (typeof content !== 'string') return { error: 'The starting text must be text.' };
    if (content.length > LIMITS.content) return { error: `The starting text can be at most ${LIMITS.content} characters.` };
    out.content = content;
  }
  return { value: out };
}

function newId() { return 't_' + crypto.randomBytes(6).toString('hex'); }

function withCreated(prefs, input, makeId = newId) {
  const list = listFrom(prefs);
  if (list.length >= LIMITS.count) return { error: `You can have at most ${LIMITS.count} templates. Delete one first.` };
  const { value, error } = clean(input);
  if (error) return { error };
  const template = { id: makeId(), dateTitle: false, ...value };
  return { prefs: { ...(prefs || {}), noteTemplates: [...list, template] }, template };
}

function withUpdated(prefs, id, input) {
  const list = listFrom(prefs);
  const i = list.findIndex((t) => t.id === id);
  if (i === -1) return { notFound: true };
  const { value, error } = clean(input, { partial: true });
  if (error) return { error };
  const template = { ...list[i], ...value };
  const next = list.slice();
  next[i] = template;
  return { prefs: { ...(prefs || {}), noteTemplates: next }, template };
}

function withRemoved(prefs, id) {
  const list = listFrom(prefs);
  if (!list.some((t) => t.id === id)) return { notFound: true };
  return { prefs: { ...(prefs || {}), noteTemplates: list.filter((t) => t.id !== id) } };
}

// The list as the apps and the pages use it. `startTitle` is the title a new note gets (a template with
// "use today's date" is titled with the date in the person's time zone); `title` is what they typed.
function forUser(user) {
  const timeZone = (user && user.timezone) || 'America/New_York';
  return listFrom(user && user.preferences).map((t) => ({ ...t, startTitle: templateTitle(t, timeZone) }));
}

function findFor(user, id) {
  return forUser(user).find((t) => t.id === id) || null;
}

// Reads the person's current settings, applies `change(prefs)` and saves what it returns.
// `change` returns { prefs, ...rest } to save, or { error } / { notFound } to stop. Resolves to the same object.
async function mutate(userId, change) {
  const row = await prisma.user.findUnique({ where: { id: userId }, select: { preferences: true } });
  const result = change(row ? row.preferences || {} : {});
  if (result.prefs) await prisma.user.update({ where: { id: userId }, data: { preferences: result.prefs } });
  return result;
}

module.exports = { TYPES, LIMITS, starterList, listFrom, clean, withCreated, withUpdated, withRemoved, forUser, findFor, mutate };
