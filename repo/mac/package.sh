#!/bin/bash
# Packages the built app into a drag-to-install DMG, for carrying it to another
# Mac. Lands in dist/, which is inside the Drive folder — so it syncs to the
# laptop by itself.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/build/Oculus.app"
DIST="$HERE/dist"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="$DIST/Oculus-$VERSION.dmg"

[[ -d "$APP" ]] || { echo "No build found — run ./build.sh first."; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "→ staging"
cp -R "$APP" "$STAGE/Oculus.app"
ln -s /Applications "$STAGE/Applications"
[[ -f "$HERE/INSTALL.md" ]] && cp "$HERE/INSTALL.md" "$STAGE/Read Me — Install.md"

echo "→ building disk image"
mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create \
	-volname "Oculus" \
	-srcfolder "$STAGE" \
	-fs HFS+ \
	-format UDZO \
	-quiet \
	"$DMG"

echo
echo "Built: $DMG"
du -h "$DMG" | awk '{print "Size:  " $1}'
echo
echo "This app is not notarized, so the receiving Mac will refuse it on a"
echo "double-click. Right-click the app and choose Open, then Open again — once"
echo "per machine. See INSTALL.md."
