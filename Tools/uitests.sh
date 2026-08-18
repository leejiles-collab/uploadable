#!/bin/bash
#
# The UI tests, with the device state they depend on.
#
# Photo-library permission is granted up front. A permission alert would stall
# the Save to Photos tap and turn a real crash into an ambiguous timeout.
#
set -euo pipefail
cd "$(dirname "$0")/.."

SIM=$(xcrun simctl list devices available | grep "iPhone 17 Pro Max" | head -1 | grep -oE "[0-9A-F-]{36}")
[ -n "$SIM" ] || { echo "error: need an iPhone 17 Pro Max simulator"; exit 1; }

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1

./Tools/generate-project.sh >/dev/null
xcodebuild -project Uploadable.xcodeproj -scheme Uploadable \
    -destination "id=$SIM" -configuration Debug build >/dev/null

APP=$(find ~/Library/Developer/Xcode/DerivedData/Uploadable-*/Build/Products/Debug-iphonesimulator \
    -maxdepth 1 -name "Uploadable.app" | head -1)
xcrun simctl install "$SIM" "$APP" >/dev/null
xcrun simctl privacy "$SIM" grant photos-add com.leejiles.uploadable 2>/dev/null || true

DATA=$(xcrun simctl get_app_container "$SIM" com.leejiles.uploadable data)
cp Fixtures/screenshot-source.jpg "$DATA/Documents/screenshot-source.jpg"
sips -s format jpeg -z 400 400 Fixtures/screenshot-source.jpg \
    --out "$DATA/Documents/screenshot-too-small.jpg" >/dev/null

exec xcodebuild test -project Uploadable.xcodeproj -scheme Uploadable \
    -destination "id=$SIM" -only-testing:UploadableUITests "$@"
