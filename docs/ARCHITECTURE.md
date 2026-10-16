# Architecture

```
song + lyrics ─► Plan ───────────────► project folder (project.mvproj, audio.mp3, transcript, prompts.md)
                  │ speech model gives word times (Parakeet Ultra, MLX)
                  │ LyricAligner maps your lyrics onto them
                  │ Planner splits sections; language model writes description + prompts
you add pictures ─► Render ──────────► MP4 (FrameComposer → AVAssetWriter, hardware H.264)
pick lyric lines ─► Shorts ──────────► 1080×1920 clips (≤ 3:00 each)
```
Two flavors share `MVCore`: **native** (`MV_NATIVE=1`, models run inside the app via `MVNative`) and **oMLX** (talks to a local oMLX server). `NativeHooks` is the only seam between them. See `CLAUDE.md` for build, test and release steps and `docs/model-benchmarks.md` for model choices.
