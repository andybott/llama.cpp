#!/usr/bin/env bash
# start-coder.sh — local llama-server backing the OMP coder role (tier0-coder-local).
# Serves Qwen3-Coder-REAP-25B-A3B on 127.0.0.1:8082 from the fable5-patched farm build.
# Runs on THIS workstation's RTX 3070 (8GB): expert weights stay in CPU RAM (--n-cpu-moe)
# so only attention/shared weights + KV live in VRAM. GGML_CUDA_REGISTER_HOST pins the
# mmap'd expert pages for fast H2D; GGML_SCHED_PREFETCH_EXPERTS overlaps expert upload
# with compute (fable5 patches — Phase 1 validated token-identical on this hardware).
#
# --chat-template-file is REQUIRED for agentic tool use: the GGUF's embedded template
# makes REAP emit malformed tool calls that llama.cpp can't parse (tool_calls:null, OMP
# loops). The bundled Qwen3-Coder.jinja builds the proper tool grammar + parser.
# (Same fix as the server's llama-swap entry — see ai-tracevector-alpha
# deploy/llama_cpp/gen_config.sh.)
#
# Idempotent: exits early if already up. Rollback: systemctl --user stop coder-local,
# OMP falls back to tier0-coder (SSH tunnel :8090 to the server's 3090 REAP).
set -euo pipefail
BIN_DIR="$HOME/coder/llama-b9896-farm-cuda"
MODEL="$HOME/models/qwen3-coder-reap-25b-a3b-q4_k_m.gguf"
TEMPLATE="$BIN_DIR/Qwen3-Coder.jinja"
PORT=8082
ALIAS=qwen3-coder-reap-25b-a3b

# --- Phase-1-tuned knobs (3070 8GB, must coexist with :8081 researcher ~3.6GB) ---
NCMOE=99        # all expert layers in CPU RAM (~13GB of the 15GB GGUF)
UBATCH=2048     # fastest prefill; drop to 512 if VRAM-tight next to the researcher
CTX=32768       # q8_0 KV; drop to 16384 if VRAM-tight
THREADS=15

if curl -s --max-time 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  echo "coder already up on :${PORT}"
  exit 0
fi

export GGML_CUDA_REGISTER_HOST=1
export GGML_SCHED_PREFETCH_EXPERTS=3
export LD_LIBRARY_PATH="${BIN_DIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
nohup "${BIN_DIR}/llama-server" \
  -m "${MODEL}" \
  --host 127.0.0.1 --port "${PORT}" \
  -ngl 99 --n-cpu-moe "${NCMOE}" \
  --flash-attn on --jinja \
  --chat-template-file "${TEMPLATE}" \
  --ctx-size "${CTX}" \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --ubatch-size "${UBATCH}" --cache-reuse 256 \
  --threads "${THREADS}" \
  --alias "${ALIAS}" \
  > "${HOME}/coder/coder.log" 2>&1 < /dev/null &
echo "started coder (pid $!) on :${PORT} — model ${ALIAS} (3070 CUDA, ncmoe=${NCMOE} ub=${UBATCH} ctx=${CTX})"
