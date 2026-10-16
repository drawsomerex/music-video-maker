# Model benchmarks (M1, 16 GB, MLX, 2026-10)

Test song: "First Strike on the Caney River" (243 s, sung, 41 lyric lines). Prompts are the app's real `describe` + `write` jobs.

## Speech → word timing
| Model | Weights | Peak RAM | 243 s song | Notes |
|---|---|---|---|---|
| Parakeet Ultra bf16 | 1.25 GB | 2.3 GB | 3.0 s | reference |
| **Parakeet Ultra 4-bit (default)** | **0.48 GB** | 1.5 GB | 3.5 s | 87% of words within 80 ms of bf16 |
| Parakeet Ultra 8-bit | 0.75 GB | 1.8 GB | 3.5 s | 98% within 80 ms of bf16 |
| Parakeet TDT-CTC 110M | 0.23 GB | 1.1 GB | 2.1 s | only 73% words matched on clean speech, median error 90 ms |
| Qwen3-ForcedAligner 0.6B 4-bit | 0.97 GB | 3.9 GB | 4.3 s | needs lyrics; 20 ms median on clean speech (best), but disagrees with Ultra on singing, unverified |
| Whisper small / large-v3-turbo | – | – | – | not runnable with the bundled runtime (needs HF processor); larger than Ultra anyway |

Decision: keep Ultra 4-bit. Revisit the forced aligner if sung-word timing complaints appear.

## Text generation (4-bit MLX)
Heuristic scores overrated tiny models; human reading of outputs is what counts.
| Model | Size | Peak | Speed | Verdict |
|---|---|---|---|---|
| Qwen3.5-9B | 5 GB | 6.3 GB | 26 tok/s | best, correct era/story; too heavy for 8 GB Macs |
| **Qwen3-4B-Instruct-2507** | 2.3 GB | 3.2 GB | 47 tok/s | good prompts, may guess the wrong era |
| **Qwen3-1.7B** | ~1 GB | 1.8 GB | 98 tok/s | usable, generic, wrong era |
| Qwen3.5-0.8B / Qwen3-0.6B | <0.5 GB | 1.4–1.7 GB | 180 tok/s | unusable: pasted lyrics into prompts / repeated one prompt |
| Qwen3.5-2B/4B, SmolLM3, LFM2.5 | – | – | – | JSON parse failures, wrong facts, or slower with no gain |
| Llama-3.2-3B, Gemma-3-1B | – | – | – | JSON unusable |
| Apple FoundationModels | 0 GB | – | 18 s | ≈ 2.6B-class quality |

Decision: tiers stay small = Qwen3-1.7B, balanced = Qwen3-4B-2507 (default), best = Qwen3.5-9B.
Reproduce with `scripts/bench/`.
