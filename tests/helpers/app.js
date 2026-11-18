// Starts the real app on a free port, and gives tests a way to empty the database.
require('./env');
const prisma = require('../../src/lib/prisma');

let server;

async function startApp() {
  const app = require('../../src/app');
  await new Promise((resolve) => { server = app.listen(0, '127.0.0.1', resolve); });
  return { base: `http://127.0.0.1:${server.address().port}` };
}

// Empties every table (not the migration history). The sessions table is created by the app.
// The app writes to the database a moment after it answers (log lines, session details), and
// that can deadlock with TRUNCATE, so a deadlock is retried.
async function resetDb() {
  for (let attempt = 1; ; attempt++) {
    try {
      const rows = await prisma.$queryRaw`
        SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> '_prisma_migrations'`;
      if (!rows.length) return;
      const list = rows.map((r) => `"${r.tablename}"`).join(', ');
      await prisma.$executeRawUnsafe(`TRUNCATE TABLE ${list} RESTART IDENTITY CASCADE`);
      return;
    } catch (err) {
      if (attempt >= 8 || !/deadlock|40P01/.test(String(err.message))) throw err;
      await new Promise((r) => setTimeout(r, 100 * attempt));
    }
  }
}

module.exports = { startApp, resetDb, prisma };
