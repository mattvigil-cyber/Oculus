#!/bin/bash
# Creates a local, self-signed code-signing identity so Oculus keeps its camera
# permission across rebuilds. Run once. You only need this if you intend to keep
# rebuilding the app — an unchanged binary keeps its grant regardless.
#
# WHAT THIS CHANGES ON YOUR MACHINE
#   • Adds one self-signed certificate ("Oculus Local Signing") to your *login*
#     keychain, valid 10 years, marked trusted for code signing only.
#   • It is not a web/TLS trust root: the certificate carries the codeSigning
#     extended key usage and nothing else, so it cannot vouch for a website.
#   • Nothing is installed system-wide and no other software is affected.
#   • macOS will ask for your login password to modify keychain trust. That
#     prompt is from the OS, not from this script — nobody else sees it.
#
# TO UNDO
#   Open Keychain Access → login → Certificates → delete "Oculus Local Signing".
set -euo pipefail

NAME="Oculus Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$NAME"; then
	echo "\"$NAME\" already exists — nothing to do."
	echo "Rebuild with ./build.sh and it will be used automatically."
	exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ generating a self-signed code-signing certificate"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	-keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
	-subj "/CN=$NAME" \
	-addext "basicConstraints=critical,CA:false" \
	-addext "keyUsage=critical,digitalSignature" \
	-addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# A PKCS#12 bundle with an EMPTY password trips a long-standing MAC-encoding
# ambiguity between LibreSSL and Apple's Security framework: security(1) then
# fails with "MAC verification failed during PKCS12 import (wrong password?)",
# which is misleading — nothing is wrong with the password. A throwaway
# password sidesteps it. The .p12 never leaves $TMP, which is wiped on exit.
PW="$(openssl rand -hex 16)"

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
	-out "$TMP/identity.p12" -passout "pass:$PW" -name "$NAME" 2>/dev/null

echo "→ importing into your login keychain"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PW" -T /usr/bin/codesign -A

echo "→ trusting it for code signing (macOS will ask for your password)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$NAME"; then
	echo "Done. \"$NAME\" is now a valid signing identity."
	echo
	echo "Next:  ./build.sh && ./install.sh"
	echo "Allow the camera one final time, and it will stick from then on."
else
	echo "The certificate was created but macOS does not yet consider it a valid"
	echo "signing identity. Open Keychain Access → login → Certificates,"
	echo "double-click \"$NAME\", expand Trust, and set Code Signing to"
	echo "\"Always Trust\". Then re-run ./build.sh."
	exit 1
fi
