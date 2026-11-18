# Obelo

A self-hosted personal productivity hub. Tasks, notes, reminders, routines, calendar, lists, bookmarks and analytics all live in one web app, with optional AI for natural-language capture and questions about your own data.

Obelo is built for one person or a small group, such as a household, running it on their own server. Your data stays in your own Postgres database. The AI features are optional: you choose the provider, and you can use a local model that never leaves your network.

- **One place for everything:** instead of separate apps for to-dos, notes, habits and calendars, the **Today** dashboard pulls together what matters now.
- **Capture fast:** press `C`, then type or dictate "call the dentist Tuesday 3pm". Obelo turns it into a reminder with the date and time filled in.
- **See your patterns:** analytics show when you actually get things done, how often you hit due times, and how consistent your routines are.
- **Works on your phone:** installable as a PWA, with swipe gestures and a mobile bottom bar. iOS Shortcuts can send captures.

## Screenshots

Taken from the public demo, with made-up data.

| Today | Tasks |
|---|---|
| <img src="assets/screenshots/today.png" alt="The Today dashboard: focus tasks, today's events, what is due and the day's routines"> | <img src="assets/screenshots/tasks.png" alt="The Tasks page with tabs, tags, quick-add and a list of tasks"> |
| **Notes** | **Calendar** |
| <img src="assets/screenshots/notes.png" alt="The Notes workspace: folders, the open note in preview, and its details"> | <img src="assets/screenshots/calendar.png" alt="The Calendar in month view"> |

---

## Contents

- [Features](#features)
- [Tech stack](#tech-stack)
- [Installation](#installation)
- [Configuration](#configuration)
- [Setting up integrations](#setting-up-integrations)
- [Managing your instance](#managing-your-instance) (including [signing in](#signing-in))
- [Local development](#local-development)
- [Ideas for contributors](#ideas-for-contributors)
- [Project structure](#project-structure)
- [External requests and privacy](#external-requests-and-privacy)
- [Security notes](#security-notes)
- [Contributing and security](#contributing-and-security)
- [License](#license)

---

## Features

| Module | What it does |
|---|---|
| **Today** | Dashboard of focus tasks, today's events, due and overdue items, today's routines, a resurfaced note, and notes due for review. Widgets can be reordered. |
| **Capture** | Natural-language quick entry. AI works out whether the text is a task, reminder, note, journal entry, quote, list or bookmark, and fills in the fields for you to review. Supports voice input. |
| **Tasks** | Inbox / Today / Upcoming / Slipping views, priorities, recurring tasks, subtask checklists, due-time alerts, bulk actions. |
| **Notes** | Markdown notes, journal entries and quotes, with tags, pinning, review dates, image attachments, autosave, PIN-locked private notes and handwriting mode. |
| **Reminders** | Timed alerts by push (Pushover or ntfy) and/or email, with snooze, recurrence and tags. |
| **Routines** | Habits scheduled by day and time of day, with streaks, completion heatmaps and time-limited challenges (e.g. 30 days). |
| **Calendar** | Syncs CalDAV (iCloud, Fastmail, Nextcloud, …) and Google Calendar, plus Obelo-native calendars that can be shared with other users. |
| **Lists** | Simple checklists that can be shared with other users. |
| **Bookmarks** | Saved links with tags, search, and HTML/CSV export. |
| **Analytics** | On-time rate, completion timing, time-of-day patterns, activity heatmap, velocity, and routine consistency trends. |
| **AI Chat** | Ask questions about your own data ("what's overdue?", "what did I journal about last week?"). Read-only: it never changes your data. Private and locked notes are never sent. |

It also has global search (`/`), keyboard shortcuts (`?` lists them), six themes plus a custom accent color, per-user module selection and ordering, import/export (JSON backup, CSV, Markdown, browser bookmarks), and an admin panel with user management and logs. The in-app **Help** page (`H`) documents every feature in detail.

## Tech stack

- **Backend:** Node.js 22, Express, EJS server-rendered views with HTMX
- **Database:** PostgreSQL 16 through Prisma (schema migrations in `prisma/migrations`)
- **Styling:** Tailwind CSS 4 (the built CSS is committed in `public/css/tailwind.css`)
- **Scheduling:** node-cron, running inside the app process (reminders, alerts, digests, calendar sync)
- **AI:** Anthropic, OpenAI, or any OpenAI-compatible server (Ollama, LM Studio, vLLM, …) through `src/lib/aiProvider.js`
- **Deployment:** Docker Compose, with an app container and a Postgres container

---

## Installation

### Quick install

On a Linux server, clone the repo and run the installer:

```bash
git clone <your-repo-url> obelo
cd obelo
./install.sh
```

It walks you through everything, asking before each change:
- installs Docker if needed, using Docker's official script
- creates `.env`, with every password and encryption key generated for you
- optionally sets up single sign-on (without it, people sign in with a username and password), AI, email, Pushover and Google Calendar
- optionally sets up a free, locked-down [ntfy](#ntfy-free-self-hosted) server for push notifications
- starts Obelo and tells you where to create your admin account
- schedules and tests nightly [backups](#backups)

It finishes by printing the reverse-proxy entries to add, and which keys to save.

If the installer had to install Docker, it adds you to the `docker` group. That only takes effect at your next login, so until you log out and back in, `docker` commands need `sudo` (the installer uses it for you). Then re-run `./install.sh`: it skips what's done and sets up the nightly backup, which needs Docker without `sudo`. It's safe to re-run, since it skips anything already set up and never overwrites an existing `.env`. `./install.sh --env-only` just creates `.env`.

The rest of this section covers the same steps by hand.

### Requirements

- A Linux server (or any machine) with **Docker** and the **Docker Compose** plugin
- A domain name and a **reverse proxy with HTTPS** (Caddy, nginx, Traefik, Nginx Proxy Manager, Cloudflare Tunnel, …). In production, session cookies are marked `Secure`, so **you can't log in over plain HTTP** when `NODE_ENV=production`.
- Anything else is optional; see the table below.

### Services at a glance

Everything Obelo can use, and whether you need it. Only the first three are required; everything else is turned on by filling in its settings, and stays off otherwise.

| Service | Used for | Needed? | Cost | Set up in |
|---|---|---|---|---|
| Docker + Docker Compose | Running Obelo | **Required** | Free | [Installation](#installation) |
| PostgreSQL 16 | All data | **Required** (bundled in `docker-compose.yml`) | Free | Automatic |
| HTTPS reverse proxy (Caddy, nginx, Traefik, Cloudflare Tunnel, …) | Serving the app over HTTPS; login needs it | **Required** in production | Free options | [Step 4](#4-point-your-reverse-proxy-at-it) |
| SMTP email account | Reminder/alert emails, daily digest, test emails | Optional | Usually free with your mail provider | [Email](#email-smtp) |
| ntfy (self-hosted) + ntfy phone app | Push notifications | Optional | **Free** | [ntfy](#ntfy-free-self-hosted) |
| Pushover + Pushover phone app | Push notifications (alternative to ntfy) | Optional | Paid app, one-time purchase per user | [Pushover](#pushover-paid-app) |
| AI provider: Anthropic, OpenAI, or a local model (Ollama, LM Studio, …) | AI Chat and Capture | Optional | Pay-per-use API, or free with a local model | [AI](#ai-chat-and-capture) |
| OpenID Connect provider (Authentik, Keycloak, …) | An extra way to sign in (single sign-on); usernames and passwords work without it | Optional | Free self-hosted options | [Single sign-on](#single-sign-on-openid-connect) |
| Google Cloud OAuth client | Google Calendar sync | Optional | Free | [Google Calendar](#google-calendar) |
| CalDAV account (iCloud, Fastmail, Nextcloud, …) | Calendar sync | Optional, per user | Free | [CalDAV](#caldav-icloud-fastmail-nextcloud-) |
| iOS Shortcuts | Quick capture | Optional, per user | Free | [iOS Shortcuts](#ios-shortcuts-capture) |
| Backup storage (NAS, second disk, …) | Nightly backups | Strongly recommended | — | [Backups](#backups) |

Some of these make the app contact outside services; see [External requests and privacy](#external-requests-and-privacy).

### 1. Get the code

```bash
git clone <your-repo-url> obelo
cd obelo
```

### 2. Create your `.env`

```bash
cp .env.example .env
```

Open `.env` and fill in at least the **Core** section:

```bash
POSTGRES_PASSWORD=<a strong password>
DATABASE_URL=postgresql://obelo:<same password>@db:5432/obelo
SESSION_SECRET=<run: openssl rand -hex 32>
NOTE_LOCK_SECRET=<run: openssl rand -hex 32>
APP_URL=https://obelo.example.com
NODE_ENV=production
```

Everything else is optional; leave a section blank to disable that feature. See [Configuration](#configuration).

> **`NODE_ENV=production` needs HTTPS.** Session cookies are marked `Secure`, so over plain `http://` you stay signed out, with no error message. To try Obelo on a local network before you have HTTPS, set `NODE_ENV=development` instead. Don't leave a real server in development mode: it turns off rate limiting.

> **Set `NOTE_LOCK_SECRET` once and never change it.** It encrypts PIN-locked notes. If it changes, existing locked notes can't be decrypted. If it's blank, `SESSION_SECRET` is used instead, which then can't be rotated safely either.

### 3. Start it

```bash
docker compose up -d --build
```

(`./install.sh` does this for you. It first tries to download a ready-made image of the latest release, which is faster, and builds from the code if none is available.)

On first start the app container creates the database schema; on later starts it applies any new migrations. It then starts the web server on port **3000** inside the container. Compose publishes that as port **3001** on the host.

Check that it started:

```bash
docker compose logs -f app
```

You should see `Obelo started on port 3000` and a line saying which AI provider is active, or `AI disabled (reason)`. If you see a warning that `/app/uploads` isn't writable, run the one-line fix it prints; otherwise note images and avatars can't be saved.

### 4. Point your reverse proxy at it

Proxy your domain to `http://<server>:3001` (or your `APP_PORT`). Example with Caddy:

```
obelo.example.com {
    reverse_proxy localhost:3001
}
```

With **Cloudflare Tunnel**, add a public hostname for your domain with service type `HTTP` and URL `<server-ip>:3001`, in the Cloudflare dashboard (Zero Trust → Networks → Tunnels → your tunnel → Public Hostname) or as an `ingress` rule in the tunnel's `config.yml`. The tunnel provides HTTPS, so no certificates are needed on your server.

If `cloudflared` runs in Docker **on the same host**, it can reach Obelo over a shared Docker network instead, and the app's port can stay closed to your LAN:

1. Create the network once, and attach your `cloudflared` container to it: `docker network create tunnel`
2. Copy the example override, which adds the app to that network as `obelo`: `cp docker-compose.override.example.yml docker-compose.override.yml`. Compose merges it automatically, and it's git-ignored, so `git pull` never touches it.
3. In `.env`, set `APP_PORT=127.0.0.1:3001`, so the published port only answers on the server itself.
4. Run `docker compose up -d app`, then route the tunnel's public hostname to `http://obelo:3000`.

The app trusts one proxy hop (`trust proxy = 1`), so the proxy must send the usual `X-Forwarded-*` headers. Caddy, nginx, Traefik and Cloudflare Tunnel all do by default.

### 5. Create the first admin account

Open your `APP_URL` in a browser. A new server shows a one-time setup page: choose a username, a name, an optional email and a password (at least 10 characters). That account becomes the admin and is signed in. The page disappears as soon as the first account exists, so it can't be used to take over a running server.

Then add everyone else under **Admin → Users**; see [Signing in](#signing-in). Single sign-on is optional and can be added any time ([see below](#single-sign-on-openid-connect)).

Rather make an account that signs in through SSO the admin? Set SSO up first, then run `docker compose exec app node scripts/make-admin.js <email>` with the email of the account at your identity provider. If no account has that email, the script creates one. That account has no password: its first SSO sign-in links to it.

---

## Configuration

All configuration lives in `.env`. `.env.example` is the complete, commented list. The app reads `.env` at startup, so restart after changing it: `docker compose up -d app`.

### Core

| Variable | Required | Description |
|---|---|---|
| `POSTGRES_PASSWORD` | yes | Password for the bundled Postgres container |
| `DATABASE_URL` | yes | Prisma connection string; the host is `db` inside Compose |
| `SESSION_SECRET` | yes | Signs session cookies. The app refuses to start without it. |
| `APP_URL` | yes | Public base URL; used for links in emails and OAuth callback URLs |
| `NODE_ENV` | yes | `production` (secure cookies, rate limits on) or `development` |
| `PORT` | no | Port inside the container (default `3000`) |
| `APP_PORT` | no | Port Obelo is published on, on the server (default `3001`); point your reverse proxy here. Add a bind address to limit who can reach it, e.g. `127.0.0.1:3001` for the server only |
| `NOTE_LOCK_SECRET` | recommended | Encryption key for locked notes (falls back to `SESSION_SECRET`) |
| `CREDENTIALS_ENCRYPTION_KEY` | recommended | Encryption key for stored calendar passwords and Google tokens (falls back to `SESSION_SECRET`). Lets you change `SESSION_SECRET` without reconnecting calendars |
| `SESSION_IDLE_HOURS` | no | Sign out after this many hours without using the app (default `12`). Each request restarts the clock |
| `SESSION_MAX_DAYS` | no | Sign out this many days after signing in, however active (default `7`) |
| `APP_SESSION_DAYS` | no | How long the iOS app stays signed in, used for both limits above instead (default `90`) |
| `LOG_LEVEL` | no | `debug`, `info` (default), `warn` or `error` |

### Uploaded files

Note images and avatars are stored outside the container, so they survive updates.

| Variable | Description |
|---|---|
| `UPLOADS_DIR` | Host location for uploads. Blank = the `uploads` Docker volume. Set an absolute path to use a host folder instead, such as a NAS mount. |
| `UPLOADS_ENCRYPTION_KEY` | Encrypts every uploaded file at rest (AES-256-GCM). Generate with `openssl rand -hex 32`. **Recommended**, and strongly recommended on a network share. |
| `UPLOAD_PATH` | Path inside the container (default `/app/uploads`). Only change it when running without Docker. |

**Recommended:** keep the default, a Docker volume on the server's own disk, and back it up to a NAS or other storage with `scripts/backup.sh` ([see Backups](#backups)). The app then keeps working when the NAS is offline, and uploads stay on the same disk as the database.

**Using a NAS or other host folder instead:** set, for example, `UPLOADS_DIR=/mnt/nas/obelo_userfiles`, then recreate the app container (`docker compose up -d app`). The folder must be writable by **UID 1001**, the app's user inside the container. On an NFS share with root squash, change the owner on the NAS itself. If the share goes offline, uploads and image views wait until it's back.

**About encryption:** with `UPLOADS_ENCRYPTION_KEY` set, the storage location only ever holds unreadable data. That protects files from anyone who can read the NAS, its snapshots or its backups, but not the server. The key lives in the server's `.env`, so it doesn't hide files from whoever runs the server. **Set the key once and back it up with your `.env`.** Changing or losing it makes existing uploads unreadable. To turn encryption on for an install that already has files, set the key, restart, then run once:

```bash
docker compose exec app node scripts/encrypt-uploads.js
```

### AI (Chat and Capture)

AI is **off until you configure it**. There is no built-in key: each install uses its own provider and account.

| Variable | Description |
|---|---|
| `AI_PROVIDER` | `anthropic`, `openai` or `openai-compatible`. Blank = AI disabled. |
| `AI_API_KEY` | Provider API key. Optional for most local servers. |
| `AI_BASE_URL` | Required for `openai-compatible`, e.g. `http://192.168.1.50:11434/v1` for Ollama |
| `AI_CHAT_MODEL` | Model for AI Chat; a capable model works best |
| `AI_CAPTURE_MODEL` | Model for Capture; a small, fast model is fine (defaults to the chat model) |
| `AI_CHAT_DAILY_LIMIT` | Per-user daily AI Chat message cap (default `50`) |
| `AI_TIMEOUT_SECONDS` | Request timeout (default `120`); raise it for slow local hardware |
| `AI_CHAT_MAX_CONTEXT_CHARS` | Optional cap on how much of the user's data AI Chat sends |

Example configurations:

```bash
# Anthropic (Claude)
AI_PROVIDER=anthropic
AI_API_KEY=sk-ant-...
AI_CHAT_MODEL=claude-sonnet-5
AI_CAPTURE_MODEL=claude-haiku-4-5

# OpenAI
AI_PROVIDER=openai
AI_API_KEY=sk-...
AI_CHAT_MODEL=<chat model>
AI_CAPTURE_MODEL=<small model>

# Local model with Ollama (no cost beyond your own hardware)
AI_PROVIDER=openai-compatible
AI_BASE_URL=http://192.168.1.50:11434/v1
AI_CHAT_MODEL=llama3.1:8b
AI_CAPTURE_MODEL=llama3.1:8b
```

**Tips for local models:**

- **The Obelo server makes the call, not your browser.** The model server must be reachable from the app container. Inside the container, `localhost` means the container itself. For a model on the Docker host, use `http://host.docker.internal:<port>/v1`; Compose maps that name for you. For another machine, use its LAN IP.
- **Raise the model's context window.** AI Chat sends a summary of your tasks, notes, calendar and routines with every question. Ollama's default context is small and **silently cuts off** anything that doesn't fit. Set `OLLAMA_CONTEXT_LENGTH=32768` (or `num_ctx` in a Modelfile); in LM Studio, raise "Context Length" in the model's load settings. If you can't, set `AI_CHAT_MAX_CONTEXT_CHARS`.
- **Capture needs clean JSON.** Obelo asks for strict JSON output where the server supports it, checks the result, and retries once. Very small models can still struggle; pick a stronger `AI_CAPTURE_MODEL` if captures fail often.

---

## Setting up integrations

Each integration is optional. Leave its variables blank to turn it off.

### Email (SMTP)

Used for reminder and alert emails and the daily digest. Set `SMTP_HOST`, `SMTP_PORT` (default `587`), `SMTP_SECURE` (`true` for port 465), `SMTP_USER`, `SMTP_PASS` and `SMTP_FROM`. Each user picks their email channels in **Settings → Notifications** and can send a test.

### Push notifications

**Dry run.** Outside production (`NODE_ENV` not `production`) Obelo does not send push or email: it writes "would send…" to the log. This protects a development server pointed at real settings, because the scheduler sends missed alerts when it starts. Production installs send normally. Set `NOTIFICATIONS_DRY_RUN=true` or `false` to force either way. The test buttons in Settings always send.

Obelo supports two push services; enable either or both. Each user picks which channels each alert type uses in **Settings → Notifications**.

#### ntfy (free, self-hosted)

[ntfy](https://ntfy.sh) is an open-source push notification server with free [iOS](https://apps.apple.com/app/ntfy/id1625396347) and [Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy) apps. Self-hosted next to Obelo, it costs nothing for any number of users, and notifications never pass through a third party (on iPhone, only a wake-up signal does; see the `upstream-base-url` note below).

**What you need:** a subdomain for ntfy (e.g. `ntfy.example.com`) routed through your HTTPS reverse proxy, and a free port on the server (2586 below).

**1. Run ntfy as its own Compose project**, separate from Obelo so each can be updated independently:

```bash
mkdir ~/ntfy && cd ~/ntfy
```

`~/ntfy/compose.yml`:

```yaml
services:
  ntfy:
    image: binwiederhier/ntfy
    command: serve
    restart: unless-stopped
    ports:
      - "2586:80"
    volumes:
      - ./server.yml:/etc/ntfy/server.yml:ro
      - cache:/var/cache/ntfy
      - lib:/var/lib/ntfy
    healthcheck:
      test: ["CMD-SHELL", "wget -q --tries=1 http://localhost:80/v1/health -O - | grep -Eo \"\\\"healthy\\\"\\s*:\\s*true\" || exit 1"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 20s

volumes:
  cache:
  lib:
```

`~/ntfy/server.yml`:

```yaml
base-url: "https://ntfy.example.com"
behind-proxy: true
cache-file: "/var/cache/ntfy/cache.db"
cache-duration: "12h"
auth-file: "/var/lib/ntfy/user.db"
# Nobody can publish or read unless allowed (set up in step 2)
auth-default-access: "deny-all"
# Required for instant notifications on iPhone: ntfy.sh relays a wake-up signal through
# Apple's push service. Only a message ID passes through ntfy.sh, never the content.
upstream-base-url: "https://ntfy.sh"
```

```bash
docker compose up -d
curl http://localhost:2586/v1/health        # → {"healthy":true}
```

**2. Lock it down so only Obelo can publish.** An open ntfy server lets anyone on the internet send notifications through it. These rules let Obelo publish to its topics (which all start with `vt-`) and let phones subscribe to them, and deny everything else:

```bash
docker compose exec -e NTFY_PASSWORD="$(openssl rand -hex 24)" ntfy ntfy user add --role=user obelo
docker compose exec ntfy ntfy access obelo 'vt-*' write-only
docker compose exec ntfy ntfy access everyone 'vt-*' read-only
docker compose exec ntfy ntfy token add obelo      # prints tk_… — Obelo's publish token
```

The password is random and never needed; Obelo uses the token.

**3. Route the subdomain to ntfy** through your reverse proxy, the same way as Obelo but to port `2586`. For example, a Cloudflare Tunnel public hostname `ntfy.example.com` → `HTTP` → `<server-ip>:2586`, or with Caddy:

```
ntfy.example.com {
    reverse_proxy localhost:2586
}
```

Don't put a login page in front of it (e.g. Cloudflare Access): the ntfy app can't get past one, and step 2 already protects the server. Check it from outside with `curl https://ntfy.example.com/v1/health`.

**4. Point Obelo at it**, in Obelo's `.env`:

```bash
NTFY_URL=https://ntfy.example.com
NTFY_TOKEN=tk_…                      # the token from step 2
```

then `docker compose up -d app` in the Obelo folder.

**5. Each user subscribes on their phone:**

1. Install the ntfy app and allow notifications.
2. In Obelo, **Settings → Notifications**: check **Enable ntfy** and save. Obelo creates a private topic for that user and shows it with the server address.
3. In the ntfy app, tap **+**, enter the topic, turn on **Use another server**, enter the server address, and subscribe.
4. Tap **Send test ntfy notification**, then tick **ntfy** on the alert types that should use it. Reminders and routine alerts go to every push channel that's enabled.

Topics are random and unguessable, and work like a password for reading someone's notifications. **New ntfy topic** replaces one that was shared by mistake.

**Updating ntfy:** `cd ~/ntfy && docker compose pull && docker compose up -d`.

**Troubleshooting**

- *Test fails with "Couldn't reach the ntfy server":* check `NTFY_URL` and `NTFY_TOKEN` in Obelo's `.env`, then `docker compose logs app | grep ntfy`. A `403` means the token or the step 2 access rules are wrong.
- *Test succeeds but nothing arrives on an iPhone:* make sure `upstream-base-url: "https://ntfy.sh"` is in `server.yml` (restart ntfy after changing it), and that the app subscribed with **Use another server** set to your server.
- *A brand-new subdomain doesn't resolve yet:* DNS can take a few minutes, and a device that looked it up too early may cache "not found" for a while.

#### Pushover (paid app)

1. Create an application at [pushover.net](https://pushover.net) and put its token in `PUSHOVER_APP_TOKEN`.
2. Each user pastes their own Pushover **user key** in **Settings → Notifications**.

### Single sign-on (OpenID Connect)

Single sign-on is optional. It adds a button to the login page and works with Authentik or any OpenID Connect provider that supports discovery. Password sign-in stays available unless an admin switches it off in **Admin → System Settings** (possible only while SSO is set up, so you can't lock everyone out).

1. Create an OAuth2/OpenID provider and application. Set the redirect URI to `https://<your domain>/auth/oidc/callback`.
2. Set `OIDC_ISSUER` (the provider's issuer URL), `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET`. `OIDC_REDIRECT_URI` is only needed to override the default of `APP_URL/auth/oidc/callback`.
3. The login page then shows the single sign-on button.

Earlier versions used `AUTHENTIK_ISSUER`, `AUTHENTIK_CLIENT_ID`, `AUTHENTIK_CLIENT_SECRET` and `AUTHENTIK_REDIRECT_URI`. Those names still work and the server logs a warning at start-up; rename them in `.env` when convenient.

When someone signs in with SSO for the first time, Obelo links them to the existing account with the same email address. If there's no such account:

- **By default, they're turned away** with a message asking them to contact the admin. To add someone, create their account under **Admin → Users** with the same email as their SSO account. Their first SSO sign-in links to the account, and the user list shows *SSO · awaiting first sign-in* until it does.
- To let SSO create accounts automatically instead, turn on **Admin → System Settings → Create accounts on first SSO sign-in**. Anyone your identity provider lets through then gets an account, so limit access to the Obelo application in the provider itself.

### Google Calendar

1. In Google Cloud Console, create an OAuth client of type *Web application* and enable the Google Calendar API.
2. Add the authorized redirect URI `https://<your domain>/calendar/auth/google/callback`.
3. Set `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.
4. Users connect their account from **Calendar → Sources → Add source**.

If Google asks you to verify your domain (for the consent screen), put the token it gives you in `GOOGLE_SITE_VERIFICATION`; Obelo adds it to every page as a `<meta>` tag.

### CalDAV (iCloud, Fastmail, Nextcloud, …)

No server configuration is needed. Each user adds a source in **Calendar → Sources** with the server URL and credentials. For iCloud, use an app-specific password. Calendars sync every 15 minutes, or on demand with **Sync now**.

### iOS Shortcuts: Capture

Both endpoints authenticate with a personal API token. Create one in **Settings → Shortcuts** (it's shown only once) and send it as `Authorization: Bearer <token>`.

- **Capture:** `POST /capture/api` with JSON `{ "raw": "call the dentist tuesday 3pm" }`. The response contains the draft for you to confirm in the app.

---

## Managing your instance

### Admin panel

Users with the admin role see **Admin** in the app (`/admin`):

- **Users:** create accounts, issue one-time password links and setup codes, grant or revoke admin, delete users
- **Logs:** view, filter, export and clear the application log
- **System settings:** whether SSO sign-ins can create new accounts (off by default, [see above](#single-sign-on-openid-connect)), whether password sign-in is allowed (on by default, can be turned off only while SSO is set up), and a maintenance message shown to all users

### Signing in

- **Adding someone:** **Admin → Users → Create User**. Leave the email empty for a password-only account. Obelo shows a **setup code** (like `K7QM-X2ND`) and a one-time link, once. Give them the username and the code (or the link). They choose their own password, on the login page's **Have a setup code?**, in the app's sign-in screen, or by opening the link. Either one works once and expires after 24 hours. Admins never see or choose anyone's password.
- **Forgotten password:** **Admin → Users → Reset password** issues a new code and link and signs that person out everywhere once they use it. Anyone signed in can change their own password in **Settings → Account**, which signs out their other devices.
- **Locked out (even the admin):** on the server, `docker compose exec app node scripts/set-password.js <username or email>`. It asks for the new password, and signs that account out everywhere.
- **Protection:** passwords are stored as bcrypt hashes. Sign-in is rate-limited per IP, an account is locked for 15 minutes after 10 wrong passwords, and setup codes get the same limit. There's no second factor for passwords; for MFA or passkeys, use SSO and switch password sign-in off.

### Updating

Before you update, take a backup (see [Backups](#backups)) and read the [`CHANGELOG.md`](CHANGELOG.md) entries newer than your version. Anything you need to do is a bullet that starts with "Hosts:". For example, 3.11.0 replaced `ANTHROPIC_API_KEY` with the `AI_*` settings. Then:

```bash
cd obelo
git pull
docker compose build app
docker compose up -d app
```

Migrations run automatically when the container starts.

To download the ready-made image of the latest release instead of building it, use `docker compose pull app` in place of `docker compose build app`. The image is the last tagged release, so if you follow `main` between releases, keep building.

### Backups

Back up two things: **the database** and **uploaded files** (note images and avatars). Both live on the server's own disk, in Docker volumes (unless you set `UPLOADS_DIR`), and a volume is a single copy. `scripts/backup.sh` backs up both in one go:

```bash
scripts/backup.sh /mnt/nas/obelo_backups
```

It writes `obelo-db-<date>.sql.gz` (a consistent `pg_dump` snapshot, safe while the app is running) and `obelo-uploads-<date>.tgz`. It checks both files are readable, and deletes backups older than 14 days (change with `BACKUP_KEEP_DAYS`). The backup folder must already exist. If it's a network share that isn't mounted, the script fails instead of filling the local disk.

Run it nightly with cron (`crontab -e` as a user in the `docker` group):

```
15 3 * * * /path/to/obelo/scripts/backup.sh /mnt/nas/obelo_backups >> $HOME/obelo-backup.log 2>&1
```

Check `~/obelo-backup.log` now and then. A failed run ends with a line containing `ERROR`. To get a push notification when a backup fails, set `PUSHOVER_APP_TOKEN` and `BACKUP_ALERT_PUSHOVER_USER` (your Pushover user key) in `.env`.

**Not included: `.env`.** It holds your secrets, so keep a copy somewhere safe and separate from the backups, such as a password manager. Without the same `NOTE_LOCK_SECRET`, locked notes in a restored database can't be opened. Without the same `UPLOADS_ENCRYPTION_KEY`, encrypted uploads can't be opened, and without the same `CREDENTIALS_ENCRYPTION_KEY` (or `SESSION_SECRET`), connected calendars need to be reconnected. Individual users can also download a full JSON export of their own data from **Settings → Data**.

#### Restoring

Restore onto a fresh install, or after removing the old volumes with `docker compose down -v`, which **deletes the current data**. Put your saved `.env` in place first, then:

```bash
docker compose up -d db
gunzip -c obelo-db-YYYY-MM-DD_HHMM.sql.gz | docker compose exec -T db sh -c 'psql -U "$POSTGRES_USER" "$POSTGRES_DB"'
docker compose run --rm -T --entrypoint sh app -c 'tar xzf - -C /app/uploads' < obelo-uploads-YYYY-MM-DD_HHMM.tgz
docker compose up -d
```

Start only the database first, so the app doesn't create an empty schema before the restore. Test a restore once, e.g. on another machine, so you know your backups work.

This procedure was tested end to end on 2026-11-14: a backup of a seeded install (a user with a password, a note, an encrypted upload) was restored into a second, empty install using only the commands above. The user, note, upload and password all came back, the app started, and no migration was pending. The restored `.env` must hold the same `UPLOADS_ENCRYPTION_KEY`, `NOTE_LOCK_SECRET` and `CREDENTIALS_ENCRYPTION_KEY` as the original, or uploads and locked notes can't be opened.

### Admin scripts

These run inside the app container:

```bash
docker compose exec app node scripts/make-admin.js <email or username>   # promote a user, or create a new admin (an SSO account: no password)
docker compose exec app node scripts/set-password.js <username or email>  # set a new password for a locked-out account
docker compose exec app node scripts/recalc-streaks.js                   # recompute all routine streaks
docker compose exec app node scripts/encrypt-uploads.js                  # encrypt existing uploads after setting UPLOADS_ENCRYPTION_KEY
```

### Logs and health checks

```bash
docker compose logs -f app       # application output, including scheduler and AI errors
docker compose ps                # container status (Postgres has a health check)
```

Set `LOG_LEVEL=debug` in `.env` for more detail. The admin **Logs** page shows the same application log in the browser.

### Background jobs

The scheduler runs inside the app process, so no extra service is needed. It remembers the last minute it processed, so notifications that fall due while the app is restarting (e.g. during an update) are sent as soon as it's back, for outages up to 15 minutes:

- **Every minute:** due reminders, routine notifications, task and reminder due-time alerts, daily digests, and on Mondays the slipping-tasks summary
- **Every 15 minutes:** calendar sync for all connected sources

---

## Local development

Requirements: Node.js 22+ and a PostgreSQL 16 database.

```bash
npm install
cp .env.example .env
# Set DATABASE_URL to your local database (e.g. postgresql://obelo:pass@localhost:5432/obelo),
# SESSION_SECRET to any string, and NODE_ENV=development (so login works over http://).
# SSO is optional; to use it, set the OIDC_* settings with http://localhost:3000/auth/oidc/callback as the redirect URI
node scripts/baseline-migrations.js # on an empty database, record the existing migrations first
npx prisma migrate deploy          # create the schema
npm run dev                        # start with auto-reload on http://localhost:3000
                                   # then open it and create your first (admin) account on the setup page
npm run watch:css                  # in a second terminal, if you change Tailwind classes
```

Other scripts:

| Command | Purpose |
|---|---|
| `npm run build:css` | Build the minified Tailwind CSS (commit the result) |
| `npm run db:migrate` | Create a new migration after changing `prisma/schema.prisma` |
| `npm run db:generate` | Regenerate the Prisma client |
| `npm run db:studio` | Browse the database in Prisma Studio |
| `npm test` | Run the server tests against a throwaway Postgres (starts one in Docker; or set `TEST_DATABASE_URL` to a database whose name ends in `_test`: the tests empty its tables) |

In development, rate limits are disabled and cookies aren't marked `Secure`.

## Ideas for contributors

Features that are deliberately not built, but would fit if you want to extend your own copy:

### Self-service sign-up

Obelo has no registration page. Accounts come from an admin (**Admin → Users** or `scripts/make-admin.js`) or, if enabled, from the first SSO sign-in. If you use SSO, a natural place for self-service sign-up is the identity provider: an enrollment flow in Authentik (ideally with email verification and an invite or approval step), combined with **Admin → System Settings → Create accounts on first SSO sign-in**. On the Obelo side, a contributor might add:

- **Admin visibility.** A notification to admins when SSO creates a new account (it's already logged with `logService`; see the OIDC callback in `src/routes/auth.js`).
- **New-user defaults**, such as enabled modules and timezone for SSO-created accounts. Follow what the admin's `POST /admin/users/create` in `src/routes/admin.js` does today.

## Project structure

```
src/
  app.js            Express app: middleware, rate limits, routes, startup
  routes/           One router per module (tasks, notes, calendar, capture, ai, admin, …)
  services/         Business logic: AI chat, capture, CalDAV/Google sync, cron, email, Pushover, ntfy, logging
  lib/              Shared helpers: Prisma client, AI provider adapter, note and upload encryption, tags, dates
  middleware/       Auth and per-user module loading
  config/modules.js Module registry (navigation, labels, icons)
  views/            EJS templates (layouts, partials, one folder per module)
prisma/             Database schema and migrations
public/             Static assets: CSS, icons, client-side JS, PWA files
scripts/            Admin and maintenance scripts (backup, admin creation, streaks, encryption)
install.sh          Interactive installer
docs/               Support and privacy pages
```

Support and privacy: [obelo.hillcraft-sc.com/support](https://obelo.hillcraft-sc.com/support) and [obelo.hillcraft-sc.com/privacy](https://obelo.hillcraft-sc.com/privacy).

## External requests and privacy

Your data lives in your own database, but some features contact outside services. None are needed for the core app.

| When | Service contacted | What it learns |
|---|---|---|
| A user has no uploaded profile picture | **Gravatar** (from the browser) | A hash of the user's email address |
| Viewing Bookmarks | **DuckDuckGo** icon service (from the browser) | The domains of bookmarked sites |
| AI Chat / Capture, if an AI provider is configured | Your AI provider (from the server) | The question or captured text, plus a summary of the user's data for AI Chat (excluding private and locked notes). Use a local model to keep this in-house |
| Calendar sync, if connected | Google, iCloud or your CalDAV server | Normal calendar access for that account |
| Push notifications | Pushover, or your own ntfy server | The notification text. With a self-hosted ntfy, iPhones also receive a wake-up signal relayed via ntfy.sh (message ID only) |
| Emails | Your SMTP provider | The email content |

Users can avoid the Gravatar request by uploading a profile picture. Obelo's security policy allows scripts only from the app itself, so if you put it behind a proxy that injects a script (for example Cloudflare Web Analytics), the browser blocks that script. Turn that feature off.

## Security notes

- **The server owner can access all user data.** As with any self-hosted app, whoever runs the server controls the database, the `.env` secrets and the code. That includes the key for locked notes, and the key for uploaded files. Only host accounts for people who trust you, and tell them so.
- **Run it behind HTTPS.** Production mode requires it for login.
- **Sessions expire** after `SESSION_IDLE_HOURS` without use (default 12) and `SESSION_MAX_DAYS` after sign-in (default 7), whichever comes first. The iOS app's sign-in lasts `APP_SESSION_DAYS` (default 90) instead, since the phone has its own lock.
- Each user can see their signed-in devices in **Settings → Account** and sign any of them out. The IP shown there is display-only and comes through `trust proxy`, so it's the real client address only if your reverse proxy sets `X-Forwarded-For`.
- **No MFA for passwords.** Password sign-in is a bcrypt-hashed password with rate limiting and per-account lockout, and no second factor. For MFA or passkeys, use SSO and switch password sign-in off.
- **Keep `.env` out of version control.** It's ignored by `.gitignore`; only `.env.example`, with blank values, is tracked.
- PIN unlock, Capture and AI endpoints are rate-limited per IP. AI Chat also has a per-user daily limit.
- Locked notes are encrypted at rest with AES-256-GCM using a key derived from `NOTE_LOCK_SECRET`. The PIN controls access in the app; it isn't part of the key.
- Uploaded files are encrypted at rest with AES-256-GCM when `UPLOADS_ENCRYPTION_KEY` is set. Each file is bound to its own path, so files can't be swapped between users. Deleting a note or an account deletes its files.
- Calendar passwords and Google tokens are encrypted at rest with AES-256-GCM using `CREDENTIALS_ENCRYPTION_KEY` (or `SESSION_SECRET`).
- API tokens are stored as SHA-256 hashes and shown to the user only once.
- AI Chat sends a summary of the asking user's data to the configured AI provider, excluding private and locked notes. If that matters to you, use a local model.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to run it locally, run the tests and send a change. Report a vulnerability privately as described in [SECURITY.md](SECURITY.md).

## License

Obelo is licensed under the [GNU General Public License v3.0](LICENSE).
