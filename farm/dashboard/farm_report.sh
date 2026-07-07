#!/usr/bin/env bash
# farm_report.sh — push this node's GPU + service status to the farm dashboard.
# Config via env (set in the systemd unit or ~/.config/farm-report.env):
#   FARM_NODE      display name (default: hostname)
#   FARM_DASH_URL  dashboard ingest URL (default: http://192.168.1.136:8180/report)
#   FARM_SERVICES  comma list of "label=url" health checks, e.g.
#                  "llama-swap :8080=http://127.0.0.1:8080/health,researcher :8081=http://127.0.0.1:8081/health"
# Runs fine on nodes without an NVIDIA GPU (gpus:[] — Mac/CPU nodes still report services).
set -uo pipefail
[ -f "$HOME/.config/farm-report.env" ] && . "$HOME/.config/farm-report.env"
NODE="${FARM_NODE:-$(hostname)}"
URL="${FARM_DASH_URL:-http://192.168.1.136:8180/report}"
export PATH="$PATH:/usr/lib/wsl/lib"   # WSL: nvidia-smi lives here; harmless elsewhere

GPUS="[]"
if command -v nvidia-smi >/dev/null 2>&1; then
  GPUS=$(nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature.gpu,power.draw \
        --format=csv,noheader,nounits 2>/dev/null | python3 -c '
import sys, json
rows = []
for line in sys.stdin:
    p = [x.strip() for x in line.split(",")]
    if len(p) < 7: continue
    def num(v, cast=int):
        try: return cast(float(v))
        except ValueError: return None
    rows.append({"idx": num(p[0]), "name": p[1], "mem_used": num(p[2]), "mem_total": num(p[3]),
                 "util": num(p[4]), "temp": num(p[5]), "power": num(p[6], float)})
print(json.dumps(rows))')
  [ -z "$GPUS" ] && GPUS="[]"
fi

SVCS="[]"
if [ -n "${FARM_SERVICES:-}" ]; then
  SVCS=$(python3 - "$FARM_SERVICES" <<'EOF'
import json, subprocess, sys
out = []
for item in sys.argv[1].split(","):
    if "=" not in item: continue
    label, url = item.split("=", 1)
    try:
        r = subprocess.run(["curl", "-s", "--max-time", "3", "-o", "/dev/null",
                            "-w", "%{http_code}", url.strip()], capture_output=True, text=True, timeout=6)
        ok = r.stdout.strip() == "200"
    except Exception:
        ok = False
    out.append({"name": label.strip(), "ok": ok})
print(json.dumps(out))
EOF
)
fi

LOAD1=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo null)
RAM=$(free -g 2>/dev/null | awk '/^Mem:/{printf "{\"used_gb\": %d, \"total_gb\": %d}", $3, $2}')
[ -z "$RAM" ] && RAM=null

curl -s --max-time 5 -X POST "$URL" -H "Content-Type: application/json" -d "{
  \"node\": \"${NODE}\", \"ts\": $(date +%s),
  \"gpus\": ${GPUS}, \"services\": ${SVCS},
  \"load1\": ${LOAD1}, \"ram\": ${RAM}
}" > /dev/null || true
