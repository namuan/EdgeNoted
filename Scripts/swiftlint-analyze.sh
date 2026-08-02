#!/bin/bash
set -euo pipefail

APP_NAME="EdgeNoted"
DERIVED_DATA_PATH="DerivedData/SwiftLintAnalyze"
BUILD_LOG="$DERIVED_DATA_PATH/xcodebuild.log"

# Analyzer rules need a clean, full compiler invocation. SwiftLint consumes
# the Xcode build log, so generate the project and build it entirely by CLI.
xcodegen generate
rm -rf "$DERIVED_DATA_PATH"
mkdir -p "$DERIVED_DATA_PATH"
xcodebuild test     -project "$APP_NAME.xcodeproj"     -scheme "$APP_NAME"     -destination 'platform=macOS'     -derivedDataPath "$DERIVED_DATA_PATH"     -skipPackagePluginValidation     -skipMacroValidation     2>&1 | tee "$BUILD_LOG"

swiftlint analyze --strict --compiler-log-path "$BUILD_LOG"
