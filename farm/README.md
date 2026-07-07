# farm/ — Sparta NJ fleet build & benchmark scripts

Branch `farm/main` = pinned upstream tag + fable5 optimization patches
(pinned host memory `GGML_CUDA_REGISTER_HOST`, MoE expert prefetch
`GGML_SCHED_PREFETCH_EXPERTS`). Plan and benchmark ledger live at
`C:\Development\llama.cpp\docs\` on the hub (DESKTOP-5Q4UBCG).

Serving config (llama-swap, systemd/launchd units, LiteLLM tiers) is
canonical in `ai-tracevector-alpha/deploy/` — these scripts only build
binaries and record benchmarks.

## Per-host builds (run on the target machine)

| Host | Script | Backend |
|---|---|---|
| hub workstation (RTX 3070) | `build-cuda.sh 86` | CUDA sm_86 |
| server ai-workstation (RTX 3090) | `build-cuda.sh 86` | CUDA sm_86 |
| Strix G18 (RTX 5060) | `build-cuda.sh 120` (fallback `build-vulkan.sh`) | CUDA sm_120 / Vulkan |
| Mac Mini (M1) | `build-metal.sh` | Metal |

## Benchmarks

`farm/bench.sh <model.gguf> <label> [llama-bench args]` — pp2048/tg128,
JSON to `~/farm-bench/`, synced into the hub ledger. Every deploy needs a
before/after pair; pause tracevector GPU units first (plan §5b).
