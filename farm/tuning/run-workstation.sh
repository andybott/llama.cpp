#!/usr/bin/env bash
# Workstation-3070 tuning wrapper: window -> sweep -> window closed (health-verified).
set -uo pipefail
cd "$(dirname "$0")"
post(){ curl -s --max-time 3 -X POST http://192.168.1.136:8180/activity -H "Content-Type: application/json" -d "{\"text\":\"$1\"}" >/dev/null 2>&1 || true; }

post "workstation-3070: tuning window OPEN (researcher + coder paused)"
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
  [ "$ok" -eq 2 ] && { post "workstation-3070: tuning window CLOSED (both services healthy)"; echo WINDOW-CLOSED-OK; exit 0; }
  sleep 5
done
post "workstation-3070: ⚠️ window close UNVERIFIED — check researcher/coder"
echo WINDOW-CLOSE-UNVERIFIED; exit 1
