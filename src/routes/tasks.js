const express = require('express');
const prisma = require('../lib/prisma');
const { requireAuth } = require('../middleware/auth');
const { marked } = require('marked');
const xss = require('xss');
const { getAllUserTags, parseTags: parseTagsShared } = require('../lib/tags');
const { byPriority } = require('../lib/priority');
marked.use({ gfm: true, breaks: true });
// Indented checklists render as checklists, not code (issue #2)
const renderMd = (src) => xss(marked(require('../services/checklist').normalize(src)));

const router = express.Router();
router.use(requireAuth);

// ── Constants ───────────────────────────────────────────────────────────────

const STATUSES = ['inbox', 'today', 'in-progress', 'done', 'archived'];
const STATUS_LABELS = { inbox: 'Inbox', today: 'Today', 'in-progress': 'In Progress', done: 'Done', archived: 'Archived' };
const STATUS_CLS = {
  inbox: 'text-gray-400',
  today: 'text-indigo-400',
  'in-progress': 'text-amber-400',
  done: 'text-green-400',
  archived: 'text-gray-600',
};
const PRIORITY_DOT = { none: 'bg-gray-600', low: 'bg-blue-500', medium: 'bg-amber-500', high: 'bg-red-500' };
const PRIORITY_RING = { none: 'border-gray-600', low: 'border-gray-600', medium: 'border-gray-600', high: 'border-gray-600' };
const PRIORITY_ICON = {
  none:   '<span class="w-3.5 h-3.5 shrink-0 inline-block"></span>',
  low:    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-width="2.5" stroke="currentColor" class="w-3.5 h-3.5 text-gray-400 shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 15.75l7.5-7.5 7.5 7.5"/></svg>',
  medium: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-width="2.5" stroke="currentColor" class="w-3.5 h-3.5 text-gray-400 shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l7.5-7.5 7.5 7.5m-15 6l7.5-7.5 7.5 7.5"/></svg>',
  high:   '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke-width="2.5" stroke="currentColor" class="w-3.5 h-3.5 text-gray-400 shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 9l7.5-7.5 7.5 7.5m-15 6l7.5-7.5 7.5 7.5m-15 6l7.5-7.5 7.5 7.5"/></svg>',
};

const SLIPPING_DAYS = 7;
// ── Helpers ─────────────────────────────────────────────────────────────────

const { nextRecurrence } = require('../lib/recurrence');
const parseTags = parseTagsShared;

// Returns { dueDate, dueTime } for the next occurrence, or null if no recurrence applies.
function nextDueDate(task) {
  const next = nextRecurrence(task.dueDate ? new Date(task.dueDate) : null, task.recurRule, task.dueTime);
  return next && { dueDate: next.dueDate, dueTime: next.dueTime, rule: next.rule };
}

// Every path that completes a task must go through here, or recurring tasks stop recurring
async function completeTask(task) {
  await prisma.task.update({
    where: { id: task.id },
    data: { status: 'done', completedAt: new Date() },
  });
  await createNextOccurrence(task);
}

async function createNextOccurrence(task) {
  if (task.recurring && task.recurRule) {
    const next = nextDueDate(task);
    if (next) {
      await prisma.task.create({
        data: {
          userId: task.userId,
          title: task.title,
          notes: task.notes,
          status: 'inbox',
          priority: task.priority,
          dueDate: next.dueDate,
          dueTime: next.dueTime ?? task.dueTime,
          tags: task.tags,
          recurring: true,
          recurRule: next.rule || task.recurRule,
        },
      });
    }
  }
}

const getUserTags = getAllUserTags;

function dayBounds(tz) {
  const todayLocal = new Date().toLocaleDateString('en-CA', { timeZone: tz || 'UTC' });
  const start = new Date(todayLocal + 'T00:00:00.000Z');
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  const weekEnd = new Date(start.getTime() + 7 * 24 * 60 * 60 * 1000);
  const slipCut = new Date(start.getTime() - SLIPPING_DAYS * 24 * 60 * 60 * 1000);
  return { start, end, weekEnd, slipCut };
}

function buildWhere(userId, view, tz) {
  const { start, end, weekEnd, slipCut } = dayBounds(tz);
  const noSubs = { parentId: null }; // exclude subtasks from top-level lists
  switch (view) {
    case 'today':
      return { userId, ...noSubs, status: { notIn: ['done', 'archived'] }, dueDate: { lt: end } };
    case 'upcoming':
      return { userId, ...noSubs, status: { notIn: ['done', 'archived'] }, dueDate: { gte: start, lt: weekEnd } };
    case 'completed':
      return { userId, ...noSubs, status: 'done' };
    case 'archived':
      return { userId, ...noSubs, status: 'archived' };
    case 'slipping':
      return { userId, ...noSubs, status: { in: ['inbox', 'today', 'in-progress'] }, updatedAt: { lt: slipCut } };
    case 'all':
      return { userId, ...noSubs, status: { notIn: ['done', 'archived'] } };
    case 'inbox':
    default:
      return { userId, ...noSubs, status: { notIn: ['done', 'archived'] }, dueDate: null };
  }
}

function buildOrder(view) {
  if (view === 'today' || view === 'upcoming') return [{ dueDate: 'asc' }, { createdAt: 'desc' }];
  if (view === 'completed') return [{ completedAt: 'desc' }];
  if (view === 'archived') return [{ updatedAt: 'desc' }];
  return [{ createdAt: 'desc' }];
}

// Applies priority on top of buildOrder's database ordering (Array#sort is stable)
function sortByPriority(tasks, view) {
  if (view === 'completed' || view === 'archived') return tasks;
  if (view === 'today' || view === 'upcoming') {
    const day = t => (t.dueDate ? t.dueDate.getTime() : Infinity);
    return tasks.sort((a, b) => day(a) - day(b) || byPriority(a, b));
  }
  return tasks.sort(byPriority);
}

function escHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// Returns HTML for the status select element (used in HTMX responses)
function statusSelectHtml(taskId, status) {
  const opts = STATUSES.map(
    (s) => `<option value="${s}" ${s === status ? 'selected' : ''}>${STATUS_LABELS[s]}</option>`
  ).join('');
  const cls = STATUS_CLS[status] || 'text-gray-400';
  return `<div id="st-${taskId}" class="shrink-0">
    <select hx-post="/tasks/${taskId}/status" hx-target="#st-${taskId}" hx-swap="outerHTML"
            hx-trigger="change" name="status"
            class="appearance-none text-xs font-medium cursor-pointer bg-transparent border-0
                   focus:outline-hidden ${cls} max-w-[90px]">
      ${opts}
    </select>
  </div>`;
}

// Returns HTML for a full task row (used in quick-add HTMX response)
function taskRowHtml(task, tz) {
  const ring = PRIORITY_RING[task.priority] || PRIORITY_RING.none;
  const icon = PRIORITY_ICON[task.priority] || PRIORITY_ICON.none;
  const due = task.dueDate ? new Date(task.dueDate) : null;
  const _now = new Date();
  const _todayLocal = _now.toLocaleDateString('en-CA', { timeZone: tz || 'UTC' });
  const _dueUTC = due ? `${due.getUTCFullYear()}-${String(due.getUTCMonth()+1).padStart(2,'0')}-${String(due.getUTCDate()).padStart(2,'0')}` : null;
  const _nowHHMM = (() => { const s = _now.toLocaleTimeString('en-US', { timeZone: tz || 'UTC', hour: '2-digit', minute: '2-digit', hour12: false }); return s === '24:00' ? '00:00' : s; })();
  const _timePast = task.dueTime ? task.dueTime < _nowHHMM : false;
  const overdue = due && task.status !== 'done' && (_dueUTC < _todayLocal || (_dueUTC === _todayLocal && _timePast));
  const _isToday = due && _dueUTC === _todayLocal && !overdue;
  const dueCls = overdue ? 'text-red-400' : _isToday ? 'text-green-400' : 'text-gray-600';
  const dueStr = due ? due.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' }) : '';
  const tags = task.tags.map((t) => `<span class="hidden sm:inline px-1.5 py-0.5 rounded text-[10px] bg-gray-800 text-gray-600">#${escHtml(t)}</span>`).join('');

  return `<div class="task-row flex items-center gap-3 px-4 py-3 border-b border-gray-800 last:border-0 hover:bg-gray-800/30 group" id="task-${task.id}">
    <input type="checkbox" name="ids" value="${task.id}" form="bulk-form"
           class="w-4 h-4 rounded border-gray-600 bg-gray-700 text-indigo-600 focus:ring-indigo-500 focus:ring-offset-gray-900 shrink-0" />
    <button hx-post="/tasks/${task.id}/complete" hx-target="#task-${task.id}" hx-swap="outerHTML"
            class="w-5 h-5 rounded-full border-2 ${ring} hover:bg-green-500/20 hover:border-green-500 shrink-0 transition-colors" title="Mark complete"></button>
    ${icon}
    <a href="/tasks/${task.id}" class="flex-1 min-w-0 text-sm text-gray-200 hover:text-white truncate">${escHtml(task.title)}</a>
    ${due ? `<span class="text-xs shrink-0 ${dueCls}">${escHtml(dueStr)}</span>` : ''}
    ${tags}
    ${statusSelectHtml(task.id, task.status)}
    <a href="/tasks/${task.id}" class="opacity-0 group-hover:opacity-100 text-gray-600 hover:text-gray-300 transition-all shrink-0 ml-1">
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
        <path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931z" />
      </svg>
    </a>
  </div>`;
}

// ── Routes ──────────────────────────────────────────────────────────────────

// GET /tasks
router.get('/', async (req, res, next) => {
  try {
    const view = req.query.view || 'inbox';
    const { tag, search } = req.query;

    const tz = req.user.timezone || 'UTC';
    const where = buildWhere(req.user.id, view, tz);
    if (tag) where.tags = { has: tag };
    if (search) where.OR = [
      { title: { contains: search, mode: 'insensitive' } },
      { notes: { contains: search, mode: 'insensitive' } },
    ];

    const { end: todayEnd, slipCut } = dayBounds(tz);
    const todayLocal = new Date().toLocaleDateString('en-CA', { timeZone: tz });
    const nowHHMM = (() => { const s = new Date().toLocaleTimeString('en-US', { timeZone: tz, hour: '2-digit', minute: '2-digit', hour12: false }); return s === '24:00' ? '00:00' : s; })();

    const [tasks, tagList, todayCount, inboxCount, slippingCount] = await Promise.all([
      prisma.task.findMany({ where, orderBy: buildOrder(view) }).then(t => sortByPriority(t, view)),
      getUserTags(req.user.id),
      prisma.task.count({ where: { userId: req.user.id, status: { notIn: ['done', 'archived'] }, dueDate: { lt: todayEnd } } }),
      prisma.task.count({ where: { userId: req.user.id, status: { notIn: ['done', 'archived'] }, dueDate: null } }),
      prisma.task.count({ where: { userId: req.user.id, status: { in: ['inbox', 'today', 'in-progress'] }, updatedAt: { lt: slipCut } } }),
    ]);

    res.render('tasks/index', {
      title: 'Tasks',
      tasks,
      tagList,
      view,
      filters: { tag: tag || '', search: search || '' },
      counts: { today: todayCount, inbox: inboxCount, slipping: slippingCount },
      todayLocal,
      nowHHMM,
      PRIORITY_DOT,
      PRIORITY_RING,
      PRIORITY_ICON,
      STATUS_CLS,
      STATUS_LABELS,
      STATUSES,
      statusSelectHtml,
    });
  } catch (err) {
    next(err);
  }
});

// GET /tasks/new
router.get('/new', async (req, res, next) => {
  try {
    const tagList = await getUserTags(req.user.id);
    res.render('tasks/form', {
      title: 'New Task',
      task: { status: req.query.status || 'inbox', priority: 'none', tags: [] },
      errors: [],
      tagList,
      STATUSES,
      STATUS_LABELS,
    });
  } catch (err) {
    next(err);
  }
});

// POST /tasks — create
router.post('/', async (req, res, next) => {
  try {
    const { title, notes, status = 'inbox', priority = 'none',
            dueDate, dueTime, tags: tagsRaw, recurring, recurRule } = req.body;

    if (!title?.trim()) {
      if (req.headers['hx-request']) return res.status(400).end();
      const tagList = await getUserTags(req.user.id);
      return res.render('tasks/form', {
        title: 'New Task', task: req.body, errors: ['Title is required.'],
        tagList, STATUSES, STATUS_LABELS,
      });
    }

    const task = await prisma.task.create({
      data: {
        userId: req.user.id,
        title: title.trim(),
        notes: notes || '',
        status,
        priority,
        dueDate: dueDate ? new Date(dueDate) : null,
        dueTime: dueTime || null,
        tags: parseTags(tagsRaw),
        recurring: recurring === 'on',
        recurRule: recurring === 'on' ? (recurRule || 'daily') : null,
      },
    });

    if (req.headers['hx-request']) return res.send(taskRowHtml(task, req.user.timezone || 'UTC'));
    res.redirect('/tasks?view=' + status);
  } catch (err) {
    next(err);
  }
});

// GET /tasks/:id
router.get('/:id', async (req, res, next) => {
  try {
    const task = await prisma.task.findFirst({
      where: { id: Number(req.params.id), userId: req.user.id },
      include: { subtasks: { orderBy: { createdAt: 'asc' } } },
    });
    if (!task) return res.status(404).render('error', { title: 'Not found', error: { message: 'Task not found.' } });
    const renderedNotes = task.notes ? renderMd(task.notes) : '';
    res.render('tasks/show', { title: task.title, task, renderedNotes, STATUSES, STATUS_LABELS, STATUS_CLS, PRIORITY_DOT, PRIORITY_ICON });
  } catch (err) {
    next(err);
  }
});

// POST /tasks/:id/subtasks — add a subtask
router.post('/:id/subtasks', async (req, res, next) => {
  try {
    const parentId = Number(req.params.id);
    const title = (req.body.title || '').trim();
    if (!title) return res.redirect(`/tasks/${parentId}`);
    const parent = await prisma.task.findFirst({ where: { id: parentId, userId: req.user.id } });
    if (!parent) return res.status(403).end();
    await prisma.task.create({ data: { userId: req.user.id, title, parentId, status: 'inbox' } });
    res.redirect(`/tasks/${parentId}`);
  } catch (err) { next(err); }
});

// POST /tasks/:id/subtasks/:sid/toggle — complete or restore a subtask
router.post('/:id/subtasks/:sid/toggle', async (req, res, next) => {
  try {
    const parentId = Number(req.params.id);
    const sid = Number(req.params.sid);
    const sub = await prisma.task.findFirst({ where: { id: sid, parentId, userId: req.user.id } });
    if (!sub) return res.status(403).end();
    const done = sub.status === 'done';
    await prisma.task.update({ where: { id: sid }, data: { status: done ? 'inbox' : 'done', completedAt: done ? null : new Date() } });
    res.redirect(`/tasks/${parentId}`);
  } catch (err) { next(err); }
});

// POST /tasks/:id/subtasks/:sid/delete
router.post('/:id/subtasks/:sid/delete', async (req, res, next) => {
  try {
    const parentId = Number(req.params.id);
    const sid = Number(req.params.sid);
    const sub = await prisma.task.findFirst({ where: { id: sid, parentId, userId: req.user.id } });
    if (!sub) return res.status(403).end();
    await prisma.task.delete({ where: { id: sid } });
    res.redirect(`/tasks/${parentId}`);
  } catch (err) { next(err); }
});

// GET /tasks/:id/edit
router.get('/:id/edit', async (req, res, next) => {
  try {
    const task = await prisma.task.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!task) return res.status(404).render('error', { title: 'Not found', error: { message: 'Task not found.' } });
    const tagList = await getUserTags(req.user.id);
    res.render('tasks/form', { title: `Edit — ${task.title}`, task, errors: [], tagList, STATUSES, STATUS_LABELS });
  } catch (err) {
    next(err);
  }
});

// POST /tasks/bulk — bulk actions (must be registered before POST /:id, or "bulk" is taken as an id)
router.post('/bulk', async (req, res, next) => {
  try {
    const { action, ids: rawIds } = req.body;
    const ids = (Array.isArray(rawIds) ? rawIds : [rawIds]).map(Number).filter(Boolean);

    if (ids.length && action) {
      let data = {};
      if (action === 'complete') {
        const tasks = await prisma.task.findMany({ where: { id: { in: ids }, userId: req.user.id, status: { not: 'done' } } });
        for (const t of tasks) await completeTask(t);
      }
      else if (action === 'archive') data = { status: 'archived' };
      else if (action === 'restore') data = { status: 'inbox' };
      else if (['high', 'medium', 'low', 'none'].includes(action)) data = { priority: action };

      if (Object.keys(data).length) {
        await prisma.task.updateMany({ where: { id: { in: ids }, userId: req.user.id }, data });
      }
    }

    res.redirect('/tasks');
  } catch (err) {
    next(err);
  }
});

// POST /tasks/:id — update
router.post('/:id', async (req, res, next) => {
  try {
    const existing = await prisma.task.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!existing) return res.status(404).render('error', { title: 'Not found', error: { message: 'Task not found.' } });

    const { title, notes, status = 'inbox', priority = 'none',
            dueDate, dueTime, tags: tagsRaw, recurring, recurRule } = req.body;

    if (!title?.trim()) {
      const tagList = await getUserTags(req.user.id);
      return res.render('tasks/form', {
        title: `Edit — ${existing.title}`,
        task: { ...existing, ...req.body, id: existing.id },
        errors: ['Title is required.'], tagList, STATUSES, STATUS_LABELS,
      });
    }

    const becameDone = status === 'done' && existing.status !== 'done';
    const completedAt = becameDone ? new Date() : existing.completedAt;

    const updated = await prisma.task.update({
      where: { id: existing.id },
      data: {
        title: title.trim(),
        notes: notes || '',
        status,
        priority,
        dueDate: dueDate ? new Date(dueDate) : null,
        dueTime: dueTime || null,
        tags: parseTags(tagsRaw),
        recurring: recurring === 'on',
        recurRule: recurring === 'on' ? (recurRule || 'daily') : null,
        completedAt,
      },
    });
    if (becameDone) await createNextOccurrence(updated);

    res.redirect(`/tasks/${existing.id}`);
  } catch (err) {
    next(err);
  }
});

// POST /tasks/:id/delete
router.post('/:id/delete', async (req, res, next) => {
  try {
    const task = await prisma.task.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (task) await prisma.task.delete({ where: { id: task.id } });
    if (req.headers['hx-request']) return res.send('');
    res.redirect('/tasks');
  } catch (err) {
    next(err);
  }
});

// POST /tasks/:id/complete — HTMX: mark complete, remove row
router.post('/:id/complete', async (req, res, next) => {
  try {
    const task = await prisma.task.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!task) return res.status(404).end();
    await completeTask(task);
    res.send('');
  } catch (err) {
    next(err);
  }
});

// POST /tasks/:id/restore — HTMX: un-complete, remove from completed view
router.post('/:id/restore', async (req, res, next) => {
  try {
    const task = await prisma.task.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!task) return res.status(404).end();
    await prisma.task.update({ where: { id: task.id }, data: { status: 'inbox', completedAt: null } });
    res.send('');
  } catch (err) {
    next(err);
  }
});

// POST /tasks/:id/status — HTMX: change status, return updated select
router.post('/:id/status', async (req, res, next) => {
  try {
    const task = await prisma.task.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!task) return res.status(404).end();

    const { status } = req.body;
    if (!STATUSES.includes(status)) return res.status(400).end();

    if (status === 'done' && task.status !== 'done') {
      await completeTask(task);
    } else {
      await prisma.task.update({
        where: { id: task.id },
        data: { status, completedAt: status === 'done' ? task.completedAt : null },
      });
    }

    res.send(statusSelectHtml(task.id, status));
  } catch (err) {
    next(err);
  }
});

// PATCH /tasks/:id/title — HTMX: inline title edit, return updated heading
router.patch('/:id/title', async (req, res, next) => {
  try {
    const task = await prisma.task.findFirst({ where: { id: Number(req.params.id), userId: req.user.id } });
    if (!task) return res.status(404).end();

    const { title } = req.body;
    const updated = title?.trim()
      ? await prisma.task.update({ where: { id: task.id }, data: { title: title.trim() } })
      : task;

    res.send(`<h1 id="task-title"
       class="text-2xl font-bold text-white cursor-text leading-tight"
       onclick="document.getElementById('title-input').classList.remove('hidden'); document.getElementById('task-title').classList.add('hidden'); document.getElementById('title-input').focus();">
  ${escHtml(updated.title)}
</h1>`);
  } catch (err) {
    next(err);
  }
});

module.exports = { router, STATUSES, completeTask, createNextOccurrence, nextDueDate, buildWhere, buildOrder, sortByPriority, dayBounds };
