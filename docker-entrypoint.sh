#!/bin/sh
set -e

# Handles new installs and pre-migration databases; no-op once migration history exists.
node scripts/baseline-migrations.js

echo "[obelo] Running database migrations..."
npx prisma migrate deploy

# Uploads must go to the mounted volume or they are lost when the container is recreated
UPLOADS="${UPLOAD_PATH:-/app/uploads}"
if ! mkdir -p "$UPLOADS" 2>/dev/null || [ ! -w "$UPLOADS" ]; then
  echo "[obelo] WARNING: $UPLOADS is not writable by $(id -un) (UID $(id -u)) — note images and avatars will fail to save."
  echo "[obelo]          Docker volume: docker compose run --rm --user root --entrypoint chown app -R 1001:1001 $UPLOADS"
  echo "[obelo]          Host/NAS folder (UPLOADS_DIR): give UID 1001 ownership of that folder on the host or NAS"
fi

echo "[obelo] Starting application..."
exec node src/app.js
