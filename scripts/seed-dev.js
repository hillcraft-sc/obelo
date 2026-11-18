// Fills a LOCAL development database with a demo user and sample data, for trying the web app or
// the iOS app in the simulator. Refuses to run unless NODE_ENV=development.
//
//   NODE_ENV=development DATABASE_URL=postgresql://…/obelo_dev node scripts/seed-dev.js
//
// Then sign the app in with DEV_APP_LOGIN_USER=demo (see ios/README.md).

require('dotenv').config();
const prisma = require('../src/lib/prisma');

if (process.env.NODE_ENV !== 'development') {
  console.error('Refusing to seed: NODE_ENV is not "development".');
  process.exit(1);
}

const TZ = 'America/New_York';
const today = new Date().toLocaleDateString('en-CA', { timeZone: TZ });
const day = (offset) => new Date(new Date(today + 'T00:00:00.000Z').getTime() + offset * 86400000);

async function main() {
  const existing = await prisma.user.findUnique({ where: { username: 'demo' } });
  if (existing) await prisma.user.delete({ where: { id: existing.id } });

  const user = await prisma.user.create({
    data: { username: 'demo', displayName: 'Demo User', email: 'demo@example.com', role: 'admin', timezone: TZ, preferences: { theme: 'dark' } },
  });
  const userId = user.id;

  await prisma.task.createMany({
    data: [
      { userId, title: 'Finish quarterly report', status: 'today', priority: 'high', dueDate: day(0), dueTime: '17:00', tags: ['work'] },
      { userId, title: 'Review pull requests', status: 'today', priority: 'medium', tags: ['work'] },
      { userId, title: 'Book dentist appointment', status: 'inbox', priority: 'low', dueDate: day(-2), tags: ['health'] },
      { userId, title: 'Renew car registration', status: 'inbox', priority: 'medium', dueDate: day(3) },
      { userId, title: 'Plan weekend hike', status: 'inbox', priority: 'none', tags: ['personal'] },
      { userId, title: 'Water the plants', status: 'inbox', priority: 'none', dueDate: day(1), recurring: true, recurRule: 'weekly' },
      { userId, title: 'Clean out the garage', status: 'in-progress', priority: 'low', dueDate: day(5) },
      { userId, title: 'Send thank-you notes', status: 'done', priority: 'none', completedAt: new Date() },
    ],
  });
  const parent = await prisma.task.findFirst({ where: { userId, title: 'Finish quarterly report' } });
  await prisma.task.createMany({
    data: [
      { userId, parentId: parent.id, title: 'Pull revenue numbers', status: 'done', completedAt: new Date() },
      { userId, parentId: parent.id, title: 'Write summary', status: 'inbox' },
    ],
  });

  await prisma.reminder.createMany({
    data: [
      { userId, title: 'Call mom', dueDate: day(0), dueTime: '18:30', priority: 'medium' },
      { userId, title: 'Pay electricity bill', dueDate: day(-1), dueTime: '09:00', priority: 'high', tags: ['bills'] },
      { userId, title: 'Pick up dry cleaning', dueDate: day(2), dueTime: '12:00' },
      { userId, title: 'Take vitamins', dueDate: day(1), dueTime: '08:00', recurring: true, recurRule: 'daily', tags: ['health'] },
    ],
  });

  const routines = [
    { title: 'Morning stretch', timeOfDay: 'morning', frequency: 'daily', tags: ['health'] },
    { title: 'Read 20 pages', timeOfDay: 'evening', frequency: 'daily' },
    { title: 'Inbox zero', timeOfDay: 'afternoon', frequency: 'weekdays', tags: ['work'] },
    { title: 'Meditate', timeOfDay: 'anytime', frequency: 'daily', durationDays: 30, startDate: day(-12) },
  ];
  for (const r of routines) {
    const routine = await prisma.routine.create({ data: { userId, ...r } });
    const done = [];
    for (let i = 1; i <= 20; i++) if ((i * 7 + routine.id) % 5 !== 0) done.push(day(-i));
    await prisma.routineCompletion.createMany({
      data: done.map((d) => ({ userId, routineId: routine.id, completedDate: d, completedAt: d })),
    });
  }
  const { recalcStreak } = require('../src/services/routineStreaks');
  for (const r of await prisma.routine.findMany({ where: { userId } })) await recalcStreak(r, today);

  await prisma.note.createMany({
    data: [
      { userId, title: 'Project ideas', pinned: true, tags: ['ideas'], content: '## App ideas\n\n- A **habit tracker** with streaks\n- Recipe scaler\n- [ ] Sketch the dashboard\n- [x] Pick a name\n\n> Ship small, ship often.' },
      { userId, type: 'journal', title: 'Tuesday reflections', content: 'Good day overall. Went for a run in the morning and finally finished the report draft.', createdAt: day(-40), updatedAt: day(-40) },
      { userId, type: 'quote', title: 'On time', author: 'Oliver Burkeman', source: 'Four Thousand Weeks', content: 'The average human lifespan is absurdly, terrifyingly, insultingly short.' },
      { userId, title: 'Wi-Fi setup notes', tags: ['home'], content: 'Router is in the hall closet. Guest network: `garden-guest`.', flaggedForReview: true, reviewDate: day(0) },
    ],
  });

  await prisma.list.create({
    data: {
      userId, title: 'Groceries',
      items: { create: ['Milk', 'Eggs', 'Sourdough bread', 'Pasta', 'Tomatoes'].map((text, i) => ({ text, position: i, checked: i === 1 })) },
    },
  });
  await prisma.list.create({
    data: { userId, title: 'Packing for trip', items: { create: ['Passport', 'Charger', 'Adapter'].map((text, i) => ({ text, position: i })) } },
  });

  await prisma.bookmark.createMany({
    data: [
      { userId, url: 'https://developer.apple.com/swift/', title: 'Swift', description: 'The Swift language', tags: ['dev'] },
      { userId, url: 'https://www.postgresql.org/docs/', title: 'PostgreSQL docs', tags: ['dev'] },
      { userId, url: 'https://www.seriouseats.com/', title: 'Serious Eats', description: 'Recipes', tags: ['food'] },
    ],
  });

  const cal = await prisma.localCalendar.create({ data: { userId, name: 'Personal', color: '#10b981' } });
  const at = (offset, hh, mm) => {
    // hh:mm New York time (EDT, UTC-4, close enough for demo data)
    const d = day(offset);
    return new Date(d.getTime() + ((hh + 4) * 60 + mm) * 60000);
  };
  await prisma.calendarEvent.createMany({
    data: [
      { userId, localCalendarId: cal.id, title: 'Team standup', startAt: at(0, 9, 30), endAt: at(0, 9, 45), createdInObelo: true },
      { userId, localCalendarId: cal.id, title: 'Lunch with Sam', startAt: at(0, 12, 30), endAt: at(0, 13, 30), location: 'Corner Café', createdInObelo: true },
      { userId, localCalendarId: cal.id, title: 'Dentist', startAt: at(2, 15, 0), endAt: at(2, 16, 0), createdInObelo: true },
      { userId, localCalendarId: cal.id, title: 'Holiday', allDay: true, startAt: day(4), endAt: day(5), createdInObelo: true },
    ],
  });

  // Three months of completed tasks and reminders with a spread of early/on-time/late
  // finishes and times of day, so Analytics has something to chart
  const lateness = [-2, -1, 0, 0, 0, 0, 0, 1, 2, 3, 5, 9];
  const hours = [7, 8, 9, 10, 11, 13, 14, 15, 16, 17, 19, 21];
  const done = [];
  for (let i = 0; i < 90; i++) {
    const dueOffset = -Math.floor(i * 1.0) - 1;
    const late = lateness[(i * 7) % lateness.length];
    const hour = hours[(i * 5) % hours.length];
    const completedAt = new Date(day(dueOffset + late).getTime() + (hour + 4) * 3600000 + ((i * 13) % 60) * 60000);
    if (completedAt > new Date()) continue;
    done.push({
      userId, title: `Past task ${i + 1}`, status: 'done', completedAt,
      priority: ['high', 'medium', 'low', 'none'][i % 4],
      dueDate: i % 6 === 5 ? null : day(dueOffset),
      dueTime: i % 3 === 0 ? `${String(hour - (late === 0 ? 0 : 1)).padStart(2, '0')}:00` : null,
    });
  }
  await prisma.task.createMany({ data: done });
  await prisma.reminder.createMany({
    data: done.filter((_, i) => i % 3 === 0).map((t, i) => ({
      userId, title: `Past reminder ${i + 1}`, completed: true, completedAt: t.completedAt,
      dueDate: t.dueDate || day(-1), dueTime: '09:00', priority: t.priority,
    })),
  });

  console.log(`Seeded demo user @demo (id ${userId})`);
}

main().catch((err) => { console.error(err); process.exit(1); }).finally(() => prisma.$disconnect());
