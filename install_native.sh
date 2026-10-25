#!/bin/bash
# Music Video Maker — standalone install with Swift MLX (no oMLX, no Python).
#
#   ./install_native.sh                    # build, install to /Applications, download models (balanced, ~4.1 GB)
#   ./install_native.sh --tier small       # smaller language model  (~1.5 GB total)
#   ./install_native.sh --tier best        # bigger language model   (~6.5 GB total)
#   ./install_native.sh --skip-models      # just the app; it offers the model download on first launch
#   ./install_native.sh --no-install       # only build (into .build-native/), don't touch /Applications
#
# What it does: checks your Mac, installs Apple's Metal Toolchain if missing (a one-time ~0.7 GB Xcode component that MLX's
# GPU kernels need), builds the app with Xcode's compiler, installs it, then downloads Parakeet Ultra (shrunk to 4-bit, ~0.5 GB)
# and a small language model into ~/Library/Application Support/MusicVideo/models.
set -euo pipefail
cd "$(dirname "$0")"
TIER="balanced"; INSTALL=1; MODELS=1
while [ $# -gt 0 ]; do case "$1" in
  --tier) TIER="$2"; shift 2;; --skip-models) MODELS=0; shift;; --no-install) INSTALL=0; shift;;
  -h|--help) sed -n 2,12p "$0"; exit 0;; *) echo "Unknown option: $1"; exit 1;; esac; done
case "$TIER" in small|balanced|best) ;; *) echo "--tier must be small, balanced or best"; exit 1;; esac
say() { printf "\n\033[1m▸ %s\033[0m\n" "$*"; }
die() { printf "\n\033[31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

say "Checking this Mac"
[ "$(uname -m)" = "arm64" ] || die "This needs an Apple Silicon Mac (M1 or newer)."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || die "macOS 14 or newer is required."
command -v xcodebuild >/dev/null || die "Xcode isn't installed. Install it from the App Store, open it once, then run this again."
xcodebuild -version >/dev/null 2>&1 || die "Xcode needs its first-run setup: open Xcode once (or run: sudo xcodebuild -license accept)."
# a first build with the models needs ~12 GB; a rebuild without them (release.sh) reuses .build-native and needs far less
NEED_GB=12; { [ "$MODELS" = 0 ] && [ -d .build-native ]; } && NEED_GB=2
FREE_GB=$(df -g / | awk 'NR==2{print $4}'); [ "$FREE_GB" -ge "$NEED_GB" ] || die "Need ~${NEED_GB} GB free for the build$( [ "$NEED_GB" = 12 ] && echo " and models") (you have ${FREE_GB} GB)."
echo "  Apple Silicon ✓   macOS $(sw_vers -productVersion) ✓   $(xcodebuild -version | head -1) ✓   ${FREE_GB} GB free ✓"

say "Metal toolchain (needed to compile MLX's GPU kernels)"
if xcrun -sdk macosx metal --version >/dev/null 2>&1; then echo "  already installed ✓"
else echo "  downloading Apple's Metal Toolchain (one time, ~0.7 GB)…"; xcodebuild -downloadComponent MetalToolchain; fi

say "Building (first build compiles MLX — about 4 minutes)"
MV_NATIVE=1 xcodebuild -scheme MusicVideoApp -destination 'platform=macOS,arch=arm64' -configuration Release \
  -derivedDataPath .build-native -skipMacroValidation -skipPackagePluginValidation build > /tmp/mv-native-build.log 2>&1 \
  || { tail -25 /tmp/mv-native-build.log; die "Build failed (full log: /tmp/mv-native-build.log)"; }
MV_NATIVE=1 xcodebuild -scheme mvideo -destination 'platform=macOS,arch=arm64' -configuration Release \
  -derivedDataPath .build-native -skipMacroValidation -skipPackagePluginValidation build > /tmp/mv-native-build-cli.log 2>&1 \
  || { tail -25 /tmp/mv-native-build-cli.log; die "CLI build failed (full log: /tmp/mv-native-build-cli.log)"; }
PRODUCTS=".build-native/Build/Products/Release"

say "Packaging the app"
APP="$PWD/.build-native/Music Video Maker.app"
scripts/assemble_app.sh "$PRODUCTS" "$APP" native
if [ "$INSTALL" = 1 ]; then
  rm -rf "/Applications/Music Video Maker.app"; cp -R "$APP" "/Applications/Music Video Maker.app"; echo "  installed: /Applications/Music Video Maker.app"
fi
if [ "$INSTALL" = 1 ]; then
  mkdir -p "$HOME/.local/bin" && cp "$PRODUCTS/mvideo" "$HOME/.local/bin/mvideo" && for b in "$PRODUCTS"/*.bundle; do cp -R "$b" "$HOME/.local/bin/"; done
  echo "  command line tool: ~/.local/bin/mvideo"
else
  echo "  built (not installed): $APP"
fi

if [ "$MODELS" = 1 ]; then
  say "Models ($TIER): Parakeet Ultra → 4-bit, plus a language model"
  "$PRODUCTS/mvideo" setup-native --tier "$TIER"
fi

say "Done"
du -sh "/Applications/Music Video Maker.app" 2>/dev/null | awk '{print "  app:    " $1}' || true
du -sh "$HOME/Library/Application Support/MusicVideo/models" 2>/dev/null | awk '{print "  models: " $1}' || true
if [ "$INSTALL" = 1 ]; then echo "  Open “Music Video Maker” from Launchpad or Spotlight."; fi
