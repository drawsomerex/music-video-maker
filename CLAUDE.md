# Music Video Maker — notes for AI assistants

Native macOS app (SwiftUI + a CLI) that turns a song + lyrics into a lyric video and YouTube Shorts. Apple Silicon, macOS 14+.
Read this before changing anything. The owner is not a programmer: prefer simple, verified, reversible changes, and **say plainly what you did and did not test**.

## Rules that matter most
1. **Never publish (`release.sh`, `git push`, `gh release`) without the owner explicitly saying so in that conversation.** Commits are fine; pushes and releases are not.
2. **Never touch the user's own oMLX settings** (`~/.omlx/settings.json`). `omlx serve` writes its CLI flags into settings, which once overwrote the user's port/memory settings. The app's hidden engine always runs with `OMLX_BASE_PATH=~/Library/Application Support/MusicVideo/omlx-engine` (see `OMLXServer.swift`). Compare the file's `md5` before/after any test that starts an engine.
3. **Never commit media, projects or keys** (`*.mp3 *.wav *.mp4 *.mvproj`, `Output/`). `.gitignore` covers them; check `git status` before every commit. The repo is public.
4. Don't delete or overwrite the user's projects (`~/Movies/Music Videos/…`). Test on copies or use `/tmp`.
5. Keep `CHANGELOG.md` current: every user-visible change goes under `## [Unreleased]` in the same commit.
6. **Permanent feature parity (the owner's rule): every picture feature works in BOTH the music video and the looping video.** When you add or change anything about pictures (drawing, quality, brightness, weather, time of day, type of shot, the picture to base it on, the cast and cast sheet, the picture check and "Fix it", "Make highest quality", the 4× sharpening, the director's choices and progress, view larger, earlier versions), do it in both workflows in the same change, with the same names in the UI, and add both to the Help guide. Shared logic lives in MVCore (`Pipeline`, `LoopVideo`, `PictureCheck`, `SuperRes`, `Director`) and is called from both. The only allowed differences are features that make no sense in the other: the moving camera's focal points, camera path, framing check and style-guide picture exist only for music videos (a loop clip has a still camera); "Cloudless sky" and "What moves" exist only for loops (they serve the seamless loop). Before a release, check the list in "Feature parity checklist" below.

## Two build flavors (same code, different engine)
| | `./build_app.sh` (oMLX flavor) | `./install_native.sh` (native flavor) |
|---|---|---|
| Compiler | `swift build` | `xcodebuild` with `MV_NATIVE=1` (needs Apple's Metal Toolchain) |
| Speech / prompts | oMLX: `OMLXRuntime` runs oMLX's bundled Python for word times; HTTP for LLM | `MVNative` (Swift MLX): `NativeEngine` registers `NativeHooks.wordTimes/chat` |
| Updates | `git pull && ./build_app.sh` | built-in updater (GitHub Releases) |
| Marker | `MVFlavor=omlx` in Info.plist | `MVFlavor=native`, Swift flag `NATIVE_MLX` |
`Package.swift` only pulls in the MLX packages when `MV_NATIVE` is set, so normal `swift build` stays fast and dependency-light.

## Layout
- `Sources/MVCore` — everything shared: `Pipeline` (plan/resync/shorts helpers), `LyricAligner`, `Planner`, `PromptWriter`, `Renderer` (`FrameComposer`, `VideoRenderer`), `Scenes` (Ken Burns, transitions), `TextLayers`/`ShortOverlays` (captions, title), `ShortStyle`, `OMLX*`, `NativeHooks`, `Models` (all Codable types).
- `Sources/MVNative` — native Swift-MLX engine + one-time model setup (`NativeEngine`, `NativeSetup`). Only compiled when `MV_NATIVE=1`.
- `Sources/MusicVideoApp` — SwiftUI app (`AppModel`, `RootView`, `PlanView`, `ShortsView`, `LivePreview`, `Updater`).
- `Sources/mvideo` — CLI (`plan`, `render`, `short`, `resync`, `setup-native`, `models`, `settings`, `preview`).
- `Vendor/mlx-audio-swift` — trimmed MIT copy with 3 patches (see `Vendor/README.md`). Re-apply them if you update it.
- `scripts/` — `assemble_app.sh` (app bundle + Info.plist), `word_timing.py` (oMLX flavor), `make_icon.swift`, `release.conf` (GitHub repo name).
- `VERSION` — single source of truth for the version; only `release.sh` changes it.

## Build & test
```
swift build -c release --product mvideo            # quick compile check (oMLX flavor)
swift build -c release --product MusicVideoApp
./build_app.sh                                     # → "Music Video Maker.app" in this folder
./install_native.sh --no-install --skip-models     # native build → .build-native/Music Video Maker.app (≈1 min incremental, 4 min cold)
./release.sh --dry-run                             # builds the release zip into dist/, publishes nothing
```
Verify with the real thing, not just compilation: run the CLI on a song, render, then look at frames (`ffmpeg -ss T -i x.mp4 -frames:v 1`). For UI changes launch the app with **`open -n "…app"`** (a raw binary launched from a shell may create no window) and use the computer-use tools to click through it. Test hooks: `MV_DEMO_PLAN=<project folder>` opens straight to a project, `MV_DEMO_MODE=1` to the Shorts tab, `MV_UPDATE_API` / `MV_UPDATE_SELFTEST=1` exercise the updater against a fake server (see below).

## Releasing (only when the owner says to)
1. Everything committed, `CHANGELOG.md` `[Unreleased]` filled in, `./release.sh --dry-run` succeeds.
2. First time only: `gh auth login`, then `./release.sh --create-repo music-video-maker` (creates the **public** repo, records it in `scripts/release.conf` and `install.sh`).
3. `./release.sh` (patch bump), or `--bump minor|major`, or `--version X.Y.Z`. It builds the native app, zips it (`dist/MusicVideoMaker-X.Y.Z-native.zip` + `.sha256`), stamps the changelog, commits, tags `vX.Y.Z`, pushes, and creates the GitHub Release.
4. Never re-tag or delete a published release; ship a new patch version instead.
The app finds releases via the GitHub API and installs `*native*.zip` after checking the `.sha256` asset. Keep those asset names.
**Updater test without publishing:** serve a JSON file shaped like GitHub's `releases/latest` (tag_name, body, assets[name, browser_download_url]) plus a zip and `.sha256` from `python3 -m http.server`, install an older-version copy of the app in /tmp, and launch it with `open -n APP --env MV_UPDATE_API=http://127.0.0.1:PORT/latest --env MV_UPDATE_SELFTEST=1 --stderr LOG`. Also test a wrong checksum is refused.

## Git
- Branch `main`. Small commits with an imperative subject line; add the trailer `Co-Authored-By: Claude <noreply@anthropic.com>` when an AI wrote it.
- Don't force-push, don't rewrite published history, don't commit build output (`.build*/`, `*.app`, `dist/`).
- Tags are `vMAJOR.MINOR.PATCH` and only created by `release.sh`.

## Gotchas learned the hard way
- macOS BSD `sed`: use `sed -i ''`; there is no `\b` — use `perl -pi -e` for word boundaries.
- `omlx serve`'s process renames itself to `omlx-server`; `pkill -f "serve --port"` misses it. Kill by port (`lsof -iTCP:8817 -sTCP:LISTEN -t`) — `OMLXServer.killListener` does this.
- SwiftUI `VideoPlayer` (AVKit) crashes in this SwiftPM-built app; use the AppKit `AVPlayerView` wrapper (`PlayerView`).
- The in-memory MLX/Metal path needs the resource bundle `mlx-swift_Cmlx.bundle` next to the binary or in `Contents/Resources` (`assemble_app.sh` copies all `*.bundle`).
- `xcodebuild` for the native flavor needs `-skipMacroValidation -skipPackagePluginValidation` and `MV_NATIVE=1` in the environment.
- Parakeet Ultra's weights written by the 4-bit "slim" step are in the model's *internal* naming (`"mv_internal_layout": true` in config); the vendored loader skips NeMo-name sanitising for them.
- Word timing comes from token timestamps; oMLX's HTTP transcription endpoint returns text only (so the windowed fallback in `Transcriber` is approximate).
- Shorts: hard 3:00 limit (`ShortClip.maxDuration`); no picture change in the first/last 3 s; captions window has no slack so selecting lines never shows neighbours (`Pipeline.clip` / `lineRange`).
- Models' licences: Parakeet Ultra is CC-BY-4.0 (credit it); mlx-audio-swift MIT.

## Gotchas learned the hard way
- **Never store secrets in the Keychain.** The app is ad-hoc signed, so every new build is a "different app" to the Keychain: reads block on a hidden permission dialog and the whole UI freezes at launch. Keys live in `config.json` (mode 0600).
- Don't `pkill -x MusicVideoApp` while testing; it also kills the user's own running copy. Launch test builds with `open -n <app> --env K=V --stderr file` and kill by full path.
- `ImageRenderer` snapshots (`MV_SNAPSHOT_DIR`) can't draw AppKit-backed controls (text fields, lists show as yellow "no" boxes) but are good for checking layout of everything else.
- Caption timing has one knob: `Plan.captionShift` (seconds, negative = earlier). Don't add offsets elsewhere.
- **Keep the help guide true.** `Sources/MVCore/HelpGuide.swift` is both the user's guide and the ONLY source the Help assistant may answer from. When you add, rename or remove a feature or button, update it in the same change, and re-run the assistant check (`MV_HELP_TEST=<file of questions> MV_DEMO_PLAN=<project> open -n …app --stderr out.txt`).

## Feature parity checklist (music video ↔ looping video)
| Picture feature | Music video | Looping video |
|---|---|---|
| Picture quality (High / Medium), Brightness, Weather, Time of day, Type of shot | Picture options (`ReferenceRows`) | the same `ReferenceRows` |
| Picture to base it on (choose, find online, keep place/building/subject, read into the ideas) | ✓ | ✓ |
| Director: one click, approve the choices, progress strip with Pause/Continue/Stop | `AutoMode.swift` | `AutoMode.swift` |
| Cast and cast sheet | `Pipeline.makeCastSheet` | `LoopVideo.makeCastSheet` |
| Automatic picture check + "Fix it" | `Pipeline.fixSectionImage` | `LoopVideo.fixPicture` |
| "Make highest quality" (xhigh, ~7¢, existing pictures only) | `Pipeline.highestQualitySectionImage` | `LoopVideo.highestQuality` |
| 4× on-device sharpening of every drawn picture | `SuperRes` in `generateSectionImage` | `SuperRes` in `LoopVideo.storePicture` |
| View larger, earlier versions kept | ✓ | ✓ |
| Extend a photo to 16:9 | ✓ | ✓ |
