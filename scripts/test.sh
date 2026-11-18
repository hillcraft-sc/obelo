#!/usr/bin/env bash
# Runs the test suite against a throwaway Postgres.
#
#   npm test                       starts a temporary Postgres in Docker, runs the tests, removes it
#   TEST_DATABASE_URL=postgresql://user:pw@host:5432/something_test npm test
#                                  uses that database instead (CI does this)
#   npm test -- tests/auth/setup.test.js     extra arguments go to `node --test`
#
# The database name must end in _test. The tests empty its tables, so this script and the
# test helpers both refuse anything else. It never reads .env or DATABASE_URL.
set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER=""
cleanup() { [ -n "$CONTAINER" ] && docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

if [ -z "${TEST_DATABASE_URL:-}" ]; then
  command -v docker >/dev/null 2>&1 || {
    echo "No TEST_DATABASE_URL and no Docker. Either start Docker, or point TEST_DATABASE_URL at a" >&2
    echo "throwaway Postgres database whose name ends in _test." >&2
    exit 1
  }
  PORT=${TEST_DB_PORT:-54555}
  CONTAINER="obelo-test-db-$$"
  docker run -d --rm --name "$CONTAINER" -e POSTGRES_PASSWORD=test -e POSTGRES_DB=obelo_test \
    -p "127.0.0.1:$PORT:5432" postgres:16-alpine >/dev/null
  ok=0
  for _ in $(seq 1 60); do
    # Postgres restarts once after first-time setup, so two good answers in a row
    if docker exec "$CONTAINER" psql -U postgres -d obelo_test -qc 'select 1' >/dev/null 2>&1 \
       && sleep 1 && docker exec "$CONTAINER" psql -U postgres -d obelo_test -qc 'select 1' >/dev/null 2>&1; then ok=1; break; fi
    sleep 1
  done
  [ "$ok" = 1 ] || { echo "The test database did not start." >&2; exit 1; }
  export TEST_DATABASE_URL="postgresql://postgres:test@127.0.0.1:$PORT/obelo_test"
fi

DB_NAME="${TEST_DATABASE_URL##*/}"; DB_NAME="${DB_NAME%%\?*}"
case "$DB_NAME" in
  *_test) ;;
  *) echo "Refusing to run: the test database name must end in _test (got '$DB_NAME')." >&2; exit 1 ;;
esac

# The real migrations, the same way the container applies them
DATABASE_URL="$TEST_DATABASE_URL" node scripts/baseline-migrations.js >/dev/null 2>&1
DATABASE_URL="$TEST_DATABASE_URL" npx prisma migrate deploy >/dev/null 2>&1 \
  || { echo "Applying the migrations to the test database failed." >&2; exit 1; }

# One process per test file, so each file gets a fresh app, rate limits and in-memory counters.
# One file at a time, because they share the one database.
exec_status=0
node --test --test-force-exit --test-concurrency=1 "${@:-tests/**/*.test.js}" || exec_status=$?
exit $exec_status
