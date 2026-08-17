#!/bin/bash
#
# Regenerates the App Store screenshots end to end.
#
#   ./Tools/screenshots.sh                      # uses Fixtures/screenshot-source.jpg
#   ./Tools/screenshots.sh path/to/portrait.jpg # uses that photo instead
#
# Every number on the output comes from the engine running on the photo you
# pass in. Nothing is mocked, and the captions state no numbers, so swapping the
# photograph cannot turn a caption into a false claim.
#
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${1:-Fixtures/screenshot-source.jpg}"
[ -f "$SOURCE" ] || { echo "error: no source photo at $SOURCE"; exit 1; }

RAW="$(mktemp -d)"
OUT="$HOME/Desktop/Uploadable-AppStore"
rm -rf "$OUT"

# Largest size per device family. Apple scales the rest itself, so these two are
# the whole set: 1320x2868 and 2064x2752.
IPHONE=$(xcrun simctl list devices available | grep "iPhone 17 Pro Max" | head -1 | grep -oE "[0-9A-F-]{36}")
IPAD=$(xcrun simctl list devices available | grep "iPad Pro 13-inch" | head -1 | grep -oE "[0-9A-F-]{36}")
[ -n "$IPHONE" ] && [ -n "$IPAD" ] || { echo "error: need an iPhone 17 Pro Max and an iPad Pro 13-inch simulator"; exit 1; }

./Tools/generate-project.sh >/dev/null

# A source too small for DS-160, so the refusal screen refuses for a real reason.
TOOSMALL="$RAW/screenshot-too-small.jpg"
sips -s format jpeg -z 400 400 "$SOURCE" --out "$TOOSMALL" >/dev/null

for DEVICE in "$IPHONE:iphone" "$IPAD:ipad"; do
  ID="${DEVICE%%:*}"; TAG="${DEVICE##*:}"
  xcodebuild -project Uploadable.xcodeproj -scheme Uploadable \
      -destination "id=$ID" -configuration Debug build >/dev/null
  APP=$(find ~/Library/Developer/Xcode/DerivedData/Uploadable-*/Build/Products/Debug-iphonesimulator \
      -maxdepth 1 -name "Uploadable.app" | head -1)

  xcrun simctl boot "$ID" 2>/dev/null || true
  xcrun simctl bootstatus "$ID" -b >/dev/null 2>&1
  xcrun simctl install "$ID" "$APP" >/dev/null
  DATA=$(xcrun simctl get_app_container "$ID" com.leejiles.uploadable data)
  cp "$SOURCE" "$DATA/Documents/screenshot-source.jpg"
  cp "$TOOSMALL" "$DATA/Documents/screenshot-too-small.jpg"
  # A clean, believable status bar rather than whatever the simulator drifted to.
  xcrun simctl status_bar "$ID" override --time "9:41" --batteryState charged \
      --batteryLevel 100 --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4

  # Any other app left running becomes a "< Smaller" back-breadcrumb in the
  # status bar, because iOS thinks we were launched from it. Terminating every
  # other app of ours clears it. A breadcrumb naming a different app on a store
  # screenshot is exactly the kind of thing a reviewer notices.
  for OTHER in $(xcrun simctl listapps "$ID" 2>/dev/null | grep -oE 'com\.leejiles\.[a-z.]+' | sort -u); do
    [ "$OTHER" = "com.leejiles.uploadable" ] || xcrun simctl terminate "$ID" "$OTHER" 2>/dev/null || true
  done

  for SCREEN in done crop nz failure home; do
    xcrun simctl terminate "$ID" com.leejiles.uploadable 2>/dev/null || true
    xcrun simctl launch "$ID" com.leejiles.uploadable "--screen=$SCREEN" >/dev/null
    case "$SCREEN" in done|nz) sleep 16 ;; *) sleep 7 ;; esac
    xcrun simctl io "$ID" screenshot "$RAW/$TAG-$SCREEN.png" >/dev/null 2>&1
  done
done

python3 Tools/screenshots.py "$RAW" "$OUT"

echo
echo "Verifying every file, because App Store Connect rejects alpha silently:"
FAIL=0
for f in "$OUT"/*/*.png; do
  W=$(sips -g pixelWidth "$f" | tail -1 | awk '{print $2}')
  H=$(sips -g pixelHeight "$f" | tail -1 | awk '{print $2}')
  A=$(sips -g hasAlpha "$f" | tail -1 | awk '{print $2}')
  SPACE=$(sips -g space "$f" | tail -1 | awk '{print $2}')
  EXPECT=$(basename "$(dirname "$f")" | grep -oE '[0-9]+x[0-9]+')
  OK="ok"
  [ "${W}x${H}" = "$EXPECT" ] || { OK="WRONG SIZE"; FAIL=1; }
  [ "$A" = "no" ] || { OK="HAS ALPHA"; FAIL=1; }
  printf "  %-46s %sx%-6s alpha=%-5s %-5s %s\n" "$(basename "$(dirname "$f")")/$(basename "$f")" "$W" "$H" "$A" "$SPACE" "$OK"
done
rm -rf "$RAW"
[ "$FAIL" -eq 0 ] || { echo "one or more files would be rejected"; exit 1; }
echo
echo "Screenshots in $OUT"
