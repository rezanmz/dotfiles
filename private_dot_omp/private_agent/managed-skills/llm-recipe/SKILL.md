---
name: llm-recipe
description: "Add or retune a local model in the llm CLI: measure the machine, read the model metadata cheaply, research which runtime serves it best, size weights and KV, write the recipe, verify, commit."
---

# Adding a model to `llm`

Use when exploring a new local model, comparing its quantizations, or writing/adjusting a recipe in
`~/.local/share/llm/recipes/`.

This skill holds **procedure and the user's preferences — not facts about hardware, engines, or models**. Free VRAM,
which runtime suits an architecture, the KV formats an engine accepts today, which quant tier fits: all of it moves.
Establish every number by measuring or by reading the code/docs in front of you, on the day you touch the model. If what
you measure contradicts anything you remember, the measurement wins, and the corrected finding belongs in memory
(`learn`), not in this file.

## What the user always wants (apply in this order)

1. **The largest usable context** the machine affords — not the context the model card advertises.
2. **Best quality that still fits**: the biggest quantization that keeps the headroom below. A bigger tier is not
   automatically better; compare actual bits per weight, not the tier label.
3. **A machine that stays usable.** The desktop (compositor, browser, games) must keep working while the model serves.
   "Usable" is measured, not assumed: sample VRAM and RAM with the model loaded *and* the desktop busy, not on an idle
   desktop. Fast with the card pinned out is a failed recipe.
4. **A tier that lives in page cache beats a bigger tier that spills.** When weights do not fit VRAM+RAM, every *new*
   prompt re-reads the working set from SSD. That, not decode speed, is what makes a model feel wrong.
5. **No speed claims in confs, headers, or `about=`.** Memory facts only (ctx, sizes, tokens, formats). The user does
   not want throughput numbers in config.

## Step 0 — measure the machine, now

Never reuse remembered figures; the same box changes with driver updates, swap settings and desktop load.

```sh
for d in /sys/class/drm/card*/device; do echo "$d $(cat $d/mem_info_vram_total 2>/dev/null) $(cat $d/mem_info_vram_used 2>/dev/null)"; done
grep -E 'MemTotal|MemAvailable|AnonPages|Cached:' /proc/meminfo; swapon --show; df -h /home
lscpu | grep -oE 'avx[0-9a-z_]*' | sort -u
```

Also record how much VRAM and RAM the desktop already holds (that is the reserve the model must not eat), the GPU
driver/runtime versions, and any swap/zram policy — then read the runtime's own sizing code before trusting arithmetic.

## Step 1 — read the model without downloading it

- File list and sizes: `https://huggingface.co/api/models/ORG/REPO/tree/main?recursive=true` (shard count, byte sizes;
  a shard that is an n-gram/PLE/embedding table is mmap'd and never fully resident — check which).
- Architecture: the base repo's `config.json`.
- **GGUF metadata by HTTP Range** — never fetch tens of GB to size a cache:
  ```sh
  curl -sfL -r 0-33554431 -o hdr.gguf "https://huggingface.co/ORG/REPO/resolve/main/<first shard>"
  ```
  then parse: magic `GGUF`, `<u32 version><u64 n_tensors><u64 n_kv>`, then per entry `<u64 len>key <u32 type><value>`
  (type 8 = string, 9 = array of `<u32 elem><u64 n>`; the tokenizer array alone can be several MB, hence the large
  first range). You want `*.attention.head_count_kv`, `*.attention.key_length`/`value_length`, `*.block_count`,
  `*.full_attention_interval` or `*.attention.recurrent_layers`, `*.expert_count`, `*.expert_used_count`,
  `*.embedding_length`, `*.context_length`, plus any indexer/PLE/draft-head keys.

## Step 2 — budget the weights

- **Weights per tier**: dense part + experts, from the file listing. VRAM share = measured VRAM − desktop baseline −
  whatever the runtime keeps for itself; RAM share = MemTotal − desktop − spare. Anything beyond both is read from SSD
  per prompt (see preference 4).
- **KV per token**, derived from the metadata above rather than from the model card:
  `Σ over layers that keep KV of n_head_kv × (key_len + value_len)` (+ indexer/router rows where the arch has them),
  times bytes per element for the KV format. Linear/recurrent layers cost a **fixed** state regardless of context.
- Confirm the formula against the sizing code of whichever runtime you pick in step 3 (`src/models/<arch>.cpp`,
  `src/*kv-cache*`, `src/*memory*` in a llama.cpp-style tree, or the equivalent in that runtime), because compressible
  formats, page sizes and padding change the real number.
- **Only then** pick `ctx`: the largest value whose KV still leaves the reserve. Shrink the KV (lower-precision K/V,
  quantized cache) before cutting context.

## Step 3 — decide how to serve it (research, do not inherit)

Multiple local runtimes compete, and the right one differs by architecture, quant format, GPU and version. Do not
copy the previous recipe's engine, and do not take this skill's word for anything engine-shaped: it is deliberately
empty here because it would rot. Answer these with sources, for *this* model on *this* machine:

- Does the runtime support the arch at all, and as of which release/PR? (upstream model-support code, open issues, the
  model author's own recommended runner)
- Does it offload this arch to this GPU and driver/runtime version, including this quant's kernels and this GPU's
  instruction set/target?
- Which KV cache formats it really accepts for this arch — and does it silently fall back? What does its KV math do
  with recurrent/linear layers, indexers, MLA, multi-token-prediction or draft heads?
- Can weights stay mmap'd in page cache, or must experts/weights stream? What does each cost on a *fresh* prompt?
- Which quant formats the repo ships vs what the runtime prefers (repacking, imatrix, mixed tiers), and what that costs
  in quality per byte.
- Whether speculative decoding / draft models pay off here, or only add memory pressure.

Then verify the claims by observation — run it, read its log, check which flags it accepted and what n_ctx / cache
type it reports back. Docs lag releases.

Implement the choice through the variables the launcher actually documents. Read those from `llm` itself
(`llm new <name>` scaffold, `llm help`, the header comment of `$(command -v llm)`) — that is the contract, not any list
in this skill. If the winning approach needs a knob `llm` does not expose, add it to `llm` and its completion instead of
working around it in a recipe. Keep engine findings out of this file: `learn` them.

## Step 4 — write the recipe

```sh
llm new <name>          # scaffolds ~/.local/share/llm/recipes/<name>.conf from the launcher's own key list
llm <name> --print      # verify the exact argv before running: context, cache types, template, port
```

Rules: one file per model; `$HOME` paths; never reference a path that belongs to another recipe; only keys the scaffold
documents. Add the optional fetch block when the repo and byte sizes are known, so `llm fetch` works later:

```
hf=ORG/REPO
files="dir/shard-00001-of-00002.gguf dir/shard-00002-of-00002.gguf"
bytes="<exact bytes> <exact bytes>"
fetch_dir=$HOME/models/<name>
```

## Step 5 — verify, then commit

- `llm <name>` in the foreground. Watch VRAM/RAM during load and after warm-up; read the engine log it names.
- Confirm from the log/API that the settings you asked for were **accepted** (context, cache type, offload, expert
  cache), not silently downgraded.
- Sample free VRAM/RAM with the desktop busy; if the driver evicts the model or the desktop stutters, raise the
  runtime's reserve or lower context/offload. Iterate until it is comfortable, then stop.
- `omp --profile offline` must answer: `llm` rewrites the shared offline profile on every start (provider `local`, model
  id `local`, context and media support from the recipe).
- Stop test servers by PID (`kill -INT <pid>`); never `closewindow`/`killwindow`/`movetoworkspacesilent` with an
  unconfirmed selector — Hyprland falls back to the active window and closes the wrong one.
- Track it: `chezmoi apply --force`, then `git add`/`commit`/`push` in `~/.local/share/chezmoi` with a one-line
  `llm: add <name> recipe` message. Recipes live at `dot_local/share/llm/recipes/<name>.conf`.
