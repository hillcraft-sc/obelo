#!/usr/bin/env bash
# Backs up the Obelo database and uploaded files. Runs on the Docker host, from anywhere.
#
#   scripts/backup.sh /mnt/nas/obelo_backups
#
# Writes obelo-db-<stamp>.sql.gz and obelo-uploads-<stamp>.tgz, verifies both, and
# deletes backups older than BACKUP_KEEP_DAYS (default 14). The backup directory must already
# exist — if it's a network share that isn't mounted, the script fails instead of quietly
# filling the local disk. Exits non-zero on any failure.
#
# Failure alerts: if .env has PUSHOVER_APP_TOKEN and BACKUP_ALERT_PUSHOVER_USER (your Pushover
# user key), a failed run sends a push notification.
#
# Not included: .env (it holds your secrets). Keep a copy of it, especially NOTE_LOCK_SECRET
# and UPLOADS_ENCRYPTION_KEY, somewhere safe and separate — without them, restored locked
# notes and encrypted uploads can't be opened.
set -euo pipefail

cd "$(dirname "$0")/.."

BACKUP_DIR="${1:-${BACKUP_DIR:-}}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
STAMP="$(date +%F_%H%M)"

log() { echo "$(date '+%F %T') [backup] $*"; }
fail() { ERROR_MSG="$*"; log "ERROR: $*"; exit 1; }

# A setting from the environment, else from .env (read without sourcing it, since values may
# contain shell-special characters)
env_value() {
  if [ -n "${!1:-}" ]; then echo "${!1}"; return; fi
  { sed -n "s/^$1=//p" .env 2>/dev/null || true; } | tail -n 1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

notify_failure() {
  local token user
  token="$(env_value PUSHOVER_APP_TOKEN)"
  user="$(env_value BACKUP_ALERT_PUSHOVER_USER)"
  [ -n "$token" ] && [ -n "$user" ] || return 0
  if curl -fsS --max-time 20 https://api.pushover.net/1/messages.json \
    --form-string "token=$token" \
    --form-string "user=$user" \
    --form-string "title=Obelo backup failed on $(hostname)" \
    --form-string "message=${ERROR_MSG:-Backup exited with an error}. See the backup log." \
    --form-string "priority=1" > /dev/null; then
    log "Sent failure alert via Pushover"
  else
    log "Could not send Pushover alert"
  fi
}

ERROR_MSG=""

on_exit() {
  local status=$?
  rm -f "${DB_FILE:-}.partial" "${UP_FILE:-}.partial"
  if [ "$status" -ne 0 ]; then
    [ -n "$ERROR_MSG" ] || { ERROR_MSG="Backup exited with status $status"; log "ERROR: $ERROR_MSG"; }
    notify_failure
  fi
}
trap on_exit EXIT

[ -n "$BACKUP_DIR" ] || fail "usage: $0 <backup-dir>"
[ -d "$BACKUP_DIR" ] || fail "$BACKUP_DIR does not exist (is the share mounted?)"
[ -w "$BACKUP_DIR" ] || fail "$BACKUP_DIR is not writable by $(id -un)"

DB_FILE="$BACKUP_DIR/obelo-db-$STAMP.sql.gz"
UP_FILE="$BACKUP_DIR/obelo-uploads-$STAMP.tgz"

log "Dumping database..."
# The names come from the database container, so this works for any install (old ones use `vibetrack`)
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip > "$DB_FILE.partial" \
  || fail "database dump failed"
gzip -t "$DB_FILE.partial" || fail "database dump is corrupt"
mv "$DB_FILE.partial" "$DB_FILE"

log "Archiving uploads..."
docker compose exec -T app tar czf - -C /app/uploads . > "$UP_FILE.partial" \
  || fail "uploads archive failed"
tar tzf "$UP_FILE.partial" > /dev/null || fail "uploads archive is corrupt"
mv "$UP_FILE.partial" "$UP_FILE"

size() { ls -lh "$1" | awk '{print $5}'; }   # apparent size (du under-reports on compressed filesystems)
log "Wrote $(size "$DB_FILE") $DB_FILE"
log "Wrote $(size "$UP_FILE") $UP_FILE"

OLD=$(find "$BACKUP_DIR" -maxdepth 1 \( -name 'obelo-*' -o -name 'vibetrack-*' \) -type f -mtime +"$KEEP_DAYS" -print -delete | wc -l | tr -d ' ')
log "Removed $OLD backup file(s) older than $KEEP_DAYS days. Done."
