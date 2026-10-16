#!/bin/bash
# Installs the latest Music Video Maker release on a Mac — no Xcode, no building.
#   curl -fsSL https://raw.githubusercontent.com/drawsomerex/music-video-maker/main/install.sh | bash
# (curl-downloaded files aren't quarantined, so macOS opens the app without the "unidentified developer" warning.)
set -euo pipefail
REPO="${MV_REPO:-drawsomerex/music-video-maker}"
die() { printf "\n✗ %s\n" "$*" >&2; exit 1; }
[ -n "$REPO" ] || die "This installer hasn't been pointed at a repo yet (release.sh does that on first publish)."
[ "$(uname -m)" = "arm64" ] || die "This app needs an Apple Silicon Mac (M1 or newer)."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || die "macOS 14 or newer is required."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "Looking up the latest release of ${REPO}…"
JSON="$(curl -fsSL -H 'Accept: application/vnd.github+json' "${MV_API:-https://api.github.com/repos/$REPO/releases/latest}")"
URL="$(printf '%s' "$JSON" | grep -o '"browser_download_url": *"[^"]*native[^"]*\.zip"' | head -1 | sed -E 's/.*"(https?[^"]*)"/\1/')"
SHA_URL="$(printf '%s' "$JSON" | grep -o '"browser_download_url": *"[^"]*native[^"]*\.zip\.sha256"' | head -1 | sed -E 's/.*"(https?[^"]*)"/\1/')"
[ -n "$URL" ] || die "No downloadable build found in the latest release."
echo "Downloading $(basename "$URL")…"
curl -fL --progress-bar "$URL" -o "$TMP/app.zip"
if [ -n "$SHA_URL" ]; then
  WANT="$(curl -fsSL "$SHA_URL" | awk '{print $1}')"; GOT="$(shasum -a 256 "$TMP/app.zip" | awk '{print $1}')"
  [ "$WANT" = "$GOT" ] || die "Download didn't match its checksum — not installing."
fi
ditto -x -k "$TMP/app.zip" "$TMP/out"
APP="$(find "$TMP/out" -maxdepth 1 -name '*.app' | head -1)"; [ -n "$APP" ] || die "The download didn't contain an app."
DEST="${MV_DEST:-/Applications}"
[ -n "${MV_DEST:-}" ] || pkill -x MusicVideoApp 2>/dev/null || true
mkdir -p "$DEST"; rm -rf "$DEST/Music Video Maker.app"; cp -R "$APP" "$DEST/Music Video Maker.app"
xattr -dr com.apple.quarantine "$DEST/Music Video Maker.app" 2>/dev/null || true
echo "Installed: $DEST/Music Video Maker.app"
echo "Open it from Launchpad or Spotlight. The first launch offers a one-time download of the speech and language models."
echo "From then on it updates itself."
