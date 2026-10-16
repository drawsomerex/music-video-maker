# Changelog

All notable changes to Music Video Maker. Newest first. **Add every user-visible change under `[Unreleased]` as you make it** —
`./release.sh` turns that section into the GitHub release notes (shown to users in the in-app "Update available" dialog) and stamps it with the version and date.

## [Unreleased]

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
