#!/usr/bin/env bash
# Vulkan build (Strix fallback). Usage: farm/build-vulkan.sh [jobs]
set -euo pipefail
JOBS="${1:-$(( $(nproc) - 2 ))}"
cd "$(dirname "$0")/.."
cmake -B build-vulkan -DGGML_VULKAN=ON -DLLAMA_CURL=ON
cmake --build build-vulkan --config Release -j "$JOBS"
build-vulkan/bin/llama-server --version
