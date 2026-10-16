#!/bin/bash
# Builds "Music Video Maker.app" (release, Apple Silicon) that talks to oMLX for speech/prompts, plus the `mvideo` CLI.
#   ./build_app.sh            build only
#   ./build_app.sh --install  build, then copy the app into /Applications
# (For the standalone build with Swift MLX — no oMLX, no Python — use ./install_native.sh)
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product MusicVideoApp
swift build -c release --product mvideo
BIN=$(swift build -c release --show-bin-path)
APP="Music Video Maker.app"
scripts/assemble_app.sh "$BIN" "$PWD/$APP" omlx
echo "Built: $PWD/$APP"
echo "CLI:   $BIN/mvideo"
if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/$APP" && cp -R "$APP" "/Applications/$APP" && echo "Installed: /Applications/$APP"
fi
