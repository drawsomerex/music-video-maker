#!/bin/bash
# Publish a new version: builds the standalone app, zips it with a checksum, tags it, and creates a GitHub Release.
# Every Mac running the app finds it on launch (or via  Music Video Maker ▸ Check for Updates…).
#
#   ./release.sh                         # bump the patch number (1.0.0 → 1.0.1) and publish
#   ./release.sh --bump minor            # 1.0.1 → 1.1.0     (or: major)
#   ./release.sh --version 2.0.0         # set it explicitly
#   ./release.sh --notes "What changed"  # release notes (default: the git log since the last release)
#   ./release.sh --create-repo NAME      # first time only: creates a PUBLIC GitHub repo called NAME and remembers it
#   ./release.sh --dry-run               # build + zip into dist/ but don't commit, tag or publish
#
# One-time prerequisite for publishing:  brew install gh && gh auth login
set -euo pipefail
cd "$(dirname "$0")"
BUMP="patch"; VERSION_ARG=""; NOTES=""; NEWREPO=""; DRY=0
while [ $# -gt 0 ]; do case "$1" in
  --bump) BUMP="$2"; shift 2;; --version) VERSION_ARG="$2"; shift 2;; --notes) NOTES="$2"; shift 2;;
  --create-repo) NEWREPO="$2"; shift 2;; --dry-run) DRY=1; shift;; -h|--help) sed -n 2,14p "$0"; exit 0;; *) echo "Unknown option: $1"; exit 1;; esac; done
say() { printf "\n\033[1m▸ %s\033[0m\n" "$*"; }
die() { printf "\n\033[31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# Never publish from a half-finished merge or with conflict markers in any file (this once shipped release notes full of "<<<<<<<").
if [ -f .git/MERGE_HEAD ] || [ -n "$(git diff --name-only --diff-filter=U 2>/dev/null)" ]; then die "A git merge is not finished. Resolve the conflicts and commit, then run this again."; fi
if git grep -lE '^(<{7}|>{7}) ' -- . ':!release.sh' ':!relay' >/dev/null 2>&1; then die "Conflict markers (<<<<<<< or >>>>>>>) are still in: $(git grep -lE '^(<{7}|>{7}) ' -- . ':!release.sh' ':!relay' | tr '\n' ' ')"; fi

if [ "$DRY" = 0 ]; then
  command -v gh >/dev/null || die "Install the GitHub CLI first:  brew install gh   then   gh auth login"
  gh auth status >/dev/null 2>&1 || die "Not logged in to GitHub. Run:  gh auth login"
  command -v git >/dev/null || die "git is required."
fi

# --- repo -------------------------------------------------------------------
REPO=$(grep -E '^REPO=' scripts/release.conf | cut -d= -f2 | tr -d ' ')
if [ -z "$REPO" ]; then
  [ "$DRY" = 1 ] && REPO="" || {
    [ -n "$NEWREPO" ] || die "No GitHub repo yet. Run once with:  ./release.sh --create-repo music-video-maker"
    say "Creating public repo $NEWREPO"
    [ -d .git ] || git init -b main >/dev/null
    gh repo create "$NEWREPO" --public --source . --remote origin >/dev/null
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    sed -i '' "s|^REPO=.*|REPO=$REPO|" scripts/release.conf
    sed -i '' "s|^REPO=.*|REPO=\"\${MV_REPO:-$REPO}\"|" install.sh
    echo "  repo: https://github.com/$REPO" ; }
fi

# --- version ----------------------------------------------------------------
CUR=$(tr -d ' \n' < VERSION)
if [ -n "$VERSION_ARG" ]; then NEW="$VERSION_ARG"; else
  IFS=. read -r MA MI PA <<< "$CUR"
  case "$BUMP" in major) NEW="$((MA+1)).0.0";; minor) NEW="$MA.$((MI+1)).0";; patch) NEW="$MA.$MI.$((PA+1))";; *) die "--bump must be patch, minor or major";; esac
fi
if [ "$DRY" = 0 ] && git rev-parse --verify --quiet "refs/tags/v$NEW" >/dev/null; then
  die "Version v$NEW already has a tag. Choose a new version; published releases must never be overwritten."
fi
echo "$NEW" > VERSION
say "Version $CUR → $NEW"

# --- build + package ----------------------------------------------------------
say "Building the standalone app"
./install_native.sh --no-install --skip-models | sed 's/^/  /'
mkdir -p dist; rm -f dist/MusicVideoMaker-"$NEW"-native.zip*
APP=".build-native/Music Video Maker.app"
ZIP="dist/MusicVideoMaker-$NEW-native.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
( cd dist && shasum -a 256 "MusicVideoMaker-$NEW-native.zip" > "MusicVideoMaker-$NEW-native.zip.sha256" )
ls -lh dist | awk 'NR>1{print "  " $5 "  " $9}'
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$NEW" ] || die "Built app doesn't carry version $NEW"

if [ "$DRY" = 1 ]; then echo "$CUR" > VERSION; say "Dry run done (VERSION restored to $CUR). Zip is in dist/"; exit 0; fi

# --- publish ------------------------------------------------------------------
say "Publishing v$NEW"
[ -n "$NOTES" ] || NOTES=$(python3 - <<'PY'
import re
t=open("CHANGELOG.md").read()
m=re.search(r"## \[Unreleased\]\n(.*?)(?=\n## \[|\Z)",t,re.S)
print((m.group(1) if m else "").strip())
PY
)
[ -n "$NOTES" ] || { LAST=$(git describe --tags --abbrev=0 2>/dev/null || true); NOTES=$( [ -n "$LAST" ] && git log --pretty='- %s' "$LAST"..HEAD || git log --pretty='- %s' | head -20 ); [ -n "$NOTES" ] || NOTES="Release $NEW"; }
# Stamp the changelog: move [Unreleased] content under the new version heading.
python3 - "$NEW" <<'PY'
import re,sys,datetime
v=sys.argv[1]; t=open("CHANGELOG.md").read()
if f"## [{v}]" not in t:
    t=t.replace("## [Unreleased]\n","## [Unreleased]\n\n## [%s] - %s\n"%(v,datetime.date.today().isoformat()),1)
    open("CHANGELOG.md","w").write(t)
PY
# Privacy gate: the public zip must not contain this Mac's user name or home path anywhere.
LEAK=$(mkdir -p /tmp/mv-leak && rm -rf /tmp/mv-leak/* && ditto -x -k "$ZIP" /tmp/mv-leak && grep -rIlaE "$USER|$HOME" /tmp/mv-leak 2>/dev/null || true)
LEAK2=$(find /tmp/mv-leak -type f -exec sh -c 'strings -a "$1" | grep -qE "$2" && echo "$1"' _ {} "$HOME" \; 2>/dev/null | head -3)
[ -z "$LEAK$LEAK2" ] || die "Release blocked: personal path found in $LEAK$LEAK2"
rm -rf /tmp/mv-leak
git add -A; git commit -qm "Release v$NEW" -m "Co-Authored-By: GPT-6 <noreply@anthropic.com>" || true
git tag "v$NEW"
git push -q origin HEAD --tags
gh release create "v$NEW" "$ZIP" "$ZIP.sha256" --repo "$REPO" --title "Music Video Maker $NEW" --notes "$NOTES"
say "Released: https://github.com/$REPO/releases/tag/v$NEW"
# keep only the newest 3 release zips on this Mac (every one is kept on GitHub); each is about 27 MB
ls -t dist/MusicVideoMaker-*-native.zip 2>/dev/null | tail -n +4 | while IFS= read -r z; do rm -f "$z" "$z.sha256"; done
echo "  Other Macs update themselves on next launch (or Music Video Maker ▸ Check for Updates…)."
echo "  Brand-new Mac (no GitHub account needed):"
echo "    curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
