#!/usr/bin/env bash
# Server-3090 tuning wrapper: §5b window -> sweep -> window closed (health-verified).
# Needs passwordless sudo for systemctl (present on .136).
set -uo pipefail
cd "$(dirname "$0")"
post(){ curl -s --max-time 3 -X POST http://127.0.0.1:8180/activity -H "Content-Type: application/json" -d "{\"text\":\"$1\"}" >/dev/null 2>&1 || true; }

post "server-3090: tuning window OPEN (local-alpha.timer + llama-swap paused)"
sudo -n systemctl stop local-alpha.timer llama-swap.service
sleep 3
NODE=server-3090 BENCH="$HOME/llama.cpp-farm/build/bin/llama-bench" \
MODEL="$HOME/models/Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf" LABEL=qwen30b-a3b \
OUT="$HOME/farm-bench/tuning" DASH=http://127.0.0.1:8180 bash sweep.sh cells-server-30b.txt

sudo -n systemctl start llama-swap.service local-alpha.timer
for i in $(seq 1 40); do
  curl -s --max-time 3 http://127.0.0.1:8080/health | grep -qi ok && { post "server-3090: tuning window CLOSED (llama-swap healthy, timer restarted)"; echo WINDOW-CLOSED-OK; exit 0; }
  sleep 5
done
post "server-3090: ⚠️ window close UNVERIFIED — check llama-swap + local-alpha.timer"
echo WINDOW-CLOSE-UNVERIFIED; exit 1
