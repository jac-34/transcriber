#!/bin/zsh
# Assembles dist/Transcriptor.app from the release binary. No Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BIN=.build/release/Transcriptor
APP=dist/Transcriptor.app

[[ -x "$BIN" ]] || { echo "Falta $BIN. Corre 'make build' primero."; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Transcriptor"

# SwiftPM resource bundles (WhisperKit ships none today; copy any that appear).
for bundle in .build/release/*.bundle(N); do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

scripts/make-icon.sh "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" scripts/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Refuse to ship if anything outside the OS is dynamically linked.
if otool -L "$APP/Contents/MacOS/Transcriptor" | tail -n +2 | awk '{print $1}' | grep -vE '^(/usr/lib/|/System/Library/)'; then
  echo "ERROR: el binario enlaza librerías dinámicas que no son del sistema (ver arriba)."
  exit 1
fi

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Listo: $APP (versión $VERSION)"
