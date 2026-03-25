#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="UFCSwap"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"
STAGING_DIR="$DIST_DIR/dmg-root"
PLIST_TEMPLATE="$ROOT_DIR/Packaging/Info.plist.template"
VERSION_INPUT="${UFCSWAP_VERSION:-${GITHUB_REF_NAME:-}}"
VERSION="${VERSION_INPUT#v}"
if [[ -z "$VERSION" ]]; then
  VERSION="1.0.0"
fi
BUILD_NUMBER="${UFCSWAP_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
BUNDLE_IDENTIFIER="${UFCSWAP_BUNDLE_IDENTIFIER:-com.ufcswap.app}"
SIGN_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"
SIGNING_MODE="unsigned"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> Building release binary"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Release executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Resource bundle not found at $RESOURCE_BUNDLE" >&2
  exit 1
fi

echo "==> Creating app bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
sed \
  -e "s/__BUNDLE_IDENTIFIER__/$BUNDLE_IDENTIFIER/g" \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__BUILD__/$BUILD_NUMBER/g" \
  "$PLIST_TEMPLATE" > "$APP_BUNDLE/Contents/Info.plist"
printf "APPLUFCS" > "$APP_BUNDLE/Contents/PkgInfo"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if codesign --display --verbose=1 "$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
  codesign --remove-signature "$APP_BUNDLE/Contents/MacOS/$APP_NAME" || true
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> Signing app bundle with Developer ID"
  SIGNING_MODE="developer-id"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "==> Signing app bundle ad hoc"
  SIGNING_MODE="ad-hoc"
  codesign --force --deep --sign - "$APP_BUNDLE"
  echo "WARNING: APPLE_SIGNING_IDENTITY is not set. App bundle is ad-hoc signed for local packaging only."
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -dv --verbose=4 "$APP_BUNDLE" || true
if spctl --assess --type execute -vv "$APP_BUNDLE"; then
  echo "spctl assessment: accepted"
else
  echo "WARNING: spctl rejected $APP_BUNDLE."
  if [[ "$SIGNING_MODE" == "ad-hoc" ]]; then
    echo "WARNING: This is expected for ad-hoc/local builds. Gatekeeper acceptance requires a real Developer ID signature and notarization."
  fi
fi

echo "==> Creating ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Creating DMG"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> Signing DMG"
  codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
else
  echo "WARNING: DMG is unsigned for local packaging. Gatekeeper warnings are expected without Developer ID signing."
fi

if [[ -n "$SIGN_IDENTITY" && -n "$NOTARY_PROFILE" ]]; then
  echo "==> Notarizing DMG"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler staple "$DMG_PATH"
else
  echo "WARNING: Notarization skipped. Configure APPLE_SIGNING_IDENTITY and APPLE_NOTARY_PROFILE to enable notarization."
fi

echo "==> Release artifacts"
ls -lh "$APP_BUNDLE" "$DMG_PATH" "$ZIP_PATH"
