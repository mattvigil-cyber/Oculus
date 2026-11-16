#!/bin/bash
# Installs the built app to ~/Applications and relaunches it from there.
#
# Running it out of the Google Drive folder works, but is a bad home for a
# process that stays resident: Drive re-syncs the 23 MB bundle on every rebuild,
# and can evict or replace files underneath the running app.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/build/Oculus.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/Oculus.app"

[[ -d "$SRC" ]] || { echo "No build found — run ./build.sh first."; exit 1; }

echo "→ stopping any running copy"
pkill -f "Oculus.app/Contents/MacOS/Oculus" 2>/dev/null || true
sleep 1

echo "→ installing to $DEST"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "→ launching"
open "$DEST"

echo
echo "Installed: $DEST"
echo
echo "The camera grant follows the app's code signature, not its location, so"
echo "moving it does not cost you the permission. If you had 'Open at Login'"
echo "ticked, tick it again from the menu so it points at this copy."
