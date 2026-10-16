#!/bin/bash
# Installs the latest Music Video Maker release on a Mac — no Xcode, no building.
#   gh api repos/drawsomerex/music-video-maker/contents/install.sh -H 'Accept: application/vnd.github.raw' | bash
# Private repo: needs GitHub's CLI signed in once (brew install gh; gh auth login). Files fetched this way aren't quarantined,
# so macOS opens the app without the "unidentified developer" warning.
set -euo pipefail
REPO="${MV_REPO:-drawsomerex/music-video-maker}"
die() { printf "\n✗ %s\n" "$*" >&2; exit 1; }
[ "$REPO" != "OWNER/NAME" ] || die "This installer hasn't been pointed at a repo yet (release.sh does that on first publish)."
[ "$(uname -m)" = "arm64" ] || die "This app needs an Apple Silicon Mac (M1 or newer)."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || die "macOS 14 or newer is required."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# The repo is private, so downloads go through GitHub's own CLI, signed in as you (nothing is public or anonymous).
GH="$(command -v gh || true)"; [ -z "$GH" ] && for c in /opt/homebrew/bin/gh /usr/local/bin/gh; do [ -x "$c" ] && GH="$c"; done
[ -n "$GH" ] || die "Install GitHub's CLI first:  brew install gh   (or https://cli.github.com), then run  gh auth login  and try again."
"$GH" auth status >/dev/null 2>&1 || die "Sign in once with:  gh auth login   — then run this installer again."
echo "Downloading the latest release of $REPO…"
"$GH" release download --repo "$REPO" --pattern '*native*.zip' --pattern '*native*.zip.sha256' --dir "$TMP" --clobber >/dev/null 2>&1 || die "Couldn't download the latest release (no access to $REPO, or no release yet)."
ZIPF="$(ls "$TMP"/*native*.zip 2>/dev/null | head -1)"; [ -n "$ZIPF" ] || die "No downloadable build found in the latest release."
mv "$ZIPF" "$TMP/app.zip"
SHAF="$(ls "$TMP"/*.sha256 2>/dev/null | head -1)"
if [ -n "$SHAF" ]; then
  WANT="$(awk '{print $1}' "$SHAF")"; GOT="$(shasum -a 256 "$TMP/app.zip" | awk '{print $1}')"
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
