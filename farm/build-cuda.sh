#!/usr/bin/env bash
# CUDA build for farm hosts. Usage: farm/build-cuda.sh <cuda-arch> [jobs]
set -euo pipefail
ARCH="${1:?cuda arch required, e.g. 86 or 120}"
JOBS="${2:-$(( $(nproc) - 2 ))}"
cd "$(dirname "$0")/.."
cmake -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES="$ARCH" -DLLAMA_CURL=ON
cmake --build build --config Release -j "$JOBS"
build/bin/llama-server --version
