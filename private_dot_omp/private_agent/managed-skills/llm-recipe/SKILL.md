---
name: llm-recipe
description: "Add or retune a local model in the llm CLI: read the model's metadata cheaply, size weights and KV cache against this machine, choose quantization and context, write the recipe, verify, commit."
---

# Adding a model to `llm`

Use when exploring a new local model, comparing its quantizations, or writing/adjusting a recipe in
`~/.local/share/llm/recipes/`.

## What the user always wants (apply in this order)

1. **The largest usable context** the machine affords — not the context the model card advertises.
2. **Best quality that still fits**: prefer the biggest quantization that keeps the headroom below. A bigger tier is
   not automatically better (Q2_0 vs IQ2_XS: IQ2_XS is larger and no better here).
3. **A machine that stays usable**: after a start, aim for **≥ 2 GiB VRAM free** for the desktop (compositor, Chrome,
   Steam) and **≥ 4 GiB spare RAM**. Cheap and fast with 500 MiB of VRAM left is a failed recipe.
4. **A tier that lives in page cache beats a bigger tier that spills.** When weights do not fit VRAM+RAM, every *new*
   prompt re-reads the whole expert set from the SSD. That, not decode, is what makes a model feel wrong.
5. **No speed claims in confs, headers, or the `about=` line.** Memory facts only (ctx, GiB, tokens, sizes). The user
   does not want throughput numbers in config.

## This machine (verify, do not recall old numbers)

```sh
for d in /sys/class/drm/card*/device; do echo "$d $(cat $d/mem_info_vram_total) $(cat $d/mem_info_vram_used)"; done
grep -E 'MemTotal|MemAvailable|AnonPages|Cached:' /proc/meminfo; swapon --show; df -h /home
```
Known shape: RX 9070 XT **15.9 GiB VRAM** (gfx1201, HIP engine 0.1.59), **30.5 GiB RAM**, WD_BLACK SN850X 1 TB,
Ryzen 7800X3D (AVX-512, so Strata's Q2_0 repack applies), zram 15 GiB with `vm.swappiness=180` (it compresses desktop
pages so the expert page cache survives — do not "fix" it to 20 while serving). Desktop baseline while busy:
~1.9 GiB VRAM, ~4 GiB anonymous RAM.

## Step 1 — read the model without downloading it

- File list and sizes: `https://huggingface.co/api/models/ORG/REPO/tree/main?recursive=true` (shard count, byte sizes,
  shard 2 often the n-gram/PLE table which is mmap'd and never resident).
- Architecture: the base repo's `config.json`.
- **GGUF metadata by HTTP Range** — never fetch 40 GB to size a cache:
  ```sh
  curl -sfL -r 0-33554431 -o hdr.gguf "https://huggingface.co/ORG/REPO/resolve/main/<first shard>"
  ```
  then parse: magic `GGUF`, `<u32 version><u64 n_tensors><u64 n_kv>`, then per entry `<u64 len>key <u32 type><value>`
  (type 8 = string, 9 = array of `<u32 elem><u64 n>`; the tokenizer array alone is ~5 MB, hence 32 MB).
  You want `*.attention.head_count_kv`, `*.attention.key_length`/`value_length`, `*.block_count`,
  `*.full_attention_interval` or `*.attention.recurrent_layers`, `*.expert_count`, `*.expert_used_count`,
  `*.embedding_length`, `*.context_length`, plus any indexer/PLE keys.

## Step 2 — budget, in this order

- **Weights** per tier: dense part + experts. VRAM share = 15.9 − (draft ~1 GiB) − reserve; RAM share = 30.5 − 4
  (desktop) − 4 (spare). Whatever exceeds those is read from the SSD.
- **KV per token** computed from the metadata above, not from the card:
  `Σ over layers that keep KV of n_head_kv × (key_len + value_len)` (+ indexer rows for QSA/DSA-style archs).
  Linear/recurrent layers cost a **fixed** state regardless of context.
- Check the arithmetic against the engine's own sizing code: `src/models/<arch>.cpp`, `src/llama-kv-cache.cpp`,
  `src/llama-memory-*.cpp` in a llama.cpp checkout (`~/.unsloth/llama.cpp`).
- **Then** pick `ctx`: the largest value whose KV still leaves the reserve. Halve the KV by choosing `k8v4` then `q4_0`
  before cutting context.

## Step 3 — pick the engine

| | `engine=llama` | `engine=strata` |
|---|---|---|
| when | a plain single-file GGUF that fits RAM/VRAM | experts do not fit (the file must be streamed), or the arch is Strata's (`qwen4exp`…) |
| gives | mmap + page cache, no expert streaming | pack (`experts.bin`), expert cache in VRAM, `reserve=`, `strata_config=` per model |
| keys | `llama_dir`, `template`, `args`, `flags`, `mtp` | `vision=`, `reserve=`, `mtp=`, `strata_config=` |

Strata-specific facts worth remembering: low-RAM mode turns on by itself when `RAM < experts + 10 GiB` (experts are
mmap'd, KV stays in VRAM — so **context trades against VRAM expert cache, not RAM**); `strata launch` rewrites
`--vram-reserve-mib` to 700 MiB on a 16 GB card with the GPU reader, and `llm` writes the requested value back after
setup; `--conversation-cache-mib` defaults to 8 GiB of RAM for parked conversations.

## Step 4 — write the recipe

```sh
llm new <name>          # writes ~/.local/share/llm/recipes/<name>.conf
llm <name> --print      # verify the exact argv before running: -ctk/-ctv, template path, ctx, port
```

Rules: one file per model, `$HOME` paths, never a path belonging to another recipe. `strata_config=` must be that
model's own run config in `~/.local/share/strata/install/`. Add the optional fetch block only when you know the repo
and byte sizes:

```
hf=ORG/REPO
files="dir/shard-00001-of-00002.gguf dir/shard-00002-of-00002.gguf"
bytes="38021379872 28800138432"
fetch_dir=$HOME/models/<name>
```

## Step 5 — verify, then commit

- `llm <name>` in the foreground; watch VRAM during and after the load; read the engine log
  (`~/.local/state/strata/launch/<cfg>.engine.log` for Strata; the `llama-server` stanza for llama.cpp:
  `n_ctx_slot`, KV types accepted).
- Strata log lines that matter: `expert cache auto: … → N slots`, `prefill plan: … fits the page cache`,
  `conversation cache sized from the free RAM`.
- Free VRAM after start must be **≥ 1 GiB**; if the desktop stutters or the driver moves the cache to RAM, raise
  `reserve=` (Strata) or lower `ctx`/`-ngl` (llama.cpp).
- `omp --profile offline` must answer: `llm` rewrites `~/.omp/profiles/offline/agent/models.yml` on every start
  (provider `local`, model id `local`, context and image support from the recipe).
- Stop test servers by PID (`kill -INT <pid>`); never `closewindow`/`killwindow` with an unconfirmed selector.
- Track it: `chezmoi apply --force`, then `git add`/`commit`/`push` in `~/.local/share/chezmoi` with a one-line
  `llm: add <name> recipe` message. Recipes live at `dot_local/share/llm/recipes/<name>.conf`.

## Worked example — Qwen3.8-Flash-Next (qwen4exp)

48 layers, `full_attention_interval=4` → 12 layers keep KV; `head_count_kv=2`, key/value length 256; indexer 4 heads ×
128 (cached as raw+pooled rows = 256 per layer) on the same 12 layers. KV per token = 12×1024 + 12×256 = **15,360
elements** → int8 0.50 GiB at 32K, 1.00 at 64K, 1.99 at 128K, 3.98 at 262K; k8v4 = 0.40/0.81/1.62/3.24;
q4_0 = 0.26/0.53/1.05/2.11. The 36 DeltaNet layers add a fixed **112 MiB**. Experts are 34 GB, so on 15.9 GiB VRAM +
30.5 GiB RAM only the Q2_0 tier fits, and it streams: `reserve=2048`, `kv=k8v4`, `ctx=131072`.
