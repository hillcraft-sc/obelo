// Whether notifications are really sent. Push (Pushover, ntfy) and email all ask here, so a
// development server pointed at real settings cannot message real people.
//
// NOTIFICATIONS_DRY_RUN=true  → log "would send" instead of sending
// NOTIFICATIONS_DRY_RUN=false → always send
// unset                       → dry run unless NODE_ENV is "production"
//
// A button a person pressed on purpose (the Settings test buttons) passes { force: true } and
// is always sent.

function isDryRun() {
  const v = (process.env.NOTIFICATIONS_DRY_RUN || '').trim().toLowerCase();
  if (v === 'true') return true;
  if (v === 'false') return false;
  return process.env.NODE_ENV !== 'production';
}

function describe() {
  return isDryRun()
    ? 'Notifications: DRY RUN, push and email are logged and not sent (set NOTIFICATIONS_DRY_RUN=false to send)'
    : 'Notifications: live';
}

module.exports = { isDryRun, describe };
