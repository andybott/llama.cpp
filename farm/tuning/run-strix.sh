#!/usr/bin/env bash
# Strix-5060 tuning wrapper: window -> sweep -> window closed (health-verified).
set -uo pipefail
cd "$(dirname "$0")"
post(){ curl -s --max-time 3 -X POST http://192.168.1.136:8180/activity -H "Content-Type: application/json" -d "{\"text\":\"$1\"}" >/dev/null 2>&1 || true; }

post "strix-5060: tuning window OPEN (llama-strix paused)"
systemctl --user stop llama-strix.service
sleep 3
NODE=strix-5060 BENCH="$HOME/llama.cpp-farm/build/bin/llama-bench" \
MODEL="$HOME/models/qwen3-coder-reap-25b-a3b-q4_k_m.gguf" LABEL=reap25b \
OUT="$HOME/farm-bench/tuning" bash sweep.sh cells-strix-reap.txt

systemctl --user start llama-strix.service
for i in $(seq 1 40); do
  curl -s --max-time 3 http://127.0.0.1:8080/health | grep -q '"ok"' && { post "strix-5060: tuning window CLOSED (service healthy)"; echo WINDOW-CLOSED-OK; exit 0; }
  sleep 5
done
post "strix-5060: ⚠️ window close UNVERIFIED — check llama-strix.service"
echo WINDOW-CLOSE-UNVERIFIED; exit 1
