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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Compile asset catalog if present and non-empty
if [ -d "$APP_NAME/Resources/Assets.xcassets" ] && [ "$(ls -A "$APP_NAME/Resources/Assets.xcassets" 2>/dev/null)" ]; then
    echo "==> Compiling asset catalog…"
    xcrun actool "$APP_NAME/Resources/Assets.xcassets" \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0
fi

# Copy remaining resources (excluding .xcassets which was compiled)
if [ -d "$APP_NAME/Resources" ]; then
    rsync -a --exclude="Assets.xcassets" --exclude="*.entitlements" \
        "$APP_NAME/Resources/" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

echo ""
echo "App bundle created at: $APP_BUNDLE"
