const prisma = require('./prisma');

// Returns other users a person can share/send items to (everyone except themselves)
async function getShareableUsers(excludeUserId) {
  return prisma.user.findMany({
    where: { id: { not: excludeUserId } },
    select: { id: true, username: true, displayName: true },
    orderBy: { username: 'asc' },
  });
}

module.exports = { getShareableUsers };
