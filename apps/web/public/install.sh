#!/bin/sh
# Installs the latest Sorcerer into /Applications.
#   curl -fsSL https://sorcererapp.dev/install.sh | sh
#
# Sorcerer isn't signed with a paid Apple developer account. A .dmg downloaded in a
# browser gets quarantined and macOS refuses to open it the first time; downloading
# with curl doesn't add that flag, so the app opens right away. The download is
# checked against the checksum published with the release.
set -eu

REPO="gbrasil720/sorcerer"
BASE="https://github.com/$REPO/releases/latest/download"

[ "$(uname -s)" = "Darwin" ] || { echo "Sorcerer is a macOS app." >&2; exit 1; }
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 15 ] || { echo "Sorcerer needs macOS 15 or later (this Mac has $(sw_vers -productVersion))." >&2; exit 1; }

tmp=$(mktemp -d)
mnt="$tmp/mnt"
cleanup() {
  hdiutil detach -quiet "$mnt" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

echo "→ downloading Sorcerer"
curl -fL --progress-bar "$BASE/Sorcerer.dmg" -o "$tmp/Sorcerer.dmg"
curl -fsSL "$BASE/Sorcerer.dmg.sha256" -o "$tmp/Sorcerer.dmg.sha256"

echo "→ checking the download"
expected=$(cut -d' ' -f1 "$tmp/Sorcerer.dmg.sha256")
actual=$(shasum -a 256 "$tmp/Sorcerer.dmg" | cut -d' ' -f1)
[ "$expected" = "$actual" ] || { echo "Checksum mismatch, not installing." >&2; exit 1; }

echo "→ installing"
mkdir -p "$mnt"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mnt" "$tmp/Sorcerer.dmg"

dest="/Applications"
[ -w "$dest" ] || dest="$HOME/Applications"
mkdir -p "$dest"
osascript -e 'quit app "Sorcerer"' >/dev/null 2>&1 || true
rm -rf "$dest/Sorcerer.app"
ditto "$mnt/Sorcerer.app" "$dest/Sorcerer.app"
xattr -dr com.apple.quarantine "$dest/Sorcerer.app" 2>/dev/null || true

echo "✓ Sorcerer installed in $dest"
open "$dest/Sorcerer.app"
