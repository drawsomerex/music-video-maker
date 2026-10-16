#!/bin/bash
# usage: assemble_app.sh <dir with built MusicVideoApp binary + resource bundles> <output .app path> [native|omlx]
set -euo pipefail
BIN="$1"; APP="$2"; FLAVOR="${3:-omlx}"; ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d ' \n' < "$ROOT/VERSION" 2>/dev/null || echo 1.0.0)"
REPO="$(grep -E '^REPO=' "$ROOT/scripts/release.conf" 2>/dev/null | cut -d= -f2 | tr -d ' ')"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MusicVideoApp" "$APP/Contents/MacOS/MusicVideoApp"
# Compiler-embedded source paths (from C++ __FILE__ in MLX) would reveal this Mac's user name; overwrite them with same-length filler.
python3 - "$APP/Contents/MacOS/MusicVideoApp" "$ROOT" "$HOME" <<'PY'
import sys
p, *needles = sys.argv[1:]
b = open(p, "rb").read()
for n in sorted(set(needles), key=len, reverse=True):
    n = n.encode(); b = b.replace(n, b"." * len(n))
open(p, "wb").write(b)
PY
cp "$ROOT/scripts/word_timing.py" "$APP/Contents/Resources/word_timing.py"
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
if [ ! -f "$ROOT/AppIcon.icns" ]; then swift "$ROOT/scripts/make_icon.swift" /tmp/mv-AppIcon.iconset && iconutil -c icns /tmp/mv-AppIcon.iconset -o "$ROOT/AppIcon.icns"; fi
cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>CFBundleName</key><string>Music Video Maker</string>
 <key>CFBundleDisplayName</key><string>Music Video Maker</string>
 <key>CFBundleIdentifier</key><string>com.drawsomerex.musicvideomaker</string>
 <key>CFBundleExecutable</key><string>MusicVideoApp</string>
 <key>CFBundleIconFile</key><string>AppIcon</string>
 <key>CFBundlePackageType</key><string>APPL</string>
 <key>CFBundleShortVersionString</key><string>$VERSION</string>
 <key>CFBundleVersion</key><string>$VERSION</string>
 <key>MVFlavor</key><string>$FLAVOR</string>
 <key>MVUpdateRepo</key><string>$REPO</string>
 <key>LSMinimumSystemVersion</key><string>14.0</string>
 <key>NSHighResolutionCapable</key><true/>
 <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
 <key>NSMicrophoneUsageDescription</key><string>Music Video Maker uses the microphone or audio input when you record a playing song to transcribe its lyrics in real time.</string>
 <key>NSAudioCaptureUsageDescription</key><string>Music Video Maker captures system audio when you record a song playing on your Mac to transcribe its lyrics in real time.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" 2>/dev/null || true
