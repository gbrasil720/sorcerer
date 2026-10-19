#!/bin/sh
# Builds Sorcerer.app (release) next to this script.
#   ./bundle.sh                 this Mac's architecture, quick
#   UNIVERSAL=1 ./bundle.sh     Apple silicon + Intel, what releases ship
#   VERSION=0.2.0 ./bundle.sh   version shown in About and Finder (default: 0.4.0)
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-0.4.0}
if [ -n "$UNIVERSAL" ]; then set -- --arch arm64 --arch x86_64; fi
swift build -c release "$@"
# Ask SwiftPM where it put the binary: the folder differs between toolchains.
BIN="$(swift build -c release "$@" --show-bin-path)/Sorcerer"
APP=Sorcerer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"

# Icon: render the pixel hat, then build every size iconutil wants.
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
swift icon.swift "$ICONSET/icon_512x512@2x.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Sorcerer</string>
  <key>CFBundleDisplayName</key><string>Sorcerer</string>
  <key>CFBundleIdentifier</key><string>sh.onside.sorcerer</string>
  <key>CFBundleExecutable</key><string>Sorcerer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
EOF

# Ad-hoc signature: free, no Apple developer account. macOS still asks once before the
# first launch (see the README); notarize here instead if you ever have a Developer ID.
codesign --force --deep --sign - "$APP"
echo "built $(pwd)/$APP ($VERSION)"
