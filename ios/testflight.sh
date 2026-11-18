#!/bin/zsh
# Archives the Obelo iOS app from the current commit and uploads it to App Store Connect, where it
# shows up in TestFlight once Apple has processed it (usually 5–30 minutes).
#
#   ios/testflight.sh
#
# Needs Xcode signed in to the developer account (Xcode → Settings → Accounts). Signing is
# automatic, so the first run also registers any missing App IDs, the App Group and the
# distribution certificate. The build number is the commit count, so every upload is higher
# than the last; the version shown to testers is MARKETING_VERSION in project.yml.

set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/ios/build/testflight"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [[ -n "$(git -C "$REPO" status --porcelain -- ios src/lib/appLogin.js)" ]]; then
  echo "Commit your iOS changes first, so the upload matches a commit." >&2
  exit 1
fi
BUILD="$(git -C "$REPO" rev-list --count HEAD)"
TEAM="$(cat "$REPO/ios/Signing.xcconfig" "$REPO/ios/Signing.local.xcconfig" 2>/dev/null | sed -n 's/^OBELO_TEAM_ID *= *//p' | tail -n 1)"
echo "Build $BUILD from $(git -C "$REPO" log --oneline -1)"

cd "$REPO/ios"
# Regenerating wipes the schemes Xcode made for this project, so only do it when project.yml changed
if [[ ! -d Obelo.xcodeproj || project.yml -nt Obelo.xcodeproj/project.pbxproj ]]; then xcodegen generate --quiet; fi
rm -rf "$OUT" && mkdir -p "$OUT"

xcodebuild -project Obelo.xcodeproj -scheme Obelo -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Obelo.xcarchive" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" -quiet archive \
  > "$OUT/archive.log" 2>&1 || { tail -n 30 "$OUT/archive.log"; echo "Archive failed (full log: $OUT/archive.log)" >&2; exit 1; }

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$OUT/Obelo.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates > "$OUT/upload.log" 2>&1 \
  || { tail -n 30 "$OUT/upload.log"; echo "Upload failed (full log: $OUT/upload.log)" >&2; exit 1; }

echo "Uploaded build $BUILD. It appears under TestFlight in App Store Connect once processing finishes."
