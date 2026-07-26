#!/bin/bash
#
# Builds Insert and assembles a runnable macOS .app bundle.
#
# SwiftPM only produces a bare executable; a real app needs an Info.plist, an
# icon, and a code signature, so we wrap it here.
#
# Usage:
#   ./build.sh            build the app bundle (build/Insert.app)
#   ./build.sh run        build + (re)launch it
#   ./build.sh install    build + install into /Applications and relaunch
#   ./build.sh icon       regenerate the app icon (Resources/AppIcon.icns)

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Insert"
BUNDLE_ID="com.alejandrolacasa.insert"
CONFIG="release"
BIN=".build/${CONFIG}/Insert"
APP="build/${APP_NAME}.app"

if [[ "${1:-}" == "icon" ]]; then
  swiftc tools/IconGenerator.swift -o tools/icongen
  ./tools/icongen
  iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
  echo "Regenerated Resources/AppIcon.icns"
  exit 0
fi

# --disable-sandbox: SwiftPM's own build sandbox can't nest inside CI/agent
# shells; harmless here since there are no third-party dependencies.
swift build -c "$CONFIG" --disable-sandbox

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

VERSION="${INSERT_VERSION:-0.1.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier ${BUNDLE_ID}" \
  -c "Set :CFBundleName ${APP_NAME}" \
  -c "Set :CFBundleDisplayName ${APP_NAME}" \
  -c "Set :CFBundleExecutable ${APP_NAME}" \
  -c "Set :CFBundleShortVersionString ${VERSION}" \
  -c "Set :CFBundleVersion ${BUILD_NUMBER}" \
  "$APP/Contents/Info.plist"

# Stable-identity signing if available, else ad-hoc.
SIGN_IDENTITY="${INSERT_SIGN_IDENTITY:-Insert Dev}"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" "$APP"
  echo "Signed with '$SIGN_IDENTITY'."
else
  codesign --force --sign - "$APP"
fi

echo "Built ${APP}"

# Quit a running copy and wait for it to actually go away: LaunchServices
# answers -600 ("kLSNoExecutableErr" / procNotFound) if asked to relaunch while
# the old instance is still tearing down.
quit_running() {
  pkill -x "$APP_NAME" 2>/dev/null || true
  for _ in $(seq 1 50); do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
}

# …and retry once anyway, in case the teardown finished after the check.
launch() {
  open "$1" 2>/dev/null && return 0
  sleep 0.5
  open "$1"
}

if [[ "${1:-}" == "run" ]]; then
  quit_running
  launch "$APP"
fi

if [[ "${1:-}" == "install" ]]; then
  quit_running
  rm -rf "/Applications/${APP_NAME}.app"
  ditto "$APP" "/Applications/${APP_NAME}.app"
  launch "/Applications/${APP_NAME}.app"
  echo "Installed /Applications/${APP_NAME}.app"
fi
