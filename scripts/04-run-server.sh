#!/usr/bin/env bash
# Etape 4 (dans WSL/Ubuntu) : lance le serveur (API OpenAI sur http://127.0.0.1:8080).
# Usage : bash 04-run-server.sh [contexte] [threads]
#   contexte : defaut 4096 (la RAM est tres juste avec 64 Go, ne pas monter sans surveiller `free -g`)
#   threads  : defaut = nombre de coeurs PHYSIQUES
# Variables optionnelles : MODEL_DIR, BUILD_DIR, PORT, LLAMA_MOE_TOP_K (5 ou 4 = plus rapide, un peu moins precis)
set -euo pipefail

CTX="${1:-4096}"
THREADS="${2:-$(lscpu -p=CORE,SOCKET | grep -v '^#' | sort -u | wc -l)}"
MODEL_DIR="${MODEL_DIR:-$HOME/dsv4}"
BUILD_DIR="${BUILD_DIR:-$HOME/modchip-build/llama.cpp/build/bin}"
PORT="${PORT:-8080}"

export LD_LIBRARY_PATH="$BUILD_DIR:${LD_LIBRARY_PATH:-}"

echo "[*] contexte=$CTX threads=$THREADS port=$PORT (le chargement prend ~1 min)"
exec "$BUILD_DIR/llama-server" \
    -m "$MODEL_DIR/DeepSeek-V4-Flash-0731-Fractal-00001-of-00003.gguf" \
    -c "$CTX" -t "$THREADS" -fa on \
    --host 127.0.0.1 --port "$PORT"
