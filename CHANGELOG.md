# Changelog

All notable changes to Music Video Maker. Newest first. **Add every user-visible change under `[Unreleased]` as you make it** —
`./release.sh` turns that section into the GitHub release notes (shown to users in the in-app "Update available" dialog) and stamps it with the version and date.

## [Unreleased]

### Added
- **Divide your lyrics into parts.** On the first screen, *Lyrics ▸ Divide into parts* shows your lines with a scissors button between them: click to start a new part, click again to join. **Each part becomes exactly one picture**, and Shorts are built from whole parts (grouped to about 30 s; a part much longer than a Short is split at its pauses) so a Short never starts or ends in the middle of a part. *Use my verse breaks* turns your blank-line verses into parts as a starting point; *Clear my parts* returns to automatic. In the text a part break is a line containing `---`. With no `---` lines the app divides the song itself as before. Parts are remembered in the project.
- **Go back to any step.** The **Song · Pictures · Video** steps at the top are buttons: from the finished video you can return to Pictures or to Song (title, lyrics and song are kept), and from Pictures back to Song or forward to Video once one exists. Nothing is lost by going back.
- **A song with a different name starts a new project.** Choose or drop an MP3 whose name differs from the one you are working on and the app starts a fresh video (the earlier one stays saved; *Open earlier project* brings it back). A file with the same name keeps the project; while you are only drafting, the title follows the file name until you type your own. If you change a song's title, lyrics or file, the main button says **Plan as a new video**, otherwise **Back to my pictures**.

### Fixed
- **Small screens (MacBook Air).** The progress bar for background tasks is now a strip above the screen instead of a panel floating over the buttons; the first screen's left column scrolls and its bottom bar shrinks to icons (then two rows) instead of overlapping; the Pictures screen's top area is limited to ~40 % of the window height and scrolls, and its top and bottom bars adapt; Shorts controls wrap; the window keeps itself inside the screen and can be as small as 860 × 560; dialogs scroll instead of running off screen.

## [1.2.1] - 2026-10-16

### Fixed
- **Gemma (language model) failing with “key … not found”** on a second Mac. Downloads never checked the server's reply, so a busy or blocking Hugging Face could hand back an error page that was saved as the model file. Downloads now check the server status, verify big files against Hugging Face's checksums (re-downloading a damaged one once), record what was downloaded, and an install whose files are missing, the wrong size or obviously not model weights is treated as *not installed* so the app offers the download again instead of failing during planning.

### Added
- **On-device models in Settings and on the setup screen.** *Parakeet Ultra* and the language model (e.g. *Gemma 4 E2B*) each show whether they are downloaded and how big they are, a live percentage while downloading, and Download / **Download again** buttons. A size picker (Small / Balanced / Best) chooses which language model is fetched.

### Changed
- **Shorts are saved next to the main video**, not in a `Shorts` subfolder (your chosen output folder, or the folder beside the project). Files are named `<Song title> – <clip name>.mp4` so several songs can share one folder. Shorts you already made stay where they are.

### Added
- **The music before the first words now gets its own picture and prompt.** When the first words start 3 s or more after the title card, the song gets a *Music before the words* section (shown after the title card until the first lyric), with a prompt that sets up the song's world. Music-only breaks and the outro are described in context too (the words before and after them), instead of one generic "establishing scene". Older projects get an **Add picture for the opening music** button on the Pictures screen (CLI: `mvideo add-intro <project>`); existing pictures stay put.
- **Every section's prompt is unique.** After writing, near-duplicate prompts (word overlap ≥ 35 %) are rewritten with the other prompts listed as "must differ from"; as a last resort a different time of day or viewpoint is added. "Another idea" also avoids all existing prompts, and a model echoing the style line at the start of a prompt is cleaned up.

## [1.2.0] - 2026-10-16

### Fixed
- **"Record it as it plays" stopped working after an update** even though *Screen & System Audio Recording* was switched on. macOS remembers that permission by the app's signature, and every build had a different ad-hoc signature, so each update invalidated it while System Settings still showed the old entry as ON. Builds are now signed with a fixed designated requirement (the bundle identifier), so the permission survives future updates. When macOS still refuses, a **Let's fix recording** window repairs it in three clicks (clears the stale entry, asks again, restarts the app); it is also under Settings ▸ *Fix recording permission…*. Updating to this version needs the permission granted once more.

### Added
- **In-app updates, made obvious.** A blue **“Update available — version X”** strip appears across the top of the window with *What's new*, **Update now** and *Later*. *Update now* downloads the new version, checks its SHA-256, installs it and restarts the app by itself, showing a progress bar and the current step. The Help and app menus have **Check for Updates…** (it becomes *Update to Version X…* when one is waiting), and Settings has an **Updates** section with the current version, status, last-checked time and a *Check for updates* button.

## [1.1.0] - 2026-10-16

### Fixed
- **Captions slightly off pace with the singing.** Every caption now follows a per-song timing offset that defaults to 0.06 s early (audiences read late captions as lagging), and the Shorts word pill now starts moving *before* each word so it lands on the onset instead of 0.1 s after it. New **Show sooner / Show later** buttons under the preview shift every caption of a song in 0.05 s steps; the setting is saved with the project (`captionShift`).
- Lyric timing for words the speech model missed now stays inside their own line instead of stretching across pauses; sung words hold for a natural length (from the other AI's alignment work, with its extra −30 ms offset removed so the caption offset is the single timing control).

### Changed
- **Much easier to use.** Every screen was reworded in plain language and every button, field and picker has a tooltip that explains what it does. A **Step bar** (Song → Pictures → Video) shows where you are, a green **next step** card says what to do next, and Help ▸ **Quick Guide** (also the `?` button, and shown on first launch) walks through the whole process.
- Pictures screen simplified: one "Picture maker" card (make all missing pictures, credit left), the song description and art style are tucked into a section that is closed by default, line-timing buttons are larger, and technical wording ("Reroll", model names) is gone from the main screens.
- Shorts editor reworded ("Cut my song into clips for me", "Choose the lines myself", "Try a different look", "Move to the nearest pause") with tooltips on every control.
- Settings reorganised: Where things are saved · Picture maker · Shortcuts & help.

### Added
- `scripts/bench/lag_scan.py` (checks a constant caption offset against acoustic onsets) and a hidden screenshot mode (`MV_SNAPSHOT_DIR`) for layout checks.

## [1.0.5] - 2026-10-16

### Added
- **OpenRouter image generation (`openai/gpt-image-2.5-sunburst` 16:9 Medium):** Enter your OpenRouter API key (in Settings or directly from the Plan screen) to generate individual section pictures, reroll any picture, generate all missing pictures, or reroll all pictures for the entire song (`--generate-images` in the CLI).
- **Live OpenRouter credit balance, cost estimates & persistent per-song total cost:** Displays your remaining OpenRouter credits alongside the estimated cost per image (`~$0.048`) and bulk generation cost, and persistently tracks and saves the cumulative USD spent on each song (`totalGenerationCostUSD` and `imagesGeneratedCount`) inside `project.mvproj`.

### Fixed
- **Silky-smooth, non-jumping Ken Burns camera engine:** Re-engineered `PhotoScene` with aspect-aware valid crop domain clamping, logarithmic (exponential) zoom interpolation (`z0 * (z1 / z0)^u`), perspective-coupled pan interpolation (`alpha = (1/z0 - 1/z(u)) / (1/z0 - 1/z1)`), and duration-scaled cosine S-curve easing so the camera never collides with image borders mid-shot, never stalls or whips across the middle, and never reverses zoom direction or jumps within a picture. Also smoothed beat-pulse envelopes (`0.045s` raised-cosine attack + exponential decay) and added cross-dissolve transitions.
- **Setup screen "Record Song Playing" layout stability:** Fixed the recording zone and live waveform meter so switching to **Record Song Playing** or actively recording a song never expands the left column vertically or horizontally.

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
