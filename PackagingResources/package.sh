#!/usr/bin/env bash
set -euo pipefail

# Build, optionally bundle Python and wheels, codesign, and create a DMG.

SCHEME="Spotlight Music"
CONFIG="Release"
BUNDLE_ID=""
VERSION="1.0.0"
SIGN_ID=""
BUNDLE_PYTHON=""
WHEELS_DIR=""
PROJECT_PATH="Spotlight Music.xcodeproj"
APP_NAME="Spotlight Music.app"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme) SCHEME="$2"; shift 2;;
    --config) CONFIG="$2"; shift 2;;
    --bundle-id) BUNDLE_ID="$2"; shift 2;;
    --version) VERSION="$2"; shift 2;;
    --sign) SIGN_ID="$2"; shift 2;;
    --bundle-python) BUNDLE_PYTHON="$2"; shift 2;;
    --wheels-dir) WHEELS_DIR="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

ROOT_DIR=$(pwd)
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$BUILD_DIR/$CONFIG/$APP_NAME"
RES_DIR="$APP_PATH/Contents/Resources"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

# 1) Build
BUILD_SIGN_FLAG=()
if [[ -z "$SIGN_ID" ]]; then
  BUILD_SIGN_FLAG+=("CODE_SIGNING_ALLOWED=NO")
fi
xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration "$CONFIG" -derivedDataPath "$BUILD_DIR/DerivedData" -quiet build "${BUILD_SIGN_FLAG[@]}"

# Find the .app in DerivedData if needed
if [[ ! -d "$APP_PATH" ]]; then
  APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME" -type d | head -n1)
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found after build" >&2; exit 1
fi

mkdir -p "$RES_DIR"

# 2) Bundle Python runtime (optional)
if [[ -n "$BUNDLE_PYTHON" ]]; then
  echo "Bundling Python from $BUNDLE_PYTHON"
  rsync -a --delete "$BUNDLE_PYTHON"/ "$RES_DIR/BundledPython"/
  chmod +x "$RES_DIR/BundledPython/bin/python3" || true
fi

# 3) Bundle wheels (optional)
if [[ -n "$WHEELS_DIR" ]]; then
  echo "Bundling wheels from $WHEELS_DIR"
  mkdir -p "$RES_DIR/PythonWheels"
  rsync -a --delete "$WHEELS_DIR"/ "$RES_DIR/PythonWheels"/
fi

# 4) Codesign (optional)
if [[ -n "$SIGN_ID" ]]; then
  echo "Codesigning with $SIGN_ID"
  codesign --force --deep --options runtime --sign "$SIGN_ID" "$APP_PATH"
fi

# 5) Create DMG
DMG_PATH="$DIST_DIR/Spotlight-Music-$VERSION.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "Spotlight Music" -srcfolder "$APP_PATH" -format UDZO "$DMG_PATH"

echo "DMG created at: $DMG_PATH"
