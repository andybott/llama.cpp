#!/usr/bin/env bash
# Generic llama-bench tuning sweep. Each cell posts live to the farm dashboard
# (/tuning table + /activity line) and writes its llama-bench JSON to $OUT.
#
# Usage:
#   NODE=<dashboard node name> BENCH=<llama-bench path> MODEL=<gguf> LABEL=<model tag> \
#   OUT=<results dir> [DASH=http://192.168.1.136:8180] bash sweep.sh <cells-file>
#
# Cells file: one cell per line —  <label> :: <ENV assignments or empty> :: <llama-bench args>
#   e.g.  t8_pf3 :: GGML_CUDA_REGISTER_HOST=1 GGML_SCHED_PREFETCH_EXPERTS=3 :: -p 2048 -n 128 -r 2 -ncmoe 99 -ub 2048 -t 8
# '#' lines and blanks are skipped. A failing/OOM cell posts FAILED and the sweep continues.
set -uo pipefail
DASH="${DASH:-http://192.168.1.136:8180}"
CELLS="${1:?cells file required}"
mkdir -p "$OUT"

post(){ curl -s --max-time 3 -X POST "$DASH/$1" -H "Content-Type: application/json" -d "$2" >/dev/null 2>&1 || true; }

N=$(grep -cvE "^\s*(#|$)" "$CELLS")
I=0
while IFS= read -r line; do
  case "$line" in \#*|"") continue;; esac
  label="$(echo "${line%%::*}" | xargs)"
  rest="${line#*::}"
  envs="$(echo "${rest%%::*}" | xargs)"
  args="$(echo "${rest#*::}" | xargs)"
  I=$((I+1))
  post activity "{\"text\":\"tuning $NODE/$LABEL [$I/$N]: $label\"}"
  f="$OUT/$(echo "${LABEL}_${label}" | tr -c 'A-Za-z0-9._-' '_' | sed 's/_$//').json"
  if env $envs timeout 900 "$BENCH" -m "$MODEL" $args -o json > "$f" 2>"$f.err"; then
    read -r PP TG <<< "$(python3 -c "
import json,sys
pp=tg='null'
for r in json.load(open(sys.argv[1])):
    if r['n_prompt']>0 and r['n_gen']==0: pp=round(r['avg_ts'],1)
    if r['n_gen']>0 and r['n_prompt']==0: tg=round(r['avg_ts'],1)
print(pp,tg)" "$f")"
    echo "[$I/$N] $label: pp=$PP tg=$TG"
    post tuning "{\"node\":\"$NODE\",\"model\":\"$LABEL\",\"config\":\"$label\",\"pp\":$PP,\"tg\":$TG}"
  else
    echo "[$I/$N] $label: FAILED (see $f.err)"
    post tuning "{\"node\":\"$NODE\",\"model\":\"$LABEL\",\"config\":\"$label FAILED\",\"pp\":null,\"tg\":null}"
  fi
done < "$CELLS"
post activity "{\"text\":\"tuning $NODE/$LABEL: sweep complete ($N cells)\"}"
echo "SWEEP-DONE"
