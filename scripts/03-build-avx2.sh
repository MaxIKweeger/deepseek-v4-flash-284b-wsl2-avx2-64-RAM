#!/usr/bin/env bash
# Etape 3 (dans WSL/Ubuntu) : compile llama.cpp + patch llama-modchip pour DeepSeek-V4-Flash,
# SANS AVX-512 (CPU Intel 10e gen, Ryzen Zen 2/3, ...). Duree : ~5 min sur 10 coeurs.
# Usage : bash 03-build-avx2.sh [dossier_de_travail]   (defaut : ~/modchip-build)
set -euo pipefail

WORK="${1:-$HOME/modchip-build}"
LLAMA_COMMIT="d2f83055"                                  # commit de llama.cpp vise par le patch
MODCHIP_COMMIT="e0a005f7a150ee8b5201b22431604fd4be1e1db2" # llama-modchip v2.5.0
JOBS="$(nproc)"

sudo apt-get update -qq
sudo apt-get install -y -qq build-essential cmake git ninja-build libomp-dev libgomp1

mkdir -p "$WORK"
cd "$WORK"

# 1) Sources amont (patch + fichiers RouteCrack)
if [ ! -d modchip ]; then
    git clone https://github.com/synchopate/llama-modchip.git modchip
fi
git -C modchip checkout -q "$MODCHIP_COMMIT"

# 2) llama.cpp au commit attendu
if [ ! -d llama.cpp ]; then
    git clone https://github.com/ggml-org/llama.cpp.git llama.cpp
fi
cd llama.cpp
git checkout -q -f "$LLAMA_COMMIT"
git clean -fdq
git checkout -q -- .

# 3) Patch : on retire d'eventuels CRLF (clone fait sous Windows => "patch does not apply")
sed 's/\r$//' ../modchip/patches/dsv4-64gb-cpu.patch > ../dsv4.lf.patch
git apply --check ../dsv4.lf.patch
git apply ../dsv4.lf.patch
echo "[+] Patch applique"

# 4) Fichiers du moteur speculatif RouteCrack (requis par common/ngram-map.cpp patche)
for f in rc_predictor.h rc_trie_v2.h rc_stockfish.h ngram-map.cpp; do
    sed 's/\r$//' "../modchip/speculative/cpp/$f" > "common/$f"
done

# 5) Compilation : -march=native (detecte AVX2 etc.), AVX-512 explicitement desactive
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_NATIVE=ON \
    -DGGML_AVX512=OFF \
    -DGGML_CUDA=OFF \
    -DLLAMA_CURL=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=ON
cmake --build build --target llama-server llama-cli -j "$JOBS"

echo "[+] Binaires : $WORK/llama.cpp/build/bin/llama-server et llama-cli"
echo "[i] Compile avec -march=native : le binaire n'est valable que pour ce CPU (ou un CPU equivalent)."
