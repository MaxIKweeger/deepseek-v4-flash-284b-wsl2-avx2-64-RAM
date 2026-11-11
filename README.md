# DeepSeek-V4-Flash 284B sur un PC Windows sans AVX-512 (WSL2 + llama-modchip)

Guide reproductible pour faire tourner **DeepSeek-V4-Flash (284B paramètres, MoE) sur CPU**, avec 64 Go de RAM, sous **Windows 11 + WSL2**, sur un processeur **Intel de 10ᵉ génération (AVX2, sans AVX-512)**.

Le projet amont [`synchopate/llama-modchip`](https://github.com/synchopate/llama-modchip) fournit le moteur, le patch et le modèle, mais son binaire précompilé et ses mesures visent des CPU AVX-512 (AMD Zen 4/5). Ce dépôt documente comment l'adapter à un CPU AVX2, avec les problèmes rencontrés et les mesures réelles.

> **Ce dépôt n'est pas affilié à `llama-modchip`, `llama.cpp` ni DeepSeek.** Il ne contient que de la documentation et de petits scripts. Les sources amont sont téléchargées par les scripts depuis leurs dépôts d'origine.

## Résultat

Sur la machine de test, le modèle complet (284B, 256 experts) se charge en ~68 s et répond correctement.

| | Auteurs du projet (Zen 5) | Cette machine |
|---|---|---|
| CPU | AMD Zen 5, 16 cœurs | Intel i9-10850K, 10 cœurs / 20 threads |
| RAM | 64 Go DDR5 | 2 × 32 Go DDR4, **2133 MT/s** (XMP désactivé) |
| Jeu d'instructions | AVX-512 | **AVX2** (`avx avx2 fma f16c bmi2`) |
| Traitement du prompt | 44,4 tok/s | **6,5 tok/s** |
| Génération | 9,1 à 9,9 tok/s | **3,3 à 3,6 tok/s** |

- Les chiffres de la colonne « Auteurs » sont ceux publiés par le projet amont, je ne les ai pas vérifiés.
- Les chiffres de la colonne « Cette machine » viennent de `scripts/bench.py` : un prompt de 793 tokens (6,46 tok/s en traitement, 3,29 tok/s en génération sur 64 tokens), puis une génération de 128 tokens (3,58 tok/s). Un tout premier test très court donnait 2,2 tok/s (mise en cache des pages mémoire à froid). Ce sont **deux séries de mesures seulement**, à contexte 4096, avec la configuration par défaut.
- La génération sur CPU est limitée par la **bande passante mémoire** : la DDR4-2133 en double canal offre environ 34 Go/s contre ~90 Go/s pour de la DDR5 rapide. L'écart de génération (≈ 2,8×) est cohérent avec ce rapport (≈ 2,7×). Le GPU de la machine (RTX 4070 Ti 12 Go) n'est **pas utilisé** : les modèles Fractal-64 n'ont pas de chemin GPU.

## Prérequis

- Windows 10/11 avec WSL2 (virtualisation activée dans le BIOS).
- **64 Go de RAM** (le modèle fait 56,56 Gio et occupe environ 57 Gio une fois chargé ; avec 64 Go, la marge est très faible, voir [Limites](#limites-et-précautions)).
- ~**120 Go** d'espace disque libre (modèle 57 Go + sources + compilation).
- Un CPU x86-64 avec **AVX2** (AVX-512 non requis avec cette procédure).
- Une connexion pour télécharger ~57 Go (environ 9 minutes sur la machine de test).

## Installation pas à pas

### 1. Installer WSL2 et lui donner la RAM (PowerShell, côté Windows)

```powershell
git clone https://github.com/MaxIKweeger/deepseek-v4-flash-284b-wsl2-avx2-64-RAM.git
cd deepseek-v4-flash-284b-wsl2-avx2-64-RAM
powershell -ExecutionPolicy Bypass -File .\scripts\01-install-wsl.ps1 -MemoryGB 59 -SwapGB 16
```

Le script installe Ubuntu et crée `%USERPROFILE%\.wslconfig` (seulement s'il n'existe pas) :

```ini
[wsl2]
memory=59GB
swap=16GB
processors=10
```

Par défaut WSL2 n'alloue que 50 % de la RAM, **insuffisant** pour ce modèle. Adapte `-MemoryGB` à environ « RAM totale − 5 Go ». Un redémarrage de Windows peut être demandé à la première installation de WSL.

Ouvre ensuite Ubuntu : `wsl -d Ubuntu`.

### 2. Télécharger le modèle (dans WSL)

Les scripts sont dans le dépôt cloné côté Windows, accessible depuis WSL sous `/mnt/c/...`. Le plus simple est de cloner aussi le dépôt dans WSL :

```bash
git clone https://github.com/MaxIKweeger/deepseek-v4-flash-284b-wsl2-avx2-64-RAM.git ~/guide
bash ~/guide/scripts/02-download-model.sh
```

Le modèle vient de Hugging Face : [`Synchopate/DeepSeek-V4-Flash-0731-Fractal-64GB-CPU-GGUF`](https://huggingface.co/Synchopate/DeepSeek-V4-Flash-0731-Fractal-64GB-CPU-GGUF) (3 fichiers `.gguf`, 56,56 Gio au total) dans `~/dsv4`. Le téléchargement reprend si on relance le script.

### 3. Compiler le moteur en AVX2 (dans WSL)

```bash
bash ~/guide/scripts/03-build-avx2.sh
```

Le script : clone `llama-modchip` (commit `e0a005f`, version 2.5.0) et `llama.cpp` (commit `d2f83055`), supprime les fins de ligne CRLF du patch, applique `patches/dsv4-64gb-cpu.patch`, copie les fichiers RouteCrack requis, puis compile avec :

```
-DGGML_NATIVE=ON -DGGML_AVX512=OFF -DGGML_CUDA=OFF -DLLAMA_CURL=OFF -DLLAMA_BUILD_SERVER=ON
```

Durée : environ 5 minutes sur 10 cœurs. Le binaire est compilé avec `-march=native` : il n'est valable que pour le CPU sur lequel il a été compilé (ou équivalent).

### 4. Lancer le serveur (dans WSL)

```bash
bash ~/guide/scripts/04-run-server.sh          # contexte 4096, threads = cœurs physiques
```

Le chargement prend environ 1 minute. L'avertissement `failed to fit params to free device memory ... abort` est **sans conséquence** : le serveur continue et affiche `model loaded` puis `listening on http://127.0.0.1:8080`.

Test rapide, dans un autre terminal WSL :

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Dis bonjour en une phrase."}],"max_tokens":40}'
```

Depuis Windows, l'API est aussi accessible sur `http://127.0.0.1:8080` (redirection de port automatique de WSL2). Elle est compatible OpenAI (`/v1/chat/completions`).

### 5. Mesurer

```bash
python3 ~/guide/scripts/bench.py
```

## Problèmes rencontrés et solutions

| Symptôme | Cause | Solution |
|---|---|---|
| `libgomp.so.1: cannot open shared object file` en lançant le binaire précompilé | Bibliothèque OpenMP absente d'Ubuntu minimal | `sudo apt-get install -y libgomp1` |
| Le binaire précompilé `llama-server-modchip-linux-x86_64` du dépôt Hugging Face plante au chargement du modèle : `trap invalid opcode` / signal 4 (`SIGILL`) dans `dmesg` | Compilé avec des instructions **AVX-512** que le CPU n'a pas | Ne pas l'utiliser : compiler soi-même (étape 3) |
| `git apply` : `patch does not apply` sur de nombreux fichiers alors que le commit est le bon | Le patch cloné côté Windows a des fins de ligne **CRLF** | `sed 's/\r$//' patch > patch.lf` avant `git apply` (fait par le script) |
| Erreur de compilation : `rc_predictor.h: No such file or directory` dans `common/ngram-map.cpp` | Le patch ne contient pas les fichiers du moteur spéculatif RouteCrack | Copier `rc_predictor.h`, `rc_trie_v2.h`, `rc_stockfish.h`, `ngram-map.cpp` depuis `speculative/cpp/` du dépôt amont vers `common/` (fait par le script) |
| `unknown tensor type 40` | Modèle Fractal-64 chargé par un `llama.cpp`/Ollama/LM Studio non patché | Utiliser uniquement le build patché de l'étape 3 |
| Sous Git Bash, `wsl ... bash /mnt/c/...` renvoie un chemin `C:/Program Files/Git/...` | Conversion automatique des chemins | Préfixer par `MSYS_NO_PATHCONV=1` |

Le lanceur Windows du projet amont (`windows/AVVIA_MODCHIP.bat`) **ne gère pas** DeepSeek-V4-Flash : il propose seulement des modèles de 8 à 30 Go avec un `llama.cpp` standard.

## Limites et précautions

- **Mémoire très juste** : environ 57 Gio occupés sur 59 Go alloués à WSL. Garde le contexte petit (4096), ferme les gros programmes Windows, et surveille `free -g` dans WSL. Je n'ai pas testé de contextes longs.
- **Vitesse** : 3 à 4 tok/s en génération et ~6,5 tok/s en traitement du prompt avec cette configuration. Un prompt de ~800 tokens prend plus de 2 minutes. Le modèle produit un raisonnement visible dans `reasoning_content` ; il peut dériver en chinois.
- **Sécurité** : le serveur écoute sur `127.0.0.1` mais, par défaut, sans clé d'API et avec CORS ouvert (`*`). Ne l'expose pas sur le réseau sans protection.
- **Code tiers** : le patch amont fait ~411 Ko et je ne l'ai pas audité dans le détail. Le projet amont recommande aussi un `curl ... | python3` dans certains de ses scripts, que je n'ai pas exécuté.
- **Reproductibilité des scripts** : les étapes ont été faites une par une, à la main, sur la machine de test. Les scripts de `scripts/` en sont la version consolidée ; ils ont été vérifiés pour la syntaxe (`bash -n`) mais **pas rejoués de bout en bout depuis une machine vierge**. Si une étape échoue, ouvre une issue.
- Les modèles/optimisations « Stockfish-PVS », `LLAMA_MOE_TOP_K=5/4` (experts élagués, plus rapide mais moins précis) ne sont pas mesurés ici.

## Piste pour aller plus vite : la RAM

La génération dépend de la bande passante mémoire. Si ta RAM tourne à 2133 MT/s alors qu'elle est prévue pour plus, active le profil **XMP** dans le BIOS. Vérifie d'abord la vitesse réelle :

```powershell
Get-CimInstance Win32_PhysicalMemory | Select PartNumber, Speed, ConfiguredClockSpeed
```

Bande passante théorique en double canal = MT/s × 8 octets × 2 : 2133 → 34 Go/s, 2933 → 47 Go/s, 3600 → 58 Go/s. En première approximation (non mesurée), la vitesse de génération suit ce rapport.

## Versions utilisées

| Composant | Version |
|---|---|
| llama-modchip | v2.5.0, commit `e0a005f7a150ee8b5201b22431604fd4be1e1db2` |
| llama.cpp | commit `d2f83055d6e3b379b5d34c4837122a918cf402c2` + `patches/dsv4-64gb-cpu.patch` |
| Modèle | `Synchopate/DeepSeek-V4-Flash-0731-Fractal-64GB-CPU-GGUF` (3 fichiers, 56,56 Gio) |
| WSL | WSL2, Ubuntu, noyau 6.6.114.1-microsoft-standard-WSL2 |
| OS hôte | Windows 11 Pro |

## Licences et crédits

- [`synchopate/llama-modchip`](https://github.com/synchopate/llama-modchip) : Apache-2.0.
- [`ggml-org/llama.cpp`](https://github.com/ggml-org/llama.cpp) : MIT.
- Modèle : fiche Hugging Face annonçant la licence MIT, quantification par Synchopate à partir de `deepseek-ai/DeepSeek-V4-Flash-0731`.
