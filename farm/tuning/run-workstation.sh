#!/usr/bin/env bash
# Workstation-3070 tuning wrapper — GPU LEASE PROTOCOL. wsl:3070 is visibility-only
# (nothing pausable from the server) but the lease suspends the endpoint probe, orders
# the queue, and shows the fleet the card is taken. Local services are ours to stop.
set -uo pipefail
cd "$(dirname "$0")"
HOLDER=llamacpp-opt
post(){ curl -s --max-time 3 -X POST http://192.168.1.136:8180/activity -H "Content-Type: application/json" -d "{\"text\":\"$1\"}" >/dev/null 2>&1 || true; }

ssh andyb@192.168.1.136 "~/.local/bin/gpuctl claim wsl:3070 --holder $HOLDER --purpose 'llama.cpp tuning sweep' --ttl-h 2" || { echo "GPU busy"; exit 1; }
post "workstation-3070: LEASED by $HOLDER (researcher + coder paused)"
systemctl --user stop researcher.service coder-local.service
sleep 3

NODE=workstation-3070 BENCH="$HOME/dev/llama.cpp/build/bin/llama-bench" \
MODEL="$HOME/models/qwen3-coder-reap-25b-a3b-q4_k_m.gguf" LABEL=reap25b \
OUT="$HOME/farm-bench/tuning" bash sweep.sh cells-workstation-reap.txt

systemctl --user start researcher.service coder-local.service
for i in $(seq 1 40); do
  ok=0
  curl -s --max-time 3 http://127.0.0.1:8081/health | grep -q '"ok"' && ok=$((ok+1))
  curl -s --max-time 3 http://127.0.0.1:8082/health | grep -q '"ok"' && ok=$((ok+1))
  [ "$ok" -eq 2 ] && { DONE=1; break; }
  sleep 5
done
ssh andyb@192.168.1.136 "~/.local/bin/gpuctl release wsl:3070 --holder $HOLDER"
if [ "${DONE:-0}" = 1 ]; then post "workstation-3070: lease RELEASED (both services healthy)"; echo WINDOW-CLOSED-OK; exit 0; fi
post "workstation-3070: ⚠️ lease released but service health UNVERIFIED"; echo WINDOW-CLOSE-UNVERIFIED; exit 1
