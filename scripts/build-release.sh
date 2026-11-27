#!/bin/bash
# Builds a Release Lingo.app and packages it as a .zip and a .dmg in dist/.
# Usage: scripts/build-release.sh
#
# The app is ad-hoc signed. To sign and notarize with a Developer ID, set
# SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" and NOTARY_PROFILE
# (a profile saved with `xcrun notarytool store-credentials`).
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v xcodegen >/dev/null; then xcodegen generate --quiet; fi

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
DERIVED=build/DerivedData
APP_SRC="$DERIVED/Build/Products/Release/Lingo.app"
DIST=dist
APP="$DIST/Lingo.app"

xcodebuild -project Lingo.xcodeproj -scheme Lingo -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath build/SourcePackages \
  build | grep -E 'error:|warning:|BUILD' || true
[ -d "$APP_SRC" ] || { echo "Build failed"; exit 1; }

rm -rf "$DIST" && mkdir -p "$DIST"
ditto "$APP_SRC" "$APP"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp \
    --entitlements App/Lingo.entitlements --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"

ZIP="$DIST/Lingo-$VERSION-arm64.zip"
DMG="$DIST/Lingo-$VERSION-arm64.dmg"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/Lingo.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Lingo $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

shasum -a 256 "$ZIP" "$DMG"
echo "Built $ZIP and $DMG"
