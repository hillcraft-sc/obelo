#!/bin/zsh
# Builds the Obelo iOS app from the committed `main` branch and installs it on your iPhone.
#
# Apps signed with a free Apple account stop opening 7 days after they're installed, so this is
# run regularly (see ios/README.md, "Keeping the app installed"). The phone must be paired with
# this Mac (Wi-Fi or cable) and reachable.
#
#   ios/install.sh               install now
#   ios/install.sh --if-due      only if the last successful install was 5+ days ago (for the scheduler)
#   ios/install.sh --schedule    run --if-due twice a day from now on (a launchd agent on this Mac)
#   ios/install.sh --unschedule  stop doing that
#
# Set OBELO_DEVICE to a device id (xcrun devicectl list devices) to pick a phone; otherwise the
# first paired, connected iPhone is used.

set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$HOME/Library/Application Support/obelo-ios"
WORKTREE="$HOME/Library/Caches/obelo-ios/main"
STAMP="$STATE/last-install"
LOG="$STATE/install.log"
DUE_AFTER_DAYS=5
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$STATE" "$(dirname "$WORKTREE")"

# ── Scheduling (launchd agent) ───────────────────────────────────────────────
LABEL="obelo.reinstall"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
if [[ "${1:-}" == "--schedule" ]]; then
  mkdir -p "$(dirname "$PLIST")"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$REPO/ios/install.sh</string><string>--if-due</string></array>
  <!-- Morning and evening, so a day with the phone away from home still gets a chance;
       a run missed while the Mac sleeps happens when it wakes -->
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Hour</key><integer>8</integer><key>Minute</key><integer>30</integer></dict>
    <dict><key>Hour</key><integer>21</integer><key>Minute</key><integer>0</integer></dict>
  </array>
  <key>StandardOutPath</key><string>$STATE/launchd.log</string>
  <key>StandardErrorPath</key><string>$STATE/launchd.log</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$PLIST" && echo "Scheduled: checks at 8:30 and 21:00 daily, reinstalls when 5+ days old. Log: $LOG"
  exit $?
fi
if [[ "${1:-}" == "--unschedule" ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  rm -f "$PLIST" && echo "Unscheduled."
  exit 0
fi

exec > >(tee -a "$LOG") 2>&1
echo "── $(date '+%Y-%m-%d %H:%M') ──"

notify() { # Mac notification (shows even when this runs in the background)
  osascript -e "display notification \"$2\" with title \"Obelo\" subtitle \"$1\"" >/dev/null 2>&1 || true
}
fail() {
  echo "FAILED: $1"
  # Warn only when the installed copy is close to expiring, so one missed day isn't noisy
  local age_days=99
  [[ -f "$STAMP" ]] && age_days=$(( ($(date +%s) - $(cat "$STAMP")) / 86400 ))
  if (( age_days >= 6 )); then
    notify "App reinstall failed" "$1 — the app stops opening $(( 7 - age_days > 0 ? 7 - age_days : 0 )) day(s) from now. Run ios/install.sh."
  fi
  exit 1
}

if [[ "${1:-}" == "--if-due" && -f "$STAMP" ]]; then
  age=$(( ($(date +%s) - $(cat "$STAMP")) / 86400 ))
  if (( age < DUE_AFTER_DAYS )); then echo "Installed $age day(s) ago; not due yet."; exit 0; fi
fi

# ── Which phone ───────────────────────────────────────────────────────────────
DEVICE="${OBELO_DEVICE:-}"
if [[ -z "$DEVICE" ]]; then
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || fail "couldn't list devices"
  # Prefer a phone with an open connection; otherwise take any paired iPhone. A phone idle on
  # Wi-Fi shows as "disconnected" until something talks to it, and the build/install opens it.
  DEVICE="$(/usr/bin/python3 -c '
import json, sys
phones = [d for d in json.load(open(sys.argv[1]))["result"]["devices"]
          if d.get("hardwareProperties", {}).get("platform") == "iOS"
          and d.get("hardwareProperties", {}).get("reality") == "physical"
          and d.get("connectionProperties", {}).get("pairingState") == "paired"]
phones.sort(key=lambda d: d.get("connectionProperties", {}).get("tunnelState") != "connected")
if phones: print(phones[0]["identifier"])
' "$json")"
  rm -f "$json"
fi
[[ -n "$DEVICE" ]] || fail "no paired iPhone found (pair it once from Xcode → Devices and Simulators)"
echo "Device: $DEVICE"

# ── Build from committed main, never from work in progress ───────────────────
if [[ ! -d "$WORKTREE" ]]; then
  git -C "$REPO" worktree add --detach "$WORKTREE" main >/dev/null 2>&1 || fail "couldn't create a build checkout"
fi
git -C "$WORKTREE" checkout --quiet --detach main 2>/dev/null || git -C "$WORKTREE" checkout --quiet --detach "$(git -C "$REPO" rev-parse main)" || fail "couldn't check out main"
echo "Building $(git -C "$WORKTREE" log --oneline -1)"

cd "$WORKTREE/ios" || fail "no ios folder"
# The maintainer's signing values are not in Git: copy them into the build checkout
[[ -f "$REPO/ios/Signing.local.xcconfig" ]] && cp "$REPO/ios/Signing.local.xcconfig" "$WORKTREE/ios/"
xcodegen generate --quiet >/dev/null || fail "xcodegen failed"
xcodebuild -project Obelo.xcodeproj -scheme Obelo -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath build -allowProvisioningUpdates -quiet build \
  > "$STATE/build.log" 2>&1 || fail "build failed (see $STATE/build.log)"

# ── Install (the phone can drop off Wi-Fi briefly; try a few times) ─────────
for attempt in 1 2 3; do
  if xcrun devicectl device install app --device "$DEVICE" build/Build/Products/Debug-iphoneos/Obelo.app 2>&1 | grep -q "App installed"; then
    date +%s > "$STAMP"
    echo "Installed. Good until $(date -v+7d '+%a %b %-d')."
    exit 0
  fi
  echo "Install attempt $attempt didn't go through; retrying…"
  sleep 20
done
fail "couldn't install on the phone (same Wi-Fi as this Mac, unlocked recently?)"
