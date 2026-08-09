#!/bin/bash
#
# Build and install onto a connected iPhone.
#
# Exists because a free Personal Team's provisioning profile expires after 7 days:
# the app stops launching and has to be reinstalled. That is an Apple limit, not
# something the project can work around — this just makes the fix one command.
#
#   ./scripts/install-to-iphone.sh            # first connected device
#   ./scripts/install-to-iphone.sh <udid>     # a specific one
#
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/connected/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-/) { print $i; exit } }')
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No connected iPhone found."
  echo "Plug it in, unlock it, and make sure you've tapped Trust This Computer."
  exit 1
fi

echo "==> Device: $DEVICE_ID"

# Regenerate so any files added since the last run are in the project.
if command -v xcodegen >/dev/null 2>&1; then
  echo "==> xcodegen generate"
  xcodegen generate >/dev/null
fi

echo "==> Building"
xcodebuild \
  -scheme KhanaKyaBanau \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates \
  build | grep -E "error:|warning: .*(deprecat|unused)|BUILD SUCCEEDED|BUILD FAILED" || true

APP="build/DerivedData/Build/Products/Debug-iphoneos/KhanaKyaBanau.app"
if [[ ! -d "$APP" ]]; then
  echo "Build did not produce $APP"
  exit 1
fi

echo "==> Installing"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo
echo "Installed. If iOS says the developer is untrusted:"
echo "  Settings › General › VPN & Device Management › your Apple ID › Trust"

# Surface how long this build will keep working.
PROFILE=$(ls -t ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision 2>/dev/null | head -1)
if [[ -n "$PROFILE" ]]; then
  EXPIRY=$(security cms -D -i "$PROFILE" 2>/dev/null \
    | plutil -extract ExpirationDate raw - 2>/dev/null || true)
  [[ -n "$EXPIRY" ]] && echo "Provisioning profile expires: $EXPIRY (re-run this script to renew)"
fi
