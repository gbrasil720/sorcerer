#!/bin/sh
# Builds Sorcerer.app (release) next to this script.
set -e
cd "$(dirname "$0")"
swift build -c release
APP=Sorcerer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Sorcerer "$APP/Contents/MacOS/"

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
  <key>CFBundleIdentifier</key><string>sh.onside.sorcerer</string>
  <key>CFBundleExecutable</key><string>Sorcerer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
echo "built $(pwd)/$APP"
