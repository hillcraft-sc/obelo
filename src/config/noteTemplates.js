// The starter note templates. Everyone starts with these; a person's own list (lib/userTemplates.js)
// is a copy they can edit, delete from and add to. A template sets the note's type, a starting title
// and starting content.

const TEMPLATES = [
  {
    key: 'meeting', label: 'Meeting Notes', type: 'note', title: 'Meeting — ',
    content: `## Attendees\n- \n\n## Agenda\n- \n\n## Notes\n\n\n## Action Items\n- [ ] \n`,
  },
  {
    key: 'weekly', label: 'Weekly Review', type: 'journal', title: 'Weekly Review — ',
    content: `## Wins this week\n- \n\n## Challenges\n- \n\n## Next week priorities\n- \n\n## How am I feeling?\n\n`,
  },
  {
    key: 'project', label: 'Project Plan', type: 'note', title: 'Project — ',
    content: `## Overview\n\n\n## Goals\n- \n\n## Tasks\n- [ ] \n\n## Notes\n\n`,
  },
  {
    key: 'journal', label: 'Journal Entry', type: 'journal', dateTitle: true,
    content: `## How am I feeling?\n\n\n## What happened today?\n\n\n## What am I grateful for?\n- \n\n## Tomorrow\n- \n`,
  },
];

// The starting title. Journal entries are titled with today's date in the user's timezone.
function templateTitle(t, timeZone = 'America/New_York') {
  if (t.dateTitle) {
    return new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone }) + ' — ';
  }
  return t.title;
}

module.exports = { STARTERS: TEMPLATES, templateTitle };
