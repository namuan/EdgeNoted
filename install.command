#!/bin/bash
set -euo pipefail

# EdgeNoted installer
# Builds the app with SwiftPM (no Xcode needed) and installs it into
# ~/Applications. Double-click this file in Finder, or run:
#   bash install.command
# after a rebuild.

# --- Toolchain checks -------------------------------------------------------
if ! command -v swift >/dev/null 2>&1; then
    echo "Error: 'swift' was not found."
    echo "Install Xcode Command Line Tools with:"
    echo "  xcode-select --install"
    exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Error: No active developer directory was found."
    echo "Install Xcode Command Line Tools with:"
    echo "  xcode-select --install"
    exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="EdgeNoted"
BUNDLE_ID="com.github.namuan.edgenoted"
BUILT_APP="$ROOT/Build/$APP_NAME.app"
DESTINATION_DIRECTORY="$HOME/Applications"
DESTINATION_APP="$DESTINATION_DIRECTORY/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "Stopping running application copies..."
pkill -x "$APP_NAME" 2>/dev/null || true

echo "Building $APP_NAME with Swift Package Manager..."
"$ROOT/Scripts/build-app.sh"

if [[ ! -d "$BUILT_APP" ]]; then
    echo "Error: Build succeeded but the app bundle was not found at:"
    echo "  $BUILT_APP"
    exit 1
fi

echo "Installing $APP_NAME in $DESTINATION_DIRECTORY..."
mkdir -p "$DESTINATION_DIRECTORY"
rm -rf "$DESTINATION_APP"
mv "$BUILT_APP" "$DESTINATION_APP"

INSTALLED_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION_APP/Contents/Info.plist")"
if [[ "$INSTALLED_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
    echo "Error: Installed bundle identifier is '$INSTALLED_BUNDLE_ID', expected '$BUNDLE_ID'."
    exit 1
fi

# tccutil resolves bundle identifiers through Launch Services. A newly built
# app has not been registered yet, so resetting its permissions otherwise
# fails with OSStatus -10814.
echo "Registering $APP_NAME with Launch Services..."
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$DESTINATION_APP"
else
    echo "Warning: Launch Services registration tool was not found."
fi

# EdgeNoted is ad-hoc signed, so TCC grants from a previous build do not carry
# over anyway; resetting gives a clean slate and a fresh permission prompt.
echo "Clearing previous macOS privacy permissions..."
if command -v tccutil >/dev/null 2>&1; then
    if ! tccutil reset AppleEvents "$BUNDLE_ID"; then
        echo "Warning: Automation had no resettable permission record."
    fi
    if ! tccutil reset Reminders "$BUNDLE_ID"; then
        echo "Warning: Reminders had no resettable permission record."
    fi
else
    echo "Warning: tccutil was not found; permissions could not be reset."
fi

codesign --verify --deep --strict "$DESTINATION_APP"

echo
echo "Installed: $DESTINATION_APP"
echo "Automation (Apple Notes/Reminders) and Reminders permissions were reset."
echo "EdgeNoted will ask you to grant them again on first use."
echo "EdgeNoted is an agent app with no Dock icon; show the panel with the"
echo "global shortcut (default Ctrl+Shift+N) or the Open Bar at the screen edge."
echo "Logs: $HOME/Library/Logs/EdgeNoted/EdgeNoted.log"
echo

open "$DESTINATION_APP"
