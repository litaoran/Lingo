#!/bin/bash
# Builds a Release Lingo.app and packages it as a .zip and a .dmg in dist/.
#
#   scripts/build-release.sh
#
# Without settings, the app is ad-hoc signed (fine for local use). For a public
# release, sign with a Developer ID and notarize:
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=lingo-notary \
#   scripts/build-release.sh
#
# NOTARY_PROFILE is a keychain profile created once with
# `xcrun notarytool store-credentials`.
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v xcodegen >/dev/null; then xcodegen generate --quiet; fi

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
DERIVED=build/DerivedData
APP_SRC="$DERIVED/Build/Products/Release/Lingo.app"
DIST=dist
APP="$DIST/Lingo.app"
ZIP="$DIST/Lingo-$VERSION-arm64.zip"
DMG="$DIST/Lingo-$VERSION-arm64.dmg"

xcodebuild -project Lingo.xcodeproj -scheme Lingo -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath build/SourcePackages \
  build | grep -E 'error:|BUILD' || true
[ -d "$APP_SRC" ] || { echo "Build failed"; exit 1; }

rm -rf "$DIST" && mkdir -p "$DIST"
ditto "$APP_SRC" "$APP"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "Signing with $SIGN_IDENTITY"
  # Sign nested code first, then the app itself (no --deep).
  find "$APP/Contents/Frameworks" -type f \( -name '*.dylib' -o -perm +111 \) 2>/dev/null | while read -r lib; do
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$lib"
  done
  codesign --force --options runtime --timestamp \
    --entitlements App/Lingo.entitlements --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

notarize() { # file
  echo "Notarizing $(basename "$1")…"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  # Notarize the app and staple its ticket so it opens offline too.
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  notarize "$DIST/notarize.zip"
  rm "$DIST/notarize.zip"
  xcrun stapler staple "$APP"
fi

ditto -c -k --keepParent "$APP" "$ZIP"

STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/Lingo.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Lingo $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl --assess --type execute --verbose=2 "$APP"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  fi
fi

shasum -a 256 "$ZIP" "$DMG"
echo "Built $ZIP and $DMG"
