require('dotenv').config();
const { PrismaClient } = require('@prisma/client');
const { recalcStreak } = require('../src/services/routineStreaks');
const prisma = new PrismaClient();

function todayUTC() {
  const now = new Date();
  return now.toISOString().split('T')[0];
}

async function main() {
  const today = todayUTC();
  const routines = await prisma.routine.findMany();
  console.log(`Recalculating streaks for ${routines.length} routines as of ${today}...`);
  for (const r of routines) {
    const old = r.streakCurrent;
    const updated = await recalcStreak(r, today);
    console.log(`  ${r.title}: ${old} → ${updated}`);
  }
  console.log('Done.');
  await prisma.$disconnect();
}

main().catch(e => { console.error(e); process.exit(1); });
