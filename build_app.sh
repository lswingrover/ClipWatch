#!/bin/bash
# build_app.sh — Build ClipWatch.app and install to ~/Applications
# Usage: ./build_app.sh [--debug] [--no-install]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ClipWatch"
BUNDLE_ID="com.louisswingrover.clipwatch"
CONFIG="release"
NO_INSTALL=false
APP_VERSION=$(grep 'static let current' "$SCRIPT_DIR/Sources/ClipWatch/Version.swift" | sed 's/.*"\(.*\)".*/\1/')

for arg in "$@"; do
  case "$arg" in
    --debug)      CONFIG="debug" ;;
    --no-install) NO_INSTALL=true ;;
  esac
done

INSTALL_DIR="/Applications"
mkdir -p "$INSTALL_DIR"

APP_BUNDLE="$APP_NAME.app"
BUILD_DIR="$SCRIPT_DIR/.build"
BINARY="$BUILD_DIR/$CONFIG/$APP_NAME"
TMP_APP="/tmp/$APP_BUNDLE"

# ── 1. Build ───────────────────────────────────────────────────────────────────
echo ""
echo "▶ Building $APP_NAME ($CONFIG)..."
cd "$SCRIPT_DIR"
swift build -c "$CONFIG" 2>&1 | grep -E "error:|warning:|Build complete|Compiling" || true

if [[ ! -f "$BINARY" ]]; then
  echo "❌  Build failed — binary not found at $BINARY"
  exit 1
fi
echo "✅  Build complete: $BINARY"

# ── 2. Icon ────────────────────────────────────────────────────────────────────
ICON_DIR="/tmp/clipwatch_icon_build"
ICNS_PATH="$ICON_DIR/AppIcon.icns"
echo ""
echo "▶ Generating app icon..."
python3 "$SCRIPT_DIR/make_icon.py" "$ICON_DIR" 2>/dev/null && \
  echo "✅  Icon generated" || \
  echo "⚠️   Icon generation skipped — generic icon will be used"

# ── 3. Assemble .app bundle ────────────────────────────────────────────────────
echo ""
echo "▶ Assembling $APP_BUNDLE..."
rm -rf "$TMP_APP"
mkdir -p "$TMP_APP/Contents/MacOS"
mkdir -p "$TMP_APP/Contents/Resources"

cp "$BINARY" "$TMP_APP/Contents/MacOS/$APP_NAME"
chmod +x "$TMP_APP/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/support/Info.plist" "$TMP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$TMP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION"            "$TMP_APP/Contents/Info.plist"

if [[ -f "$ICNS_PATH" ]]; then
  cp "$ICNS_PATH" "$TMP_APP/Contents/Resources/AppIcon.icns"
  echo "   ✓ AppIcon.icns installed"
fi

echo "✅  Bundle assembled at $TMP_APP"

# ── 4. Ad-hoc code sign ────────────────────────────────────────────────────────
echo ""
echo "▶ Signing (ad-hoc)..."
codesign \
  --sign - \
  --force \
  --deep \
  --timestamp=none \
  --identifier "$BUNDLE_ID" \
  --options runtime \
  "$TMP_APP" 2>&1 | grep -v "replacing existing" || true
echo "✅  Signed"

# ── 5. Install ─────────────────────────────────────────────────────────────────
if [[ "$NO_INSTALL" == true ]]; then
  echo ""
  echo "▶ --no-install: app is at $TMP_APP"
  echo "   Run with: open '$TMP_APP'"
  exit 0
fi

echo ""
echo "▶ Installing to $INSTALL_DIR/$APP_BUNDLE..."

if [[ -d "/Applications/$APP_BUNDLE" ]]; then
  echo "   Removing old /Applications/$APP_BUNDLE..."
  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
  sleep 0.3
  rm -rf "/Applications/$APP_BUNDLE"
fi

if [[ -d "$INSTALL_DIR/$APP_BUNDLE" ]]; then
  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
  sleep 0.5
  rm -rf "$INSTALL_DIR/$APP_BUNDLE"
fi

cp -R "$TMP_APP" "$INSTALL_DIR/"
echo "✅  Installed"

# ── 6. Register with Launch Services ──────────────────────────────────────────
echo ""
echo "▶ Registering with Launch Services + clearing icon cache..."
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$LSREG" -kill -r -domain local -domain system -domain user 2>/dev/null || true
"$LSREG" "$INSTALL_DIR/$APP_BUNDLE" 2>/dev/null || true
rm -rf ~/Library/Caches/com.apple.iconservices.store 2>/dev/null || true
rm -rf ~/Library/Caches/com.apple.dock.iconcache      2>/dev/null || true
touch "$INSTALL_DIR/$APP_BUNDLE"
killall Finder 2>/dev/null || true
killall Dock   2>/dev/null || true
sleep 2
echo "✅  Registered + icon cache cleared"

# ── 7. Strip custom icon xattr ─────────────────────────────────────────────────
echo ""
echo "▶ Clearing custom icon xattr..."
xattr -d com.apple.FinderInfo   "$INSTALL_DIR/$APP_BUNDLE" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$INSTALL_DIR/$APP_BUNDLE" 2>/dev/null || true
echo "✅  Done"

# ── 8. Launch ──────────────────────────────────────────────────────────────────
echo ""
echo "▶ Launching $APP_NAME..."

# Step 6 restarts Dock + Finder to refresh icons, which briefly destabilises
# LaunchServices. Firing `open` into that window returns:
#     _LSOpenURLsWithCompletionHandler() failed with error -600
# (-600 = procNotFound). Under `set -euo pipefail` that aborts the whole build,
# leaving the app installed but NOT running. The `sleep 2` above narrows the
# window but does not close it.
#
# And `open`'s exit status is not proof of life — it can return 0 while the app
# crashes seconds later on launch. The only honest signal is the process being
# up, so poll for it rather than claiming success blind.
relaunched=false
for attempt in 1 2 3 4 5; do
    open "$INSTALL_DIR/$APP_BUNDLE" 2>/dev/null || true
    for _ in $(seq 1 10); do
        if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            relaunched=true
            break
        fi
        sleep 0.5
    done
    [[ "$relaunched" == true ]] && break
    [[ "$attempt" -lt 5 ]] && echo "   · launch attempt $attempt failed, retrying…"
    sleep "$attempt"
done

if [[ "$relaunched" != true ]]; then
    echo "" >&2
    echo "✗  Launch FAILED — $APP_NAME is NOT running." >&2
    echo "   The build IS installed at $INSTALL_DIR/$APP_BUNDLE —" >&2
    echo "   only the automatic launch failed. Start it manually:" >&2
    echo "" >&2
    echo "       open -a $APP_NAME" >&2
    echo "" >&2
    exit 1
fi
echo "✅  Launched (verified running)"

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║  ClipWatch installed to /Applications ✅     ║"
echo "║                                               ║"
echo "║  Look for the clipboard icon in your menu bar ║"
echo "║  Grant Accessibility access when prompted     ║"
echo "╚═══════════════════════════════════════════════╝"
