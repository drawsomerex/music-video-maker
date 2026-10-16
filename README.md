# Music Video Maker

A native macOS app (Apple Silicon) that turns a song into a YouTube-ready video. Give it an MP3/WAV, a title and your lyrics and it makes a 1080p MP4 with a title card, a Ken Burns picture sequence with feathered wipes, and karaoke-style lyrics synced to the singing — plus vertical **YouTube Shorts** cut from any lines you pick. All AI (speech timing, writing picture prompts) runs **on your Mac**, offline; nothing is uploaded.

> **Built with Claude.** This project was written with the help of [Claude](https://claude.com/claude-code) (Anthropic's AI coding assistant), directed and tested by its owner. `CLAUDE.md` / `AGENTS.md` hold the rules an AI assistant should follow when changing it.

## Requirements
- A Mac with Apple Silicon (M1 or newer), macOS 14+; 16 GB RAM is plenty (8 GB works with the *small* model).
- About 5 GB of free disk for the on-device models (downloaded once, on first launch).
- To build from source: Xcode (the install script checks everything and tells you what is missing).

## Quick start (build it yourself)
```bash
git clone https://github.com/drawsomerex/music-video-maker.git && cd music-video-maker
./install_native.sh                                          # builds, installs to /Applications, downloads the models
```
Open **Music Video Maker** from Launchpad/Spotlight. Optional: *Settings → Dock → Add to Dock*, and *Settings → Where things are saved* (or the “Saving to…” button) to pick the folder for everything.

## How to make a video
1. **Plan** — pick the MP3, type the title, paste the lyrics, press *Plan my video*. The app syncs your lyrics to the audio, splits the song into sections, writes a song description and one picture prompt per section (progress is shown with percentage and time left).
2. **Make your pictures** — generate them with any image tool (16:9, 1920×1080 or larger, same style), then drag each onto its section (or load a folder named `00.png`, `01.png`, …).
3. **Make the video** — press *Make my video* (use *Preview* first; if the words look early or late, *Show sooner / Show later* shifts them). The finished MP4 appears in your folder; *Show in Finder* / *Share* from the last screen.
4. **Shorts** (optional) — open the *YouTube Shorts* tab, pick lyric lines, fine-tune against the waveform, render a 9:16 clip (3:00 max).

## Install options
| | `./build_app.sh` (what you use now) | `./install_native.sh` (standalone) |
|---|---|---|
| Speech + prompts run in | oMLX (needs oMLX installed) | the app itself, Swift MLX — **no oMLX, no Python** |
| App size | 4 MB | 55 MB |
| Models | whatever oMLX has | Parakeet Ultra 4-bit 0.46 GB + a language model (below) |
| Needs | Swift toolchain | Xcode + Apple's Metal Toolchain (the script installs it, ~0.7 GB, once) |

`./install_native.sh [--tier small|balanced|best] [--skip-models] [--no-install]` checks the Mac, builds with Xcode's compiler, installs to /Applications, then downloads the models once (progress shown; resumes if interrupted). The app also offers the download on first launch.

**Sizes (total on disk):** small ≈ 1.5 GB (Qwen3-1.7B) · **balanced ≈ 4.1 GB (Gemma 4 E2B, default)** · best ≈ 6.5 GB (Qwen3.5-9B). Speech is the same in every tier:
Parakeet Ultra shrunk to 4-bit keeps word timings within one frame (80 ms) of full precision and transcribes a 4-minute song in under 3 s.

## Publishing updates & installing on other Macs
Releases live on a **public GitHub repo** (Releases hold the app zip + checksum; downloading needs no GitHub account). No Apple developer account is needed.

**You (once):** `brew install gh && gh auth login`, then `./release.sh --create-repo music-video-maker` — creates the public repo, builds, tags `v1.0.1`, uploads the release.
**You (every update):** change the code, then `./release.sh` (`--bump minor`, `--version 2.0.0`, `--notes "…"` if you like). `./release.sh --dry-run` builds the zip without publishing.

**Any Mac, first time (no Xcode, no GitHub account, ~13 MB download):**
```
curl -fsSL https://raw.githubusercontent.com/drawsomerex/music-video-maker/main/install.sh | bash
```
The download is checksum-verified and `curl` doesn't tag files as downloaded from the internet, so macOS opens the app with no "unidentified developer" prompt. The first launch offers the one-time model download.

**After that the app updates itself:** it checks GitHub once a day on launch (and via *Music Video Maker ▸ Check for Updates…*), shows the release notes, and on *Install & Restart* downloads the zip, **verifies its SHA-256**, swaps itself in and relaunches. Models are separate, so an update is only ~13 MB.

Notes: this applies to the standalone (native) app. A copy built with `./build_app.sh` (the oMLX flavor) updates with `git pull && ./build_app.sh`. The app is ad-hoc signed (no paid certificate), so macOS may ask once more for access to your Movies folder after an update.

## Run
Use it like any program: `./build_app.sh --install` puts **Music Video Maker** in Applications (Launchpad / Spotlight, no Terminal). Or double-click **`Music Video.command`** (builds the app the first time). oMLX must be installed; the app launches it if it isn't running.

## Your project folder (everything you need to come back and edit)
Each song gets `~/Movies/Music Videos/<Title>/<Title> – project/`:
| File | What it is |
|---|---|
| `project.mvproj` | The save file — sections, prompts, pictures, synced lyric timings, Shorts. **Open Project** in the app (or `mvideo render/short <folder>`) reloads it |
| `audio.mp3` | A copy of your song, so the folder is self-contained |
| `transcript.txt` | Plain-text transcript from the speech model (unedited) |
| `lyrics_synced.txt` | Your lyrics with the time each line is sung, `[1:23.4] line` |
| `prompts.md` | The song description, style and an image prompt for every picture |
| `full/`, `thumbs/` | Your pictures |
| `Shorts/` | Rendered YouTube Shorts |
The finished video is saved next to the project folder.

## Runs like a normal program
- **No oMLX window.** If oMLX isn't already serving, the app starts oMLX's *engine* hidden (`omlx serve`, port 8817) and stops it 75 s after the last request so its model doesn't hold memory while rendering. If the oMLX app is already running, that one is used. The hidden engine keeps its settings in `~/Library/Application Support/MusicVideo/omlx-engine`, so your own oMLX settings are never touched.
- **Your folders.** *Settings → Where things are saved*: a Projects folder and a Finished videos & Shorts folder.
- **Live preview.** The Shorts editor (and **Preview video** for the full video) plays the real composition — same renderer as the export — next to the audio. Drag the captions up/down in the preview, or use the slider; *Safe zones* shows where YouTube's UI covers the frame.
- **Light on a 16 GB fanless Mac.** Pictures are decoded only while their section is on screen (peak memory for a whole-song vertical render: 2.5 GB → 1.7 GB, ~40% faster); render threads back off when the Mac heats up or Low Power Mode is on; oMLX's memory guard is set to *safe* when it runs the engine on a 16 GB machine.

## Exact lyric timing
Word times come from your own `parakeet-ultra-mlx` model, run with oMLX's bundled Python/MLX runtime (`scripts/word_timing.py`) — true word timestamps, no extra downloads (~6 s for a 4-minute song).
oMLX's HTTP transcription endpoint only returns text, so if its runtime can't be found the app falls back to inferring times from short overlapping windows (±0.3 s) and flags the project **“Lyric timing is approximate”** — click **Re-sync (exact)** (or `mvideo resync "<project>"`) to upgrade an older project without losing pictures or Shorts.

## YouTube Shorts (vertical 1080×1920)
Open a project → **YouTube Shorts** tab → **New Short** (30 s by default). Pick lyrics with **In / Out**, then line the music up against the waveform
(drag the green/red handles, nudge ±0.1 s / ±1 s, **Snap to word gap**, audition ▶ First 4 s / Last 4 s / Whole clip). A live 9:16 preview shows the result.

**Dynamic style kit** (on by default). Every random choice comes from one **style seed** (reproducible; **Shuffle** rolls new title/cuts).
- **Music before and after the words** — picking lyrics adds 3 s of music before the first word and 3 s after the last (adjustable; never runs into neighbouring lyrics).
- **Your song title for the first 2 s** — animates in (slam / letter-drop / bar-wipe, from the seed) while the music fades up and the picture eases back from a tight zoom. No black fade-in. Editable.
- **Lyrics in a pill** (default) — whole sentences stay on screen; the pink pill hops word to word. Also: Pop, Big, Sweep. Accent colour is selectable.
- **Calm motion** (default) — each picture gets one smooth continuous camera path; soft cuts between pictures; no picture change in the first/last 3 s. **Punchy** adds multi-angle cuts, shake and beat pulses (not recommended unless you want them).
- **Loop ending**, optional **closing text**, and **3 variants to A/B test** in YouTube Studio. Each Short also gets `<name>.txt` with an AI-written title, description and hashtags.
- **Scrubbing** — zoom the waveform onto the Start or End (down to 1.5 s across, with every word labelled); the edge you drag plays back automatically.

**Hard 3:00 limit:** a Short can never exceed 3:00 — dragging, nudging or typing past it stops at 3:00, and the renderer refuses longer clips. **New → Whole song** (or `--whole`) makes the entire song as Shorts: one video if it fits, otherwise the fewest equal-ish parts (e.g. a 4:03 song → 2 parts), each cut at a natural gap in the lyrics.

CLI: `mvideo short "<project>" --list` · `--lines 13-18 --snap --seed 4242 --variants 3 --cta "Full song on YouTube ▶" --hook "The day oil changed everything"` · `--plain` for the old simple look.

## The two steps
1. **Plan** — enter title, subject, lyrics and the MP3. Parakeet (via oMLX) syncs your lyrics, the song is split into sections (about one picture every N seconds — you choose N),
   and a local LLM writes **one shared style line + a prompt per picture** (title card = `00`). Repeated choruses are flagged so you can reuse a picture.
   Everything is saved to `prompts.md` in the work folder, and shown in the app with Copy buttons.
2. **Load your pictures** — generate them anywhere (16:9, 1920×1080+), then drag each onto its section (or load a folder of `00.png`, `01.png`, …) and press **Render**.
   Ken Burns zooms toward each picture's focal point, with feathered wipes / iris / blinds / push transitions, karaoke lyrics, title card and fade-out.

| Stage | Tech |
|---|---|
| Transcription | `parakeet-ultra-mlx` via oMLX `/v1/audio/transcriptions` (text only, so 4 s windows every 0.75 s) |
| Lyric sync | A cursor walks your lyrics; each word's time comes from which windows contain it. On-screen text is always your pasted lyrics |
| Prompts | A local language model (Gemma 4 E2B by default) — one style + per-section prompts |
| Render | Core Graphics frames in parallel → hardware H.264 via AVAssetWriter, AAC 256k, faststart MP4 (~5× real time on M1 Pro) |

## CLI / headless
```
./"Music Video.command" plan song.mp3 -t "Title" -s "subject" -l lyrics.txt -o outdir --every 15
./"Music Video.command" render "outdir/Title – work" --images ./pictures        # add --allow-missing to gradient-fill gaps
mvideo models      # check oMLX + which models are used
mvideo settings --llm-model NAME --stt-model NAME
```
oMLX's API key is read from `~/.omlx/settings.json` automatically (override with `OMLX_API_KEY`, `OMLX_URL`).

## Credits & licences
- **Parakeet Ultra** — [moondream/parakeet-ultra](https://huggingface.co/moondream/parakeet-ultra), MLX conversion [selcukkubur/parakeet-ultra-mlx](https://huggingface.co/selcukkubur/parakeet-ultra-mlx), **CC-BY-4.0** (attribution required if you redistribute the model or the app with it).
- **mlx-audio-swift** (`Vendor/`, trimmed + 3 small patches) — MIT, © Prince Canuma. **mlx-swift / mlx-swift-lm** — MIT, Apple/ML Explore.

## Project layout
`Sources/MVCore` shared engine (planning, lyric alignment, rendering) · `Sources/MusicVideoApp` SwiftUI app · `Sources/mvideo` command-line tool · `Sources/MVNative` on-device Swift-MLX models · `Vendor/` trimmed mlx-audio-swift · `scripts/` packaging and benchmarks · `docs/model-benchmarks.md` why these models were chosen · `CHANGELOG.md` release notes.

## Licence
Source is public to read; all rights reserved by the owner (no licence granted to copy or redistribute). Third-party components keep their own licences (above).
