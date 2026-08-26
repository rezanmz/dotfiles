## Personal Workflow Rules

- Classify the request before acting: quick single-file work can stay inline; unfamiliar, multi-file, risky, or cross-system work needs deliberate delegation.
- For unfamiliar code, delegate reconnaissance to `explorer` before assigning implementation. Use `oracle` for architecture, debugging hypotheses, risky refactors, and final design review; use `librarian` for external library/API facts.
- Delegate genuinely independent slices in parallel only when each writer has explicit, non-overlapping file ownership. Serialize overlapping edits rather than asking agents to resolve collisions.
- Give every delegated task exact targets, observable acceptance criteria, non-goals, and the required verification command or scenario. Prefer one-pass implementation agents over speculative planning.
- Preserve the user's requested scope. Do not add abstractions, retries, telemetry, documentation, or compatibility shims unless required by the task.
- Before claiming completion, inspect the changed contract and run the narrowest meaningful behavioral verification. Report the exact evidence and any remaining risk.
