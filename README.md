# rezanmz dotfiles

A public [chezmoi](https://www.chezmoi.io/) source repository for a personal or work machine. The source is intentionally credentials-free and supports macOS plus an optional Linux X11 desktop profile.

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

## Rollback and legacy history

Review with `chezmoi diff` before every apply. To undo an uncommitted source edit, use `chezmoi git -- checkout -- <path>` and re-run `chezmoi diff`. To restore a previously applied target, use `chezmoi diff` to identify it and restore that file from the source or your normal backup. The original bare-Git Arch Linux home mirror is preserved locally at the `archlinux-2022` tag for historical recovery; it is not an active source profile and should not be copied wholesale into a new home.

## Repository protection

Install pre-commit and run `pre-commit install` after cloning. The GitHub workflow checks pushes and pull requests with a full-history checkout. If a scan finds a secret, stop, remove it from the working tree and history as appropriate, and rotate it through the owning provider; do not bypass the check or paste the finding into an issue.
