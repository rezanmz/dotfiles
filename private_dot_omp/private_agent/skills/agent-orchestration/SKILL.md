---
name: agent-orchestration
description: How to delegate to subagents (task tool) well — when to spawn, how to brief, how to batch, how to verify. Use when a task is large enough to split, when fanning out investigation or review work, or when asked to parallelize, orchestrate, or use subagents.
---

# Orchestrating subagents

Synthesized from omp's own documented mechanics plus published guidance from
Anthropic (multi-agent research system, Claude Code subagent/best-practices docs),
OpenAI Codex, Cursor, Amp, OpenHands, and Cognition. Rules below are stated as
**policy**, not as harness guarantees — omp enforces only the mechanism items in
§7.

## 1. Default to not spawning

Delegation multiplies cost (3–15x tokens) and wall-clock latency. The bar is
"independent, sizeable, bounded, and the result is worth a summary", not "this
is a big task".

**Do it yourself** when:
- it is a handful of tool calls, or a lookup whose target you already know
- you would delegate a check you could just run inline
- the work needs continuous back-and-forth with the user
- phases share heavy context (plan → implement → test in one thread)
- latency matters and the task is small — a subagent starts cold and may be slower

**Delegate** when:
- the work is genuinely independent of what you are doing next
- answering would mean reading across many files, and you only want the conclusion
- the output is verbose and would pollute your context
- 2+ independent slices can run concurrently in one wave
- you want a review with a *fresh* perspective, unanchored on your reasoning

"If you cannot write a clear brief, you do not understand the task well enough to
hand it off." When in doubt, don't spawn. Volume alone never justifies delegation.

## 2. Write a self-contained brief

Subagents start with **zero conversation history**. They do not see this chat.
The `task` string is the only context.

Every brief needs four parts:
1. **Objective** — what to achieve, and why it matters
2. **What you already ruled out** — dead ends, so they don't repeat them
3. **Pointers** — exact file paths, line numbers, commands, docs. Don't retype
   content; point at it. (Subagents share your `local://` root, so a file written
   once can be referenced.)
4. **Deliverable + boundaries** — output format, length cap, and what is out of scope

**Never delegate understanding.** Do not write "based on your findings, fix the
bug" or "based on the research, implement it" — those push synthesis onto an
agent without your context. Include the decision, not a request to make one.

- Lookups: hand over the exact command.
- Investigations: hand over the question, not a prescribed procedure — steps
  become dead weight when the premise is wrong.

## 3. Size the work, keep spawn counts low

- Simple fact-finding: 1 agent.
- Direct comparison: 2–4 agents.
- Broad independent research: more, each with clearly divided responsibility.
- Split by **context boundary, not job title**. One agent that owns a feature owns
  its tests. Planner/implementer/tester/reviewer splits spend more tokens
  coordinating than working, and every handoff loses context.
- Too small: coordination overhead exceeds the benefit. Too large: no check-ins,
  wasted effort. Right: a self-contained unit with one clear deliverable.

## 4. Batch independent work into ONE call

omp's `task` tool is batch-shaped: one call carries `{ context, tasks[] }`.

- Put every mutually independent task of the same **wave** in a single call —
  that is the only way they run concurrently.
- **Never batch dependent tasks.** The call is a wait-for-all barrier; a task that
  needs another's output must go in a later call.
- `context` carries the shared brief (goal, conventions, ruled-out hypotheses).
  Each `tasks[]` item carries its own objective/deliverable/boundaries.
- `solutionSpace` is required and is what the child's thinking classifier reads —
  it is not rendered from `task`. Describe how *open-ended* the problem is
  (e.g. `one fix: rename, names given` vs `deadlock cause open, no repro`).
- Pick the narrowest `agent` and `tools` that fit the job.

## 5. One writer per file; isolate when writes overlap

- Fan out **reads** freely — reads cannot conflict.
- **Serialize or isolate writes.** Concurrent writers to the same file overwrite
  each other. Give each writer a disjoint file set, or use `isolated: true` so it
  runs in its own worktree.
- Be conservative with parallel write-heavy work; prefer read-heavy fan-out.
- For any multi-writer wave, **one integration owner** (you) reconciles results.
  Agents cannot reliably negotiate conflicts among themselves.

## 6. Verify artifacts, never summaries

"An agent's summary describes what it intended to do, not necessarily what it
did." Claims from a subagent are unverified until you check.

- Read the actual diff, run the actual command, inspect the actual file.
- For risky work, spawn a **fresh-context reviewer** — give it the artifact and
  the criteria, never your own conclusion (a reviewer anchored on your reasoning
  cannot catch your errors).
- Give verification **exhaustive, explicit criteria**; otherwise verifiers take
  shortcuts — run one or two checks, see them pass, declare success.
- **Cap review loops.** Reject-and-fix cycles can run indefinitely (one reported
  case exceeded fifty rounds). After ~3 rounds, stop and reconsider the approach
  rather than chasing every finding; a reviewer told to find gaps will always
  find some.

## 7. omp mechanics that constrain all of the above

Documented behavior, not policy:

- **Batch shape is the default** (`task.batch: true`): `{ context, tasks[] }`.
  `context` is required and rendered into every child's system prompt.
- **Children do not inherit this conversation.** They get the workspace tree,
  skills, and the shared `local://` root — plus whatever you write in `task`.
  Inherited context files whose basename is `agents.md` are **dropped** for
  subagents (`CLAUDE.md`/`GEMINI.md` are kept). So `AGENTS.md` guidance reaches
  *you* but never a child; a **skill** does reach them. Put delegation rules here.
- **Concurrency** is capped by `task.maxConcurrency`; eval `agent()` handles are
  bounded separately by `async.maxJobs`. Exceeding the cap queues, it does not fail.
- **Recursion** is capped by `task.maxRecursionDepth`. At the cap, `task` is
  stripped from the child's tools — assume flat, one-level delegation.
- **Approval is forced to `yolo`** for children: they have no UI, so they can
  never prompt for approval. Anything destructive you delegate will just happen.
- **Soft request budget** (`task.softRequestBudget`) injects a wrap-up notice and
  force-stops around 1.5x, returning partial findings.
- **Results auto-deliver.** Do not poll; do not `wait` unless you have nothing
  else to do. Continue useful work.
- **Don't peek at a running subagent's transcript** mid-flight — it pulls tool
  noise into your context and defeats the isolation you paid for.
- **Prefer messaging an existing agent** (`write agent://<id>`) over a fresh spawn
  for follow-up work; it already holds the relevant context.

## 8. Anti-patterns

- Vague briefs → duplicated work, gaps, mis-scoped effort.
- Spawning a batch for trivial work; spawning 50 agents for a simple query.
- Delegating and then also doing the work yourself; waiting passively instead.
- **Fabricating a pending agent's result** — report "still running", never a guess.
- Trusting a summary instead of the artifact.
- Role-based splits (planner/implementer/tester) on work one agent could own.
- Dozens of near-identical agents with vague descriptions — delegation routing
  degrades and the descriptions cost context every session.
- Running verification mid-flight inside a non-owner subagent: it duplicates work
  you will redo and can be invalidated by siblings still editing. Verify once, at
  the end, in the owner of the change.
