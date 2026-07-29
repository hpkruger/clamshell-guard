#!/bin/bash
# Builds AwakeToggle.app as a universal binary (Intel + Apple silicon), macOS 12+.
# Requires only the Xcode Command Line Tools: xcode-select --install
set -euo pipefail

APP="AwakeToggle.app"
BUILD="build"
DEPLOY_TARGET="12.0"

rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD" "$APP/Contents/MacOS"

for arch in arm64 x86_64; do
    swiftc -O \
        -target "${arch}-apple-macos${DEPLOY_TARGET}" \
        -o "$BUILD/AwakeToggle-$arch" \
        AwakeToggle.swift
    swiftc -O \
        -target "${arch}-apple-macos${DEPLOY_TARGET}" \
        -o "$BUILD/AwakeToggleHook-$arch" \
        AwakeToggleHook.swift
done

lipo -create "$BUILD/AwakeToggle-arm64" "$BUILD/AwakeToggle-x86_64" \
     -output "$APP/Contents/MacOS/AwakeToggle"
lipo -create "$BUILD/AwakeToggleHook-arm64" "$BUILD/AwakeToggleHook-x86_64" \
     -output "$APP/Contents/MacOS/AwakeToggleHook"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AwakeToggle</string>
    <key>CFBundleDisplayName</key><string>AwakeToggle</string>
    <key>CFBundleIdentifier</key><string>com.machinefriendly.awaketoggle</string>
    <key>CFBundleVersion</key><string>1.0.1</string>
    <key>CFBundleShortVersionString</key><string>1.0.1</string>
    <key>CFBundleExecutable</key><string>AwakeToggle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>${DEPLOY_TARGET}</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
rm -rf "$BUILD"

echo "Built $APP"
lipo -archs "$APP/Contents/MacOS/AwakeToggle"

# Package for distribution. ditto preserves the bundle structure that a plain
# `zip` would flatten.
rm -f AwakeToggle.zip
ditto -c -k --sequesterRsrc --keepParent "$APP" AwakeToggle.zip
echo "Packaged AwakeToggle.zip"
