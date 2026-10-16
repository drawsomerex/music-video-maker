#!/bin/bash
# Double-click to open Music Video Maker (builds it automatically the first time or after code changes).
#
# Headless / AI use — pass arguments and it runs without the UI, in two steps:
#   1. ./"Music Video.command" plan song.mp3 -t "Title" -s "subject" -l lyrics.txt [-o outdir] [--every 15]
#        → syncs the lyrics, splits the song into sections, prints + saves an image prompt for each (prompts.md in the work folder)
#   2. make the pictures (16:9), name them 00.png (title card), 01.png, 02.png …, then
#      ./"Music Video.command" render "<outdir>/<Title> – work" --images <folder>
#   3. Shorts: ./"Music Video.command" short "<project folder>" --list   (numbered lyric lines)
#              ./"Music Video.command" short "<project folder>" --lines 13-18 --snap
# Other: models (check oMLX), preview, settings.   (lyrics file may be "-" for stdin; --help for options)
cd "$(dirname "$0")" || exit 1
APP="Music Video Maker.app"

needs_build() {
  [ ! -d "$APP" ] && return 0
  [ -n "$(find Sources Package.swift -newer "$APP/Contents/MacOS/MusicVideoApp" -type f 2>/dev/null | head -1)" ]
}

if [ $# -gt 0 ]; then
  # ---- headless ----
  BIN=".build/release/mvideo"
  if [ ! -x "$BIN" ] || [ -n "$(find Sources Package.swift -newer "$BIN" -type f 2>/dev/null | head -1)" ]; then
    swift build -c release --product mvideo 1>&2 || exit 1
  fi
  case "$1" in
    plan|render|short|preview|models|settings|help|--help|-h) exec "$BIN" "$@" ;;
    *) exec "$BIN" plan "$@" ;;
  esac
fi

# ---- GUI ----
if needs_build; then
  echo "Building Music Video Maker (first run takes a few minutes)…"
  ./build_app.sh || { echo; echo "Build failed."; read -n 1 -s -r -p "Press any key to close"; exit 1; }
fi
if [ -d "/Applications/$APP" ] && [ -z "$(find Sources Package.swift -newer "/Applications/$APP/Contents/MacOS/MusicVideoApp" -type f 2>/dev/null | head -1)" ]; then open "/Applications/$APP"; else open "$APP"; fi
sleep 1
osascript -e 'tell application "Terminal" to close (every window whose name contains "Music Video.command")' >/dev/null 2>&1 &
exit 0
