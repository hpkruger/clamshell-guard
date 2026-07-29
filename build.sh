#!/bin/bash
# Builds Clamshell Guard.app as a universal binary (Intel + Apple silicon), macOS 12+.
# Requires only the Xcode Command Line Tools: xcode-select --install
set -euo pipefail

APP="Clamshell Guard.app"
EXECUTABLE="ClamshellGuard"
ARCHIVE="ClamshellGuard.zip"
BUILD="build"
DEPLOY_TARGET="12.0"

rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD" "$APP/Contents/MacOS"

for arch in arm64 x86_64; do
    swiftc -O \
        -target "${arch}-apple-macos${DEPLOY_TARGET}" \
        -lsqlite3 \
        -framework IOKit \
        -o "$BUILD/$EXECUTABLE-$arch" \
        ClamshellGuard.swift CodexIPCMonitor.swift SystemSleepAssertion.swift \
        ClamshellDisplaySleepController.swift
done

lipo -create "$BUILD/$EXECUTABLE-arm64" "$BUILD/$EXECUTABLE-x86_64" \
     -output "$APP/Contents/MacOS/$EXECUTABLE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Clamshell Guard</string>
    <key>CFBundleDisplayName</key><string>Clamshell Guard</string>
    <key>CFBundleIdentifier</key><string>com.hpkruger.clamshellguard</string>
    <key>CFBundleVersion</key><string>1.1.0</string>
    <key>CFBundleShortVersionString</key><string>1.1.0</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>${DEPLOY_TARGET}</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
rm -rf "$BUILD"

echo "Built $APP"
lipo -archs "$APP/Contents/MacOS/$EXECUTABLE"

# Package for distribution. ditto preserves the bundle structure that a plain
# `zip` would flatten.
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
echo "Packaged $ARCHIVE"
