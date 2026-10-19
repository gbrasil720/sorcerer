#!/bin/sh
# Packs Sorcerer.app into Sorcerer.dmg with a shortcut to /Applications.
#   UNIVERSAL=1 VERSION=0.1.0 ./dmg.sh
set -e
cd "$(dirname "$0")"
./bundle.sh
STAGE=$(mktemp -d)
cp -R Sorcerer.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f Sorcerer.dmg
hdiutil create -volname "Sorcerer" -srcfolder "$STAGE" -ov -format UDZO Sorcerer.dmg >/dev/null
echo "packed $(pwd)/Sorcerer.dmg ($(du -h Sorcerer.dmg | cut -f1))"
