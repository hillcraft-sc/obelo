// Locked out? Sets a new password for an account, from the server's command line.
//   docker compose exec app node scripts/set-password.js <username or email>
// Changes data, so it asks for the password twice and signs that account out everywhere.
require('dotenv').config();
const { PrismaClient } = require('@prisma/client');
const readline = require('readline');
const passwords = require('../src/lib/passwords');
const prisma = new PrismaClient();

// One readline for both prompts; what is typed is not echoed when a terminal is attached
const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: process.stdin.isTTY });
const lines = [];
let waiting = null;
rl.on('line', (l) => (waiting ? waiting(l) : lines.push(l)));
let muted = false;
rl._writeToOutput = (str) => { if (!muted) rl.output.write(str); };

function promptHidden(question) {
  process.stdout.write(question);
  muted = true;
  return new Promise((resolve) => {
    const done = (l) => { waiting = null; muted = false; process.stdout.write('\n'); resolve(l); };
    if (lines.length) done(lines.shift()); else waiting = done;
    rl.once('close', () => waiting && done(''));
  });
}

async function main() {
  const identifier = process.argv[2];
  if (!identifier) {
    console.error('Usage: node scripts/set-password.js <username or email>');
    process.exit(1);
  }
  const user = await prisma.user.findFirst({
    where: { OR: [
      { username: { equals: identifier, mode: 'insensitive' } },
      { email: { equals: identifier, mode: 'insensitive' } },
    ] },
  });
  if (!user) { console.error(`No account for "${identifier}".`); process.exit(1); }

  const pw = await promptHidden(`New password for @${user.username}: `);
  const bad = passwords.checkNewPassword(pw);
  if (bad) { console.error(bad); process.exit(1); }
  if (pw !== await promptHidden('Again: ')) { console.error("The two passwords don't match."); process.exit(1); }

  await prisma.user.update({ where: { id: user.id }, data: { passwordHash: await passwords.hashPassword(pw) } });
  const ended = await prisma.$executeRaw`DELETE FROM sessions WHERE sess->>'userId' = ${String(user.id)}`;
  console.log(`✓ Password set for @${user.username}; signed out of ${ended} session(s).`);
}

main().catch(err => { console.error(err); process.exit(1); }).finally(() => { rl.close(); return prisma.$disconnect(); });
