const prisma = require('./prisma');

function parseTags(raw) {
  if (!raw) return [];
  return [...new Set(raw.split(',').map(t => t.trim().toLowerCase()).filter(Boolean))];
}

// Returns all distinct tags for a user — union of item tags + manager-created tags in prefs.userTags
async function getAllUserTags(userId) {
  const [tasks, notes, reminders, routines, bookmarks, user] = await Promise.all([
    prisma.task.findMany({ where: { userId }, select: { tags: true } }),
    prisma.note.findMany({ where: { userId }, select: { tags: true } }),
    prisma.reminder.findMany({ where: { userId }, select: { tags: true } }),
    prisma.routine.findMany({ where: { userId }, select: { tags: true } }),
    prisma.bookmark.findMany({ where: { userId }, select: { tags: true } }),
    prisma.user.findUnique({ where: { id: userId }, select: { preferences: true } }),
  ]);
  const prefTags = Array.isArray(user?.preferences?.userTags) ? user.preferences.userTags : [];
  return [...new Set([
    ...prefTags,
    ...[...tasks, ...notes, ...reminders, ...routines, ...bookmarks].flatMap(i => i.tags),
  ])].sort();
}

// Returns { tagName: count } across all item models (manager-created tags with no items show as 0)
async function getTagUsageCounts(userId) {
  const [tasks, notes, reminders, routines, bookmarks, user] = await Promise.all([
    prisma.task.findMany({ where: { userId }, select: { tags: true } }),
    prisma.note.findMany({ where: { userId }, select: { tags: true } }),
    prisma.reminder.findMany({ where: { userId }, select: { tags: true } }),
    prisma.routine.findMany({ where: { userId }, select: { tags: true } }),
    prisma.bookmark.findMany({ where: { userId }, select: { tags: true } }),
    prisma.user.findUnique({ where: { id: userId }, select: { preferences: true } }),
  ]);
  const counts = {};
  for (const item of [...tasks, ...notes, ...reminders, ...routines, ...bookmarks]) {
    for (const tag of item.tags) {
      counts[tag] = (counts[tag] || 0) + 1;
    }
  }
  // Ensure manager-created tags appear even with count 0
  const prefTags = Array.isArray(user?.preferences?.userTags) ? user.preferences.userTags : [];
  for (const tag of prefTags) {
    if (!(tag in counts)) counts[tag] = 0;
  }
  return counts;
}

async function createTag(userId, tagName) {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { preferences: true } });
  const prefs = user?.preferences || {};
  const existing = Array.isArray(prefs.userTags) ? prefs.userTags : [];
  if (!existing.includes(tagName)) {
    await prisma.user.update({
      where: { id: userId },
      data: { preferences: { ...prefs, userTags: [...existing, tagName].sort() } },
    });
  }
}

async function renameTag(userId, oldName, newName) {
  await Promise.all([
    prisma.$executeRaw`UPDATE tasks SET tags = array_replace(tags, ${oldName}, ${newName}) WHERE ${oldName} = ANY(tags) AND user_id = ${userId}`,
    prisma.$executeRaw`UPDATE notes SET tags = array_replace(tags, ${oldName}, ${newName}) WHERE ${oldName} = ANY(tags) AND user_id = ${userId}`,
    prisma.$executeRaw`UPDATE reminders SET tags = array_replace(tags, ${oldName}, ${newName}) WHERE ${oldName} = ANY(tags) AND user_id = ${userId}`,
    prisma.$executeRaw`UPDATE routines SET tags = array_replace(tags, ${oldName}, ${newName}) WHERE ${oldName} = ANY(tags) AND user_id = ${userId}`,
    prisma.$executeRaw`UPDATE bookmarks SET tags = array_replace(tags, ${oldName}, ${newName}) WHERE ${oldName} = ANY(tags) AND user_id = ${userId}`,
  ]);
  // Update prefs.userTags if present
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { preferences: true } });
  const prefs = user?.preferences || {};
  const prefTags = Array.isArray(prefs.userTags) ? prefs.userTags : [];
  if (prefTags.includes(oldName)) {
    const updated = prefTags.filter(t => t !== oldName);
    if (!updated.includes(newName)) updated.push(newName);
    await prisma.user.update({ where: { id: userId }, data: { preferences: { ...prefs, userTags: updated.sort() } } });
  }
}

async function deleteTag(userId, tagName) {
  await Promise.all([
    prisma.$executeRaw`UPDATE tasks SET tags = array_remove(tags, ${tagName}) WHERE ${tagName} = ANY(tags) AND user_id = ${userId}`,
    prisma.$executeRaw`UPDATE notes SET tags = array_remove(tags, ${tagName}) WHERE ${tagName} = ANY(tags) AND user_id = ${userId}`,
    prisma.$executeRaw`UPDATE reminders SET tags = array_remove(tags, ${tagName}) WHERE ${tagName} = ANY(tags) AND user_id = ${userId}`,
    prisma.$executeRaw`UPDATE routines SET tags = array_remove(tags, ${tagName}) WHERE ${tagName} = ANY(tags) AND user_id = ${userId}`,
    prisma.$executeRaw`UPDATE bookmarks SET tags = array_remove(tags, ${tagName}) WHERE ${tagName} = ANY(tags) AND user_id = ${userId}`,
  ]);
  // Remove from prefs.userTags if present
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { preferences: true } });
  const prefs = user?.preferences || {};
  const prefTags = Array.isArray(prefs.userTags) ? prefs.userTags : [];
  if (prefTags.includes(tagName)) {
    await prisma.user.update({
      where: { id: userId },
      data: { preferences: { ...prefs, userTags: prefTags.filter(t => t !== tagName) } },
    });
  }
}

module.exports = { parseTags, getAllUserTags, getTagUsageCounts, createTag, renameTag, deleteTag };
