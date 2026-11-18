# Contributing to Obelo

Thanks for looking. Obelo is a personal productivity hub that one person or a small group runs on their own server. It is kept small on purpose, so the best first step is to **open an issue** and say what you would like to change before you spend time on a large pull request.

Obelo is licensed under the [GNU GPL v3](LICENSE). By contributing you agree that your contribution is under the same license.

## Run it locally

You need Node.js 22 or newer, PostgreSQL 16 (or Docker), and Git.

```bash
git clone https://github.com/hillcraft-sc/obelo.git
cd obelo
npm ci
cp .env.example .env     # then set DATABASE_URL and SESSION_SECRET (see the README)
npx prisma migrate dev   # creates the tables in your local database
npm run dev              # the server, restarting on changes, on http://localhost:3000
```

Use a database of your own for development, never a real instance's. Set `NODE_ENV=development` in `.env` so that sign-in works over plain `http://`. To fill it with sample data: `NODE_ENV=development node scripts/seed-dev.js` (it refuses to run in any other mode).

Styling is Tailwind 4. After you add or change classes in a view, run `npm run build:css` and commit the built `public/css/tailwind.css` (`npm run watch:css` while you work).

## Tests

```bash
npm test
```

The server tests run against a throwaway PostgreSQL that the script starts in Docker. Without Docker, point `TEST_DATABASE_URL` at an empty database whose name ends in `_test` (the tests empty its tables, and refuse any other name). GitHub Actions runs the same tests, a dependency audit and a Docker build on every pull request.

Add a test with a change when you can. A new route that takes an id must be added to `KINDS` in `tests/access/access-control.test.js` (or to `EXEMPT`, with a reason); the test fails until it is, and then checks that other users cannot reach it.

## Rules the code follows

- **Scope every query to the signed-in user** (`where: { id, userId: req.user.id }`), and look up child records with their parent's id as well. Another person's id must give the same answer as a missing one.
- **Schema changes go through a Prisma migration**, committed with the change: `npx prisma migrate dev`. Never `prisma db push`. A change that drops or rewrites data needs a note in the changelog telling hosts to back up first.
- **Shared helpers are the only way in** for their job: `src/lib/aiProvider.js` for every AI call, `src/lib/uploads.js` for every file read, write and delete, `src/lib/credentials.js` for stored secrets. Every AI feature needs a working path with AI switched off.
- **Nothing specific to one server** in code or views: no domains, names or one person's integrations. Anything a host might want to change is a setting in `.env`, and every variable the code reads is listed in `.env.example`.
- **Private and locked notes never leave the user**: not into AI prompts, search for others, or logs.
- Send no secrets or personal data to outside services, and do not add analytics or other third-party scripts.
- Use `src/views/partials/` and the patterns already in the views, and keep pages usable on a small screen: there is no Android app, so some people use Obelo in a phone browser.

## The apps

The iPhone, iPad and Mac apps live in `ios/` (SwiftUI; the Xcode project is generated from `ios/project.yml` with XcodeGen). The web is the reference design, and the maintainers keep the apps in step with it, so a web-only pull request is fine: say so in the description and the apps will follow. If you change the API (`/api/v1`), keep it backward compatible, because installed apps keep using it.

## Pull requests

- Work on a branch and keep the change focused on one thing.
- Describe what changed for a user, and how you tested it. Say what you could not test.
- Add a line to `CHANGELOG.md` under the Server part (or Apps for `ios/`), written for the person updating their server, with a "Hosts:" line if they have to do anything.
- Do not bump the version; the maintainers do it when releasing.

## Security problems

Please do not file those as public issues. See [SECURITY.md](SECURITY.md).
