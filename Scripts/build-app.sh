#!/bin/bash
set -euo pipefail

APP_NAME="EdgeNoted"
BUNDLE_ID="com.github.namuan.edgenoted"
CONFIGURATION="${CONFIGURATION:-release}"
BUILD_DIR=".build"
APP_BUNDLE="Build/$APP_NAME.app"

echo "==> Building $APP_NAME with SwiftPM ($CONFIGURATION)..."
swift build -c "$CONFIGURATION"

echo "==> Creating app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the compiled binary
BIN_PATH=$(swift build -c "$CONFIGURATION" --show-bin-path)
cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Generate Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.6</string>
    <key>CFBundleVersion</key>
    <string>16</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>EdgeNoted reads and writes your Apple Notes so they stay in sync with the edge panel.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>EdgeNoted needs access to your reminders to show and manage due tasks.</string>
</dict>
</plist>
EOF

# Build the app icon into AppIcon.icns. Apple's `actool` (which normally
# compiles an .xcassets catalog) only ships inside full Xcode, not Command
# Line Tools, so this build must not depend on it. Instead we generate the
# .icns from the largest PNG in the asset catalog using /usr/bin/sips and
# /usr/bin/iconutil, both of which ship with macOS and Command Line Tools.
ICON_SOURCE=""
ICONSET_DIR="$APP_NAME/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICONSET_DIR" ]; then
    BIGGEST=0
    for f in "$ICONSET_DIR"/*.png; do
        [ -f "$f" ] || continue
        size=$(stat -f%z "$f")
        if [ "$size" -gt "$BIGGEST" ]; then
            BIGGEST=$size
            ICON_SOURCE=$f
        fi
    done
fi
if [ -n "$ICON_SOURCE" ]; then
    echo "==> Generating AppIcon.icns from $(basename "$ICON_SOURCE")…"
    TMP_DIR=$(mktemp -d)
    TMP_ICONSET="$TMP_DIR/AppIcon.iconset"
    mkdir -p "$TMP_ICONSET"
    # The classic 10-file macOS iconset: each base size plus its @2x variant.
    while read -r size name; do
        sips -z "$size" "$size" "$ICON_SOURCE" --out "$TMP_ICONSET/$name" >/dev/null
    done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES
    iconutil -c icns "$TMP_ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$TMP_DIR"
else
    echo "==> No app icon found; skipping icon generation"
fi

# Copy remaining resources (excluding the asset catalog, already handled above)
if [ -d "$APP_NAME/Resources" ]; then
    rsync -a --exclude="Assets.xcassets" --exclude="*.entitlements" \
        "$APP_NAME/Resources/" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

# Sign with entitlements (ad-hoc). A real developer identity can be used by
# setting CODE_SIGN_IDENTITY in the environment; without it the TCC automation
# permission may be re-requested after each rebuild.
echo "==> Signing app bundle…"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
codesign --force --deep --sign "$CODE_SIGN_IDENTITY" \
    --entitlements "$APP_NAME/Resources/EdgeNoted.entitlements" \
    "$APP_BUNDLE"

echo ""
echo "App bundle created at: $APP_BUNDLE"
