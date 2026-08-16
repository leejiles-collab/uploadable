#!/bin/bash
#
# Generates Fits.xcodeproj from project.yml.
#
# The bundle identifier prefix has exactly one home: BundleConfig.swift. This
# script reads it from there and feeds it to XcodeGen and the entitlements.
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is not installed."
  echo
  echo "  brew install xcodegen"
  echo
  echo "Then run this script again. (FitsKit and fitscli build with swift build"
  echo "and do not need the Xcode project.)"
  exit 1
fi

CONFIG="$ROOT/FitsKit/Sources/FitsKit/Models/BundleConfig.swift"
BUNDLE_PREFIX="$(sed -n 's/.*static let prefix = "\(.*\)".*/\1/p' "$CONFIG")"

if [ -z "$BUNDLE_PREFIX" ]; then
  echo "error: could not read the prefix out of $CONFIG"
  exit 1
fi

export BUNDLE_PREFIX
APP_GROUP="group.${BUNDLE_PREFIX}.fits"

write_entitlements() {
  cat > "$1" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>${APP_GROUP}</string>
	</array>
</dict>
</plist>
PLIST
}

mkdir -p "$ROOT/Support"
write_entitlements "$ROOT/Support/Fits.entitlements"
write_entitlements "$ROOT/Support/FitsShare.entitlements"

xcodegen generate --spec "$ROOT/project.yml"

# XcodeGen writes the StoreKit configuration path relative to the .xcodeproj,
# but Xcode resolves it from the .xcscheme, two directories deeper. Left alone
# the setting shows red in the scheme editor and an Xcode run talks to the real
# App Store instead of the local config. Paid for on Smaller.
SCHEME="$ROOT/Fits.xcodeproj/xcshareddata/xcschemes/Fits.xcscheme"
WANT='identifier = "../../../Support/Fits.storekit"'
if [ -f "$SCHEME" ]; then
  sed -i '' \
    's|identifier = "\.\./\.\./Support/Fits\.storekit"|identifier = "../../../Support/Fits.storekit"|' \
    "$SCHEME"
  if ! grep -qF "$WANT" "$SCHEME"; then
    echo
    echo "warning: could not set the StoreKit configuration path in the scheme."
    echo "         Check Product > Scheme > Edit Scheme > Run > Options."
  fi
fi

echo
echo "Generated Fits.xcodeproj"
echo "  bundle prefix: $BUNDLE_PREFIX"
echo "  app group:     $APP_GROUP"
