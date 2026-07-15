#!/bin/bash
# Renders the two menu-bar states into a PNG, reusing the app's own glyph code.
# Usage: tools/export-thumbnail.sh [output.png]
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-thumbnail.png}"
FONTS="${2:-}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Take the app source minus its top-level bootstrap, then append the exporter.
# Top-level statements are only legal in a file called main.swift.
sed '/^let app = NSApplication.shared/,$d' AwakeToggle.swift > "$TMP/main.swift"
cat tools/export-thumbnail.swift >> "$TMP/main.swift"

swiftc -O -o "$TMP/export" "$TMP/main.swift"
"$TMP/export" "$OUT" "$FONTS"
