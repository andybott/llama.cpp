# Farm tuning methodology

The repeatable procedure for optimizing any llama.cpp node — written so the V100 boxes
(and any future hardware) get tuned the same way. Results stream live to the dashboard's
**Tuning runs** table (http://192.168.1.136:8180) and persist in
`~/farm-dashboard/history/tuning.jsonl` on the server.

## The knobs, in order of impact for CPU-offloaded MoE

1. **`-ncmoe N`** (expert layers kept in CPU RAM): fewer = more experts on GPU = better
   generation, until VRAM runs out. Sweep down from all-on-CPU until a cell FAILs or the
   serving-context probe exceeds ~93% VRAM.
2. **`-t` threads**: generation with CPU experts is memory-bandwidth-bound — more threads
   ≠ better. Sweep around physical-core count; on hybrid CPUs (P+E cores) test above it.
3. **`GGML_SCHED_PREFETCH_EXPERTS` depth** (default 3): staging-slot lookahead. 2/4/6.
4. **`-ub` ubatch**: already established (512 vs 2048 ≈ 3-4× prefill difference); 2048
   is the standard for agent prefill. Revisit only if VRAM-squeezed.

## Procedure (per node)

1. **Lease the GPU** (GPU Lease Protocol, `ai-tracevector-alpha/docs/GPU_LEASE_PROTOCOL_2026-07-07.md`):
   wrappers `gpuctl claim` (holder `llamacpp-opt`) before touching the card — this pauses
   the GPU's user-timer consumers fleet-wide, suspends endpoint probes, and queues other
   users. System units (llama-swap, local-alpha) are still stopped/started by the wrapper
   with sudo. Release only after services are health-verified. Never stop timers manually
   without a lease — the remediator restarts them within 15 min.
2. **Sweep** with `sweep.sh` at `-r 2` (exploration; ±few % noise is fine for ranking).
3. **Confirm the winner at `-r 3`**, plus a **serving probe** at the real serving config
   (full ctx, q8 KV): must load, stay under ~93% VRAM, pass a tool-call/completion smoke.
4. **Adopt only if** the winner beats the current serving config by **≥3%** on the metric
   that matters for the node's role (tg for interactive/agent nodes, pp for prefill-heavy)
   with **no >2% regression** on the other. Update the unit/llama-swap entry + the
   canonical copy in ai-tracevector-alpha, restart, re-verify health.
5. **Record**: bench JSONs → `docs/benchmarks/` ledger; decision → `FARM_UPGRADE_TASKS.md`.

## Cautions

- Never compile on a box mid-sweep (skews CPU-bound cells).
- Sequential windows for nodes the pipeline depends on; aux nodes may sweep in parallel.
- On the workstation, the orchestrating session itself adds CPU noise — re-confirm close
  threads calls at `-r 3`.
- A FAILED ncmoe cell usually = VRAM OOM at bench ctx; it would be worse at serving ctx.

## V100 bring-up (Phase 6) — apply this file

When the 4× V100 farm server (and Worker C's 5th card) come up: run the standard
validation battery first (backend-ops, token-identical), then a cells file per intended
model with the same knobs **plus** `--split-mode layer` row/layer comparisons across the
pool, and `-t` swept around that box's core count. Volta has no FA2-class kernels — do
not copy 3090 winners; measure.
