#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="NotchActivityBar"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

# Local dev signing identity — used for --install (fast inner-loop testing).
# Stable Team ID-backed identity avoids ad-hoc signing's per-build CDHash churn,
# which was breaking macOS's status-item scene registration across rebuilds.
DEV_SIGN_IDENTITY="Apple Development: Rysard Gvozdovic (SYWA449RD8)"

# Distribution signing identity — required for --release (Developer ID + notarization).
# Create this once via Xcode > Settings > Accounts > Manage Certificates > "+" >
# "Developer ID Application", or at developer.apple.com/account/resources/certificates.
DIST_SIGN_IDENTITY="Developer ID Application: Rysard Gvozdovic (5679JUAZRH)"

# Notarytool keychain profile name — create once with:
#   xcrun notarytool store-credentials "notch-activity-bar-notary" \
#     --apple-id "you@example.com" --team-id "SYWA449RD8" --password "app-specific-password"
NOTARY_PROFILE="notch-activity-bar-notary"

SPARKLE_TOOLS="$ROOT_DIR/Scripts/sparkle-tools"
GITHUB_REPO="dzekuza/NotchActivityBar"
APPCAST_PATH="$ROOT_DIR/appcast.xml"

INSTALL=0
RELEASE=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --release) RELEASE=1 ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--install] [--release]" >&2
            exit 1
            ;;
    esac
done

if [ "$RELEASE" = "1" ] && [ "$INSTALL" = "1" ]; then
    echo "--install and --release are mutually exclusive." >&2
    exit 1
fi

SIGN_IDENTITY="$DEV_SIGN_IDENTITY"
if [ "$RELEASE" = "1" ]; then
    SIGN_IDENTITY="$DIST_SIGN_IDENTITY"
fi

if [ "$RELEASE" = "1" ]; then
    "$ROOT_DIR/Scripts/fetch_sparkle_tools.sh"
fi

echo "Building release binary..."
cd "$ROOT_DIR"
swift build -c release

echo "Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE" "$ZIP_PATH" "$DMG_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Embedding Sparkle.framework..."
ditto "$BUILD_DIR/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
echo "Code signing Sparkle.framework's nested components with $SIGN_IDENTITY..."
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$SPARKLE_FRAMEWORK"

echo "Code signing $APP_NAME.app with $SIGN_IDENTITY..."
if [ "$RELEASE" = "1" ]; then
    # Release builds must NOT carry the get-task-allow debug entitlement from
    # NotchActivityBar.entitlements — Apple's notary service rejects it outright.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
    codesign --force --options runtime --timestamp --entitlements "$ROOT_DIR/Resources/NotchActivityBar.entitlements" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [ "$RELEASE" = "1" ]; then
    echo "Zipping for notarization..."
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    echo "Submitting to Apple notary service (this can take a few minutes)..."
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"
    rm -f "$ZIP_PATH"

    echo "Verifying Gatekeeper acceptance..."
    spctl --assess --type execute --verbose=4 "$APP_BUNDLE"

    echo "Creating DMG for distribution..."
    hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_PATH"

    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Resources/Info.plist")
    TAG="v$VERSION"
    DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/$APP_NAME.dmg"

    echo "Generating Sparkle appcast entry for $VERSION..."
    "$SPARKLE_TOOLS/generate_appcast" \
        --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/$TAG/" \
        -o "$APPCAST_PATH" \
        "$DIST_DIR"

    echo "Done: $DMG_PATH"
    echo
    echo "Next steps to publish this release:"
    echo "  1. git commit the updated appcast.xml and push to main."
    echo "  2. gh release create $TAG \"$DMG_PATH\" --title \"$APP_NAME $VERSION\" --notes \"...\""
    echo "     (the DMG must be uploaded at: $DOWNLOAD_URL)"
    echo "  Existing installs will pick up the update automatically via SUFeedURL."
elif [ "$INSTALL" = "1" ]; then
    echo "Installing to $INSTALLED_APP..."
    pkill -f "$INSTALLED_APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    rm -rf "$INSTALLED_APP"
    cp -R "$APP_BUNDLE" "$INSTALLED_APP"
    echo "Installed: $INSTALLED_APP"
    echo "Launching..."
    open "$INSTALLED_APP"
else
    echo "Done: $APP_BUNDLE"
    echo "Tip: run with --install for a local dev build in /Applications, or --release to sign, notarize, and package a distributable DMG."
fi
