---
name: llm-recipe
description: "Add or retune a local model in the llm CLI as a gated procedure: enumerate artifacts, audit provenance, budget memory and cache, prove engine eligibility, audit capabilities, keep knob discipline, verify, record the evidence, and leave nothing running."
---

# Adding a model to `llm`

Use when exploring a new local model, comparing its artifacts, or writing/adjusting a recipe in
`~/.local/share/llm/recipes/`.

This skill is **procedure and the user's preferences, not facts about hardware, engines or models**. Free memory, which
runtime suits an architecture, the KV formats an engine accepts today, which tier fits: all of it moves. Establish every
number by measuring, or by reading the code in front of you, on the day. If a measurement contradicts a memory, the
measurement wins — and the corrected finding belongs in long-term memory (`learn`), not in this file, except as a
generalised rule.

## The shape of the job

There are two jobs here and they fail in different ways.

1. **Decide** whether this artifact, on this engine, on this machine, is worth serving at all.
2. **Provision** it safely, and prove the capabilities are real.

Provisioning is mechanical and mostly safe. The deciding half is where the expensive errors live, because each of its
questions — *faithful? reachable? fits? comparable? worth the trade?* — has no exit criterion unless one is written
down. So this procedure is built out of **gates**, and a gate is only closed by evidence.

## Gates — never cross one on assumption

| gate | question | closed by |
|---|---|---|
| **G1 faithful** | is this artifact genuinely derived from the release, unaltered? | a provenance audit against the source of truth (step 2) |
| **G2 reachable** | can this engine execute on *this* accelerator at all? | build config and device enumeration, not reputation (step 4) |
| **G3 fits** | does it leave the desktop its reserve at the context wanted? | the engine's own measured split (step 3) |
| **G4 comparable** | is any "better" established under like-for-like conditions? | equal placement, equal context, warm, repeated (step 6) |
| **G5 worth it** | does it buy enough for what it costs in quality or capability? | a stated trade, and the user's decision (see Authority) |

Every gate in that table has, at some point, looked "obviously fine" and then been wrong. A gate skipped is a claim you
can no longer make.

## What the user always wants (apply in this order)

1. **The largest usable context** the machine affords — not the context a model card advertises.
2. **The quality that still fits**, and no silent downgrade of it. A bigger tier is not automatically better; compare
   actual bits per weight rather than the tier label, and establish what "equal or better" means *before* accepting a
   trade that moves quality.
3. **A machine that stays usable.** The desktop (compositor, browser, games) must keep working while the model serves.
   Measured with the model loaded *and* the desktop busy — fast with the card pinned out is a failed recipe.
4. **Resident beats spilling.** When weights do not fit the fast memory, every new prompt re-reads the working set from
   storage. That, not token rate, is what makes a model feel wrong.
5. **Every capability the model and runtime can give — on, and verified.** Not just text: vision, tool calling, and every
   acceleration the stack supports (step 5). Turning a capability off is a decision to state and justify, never a default
   to inherit. A capability that cannot be exercised through the deployed path must be reported as absent.
6. **No performance claims in confs, headers, or `about=`.** Memory and capability facts only (context, sizes, tokens,
   formats, flags). Performance numbers age badly, and a config is not the place for them.
7. **Nothing may wear the hardware out.** Reading is free; writing is not. A model that must be re-downloaded,
   re-exported, re-converted or re-packed per start, or a runtime that spools a cache to disk continuously, turns a
   read-only workload into sustained writes — design that out. A recurring cost is unacceptable; a one-off is fine.
8. **Nothing is left serving, and nothing is left behind.** The job ends with the recipe on disk and the machine as the
   desktop expects it: no process, no port, memory returned, no client config pointing at a dead service, and no
   artifact of the investigation left unowned (step 10).
9. **Never let two accelerator jobs overlap, and never crash the user's machine to take a measurement.** This outranks
   finishing the job; a crashed machine answers nothing (step 0a).

## Step 0 — measure the machine, now

Never reuse remembered figures; the same box changes with driver, firmware and desktop load.

```sh
for d in /sys/class/drm/card*/device; do echo "$d $(cat $d/mem_info_vram_total 2>/dev/null) $(cat $d/mem_info_vram_used 2>/dev/null)"; done
grep -E 'MemTotal|MemAvailable|AnonPages|Cached:' /proc/meminfo; swapon --show; df -h /home
lscpu | grep -oE 'avx[0-9a-z_]*' | sort -u
```

Record the accelerator, driver/runtime versions, the instruction-set targets the runtime must cover, and how much memory
the desktop already holds — that is the reserve the model must not eat. Then read the runtime's own sizing code before
trusting arithmetic.

**The desktop baseline is not a constant.** It moves with browser tabs, games, video. A sample taken while your own test
server still held memory, or just after one died, is not a baseline — it is a transition. Confirm nothing of yours is
resident, let the compositor settle, and take several samples. Never conclude headroom from one reading, and never
report a number you did not see repeat.

## Step 0a — one accelerator job at a time

**A hard rule with a crash behind it.** Two full model loads on one accelerator ran a machine out of memory and took the
user's desktop down. The trigger was not the model: it was launching without checking, then *relaunching* because the
first run had not printed anything yet.

- **Before any launch, count processes.** A job that prints nothing is usually still working: evaluation and prefill take
  tens of minutes. If anything of yours is resident, wait or stop it — never start a second copy.
- **`pgrep -c` exits non-zero when it matches nothing**, so `$(pgrep -c x)` inside `set -e` or a `[ ]` test silently
  misfires. Count with `| wc -l`, or handle the status explicitly. Beware patterns that match the guard's own command
  line: `pgrep -f 'x|y'` matches itself, which both invents a phantom process and can mask a real one. Match on the
  executable (`pgrep -x`) where the name is exact.
- **A process holding the accelerator is not necessarily yours.** The user may be serving something from their own
  session, or another recipe's model may be up. Identify it (`pgrep -ax`, the port, the model path) before concluding
  anything, and **never stop or requeue something you did not start** — that is the user's, and killing it is data loss.
  Gate on your own work specifically, and if the accelerator is occupied by someone else's model, say so and ask rather
  than proceeding.
- **Gate every launch** on a check that the process count is zero *and* free memory is at least what the run needs. Put
  the guard at the top of the script so it cannot be forgotten at a call site.
- **Serialize anything that touches the accelerator.** Fanning out looks faster and is how the device runs out. A
  sequential pass that takes forty minutes is the correct cost.
- **After a crash, re-verify the machine before trusting anything**: memory back to baseline, nothing resident, and note
  that scratch space may have been wiped — rebuild inputs rather than assuming paths survive.

## Step 1 — enumerate the artifacts, then acquire

A release is a **family**, not a file: several tiers, several variants, auxiliary files (projectors, drafters, indexes),
sometimes "research" checkpoints. Adopting the first plausible file is how you silently discard the best option.

- List every file in the release and every variant table it publishes.
- For each one, record an explicit **adopt / reject-with-reason**. Silence about an artifact is a defect, not a default.
- Distinguish **tiers** (same model, different precision) from **variants** (same recipe, different behaviour or
  training) — a variant is a different model and needs its own decision.
- **Exhaust free evidence before spending on a download.** A multi-GB fetch is the *last* step of research, not the
  first act of it. Sizes, precision tables, architecture and file layout all come from metadata and directory listings;
  a header probe by HTTP range answers most structural questions without fetching the body.
- Zip several independent assumptions into one cheap probe where you can: the same partial read can confirm
  architecture, naming convention, vocabulary, and which auxiliary tensors exist.

## Step 2 — audit provenance before trusting anything (gate G1)

"Is this a faithful artifact?" is answerable, and it should never be taken from a card or a filename.

- **Compare declared structure** with the source of truth: the release's own config/metadata against the artifact's.
  Feature-by-feature, not just "looks the same".
- **Map naming across implementations.** Tensor names, key names and index bases differ between the reference and every
  exporter; prove the mapping with a structural landmark (a shape that only one position can have) rather than assuming
  an offset.
- **Spot-check values, not just shapes.** Fetch small tensors from the source by range and compare exactly. Bit-identical
  dense components plus matching structure is strong evidence; matching sizes is not.
- **Establish what was derived from what.** Ask explicitly: *was the source already quantised?* Requantising an
  already-quantised release is a second loss hidden by the tier label, and it is where unexpected quality goes. If the
  source is already low precision, the artifact is not "a quantisation of the original" and must not be described as one.
- **Record what cannot be verified.** Calibration data, undisclosed pipelines and unreproducible provenance are findings
  to report, not gaps to paper over.

## Step 3 — budget the weights, the cache, and the non-obvious buffers (gate G3)

- **Weights per tier** from the file listing: dense part and conditional/experts part separately. Fast-memory share =
  measured capacity − desktop reserve − what the runtime keeps for itself; host share = total − desktop − spare.
- **Cache per token** derived from metadata, not from a card: `Σ over layers that keep it of
  n_kv_heads × (key_len + value_len)`, times bytes per element for the format. Layers that keep a recurrent or
  convolutional state cost a **fixed** amount regardless of context.
- **Confirm the formula against the runtime's sizing code.** Compressible formats, page granularity and padding change
  the real number.
- **Budget the non-obvious buffers, and attribute each to its true owner.** The large buffer is often not the weights or
  the cache: a per-head bias or mask can scale with `context × batch × heads` and outgrow both; a recurrent state that
  looks huge in one log line is often tiny in another; host memory that looks like model state is often offloaded
  weights. Read the engine's own breakdown and quote it.
- **Never carry a number across configurations.** Cache measured at one context says nothing about another; a compute
  buffer measured at one batch size says nothing about another. Re-derive, or re-measure.
- **Only then pick the context**: the largest whose cache still leaves the reserve. Shrink the cache precision before
  cutting context.

## Step 4 — choose the engine: eligibility first, then the ecosystem (gate G2)

Several runtimes compete and the right one differs by architecture, precision format, accelerator and version. Do not
inherit the previous recipe's engine or its flags.

**Eligibility is a decision procedure, not a reputation.**

- From the runtime's own build configuration and device enumeration, answer: does it reach *this* accelerator? A hard
  `FATAL_ERROR` on an architecture list, a language/toolkit requirement, a backend that only compiles under one vendor's
  flag — any of these disqualifies it regardless of benchmark posts, and all of them are visible in the build files.
- Then check **kernel and precision coverage** for this artifact on this instruction set or device target, and which
  cache formats are genuinely accepted versus silently falling back.
- Then check whether the runtime's own flags exist for the mechanism you intend to use. A plausible engine that cannot
  execute here, or a flag that parses and does nothing, costs more than an absent option — because it wastes a
  measurement cycle before you notice.

**Sweep the ecosystem; do not only consult the engine you already know.**

- Search each candidate by the architecture's name across its **issues, pull requests, and forks**. Real support for a
  new architecture frequently lives in an open PR, a vendor branch, or a fork tuned for one device family — invisible to
  "check the engine I know".
- When a fork exists, read its own limitations section before its headline numbers: which device class the fast paths
  actually switch on for, which platform it was measured on, whether the target chip was tested at all.
- **Treat published benchmarks as claims to reproduce, not as facts.** Note the placement, precision, context and batch
  they were taken at; a headline number is only meaningful against your own run under the same shape.
- If the answer is "nothing reaches this accelerator today", say that plainly and recite what you checked — do not
  present a lower-tier arrangement as if it were the ceiling.

Then confirm the choice by observation: which flags were accepted, what context and cache type the engine reports, what
modalities and draft acceptance it actually has.

## Step 5 — audit capabilities against intent, not documentation (part of G5)

Go through this list for every model and **interrogate** each item: is the mechanism present in the artifact, does the
runtime parse it, does the deployed path expose it, and can you exercise it through that path?

1. **Vision / images** — budget the projector in fast memory or host explicitly; prefer it on; only off when it costs the
   desktop its reserve, and then say so. Verify by sending an image whose answer you know, not by reading a flag.
2. **Tool calling / function calling** — the template must parse it *and* the engine must expose the fields. Test a real
   call through the API. A template that cannot emit tool calls breaks every agent client, and that is invisible until a
   client tries.
3. **Speculative decoding / drafters** — is there one that fits the remaining memory, and does it pay? Watch the
   acceptance in the log instead of assuming. A shipped drafter can be unloadable for reasons the artifact controls
   (padding, vocabulary, layout); determine whether the mismatch is in the artifact, the target it borrows from, or the
   engine, and state which. A driver's recommendation to use *its* build is worth checking against that build's actual
   support for this architecture — a fork can lag the upstream by versions.
4. **Cache optimisations** — quantised or compressed formats, streaming versus resident, growth, prefix reuse. Take the
   format that buys the most context inside the reserve, then confirm from the log that it was accepted.
5. **Batching and scheduling knobs that change memory** — one slot for a single-user box unless there is a reason.
   Where a mask or bias term makes a buffer scale with batch size, batch is a memory knob with a real throughput cost:
   measure both ends, and record the measurement behind the choice.
6. **The sampling defaults the model ships** over guesses.
7. **Anything else the runtime offers for this architecture** — re-packing, mixed tiers, fusing, prompt lookup, graph
   capture, offload modes, effort controls. Read the option list fresh each time; this list is a starting point.
8. **Architecture-specific override knobs exist and can trade quality for speed** (repeat counts, layer skipping, draft
   length). Before adopting one: establish what quality would count as equal, check capability regressions, and check
   the *direction* — a knob's effect is not monotonic, so the intuitive setting may be worse than the trained default on
   every axis. A speed knob that quietly degrades the model is the definition of a bad trade.

## Step 6 — knob discipline: units, one change at a time, and a stopping rule (gate G4)

- **Know a knob's unit before predicting anything with it.** What does it count — layers, tensors, rows, bytes? From
  index zero or from the middle? Once per start or per token? Nearly every wrong estimate in this work came from a wrong
  unit, not from a wrong formula. State the semantics before using the knob.
- **Change one variable at a time**, with the expected direction written down before the run. A compound change is a
  measurement you cannot interpret, and it forces every conclusion to be re-derived.
- **Like-for-like or it is not a comparison**: identical placement of weights, identical context, identical cache format,
  identical sampling. Two runs that differ in where the weights live are not measuring the engine.
- **Warm before measuring, and randomise the input.** A first inference includes compilation or caching; repeating one
  prompt measures the prompt cache, not the device. Discard the warm-up, vary the input, repeat, and report a spread
  rather than a single figure.
- **A difference inside the noise is not a difference.** Take repeated samples, keep the error, and refuse to call
  something better when the bars overlap.
- **Stop when the next option no longer moves the metric beyond its own noise, or when it costs a capability.** Iteration
  has no natural terminus; write one.

## Step 7 — wear: what a start or a token costs the disk

Answer these before recommending a route; storage endurance is the one resource a bad serving setup consumes on the
user's behalf.

- **Does it write on start?** A pack build, re-export, index rebuild, rewarming step that rewrites the model file: fine
  *once*, unacceptable per start. Find the marker that skips it and what invalidates that marker — a recipe edit that
  changes cache or context may re-trigger it, so know that cost before making the edit.
- **Does it write while serving?** Cache or state spooled to a file, slot-save paths, verbose logs, page-file pressure on
  a machine whose model does not fit memory. Look for a directory growing during a run and for swap activity.
- **Does it write by design per token?** State spools, on-disk readers that index a file. A read-only map of the weights
  is the target shape: same bytes in, nothing out.
- **Does "streaming" read or rewrite?** Streaming from a mapped file is reads; a runtime that re-prepares or re-quantises
  on load is writes.
- **Verify, do not assume:** watch the process's own read/write counters across a real session, plus the filesystem
  before and after — and confirm the model file's mtime and size are unchanged. Report what was written.

## Step 8 — write the recipe

```sh
llm new <name>          # scaffolds ~/.local/share/llm/recipes/<name>.conf from the launcher's own key list
llm <name> --print      # verify the exact argv before running: context, cache types, template, port
```

One file per model; `$HOME` paths; never reference another recipe's path; only keys the scaffold documents.

**The header is a record of evidence, not of belief.**

- Every number in it must be one you measured in this session and can point at a line of output. If a later run
  contradicts it, correct it — never leave two figures that disagree.
- Every "this build or version is required" claim must be shown to **apply to this artifact**. A changelog entry can be
  real and irrelevant; a fix that touches tensors your file does not carry changes nothing here. Cite the mechanism, and
  the observation that confirms it.
- State each trade explicitly, with what justified it, and state what a later setup run would silently revert.
- **Record the rejected routes and why.** A rejection without a recorded reason gets retried — by this session, and by
  the next one. Attributing a buffer or a cost to the wrong owner is the same error as inventing a number; both become
  facts in a file people trust.

Add the optional fetch block when the publisher and byte sizes are known, so `llm fetch` works later:

```
hf=ORG/REPO
files="dir/shard-00001-of-00002.gguf dir/shard-00002-of-00002.gguf"
bytes="<exact bytes> <exact bytes>"
fetch_dir=$HOME/models/<name>
```

Implement the choice through the variables the launcher actually documents — `llm new`, `llm help`, and the header
comment of the launcher itself are the contract, not any list in this file. **When the winning approach needs a knob the
launcher does not expose, add it to the launcher and its completion** instead of hand-editing an engine config that the
next setup run overwrites: a recipe key mapping to one engine flag is diffable, tracked, and visible in `--print`, and a
guard that lives in the launcher cannot be forgotten at a call site. Keep engine findings out of this file; `learn` them.

## Step 9 — verify, then record

- Run it the way the user will. Watch memory during load and after warm-up; read the log it names.
- Confirm the settings were **accepted**, not silently downgraded, and that the capability list is live rather than
  requested: modalities reported, a real tool call round-trips, a drafter's acceptance or absence is known.
- **Exercise each capability more than once.** A failure that appears one time in four is a real defect and a single
  trial cannot see it. Report the ratio, not "it worked".
- **Confirm the work is landing on the accelerator.** Loading on the host succeeds too, at a fraction of the speed, and
  the only symptoms are a slow rate and a log that never names a device. Check the device line and the buffer sizes, and
  check that the memory the desktop sees actually moved.
- **Read paths from the source, not from memory.** When a claim is about a file existing, being gone, or holding a value,
  look at the exact path the code uses. A wrong path produces a confident, false statement.
- Prove the wear profile per step 7, and prove free memory with the desktop busy; if the driver evicts the model or the
  desktop stutters, raise the runtime's reserve or lower context before declaring it comfortable.
- Never dispatch window actions with an unconfirmed selector — the compositor falls back to the active window and closes
  the wrong one.
- Track it: `chezmoi apply --force`, then commit and push in the chezmoi source with a one-line, area-prefixed message.
  Stage only your own files: the repo may hold the user's in-progress edits, and a rebase needs them stashed and
  restored, not committed.

## Step 10 — take everything down, including what you created

Preference 8. Finish with no process, no bound port, memory returned, and no client configuration pointing at a service
that is gone. Do this **before** reporting done.

- Use the launcher's own stop path where it exists, because it verifies the port afterwards; stop anything you started
  outside it by PID and confirm each is gone. A stray process from a sweep both holds memory and silently pushes the
  next start onto the host.
- **A closed port does not mean a dead process**, and a process that outlives its parent job can leave memory mapped
  with nothing listening. Check both.
- **Clean the client state the stop path does not clean.** A launcher may rewrite a shared profile on start and leave it
  naming the dead endpoint on stop. Either remove it (if it is regenerated on the next start) or say plainly that it is
  stale until then — never claim it went away without looking at the path the code uses.
- **Own the whole footprint you created**, not just the server: downloaded artifacts you rejected, build outputs, scratch
  directories, caches, generated inputs. Say what you removed and what you kept, and why. Keeping a rejected 17 GB file
  "in case" is not cleanup.
- If the final state should be serving (the user asked for it, or a service is expected up), that is a different request
  and is stated explicitly. The default after building a recipe is **down**.
- Report the teardown as part of the result: what was stopped, what was reclaimed, what remains on disk, and what the
  shared client profile now does.

## Authority: what is yours to decide, and what is not

Investigate, build, verify, measure and report are yours. These are not, and deciding them silently is as much a defect
as asking for something you could have determined yourself:

- **accepting a quality trade** — that a model is "still good enough" at a lower precision, fewer passes, or a shorter
  context is the user's call, presented with evidence;
- **fidelity versus convenience** — preferring an unquantised or reference artifact over a convenient one when the
  difference is real;
- **installing large toolchains, or building from source** — propose it with its cost, do not start it unasked;
- **deleting data, and spending significant time or bandwidth** on an uncertain route;
- **what counts as finished** when the trade-offs are in tension.

## Quality is a frame, not a score

Your job is to make a trade-off *comparable*, not to certify it. Establish what would count as equal or better — same
inputs, same conditions, comparable artifacts — surface the disagreement, and hand the decision over. A claim that
something is "better" without a like-for-like basis is exactly the failure this procedure exists to prevent, and so is
presenting a faithful-looking artifact whose provenance you never audited.
