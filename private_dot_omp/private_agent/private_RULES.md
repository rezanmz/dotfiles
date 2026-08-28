# Standing rules

- Config tracking: any config change that makes sense to track MUST be made in the
  chezmoi source (`~/.local/share/chezmoi`), applied with `chezmoi apply --force`,
  verified against the live file, committed, and pushed to
  `github.com/rezanmz/dotfiles`. NEVER edit a live managed file only — the change
  would be lost on other machines and overwritten by the next `chezmoi apply`.
- Model selection: when asked to set/use a model, prefer the `opencode-go/<slug>`
  variant as primary when it exists; use `openrouter/<vendor>/<slug>` as fallback.
  If the model only exists on openrouter, use it directly and keep the previous
  opencode-go primary as first fallback entry.
