#!/usr/bin/env bash
# Builds CaveOfNations and wraps it in a .app bundle with Info.plist and AppIcon.icns.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Cave of Nations"
PRODUCT="CaveOfNations"
BUNDLE_ID="com.example.CaveOfNations"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/.build/CaveOfNations.app"
RESOURCES_SRC="$ROOT/Sources/CaveOfNationsApp/Resources"

cd "$ROOT"
swift build -c release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$PRODUCT" "$APP_DIR/Contents/MacOS/$PRODUCT"
cp "$RESOURCES_SRC/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$RESOURCES_SRC/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$RESOURCES_SRC/Blocks" "$APP_DIR/Contents/Resources/Blocks"
cp -R "$RESOURCES_SRC/Characters" "$APP_DIR/Contents/Resources/Characters"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $PRODUCT" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $PRODUCT" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_DIR/Contents/Info.plist"

echo "Packaged: $APP_DIR"
