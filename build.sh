#!/bin/sh
# Builds a universal (arm64 + x86_64) Pi Tunnel.app into ./build.
#
#   ./build.sh              build only
#   ./build.sh --install    also copy to ~/Applications, replacing a running copy, and launch
#   ./build.sh --release    also zip it as build/Pi-Tunnel-<version>.zip (notarized when possible)
#
# Signing: ad hoc by default. Set SIGN_IDENTITY to a "Developer ID Application: …"
# certificate name to sign for distribution, and NOTARY_PROFILE to a notarytool
# keychain profile (xcrun notarytool store-credentials) to notarize and staple.
set -eu
cd "$(dirname "$0")"

XCODE="${XCODE:-/Applications/Xcode.app/Contents/Developer}"
SWIFTC="$XCODE/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="$XCODE/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
[ -x "$SWIFTC" ] || SWIFTC="$(command -v swiftc)"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"
ARCHS="${ARCHS:-arm64 x86_64}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"

APP="build/Pi Tunnel.app"
rm -rf "$APP"
mkdir -p build/ModuleCache "$APP/Contents/MacOS" "$APP/Contents/Resources"

SLICES=""
for arch in $ARCHS; do
  "$SWIFTC" -O -module-name PiTunnel \
    -sdk "$SDK" -target "$arch-apple-macos13.0" \
    -module-cache-path build/ModuleCache \
    Sources/*.swift -o "build/PiTunnel-$arch"
  SLICES="$SLICES build/PiTunnel-$arch"
done
# shellcheck disable=SC2086
lipo -create $SLICES -output "$APP/Contents/MacOS/PiTunnel"

cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  echo "signed with $SIGN_IDENTITY"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
  echo "signed ad hoc (set SIGN_IDENTITY for distribution)"
fi
echo "built $APP ($VERSION, $ARCHS)"

case "${1:-}" in
  --install)
    DEST="$HOME/Applications/Pi Tunnel.app"
    mkdir -p "$HOME/Applications"
    pkill -x PiTunnel 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "installed and launched $DEST"
    ;;
  --release)
    ZIP="build/Pi-Tunnel-$VERSION.zip"
    rm -f "$ZIP"
    if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
      ditto -c -k --keepParent "$APP" "$ZIP"
      xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
      xcrun stapler staple "$APP"
      rm -f "$ZIP"
      echo "notarized and stapled"
    fi
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "release archive: $ZIP"
    ;;
esac
