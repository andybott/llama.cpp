#!/usr/bin/env bash
# Strix-5060 tuning wrapper — GPU LEASE PROTOCOL. strix:5060 is visibility-only; the
# lease suspends the endpoint probe + orders the queue. llama-strix is ours to stop.
# Runs ON the Strix.
set -uo pipefail
cd "$(dirname "$0")"
HOLDER=llamacpp-opt
post(){ curl -s --max-time 3 -X POST http://192.168.1.136:8180/activity -H "Content-Type: application/json" -d "{\"text\":\"$1\"}" >/dev/null 2>&1 || true; }

ssh andyb@192.168.1.136 "~/.local/bin/gpuctl claim strix:5060 --holder $HOLDER --purpose 'llama.cpp tuning sweep' --ttl-h 2" || { echo "GPU busy"; exit 1; }
post "strix-5060: LEASED by $HOLDER (llama-strix paused)"
systemctl --user stop llama-strix.service
sleep 3

NODE=strix-5060 BENCH="$HOME/llama.cpp-farm/build/bin/llama-bench" \
MODEL="$HOME/models/qwen3-coder-reap-25b-a3b-q4_k_m.gguf" LABEL=reap25b \
OUT="$HOME/farm-bench/tuning" bash sweep.sh cells-strix-reap.txt

systemctl --user start llama-strix.service
for i in $(seq 1 40); do
  curl -s --max-time 3 http://127.0.0.1:8080/health | grep -q '"ok"' && { DONE=1; break; }
  sleep 5
done
ssh andyb@192.168.1.136 "~/.local/bin/gpuctl release strix:5060 --holder $HOLDER"
if [ "${DONE:-0}" = 1 ]; then post "strix-5060: lease RELEASED (service healthy)"; echo WINDOW-CLOSED-OK; exit 0; fi
post "strix-5060: ⚠️ lease released but service health UNVERIFIED"; echo WINDOW-CLOSE-UNVERIFIED; exit 1
