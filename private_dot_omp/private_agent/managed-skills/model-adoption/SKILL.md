---
name: model-adoption
description: Research a newly released LLM, decide whether it fits better than a current OMP model-role assignment, update the chezmoi-managed OMP config, apply, and push. Use when the user mentions a new model on OpenRouter or another provider and asks where it stands or to adopt/swap it.
---

# Adopting a new model into OMP

Workflow proven on 2026-08-28 adopting `tencent/hy4-preview` for `slow`/`plan`.

## 1. Research

- Read the provider model page (e.g. `https://openrouter.ai/<vendor>/<slug>`) for
  price in/out per M tokens, context, max output, modality.
- Web-search release notes and independent benchmarks (Artificial Analysis
  Intelligence Index). Flag vendor-reported scores as unverified; zero-day
  "preview" models have no independent index yet.
- Run `omp models` — output is sectioned per provider. Confirm which provider
  carries the model (`opencode-go` catalog is separate from `openrouter`) and
  note: context, max-out, thinking levels (`low,high,...` — this determines the
  effort suffix like `:high`/`:max`), and `images` yes/no.

## 2. Current role layout (personal machine)

| Role(s) | Purpose | Notes |
| --- | --- | --- |
| `default`, `task`, `vision`, `designer`, `advisor` | High-volume workhorse | Cheap + multimodal; only swap for a major jump |
| `slow`, `plan` | Reasoning; `security-reviewer` maps to `@slow` | Quality per $; cheapest place to save (was kimi-k3:max) |
| `smol`, `commit`, `tiny` | Low-effort utility | Almost never worth changing |

- `task.agentModelOverrides` and `retry.fallbackChains` must stay consistent
  with role changes (a new primary's fallback chain should start with the
  previous primary).

## 3. Fit decision

- High-volume roles: cost dominates; a preview model 10x pricier is not a fit.
- `slow`/`plan`: reasoning quality per dollar; a cheaper model with
  vendor-claimed parity is a reasonable bet IF fallbacks auto-revert.
- `vision`/`designer`: model must be multimodal (`images: yes`).
- Constraints that disqualify: no thinking levels above the role's needs, tiny
  max output for plan-sized outputs, single provider (uptime risk).
- Standing rule (see user `RULES.md`): prefer `opencode-go/<slug>` as primary
  when it exists; `openrouter` as fallback. If only on openrouter, keep the
  previous opencode-go primary as first fallback.
- Work machine branch uses `github-copilot` models only — don't touch unless
  the ask is about that machine.

## 4. Edit via chezmoi (never the live file)

- Source of truth:
  `~/.local/share/chezmoi/private_dot_omp/private_agent/private_config.yml.tmpl`
  → deploy target `~/.omp/agent/config.yml` (chezmoi strips the `private_`
  attribute from the whole filename). Note `~/.omp/agent/private_config.yml`
  is NOT managed — don't be fooled by its name.
- Edit only the `{{- else }}` (personal) branch of `eq .machine "work"` unless
  the work machine is in scope.
- Role IDs: `opencode-go/<slug>` or `openrouter/<vendor>/<slug>` + effort
  suffix from the thinking column. Fallback chain entries use the same form.
- Keep `{{-` / `-}}` trim tags on template control lines; bare `{{ if }}` lines
  render stray blank lines and make omp/chezmoi fight over the file.

## 5. Apply, verify, push

```sh
# omp rewrites config.yml (alphabetizes keys) on its own → drift prompts; --force skips the TTY confirm
chezmoi apply --force ~/.omp/agent/config.yml
# must print nothing (render == live ⇒ stable, no drift next time)
diff ~/.omp/agent/config.yml <(chezmoi cat ~/.omp/agent/config.yml)
grep -nE "^  (slow|plan|default|task):" ~/.omp/agent/config.yml
grep -A2 -E "^    (slow|plan):" ~/.omp/agent/config.yml   # fallback chains
```

- Commit in `~/.local/share/chezmoi` with an imperative one-liner subject
  (see `git log` for style) and `git push`.
- Config loads at omp startup: takes effect on the NEXT launch, not the
  current session.
