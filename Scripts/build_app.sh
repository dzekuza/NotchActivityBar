#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="NotchActivityBar"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"
# Stable Team ID-backed identity — avoids ad-hoc signing's per-build CDHash churn,
# which was breaking macOS's status-item scene registration across rebuilds.
SIGN_IDENTITY="Apple Development: Rysard Gvozdovic (SYWA449RD8)"

INSTALL=0
for arg in "$@"; do
    if [ "$arg" = "--install" ]; then
        INSTALL=1
    fi
done

echo "Building release binary..."
cd "$ROOT_DIR"
swift build -c release

echo "Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Code signing with $SIGN_IDENTITY..."
codesign --force --deep --options runtime --entitlements "$ROOT_DIR/Resources/NotchActivityBar.entitlements" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo "Done: $APP_BUNDLE"

if [ "$INSTALL" = "1" ]; then
    echo "Installing to $INSTALLED_APP..."
    pkill -f "$INSTALLED_APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    rm -rf "$INSTALLED_APP"
    cp -R "$APP_BUNDLE" "$INSTALLED_APP"
    echo "Installed: $INSTALLED_APP"
    echo "Launching..."
    open "$INSTALLED_APP"
else
    echo "Tip: run with --install to copy into /Applications and relaunch (needed for Launch at Login to persist)."
fi
