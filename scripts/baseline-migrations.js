// Runs before `prisma migrate deploy` on container start (docker-entrypoint.sh).
//
// prisma/migrations has two "init" migrations: 20260616114525_init is an early, incomplete
// schema that was superseded by 20260618000000_init. Neither may run on top of the other.
//
//   - Migration history exists → nothing to do (normal case for every existing install).
//   - Empty database (new install) → mark the stale early init as applied so deploy starts
//     from the complete 20260618000000_init.
//   - Tables exist but no migration history (install created with `prisma db push` before
//     migrations were adopted) → mark both inits as applied; later migrations then run.
require('dotenv').config();
const { execFileSync } = require('child_process');
const { PrismaClient } = require('@prisma/client');

const STALE_INIT    = '20260616114525_init';
const BASELINE_INIT = '20260618000000_init';

function markApplied(name) {
  execFileSync('npx', ['prisma', 'migrate', 'resolve', '--applied', name], { stdio: 'inherit' });
}

async function main() {
  const prisma = new PrismaClient();
  let hasHistory, hasTables;
  try {
    const [row] = await prisma.$queryRaw`
      SELECT to_regclass('public._prisma_migrations') IS NOT NULL AS history,
             to_regclass('public.users') IS NOT NULL            AS tables`;
    hasHistory = row.history;
    hasTables  = row.tables;
  } finally {
    await prisma.$disconnect();
  }

  if (hasHistory) {
    console.log('[obelo] Migration history found — no baseline needed.');
  } else if (!hasTables) {
    console.log('[obelo] Empty database — skipping superseded early init migration.');
    markApplied(STALE_INIT);
  } else {
    console.log('[obelo] Existing tables without migration history — baselining.');
    markApplied(STALE_INIT);
    markApplied(BASELINE_INIT);
  }
}

main().catch(err => {
  console.error('[obelo] Migration baseline failed:', err.message);
  process.exit(1);
});
