# DeepSeek-V4-Flash 284B on a Windows PC without AVX-512 (WSL2 + llama-modchip)

A reproducible guide to running **DeepSeek-V4-Flash (284B parameters, MoE) on CPU**, with 64 GB of RAM, under **Windows 11 + WSL2**, on an **Intel 10th-gen processor (AVX2, no AVX-512)**.

The upstream project [`synchopate/llama-modchip`](https://github.com/synchopate/llama-modchip) provides the engine, the patch and the model, but its prebuilt binary and its benchmarks target AVX-512 CPUs (AMD Zen 4/5). This repository documents how to adapt it to an AVX2 CPU, including the problems I ran into and the measured results.

> **This repository is not affiliated with `llama-modchip`, `llama.cpp` or DeepSeek.** It only contains documentation and small scripts. The scripts download the upstream sources from their original repositories.

## Result

On the test machine, the full model (284B, 256 experts) loads in ~68 s and answers correctly.

| | Upstream authors (Zen 5) | This machine |
|---|---|---|
| CPU | AMD Zen 5, 16 cores | Intel i9-10850K, 10 cores / 20 threads |
| RAM | 64 GB DDR5 | 2 × 32 GB DDR4, **2133 MT/s** (XMP disabled) |
| Instruction set | AVX-512 | **AVX2** (`avx avx2 fma f16c bmi2`) |
| Prompt processing | 44.4 tok/s | **6.5 tok/s** |
| Generation | 9.1 to 9.9 tok/s | **3.3 to 3.6 tok/s** |

- The "Upstream authors" column contains the figures published by the upstream project. I have not verified them.
- The "This machine" column comes from `scripts/bench.py`: a 793-token prompt (6.46 tok/s processing, 3.29 tok/s generation over 64 tokens), then a 128-token generation (3.58 tok/s). A very first, very short test gave 2.2 tok/s (cold memory pages). These are **only two series of measurements**, at a 4096 context, with the default configuration.
- CPU generation is limited by **memory bandwidth**: dual-channel DDR4-2133 gives roughly 34 GB/s versus ~90 GB/s for fast DDR5. The generation gap (≈ 2.8×) is consistent with that ratio (≈ 2.7×). The machine's GPU (RTX 4070 Ti, 12 GB) is **not used**: Fractal-64 models have no GPU path.

## Requirements

- Windows 10/11 with WSL2 (virtualization enabled in the BIOS).
- **64 GB of RAM** (the model is 56.56 GiB and uses about 57 GiB once loaded; with 64 GB the margin is very thin, see [Limitations](#limitations-and-precautions)).
- ~**120 GB** of free disk space (57 GB model + sources + build).
- An x86-64 CPU with **AVX2** (AVX-512 is not required with this procedure).
- A connection able to download ~57 GB (about 9 minutes on the test machine).

## Step-by-step installation

### 1. Install WSL2 and give it the RAM (PowerShell, on Windows)

```powershell
git clone https://github.com/MaxIKweeger/deepseek-v4-flash-284b-wsl2-avx2-64-RAM.git
cd deepseek-v4-flash-284b-wsl2-avx2-64-RAM
powershell -ExecutionPolicy Bypass -File .\scripts\01-install-wsl.ps1 -MemoryGB 59 -SwapGB 16
```

The script installs Ubuntu and creates `%USERPROFILE%\.wslconfig` (only if it does not already exist):

```ini
[wsl2]
memory=59GB
swap=16GB
processors=10
```

By default WSL2 only gets 50 % of the RAM, which is **not enough** for this model. Set `-MemoryGB` to roughly "total RAM − 5 GB". Windows may ask for a reboot the first time WSL is installed.

Then open Ubuntu: `wsl -d Ubuntu`.

### 2. Download the model (inside WSL)

The scripts live in the repository cloned on the Windows side, reachable from WSL under `/mnt/c/...`. The simplest way is to also clone the repository inside WSL:

```bash
git clone https://github.com/MaxIKweeger/deepseek-v4-flash-284b-wsl2-avx2-64-RAM.git ~/guide
bash ~/guide/scripts/02-download-model.sh
```

The model comes from Hugging Face: [`Synchopate/DeepSeek-V4-Flash-0731-Fractal-64GB-CPU-GGUF`](https://huggingface.co/Synchopate/DeepSeek-V4-Flash-0731-Fractal-64GB-CPU-GGUF) (3 `.gguf` files, 56.56 GiB in total) into `~/dsv4`. The download resumes if you rerun the script.

### 3. Build the engine for AVX2 (inside WSL)

```bash
bash ~/guide/scripts/03-build-avx2.sh
```

The script clones `llama-modchip` (commit `e0a005f`, version 2.5.0) and `llama.cpp` (commit `d2f83055`), strips the CRLF line endings from the patch, applies `patches/dsv4-64gb-cpu.patch`, copies the required RouteCrack files, then builds with:

```
-DGGML_NATIVE=ON -DGGML_AVX512=OFF -DGGML_CUDA=OFF -DLLAMA_CURL=OFF -DLLAMA_BUILD_SERVER=ON
```

Duration: about 5 minutes on 10 cores. The binary is built with `-march=native`: it is only valid for the CPU it was built on (or an equivalent one).

### 4. Start the server (inside WSL)

```bash
bash ~/guide/scripts/04-run-server.sh          # context 4096, threads = physical cores
```

Loading takes about 1 minute. The warning `failed to fit params to free device memory ... abort` is **harmless**: the server keeps going and prints `model loaded` then `listening on http://127.0.0.1:8080`.

Quick test, in another WSL terminal:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":40}'
```

From Windows, the API is also reachable at `http://127.0.0.1:8080` (WSL2 forwards the port automatically). It is OpenAI-compatible (`/v1/chat/completions`).

### 5. Benchmark

```bash
python3 ~/guide/scripts/bench.py
```

## Problems encountered and fixes

| Symptom | Cause | Fix |
|---|---|---|
| `libgomp.so.1: cannot open shared object file` when running the prebuilt binary | OpenMP library missing on a minimal Ubuntu | `sudo apt-get install -y libgomp1` |
| The prebuilt `llama-server-modchip-linux-x86_64` from the Hugging Face repo crashes while loading the model: `trap invalid opcode` / signal 4 (`SIGILL`) in `dmesg` | Built with **AVX-512** instructions that the CPU does not have | Do not use it: build it yourself (step 3) |
| `git apply`: `patch does not apply` on many files even though the commit is correct | The patch cloned on the Windows side has **CRLF** line endings | `sed 's/\r$//' patch > patch.lf` before `git apply` (done by the script) |
| Build error: `rc_predictor.h: No such file or directory` in `common/ngram-map.cpp` | The patch does not include the RouteCrack speculative-engine files | Copy `rc_predictor.h`, `rc_trie_v2.h`, `rc_stockfish.h`, `ngram-map.cpp` from the upstream repo's `speculative/cpp/` into `common/` (done by the script) |
| `unknown tensor type 40` | Fractal-64 model loaded by an unpatched `llama.cpp` / Ollama / LM Studio | Only use the patched build from step 3 |
| In Git Bash, `wsl ... bash /mnt/c/...` returns a `C:/Program Files/Git/...` path | Automatic path conversion | Prefix the command with `MSYS_NO_PATHCONV=1` |

The upstream project's Windows launcher (`windows/AVVIA_MODCHIP.bat`) **does not support** DeepSeek-V4-Flash: it only offers 8 to 30 GB models with a stock `llama.cpp`.

## Limitations and precautions

- **Very tight memory**: about 57 GiB used out of the 59 GB given to WSL. Keep the context small (4096), close heavy Windows programs, and watch `free -g` inside WSL. I did not test long contexts.
- **Speed**: 3 to 4 tok/s generation and ~6.5 tok/s prompt processing with this setup. An ~800-token prompt takes more than 2 minutes. The model outputs visible reasoning in `reasoning_content`; it may drift into Chinese.
- **Security**: the server listens on `127.0.0.1` but, by default, with no API key and open CORS (`*`). Do not expose it to the network without protection.
- **Third-party code**: the upstream patch is ~411 KB and I did not audit it in detail. The upstream project also recommends a `curl ... | python3` in some of its scripts, which I did not run.
- **Script reproducibility**: the steps were done one by one, by hand, on the test machine. The scripts in `scripts/` are the consolidated version; they were checked for syntax (`bash -n`) but **not replayed end to end from a clean machine**. If a step fails, please open an issue.
- The "Stockfish-PVS" draft model and `LLAMA_MOE_TOP_K=5/4` (pruned experts, faster but less accurate) were not measured here.
- The comments inside the scripts are written in French.

## Speeding things up: RAM

Generation depends on memory bandwidth. If your RAM runs at 2133 MT/s while it is rated for more, enable the **XMP** profile in the BIOS. First check the actual speed:

```powershell
Get-CimInstance Win32_PhysicalMemory | Select PartNumber, Speed, ConfiguredClockSpeed
```

Theoretical dual-channel bandwidth = MT/s × 8 bytes × 2: 2133 → 34 GB/s, 2933 → 47 GB/s, 3600 → 58 GB/s. As a first approximation (not measured), generation speed follows that ratio.

## Versions used

| Component | Version |
|---|---|
| llama-modchip | v2.5.0, commit `e0a005f7a150ee8b5201b22431604fd4be1e1db2` |
| llama.cpp | commit `d2f83055d6e3b379b5d34c4837122a918cf402c2` + `patches/dsv4-64gb-cpu.patch` |
| Model | `Synchopate/DeepSeek-V4-Flash-0731-Fractal-64GB-CPU-GGUF` (3 files, 56.56 GiB) |
| WSL | WSL2, Ubuntu 26.04.1 LTS, kernel 6.6.114.1-microsoft-standard-WSL2 |
| Build tools | gcc 15.2.0, CMake 4.2.3, Ninja |
| Host OS | Windows 11 Pro |

## Licenses and credits

- [`synchopate/llama-modchip`](https://github.com/synchopate/llama-modchip): Apache-2.0.
- [`ggml-org/llama.cpp`](https://github.com/ggml-org/llama.cpp): MIT.
- Model: the Hugging Face model card states an MIT license; quantized by Synchopate from `deepseek-ai/DeepSeek-V4-Flash-0731`.
