#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/FaceCast.xcodeproj"
SCHEME="FaceCast"
CONFIGURATION="Release"
APP_NAME="FaceCast"
BUILD_DIR="$ROOT_DIR/build/package"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
ARCHIVE_APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
DIST_APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_STAGE_DIR="$BUILD_DIR/dmg"
DIST_DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
RW_DMG_PATH="$BUILD_DIR/$APP_NAME-temp.dmg"
DMG_BACKGROUND_PATH="$BUILD_DIR/dmg-background.png"
BACKGROUND_SCRIPT="$ROOT_DIR/scripts/render-dmg-background.py"
DERIVED_DATA_PATH="/tmp/${APP_NAME}DerivedData"
SKIP_DMG=0
DMG_DEVICE=""

usage() {
  cat <<'EOF'
Usage: ./scripts/package-mac.sh [--app-only]

Builds a Release archive and exports:
  - dist/FaceCast.app
  - dist/FaceCast.dmg

Options:
  --app-only   Build the .app only and skip .dmg creation.
  -h, --help   Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-only)
      SKIP_DMG=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

cleanup() {
  local exit_code=$?

  if [[ -n "$DMG_DEVICE" ]]; then
    hdiutil detach "$DMG_DEVICE" -quiet || hdiutil detach "$DMG_DEVICE" -force -quiet || true
  fi

  exit "$exit_code"
}

trap cleanup EXIT

require_command xcodebuild
require_command ditto

mkdir -p "$BUILD_DIR" "$DIST_DIR"
rm -rf "$ARCHIVE_PATH" "$DIST_APP_PATH" "$DMG_STAGE_DIR" "$DIST_DMG_PATH" "$RW_DMG_PATH" "$DERIVED_DATA_PATH" "$DMG_BACKGROUND_PATH"

echo "==> Archiving $APP_NAME ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  archive

if [[ ! -d "$ARCHIVE_APP_PATH" ]]; then
  echo "Archive finished, but app bundle was not found at:" >&2
  echo "  $ARCHIVE_APP_PATH" >&2
  exit 1
fi

echo "==> Exporting app bundle"
ditto "$ARCHIVE_APP_PATH" "$DIST_APP_PATH"

echo "==> Verifying output"
lipo -archs "$DIST_APP_PATH/Contents/MacOS/$APP_NAME"
codesign -dv --verbose=2 "$DIST_APP_PATH" 2>&1 | sed -n '1,8p'

if [[ "$SKIP_DMG" -eq 0 ]]; then
  require_command hdiutil
  require_command osascript
  require_command SetFile
  require_command bless
  require_command python3

  echo "==> Rendering dmg background"
  python3 "$BACKGROUND_SCRIPT" --output "$DMG_BACKGROUND_PATH"

  echo "==> Building styled dmg"
  mkdir -p "$DMG_STAGE_DIR/.background"
  ditto "$DIST_APP_PATH" "$DMG_STAGE_DIR/$APP_NAME.app"
  ln -s /Applications "$DMG_STAGE_DIR/Applications"
  ditto "$DMG_BACKGROUND_PATH" "$DMG_STAGE_DIR/.background/background.png"
  ditto "$DIST_APP_PATH/Contents/Resources/AppIcon.icns" "$DMG_STAGE_DIR/.VolumeIcon.icns"
  SetFile -a V "$DMG_STAGE_DIR/.VolumeIcon.icns"
  SetFile -a V "$DMG_STAGE_DIR/.background"

  hdiutil create \
    -fs HFS+ \
    -srcfolder "$DMG_STAGE_DIR" \
    -volname "$APP_NAME" \
    -ov \
    -format UDRW \
    "$RW_DMG_PATH"

  DMG_DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG_PATH" | awk '/^\/dev\// { print $1; exit }')"

  if [[ -z "$DMG_DEVICE" ]]; then
    echo "Failed to attach temporary dmg image." >&2
    exit 1
  fi

  MOUNT_DIR="/Volumes/$APP_NAME"

  SetFile -a V "$MOUNT_DIR/.VolumeIcon.icns"
  SetFile -a V "$MOUNT_DIR/.background"
  chflags hidden "$MOUNT_DIR/.background" "$MOUNT_DIR/.VolumeIcon.icns"
  bless --folder "$MOUNT_DIR"

  osascript <<EOF
 tell application "Finder"
   tell disk "$APP_NAME"
     open
     set current view of container window to icon view
     set toolbar visible of container window to false
     set statusbar visible of container window to false
     set the bounds of container window to {120, 120, 1080, 740}
     set viewOptions to the icon view options of container window
     set arrangement of viewOptions to not arranged
     set icon size of viewOptions to 128
     set text size of viewOptions to 14
     set background picture of viewOptions to file ".background:background.png"
     set position of item "$APP_NAME.app" of container window to {184, 410}
     set position of item "Applications" of container window to {664, 410}
     close
     open
     update without registering applications
     delay 2
   end tell
 end tell
EOF

  sync
  hdiutil detach "$DMG_DEVICE"
  DMG_DEVICE=""

  hdiutil convert "$RW_DMG_PATH" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DIST_DMG_PATH"

  echo "Created: $DIST_DMG_PATH"
else
  echo "Skipped dmg creation."
fi

echo "Created: $DIST_APP_PATH"
