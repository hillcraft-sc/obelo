# Security policy

Obelo is a self-hosted app. Whoever runs a server controls its data, so most hardening advice is in the [Security notes](README.md#security-notes) of the README. This page is about reporting a problem in Obelo's own code.

## Reporting a vulnerability

Please don't open a public issue for a security problem.

Use GitHub's private reporting: open the **Security** tab of this repository and choose **Report a vulnerability**. That goes to the maintainers only.

Please include:

- what you found and where (the page, the endpoint or the file),
- the steps to reproduce it, or a short proof of concept,
- the Obelo version (shown at the bottom of the sidebar) and how it is run (Docker, the sign-in method),
- what an attacker could do with it.

Leave out real passwords, keys and other people's data. If a test account is enough, use one.

## What to expect

Obelo is built and maintained by a very small team, so there is no formal schedule. We aim to confirm a report within a week, to fix real problems in the next release, and to say in the changelog what was fixed. We are glad to credit you if you want to be named.

## Which versions get fixes

The latest release. Fixes are not backported, so hosts need to update. The [changelog](CHANGELOG.md) says when an update needs anything from you.

## In scope

The server (`src/`), the web pages, the `/api/v1` API, the install files (`install.sh`, `docker-compose.yml`), and the iPhone, iPad and Mac apps in `ios/`. The kinds of problem that matter most here are:

- one user reaching another user's data (including notes marked private or locked),
- signing in without the right credentials, or getting admin without being an admin,
- script injection (XSS), CSRF, SQL injection, and unsafe file access through uploads,
- secrets (keys, tokens, calendar passwords) leaking into logs, pages or responses.

## Out of scope

- Things that need access to the server itself: the server owner can read everything by design (see the README).
- A host that runs Obelo over plain HTTP, leaves `NODE_ENV=development` on a public server, or publishes its `.env`.
- Findings only in an optional third-party service Obelo connects to (your SSO provider, SMTP server, AI provider, Pushover or ntfy).
- Denial of service by sending very large amounts of traffic.
- Missing hardening with no demonstrated effect, such as a missing header on a page with no sensitive data.
