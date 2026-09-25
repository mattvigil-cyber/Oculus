#!/bin/bash
# Assembles Oculus.app from Sources/ plus the two HTML pieces one directory up.
# Needs only the Command Line Tools — no Xcode project, no package manifest.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
APP="$HERE/build/Oculus.app"
DEPLOY_TARGET="13.0"

echo "→ cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"

echo "→ compiling"
ARCH="$(uname -m)"
swiftc \
	-O \
	-swift-version 5 \
	-target "${ARCH}-apple-macos${DEPLOY_TARGET}" \
	-framework AppKit -framework WebKit -framework Network -framework ServiceManagement \
	-o "$APP/Contents/MacOS/Oculus" \
	"$HERE"/Sources/*.swift

echo "→ staging resources"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/i-see-you.html" "$ROOT/oculus.html" "$APP/Contents/Resources/web/"
cp -R "$HERE/Resources/web/vendor" "$APP/Contents/Resources/web/vendor"

# TCC keys the camera grant to the designated requirement. Signed with a real
# identity that is `identifier + certificate`, which survives a rebuild; ad-hoc
# it is the raw cdhash, which changes with every byte of the binary — so an
# ad-hoc build asks for the camera again every single time it is rebuilt.
IDENTITY="${OCULUS_SIGN_IDENTITY:-Oculus Local Signing}"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
	echo "→ signing as \"$IDENTITY\" (grant survives rebuilds)"
	codesign --force --sign "$IDENTITY" --identifier com.mattvigil.oculus "$APP" >/dev/null
else
	echo "→ signing ad-hoc — macOS will ask for the camera again after this build"
	echo "  (run ./make-signing-identity.sh once to stop that)"
	codesign --force --sign - --identifier com.mattvigil.oculus "$APP" >/dev/null
fi

echo
echo "Built: $APP"
du -sh "$APP" | awk '{print "Size:  " $1}'
echo
echo "Run it with:  open \"$APP\""
