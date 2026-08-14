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
# Pinned to a SHA-1 hash (not the display name) because the keychain holds two
# valid "Developer ID Application: Rysard Gvozdovic" certs (a 2027 and a 2031
# one) and codesign refuses to pick between identically-named identities.
DIST_SIGN_IDENTITY="0615662DF591ED01904D50F128307AA40E019CE9"

# Notarytool keychain profile name — create once with:
#   xcrun notarytool store-credentials "notch-activity-bar-notary" \
#     --apple-id "you@example.com" --team-id "SYWA449RD8" --password "app-specific-password"
NOTARY_PROFILE="notch-activity-bar-notary"

SPARKLE_TOOLS="$ROOT_DIR/Scripts/sparkle-tools"
GITHUB_REPO="dzekuza/NotchActivityBar"
APPCAST_PATH="$ROOT_DIR/appcast.xml"

INSTALL=0
RELEASE=0
BUMP_VERSION=""
RELEASE_NOTES=""
while [ $# -gt 0 ]; do
    case "$1" in
        --install) INSTALL=1; shift ;;
        --release) RELEASE=1; shift ;;
        --bump)
            BUMP_VERSION="${2:-}"
            [ -n "$BUMP_VERSION" ] || { echo "--bump requires a version, e.g. --bump 1.0.1" >&2; exit 1; }
            shift 2
            ;;
        --notes)
            RELEASE_NOTES="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--install] [--release [--bump VERSION] [--notes \"...\"]]" >&2
            exit 1
            ;;
    esac
done

if [ "$RELEASE" = "1" ] && [ "$INSTALL" = "1" ]; then
    echo "--install and --release are mutually exclusive." >&2
    exit 1
fi

if [ -n "$BUMP_VERSION" ] && [ "$RELEASE" != "1" ]; then
    echo "--bump requires --release." >&2
    exit 1
fi

if [ -n "$BUMP_VERSION" ]; then
    if ! [[ "$BUMP_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo "--bump version must look like 1.2.3 (got: $BUMP_VERSION)" >&2
        exit 1
    fi

    TAG="v$BUMP_VERSION"
    if git -C "$ROOT_DIR" rev-parse "$TAG" >/dev/null 2>&1; then
        echo "Tag $TAG already exists locally." >&2
        exit 1
    fi
    REMOTE_TAG=$(env -u GITHUB_TOKEN git -C "$ROOT_DIR" ls-remote --tags origin "refs/tags/$TAG")
    if [ -n "$REMOTE_TAG" ]; then
        echo "Tag $TAG already exists on origin." >&2
        exit 1
    fi

    # Refuse to bundle unrelated in-progress work into an automated release commit.
    DIRTY_FILES=$(git -C "$ROOT_DIR" status --porcelain -- . ":(exclude)Resources/Info.plist" ":(exclude)appcast.xml")
    if [ -n "$DIRTY_FILES" ]; then
        echo "Working tree has uncommitted changes outside Info.plist/appcast.xml — commit or stash them first:" >&2
        echo "$DIRTY_FILES" >&2
        exit 1
    fi

    CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ROOT_DIR/Resources/Info.plist")
    NEW_BUILD=$((CURRENT_BUILD + 1))
    echo "Bumping version to $BUMP_VERSION (build $NEW_BUILD)..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BUMP_VERSION" "$ROOT_DIR/Resources/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$ROOT_DIR/Resources/Info.plist"
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
    DMG_STAGING="$DIST_DIR/dmg-staging"
    DMG_RW_PATH="$DIST_DIR/$APP_NAME-rw.dmg"
    rm -rf "$DMG_STAGING" "$DMG_RW_PATH"
    mkdir -p "$DMG_STAGING"
    ditto "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
    ln -s /Applications "$DMG_STAGING/Applications"

    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDRW -fs HFS+ "$DMG_RW_PATH"

    MOUNT_DIR=$(hdiutil attach "$DMG_RW_PATH" -readwrite -noverify -noautoopen | tail -1 | awk -F '\t' '{print $NF}')

    osascript <<OSASCRIPT
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 760, 460}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set position of item "$APP_NAME.app" of container window to {140, 160}
        set position of item "Applications" of container window to {420, 160}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
OSASCRIPT

    hdiutil detach "$MOUNT_DIR"
    hdiutil convert "$DMG_RW_PATH" -format UDZO -ov -o "$DMG_PATH"
    rm -rf "$DMG_RW_PATH" "$DMG_STAGING"

    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Resources/Info.plist")
    TAG="v$VERSION"
    DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/$APP_NAME.dmg"

    echo "Generating Sparkle appcast entry for $VERSION..."
    "$SPARKLE_TOOLS/generate_appcast" \
        --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/$TAG/" \
        -o "$APPCAST_PATH" \
        "$DIST_DIR"

    echo "Done: $DMG_PATH"

    if [ -n "$BUMP_VERSION" ]; then
        BRANCH=$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)
        NOTES="${RELEASE_NOTES:-Release $VERSION}"

        echo
        echo "Publishing $TAG..."
        git -C "$ROOT_DIR" add Resources/Info.plist "$APPCAST_PATH"
        git -C "$ROOT_DIR" commit -m "Release $TAG"
        env -u GITHUB_TOKEN git -C "$ROOT_DIR" push origin "$BRANCH"
        env -u GITHUB_TOKEN gh release create "$TAG" "$DMG_PATH" --title "$APP_NAME $VERSION" --notes "$NOTES"

        echo "Published: https://github.com/$GITHUB_REPO/releases/tag/$TAG"
        echo "Existing installs will pick up the update automatically via SUFeedURL."
    else
        echo
        echo "Next steps to publish this release:"
        echo "  1. git commit the updated appcast.xml and push to main."
        echo "  2. gh release create $TAG \"$DMG_PATH\" --title \"$APP_NAME $VERSION\" --notes \"...\""
        echo "     (the DMG must be uploaded at: $DOWNLOAD_URL)"
        echo "  Existing installs will pick up the update automatically via SUFeedURL."
        echo
        echo "Tip: pass --bump $VERSION (or a newer version) next time to automate this."
    fi
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
