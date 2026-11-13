---
name: llm-recipe
description: "Add or retune a local model in the llm CLI: measure the machine, read the model metadata cheaply, research which runtime and which capabilities (vision, tools, KV formats, speculative decoding) to turn on, size weights and KV, write the recipe, verify, commit."
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
5. **Every capability the model and the runtime can give — on, and verified.** Not just text: vision, tool calling,
   and every acceleration trick the stack supports (the checklist is step 3). Turning a capability off is a decision to
   state and justify, never a default to inherit. A recipe that quietly serves text-only, or with speculative decoding
   left off because nobody checked, is incomplete.
6. **No speed claims in confs, headers, or `about=`.** Memory facts only (ctx, sizes, tokens, formats, flags). The user
   does not want throughput numbers in config; they age badly and a config is not the place for them.
7. **Nothing a recipe does may wear the hardware out.** The user cares about this explicitly. Reading is free; writing is
   not. A model that has to be re-downloaded, re-exported, re-converted or re-packed on every start, or a runtime that
   spools a cache to disk continuously, turns a read-only workload into sustained SSD writes — that is a failure mode to
   design out, not to tolerate. One-off downloads, conversions and pack builds are fine; a cost that recurs per start,
   per prompt or per token is not. Check it before recommending a route, and prefer the option that reads the same bytes
   every start (the wear checklist in step 3).

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
- **Capabilities are in the metadata too**, and they decide step 3: `tokenizer.chat_template` (does it parse tool
  calls?), `*.ple.image_token_id` or an `mmproj` in the repo (vision), MTP/draft-head tensors (speculative decoding),
  `general.sampling.*` (the model's own tuned sampling defaults — do not invent your own). Read them, do not assume.

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

## Step 3 — research how to run it, and what to turn on

Multiple local runtimes compete, and the right one differs by architecture, quant format, GPU and version. Do not copy
the previous recipe's engine and do not inherit the previous recipe's flags: every line below is a question to answer
with a source (upstream model-support code, open issues/PRs, the model author's own recommended runner, the runtime's
`--help` and docs) and then confirm by observation. Docs lag releases.

**Support and placement**

- Does the runtime support this arch at all, and as of which release/PR?
- Does it offload this arch to this GPU and driver/runtime version, including this quant's kernels and this GPU's
  instruction set/target?
- Which KV cache formats it really accepts for this arch — and does it silently fall back? What does its KV math do
  with recurrent/linear layers, indexers, MLA, draft heads?
- Can weights stay mmap'd in page cache, or must experts stream? What does each cost on a *fresh* prompt? Some runtimes
  default to the memory-hungry placement; measure both.
- Which quant formats the repo ships vs what the runtime prefers (repacking, imatrix, mixed tiers), and what that costs
  in quality per byte.

**Capabilities — go through this list for every model**

1. **Vision / images**, when the model has it: an `mmproj` (llama.cpp) or a separate tower (other engines). Budget it in
   VRAM or CPU explicitly, and prefer it on — the user wants the capability, not a text-only recipe. Only turn it off
   if it costs the desktop its headroom, and then say so in the header; prefer `cpu` over `off` when that fits. Check
   what the runtime reports: `input_modalities` should include `image`.
2. **Tool calling / function calling**: the chat template must parse them and the runtime must expose the fields. State
   how tools are enabled and test one real tool call through the API — a template that cannot emit tool calls breaks
   every agent client, and that is invisible until a client tries.
3. **Speculative decoding / draft models** (MTP, draft head, EAGLE, n-gram lookup, suffix drafts): is there a drafter
   that fits the remaining memory, and does it pay? Watch the acceptance rate in the log instead of assuming; if it
   costs memory the desktop needs, prefer off and say why.
4. **KV optimizations**: quantized/compressed KV formats, KV streaming vs resident, KV growth, prompt caching and prefix
   reuse, cache tails. Take the format that buys the most context inside the reserve (preference 1), then verify from
   the engine log that it was accepted.
5. **Batching and scheduling knobs that change memory**: parallel slots, prefill chunk sizes, expert cache size,
   adaptive overlap. Prefer one slot for a single-user box unless there is a reason.
6. **The sampling defaults the model ships** (`general.sampling.*`, `generation_config.json`) over guesses.
7. **Anything else the runtime offers for this arch**: repacking, imatrix/mixed tiers, fusing, prompt-lookup decoding,
   graph capture, CPU-expert offload modes, reasoning-effort controls. Read the runtime's option list fresh each time;
   this list is a starting point, not the catalogue.

**Wear — answer these before recommending a route** (preference 7: SSD write endurance is the one machine resource a bad
serving setup actually consumes, and it is not something the recipe should spend on the user's behalf)

- **Does it write on start?** A pack/pack-build, a re-export, an index rebuild, a "warming" step that rewrites the model
  file: all fine *once*, all unacceptable per start. Check whether the build is keyed on a marker (file present → skip)
  and what invalidates that marker; a recipe that changes ctx/kv/anything can re-trigger it, so know the cost of that
  edit before making it.
- **Does it write while serving?** Prompt/KV cache spooled to a file, slot-save paths, continuous logs at debug level,
  page-file or swap pressure on a machine whose model does not fit RAM. Look for a cache directory growing during a test
  run, and for `swapon` activity — zram writes are RAM and harmless, a swap partition on SSD is not.
- **Does it write by design per token?** Some engines spool state (KV offload, prompt cache to disk, "lazy" n-gram
  readers that index a file). A read-only mmap of the weights is the target shape: same bytes in, no writes out.
- **Does streaming read or rewrite?** Expert streaming from a mapped file is reads; a runtime that "prepares" or
  re-quantizes on load is writes. This is the difference between an SSD lasting years and one lasting months.
- **Verify it, do not assume it:** watch the disk counters across a real session — `iostat -x 1`, or
  `/proc/<pid>/io` (`read_bytes` vs `write_bytes`) — plus `df` on the model's filesystem before and after. Report what
  was written, not that it "should" be read-only.

Then verify the claims by observation — run it, read its log, check which flags it accepted and what n_ctx, cache type,
modalities and draft acceptance it reports back.

Implement the choice through the variables the launcher actually documents. Read those from `llm` itself
(`llm new <name>` scaffold, `llm help`, the header comment of `$(command -v llm)`) — that is the contract, not any list
in this skill. **When the winning approach needs a knob `llm` does not expose, add it to `llm` and its completion**
instead of hand-editing an engine config that the next setup run overwrites. A recipe key that maps to one engine flag
(like `experts=mmap`) is the right shape: diffable, tracked, and visible in `llm <name> --print`. Keep engine findings
out of this file: `learn` them.

## Step 4 — write the recipe

```sh
llm new <name>          # scaffolds ~/.local/share/llm/recipes/<name>.conf from the launcher's own key list
llm <name> --print      # verify the exact argv before running: context, cache types, template, port
```

Rules: one file per model; `$HOME` paths; never reference a path that belongs to another recipe; only keys the scaffold
documents. The header comment carries the memory facts and the *why* (what did not fit, which knob was forced and onto
which value, what a later setup run would revert) — never throughput. Add the optional fetch block when the repo and
byte sizes are known, so `llm fetch` works later:

```
hf=ORG/REPO
files="dir/shard-00001-of-00002.gguf dir/shard-00002-of-00002.gguf"
bytes="<exact bytes> <exact bytes>"
fetch_dir=$HOME/models/<name>
```

## Step 5 — verify, then commit

- `llm <name>` in the foreground. Watch VRAM/RAM during load and after warm-up; read the engine log it names.
- Confirm from the log/API that the settings you asked for were **accepted** (context, cache type, offload, expert
  cache), not silently downgraded — and that the capability checklist is live, not just requested: `/v1/models` reports
  the input modalities, a real tool call round-trips, the drafter's acceptance is non-zero.
- Prove the wear profile: read `/proc/<pid>/io` before and after a real prompt and a restart. Serving should show
  `read_bytes` climbing and `write_bytes` flat; a restart should not re-write the model. If a start writes GBs, say how
  much and make it a one-off, or pick another route.
- Sample free VRAM/RAM with the desktop busy; if the driver evicts the model or the desktop stutters, raise the
  runtime's reserve or lower context/offload. Iterate until it is comfortable, then stop.
- `omp --profile offline` must answer: `llm` rewrites the shared offline profile on every start (provider `local`, model
  id `local`, context and media support from the recipe).
- Stop test servers by PID (`kill -INT <pid>`); never `closewindow`/`killwindow`/`movetoworkspacesilent` with an
  unconfirmed selector — Hyprland falls back to the active window and closes the wrong one.
- Track it: `chezmoi apply --force`, then `git add`/`commit`/`push` in `~/.local/share/chezmoi` with a one-line
  `llm: add <name> recipe` message. Recipes live at `dot_local/share/llm/recipes/<name>.conf`.
