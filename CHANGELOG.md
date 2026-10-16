# Changelog

All notable changes to Music Video Maker. Newest first. **Add every user-visible change under `[Unreleased]` as you make it** —
`./release.sh` turns that section into the GitHub release notes (shown to users in the in-app "Update available" dialog) and stamps it with the version and date.

## [Unreleased]

## [1.0.4] - 2026-10-16

### Added
- **Live song recording, real-time transcription & automatic silence trimming:** Record any song playing on your Mac (via `ScreenCaptureKit` system audio) or from a microphone/audio input, watch Parakeet transcribe the lyrics in real time as it plays, and automatically trim leading and trailing silence when you stop. Includes one-click **Paste Over Lyrics**, **Auto-Transcribe**, and **Trim Silence** actions.
- **Automated 4–7 ~30-second Shorts when making the main video:** Every planned song now automatically partitions into 4–7 ~30-second Shorts cut at natural stanza breaks and vocal pauses (`Pipeline.autoShorts`). Leave **Also make Shorts (~30s)** checked when clicking **Render Video + Shorts** (or pass `--with-shorts` on the CLI) to render the main widescreen video and all 4–7 Shorts with AI-written opening hooks in a single pass. Also added **Auto-Make 4–7 Shorts (30 s)** and **Render All Shorts** buttons in the Shorts tab.
- **Curated visual style preset dropdowns:** Pick from 14 built-in art styles on the Setup and Plan screens (**Oil Painting**, **Acrylic Painting**, **Vector Image**, **Realistic**, **Watercolor & Ink**, **Studio Anime**, **Vintage Comic Book**, **Neon Cyberpunk**, **Charcoal & Gold Leaf**, **3D Claymation Diorama**, **Ukiyo-e Woodblock Print**, **Stained Glass**, **Retro 1970s Poster**, or **AI Auto**).
- **Clear on-screen progress bars & task cancellation everywhere:** Floating progress bar banner with percentage, elapsed clock, phase description, and **Cancel** button whenever any background task runs (rewriting song description, regenerating prompts, loading a folder of pictures, re-syncing lyrics, writing Short hooks, live preview preparation, and audio transcription/silence trimming), plus **Cancel** buttons on full video and Short renders that cleanly remove partial files.
- **Interactive Focal Point & 9:16 Short crop preview:** Drag the orange focal-point target directly on any loaded picture in the Plan screen to aim the Ken Burns camera pan and preview the dashed 9:16 vertical Short crop box, with an **Auto Focus** reset button.
- **Per-line lyric timing nudges & audition:** Play (`▶`) individual lyric lines in any section and nudge their timing (`−0.5s`, `−0.1s`, `+0.1s`, `+0.5s`) without re-running full alignment.

### Changed
- **Faster rendering & lower CPU overhead:** Replaced the `AVAssetWriter` polling spin-wait with an event-driven pending frame queue, cached the `t = 0` opening frame for looping Shorts, and deduplicated `TextBitmap` rasterization across repeated words in Shorts.
- **Single-pass audio decode & persistent waveform/beat caches:** 16 kHz mono PCM is decoded once in memory and `waveform.json` and `beats.json` are saved inside the `.mvproj` project folder for instant project reopening and Short scrubbing.
- **Beat-synced sub-shot cuts & vertical subject framing:** Dynamic Short sub-shots now snap cut times to detected musical beats and anchor horizontal pans to the detected vertical subject focal point (`focus.y`).

### Fixed
- **Karaoke word highlight drift:** Fixed substring matching on repeated short words within the same lyric line (`LyricLayer.buildRows`) by advancing past whitespace and matching anchored tokens first.
- **Resilient local AI prompt parsing:** Added a regex salvage parser and per-section fallback in `PromptWriter` so truncated or malformed LLM JSON output never aborts a video plan.
- **Project disk cleanup:** Replacing or removing a section's picture now automatically deletes unreferenced `full/section_*` and `thumbs/section_*` files from the project folder.

## [1.0.3] - 2026-10-16

## [1.0.2] - 2026-10-16

## [1.0.1] - 2026-10-16

### Changed
- Balanced tier now uses Gemma 4 E2B (faster, closer to the song's era than Qwen3-4B).
- Clear progress panel: percentage, bar, current task, step checklist, elapsed and time left (planning, rendering, setup, Shorts).
- One "Saving to…" button on the main screen sets the folder for all projects, pictures and videos.

### Changed (privacy)
- Releases are public; installer and in-app updater download anonymously (no GitHub account needed).
- App identifier is now com.drawsomerex.musicvideomaker; commit author is the GitHub handle only.
- Removed song-specific test scoring script and example text.

### Added
- Settings → Dock: add/remove the app from the Dock.

### Added
- Model benchmarks (`docs/model-benchmarks.md`, `scripts/bench/`) and hidden `mvideo align-check`; confirmed default model tiers.

## [1.0.0] - 2026-10-16
First release.

### Added
- **Two-step workflow:** plan (sync lyrics, split the song into sections, write a shared style + one image prompt per section), then load your own pictures and render. Projects are self-contained folders (`project.mvproj`, `audio.mp3`, `transcript.txt`, `lyrics_synced.txt`, `prompts.md`, pictures) that can be reopened and edited.
- **Exact lyric timing** from Parakeet Ultra word timestamps (4-minute song in under 3 s), aligned to your pasted lyrics; the on-screen text is always yours.
- **Rendering:** Ken Burns camera, feathered wipes/iris/blinds/push transitions, karaoke lyrics, title card, hardware H.264 at YouTube-friendly bitrate; memory-lean and thermal-aware for 16 GB fanless Macs.
- **YouTube Shorts (1080×1920):** pick lyric lines (click / shift-click / In / Out), waveform with zoom-to-scrub and audition, live preview with draggable captions and safe zones, hard 3:00 limit, whole-song mode that splits into parts under 3:00, dynamic style kit (title opening, pink word pill, calm motion, loop ending, optional closing text), 3-variant A/B renders, AI-written upload text.
- **Local AI:** works through oMLX (hidden headless engine, never touching your oMLX settings) **or** fully standalone with Swift MLX (`install_native.sh`: Parakeet Ultra 4-bit 0.46 GB + a Qwen model, tiers small / balanced / best).
- **Distribution:** `release.sh` publishes to GitHub Releases; `install.sh` installs on a new Mac; the app updates itself (checksum-verified).
- Folder choices for projects and finished videos; app icon; command-line tool `mvideo`.
