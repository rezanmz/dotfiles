# rezanmz dotfiles

A public [chezmoi](https://www.chezmoi.io/) source repository for a personal or work machine. The source is intentionally credentials-free and supports macOS plus a Linux Wayland/Hyprland desktop profile.

Managed editor configuration includes the preserved Vim setup at `~/.vimrc`; chezmoi source path `dot_vimrc` restores it on every profile.

## Linux desktop profile

The Linux profile targets Arch Linux with Hyprland on Wayland. Configuration is split by role:

| Source path | Purpose |
| --- | --- |
| `dot_config/hypr/hyprland.lua` | Entry point; `require`s the modules below |
| `dot_config/hypr/modules/00-theme.lua` | Dracula palette and the `dra()` colour helper |
| `dot_config/hypr/modules/10-monitors.lua` | Output modes (Dell U3225QE, 3840x2160@120) |
| `dot_config/hypr/modules/20-env.lua` | Wayland/Electron/Firefox environment variables |
| `dot_config/hypr/modules/30-autostart.lua` | Empty: systemd user units own startup |
| `dot_config/hypr/modules/40-look.lua` | Gaps, borders, shadows, blur, animations |
| `dot_config/hypr/modules/50-input.lua` | Keyboard layout, pointer settings |
| `dot_config/hypr/modules/60-binds.lua` | Keybindings |
| `dot_config/hypr/modules/70-rules.lua` | Window and workspace rules |
| `dot_config/hypr/hyprpaper.conf` | Wallpaper (`wallpaper { }` blocks) |
| `dot_config/hypr/hypridle.conf` | DPMS off, lock, and suspend timers |
| `dot_config/hypr/hyprlock.conf` | Lock screen |
| `dot_config/waybar/` | Status bar config and Dracula stylesheet |
| `dot_config/dunst/dunstrc` | Notifications |
| `dot_config/fuzzel/fuzzel.ini` | Launcher; also driven via `--dmenu` |
| `dot_config/systemd/user/` | `wl-clip-persist.service` |
| `dot_local/bin/executable_*` | `screenshot`, `clipboard-pick`, `exit-menu` |
| `dot_config/gtk-3.0`, `dot_config/gtk-4.0` | GTK theme, icons, cursor |
| `dot_config/chrome-flags.conf` | Forces Chrome onto the native Wayland backend |

`PACKAGES.md` lists package prerequisites; chezmoi never installs packages.

Hyprland 0.55+ reads `hyprland.lua` in preference to `hyprland.conf`. Note that
Hyprland's Lua `require()` resolves against the **current working directory**
(`./modules/...`), not the directory holding the main config, so submodules are
loaded with `loadfile()` and an absolute path built from `$XDG_CONFIG_HOME`.

`Hyprland --verify-config` does **not** reproduce that resolution, so it can
report `config ok` for a config the running compositor will reject. Treat a live
reload as the real check:

```sh
hyprctl reload && hyprctl configerrors   # must print nothing
```

Run `Hyprland --verify-config -c ~/.config/hypr/hyprland.lua` from
`~/.config/hypr` as a quick syntax check only.

The session must start through `uwsm` (the "Hyprland (uwsm-managed)" entry in
the display manager) so that waybar, hyprpaper, hypridle, cliphist and the
polkit agent run as `graphical-session.target` user units. Enable them once:

```sh
systemctl --user enable --now waybar hyprpaper hypridle cliphist hyprpolkitagent wl-clip-persist
```

## System tuning (not chezmoi-managed)

chezmoi only manages files under `$HOME`. The following `/etc` files are
machine setup and must be recreated by hand on a new install:

`/etc/systemd/zram-generator.conf` — 32 GiB RAM yields a 15.25 GiB zstd swap:

```ini
[zram0]
zram-size = ram/2
compression-algorithm = zstd
swap-priority = 100
```

`/etc/sysctl.d/99-zram.conf` — tuning for zram-only swap (the defaults assume a
seek-costly disk):

```ini
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
```

Apply the sysctl values immediately with `sudo sysctl --system`; the zram size
takes effect on reboot. Verify the generator's output without rebooting:

```sh
sudo /usr/lib/systemd/system-generators/zram-generator /tmp/zg /tmp/zg /tmp/zg
ls /tmp/zg          # expect dev-zram0.swap + systemd-zram-setup@zram0.service.d
```

### Display manager (ly) must launch the uwsm session

Six desktop units (waybar, hyprpaper, hypridle, cliphist, wl-clip-persist,
hyprpolkitagent) declare `Requisite=graphical-session.target`, which uwsm sets
up. Launched from a plain `Hyprland` session they **cannot** start at all, so
the desktop comes up without a bar, wallpaper, lock timers, clipboard history or
polkit agent.

`~/.config/uwsm/default-id` only affects `uwsm start default`; it does **not**
change what ly launches. ly stores its choice by *index* into a list it builds
at runtime, and in ly 1.4.1 that list is:

| index | entry |
| --- | --- |
| 0 | shell (`shell = true` in `/etc/ly/config.ini`) |
| 1 | `/usr/share/wayland-sessions/hyprland-uwsm.desktop` |
| 2 | `/usr/share/wayland-sessions/hyprland.desktop` |

The Wayland entries are added in raw `readdir()` order, which is not
deterministic, and ly clamps an out-of-range saved index to the last entry. A
stale `reza:3` therefore silently selects plain Hyprland. Pin it explicitly with
a dedicated session directory holding exactly one entry:

```sh
sudo mkdir -p /etc/ly/wayland-sessions
sudo ln -sf /usr/share/wayland-sessions/hyprland-uwsm.desktop \
            /etc/ly/wayland-sessions/hyprland-uwsm.desktop
sudo sed -i 's|^waylandsessions = .*|waylandsessions = /etc/ly/wayland-sessions|' /etc/ly/config.ini
```

This makes the list `0` = shell, `1` = hyprland-uwsm. `/etc/ly/save.txt` then
reads `1` / `root:0` / `reza:1`. ly rewrites that file on every login, so the
file heals itself after one correct login. Confirm the result with:

```sh
tr '\0' ' ' < /proc/$(pgrep -x Hyprland | head -1)/cmdline   # want a uwsm wrapper, not "Hyprland --watchdog-fd"
systemctl --user is-active graphical-session.target            # want: active
```

### Bluetooth input

BlueZ only reconnects to **paired and bonded** devices, so trust alone is not
enough. `/etc/bluetooth/main.conf` sets an explicit retry policy:

```ini
[Policy]
ReconnectAttempts=10
ReconnectIntervals=1,2,4,8,16,32,64,128,256,512
```

`FastConnectable=true` additionally keeps the controller page-scanning, which
shortens the connect window at boot.

Pair a keyboard once over Bluetooth (it must be *paired*, not just trusted) and
BlueZ will bring it back automatically from then on, including while ly is
showing — ly runs inside the same systemd session as the `bluetooth.service`
daemon, so the keyboard is already available before any compositor starts.
A device that is only ever used over USB (as the Keychron K8 Pro is here)
cannot auto-reconnect over Bluetooth until it is paired on that transport.



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

`machine=work` is the conservative profile: personal-only integrations and private mounts are not managed, and network access remains opt-in. `machine=personal` may opt into the MCP booleans explicitly. The Linux Hyprland, waybar, dunst, fuzzel, GTK, fontconfig, systemd-user, and `.local/bin` files are gated by `.chezmoiignore` outside Linux.

Fonts are not vendored. Install Hack Nerd Font (`ttf-hack-nerd`) through the platform package manager; waybar and the terminals need its glyphs. The wallpaper at `~/.local/share/wallpapers/current.png` is machine-local and not vendored. B Nazanin is an optional local font; install it independently and never commit the font file.

## OMP model routing

The OMP configuration is rendered from the machine role. `personal` uses the OpenCode Go routing profile. `work` uses only `github-copilot/*` models and keeps authentication machine-local.

| OMP role | Work model | Purpose |
| --- | --- | --- |
| `default`, `task` | GPT-5.6 Terra | Everyday implementation and delegated coding |
| `slow` | Claude Opus 5 | Highest-judgment review and security |
| `plan` | GPT-5.6 Sol | Architecture and deep coding plans |
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
