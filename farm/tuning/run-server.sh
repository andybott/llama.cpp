#!/usr/bin/env bash
# Server-3090 tuning wrapper — GPU LEASE PROTOCOL (docs/GPU_LEASE_PROTOCOL_2026-07-07.md).
# gpuctl claim stops the GPU's user-timer dependents and suspends endpoint probes;
# llama-swap + local-alpha are SYSTEM units the holder manages (sudo -n present on .136).
# Runs ON the server.
set -uo pipefail
cd "$(dirname "$0")"
HOLDER=llamacpp-opt
post(){ curl -s --max-time 3 -X POST http://127.0.0.1:8180/activity -H "Content-Type: application/json" -d "{\"text\":\"$1\"}" >/dev/null 2>&1 || true; }

~/.local/bin/gpuctl claim server:3090 --holder $HOLDER --purpose "llama.cpp tuning sweep" --ttl-h 3 || { echo "GPU busy — queue with: gpuctl wait server:3090 --holder $HOLDER"; exit 1; }
post "server-3090: LEASED by $HOLDER for tuning sweep"
sudo -n systemctl stop local-alpha.timer llama-swap.service
sleep 3

NODE=server-3090 BENCH="$HOME/llama.cpp-farm/build/bin/llama-bench" \
MODEL="$HOME/models/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf" LABEL=qwen30b-a3b \
OUT="$HOME/farm-bench/tuning" DASH=http://127.0.0.1:8180 bash sweep.sh cells-server-30b.txt

sudo -n systemctl start llama-swap.service local-alpha.timer
for i in $(seq 1 40); do
  curl -s --max-time 3 http://127.0.0.1:8080/health | grep -qi ok && { OK=1; break; }
  sleep 5
done
~/.local/bin/gpuctl release server:3090 --holder $HOLDER
if [ "${OK:-0}" = 1 ]; then post "server-3090: lease RELEASED (llama-swap healthy, timer restarted)"; echo WINDOW-CLOSED-OK; exit 0; fi
post "server-3090: ⚠️ lease released but llama-swap health UNVERIFIED"; echo WINDOW-CLOSE-UNVERIFIED; exit 1
