#!/bin/zsh
# Usage: scripts/make-icon.sh path/to/AppIcon.icns
set -euo pipefail
OUT="$1"
WORK="$(mktemp -d)"
swift "$(dirname "$0")/render-icon.swift" "$WORK/icon-1024.png"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$WORK/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$WORK"
