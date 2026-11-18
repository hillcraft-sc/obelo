# Support

Obelo is free software that you run yourself. This page says where to start and where to ask.

## Install

You need a Linux server (or any machine) with Docker and the Docker Compose plugin, and a domain with HTTPS. Sign-in cookies are marked secure in production, so Obelo cannot be used over plain HTTP.

1. Clone the code: `git clone https://github.com/hillcraft-sc/obelo.git`
2. Go into the folder and run `./install.sh`. It asks before each change, creates the settings file with every password and key generated for you, and starts Obelo.
3. Point your reverse proxy (Caddy, nginx, Traefik, Cloudflare Tunnel or similar) at it, and open your address to create the first (admin) account.

The [install guide](https://github.com/hillcraft-sc/obelo#installation) on GitHub has the whole walk-through, including what each optional service is for and what it costs: single sign-on, email, push notifications (Pushover or ntfy), AI, Google Calendar and CalDAV, and nightly backups.

## Update

Pull the new code and rebuild, as the install guide describes. Each release's changes are in the [changelog](https://github.com/hillcraft-sc/obelo/blob/main/CHANGELOG.md), which also says when you need to do something (a new setting, or a backup before an upgrade).

## The apps

The iPhone, iPad and Mac apps are not in the App Store yet. They work with any Obelo server and any sign-in provider: you enter your server's address in the app. They do not send you to the website; every feature works in the app.

## Getting help

- **Something is broken, or you have a question:** open an issue on [GitHub](https://github.com/hillcraft-sc/obelo/issues). Say what you did, what you expected and what happened, and which version you run (it is shown at the bottom of the sidebar). Please leave out passwords, keys and anything private.
- **A security problem:** please don't post it publicly. See [SECURITY.md](https://github.com/hillcraft-sc/obelo/blob/main/SECURITY.md) for the private way to report it.
- **Ideas:** also welcome as issues. The project is built for one person or a small group on their own server, so it is kept small on purpose.

## Backups and your data

Your data lives in your own database. Settings ▸ Data exports it in open formats (JSON, CSV and HTML), and the installer can set up nightly backups. Test a restore before you need one.
