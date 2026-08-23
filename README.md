# rezanmz dotfiles

A public [chezmoi](https://www.chezmoi.io/) source repository for a personal or work machine. The source is intentionally credentials-free and supports macOS plus an optional Linux X11 desktop profile.

Managed editor configuration includes the preserved Vim setup at `~/.vimrc`; chezmoi source path `dot_vimrc` restores it on every profile.

## First machine

Install chezmoi using the operating system's trusted package manager, then initialize without applying so the generated plan can be reviewed:

```sh
chezmoi init https://github.com/rezanmz/dotfiles.git
chezmoi diff
chezmoi apply
```

The first initialization prompts once for `machine` (`personal` or `work`), Git author name/email, and two MCP switches. MCP integrations default to `false`. Package prerequisites are installed manually with the operating system's trusted package manager; chezmoi never installs packages. On a work machine, keep the defaults unless your organization has approved the integration.

For a work laptop, **always inspect `chezmoi diff` before `chezmoi apply`**. Apply only after confirming that no personal application, cloud mount, home path, or integration is being enabled. Linux desktop files are ignored automatically on macOS.

## Daily operations

```sh
chezmoi git -- pull --rebase  # fetch source changes
chezmoi diff                  # review target changes (do this before apply)
chezmoi apply                 # apply only the approved plan
chezmoi edit <file>           # edit a managed file in the source state
chezmoi data                  # inspect non-secret machine data
```

Use `chezmoi add --secrets error <file>` only after reviewing the file for credentials and machine-specific state. Keep changes small, run `chezmoi diff`, and commit the source change through the normal Git review process. Install package prerequisites manually; package names vary by OS and distribution.

## Secret boundary

This is a public repository. Never add passwords, API keys, bearer values, OAuth databases, cloud credentials, SSH keys, age identities, private certificates, `.env` files, shell histories, or generated sessions. Authentication and machine state remain in the home directory or an approved secret manager. The Context7 integration uses the literal OpenCode substitution `Bearer {env:CONTEXT7_API_KEY}`; the environment variable is supplied locally and its value must never appear in source, examples, logs, or commits. Gitleaks runs on staged changes locally and on complete Git history in GitHub Actions; both scans redact findings.

## Profiles and optional fonts

`machine=work` is the conservative profile: personal-only integrations and private mounts are not managed, and network access remains opt-in. `machine=personal` may opt into the MCP booleans explicitly. Linux i3, i3status-rust, picom, rofi, and fontconfig files are gated by `.chezmoiignore` outside Linux.

Fonts are not vendored. Install Hack Nerd Font through the platform package manager if desired. B Nazanin is an optional local font; install it independently and never commit the font file.

## OMP model routing

The OMP configuration is rendered from the machine role. `personal` uses the OpenCode Go routing profile. `work` uses only `github-copilot/*` models and keeps authentication machine-local.

| OMP role | Work model | Purpose |
| --- | --- | --- |
| `default`, `task` | GPT-5.6 Sol | Primary and long-running implementation |
| `slow`, `plan` | Claude Opus 5 | Architecture, review, and highest-judgment work |
| `smol` | Gemini 3.7 Flash | Fast scouting, research, and mechanical agents |
| `vision`, `designer` | Claude Sonnet 5 | Multimodal and UI/UX work |
| `commit`, `tiny` | GPT-5.6 Luna | Low-cost utility operations |
| `advisor` | Grok 4.6 | Diverse second-opinion review |

Authenticate on the work laptop from inside OMP with `/login github-copilot`. Credentials are not managed by chezmoi. Verify the live catalog and quota after login:

```sh
omp models github-copilot --json
omp usage --provider github-copilot
```

Copilot model availability and billing metadata can change. OMP reads model capabilities dynamically; review these commands after major provider changes before updating the pinned role IDs.

## Rollback and legacy history

Review with `chezmoi diff` before every apply. To undo an uncommitted source edit, use `chezmoi git -- checkout -- <path>` and re-run `chezmoi diff`. To restore a previously applied target, use `chezmoi diff` to identify it and restore that file from the source or your normal backup. The original bare-Git Arch Linux home mirror is published at the `archlinux-2022` tag for historical recovery; it is not an active source profile and should not be copied wholesale into a new home.

## Repository protection

Install pre-commit and run `pre-commit install` after cloning. The GitHub workflow checks pushes and pull requests with a full-history checkout. If a scan finds a secret, stop, remove it from the working tree and history as appropriate, and rotate it through the owning provider; do not bypass the check or paste the finding into an issue.
