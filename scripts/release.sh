#!/usr/bin/env bash
#
# Builds NekoRun for Release, ad-hoc signs it, and packages it as a
# drag-to-Applications DMG. Intended for distribution without a paid
# Apple Developer Program account — users will see a Gatekeeper warning
# on first launch and have to approve in System Settings → Privacy &
# Security → Open Anyway.
#
# Output: release/NekoRun-<version>.dmg + SHA256 printed to stdout.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

PROJECT="NekoRun.xcodeproj"
SCHEME="NekoRun"
CONFIGURATION="Release"
APP_NAME="NekoRun.app"
VOLUME_NAME="NekoRun"

BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$PROJECT_DIR/release"

VERSION=$(xcodebuild -project "$PROJECT" -showBuildSettings -configuration "$CONFIGURATION" 2>/dev/null \
    | awk '/^[[:space:]]+MARKETING_VERSION[[:space:]]+=/{print $3; exit}')
[ -z "${VERSION:-}" ] && VERSION="dev"

DMG_PATH="$RELEASE_DIR/NekoRun-$VERSION.dmg"

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
DMG_STAGE="$BUILD_DIR/dmg"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

echo "==> Creating $DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_STAGE" \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

echo ""
echo "Output: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
