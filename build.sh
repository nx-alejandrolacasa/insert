#!/bin/bash
#
# Builds Insert and assembles a runnable macOS .app bundle.
#
# SwiftPM only produces a bare executable; a real app needs an Info.plist, an
# icon, and a code signature, so we wrap it here.
#
# Two variants, so the copy you use every day and a work-in-progress build can
# run side by side without fighting over settings, permissions or notes — the
# same split prtscn uses:
#   dev     → "Insert Dev.app", bundle id com.alejandrolacasa.insert.dev
#   release → "Insert.app",     bundle id com.alejandrolacasa.insert
# macOS keys the Documents-folder grant (TCC) and UserDefaults to the bundle id,
# so each variant asks for access once and keeps its own settings. Because the
# dev variant gets its own defaults it never inherits the real build's saved
# folder, and the app defaults it to ~/Documents/Insert Dev — so testing a delete
# or the completed-task sweep can't reach your real notes. It also wears a
# different menu-bar glyph (see MenuBarLabel) so two running copies are telling
# apart at a glance.
#
# Usage:
#   ./build.sh            build the DEV app bundle (build/Insert Dev.app)
#   ./build.sh run        build the dev app + (re)launch it
#   ./build.sh release    build the RELEASE bundle (build/Insert.app) —
#                         what CI does before packaging the DMG (see dmg.sh)
#   ./build.sh install    build the RELEASE app + install into /Applications
#   ./build.sh icon       regenerate the app icon (Resources/AppIcon.icon + .icns)

set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "install" || "${1:-}" == "release" ]]; then
  APP_NAME="Insert"
  BUNDLE_ID="com.alejandrolacasa.insert"
else
  APP_NAME="Insert Dev"
  BUNDLE_ID="com.alejandrolacasa.insert.dev"
fi

CONFIG="release"
# SwiftPM's product name is fixed; the bundle's executable is renamed per variant
# below so `pkill -x` and Activity Monitor show which one is running.
BIN=".build/${CONFIG}/Insert"
APP="build/${APP_NAME}.app"

# The generator emits two things from one set of proportions: a layered
# AppIcon.icon (unmasked full-bleed SVG layers, for macOS 26's Liquid Glass icon
# treatment) and the classic flat AppIcon.iconset, which still backs the .icns
# fallback below.
if [[ "${1:-}" == "icon" ]]; then
  swiftc tools/IconGenerator.swift -o tools/icongen
  ./tools/icongen
  iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
  rm -rf Resources/AppIcon.icon
  mv AppIcon.icon Resources/AppIcon.icon
  rm -rf AppIcon.iconset
  echo "Regenerated Resources/AppIcon.icon and Resources/AppIcon.icns"
  exit 0
fi

# --disable-sandbox: SwiftPM's own build sandbox can't nest inside CI/agent
# shells; harmless here since there are no third-party code dependencies.
swift build -c "$CONFIG" --disable-sandbox

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# The SwiftPM resource bundle — the two OFL fonts Insert bundles (see
# BundledFonts). SwiftPM emits it beside the executable; Contents/Resources is
# where it belongs in an app, and BundledFonts looks there first.
#
# Do NOT go back to trusting `Bundle.module` for this. Its generated accessor
# looks beside Contents/ and then at an absolute .build path on the machine that
# compiled the binary, so a CI-built 0.12.0 trapped at launch on every other Mac
# while every local build worked. BundledFonts finds the bundle itself now.
#
# A hard failure rather than a warning: Grotesk is the default face, so a bundle
# without this is a build that looks wrong everywhere and says nothing.
RESOURCE_BUNDLE=".build/${CONFIG}/Insert_Insert.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "error: no ${RESOURCE_BUNDLE} — SwiftPM did not emit the font resources." >&2
  exit 1
fi
ditto "$RESOURCE_BUNDLE" "$APP/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"

# App icon.
#
# macOS 26 can draw an app icon from *layers*, applying the Liquid Glass
# treatment and deriving the dark / clear / tinted variants, which needs
# Resources/AppIcon.icon compiled by actool (full Xcode only).
#
# This is the icon Insert ships. It spent a while opt-in because it rendered as a
# ghost of itself — the white cards all but invisible, badly worse than the flat
# icon — and the manifest turned out to be asking for exactly that: the background
# was `groups[0]`, which is the *front* of the stack, so a translucent gradient was
# painted over the cards, and each group carried Icon Composer's default
# translucency on top of that. Fixed in `iconManifest` (tools/IconGenerator.swift).
#
# The flat .icns stays as the fallback for a machine with only the Command Line
# Tools, where there's no actool to compile the layers. INSERT_LAYERED_ICON=0 forces
# that path for comparison.
ICON_COMPILED=0
if [[ "${INSERT_LAYERED_ICON:-1}" != "0" ]] \
    && [[ -d "Resources/AppIcon.icon" ]] && command -v actool >/dev/null 2>&1; then
  ICON_LOG="$(mktemp)"
  # Absolute paths on purpose: actool hands the job to a persistent helper
  # agent that keeps the working directory of its *first* launch, so a relative
  # --compile can resolve against some other checkout the agent was started
  # from — seen here as "output directory …/prtscn/… does not exist" while
  # building insert.
  ICON_CMD=(actool "$PWD/Resources/AppIcon.icon"
    --compile "$PWD/$APP/Contents/Resources"
    --platform macosx
    --minimum-deployment-target 26.0
    --app-icon AppIcon
    --output-partial-info-plist "$(mktemp)")

  # Launched through an inner `bash -c` on purpose. A misconfigured actool dies on
  # SIGABRT, and whichever shell owns that process announces it as a bare
  # "Abort trap: 6" — from this script it would land mid-build looking like our own
  # crash. Handing it to a child shell moves the announcement onto *that* shell's
  # stderr, which goes to the log with everything else.
  #
  # The `set +e; …; exit $?` matters: given a single command, `bash -c` execs it
  # and there's no child shell left to absorb the message.
  ICON_OK=0
  bash -c 'set +e; "$@"; exit $?' _ "${ICON_CMD[@]}" >"$ICON_LOG" 2>&1 && ICON_OK=1 || true

  if [[ "$ICON_OK" == "1" && -f "$APP/Contents/Resources/Assets.car" ]]; then
    ICON_COMPILED=1
    echo "Compiled Resources/AppIcon.icon (layered)."
  else
    echo "warning: could not compile Resources/AppIcon.icon — falling back to the"
    echo "         flat .icns, which forgoes the Liquid Glass icon treatment."
    grep -vE '^[[:space:]]*$|Abort trap' "$ICON_LOG" | sed 's/^/         /' | head -20
  fi
  rm -f "$ICON_LOG"
elif [[ "${INSERT_LAYERED_ICON:-1}" != "0" ]] && ! command -v actool >/dev/null 2>&1; then
  echo "note: no actool (full Xcode) — using the flat .icns, which forgoes the"
  echo "      Liquid Glass icon treatment."
fi

# Copied *after* actool on purpose. actool derives its own AppIcon.icns from the
# layers, but that render is a flat snapshot of art designed to be lit by the
# system — the cards lose the separation the effects were going to give them.
# Our hand-drawn one keeps its shadows and reads better, so it wins the fallback
# slot. On macOS 26 this file is largely moot anyway: CFBundleIconName below
# points the bundle at Assets.car.
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# The marketing version. Bump it here when cutting a release; the build number
# comes from git (commit count — monotonic and reproducible), so About and Finder
# always show which build this actually is. CI overrides the version from the
# pushed tag via INSERT_VERSION.
VERSION="${INSERT_VERSION:-0.19.1}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier ${BUNDLE_ID}" \
  -c "Set :CFBundleName ${APP_NAME}" \
  -c "Set :CFBundleDisplayName ${APP_NAME}" \
  -c "Set :CFBundleExecutable ${APP_NAME}" \
  -c "Set :CFBundleShortVersionString ${VERSION}" \
  -c "Set :CFBundleVersion ${BUILD_NUMBER}" \
  "$APP/Contents/Info.plist"

# Point the bundle at the compiled asset rather than the .icns. Only when the
# layered icon actually built — naming an icon that isn't in the bundle leaves the
# app with the generic placeholder, which is worse than the flat fallback.
if [[ "$ICON_COMPILED" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" \
    "$APP/Contents/Info.plist" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" \
      "$APP/Contents/Info.plist" >/dev/null
fi

# Code signing.
#
# macOS ties file-access permissions (TCC) to the app's signing identity, and
# Insert reads and writes a folder under ~/Documents. An ad-hoc signature ("-")
# changes every build, so macOS treats each rebuild as a new app and re-prompts
# for Documents access. Signing with a STABLE self-signed certificate keeps the
# identity constant, so you grant it once and it sticks.
#
# Two identities, so a locally-built copy and a released DMG don't fight over
# that grant: `release` (what CI runs) and `install` use the release cert, which
# also lives in CI as repo secrets; plain builds and `run` use the dev cert,
# which never leaves this machine. Create them once (see README → "Sign once,
# grant once"); override either name with INSERT_SIGN_IDENTITY.
if [[ "${1:-}" == "release" || "${1:-}" == "install" ]]; then
  SIGN_IDENTITY="${INSERT_SIGN_IDENTITY:-Insert Release}"
else
  SIGN_IDENTITY="${INSERT_SIGN_IDENTITY:-Insert Dev}"
fi

if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" "$APP"
  echo "Signed with '$SIGN_IDENTITY' (stable identity)."
else
  codesign --force --sign - "$APP"
  echo "warning: '$SIGN_IDENTITY' code-signing identity not found — used ad-hoc."
  echo "         macOS will re-prompt for Documents access on each rebuild."
  echo "         See README → 'Sign once, grant once' to fix this permanently."
fi

# One check on the artifact itself, rather than on the pieces that went into it.
# 0.12.0 shipped a DMG that trapped on launch, and every step of the build had
# reported success — so the last word is a look inside the app that is about to
# leave the machine.
for required in \
  "Contents/MacOS/${APP_NAME}" \
  "Contents/Resources/Insert_Insert.bundle/Fonts/SpaceGrotesk-Variable.ttf" \
  "Contents/Resources/Insert_Insert.bundle/Fonts/SpaceGrotesk-OFL.txt"; do
  if [[ ! -e "$APP/$required" ]]; then
    echo "error: assembled app is missing ${required}" >&2
    exit 1
  fi
done

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
