#!/usr/bin/env bash
#
# run-carplay.sh — build, install and launch Nesteferge in the CarPlay Simulator.
#
# The Simulator needs a two-pass install, because the CarPlay entitlement is
# required for the app to appear on the CarPlay home screen, but makes the binary
# unlaunchable when applied with `codesign`. See Nesteferge/Nesteferge.entitlements.
#
#   pass 1: sign WITH the entitlement,    install  -> registers CarPlay capability
#   pass 2: sign WITHOUT it, install OVER the top  -> launchable, registration kept
#
# Usage:
#   scripts/run-carplay.sh
#   DEVICE="iPhone 16" scripts/run-carplay.sh
#   LAT=62.39 LNG=6.33 scripts/run-carplay.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 16}"
BUNDLE_ID="com.axb.nesteferge"
DERIVED="${DERIVED:-$PWD/.build/dd}"
# Festøya, on the Festøya–Solavågen crossing.
LAT="${LAT:-62.39}"
LNG="${LNG:-6.33}"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- resolve and boot the device ---------------------------------------------
UDID="$(xcrun simctl list devices available -j | python3 -c "
import json, sys
name = sys.argv[1]
for runtime, devs in json.load(sys.stdin)['devices'].items():
    if 'iOS' not in runtime:
        continue
    for dev in devs:
        if dev['name'] == name:
            print(dev['udid']); sys.exit(0)
sys.exit(1)
" "$DEVICE")" || die "no available simulator named '$DEVICE'"

say "Device: $DEVICE ($UDID)"

if ! xcrun simctl list devices booted | grep -q "$UDID"; then
  say "Booting simulator"
  xcrun simctl boot "$UDID"
fi
open -a Simulator
xcrun simctl bootstatus "$UDID" -b >/dev/null

# --- build --------------------------------------------------------------------
say "Building"
xcodebuild \
  -project Nesteferge.xcodeproj \
  -scheme Nesteferge \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Nesteferge.app"
[ -d "$APP" ] || die "build product not found at $APP"

# --- two-pass install ---------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/carplay.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.carplay-driving-task</key>
	<true/>
	<key>com.apple.security.get-task-allow</key>
	<true/>
</dict>
</plist>
EOF

cat > "$WORK/plain.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.get-task-allow</key>
	<true/>
</dict>
</plist>
EOF

# Nested Mach-O first: Xcode ships the real code in Nesteferge.debug.dylib and
# re-signing only the bundle would invalidate it.
sign() {
  for lib in "$APP"/*.dylib; do
    [ -e "$lib" ] && codesign -f -s - "$lib" >/dev/null 2>&1
  done
  codesign -f -s - --entitlements "$1" "$APP" >/dev/null 2>&1
}

say "Pass 1: registering CarPlay capability"
sign "$WORK/carplay.entitlements"
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"

say "Pass 2: installing launchable build"
sign "$WORK/plain.entitlements"
xcrun simctl install "$UDID" "$APP"   # deliberately NOT preceded by uninstall

# --- runtime setup ------------------------------------------------------------
# Both of these are cleared by `simctl erase`, so always re-apply them. Without a
# location near a Norwegian quay, /api/guess correctly returns no candidates.
xcrun simctl privacy "$UDID" grant location-always "$BUNDLE_ID" >/dev/null 2>&1 || true
say "Setting location to $LAT,$LNG"
xcrun simctl location "$UDID" set "$LAT,$LNG"

if ! xcrun simctl io "$UDID" enumerate 2>/dev/null | grep -q 'Type: TVOut'; then
  cat <<'EOF'

  !! The CarPlay display is not attached.
     In Simulator: I/O > External Displays > CarPlay

EOF
fi

say "Launching on iPhone"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null

cat <<'EOF'

Done. Click the Nesteferge icon on the CarPlay window to open the car UI.

Screenshot the CarPlay display (it is display 2, reported as "TVOut"):
  xcrun simctl io booted screenshot --display 2 /tmp/carplay.png

Troubleshooting:
  * CarPlay screen blank after the app was terminated — reconnect the display
    via I/O > External Displays (Disabled, then CarPlay).
  * Clicks not registering anywhere, even in built-in apps like Messages — the
    Simulator's input state has wedged; quit and reopen Simulator.

EOF
