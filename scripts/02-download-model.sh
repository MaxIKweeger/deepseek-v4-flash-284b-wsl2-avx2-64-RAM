#!/usr/bin/env bash
# Etape 2 (dans WSL/Ubuntu) : telecharge le GGUF DeepSeek-V4-Flash Fractal-64 (~57 Go).
# Usage : bash 02-download-model.sh [dossier_destination]   (defaut : ~/dsv4)
set -euo pipefail

DEST="${1:-$HOME/dsv4}"
REPO="Synchopate/DeepSeek-V4-Flash-0731-Fractal-64GB-CPU-GGUF"

sudo apt-get update -qq
sudo apt-get install -y -qq pipx curl python3
pipx install 'huggingface_hub[cli]' || true
export PATH="$PATH:$HOME/.local/bin"

mkdir -p "$DEST"
cd "$(dirname "$DEST")"
# Reprend automatiquement si le telechargement est interrompu : relancer le script.
hf download "$REPO" --local-dir "$DEST"

echo "[+] Modele telecharge dans $DEST"
ls -l "$DEST"/*.gguf
echo "[i] Le depot contient aussi un binaire precompile AVX-512 : il plante (SIGILL) sur les CPU AVX2,"
echo "    utilise scripts/03-build-avx2.sh a la place."
