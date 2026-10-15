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
| `dot_config/hypr/modules/30-autostart.lua` | App autostart (Thunderbird on workspace 10) |
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

### Wi-Fi: 5 GHz, power saving, and bufferbloat

The AP (`TP-Link_9271`) advertises the **same SSID on 2.4 GHz and 5 GHz**. With
no band preference, NetworkManager picks on signal strength, and the 2.4 GHz
radio is stronger, so a Wi-Fi 6E card silently lands on the slower band.

`wifi-tune` pins a connection to 5 GHz and disables power saving:

```sh
wifi-tune                  # the connection currently in use
wifi-tune TP-Link_9271     # or by name
nmcli connection up TP-Link_9271   # to apply
```

These settings live in the NetworkManager profile under
`/etc/NetworkManager/system-connections/`, which is **not tracked here**: it is
root-owned and embeds the network PSK. Re-apply with `wifi-tune` on a new
machine.

Measured, `iw dev wlp8s0 link` and `ping 192.168.1.1`:

| Setting | Link rate | Gateway ping (min) |
|---|---|---|
| 2.4 GHz, power save on | 259 Mbit/s @ 2422 MHz | 19.0 ms |
| 5 GHz, power save off | 648 Mbit/s @ 5745 MHz | 3.6 ms |

**Bufferbloat is a separate, larger problem and is only half-fixed here.** A
Steam download saturates the link at ~430 Mbit/s and drives gateway latency
from ~7 ms to ~140 ms — for *all* devices on the network, and for the router's
own LAN hop, which should be single-digit milliseconds.

Measured on this machine, ping to the gateway:

| Condition | avg |
|---|---|
| idle | 6.8 ms |
| loaded, no qdisc | 148.5 ms |
| loaded, with fq_codel | 138.8 ms |

So this machine's qdisc is not the bottleneck — the queue that fills is in the
router, on the downstream path. **Enable SQM (fq_codel or CAKE) on the router**;
that is what actually restores low latency under load.

What is applied locally is `fq_codel` on the Wi-Fi interface, installed by
`run_onchange_after_install-fq-codel-dispatcher.sh` as a NetworkManager
dispatcher script (`/etc/NetworkManager/dispatcher.d/90-fq_codel`). A
dispatcher is used because a bare `tc` command is lost on every interface reset
and reboot.

### GeForce NOW

Installed as NVIDIA's official Flatpak, from NVIDIA's own signed remote — not
from the AUR, so it is the same build NVIDIA ships:

```sh
sudo flatpak remote-add --if-not-exists GeForceNOW \
    https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo
sudo flatpak install GeForceNOW com.nvidia.geforcenow
```

Launch with `flatpak run com.nvidia.geforcenow`. NVIDIA's `.bin` installer does
the same thing, but checks for a Debian base first, so the Flatpak is used
directly here.

**The Linux client is still labelled beta.** Prerequisites verified on this
machine:

| Requirement | Status |
|---|---|
| AMD/Intel GPU → Wayland session | Hyprland, `XDG_SESSION_TYPE=wayland` |
| Mesa ≥ 24.2.8 | 26.2.4 |
| Vulkan H.264/H.265 decode | both extensions present (RADV) |
| Disk space | ample |

**Hardware caveat: this box has no discrete GPU.** The renderer is the Ryzen
7800X3D's integrated Radeon 610M, which is fine for *decoding* a stream but
leaves no headroom. GeForce NOW's system requirements are all about decode
support, not rendering power — the game runs in NVIDIA's datacenter. Expect
1080p to be comfortable; the 4K/240 FPS tiers also need a Premium membership.

**Networking caveat.** Streaming requires 25 Mbps sustained for 1080p60 and
under 80 ms of latency to an NVIDIA datacenter. See the Wi-Fi section above:
bufferbloat on the router pushes latency to ~140 ms under load, which will
degrade a stream. A wired connection is what NVIDIA recommends.

### Google Drive

Mounted with rclone at `~/GoogleDrive` by the `gdrive.service` user unit
(`~/.config/systemd/user/gdrive.service`). The OAuth token lives in
`~/.config/rclone/rclone.conf`, which is **deliberately git-ignored** — it is a
refresh token for the whole Drive.

**Google-native files read as 0 bytes through the mount.** Docs, Sheets and
Slides have no stored bytes; Drive serves them only via export. The mount lists
them with a sensible name (`.docx`, `.xlsx`) but an empty body, so `cp` or a
GUI file manager will copy nothing. Uploaded binary files (PDFs, images, zips)
work normally.

Use the helper for anything Google-native:

```sh
gdrive-export "Employment Reference Letter.docx" ~/Documents
```

It runs `rclone copy`, which performs the export properly. To find which files
are affected: `find ~/GoogleDrive -type f -size 0`.

### Mail on workspace 10

Thunderbird autostarts at login into workspace 10, an ordinary workspace reached
with `SUPER+0` exactly like `SUPER+1..9`. It is not floated or pinned, so it
tiles normally and mail is always loaded when you switch to it.

The window rule carries `no_initial_focus = true` and `suppress_event =
"activate"`. Both are required: Thunderbird asks for activation as it starts, so
without them the session opens on workspace 10 instead of workspace 1. The
`activate` suppression does not prevent focusing the window later — switching to
workspace 10 still focuses mail normally.

An earlier design put mail on a special/scratchpad workspace. That was replaced:
`toggle_special` only *overlays* the current workspace rather than switching to
it, which is a different experience from every other workspace keybinding.

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
