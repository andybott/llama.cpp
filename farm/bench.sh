#!/usr/bin/env bash
# Farm benchmark wrapper: standardized llama-bench run + JSON ledger entry.
# Usage: farm/bench.sh <model.gguf> <label> [extra llama-bench args...]
# Env: BENCH_OUT (ledger dir, default ~/farm-bench), BUILD_DIR (default build)
set -euo pipefail

MODEL="$1"; LABEL="$2"; shift 2
BUILD_DIR="${BUILD_DIR:-build}"
OUT_DIR="${BENCH_OUT:-$HOME/farm-bench}"
mkdir -p "$OUT_DIR"

GIT_DESC=$(git -C "$(dirname "$0")/.." describe --tags --always --dirty 2>/dev/null || echo unknown)
STAMP=$(date +%Y%m%d-%H%M%S)
HOST=$(hostname)
OUT="$OUT_DIR/${STAMP}_${HOST}_${LABEL}.json"

"$BUILD_DIR/bin/llama-bench" -m "$MODEL" -p 2048 -n 128 -o json "$@" > "$OUT"

python3 - "$OUT" "$GIT_DESC" "$LABEL" <<'EOF'
import json, sys
path, gitdesc, label = sys.argv[1:4]
rows = json.load(open(path))
for r in rows:
	r["farm_git"] = gitdesc
	r["farm_label"] = label
json.dump(rows, open(path, "w"), indent=1)
for r in rows:
	print(f'{label} {r.get("n_prompt",0)}p/{r.get("n_gen",0)}g: {r.get("avg_ts",0):.1f} t/s')
EOF
echo "ledger: $OUT"
