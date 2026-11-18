#!/bin/zsh
# Archives the Obelo Mac app from the current commit. By default it stops there, so you can check
# the archive; with --upload it also sends it to App Store Connect, where it shows up in TestFlight
# (Mac) once Apple has processed it.
#
#   ios/testflight-mac.sh             # archive only, into ios/build/testflight-mac
#   ios/testflight-mac.sh --upload    # archive and upload
#
# Needs Xcode signed in to the developer account, and macOS added to the Obelo record in App Store
# Connect (App Information, Add Platform). Signing is automatic. The build number is the commit
# count; the version shown to testers is MARKETING_VERSION in project.yml.

set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/ios/build/testflight-mac"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

UPLOAD=0
[[ "${1:-}" == "--upload" ]] && UPLOAD=1

if [[ -n "$(git -C "$REPO" status --porcelain -- ios)" ]]; then
  echo "Commit your iOS changes first, so the build matches a commit." >&2
  exit 1
fi
BUILD="$(git -C "$REPO" rev-list --count HEAD)"
TEAM="$(cat "$REPO/ios/Signing.xcconfig" "$REPO/ios/Signing.local.xcconfig" 2>/dev/null | sed -n 's/^OBELO_TEAM_ID *= *//p' | tail -n 1)"
echo "Build $BUILD from $(git -C "$REPO" log --oneline -1)"

cd "$REPO/ios"
# Regenerating wipes the schemes Xcode made for this project, so only do it when project.yml changed
if [[ ! -d Obelo.xcodeproj || project.yml -nt Obelo.xcodeproj/project.pbxproj ]]; then xcodegen generate --quiet; fi
rm -rf "$OUT" && mkdir -p "$OUT"

xcodebuild -project Obelo.xcodeproj -scheme ObeloMac -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$OUT/Obelo.xcarchive" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" -quiet archive \
  > "$OUT/archive.log" 2>&1 || { tail -n 30 "$OUT/archive.log"; echo "Archive failed (full log: $OUT/archive.log)" >&2; exit 1; }

if [[ $UPLOAD -eq 0 ]]; then
  echo "Archived build $BUILD at $OUT/Obelo.xcarchive. Not uploaded (add --upload to send it)."
  exit 0
fi

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

echo "Uploaded Mac build $BUILD. It appears under TestFlight in App Store Connect once processing finishes."
