#!/usr/bin/env bash
# Metal build (Mac Mini M1). Usage: farm/build-metal.sh [jobs]
set -euo pipefail
JOBS="${1:-$(sysctl -n hw.ncpu)}"
cd "$(dirname "$0")/.."
cmake -B build -DGGML_METAL=ON -DLLAMA_CURL=ON
cmake --build build --config Release -j "$JOBS"
build/bin/llama-server --version
