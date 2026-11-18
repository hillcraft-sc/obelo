const prisma = require('./prisma');

// Copy one of your bookmarks to another user. Shared by the web page and /api/v1.
// Returns { status, body } so each caller can answer in its own way.
async function shareBookmarkToUser(userId, bookmarkId, rawUsername) {
  const bookmark = await prisma.bookmark.findFirst({ where: { id: bookmarkId, userId } });
  if (!bookmark) return { status: 404, body: { error: 'Bookmark not found' } };

  const username = String(rawUsername || '').trim().replace(/^@/, '');
  if (!username) return { status: 400, body: { error: 'Username is required' } };

  const target = await prisma.user.findUnique({ where: { username } });
  if (!target) return { status: 404, body: { error: `No user found with username "${username}"` } };
  if (target.id === userId) return { status: 400, body: { error: 'Cannot share with yourself' } };

  const existing = await prisma.bookmark.findFirst({ where: { userId: target.id, url: bookmark.url } });
  if (existing) return { status: 409, body: { error: `@${username} already has this bookmark` } };

  await prisma.bookmark.create({
    data: {
      userId: target.id, url: bookmark.url, title: bookmark.title,
      description: bookmark.description, tags: bookmark.tags,
    },
  });
  return { status: 200, body: { ok: true, message: `Sent to @${target.username}` } };
}

module.exports = { shareBookmarkToUser };
