#!/bin/bash
# Swaps the app icon. One argument: a 1024x1024 PNG.
#
#   ./Tools/set-icon.sh path/to/icon.png
#
# App Store Connect rejects any icon carrying an alpha channel, silently, so
# this flattens and checks rather than trusting the source.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -eq 1 ] || { echo "usage: $0 <1024x1024 png>"; exit 1; }
DEST="Assets.xcassets/AppIcon.appiconset/icon-1024.png"
sips -s format png -z 1024 1024 "$1" --out "$DEST" >/dev/null
# sips keeps alpha if the source had it; re-encode without.
python3 - "$DEST" <<'PY'
import sys
from PIL import Image
p = sys.argv[1]
Image.open(p).convert("RGB").save(p)
PY
echo "icon set from $1"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$DEST" | tail -3
