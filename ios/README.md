# Obelo for iOS

A native SwiftUI app for Obelo, laid out like the mobile web app: the same top bar, bottom bar
plus More sheet, cards, and all eight themes plus the custom accent. Requires iOS 27 or later and a
Obelo server running 3.26.0 or later (older servers are missing API endpoints the app uses).

Everything the web app does is in the app; nothing opens the website.

| Area | In the app |
|---|---|
| Today | Your Today cards in your order, quick capture, tick-off, snooze |
| Tasks, Reminders, Routines | Views and filters, create/edit, subtasks, recurrence, snooze, streaks, 12-week heatmap |
| Notes | Markdown, journal and quotes, thoughts, pin/flag, PIN-locked notes, photo attachments (camera or library), handwritten notes (finger or Apple Pencil, same format as the web canvas) |
| Lists, Bookmarks | Sharing, reorder, tags, search |
| Calendar | Week agenda; create, edit and delete events on any calendar you can write to |
| Capture, AI Chat, Search, Analytics | Same as the web (Capture and AI Chat need AI configured on the server) |
| Settings | Every tab: Account (photo, timezone, devices), Modules, Notifications, Appearance, Notes, Dashboard, Tags, Data (export/import, delete account) |
| Help | The web's help text, in the app's theme |

Plus things only the app does:
- **Share sheet** (Share → Obelo): save a bookmark or send text to Capture from any app.
- **Widget**: Today on the home screen or lock screen (small, medium, large), with tick-off buttons.

## How it talks to the server

The app uses the JSON API at `/api/v1` (`src/routes/api.js`). Every feature reuses the web's own
code (shared functions in the web routes), so the app and the web always agree.

Sign-in is the same SSO as the web. The app opens `/auth/oidc?client=ios` in a system sign-in
sheet. After the provider sign-in, the server redirects to `obelo://auth?code=…` with a one-time code
that lasts two minutes (`src/lib/appLogin.js`), and the app trades it for an ordinary session
cookie. The provider redirect URI doesn't change, and the app follows the same idle/7-day limits
as the web; it shows up under Settings → Signed-in devices as "Obelo app on iPhone".

The app, share extension and widget share the sign-in cookie and server address through an App
Group (its name is set in `Signing.xcconfig`, see Signing below).

## Project layout

| Target | Folder | What it is |
|---|---|---|
| Obelo | `Obelo/` | The app. `Core/` (API client, models, theme, formatting), `Components/` (the web's Tailwind patterns as SwiftUI views), `Features/` (one folder per module), `App/` (shell, bottom bar, routing) |
| ObeloShare | `ObeloShare/` + `Features/Share/` | Share extension |
| ObeloWidget | `ObeloWidget/` | Today widget (WidgetKit + an App Intent for tick-off buttons) |

The Xcode project is generated from `project.yml` and isn't committed.

## Building

```bash
brew install xcodegen
cd ios
xcodegen generate          # creates Obelo.xcodeproj from project.yml
open Obelo.xcodeproj
```

To run on a real iPhone, set your team as `DEVELOPMENT_TEAM` in `project.yml` (or under Signing &
Capabilities). Automatic signing registers the App Group for you. The app asks for your server
address on the sign-in screen; it starts with the placeholder `https://your-server.example`, which you replace.

From the command line, with the phone connected:

```bash
xcodebuild -project Obelo.xcodeproj -scheme Obelo -destination 'id=<device id>' \
  -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device <device id> build/Build/Products/Debug-iphoneos/Obelo.app
```

(`xcrun devicectl list devices` shows the device id.) Builds installed this way expire; the first
time, trust the developer under Settings → General → VPN & Device Management on the phone.

## Signing

`Signing.xcconfig` holds the bundle id, App Group and team, with placeholder values, so the code builds
without anyone's Apple account. To sign and install with your own account, create `ios/Signing.local.xcconfig`
(Git ignores it) with your own values, then regenerate the project:

```
OBELO_BUNDLE_ID = com.yourname.obelo
OBELO_APP_GROUP = group.com.yourname.obelo
OBELO_TEAM_ID = YOURTEAMID
```

Then run `xcodegen generate` in `ios/`. The scripts below read the team from these files.

## TestFlight

To send a build to TestFlight (the maintainer's App Store Connect record; see Signing), commit, then:

```bash
ios/testflight.sh            # archive the current commit and upload it
```

The build number is the commit count, so each upload is higher than the last; bump
`MARKETING_VERSION` in `project.yml` for a new version. Xcode must be signed in to the developer
account. Apple takes 5–30 minutes to process a build before testers can install it.
`Obelo/Resources/PrivacyInfo.xcprivacy` is the privacy manifest; keep it in step with the App
Privacy answers in App Store Connect if the app starts sending anything new.

## Keeping the app installed

Apps signed with a free Apple account stop opening 7 days after they're installed (the paid
Developer Program extends that to a year, and TestFlight builds last 90 days). Notifications come
through ntfy/Pushover/email. `install.sh` installs straight from this Mac and can keep it alive:

```bash
ios/install.sh               # build committed `main` and install on your iPhone now
ios/install.sh --schedule    # check at 8:30 and 21:00 daily; reinstall when the install is 5+ days old
ios/install.sh --unschedule  # stop the schedule
```

It builds from a separate checkout of `main` (in `~/Library/Caches/obelo-ios`), so work in
progress is never installed. The phone has to be paired with the Mac and on the same Wi-Fi (or
plugged in). If reinstalling keeps failing and the app is about to expire, you get a Mac
notification. Logs: `~/Library/Application Support/obelo-ios/install.log`.

## Running against a local server (simulator)

The local server has no SSO, so development builds have a "Developer sign-in" button that only
works when the server runs with `NODE_ENV=development` **and** `DEV_APP_LOGIN_USER` is set.
Never set `DEV_APP_LOGIN_USER` on a real server.

```bash
# a local Postgres database, then:
export DATABASE_URL=postgresql://obelo:…@localhost:5432/obelo_dev
export NODE_ENV=development PORT=3100 SESSION_SECRET=dev DEV_APP_LOGIN_USER=demo
npx prisma migrate deploy && node scripts/seed-dev.js && node src/app.js
```

On the sign-in screen, change the server to `http://localhost:3100` and tap "Developer sign-in".

Debug builds take launch arguments for scripted testing (useful with `xcrun simctl launch` and
`xcrun simctl io … screenshot`):

| Argument | Does |
|---|---|
| `-devSignIn YES` | Signs in to the local server on launch |
| `-serverURL http://localhost:3100` | Overrides the saved server address |
| `-startTab tasks` | Opens a tab (any module key) |
| `-route note:3` | Opens a screen: `task:`, `reminder:`, `routine:`, `note:`, `list:`, `event:` + id, `module:<key>`, `search`, `more` |
| `-route share` / `widget` / `draw` | Previews the share sheet, the widget at each size, or the drawing editor |
| `-settingsTab notifications` | Opens a Settings tab |
| `-scrollY 0.5` | Starts scrolling pages part-way down (0 = top, 1 = bottom) |
| `-newEvent YES` | Opens the New Event form on Calendar |
| `-chatSend "question"` | Sends an AI Chat message on open |
