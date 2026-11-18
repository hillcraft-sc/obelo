# Changelog

What changed in each release, newest first. Server versions are `package.json`; app versions are `MARKETING_VERSION` in `ios/project.yml`. Hosts: lines that start with "Hosts:" are things you may need to do before or after updating.

## Server

The web app and server (everything under `src/`, `prisma/`, `public/`, and the Docker files).

### 3.57.1

**Changed**

- The prebuilt image is now published for ARM as well as Intel/AMD, so `docker compose pull app` works on a Raspberry Pi, an ARM server and a Mac with Apple silicon. (3.57.0's image was Intel/AMD only; there, `install.sh` fell back to building.) No change to the app itself.

### 3.57.0

**Changed**

- Web: Notes now has one screen, the workspace (folders beside the open note). The Classic list and its Settings choice are gone; old note links open the note in the workspace.
- Web: the workspace list has a Show menu (All, Notes, Journal, Quotes, Flagged, Slipping) and a Select button for bulk actions: delete, pin, unpin, flag, unflag, add or remove tags. The Flagged and Slipping lists moved here from the old list.
- Web: Markdown import is in Settings ▸ Data only (the Classic list's Import button is gone). Swiping a note row to pin or flag it is gone; use Select.
- No app change: the iPhone, iPad and Mac apps never had the Classic view.

**Added**

- `install.sh` first tries to download a ready-made image of the latest release (faster, no build) and builds from the code if none is available. `docker-compose.yml` names the image `ghcr.io/hillcraft-sc/obelo:latest`; `docker compose pull app` fetches it. Building from your checkout still works as before.
- README: an Upgrading section (back up, read the Hosts: lines, update).

**Fixed**

- Web: a long note in Preview ran off the bottom of the workspace with no scrollbar. The note area now scrolls.
- The content security policy no longer allows Cloudflare Insights scripts (they were one instance's analytics). Hosts: if you turned on Cloudflare Web Analytics for your domain, the browser will now block its script; turn it off in Cloudflare.

### 3.56.1

**Changed**

- The public demo (`DEMO_MODE=true`) refuses password changes too, so everyone can keep signing in as demo / demo. The web and apps hide the password section there.

### 3.56.0

**Added**

- `DEMO_MODE=true` for the public demo: calendar accounts (CalDAV and Google) and notification channels are refused on the server, and the web and apps say so. Reading them still works, and local calendars still work.
- Hosts: set `DEMO_MODE=true` only on a public demo. Leave it blank on your own server.

### 3.55.0

**Added**

- Apps: managing calendars. New `/api/v1` calls to add a CalDAV account, sync it, change its colour, choose which of its calendars to sync, remove it, and to create, rename, recolour, delete and share your own calendars, and set the default calendar (`GET /api/v1/calendar/sources` lists everything). Nothing returns a password or token. Connecting a new Google account from an app comes in a later version; Google accounts connected on the web can already be managed.
- Web: Settings has a Calendars entry that opens Calendar Sources, so every client finds it in the same place.

**Changed**

- The web's Calendar Sources page and the apps now share one set of code, so they follow the same rules. A bad colour is replaced by the default, "Calendars to sync" ignores addresses that are not in the account, and adding a CalDAV account is limited to 20 tries per 15 minutes per address.
- Hosts: no new setting and no migration. Deploy this version before the apps' Calendars tab can work.

### 3.54.0

**Changed**

- The web's sidebar now looks and works like the Mac's and the wide iPad's: modules in groups (Today and Capture, then Do, Write, Plan, See, Assist), each group with a heading and a fixed order, whatever order was saved. Settings is the profile block at the bottom (click it), not a row in the list.
- Settings ▸ Modules on the web is for switching modules on or off only: no dragging and no "Bottom bar" badges. Saving it leaves the saved order alone. The order only matters for the phone's bottom bar, which you set in the iPhone app (Settings ▸ Modules), and the web's phone-sized bottom bar still follows it.
- Hosts: no new setting and no migration.

### 3.53.0

**Added**

- Apps: three new API calls for the Shortcuts tab: `GET /api/v1/settings/api-tokens` (your keys, by name, with when each was made and last used), `POST /api/v1/settings/api-tokens` (makes one; the token is in that one answer only, and only its hash is kept) and `DELETE /api/v1/settings/api-tokens/:id` (revokes one). The web's Shortcuts tab is unchanged.

**Fixed**

- The iOS Shortcuts capture address (`POST /capture/api`, signed in by its Bearer token) was refused with 403 by the web's CSRF check since 3.46.9, so no Shortcut could capture. It now passes the CSRF check on its Bearer token alone, as the apps' `/api/v1` does; every other address still needs the CSRF token (tested).
- Hosts: deploy this version before the apps' Shortcuts tab can work. No new setting and no migration.

### 3.52.1

**Fixed**

- AI Chat no longer pretends to do things it can't. The chat only reads your data, but asked to "go ahead and set it up" the model could answer "Done!" with a list of routines it never created. Its instructions now say plainly that it cannot create, change or delete anything, and to give you the exact details (title, day, time, how often) so you can add them yourself. This is the same on the web, iPhone, iPad and Mac. (Letting the chat create items for you is a possible later feature.)
- Hosts: no new setting and no migration. Redeploy to pick it up.

### 3.52.0

**Added**

- Apps: `GET /api/v1/calendar` also returns `sources`, the calendars you have connected (name, colour, when each last synced), so the apps can show the web's legend under the calendar and its "No calendars connected" notice. Older apps ignore it.
- Hosts: deploy this version before the apps' calendar legend and notice appear. No new setting.

### 3.51.0

**Added**

- Apps: two new API calls. `POST /api/v1/bookmarks/bulk-delete` (`{ ids }`) deletes several of your bookmarks in one request, and `POST /api/v1/bookmarks/:id/share-to-user` (`{ username }`) sends a copy of one of your bookmarks to another user, the same as the web's Share box (which now uses the same code, so nothing changes on the web).
- Hosts: deploy this version before the apps' bookmark bulk delete and "Send to Obelo user" can work. No new setting.

### 3.50.0

**Added**

- Lists can be renamed. On the web, click the pencil beside a list's title (Return saves, Escape cancels); the apps get the same on iPhone, iPad and Mac. Only the owner can rename.
- A new API call, `GET /api/v1/users/shareable`, lists the people you can share a list with, so the apps can suggest names as you type in the Share box.

### 3.49.0

**Added**

- Apps: the apps can now complete, archive, restore or set the priority of several tasks in one request (`POST /api/v1/tasks/bulk`, same actions as the web's bulk bar). Needed by the Mac app's rebuilt Tasks screen. No migration.
- Web: Capture lets you choose the type before processing (Auto, Task, Reminder, Note, Journal, Quote, List, Bookmark), so "take out the trash at 10am" can be a task with a time instead of always a reminder. The example chips are replaced by this row, and the suggestion step uses the same tag picker as Notes instead of a comma-separated box.
- Apps: `POST /api/v1/capture` accepts an optional `type`. The AI is told the type, and the chosen type is the one returned. Apps that don't send it work as before. No migration.
- Web: note templates are now yours. The "+ Note" menu offers your own list, which starts as Meeting Notes, Weekly Review, Project Plan and Journal Entry (**Book Review is gone**), and you can edit, delete and add templates under Settings ▸ Notes ▸ Note templates. "Save as template" on an open note in the workspace keeps its type, title and text as a template. A template can use today's date as its title.
- Apps: `GET /api/v1/note-templates` and `POST`, `PATCH /:id`, `DELETE /:id` for the same list. Your templates are kept with your settings, so there is no migration.
- Web and apps: **handwriting paper**. A new setting, Settings ▸ Notes ▸ Handwriting paper, lets the paper behind handwritten notes follow your theme (the default: dark paper in dark themes, light paper in light themes), or always be Dark or White. The pen colours adjust to the paper (the white pen becomes near-black on light paper), and saved drawings are unchanged, so any drawing reads on either paper. The web editor and note page use it now. The API carries it as `notePaper` in `GET /api/v1/me` and `GET`/`PUT /api/v1/settings/notes` (additive). Kept with your settings, so there is no migration.
- Apps: `POST /api/v1/reminders/bulk` (`{ action: "complete" | "delete", ids }`) completes or deletes several of your reminders in one request, the same as the web's bulk bar (a repeating reminder makes its next one, as when completed one by one). Needed by the Mac app's rebuilt Reminders screen. No migration.
- Apps: `POST /api/v1/routines/bulk` (`{ action: "archive" | "restore" | "delete", ids }`) archives, restores or deletes several of your routines in one request, the same as the web's bulk bar (deleting a routine removes its history with it). Every routine the API returns now also has its `createdAt`. Needed by the Mac app's rebuilt Routines screen. No migration.
- Hosts: deploy this version for the type you choose to reach the AI. No new setting.

### 3.48.0

**Added**

- Web: development servers no longer send push or email. Outside production, Obelo writes "would send…" to the log instead, so a test copy pointed at real settings can't message anyone when the scheduler catches up at start-up. The test buttons in Settings always send.
- Hosts: set `NODE_ENV=production` in `.env`, or add `NOTIFICATIONS_DRY_RUN=false`, before updating. Without one of them your notifications will be logged and not sent. The start-up log says `Notifications: live` or `Notifications: DRY RUN`. No migration.

**Security**

- Updated libraries to clear every known vulnerability (`npm audit` now reports none): multer, nodemailer 10 and others. Email sending is covered by a new test.

**Changed**

- Backup and restore (README) was tested end to end on a fresh install: user, notes, uploads and password all came back.

### 3.47.1

**Changed**

- The in-app Changelog page is gone. What changed in each release is now in `CHANGELOG.md` in the repository, split into Server and Apps. The version number in the sidebar stays as plain text.
- Hosts: no migration and no new settings.

### 3.47.0

**Changed**

- Web, iPhone and iPad: the sign-in button now says "Continue with single sign-on" with a neutral key icon, instead of naming one provider. Any OpenID Connect provider works.
- Hosts: the single sign-on settings are now OIDC_ISSUER, OIDC_CLIENT_ID, OIDC_CLIENT_SECRET and OIDC_REDIRECT_URI. The old AUTHENTIK_* names still work; the server logs a warning at start-up until you rename them in .env. No migration.
- Hosts: two new scripts for the server checkout. scripts/server-branches.sh lists the branches (and which add a migration); scripts/server-deploy.sh [branch] puts a branch on the server, offers a backup first if it adds a migration, rebuilds the app and shows the start-up log.

### 3.46.9

**Security**

- Web: every change you make on the website (saving, deleting, uploading, signing in or out) now carries a hidden per-session token, so another website can no longer trigger one on your behalf. Nothing looks different. If a page has been open since before the update, reload it once if you see "Your session expired". The iPhone, iPad and Mac apps are not affected.

### 3.46.8

**Fixed**

- Web: the Bookmarks page now only turns web addresses (http and https) into links. A bookmark holding something like a "javascript:" address could run code when clicked; the add and edit forms already prevented that, but a JSON import could still bring one in. The import now skips anything that is not a web address
- For developers: new automated tests for output escaping (every page and note preview with attack text) and for database migrations (new install, and upgrades from older versions with data). No change for hosts: no migration, no new settings

### 3.46.7

**Fixed**

- Tasks and reminders that repeat monthly (or every 3 or 6 months) from the 31st or 30th: after a shorter month they now go back to that day. Jan 31 repeats on Feb 28, then Mar 31, Apr 30, May 31, instead of staying on the 28th. The repeat then shows as "Every 1 month on day 31"
- Hosts: no migration and no new settings. Items that already slipped to the 28th stay there until you set their repeat to "Every 1 month on day 31"

### 3.46.6

**Fixed**

- Reminders and calendar events (web and apps): a reminder set for early morning in a zone behind UTC (for example 1:00 in New York) or late evening in a zone ahead of it (for example 23:00 in Tokyo) was scheduled on the wrong day, and times near the day the clocks change could be an hour out. They now fire at the time you set
- Recurring reminders keep the same time on the clock when daylight saving starts or ends; before, a 9:00 reminder moved to 8:00 or 10:00 after the change
- Monthly, every 3 months, every 6 months and yearly repeats (tasks and reminders) no longer run over short months: Jan 31 repeats on Feb 28, not Mar 3, and Feb 29 repeats on Feb 28. "On the Nth weekday" repeats no longer skip February
- Routine reminders are no longer sent for a routine that has not started yet
- Hosts: no migration and no new settings. Reminders already saved keep their stored times until they next repeat. Rebuild the app image to update

### 3.46.5

**Fixed**

- Web and apps: confirming a Capture draft that is not yours, or no longer exists, now says "not found" instead of a server error
- Admin → Users: a "Password link" request for an id such as 1.5 is now refused instead of acting on user 1
- For developers: the project now has automated tests (npm test) for sign-in and for access control between users. No change for hosts: no migration, no new settings, and the server starts exactly as before

### 3.46.4

**Changed**

- New installs now create a database and user called "obelo" instead of "vibetrack". Existing installs are not touched and keep their names: do not add POSTGRES_DB or POSTGRES_USER to an existing .env. Backups and the restore command in the README work with either name
- Capture works without AI: the server saves what you type as a note (as the web page already did), so the apps and shortcuts no longer get an error when AI is not set up
- Installs now use the committed package-lock.json (npm ci), so every build gets the same dependency versions
- Hosts: rebuild the app image (docker compose build app && docker compose up -d app) to pick up the new install step. No migration

### 3.46.3

**Added**

- Web and apps: if you open a production server over plain http://, the sign-in page now says it needs HTTPS. Sign-in and creating the first account are refused with that explanation (before, you were just left signed out), and the apps show the same message
- New setting GOOGLE_SITE_VERIFICATION: the Google site-verification tag is no longer built in, so add your own token to .env if Google asks you to verify your domain
- Hosts: if you relied on the old built-in tag, put its token in GOOGLE_SITE_VERIFICATION in .env, or Google may drop the verification. No migration

### 3.46.2

**Changed**

- Web and installer: single sign-on is now optional everywhere. install.sh asks about it (default: no) and points you to the first-run setup page for the admin account; the README, Help and the admin Setup checklist describe password sign-in, with "Password sign-in" as the required item and SSO as optional
- Admin → Users: the text now mentions the setup code and that admins never see or set a password
- Hosts: no migration and no new settings. Rebuild the app to get the updated pages

### 3.46.1

**Added**

- Web: the sign-in page has "Have a setup code?", so a new person can choose their password with the code from their admin on the web too, not only in the apps

### 3.46.0

**Added**

- Admin → Users: the one-time password link now comes with a short setup code, so a new person can choose their password in the app without opening a browser. Either one works once and expires in 24 hours; using one cancels the other
- Hosts: this release has a small database migration (one new column). Back up as usual before updating

### 3.45.0

**Added**

- You can now sign in with a username and password, with or without SSO. A new server shows a one-time page to create the first (admin) account
- Admin → Users: add someone without an email and you get a one-time link for them to choose their own password; "Reset password" makes a new one. Admins never see or set anyone's password
- Settings → Account: set or change your own password (changing it signs out your other devices)
- Admin → System Settings: "Allow password sign-in" can be switched off while SSO is set up
- Locked out? Run scripts/set-password.js <username or email> on the server
- Hosts: this release has a database migration (adds a password column and a table for one-time links). Back up as usual before updating

### 3.44.1

**Fixed**

- Mac app: SSO sign-in opens in the app's own window, so it works whatever your default browser is (Brave and other third-party browsers never handed the sign-in back to the app)

### 3.44.0

**Added**

- iPad and Mac apps: Notes is a three-pane workspace, as on the web: the folder tree with pinned notes, the open note, and its details beside it when there's room
- iPad and Mac apps: drag a note onto a folder (or Top level) in the tree to move it; right-click or long-press a note to move, pin or delete it
- iPad app: keyboard shortcuts with a hardware keyboard, the same as on the Mac (⌘N, ⌘1–⌘9, ⌘F, ⌘R, ⌘,)

**Changed**

- iPad and Mac apps: pages use the same widths as the web (list pages 768pt, Calendar wider)
- Mac app: switches in place of checkboxes, and no repeated labels on segmented controls

### 3.43.0

**Added**

- Mac app: a native Obelo app for the Mac, with every feature of the iPhone app, including handwritten notes (draw with the mouse or trackpad)
- Mac app: a sidebar grouped into Do, Write, Plan, See and Assist, with Search, Settings and Help at the bottom
- Mac app: menu bar shortcuts: ⌘N for a new item on the page you're on, ⌘1–⌘9 for the sidebar, ⌘F Search, ⌘R Refresh, ⌘, Settings

**Changed**

- iPad app: at full width, the app uses the same sidebar as the Mac in place of the bottom bar

### 3.42.0

**Changed**

- iPhone app: section tabs are underlined, as on the web
- iPhone app: page headers show a one-line description and one main button ("New task", "New note"), and no longer repeat the page name shown in the top bar
- iPhone app: empty lists use the web's wording, with a button to add the first item or clear the filter
- iPhone app: Lists has a New list button in place of the inline name field, and the Calendar heading is the week shown

### 3.41.0

**Added**

- iPhone app: "What stands out" at the top of Analytics, as on the web. Tap a finding to open the routine or list behind it

**Changed**

- iPhone app: Analytics uses the web's plain wording, with a one-line explanation under each chart
- The app's Analytics findings are worded by AI when AI is set up, as on the web
- Completion Velocity says 12 weeks, the period it shows

### 3.40.0

**Added**

- iPhone app: notes folders. Folders on the Notes page opens the folder tree; long-press a folder to add a subfolder, rename it or delete it
- iPhone app: move a note with Move to… (long-press the note) or by dragging it onto a folder
- iPhone app: a note opens ready to edit and saves on its own, as in the web workspace. Folder, type, tags and the rest are under Details
- iPhone app: tick and untick checklist items in a note's Preview

**Fixed**

- iPhone app: Today and the widget refresh on a new day, so routines ticked yesterday no longer show as done
- iPhone app: tag suggestions no longer overlap the row below them

### 3.39.0

**Added**

- Notes: tick and untick checklist items on the note page, and in the editor Preview. A tick on the note page saves at once

**Fixed**

- An indented checklist in a note (for example after a heading) shows as a checklist, not as a code block
- Today reloads when the day changes while the page stays open, so routines ticked yesterday no longer show as done

### 3.38.0

**Changed**

- Tasks and Notes use the same underlined tabs as Routines and Reminders
- Every main page has the same header: the page name, one line of description, and a "New …" button on the right
- Lists and Bookmarks: the add form opens from a New list / New bookmark button instead of always showing
- Empty lists show one centred message and a button to start, or to clear the filter when a filter hides everything
- On phones the page name shows only in the top bar, not again as a heading

### 3.37.0

**Added**

- Settings → Notes: choose whether the Notes menu item opens Classic or Workspace. Both views are always available
- Notes workspace: templates (Meeting, Book Review, Weekly Review, Project Plan, Journal Entry) from the + Note menu
- Notes workspace: Type radio buttons, and Author and Source for quotes, as in the classic form

**Changed**

- The notes workspace is no longer behind a server flag. A Classic view link is on the workspace, and a Workspace link is on the classic list
- Note previews in the classic form are sanitised on the server, as in the workspace

### 3.36.2

**Fixed**

- Note preview in the workspace shows Markdown styling (code, headings, lists) as it does in the classic editor
- Task-list checkboxes render as checkboxes in note previews, instead of as text

### 3.36.1

**Fixed**

- Notes workspace autosave keeps edits made while a save is still running
- Note preview shows the latest text when you switch to it quickly after editing

### 3.36.0

**Changed**

- Notes workspace uses the same editor as the classic note form: Text/Draw, the Markdown toolbar, and Write/Preview
- Handwritten notes open in the workspace editor, in Draw mode
- Tags: pick from a dropdown and see the chosen tags as pills, in the classic form and the workspace. Type a new tag and press Enter to create it

### 3.35.0

**Fixed**

- Styles and scripts update on the next visit after a release, instead of staying on an older copy cached in the browser (this could break the Notes workspace layout)

### 3.34.0

**Changed**

- Notes workspace: the Pinned section stays fixed above the folder tree, so it does not scroll away
- Notes workspace: opening the workspace shows the empty state, not the first note (which could be a locked one)

### 3.33.0

**Changed**

- Notes workspace: pinned notes get a Pinned section at the top of the folder tree (they stay in their folder too)
- Notes workspace: folders can be collapsed, and rename, new subfolder and delete are always visible
- Notes workspace: the folder tree no longer covers the top bar on small screens

### 3.32.0

**Added**

- Notes folders in the app API: list, create, rename and delete folders, and move notes into them. Deleting a folder moves its notes and subfolders up one level

### 3.31.2

**Changed**

- New Obelo app icon, on the website (favicon and home-screen icon) and in the iOS app

### 3.31.1

**Changed**

- The remaining vibeTrack references in the app, code and docs now say Obelo. Saved data, sign-in and backups carry on as before
- iOS app: new bundle ids, App Group and obelo:// link scheme, ready for TestFlight. It installs as a new app, so sign in again; older builds can no longer finish signing in

### 3.31.0

**Added**

- Catppuccin themes now use Catppuccin's own colours for priority dots, overdue, done, warnings and the analytics charts (Red, Yellow, Green, Blue, Peach, Maroon), on the web and in the iOS app
- Settings → Appearance → Status colours: switch a Catppuccin theme back to the classic Tailwind colours

### 3.30.0

**Added**

- Catppuccin themes (catppuccin.com) on the web and in the iOS app: Latte (light), Frappé, Macchiato and Mocha (dark), with the Mauve accent. Text on accent buttons is dark where the pastel accent needs it

### 3.29.0

**Changed**

- The app icon now only appears on the welcome and sign-in pages; the sidebar, top bar and iOS app show the name Obelo on its own, in larger text
- An installed web app no longer shows the name twice in its window title

### 3.28.0

**Changed**

- The iOS app stays signed in for 90 days instead of being signed out after 12 hours without use or 7 days after signing in. The website keeps its shorter limits. Hosts can change it with APP_SESSION_DAYS

### 3.27.0

**Changed**

- vibeTrack is now called Obelo, on the web and in the iOS app
- A new app icon, used for the favicon, the home-screen icon and the iOS app

**Removed**

- The app icon choice in Settings → Appearance, now that there's a single icon

### 3.26.0

**Added**

- iOS app: handwritten notes — draw with a finger or Apple Pencil (pressure-sensitive), with the web's colours, sizes, eraser, undo and clear. Drawings open and edit on both the app and the web
- iOS app: Help, with the same text as the web's Help page. Nothing in the app opens the website any more

### 3.25.0

**Added**

- iOS app: the Data tab works in the app — export (share sheet: Files, AirDrop…), import Markdown notes, task CSVs or a full JSON backup from Files, and delete your account

**Changed**

- The phone bottom bar (web and app) is now Today plus the first four modules you have switched on, in your Settings → Modules order, instead of a fixed set. Modules shows which ones are in the bar

### 3.24.0

**Added**

- iOS app: Notifications, Notes and Tags settings — delivery channels with test buttons and ntfy topic, digest/slipping/due-alert types, autosave, note-lock PIN, and tag create/rename/delete. Settings tabs now match the web

**Fixed**

- "Send test email" said it was sent even when email isn't set up or sending failed; it now reports what actually happened

### 3.23.0

**Added**

- iOS app: Account, Modules, Appearance and Dashboard settings — profile photo (camera or library), name, email, timezone, time format, sign out other devices, module order, custom accent theme and Today card order
- iOS app: a Today widget for the home screen and lock screen, with tick-off buttons

**Changed**

- Settings → Account now rejects a timezone that doesn't exist instead of saving it

### 3.22.0

**Added**

- iOS app: add photos to notes from your photo library or camera, view them full screen (zoom, share) and delete them
- iOS app: Share → Obelo from Safari or any app saves a bookmark, or sends text to Capture

**Fixed**

- iOS app: the home screen icon was solid black

### 3.21.0

**Added**

- iOS app: create, edit and delete calendar events, on the same calendars the web offers (including shared and synced ones). Calendar search results now open the event itself

### 3.20.0

**Added**

- AI Chat in the iOS app: ask questions about your own data, with the same suggestions, daily limit and privacy rules as the web. Each device keeps its own conversation. If the AI can't answer, your question is put back so you can try again

**Fixed**

- iOS app: text boxes now move up with the keyboard instead of being hidden behind it

### 3.19.0

**Added**

- Analytics in the iOS app: the same rates, charts, heatmap and routine stats as the web page, from the same calculations. Tap a chart to see that week's numbers

**Changed**

- Completion Timing chart: "Late 1–3d" and "Late 4–7d" have new shades of orange, so 4–7 days late and 8+ days late are easy to tell apart (they were almost the same colour)

### 3.18.0

**Added**

- A native iOS app (in ios/): Today, Tasks, Reminders, Routines, Notes, Lists, Bookmarks, Calendar, Capture, Search and Settings, laid out like the mobile web app with the same themes. It signs in through the same SSO and shows up under Signed-in devices as "Obelo app on iPhone"
- A JSON API for the app at /api/v1. It uses your normal sign-in session, so the same idle and 7-day limits apply

**Fixed**

- Events from Obelo calendars on the Today page now show their calendar's colour instead of the default

### 3.17.0

**Added**

- Settings → Account → Signed-in devices: see every device you're signed in on (e.g. "Safari on iPhone"), when it signed in, when it was last active and its IP address, and sign out any of them, or all except the one you're using. Devices signed in before this update show as "Unknown device" until they sign in again

**Changed**

- Shorter sign-ins: you're signed out after 12 hours without using Obelo, and 7 days after signing in no matter how active you are (it used to be 30 days). Admins can change both with SESSION_IDLE_HOURS and SESSION_MAX_DAYS. Anyone already signed in gets the full 7 days from the update rather than being signed out right away

**Removed**

- The leftover password_hash column. Sign-in has been SSO only since 3.16.0, so stored password hashes are deleted by this update's database migration

### 3.16.0

**Changed**

- Sign-in is now single sign-on only. The username and password form is gone from the login page, along with Change Password in Settings and Reset/Add password in Admin → Users. Who can sign in, and how, is managed in your identity provider
- Admin → Users: new accounts always need an email, which links the person's first SSO sign-in to the account
- scripts/make-admin.js creates SSO accounts: give it the email of the person's SSO account. The installer now always sets up SSO and asks for the admin's email
- If SSO isn't configured, the login page says so and the app logs a warning at startup

**Removed**

- scripts/seed-users.js (and npm run seed), which created password accounts. Use scripts/make-admin.js

### 3.15.1

**Fixed**

- Routines: routines listed under "Not due today" can no longer be checked off or swiped complete. A stray tap there logged the wrong routine and quietly cost the one you meant its streak. Completing a routine on a day it isn't scheduled is now blocked everywhere, as the routine's own page already did; undoing a completion still works

### 3.15.0

**Added**

- New ./install.sh: an interactive installer for new servers. It installs Docker if needed, creates .env with generated passwords and encryption keys, optionally sets up AI, email, Pushover, SSO, Google Calendar and a locked-down ntfy server, starts Obelo, creates the admin account, schedules tested nightly backups, and prints the reverse-proxy entries to add. Safe to re-run; never overwrites an existing .env
- APP_PORT setting to choose which port Obelo is published on (default 3001, so existing installs are unchanged)
- README: services-at-a-glance table, a complete ntfy self-hosting guide, Cloudflare Tunnel instructions, and a section on which outside services the app contacts

**Fixed**

- Backup failure alerts: the alert-sending step in scripts/backup.sh now uses a proper if/else, and the cleanup count no longer includes stray spaces

### 3.14.0

**Added**

- ntfy push notifications — a free, open-source alternative to Pushover that you can self-host. Turn it on in Settings → Notifications to get your own private topic, subscribe in the free ntfy app, and send a test. Every alert type can use it: reminders, routine alerts, task & reminder due alerts, the daily digest and the slipping-tasks alert
- Server admins: set NTFY_URL (and optionally NTFY_TOKEN) in .env; the README has a step-by-step self-hosting guide, including iPhone setup and locking the server down

**Fixed**

- Unchecking Pushover for Task & reminder alerts had no effect — Pushover alerts kept coming

### 3.13.3

**Fixed**

- Notifications that fell due while Obelo was restarting (for example during an update) were never sent. The scheduler now remembers the last minute it handled and catches up on anything missed as soon as it starts — reminders, routine alerts, task and reminder due alerts, and the daily digest — for outages of up to 15 minutes, without sending anything twice

### 3.13.2

**Security**

- Stored calendar credentials (CalDAV/iCloud passwords and Google tokens) now use AES-256-GCM, which detects tampering, instead of AES-256-CBC. Existing credentials are upgraded automatically on startup — no need to reconnect calendars
- Credentials that can't be decrypted now show a clear "reconnect this calendar" error instead of silently sending garbage to the calendar server
- New optional CREDENTIALS_ENCRYPTION_KEY setting: set it and SESSION_SECRET can be changed later without reconnecting calendars
- the security audit: new Audit 4 section covering this release series, and corrected outdated statements

### 3.13.1

**Improved**

- Admin → Users: new Sign-in method choice when SSO is configured. SSO accounts need an email (it links their first SSO sign-in) and no password, so they can only sign in through SSO; password accounts now require at least 8 characters
- The user list shows how each person signs in — SSO, SSO + password, or "SSO · awaiting first sign-in" until their first SSO login links the account — and offers "Add password" instead of "Reset pw" for SSO-only accounts
- Creating a user with an email another account already uses now shows a clear message instead of an error page

### 3.13.0

**Fixed**

- Tasks: High-priority tasks sorted to the bottom of Inbox, All and the Today focus list (priority was sorted alphabetically). They now sort High → Medium → Low → None
- Tasks: the bulk-action bar (complete, archive, restore, set priority) failed with an error every time
- Recurring tasks and reminders now create their next occurrence however they're completed — status dropdown, bulk actions and the edit form, not only the complete button
- Reminders: Snooze → Tomorrow ignored your timezone (a 9:00 AM reminder fired at 5:00 AM Eastern) and was relative to the old due date; it now means tomorrow in your timezone
- Reminders: 15-minute and 1-hour snoozes counted from the original reminder time, so snoozing an overdue reminder could set it in the past; they now count from now
- Reminders: recurring reminders lost their tags after the first occurrence
- Reminders: the at-the-time alert now also emails you when email is turned on for Task & reminder alerts, and no longer fires a minute early
- Routines: streaks didn't reset after missed days until you next ticked the routine; they now refresh hourly and after you edit a routine's schedule
- Calendar: events created in Obelo for iCloud/CalDAV or Google showed twice after the next sync
- Calendar: events created in Obelo could silently disappear — after a failed save to the calendar server, or once they were more than ~3 months old. Save failures are now shown on the form
- Calendar: repeating events from iCloud/CalDAV only appeared once (or not at all). Every occurrence now shows, including skipped and moved occurrences
- Calendar: sync now swaps events in all at once, so events no longer blink out during a sync and a failed sync keeps the existing events
- Analytics: routine completion rates could exceed 100% (completions on unscheduled days, and archived routines in the weekly chart, were counted)
- SSO: sign-in now matches an existing account's email regardless of capitalisation
- Backup: JSON restore duplicated everything when run twice and silently skipped reminders, routines, lists, subtasks and locked or handwritten notes. It now restores all of them, including routine history, and skips items you already have
- Notes: bulk-deleting notes now also deletes their attached images
- Weekly slipping-tasks alert now goes out on Monday in your timezone

### 3.12.1

**Security**

- Fixed: any signed-in user could edit, check off or delete items in other people's lists (the item wasn't checked against the list in the request)
- Fixed: any signed-in user could add events to a shared calendar they weren't a member of. Only the owner and members with edit access can now add events
- Fixed: global search displayed result titles as HTML, so a shared list, a sent bookmark or a synced calendar invite could run script in your browser. Results are now shown as plain text
- Fixed: a shared list's title or items could break out of the list page's script and run code for the people it was shared with
- Hardening: calendar event links are only shown for http(s) URLs; uploaded files are served with headers that stop them running script if opened directly; the notes tag picker no longer builds HTML from tag names

**Fixed**

- Submitting the New Event form without a title or date showed an error page instead of the validation message

### 3.12.0

**Changed**

- SSO sign-in no longer creates accounts automatically by default. Someone signing in with SSO who has no Obelo account (matched by SSO identity or email) is turned away with a message to contact the admin. Server admins: create their account under Admin → Users with the same email, or turn on Admin → System Settings → "Create accounts on first SSO sign-in" to restore the old behavior. Existing SSO users are unaffected
- The Admin panel's "Allow new registrations" toggle, which never did anything, is replaced by that SSO setting

**Improved**

- Refused SSO sign-ins are logged with the email and username, so admins can see who tried
- README: new "Ideas for contributors" section describing what a self-service sign-up page would need

### 3.11.1

**Fixed**

- Note images and profile pictures were saved inside the app container instead of the uploads volume, so they were deleted every time the server was updated. They are now stored on the volume and survive updates. Images uploaded before this fix are gone from the server and need to be re-attached
- AI Chat included private notes (title and a short excerpt) in what it sent to the AI provider, despite the Help page saying they were excluded. Private and locked notes are now never sent, and their tags are no longer used as Capture hints either
- A brand-new install failed on first start because the startup script skipped the complete initial database schema. New installs now create the schema correctly; existing installs are unaffected
- Capture and Help no longer say "Claude" now that the AI provider is configurable
- Deleting an account now also deletes that user's note images and avatar, which were previously left behind on disk

**Improved**

- Uploaded files can be encrypted at rest (AES-256-GCM) by setting UPLOADS_ENCRYPTION_KEY, so the storage location only holds unreadable data. Existing files can be encrypted with scripts/encrypt-uploads.js
- The uploads location is configurable with UPLOADS_DIR, e.g. a NAS folder instead of the default Docker volume
- The server logs a clear warning, with the fix, if the uploads folder isn't writable, and logs where uploads are stored and whether they're encrypted
- New README covering what Obelo is, installation, configuration, integrations, backups and updating
- New scripts/backup.sh backs up the database and uploaded files to a folder of your choice (e.g. a NAS) with verification and automatic cleanup of old backups — see Backups in the README

### 3.11.0

**Added**

- AI Chat and Capture can now use the AI provider of the server host's choice: Anthropic (Claude), OpenAI, or any OpenAI-compatible server — including self-hosted local models like Ollama, LM Studio, llama.cpp and vLLM for no-cost AI
- Chat and Capture each have their own model setting (AI_CHAT_MODEL / AI_CAPTURE_MODEL), so a capable model can answer questions while a small, fast one parses captures
- New .env.example documents every server setting with blank placeholders, so a fresh install knows exactly what to fill in
- Optional AI_TIMEOUT_SECONDS (for slower local hardware) and AI_CHAT_MAX_CONTEXT_CHARS (caps how much of your data AI Chat sends, for local models with small context windows)

**Improved**

- Capture asks the model for strict JSON output where the provider supports it, validates the result, and retries once on a malformed reply — much more reliable with smaller models
- When no AI provider is configured, AI Chat and Capture show a clear "AI isn't configured on this server" notice and the quick-capture button is hidden, instead of failing with errors
- The iOS Shortcuts capture endpoint now returns clear JSON error messages for AI failures instead of a generic server error

**Changed**

- Server admins: AI is now configured with AI_PROVIDER, AI_API_KEY, AI_CHAT_MODEL and AI_CAPTURE_MODEL (plus AI_BASE_URL for OpenAI-compatible servers). ANTHROPIC_API_KEY is no longer read — rename it to AI_API_KEY and set AI_PROVIDER=anthropic when upgrading, or AI features will be turned off
- No AI provider or key is set by default — each install configures its own

### 3.10.3

**Fixed**

- A time-limited routine (e.g. a 30-day challenge) would re-archive itself on every single completion after being restored, since the auto-archive check compared total completions to the duration with >=, which stays true forever once first reached — it now only fires once, exactly when the duration is reached
- Routines on a weekly or custom schedule could have their current streak reset to 0, and their best streak permanently capped at 1, any time streaks were recalculated — the "is this streak still alive" and "are these two completions consecutive" checks only understood daily gaps. Streak calculation is now schedule-aware, so it correctly tracks runs across a routine's actual scheduled days instead of assuming every day is scheduled

### 3.10.2

**Fixed**

- All-day calendar events (birthdays, holidays) showed one day early on the Today dashboard and Calendar week/month views for anyone in a timezone behind UTC. All-day events are stored as bare UTC dates and must never be shifted into the viewer's local timezone, unlike timed events — day-bucketing now goes through one shared helper that applies the correct rule per event type so this can't drift out of sync again
- Bookmark tags now suggest from the same app-wide tag vocabulary as Notes/Tasks/Reminders/Routines, instead of only tags already used on bookmarks, and are lowercased/deduplicated the same way on save for consistency

**Added**

- Bookmarks: add and edit forms now show clickable tag suggestions, matching Notes
- Sharing a bookmark, list, or calendar with another Obelo user now shows a suggested list of usernames to pick from instead of requiring the exact username typed blind
- Lists: new "Send as text message" option opens your phone's messaging app with the list title and items pre-filled, no Obelo account needed for the recipient
- Archived routines can now be un-archived: the Archived view has a Restore bulk action, and a single routine can be restored from its detail page
- Tasks now have an Archived view, with a "Restore to inbox" bulk action and per-row status dropdown to bring archived tasks back

### 3.10.1

**Fixed**

- Routine streaks no longer absorb a missed day — a gap immediately resets the streak (previously a hidden grace period counted a 5-day streak ending Jun 30 + Jul 2 as unbroken)

**Added**

- Streak history tracking: every consecutive run is now recorded with start date, end date, and length
- Analytics: routine cards now show total streak count, average streak length, last broken streak date, and top 3 streak spans
- AI chat: streak history is included in routine context so the assistant can accurately answer questions about past streaks

### 3.10.0

**Added**

- Routine completions now record a timestamp (completedAt) in addition to the date — enables time-of-day tracking for habits
- Analytics: "When You Complete Things" time-of-day chart now includes routine completions (previously tasks and reminders only)
- Analytics: Activity heatmap now counts routine completions alongside tasks and reminders
- Analytics: Productivity streak now counts days where any routine was completed, not just tasks and reminders
- Analytics: New "On-time Rate Trend" line chart shows whether your punctuality is improving week over week
- Analytics: Routines section now shows current streak and best streak per routine
- Analytics: Routines with a specific scheduled time show an on-time compliance rate (% completed within 30 min of scheduled time) — builds up as new timed completions are logged
- Analytics: New 8-week routine consistency trend chart shows aggregate weekly completion rate across all active routines
- Analytics: Routine titles link directly to the routine detail page
- AI chat: Routine context now includes best streak and specific-time on-time rate when a scheduled time is set

### 3.9.2

**Fixed**

- Routines Today view showed all items as uncompleted in the evening — the server used UTC dates for completion lookups, so past midnight UTC (but still the same local day) completions were invisible
- Routine streak recalculation used UTC "today" — streaks could incorrectly reset to 0 after completing a routine in the evening for users in UTC- timezones
- Routine heatmap and weekly stats anchored to UTC date instead of user's local date
- Dashboard routine completions and isDueToday filter used UTC date instead of user timezone
- Cron routine notifications checked a single shared UTC date against per-user completion records — could send duplicate alerts or miss completions for users outside UTC
- Analytics day-of-week completion counts used UTC weekday (getUTCDay) instead of the user's local weekday
- Analytics activity heatmap bucketed completions by UTC date instead of local date
- Calendar event times displayed in UTC — formatTime had no timeZone option, so 3 PM local appeared as 8 PM for UTC-5 users
- Calendar events appeared in the wrong day column — startAt timestamps were bucketed by UTC date rather than the user's local date
- New Reminder form pre-filled today's date using UTC (toISOString) instead of the user's local date
- Snooze to tomorrow used local setDate/getDate on a UTC-midnight Date object — could land on the wrong day for non-UTC servers
- AI chat "most productive day" stat used UTC weekday instead of user's local weekday
- AI chat could not answer questions about specific routine completion dates — context only included streak count, not the completion history; now includes the last 30 days of completions per routine

### 3.9.1

**Fixed**

- Sidebar avatar clipped or missing when switching pages — nav flex container was missing min-h-0, allowing it to overflow and push the user section below the viewport
- Service worker no longer intercepts cross-origin requests (Gravatar avatars) — they now go through the browser natively, eliminating latency and intermittent failures
- Bulk actions for Reminders and Routines were silently broken — POST /bulk was registered after POST /:id, causing Express to match "bulk" as an ID param

**Added**

- AMOLED theme — pure #000000 background for OLED screens where black pixels are fully off

**Chore**

- Updated node-cron (4.2 → 4.5), pg (8.21 → 8.22), tsdav (2.2 → 2.3), @anthropic-ai/sdk (0.104 → 0.107)

### 3.9.0

**Added**

- Calendar event editing — events created in Obelo now have an Edit button on their detail page to update title, date, time, location, and notes
- Reminders: tag filter pills below the view tabs to filter by tag
- Reminders: bulk action bar (select checkboxes → Mark complete or Delete)
- Routines: tag filter pills below the view tabs
- Routines: bulk action bar (select checkboxes → Archive or Delete)
- Routines: swipe right on mobile to toggle today's completion — row updates in place without removing from the list
- Bookmarks: bulk delete — check multiple bookmarks and delete them in one action
- PWA: Notes and Reminders added to app shortcuts (long-press the home screen icon)
- PWA: service worker now caches static assets (CSS, JS, icons) for faster repeat loads
- All third-party libraries (HTMX, SortableJS, Chart.js) now served locally — no CDN dependencies remain

### 3.8.6

**Fixed**

- Safari on iOS no longer shows an unstyled page — switched from the Tailwind CDN to a locally served stylesheet, eliminating a WebAssembly CSP restriction that Safari enforces strictly

### 3.8.5

**Added**

- Swipe actions on Notes (mobile): short swipe right = pin/unpin, full swipe right = flag for review, swipe left = delete — hint color transitions between stages
- Swipe actions on Reminders (mobile): swipe right = complete, short swipe left = snooze 1 hour, full swipe left = delete — hint color transitions between stages

### 3.8.4

**Added**

- Underline button added to the Markdown toolbar — wraps selected text in &lt;ins&gt; tags
- Toolbar tooltips now appear instantly on hover instead of after the browser's default delay

**Fixed**

- Clicking a toolbar button no longer causes the editor to jump to the bottom of the text area
- Long unbroken text no longer overflows in the note edit preview panel or on the task detail page
- &lt;ins&gt; tags no longer appear as raw HTML in note card previews on the Notes index page

### 3.8.3

**Fixed**

- Long unbroken text (API tokens, hashes, URLs) no longer overflows outside the note content box when viewing a note

### 3.8.2

**Fixed**

- Locked notes can now be edited after entering the PIN — Edit button appears in the unlocked view and changes are re-encrypted on save

### 3.8.1

**Security**

- Fixed route ordering bug where POST /notes/import was unreachable — note imports now work correctly
- Fixed stored XSS via tag names in tag suggestion buttons across Notes, Tasks, Routines, and Reminders
- Fixed stored XSS via drawing data and tag lists embedded in script blocks
- App now refuses to start if SESSION_SECRET is not set — eliminates hardcoded fallback key risk
- Note lock encryption now uses a separate NOTE_LOCK_SECRET env var, decoupled from the session secret
- File upload filters added — note import accepts only .md files; settings import accepts .md, .json, and .csv
- Admin password reset temp password now delivered via session flash instead of the redirect URL and server logs
- Rate limiting added to PIN unlock and password change endpoints (10 attempts per 15 minutes)
- Rate limiters now apply in all non-development environments — previously skipped in staging and misconfigured prod
- Internal Prisma error details no longer exposed to users in error pages

### 3.8.0

**New**

- Import notes button on the notes list — import .md files directly from the list header without going to Settings
- Notes bulk actions: Add tags and Remove tags — select multiple notes and apply or strip tags in one step, with autocomplete dropdown from your existing tags
- Private note indicator — private notes show an eye-slash icon in the notes list alongside the existing lock, pin, and flag icons
- Note autosave — existing notes save automatically after each pause in editing; a "Saved ✓" indicator appears briefly in the header
- Autosave revert modal — clicking Cancel after an autosave has fired prompts to keep the autosaved version or revert to the state when the note was opened
- Notes settings tab (Settings → Notes) — enable or disable autosave and set the save delay: Immediate (1.5 s), 2 minutes, or 5 minutes

### 3.7.0

**New**

- Handwriting mode for Notes — switch any note to Draw mode to write with Apple Pencil or finger on a lined canvas
- Canvas auto-expands as you write, scrolling indefinitely downward like Apple Notes — no fixed page limit
- Pen tools: 4 colors, 3 sizes, eraser, undo per-stroke, and clear all
- Handwritten notes show a pencil badge and "Handwritten note" preview in the notes list
- Drawing data stored as smooth stroke vectors (not a rasterized image) so content scales correctly on any screen width

**Improved**

- Stroke rendering uses quadratic Bézier midpoint smoothing — curves are smooth even at low Pencil speeds
- iOS long-press callout and text-selection popup suppressed during drawing strokes
- Clear button now works reliably on Brave iOS (confirm() dialog removed — clear is immediate)

### 3.6.0

**New**

- List item reordering — drag active items into any order; uses touch-native drag on mobile with a grip handle on each row
- Order persists across sessions and is shared with other users the list is shared with

**Improved**

- Drag handles across the app now use a consistent 6-dot grip icon (Modules, Dashboard widgets, and List items)
- Settings tabs now scroll horizontally on narrow screens instead of overflowing
- Bookmarks add form stacks vertically on mobile — no more inputs getting cut off on portrait iPhone

### 3.5.0

**New**

- Note locking — lock any note with a 4–6 digit PIN set in Settings → Account; content is AES-256-GCM encrypted at rest and hidden behind a PIN prompt
- Works with all login methods including SSO/OIDC — the lock PIN is independent of how you sign in
- Locking is one-click; unlocking requires the PIN to prove physical presence
- Locked notes show a padlock badge and title in the list; content and search preview are hidden
- Unlock is page-scoped — content shown for the current page load only, re-locks on navigation
- Remove Lock permanently decrypts a note back to normal (PIN required)
- Locked notes are excluded from AI context

### 3.4.2

**Security**

- Third-pass OWASP audit — 6 additional findings, all fixed (17 total across all three passes)
- OIDC nonce check hardened — callback now rejects tokens with no nonce at all, not only on active mismatch
- JS injection via single-quote in confirm() dialogs fixed (admin, calendar, settings) — user-controlled names moved to data-confirm attributes which are safely HTML attribute-encoded
- IDOR on capture draft reject fixed — reject handler now scoped to the current user's drafts
- Password change for OIDC-only accounts now returns a clear error instead of a 500
- Avatar file serving now has the same path-traversal bounds check as note attachments

### 3.4.1

**Security**

- Full OWASP Top 10 / ASVS Level 1 audit (two passes) — 11 findings across both passes, all fixed
- Helmet.js added: Content-Security-Policy, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, and HSTS now sent on every response
- Session fixation fixed — session ID regenerated on every login (local and OIDC)
- XSS fixed in reminder notes and in markdown rendering (marked() output sanitized with the xss package)
- XSS fixed in AI chat error display — SDK exception messages HTML-escaped before injection into HTMX fragments
- Google Calendar OAuth CSRF fixed — random state token generated and validated on callback
- OIDC hardened — nonce claim verified on callback; provider error_description no longer reflected into the login page
- Note attachment path traversal fixed — filename stripped, bounds-checked, and verified against the database before serving
- API token no longer passed in redirect URL — delivered via session flash instead
- Rate limiting: 10 login attempts / 15 min / IP; 30 AI/capture requests / min / IP
- Body parser size cap: 100 KB on all JSON and form requests
- Bulk-action redirects in Notes and Tasks no longer follow the Referer header

### 3.4.0

**New**

- Productivity streak — two new summary cards on the Analytics page: Current streak (consecutive days with at least one completion) and Best streak (longest unbroken run, all-time)
- When You Complete Things — a new time-of-day bar chart showing what hour your completions actually happen, grouped in 2-hour buckets; respects the range toggle
- Late 8+ days age breakdown — average, median, and longest delay for items completed more than 8 days past due; appears inside the By Priority section when relevant data exists
- Completion Velocity — a 12-week line chart (always fixed at 12 weeks) showing completions per week with a trend indicator comparing the last 4 weeks against the prior 4 weeks

### 3.3.1

**Bug fixes**

- Routines analytics: weekly and custom routines now correctly report completion rates — day abbreviations stored in the database ('Tue', 'Wed') were not matching the full names used internally, causing all weekly/custom routines to show "—"
- Routines analytics: expected completion count now starts from the routine's creation date rather than the full 30-day window, so recently created routines show an accurate rate instead of an artificially low one

### 3.3.0

**New**

- Tags for Reminders and Routines — Reminders and Routines now support tags, matching the existing tag support in Notes, Tasks, and Bookmarks
- Global tag registry — tags are now shared across all modules; the picker in any form shows suggestions from your entire tag library
- Tag Manager in Settings → Tags — create new tags, rename a tag across every item that uses it, or delete a tag globally with one click; includes per-tag usage counts
- Inline tag creation — type a new tag name in any tags field to add it on the fly without visiting the manager

### 3.2.1

**Bug fixes**

- Analytics: completion timing is now timestamp-accurate, not just date-accurate — a reminder due at 1:47 PM completed at 6:23 PM the same day no longer counts as "On time"

**Improvements**

- New "Same-day late" timing bucket (yellow) for items completed on the correct calendar day but past the due time — sits between "On time" and "Late 1–3d" in the chart
- Summary cards split into two on-time metrics: Same-day rate (did I get to it today?) and True on-time rate (did I do it within 30 min of when I said?)
- 30-minute grace window applied to "On time" classification to account for the delay between finishing a task and marking it complete
- Priority breakdown now shows both true on-time and same-day rates when they differ
- AI chat context updated with the new bucket breakdown so it can answer "how often do I complete things the right day but past the time?"

### 3.2.0

**New**

- Completion Analytics — a new /analytics page with summary cards (total completed, on-time rate, avg days late, best day of week), a weekly stacked bar chart by timing bucket, priority breakdown, a 12-week activity heatmap, and a routines completion rate sorted worst to best
- AI Chat now includes a compact completion analytics block in its context so it can answer questions like "am I completing tasks on time?" or "which routines am I slipping on?"

**Improvements**

- Keyboard shortcut A navigates to Analytics from anywhere in the app

### 3.1.0

**New**

- Sunset theme — a new warm amber-on-dark theme with a burnt-orange accent

**Improvements**

- All 7 themes (Dark, Midnight, Mocha, Forest, Sunset, Light, Breeze) redesigned from scratch with WCAG AA–compliant contrast ratios across all color pairs
- Theme system now uses CSS custom properties — every semantic role (background, surface, border, text, accent) is defined as a variable, making all themes consistent and maintainable from one place
- Dark theme updated to a richer near-black (#0f1117) with a crisp blue accent (#2563eb)
- Midnight updated to deep indigo with a vibrant violet accent (#7c3aed)
- Mocha rebalanced to a truer coffee-brown palette with an amber-700 accent (#b45309)
- Forest updated with deeper greens and an accessible green-700 accent (#15803d)
- Light and Breeze accent colors corrected for proper white-text contrast on buttons

### 3.0.1

**Bug fixes**

- Fixed overdue/red coloring appearing a day early for users in timezones behind UTC — today comparisons now use the user's local timezone instead of UTC, so a reminder due tomorrow no longer shows as overdue at 8 PM Eastern

### 3.0.0

**New**

- Per-calendar granularity when creating events — the New Event form now lists individual calendars (e.g. "Personal", "Work") from each connected source instead of source-level only; write goes to the exact CalDAV URL or Google calendar ID
- Google Calendar write support — events created in Obelo are now pushed to your actual Google Calendar via the REST API; read-only calendars (freeBusyReader/reader) are automatically filtered from the picker
- Calendar name stored on events — each event records which sub-calendar it was written to or synced from, shown on the event detail page
- Shared Calendars — create Obelo-native shared calendars and invite other users by username; their events appear on your calendar in a distinct color and they can add events visible to all members

**Improvements**

- Events from shared calendars appear in week and month views alongside your own events
- Deleting a shared calendar preserves all its events — events are unlinked (calendar name grayed out) rather than deleted, since the events are the user's real data
- Shared calendar members section on Calendar Sources page with add-by-username and inline remove

### 2.9.0

**New**

- Global Search now covers Lists (title + item text) and Bookmarks (title, URL, description, tags) — bringing the total to 7 modules
- Notes tag search — typing a tag name in global search now matches notes by tag, not just by title or body content

**Fixes**

- Task and Reminder search results now link directly to the item's detail page instead of the list view with a non-functional highlight parameter
- Routine search results now link directly to the matched routine's detail page instead of the index
- Calendar search results now surface upcoming events first (nearest next), falling back to most-recent past — previously sorted newest-first regardless of direction

### 2.8.0

**New**

- Slipping Notes — a new "Slipping" tab in Notes surfaces any note untouched for 30+ days, sorted most stale first, each showing an amber "N days ago" badge instead of the usual date
- Slipping notes also appear in the Today dashboard's "Needs Review" widget with a stale badge, keeping them separate from explicit flag-for-review items

### 2.7.0

**New**

- Routines heatmap — 12-week grid on each routine's detail page showing completed (green), missed (dark), not applicable (faint, e.g. non-Tuesday for a Tuesday-only routine), and future (empty) days
- Completed Streaks — archived time-limited routines that hit their duration goal now appear in their own "Completed Streaks" section under Archived, showing days completed, percentage, and best streak
- Day N/M progress badge on each routine row for active time-limited routines

**Improvements**

- Routine form now uses an Ongoing / Time-limited radio toggle — duration and start date fields only appear when Time-limited is selected, keeping the form clean for the common case
- Heatmap and weekly bar chart correctly skip days that were never scheduled (e.g. weekday-only routines no longer mark weekends as missed)
- isDueToday respects startDate — routines with a future start date no longer appear in Today before they begin

### 2.6.0

**New**

- Time format preference — choose 12-hour (1:30 PM) or 24-hour (13:30) in Settings → Account; 12-hour is the default

**Improvements**

- All time displays in the app now respect the preference: task and reminder due times, calendar events, the dashboard clock, reminder notify timestamps, and search results
- Push and email notifications for due tasks and reminders also use your format preference

### 2.5.0

**Improvements**

- Due-today date color changed from amber to green across tasks, reminders, and the Today dashboard — green now means "on your plate today," red means overdue
- High priority icon updated to three stacked chevrons (↑↑↑), completing the consistent 1/2/3 chevron pattern for low, medium, and high priority

### 2.4.0

**Improvements**

- Priority indicators are now shape-only — completion circle ring and priority icons (↑ / ↑↑ / !) are all neutral gray so they no longer compete with date urgency colors (amber = due today, red = overdue)

### 2.3.0

**New**

- Bookmark sharing — each bookmark now has a share button with three options: send a copy to another Obelo user by username, share via text message (SMS), or copy the link to clipboard

### 2.2.0

**New**

- Expanded recurrence options — Reminders and Tasks now support Hourly, Weekends, Biweekly, Every 3 Months, Every 6 Months, and Yearly presets, plus a Custom option with Frequency × Every N and monthly Each-day or On-the-Nth-weekday sub-options
- Reminder detail page shows a human-readable label for the recurrence rule (e.g. "Every 2 months on day 15") instead of the raw string

**Improvements**

- Mobile bottom bar reorganized — main bar now shows Today, Tasks, Reminders, Lists, and Bookmarks; everything else (Notes, Capture, Routines, Calendar, AI Chat, Settings, Help) moves to the More sheet

### 2.1.0

**New**

- Task & reminder due-time alerts — Pushover and/or email notifications fire 15 min before the due time, exactly at it, and 5 min after if still open
- Toggle and channel configuration in Settings → Notifications alongside the existing digest and slipping-tasks alerts

**How it works**

- Tasks: only fires for tasks with a specific time set (dueTime field). Date-only tasks are still covered by the Monday slipping-tasks alert.
- Reminders: 15-min advance and overdue alerts are new; the at-time push was already present and continues to work.
- Notifications respect your timezone — due times are evaluated in your local time, not server time.

### 2.0.0

**New**

- Six built-in themes — Dark (default), Midnight (deep navy), Forest (earthy green), Mocha (warm amber), Light, and Breeze (cool blue-gray)
- Custom theme builder — pick any accent color and a dark or light base; the accent updates live as you drag the color picker before saving

**Improvements**

- Appearance tab redesigned with mini app previews in each theme card so you can see exactly what you're picking
- App icon section simplified to a single picker (one icon for all modes)
- PWA manifest background_color now reflects your selected theme correctly

### 1.16.2

**Changed**

- iPhone, iPad and Mac: on the public demo, the password section in Settings ▸ Account is hidden.

### 1.16.1

**Changed**

- iPhone, iPad and Mac: on the public demo, the calendar and notification settings say that they aren't available there, instead of offering forms.
- Hosts: works with server 3.56.0, which tells the apps they are on the demo. Older servers behave as before.

### 1.16.0

**Added**

- iPhone, iPad and Mac: when your server is older than the app, the app shows a notice with both versions, and what to update.

**Changed**

- iPhone, iPad and Mac: a new install's sign-in screen starts empty. There is no built-in server address; enter your own.
- The apps' bundle identifiers, App Group and team are set in `ios/Signing.xcconfig`, so anyone can build the code with their own Apple account. The public code carries placeholders only.
- Hosts: no change. Server 3.55.0 or later is needed for the Calendars tab, as before.

### 1.15.2

**Changed**

- Apps: the sign-in screen no longer starts with the maintainer's server address. It starts with a placeholder (`your-server.example`) that you replace with your own server's address.
- Hosts: no change.

### 1.15.1

**Fixed**

- Mac: the colour dot in Settings ▸ Calendars, and every other colour choice, now opens the colour panel every time you click it. Before, it opened only some of the time.

### 1.15.0

**Added**

- iPhone, iPad and Mac: Settings ▸ Calendars. Connect a CalDAV account (Apple iCloud or another server), sync it now, change its colour, choose which of its calendars to sync, and remove it; create, rename, recolour, share (by username) and delete your own calendars; choose the default calendar for new events. It matches the web's Calendar Sources page. Connecting a Google account still needs the web for now; Google accounts you already connected show up and can be managed.
- Hosts: server 3.55.0 must be deployed first.

### 1.14.0

**Changed**

- Mac: clean-up. The Mac app now has only its own screens; the old iPhone screens it used to fall back on are gone from it, and the iPhone files no longer carry Mac code. Nothing should look different on the Mac, iPhone or iPad.
- Mac: VoiceOver reads decorative icons less (they are hidden), a picture that can't load says so, and rows in the Notes tree, the lists and Routines can be selected from VoiceOver.
- Hosts: no server change.

### 1.13.1

**Fixed**

- Mac: the app icon showed the generic one. The app's icon set had only an iPhone icon; it now has the Mac sizes too (the same artwork on a rounded square with the usual margin).
- Mac: your photo now shows in the sidebar's profile block, not only in Settings. It updates when you change or remove it there.

### 1.13.0

**Changed**

- Mac and wide iPad: the sidebar's modules sit in a fixed order inside each group (Do: Tasks, Reminders, Routines; Write: Notes, Lists, Bookmarks), the same as the web, whatever order you had saved. Settings ▸ Modules is only for switching modules on or off there (the rows are listed in the sidebar's order), with no dragging.
- iPhone (and a narrow iPad that shows the bottom bar): Settings ▸ Modules still lets you drag modules into order, since that is the bottom bar's order, and the "Bottom bar" badges stay.

### 1.12.0

**Added**

- Mac: Settings is its own window with a toolbar of tabs (Account, Modules, Notifications, Appearance, Notes, Dashboard, Tags, Shortcuts, Data). Open it with ⌘, or the profile at the bottom of the sidebar. Every card has the web's wording and its own Save button: profile and photo, password, signed-in devices, note lock PIN and deleting your account; modules and dashboard widgets you drag into order (or move with ⌥↑ ⌥↓); Pushover, ntfy and email with the three alert types and the test buttons; themes as cards (the whole app changes as you choose; Save keeps it, closing the window without saving puts the old colours back), custom accent and status colours; handwriting paper, autosave and your note templates; the tag manager; API tokens; exporting and importing your data with the Mac's Save and Open panels.
- iPhone and iPad: a Shortcuts tab in Settings (the web's API tokens: create one and copy it once, see when each was last used, revoke it), with the text for setting up iOS Shortcuts. Hosts: needs server 3.53.0 or newer.

### 1.11.0

**Added**

- Mac: Help is its own window. Open it with Help ▸ Obelo Help (⌘?), the Help link in the sidebar, or the H key; it stays beside your work. The contents are on the left and the section you are reading is marked as you scroll; the text is the server's own help text (the same as the web and the other apps) in your theme's colours. A "Find in Help" box (⌘F in that window) jumps from match to match. The phone-only "Mobile" section is left out, and Keyboard Shortcuts is the Mac's own list. Press `?` from any screen (when you are not typing), or choose Help ▸ Keyboard Shortcuts, for the shortcuts on their own. No server change.

### 1.10.0

**Added**

- Mac: Search is a centred palette over the window, as on the web. Open it with ⌘K, `/` (when you are not typing), the Search box in the sidebar, or Go ▸ Search. Type at least 2 characters; results come in groups (Notes, Tasks, Reminders, Routines, Calendar, Lists, Bookmarks) with the words you typed highlighted. ↑ and ↓ move, Return or a click opens the result inside the app (with Back in the title bar), Esc or a click outside closes. A Calendar result opens that event and a Bookmarks result selects that bookmark. On the Notes screen ⌘K is still Link; use the sidebar, Go ▸ Search or `/` there. No server change.

### 1.9.1

**Fixed**

- Mac: Delete did nothing. Pressing Delete in "Delete this task?" (and the same question for routines, reminders, bookmarks, events, lists, notes, folders, attachments and thoughts) closed the box without deleting anything and without any message. The answer is now passed to the action when the box opens. The "name" box for a new or renamed folder and for Save as template had the same weakness and is hardened the same way. Found by testing the real Delete button on Tasks; the task now goes.

### 1.9.0

**New**

- Help center (/help) — a full user guide covering every module, accessible via the Help link at the bottom of the sidebar
- Capture now supports Lists and Bookmarks — say "grocery list: milk, eggs, bread" or "bookmark github.com/…" and Claude routes it to the right module

**Improvements**

- Keyboard shortcuts updated: D=Today, T=Tasks, B=Bookmarks, ,=Settings (all shown in the ? reference panel)

### 1.9.0

**Added**

- Mac: AI Chat is rebuilt. The thread with bubbles (yours on the right, the AI's on the left), the four suggestions that fill the box without sending, typing dots while a reply is on its way, "N messages remaining today" under new replies, and Clear chat (Edit ▸ Clear Chat…, ⇧⌘⌫, asks first). Return sends, ⇧Return starts a new line, ⌘Return also sends. Copy a message with a right-click or the button that appears when you hover it. A failed send (for example the daily limit) shows the server's words and puts your text back in the box. No server change.

### 1.8.0

**New**

- Swipe actions on mobile — swipe right on any task to mark it complete, swipe left to delete; a colored hint reveals as you drag before committing
- Keyboard shortcut reference — press ? from anywhere (outside an input) to open a panel listing all shortcuts; close with Escape or tap outside

**Fixes**

- Dashboard calendar no longer shows yesterday's all-day events — all-day events store an exclusive end date (e.g. Juneteenth Jun 19 → endAt Jun 20), so the query now correctly uses > instead of ≥

### 1.8.0

**Added**

- Mac: Analytics is rebuilt. "What stands out" (a finding opens its task, reminder, routine or note in the app), the 30d / 90d / All time choice (remembered; View ▸ Show 30 Days, 90 Days, All Time, ⌥⌘1, ⌥⌘2, ⌥⌘3), the summary tiles, and every chart and card the web page has: Completion Timing, On-time Rate Trend, When You Complete Things, By Priority, Activity Heatmap, Completion Velocity and Routines Completion Rate. Charts sit in two columns when the window is wide. Hover a column, point or heatmap day for its numbers. No server change.
- iPhone and iPad: a routine's best past streaks, and "(N logged)" beside a routine's on-time-at-time rate when fewer than five are logged, as on the web.

### 1.7.0

**New**

- Shared lists — share any list with another user on the same instance by username; shared users can add, edit, and check off items in real time
- Lists index splits into "My Lists" and "Shared with me" sections
- List detail shows who the list is shared with; owner can remove access at any time

### 1.6.0

**New**

- Data import (Settings → Data) — import Markdown files as notes (YAML frontmatter supported), tasks from any CSV with a title column, or restore notes/tasks/bookmarks from a Obelo JSON export

### 1.5.0

**New**

- Data export (Settings → Data) — download all your data as JSON, tasks as CSV, notes as JSON, or bookmarks as CSV / browser-importable HTML

### 1.4.0

**New**

- Bookmarks module — save URLs with title, notes, and tags; open in new tab or pop out in a new window

**Improvements**

- Markdown checklist button in Notes and Tasks toolbar — toggles - [ ] ↔ - [x] on selected lines
- Checklist items render as styled checkboxes in note and task detail views
- Task notes field now renders full markdown (same as Notes)

### 1.3.0

**New**

- Task subtasks — add a checklist of subtasks to any task; tick them off inline on the task detail page
- Dashboard customization — choose which widgets appear on Today and drag to reorder them (Settings → Dashboard)

**Improvements**

- Note templates — Blank button now properly clears title, content, and resets type
- Journal template title pre-fills with the current date

### 1.2.0

**New**

- Note attachments — upload images on any note type (Note, Journal, Quote); click to open full-size lightbox
- Admin user creation — create new users directly from Admin → Users without needing the command line
- Account deletion — users can permanently delete their own account from Settings → Account
- Custom avatars — upload a profile photo in Settings → Account; falls back to Gravatar, then initials

### 1.1.0

**New**

- Lists module — create and manage checklists; tick items to mark complete
- Module reordering — drag and drop modules in Settings → Modules to set sidebar order
- Table toolbar button in the Notes markdown editor
- Inline list item editing — click the pencil icon to edit a list item without leaving the page
- Public landing page at / for unauthenticated visitors
- Privacy Policy and Terms of Service pages

**Improvements**

- New modules are now visible by default for existing users (no longer requires re-saving module preferences)
- Switched from db push to proper Prisma migrations for safer production deployments
- Login page branding — added app description and feature tagline
- Google site verification via HTML meta tag

### 1.0.0

**Modules**

- Today dashboard — daily focus: tasks, calendar events, routines, reminders, and resurfaced notes
- Notes — Markdown notes, journal entries, and quotes with tags, pinning, flagging, and thoughts feed
- Tasks — inbox, priorities (none/low/medium/high), due dates, recurring tasks, and today focus
- Reminders — time-based reminders with push notifications and email delivery
- Routines — daily habits with time-of-day grouping and streak tracking
- Calendar — Apple CalDAV and Google Calendar sync, event creation
- Lists — quick checklists for anything
- AI Chat — ask questions about your own data
- Capture — quick-capture FAB available from anywhere in the app

**Platform**

- Self-hosted — fully runs on your own infrastructure via Docker
- Authentication — username/password login, Google OAuth, and Authentik OIDC SSO
- Dark and light theme with per-user preference
- PWA support — installable on desktop and mobile
- Admin panel — user management, system settings, and structured log viewer with CSV export
- API tokens — generate personal access tokens for external integrations
- Gravatar support for user avatars
- Mobile bottom navigation with overflow sheet

## Apps

The iPhone, iPad and Mac apps (`ios/`).

### 1.7.0

**Added**

- Mac: Calendar is rebuilt. The week or the month as a grid (Monday first, today highlighted, coloured event chips, "+N more" in the month), Week and Month, Prev, Today and Next, and New event. Click an event to open it on the right (details, with Edit event and Delete event for the ones you made in Obelo); click a day's number or double-click a day to start an event there; the form has Title, Date, All day, times, Location, Notes and which calendar. Right-click an event or a day for its menu. ⌘N adds, ⌘E edits, ⌘⌫ deletes, ⌥⌘← ⌥⌘→ ⌥⌘T move between weeks or months. The legend with when each calendar last synced and the "No calendars connected" notice show under the grid. Connecting and managing calendars is still on the web only.
- iPhone and iPad: the same "No calendars connected" notice and calendar legend under the week. Hosts: needs server 3.52.0 or newer.

### 1.6.0

**Added**

- Mac: Bookmarks is rebuilt. A table of your bookmarks on the left (site icon, title, address, note, site, tags and when added; click a heading to sort, newest first by default) and the selected bookmark on the right, with Save and Cancel. Filter by typing (title, address, note and tags) or with the tag buttons, select several with ⌘-click or ⇧-click and use "Delete selected", right-click for Open in Browser, Copy Link, Edit, Share and Delete. Return or a double-click opens the link in your browser, ⌘E edits, ⌘F filters, ⌘N adds, ⌘⌫ deletes. Share has Send to Obelo user (with name suggestions), Share via text message, and Copy link.
- iPhone and iPad: "Send to Obelo user" in a bookmark's menu, with name suggestions, like the web's Share box. Hosts: needs server 3.51.0 or newer.

### 1.5.1

**Changed**

- iPhone, iPad and Mac: the Share box now lists everyone you can share with as soon as you open it, like the web, and narrows the list as you type. If the list of people can't be loaded (for example the server is older than 3.50.0), a message says so instead of showing nothing.

### 1.5.0

**Added**

- Mac: Lists is rebuilt. Your lists on the left, the selected list on the right: add items (Return), tick them (click or Space), edit (double-click), delete, and drag the grip to reorder (or ⌥↑ and ⌥↓). The title is editable in place, "Send as text message" opens Messages, and sharing shows name suggestions as you type. ⌘N makes a new list, ⌘⌫ deletes the open one.
- iPhone, iPad and Mac: rename a list (a Rename button on iPhone and iPad), and the Share box suggests people as you type. Hosts: needs server 3.50.0.

### 1.4.0

**Added**

- Mac: the start of a Mac interface built for the Mac, not the iPhone screens. A sidebar with your modules in groups, a menu bar (⌘1 to ⌘9 to jump to a module, ⌘K for search, ⌘N and ⇧⌘N for new items, ⌃⌘S to hide the sidebar) and the website's one-key shortcuts when you aren't typing (D, T, N, C, A, B, H and /).
- Mac: Tasks is rebuilt. The list is on the left and the selected task on the right, edited in place and saved automatically. Select several tasks with ⌘-click or ⇧-click and use the bulk bar, right-click a task for its menu, use the arrow keys, Space, Delete, ⌘↩ (mark complete), ⌘⌫ (delete) and ⌘F (search). Repeat has the usual choices plus custom rules. Task notes show as full Markdown (headings, lists, checklists, quotes, code), as on the website and the iPhone.
- Mac: a new sign-in screen. Username and password, single sign-on, and "Have a setup code?" (the setup-code form opens in the same window), with the server address shown and changeable.
- Mac: Today is rebuilt. The date and clock, then the cards you have switched on in Settings ▸ Dashboard, in your order (My Focus, Today's Events, Due Today & Overdue, Routines, Resurfacing, Needs Review), in two columns when the window is wide. Complete a task or reminder, snooze a reminder, tick a routine or mark a note reviewed from the page, and right-click any row for its menu. Clicking a row opens that item, and Back (⌘[) returns you to Today.
- Mac: Capture is rebuilt. Type anything, choose the type first if you like (Auto lets the AI decide), check the suggestion, and save. The saved item opens and Back returns to Capture. What you typed and an unsaved suggestion stay while you visit another screen, and Today's Quick Capture sends its text here.
- iPhone and iPad: Capture has the same Type row (Auto and the seven types) in place of the example chips. It needs server 3.49.0 or newer to reach the AI; the app also applies your choice itself.
- Mac: Notes is rebuilt. Folders on the left (search, pinned notes, folders that fold shut, drag a note onto a folder, right-click menus), the open note in the middle (a Markdown writing area with a formatting toolbar and a Format menu, Write and Preview), and Details on the right (folder, type, tags, pinned, private, flag for review, Save as template, delete; ⌘⌥I hides it). Everything saves by itself. Handwriting, attachments, locked notes and thoughts come in the next release; until then a handwritten or locked note shows a short message. ⌘K is Link while you are in Notes.
- iPhone and iPad: handwriting paper follows your theme, or is always Dark or White (Settings ▸ Notes ▸ Handwriting paper, shown once your server is on 3.49.0 or newer). The pen colours adjust to the paper, so black-on-white writing works. The Mac follows the setting too; its own Settings window comes later.
- Mac: Notes is complete. Handwriting (a Text | Draw switch, pen colours, sizes, eraser, undo and clear, on the paper from Settings ▸ Notes ▸ Handwriting paper), attachments (the Attach button or drag files from Finder onto the note; images open larger in the app, PDFs and text files in their own app; Save As… and Remove from the right-click menu), locked notes (enter your PIN to open one; Lock from Details) and thoughts. Unlocked notes stay open for the session and there is no Remove lock yet, as on the iPhone and iPad.
- Mac: Reminders is rebuilt. The list on the left and the selected reminder on the right, edited and saved automatically. Tabs (Upcoming, Today, Overdue, Completed) with counts, tag filter, select several with ⌘-click or ⇧-click and Mark complete or Delete them from the bulk bar (needs server 3.49.0 or newer), a Snooze menu on each row (15 minutes, 1 hour, Tomorrow), right-click menus, and a New reminder form that starts with today, the next full hour and "At the due time" and adds the reminder when you press Add reminder. A click on a reminder in Today opens it here. Also: Undo and Clear in the Mac drawing toolbar are text buttons like Eraser.
- Mac: Routines is rebuilt. The list on the left and the selected routine on the right, edited and saved automatically. Today groups your routines by Morning, Afternoon, Evening and Anytime, with "Not due today" below; All and Archived (with Completed Streaks) are flat lists. The routine shows its current and best streak, total completions, a "Mark done for today" button, the 12-week heatmap and weekly completion bars, and every setting (time of day, specific time, frequency and days, ongoing or time-limited, tags, push notification). Tick routines done from the list or with Space, select several with ⌘-click or ⇧-click and archive, restore or delete them from the bulk bar (needs server 3.49.0 or newer), and add a routine from the New routine form. A click on a routine in Today opens it here.
- iPhone, iPad and Mac: note templates. On every app, a tap on "New note" makes a blank note and a press-and-hold (or long click) shows your templates, Settings ▸ Notes has a Note templates card to add, edit and delete them, and a note's details have "Save as template". Needs server 3.49.0 or newer. On the Mac these are in the "+ Note" menu of the new Notes screen and in the Settings screen (still the earlier one).

**Changed**

- Mac: the other modules still show the earlier screens for now, with a quieter title bar and a new Back button (⌘[). Each one gets its own Mac screen in later releases.
- iPhone, iPad and Mac: no visible change. The code the apps share (server connection, data models, sign-in state, note editor rules, the Markdown drawing, Tasks logic) moved into its own folder, ready for the Mac interface rebuild (the Mac app plan).
- Hosts: the Mac Tasks bulk actions need server 3.49.0 or newer. Everything else works with the server you have.

### 1.3.3

**Changed**

- iPhone and iPad: the sign-in button now says "Continue with single sign-on" with a key icon, instead of naming one provider.

### 1.3.2

**Changed**

- iPhone, iPad and Mac apps: Capture works when the server has no AI. It says so, and saves what you type as a note after you review it (needs server 3.46.4 or newer)

### 1.3.1

**Added**

- iPhone, iPad and Mac apps: "Have a setup code?" on the sign-in screen lets a new person enter their username and the code from their admin, choose a password, and sign in (needs server 3.46 or newer)

### 1.3.0

**Added**

- iPhone, iPad and Mac apps: sign in with a username and password, or with SSO. Settings → Account has a card to set or change your password (needs server 3.45 or newer)

### 1.2.0

**Changed**

- iPhone, iPad and Mac apps: the note editor has the web's controls: Text or Draw, Write or Preview, and the Markdown toolbar (headings, bold, italic, lists, checklists, quotes, code, links, rules, tables) that formats what you've selected
- iPhone, iPad and Mac apps: tags work like the web's tag box: tags sit inside one box, a list of your tags drops down as you type, and you can create a new one from there
- iPad and Mac apps: the note's title, save status and Details button sit in the note itself, drawings are made right in the note, and the details panel uses the web's type selector and checkboxes
- iPad app: AI Chat no longer leaves a gap under the input at full width
- Mac app: AI Chat no longer pushes the window's content up, and its input is one line (Return sends)
- Mac app: the strip above each page matches the page colour
