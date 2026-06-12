#!/usr/bin/env bash
#
# Builds NekoRun for Release, ad-hoc signs it, and packages it as a
# drag-to-Applications DMG with a custom background, icon view, fixed
# window size, and positioned icons.
#
# Intended for distribution without a paid Apple Developer Program
# account — downloaders will see a Gatekeeper warning on first launch
# and have to approve via System Settings → Privacy & Security →
# Open Anyway.
#
# Output: release/NekoRun-<version>.dmg + SHA256 printed to stdout.

set -euo pipefail

# Make sure Homebrew tools (gh) are visible regardless of how the script
# is invoked.
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

PROJECT="NekoRun.xcodeproj"
SCHEME="NekoRun"
CONFIGURATION="Release"
APP_NAME="NekoRun.app"
VOLUME_NAME="NekoRun"
BACKGROUND_SRC="$PROJECT_DIR/scripts/dmg-background.png"

BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$PROJECT_DIR/release"

VERSION=$(xcodebuild -project "$PROJECT" -showBuildSettings -configuration "$CONFIGURATION" 2>/dev/null \
    | awk '/^[[:space:]]+MARKETING_VERSION[[:space:]]+=/{print $3; exit}')
[ -z "${VERSION:-}" ] && VERSION="dev"

DMG_PATH="$RELEASE_DIR/NekoRun-$VERSION.dmg"
RW_DMG="$BUILD_DIR/NekoRun-rw.dmg"
DMG_STAGE="$BUILD_DIR/dmg"

if [ ! -f "$BACKGROUND_SRC" ]; then
    echo "ERROR: missing $BACKGROUND_SRC — run scripts/generate-dmg-background.swift first." >&2
    exit 1
fi

echo "==> Cleaning"
rm -rf "$BUILD_DIR" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

echo "==> Building $SCHEME $CONFIGURATION (v$VERSION)"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR" \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    >/dev/null

APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: build did not produce $APP_PATH" >&2
    exit 1
fi

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "==> Staging DMG contents"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE/.background"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$BACKGROUND_SRC" "$DMG_STAGE/.background/background.png"

echo "==> Creating writable DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_STAGE" \
    -format UDRW \
    -ov \
    "$RW_DMG" >/dev/null

echo "==> Mounting"
ATTACH_OUTPUT=$(hdiutil attach "$RW_DMG" -nobrowse -noverify -noautoopen)
MOUNT_POINT=$(printf '%s\n' "$ATTACH_OUTPUT" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')
MOUNTED_VOLUME=$(basename "$MOUNT_POINT")
if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo "ERROR: could not determine mount point from hdiutil output:" >&2
    printf '%s\n' "$ATTACH_OUTPUT" >&2
    exit 1
fi

echo "==> Configuring Finder view (mounted at $MOUNT_POINT)"
osascript <<APPLESCRIPT
set bgFile to POSIX file "$MOUNT_POINT/.background/background.png"
tell application "Finder"
    tell disk "$MOUNTED_VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1000, 500}
        set viewOpts to the icon view options of container window
        set arrangement of viewOpts to not arranged
        set icon size of viewOpts to 96
        set background picture of viewOpts to bgFile
        set position of item "$APP_NAME" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Give Finder a moment to flush .DS_Store, then unmount (with a forced
# fallback because Finder occasionally holds the volume briefly).
sync
sleep 1
if ! hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1; then
    sleep 2
    hdiutil detach "$MOUNT_POINT" -force >/dev/null
fi

echo "==> Converting to compressed read-only DMG"
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" -ov >/dev/null
rm -f "$RW_DMG"

echo ""
echo "Output: $DMG_PATH"
shasum -a 256 "$DMG_PATH"

if [ "${SKIP_GH_RELEASE:-0}" = "1" ]; then
    exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
    echo ""
    echo "Note: 'gh' not installed — skipping GitHub Release upload."
    echo "      Install with 'brew install gh' or upload $DMG_PATH manually."
    exit 0
fi

TAG="v$VERSION"
echo ""
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "==> Updating GitHub Release $TAG"
    gh release upload "$TAG" "$DMG_PATH" --clobber
else
    echo "==> Creating GitHub Release $TAG"
    gh release create "$TAG" "$DMG_PATH" \
        --title "NekoRun $VERSION" \
        --notes "Drag-to-install DMG. Ad-hoc signed — on first launch, approve via System Settings → Privacy & Security → Open Anyway."
fi
