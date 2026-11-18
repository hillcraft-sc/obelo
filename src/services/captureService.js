const prisma = require('../lib/prisma');
const ai = require('../lib/aiProvider');

const TYPES = ['task', 'reminder', 'note', 'journal', 'quote', 'list', 'bookmark'];

const nullable = type => ({ type: [type, 'null'] });

// Mirrors the schema in SYSTEM_PROMPT; sent as native JSON mode where the provider supports it
const CAPTURE_SCHEMA = {
  type: 'object',
  properties: {
    type:          { type: 'string', enum: TYPES },
    title:         { type: 'string' },
    content:       nullable('string'),
    url:           nullable('string'),
    items:         { type: ['array', 'null'], items: { type: 'string' } },
    dueDate:       nullable('string'),
    dueTime:       nullable('string'),
    tags:          { type: 'array', items: { type: 'string' } },
    priority:      { type: 'string', enum: ['none', 'low', 'medium', 'high'] },
    flagForReview: { type: 'boolean' },
    reviewDate:    nullable('string'),
    source:        nullable('string'),
    author:        nullable('string'),
    confidence:    { type: 'string', enum: ['high', 'medium', 'low'] },
  },
  required: ['type', 'title', 'content', 'url', 'items', 'dueDate', 'dueTime', 'tags',
             'priority', 'flagForReview', 'reviewDate', 'source', 'author', 'confidence'],
  additionalProperties: false,
};

const SYSTEM_PROMPT = `You are a personal productivity assistant embedded in Obelo. Your job is to parse a user's raw input and return a structured JSON object representing what they want to capture.

Return ONLY valid JSON — no prose, no markdown fences, no explanation.

Schema:
{
  "type": "task" | "reminder" | "note" | "journal" | "quote" | "list" | "bookmark",
  "title": string,
  "content": string | null,
  "url": string | null,
  "items": string[] | null,
  "dueDate": "YYYY-MM-DD" | null,
  "dueTime": "HH:MM" | null,
  "tags": string[],
  "priority": "none" | "low" | "medium" | "high",
  "flagForReview": boolean,
  "reviewDate": "YYYY-MM-DD" | null,
  "source": string | null,
  "author": string | null,
  "confidence": "high" | "medium" | "low"
}

Rules:
- "task" = something to do with no specific time; "reminder" = something with a specific date/time
- "note" = general knowledge, thoughts, or information; "journal" = personal reflection dated to today
- "quote" = a quote or book/podcast recommendation — put the quote or book title in title, author in author, source in source
- "list" = a named checklist of items; use when the user wants to create a list or enumerate items for a collection; put each item as a string in the "items" array; title is the list name
- "bookmark" = saving a URL or link; put the full URL in "url", a short descriptive label in "title", and any notes in "content"; auto-add https:// if the protocol is missing
- Extract due dates/times from natural language ("tuesday", "3pm", "next week") relative to the current date provided
- Set confidence "low" if intent is genuinely ambiguous
- Tags should be lowercase, no spaces (use hyphens), no # prefix
- If input mentions a person's name in context of a meeting or reminder, do NOT add them as a tag
- title should be concise and action-oriented for tasks/reminders, descriptive for notes/lists/bookmarks
- For "list" and "bookmark" types, set dueDate, dueTime, and priority to null/"none" unless explicitly stated`;

// Without AI, Capture keeps what was typed as a plain note: the same thing the web's Capture page
// does. Returning it as a normal suggestion lets the apps use their usual review-and-save flow.
function plainNoteSuggestion(rawInput) {
  const text = String(rawInput).trim();
  return {
    type: 'note', title: text.split('\n')[0].slice(0, 80) || 'Untitled', content: text,
    url: null, items: null, dueDate: null, dueTime: null, tags: [], priority: 'none',
    flagForReview: false, reviewDate: null, source: null, author: null, confidence: 'high',
  };
}

// An optional type the person chose before processing ("task", "reminder", …). Anything else, including
// "auto" or nothing, leaves the choice to the AI.
function typeHint(value) {
  if (typeof value !== 'string') return null;
  const v = value.trim().toLowerCase();
  return TYPES.includes(v) ? v : null;
}

// Tells the model the choice. Without this a time in the text ("at 10am") makes it pick a reminder.
function hintInstruction(hint) {
  return hint
    ? `The user has chosen the type "${hint}". Set "type" to "${hint}" and fill in the fields that suit it. A task may have a due date and a due time.`
    : '';
}

// Whatever the model answered, the chosen type is the one returned
function applyTypeHint(suggestion, hint) {
  return hint ? { ...suggestion, type: hint } : suggestion;
}

// `hint` is ignored when AI isn't set up: the text is kept as a note and the person can change the type
// on the review card.
async function processCapture(rawInput, user, hint) {
  if (!ai.isConfigured()) return plainNoteSuggestion(rawInput);
  const chosen = typeHint(hint);
  const now = new Date();
  const dateStr = now.toLocaleDateString('en-US', {
    timeZone: user.timezone || 'America/New_York',
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
  });
  const timeStr = now.toLocaleTimeString('en-US', {
    timeZone: user.timezone || 'America/New_York',
    hour: 'numeric', minute: '2-digit',
  });

  const existingTags = await prisma.note.findMany({
    where: { userId: user.id, private: false, locked: false },
    select: { tags: true },
  }).then(notes => [...new Set(notes.flatMap(n => n.tags))].slice(0, 30));

  const userContext = `Current date/time: ${dateStr}, ${timeStr}
User timezone: ${user.timezone || 'America/New_York'}
Existing tags (use these when appropriate): ${existingTags.join(', ') || 'none yet'}`;

  const request = {
    feature:    'capture',
    system:     SYSTEM_PROMPT,
    messages:   [{ role: 'user', content: `${userContext}${chosen ? `\n\n${hintInstruction(chosen)}` : ''}\n\nRaw input: ${rawInput}` }],
    jsonSchema: CAPTURE_SCHEMA,
  };

  // Smaller/local models occasionally return malformed JSON — give them one more try
  let text = await ai.complete(request);
  let suggestion = parseSuggestion(text);
  if (!suggestion) {
    console.error('[capture] invalid AI response, retrying. raw:', text);
    text = await ai.complete(request);
    suggestion = parseSuggestion(text);
  }
  if (!suggestion) {
    console.error('[capture] invalid AI response after retry. raw:', text);
    throw new ai.AiError("The AI model didn't return a usable result — try rephrasing, or ask the server admin to use a stronger capture model.");
  }
  return applyTypeHint(suggestion, chosen);
}

// Returns a normalized suggestion object, or null if the text isn't a usable capture
function parseSuggestion(text) {
  let s = (text || '').trim()
    .replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim();
  // Tolerate prose around the object ("Sure! Here it is: {...}")
  const start = s.indexOf('{');
  const end   = s.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  s = s.slice(start, end + 1);

  let obj;
  try { obj = JSON.parse(s); } catch { return null; }
  if (!obj || typeof obj !== 'object' || !TYPES.includes(obj.type)) return null;
  if (typeof obj.title !== 'string' || !obj.title.trim()) return null;

  const str = v => (typeof v === 'string' && v.trim() ? v : null);
  return {
    type:          obj.type,
    title:         obj.title.trim(),
    content:       str(obj.content),
    url:           str(obj.url),
    items:         Array.isArray(obj.items) ? obj.items.filter(i => typeof i === 'string') : null,
    dueDate:       str(obj.dueDate),
    dueTime:       str(obj.dueTime),
    tags:          Array.isArray(obj.tags) ? obj.tags.filter(t => typeof t === 'string') : [],
    priority:      ['none', 'low', 'medium', 'high'].includes(obj.priority) ? obj.priority : 'none',
    flagForReview: obj.flagForReview === true,
    reviewDate:    str(obj.reviewDate),
    source:        str(obj.source),
    author:        str(obj.author),
    confidence:    ['high', 'medium', 'low'].includes(obj.confidence) ? obj.confidence : 'low',
  };
}

async function confirmCapture(draftId, userId, edits = {}) {
  const draft = await prisma.captureDraft.findFirst({
    where: { id: draftId, userId },
  });
  if (!draft) throw Object.assign(new Error('Draft not found'), { status: 404 });

  const s = { ...draft.aiSuggestion, ...edits };
  let saved;

  if (s.type === 'task') {
    saved = await prisma.task.create({
      data: {
        userId,
        title:    s.title,
        notes:    s.content   || null,
        priority: s.priority  || 'none',
        dueDate:  s.dueDate   ? new Date(s.dueDate) : null,
        dueTime:  s.dueTime   || null,
        tags:     s.tags      || [],
        status:   'inbox',
      },
    });
  } else if (s.type === 'reminder') {
    saved = await prisma.reminder.create({
      data: {
        userId,
        title:    s.title,
        notes:    s.content  || null,
        priority: s.priority || 'none',
        dueDate:  s.dueDate  ? new Date(s.dueDate) : null,
        dueTime:  s.dueTime  || null,
      },
    });
  } else if (s.type === 'list') {
    const itemTexts = (s.items || []).filter(Boolean);
    saved = await prisma.list.create({
      data: {
        userId,
        title: s.title,
        items: itemTexts.length
          ? { create: itemTexts.map(text => ({ text })) }
          : undefined,
      },
    });
  } else if (s.type === 'bookmark') {
    let url = (s.url || '').trim();
    if (url && !/^https?:\/\//i.test(url)) url = 'https://' + url;
    saved = await prisma.bookmark.create({
      data: {
        userId,
        url:         url || 'https://',
        title:       s.title       || null,
        description: s.content     || null,
        tags:        s.tags        || [],
      },
    });
  } else {
    saved = await prisma.note.create({
      data: {
        userId,
        type:            s.type === 'journal' || s.type === 'quote' ? s.type : 'note',
        title:           s.title,
        content:         s.content         || null,
        source:          s.source          || null,
        author:          s.author          || null,
        tags:            s.tags            || [],
        flaggedForReview: s.flagForReview  || false,
        reviewDate:      s.reviewDate      ? new Date(s.reviewDate) : null,
      },
    });
  }

  await prisma.captureDraft.update({
    where: { id: draftId },
    data:  { status: 'confirmed' },
  });

  return { type: s.type, saved };
}

module.exports = { processCapture, confirmCapture, typeHint, hintInstruction, applyTypeHint };
