#!/bin/bash
#
# Generates Uploadable.xcodeproj from project.yml.
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
  echo "Then run this script again. (UploadableKit and uploadablecli build with swift build"
  echo "and do not need the Xcode project.)"
  exit 1
fi

CONFIG="$ROOT/UploadableKit/Sources/UploadableKit/Models/BundleConfig.swift"
BUNDLE_PREFIX="$(sed -n 's/.*static let prefix = "\(.*\)".*/\1/p' "$CONFIG")"

if [ -z "$BUNDLE_PREFIX" ]; then
  echo "error: could not read the prefix out of $CONFIG"
  exit 1
fi

export BUNDLE_PREFIX
APP_GROUP="group.${BUNDLE_PREFIX}.uploadable"

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
write_entitlements "$ROOT/Support/Uploadable.entitlements"
write_entitlements "$ROOT/Support/UploadableShare.entitlements"

xcodegen generate --spec "$ROOT/project.yml"

# XcodeGen writes the StoreKit configuration path relative to the .xcodeproj,
# but Xcode resolves it from the .xcscheme, two directories deeper. Left alone
# the setting shows red in the scheme editor and an Xcode run talks to the real
# App Store instead of the local config. Paid for on Smaller.
SCHEME="$ROOT/Uploadable.xcodeproj/xcshareddata/xcschemes/Uploadable.xcscheme"
WANT='identifier = "../../../Support/Uploadable.storekit"'
if [ -f "$SCHEME" ]; then
  sed -i '' \
    's|identifier = "\.\./\.\./Support/Uploadable\.storekit"|identifier = "../../../Support/Uploadable.storekit"|' \
    "$SCHEME"
  if ! grep -qF "$WANT" "$SCHEME"; then
    echo
    echo "warning: could not set the StoreKit configuration path in the scheme."
    echo "         Check Product > Scheme > Edit Scheme > Run > Options."
  fi
fi

echo
echo "Generated Uploadable.xcodeproj"
echo "  bundle prefix: $BUNDLE_PREFIX"
echo "  app group:     $APP_GROUP"
