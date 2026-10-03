#!/usr/bin/env bash
# Builds a versioned Jerox release into dist/:
#   Jerox-<version>.dmg     drag-to-Applications disk image
#   Jerox-<version>.pkg     macOS Installer package (installs to /Applications)
#   Jerox-<version>.zip     Sparkle update archive
#   appcast.xml             Sparkle feed (needs SPARKLE_PRIVATE_ED_KEY)
#   Jerox-<version>.sha256  checksums
#
# Usage: scripts/release.sh [version]        version defaults to the latest v* git tag
# Optional environment:
#   SIGN_IDENTITY       "Developer ID Application: Name (TEAMID)"  signs the app with the hardened runtime
#   INSTALLER_IDENTITY  "Developer ID Installer: Name (TEAMID)"    signs the .pkg
#   NOTARY_PROFILE      notarytool keychain profile                 notarizes and staples both files
#   RELAYOUT=1          re-arrange the DMG window in Finder and save it to installer/dmg-DS_Store
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+.][0-9A-Za-z.]+)?$ ]] || { echo "error: version must look like 1.2.3 (got '$VERSION')" >&2; exit 1; }
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

DIST=dist
DERIVED=build/release
APP="$DERIVED/Build/Products/Release/Jerox.app"
NAME="Jerox-$VERSION"
mkdir -p "$DIST"
rm -rf "$DERIVED" build/dmg build/pkgroot

step() { printf '\n▸ %s\n' "$*"; }

step "Building Jerox $VERSION (build $BUILD)"
SIGN_ARGS=()
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp)
fi
xcodebuild -quiet -project Jerox.xcodeproj -scheme Jerox -configuration Release -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} build

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # The vendored Sparkle.xcframework ships ad-hoc signed; Xcode's embed step
  # does not re-sign it with our identity. Re-sign inside out: nested XPC
  # services and helper tools first, then the framework, then the app.
  find "$APP" -type f \( -path "*.xpc/Contents/MacOS/*" -o -path "*/XPCServices/*/Contents/MacOS/*" \) -print0 \
    | while IFS= read -r -d '' BIN; do
        codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$BIN"
      done
  find "$APP" -type d -name "*.xpc" -print0 | while IFS= read -r -d '' XPC; do
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$XPC"
  done
  find "$APP/Contents/Frameworks" -maxdepth 1 -type d -name "*.framework" -print0 \
    | while IFS= read -r -d '' FW; do
        codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$FW"
      done
  # Re-signing the app drops its entitlements unless they are passed again; without
  # audio-input the hardened runtime blocks the microphone and no prompt ever appears.
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --entitlements Config/Jerox.entitlements "$APP"
fi

codesign --verify --deep --strict "$APP"
SHIPPED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$SHIPPED" == "$VERSION" ]] || { echo "error: app reports $SHIPPED, expected $VERSION" >&2; exit 1; }

step "Disk image"
mkdir -p build/dmg/.background
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
cp installer/dmg-background.tiff build/dmg/.background/background.tiff
[[ -f installer/dmg-DS_Store && "${RELAYOUT:-0}" != 1 ]] && cp installer/dmg-DS_Store build/dmg/.DS_Store
hdiutil create -quiet -ov -volname Jerox -srcfolder build/dmg -fs HFS+ -format UDRW build/rw.dmg
if [[ "${RELAYOUT:-0}" == 1 ]]; then
  MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen build/rw.dmg | awk -F'\t' '/\/Volumes\//{print $NF}')"
  osascript <<EOS
tell application "Finder"
  tell disk "Jerox"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set background picture of opts to file ".background:background.tiff"
    set position of item "Jerox.app" of container window to {165, 190}
    set position of item "Applications" of container window to {495, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOS
  sync
  cp "$MOUNT/.DS_Store" installer/dmg-DS_Store
  hdiutil detach -quiet "$MOUNT"
  echo "saved window layout to installer/dmg-DS_Store"
fi
rm -f "$DIST/$NAME.dmg"
hdiutil convert -quiet build/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$DIST/$NAME.dmg"
rm -f build/rw.dmg
[[ -n "${SIGN_IDENTITY:-}" ]] && codesign --sign "$SIGN_IDENTITY" --timestamp "$DIST/$NAME.dmg"

step "Installer package"
mkdir -p build/pkgroot/Applications
cp -R "$APP" build/pkgroot/Applications/
pkgbuild --analyze --root build/pkgroot build/component.plist >/dev/null
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' build/component.plist
PKG_SIGN=()
[[ -n "${INSTALLER_IDENTITY:-}" ]] && PKG_SIGN=(--sign "$INSTALLER_IDENTITY" --timestamp)
pkgbuild --quiet --root build/pkgroot --component-plist build/component.plist --install-location / \
  --identifier com.jxngrx.jerox.pkg --version "$VERSION" ${PKG_SIGN[@]+"${PKG_SIGN[@]}"} "$DIST/$NAME.pkg"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  step "Notarizing"
  for f in "$DIST/$NAME.dmg" "$DIST/$NAME.pkg"; do
    xcrun notarytool submit "$f" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$f"
  done
fi

step "Sparkle archive"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"

if [[ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]]; then
  SPARKLE_TOOLS=build/sparkle-2.10.0
  if [[ ! -x "$SPARKLE_TOOLS/bin/sign_update" ]]; then
    curl -fsSL -o build/Sparkle-2.10.0.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz
    mkdir -p "$SPARKLE_TOOLS"
    tar -xJf build/Sparkle-2.10.0.tar.xz -C "$SPARKLE_TOOLS"
  fi
  SIG_LINE="$(printf '%s\n' "$SPARKLE_PRIVATE_ED_KEY" | "$SPARKLE_TOOLS/bin/sign_update" --ed-key-file - "$DIST/$NAME.zip" | tr -d '\n')"
  DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"
  cat > "$DIST/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Jerox</title>
    <item>
      <title>Jerox $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.1</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/jxngrx/Jerox/releases/download/v$VERSION/$NAME.zip" $SIG_LINE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
else
  echo "warning: SPARKLE_PRIVATE_ED_KEY unset; wrote $NAME.zip but skipped appcast.xml" >&2
fi

HASHES=("$NAME.dmg" "$NAME.pkg" "$NAME.zip")
[[ -f "$DIST/appcast.xml" ]] && HASHES+=("appcast.xml")
( cd "$DIST" && shasum -a 256 "${HASHES[@]}" > "$NAME.sha256" )
step "Done"
ls -lh "$DIST"
