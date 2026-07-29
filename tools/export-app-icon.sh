#!/bin/bash
# Generates a complete macOS iconset from the app's open-lid menu glyph.
# Usage: tools/export-app-icon.sh <output.iconset>
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:?output .iconset path is required}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Compile the shipping drawLaptop() implementation together with the iconset
# renderer, so the app icon uses exactly the same geometry as the menu glyph.
{
    sed -n '1,2p' ClamshellGuard.swift
    sed -n '/^func drawLaptop(closed:/,/^}$/p' ClamshellGuard.swift
    cat tools/export-app-icon.swift
} > "$TMP/main.swift"

swiftc -O -o "$TMP/export-app-icon" "$TMP/main.swift"
"$TMP/export-app-icon" "$OUT"
