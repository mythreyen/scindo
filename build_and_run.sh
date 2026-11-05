#!/usr/bin/env bash
set -e

if [ -z "$DEVELOPER_DIR" ] && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo "==> Terminating any running instance of VolumeDialApp..."
killall VolumeDialApp 2>/dev/null || true

echo "==> Checking for XcodeGen..."
if ! command -v xcodegen &> /dev/null; then
    echo "Installing xcodegen via Homebrew..."
    brew install xcodegen
fi

echo "==> Generating VolumeDialApp.xcodeproj..."
xcodegen generate

echo "==> Building VolumeDialApp (Debug)..."
xcodebuild -project VolumeDialApp.xcodeproj \
           -scheme VolumeDialApp \
           -configuration Debug \
           -derivedDataPath ./build \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO \
           build

APP_PATH="./build/Build/Products/Debug/VolumeDialApp.app"
echo "==> Applying ad-hoc signature with CoreAudio entitlements..."
codesign --force --deep --sign - --entitlements Config/VolumeDialApp.entitlements "$APP_PATH"

echo "==> Ensuring previous instance is terminated before launching..."
killall VolumeDialApp 2>/dev/null || true

echo "==> Launching VolumeDialApp..."
open "$APP_PATH"
