#!/bin/bash
# Links the real sources (minus main.swift) against the test file, so the tests
# exercise shipping code rather than a copy of it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

SOURCES=()
for f in "$HERE"/Sources/*.swift; do
	[[ "$(basename "$f")" == "main.swift" ]] && continue
	SOURCES+=("$f")
done

swiftc \
	-swift-version 5 \
	-target "$(uname -m)-apple-macos13.0" \
	-o "$OUT/tests" \
	"${SOURCES[@]}" "$HERE"/Tests/*.swift

"$OUT/tests"
