# Phase 2 — workstation coder rollout (staging)

Staged artifacts for the WSL workstation (RTX 3070 8GB). Canonical home after
deployment: `ai-tracevector-alpha/deploy/wsl/` (copy these there once accepted).

## Deploy steps

```bash
# 1. versioned binary dir (pattern matches the researcher's llama-b9596-cuda)
mkdir -p ~/coder/llama-b9896-farm-cuda
cp ~/dev/llama.cpp/build/bin/llama-server ~/dev/llama.cpp/build/bin/*.so ~/coder/llama-b9896-farm-cuda/
cp ~/dev/llama.cpp/models/templates/Qwen3-Coder.jinja ~/coder/llama-b9896-farm-cuda/

# 2. start script + unit
cp start-coder.sh ~/coder/ && chmod +x ~/coder/start-coder.sh
cp coder-local.service ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now coder-local.service

# 3. verify
curl -s http://127.0.0.1:8082/health
nvidia-smi   # coder + researcher must both fit; tune UBATCH/CTX in start-coder.sh if not
```

## LiteLLM tiers.yaml addition (also append to live ~/litellm_config.yaml)

```yaml
  - { model_name: tier0-coder-local,   litellm_params: { model: openai/qwen3-coder-reap-25b-a3b, api_base: http://127.0.0.1:8082/v1, api_key: sk-local } }
```

Fallback chain (merge into router_settings when activating): local coder falls back
to the tunneled server coder.

```yaml
    - { tier0-coder-local:    [tier0-coder] }
```

## Acceptance test (spec Phase 2 exit criteria)

1. OMP coding-agent session pointed at `tier0-coder-local` — must complete a real
   coding task with working tool calls (structured tool_calls, no null/parse loops).
2. Compare latency/quality vs `tier0-coder` (tunneled 3090). Local wins on latency
   for interactive prefill; server wins on raw generation speed.
3. Exit: local coder is the OMP default; tunnel demoted to fallback.

## VRAM budget (8GB card, ~1.4GB desktop overhead in WSL)

| consumer                              | approx VRAM |
|---------------------------------------|-------------|
| researcher :8081 (gemma-E4B, ngl 99)  | ~3.6 GB     |
| coder :8082 attention+shared weights  | ~1.5–2 GB   |
| coder KV q8_0 @ 32k + ub2048 compute  | ~1.5–2.5 GB |

If over budget: UBATCH 2048→512 first (biggest compute-buffer saving; prefill cost
measured in Phase 1 matrix), then CTX 32768→16384. Re-measure with both services up.
