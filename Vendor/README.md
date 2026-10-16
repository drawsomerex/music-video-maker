# Vendor

`mlx-audio-swift/` — a trimmed copy (speech-to-text stack only) of [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift), MIT licensed
(see its LICENSE). Changes from upstream:

1. `ParakeetModel.fromDirectory` is `public`.
2. `ParakeetModel.alignedResult(audio:chunkDuration:)` added — returns token-level timings (upstream only exposes sentence segments).
3. `fromDirectory` honours `"mv_internal_layout": true` in config.json (weights already in the model's internal naming, written by the app's 4-bit "slim" step) and skips the NeMo-name `sanitize` pass.

Only compiled for the native build (`MV_NATIVE=1`, see `install_native.sh`).
