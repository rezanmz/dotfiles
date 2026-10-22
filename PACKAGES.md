# Host-specific packages are installed manually; chezmoi never installs
# packages. This list is the reference for the Arch desktop.
#
# --- Desktop stack (Wayland/Hyprland) -------------------------------------
# hyprland, hyprpaper, hypridle, hyprlock, hyprpolkitagent,
# xdg-desktop-portal-hyprland, quickshell, wl-clipboard,
# wl-clip-persist, cliphist, grim, slurp, satty, yazi,
# udisks2, udiskie, libayatana-appindicator (udiskie tray icon)
# Replaced by quickshell (bar, notifications, launcher) and removed: waybar,
# dunst, anyrun (AUR). Their units are still masked, so a stray reinstall cannot
# bring them back on login.
#
# --- Shell -----------------------------------------------------------------
# zsh, zsh-completions
#
# --- Fonts -----------------------------------------------------------------
# ttf-hack-nerd            (terminal + quickshell glyphs)
# noto-fonts, noto-fonts-emoji, noto-fonts-cjk
# vazirmatn-fonts          (AUR: Persian)
#
# --- Themes ----------------------------------------------------------------
# dracula-gtk-theme (AUR), papirus-icon-theme
#
# --- xdg dirs / audio / bluetooth -----------------------------------------
# xdg-user-dirs, pipewire, wireplumber, pavucontrol, bluez, bluez-utils, bluetui
#
# Not package-managed: ~/.local/share/wallpapers/current.png (wallpaper) and
# ~/.ssh/allowed_signers (commit signing). See README.md.

# --- Cloud gaming ----------------------------------------------------------
# flatpak                  (hosts NVIDIA's official GeForce NOW build)
# vulkan-tools             (verifies VK_KHR_video_decode_h264/h265 for GFN)
# iw                       (Wi-Fi link diagnostics: band, rate, power save)

# --- Stress testing --------------------------------------------------------
# These are NOT installed system-wide on this machine. `stresspc` runs them
# from ~/.local/share/stress-tools, which holds extracted Arch packages plus
# the private shared libraries each one needs, because the machine has no
# passwordless sudo. Install them system-wide instead if you would rather
# have plain `stress-ng`, `fio`, `memtest_vulkan`, `glmark2` and `occt` on PATH:
# stress-ng, s-tui, fio, glmark2, memtest_vulkan, vkmark, occt
# python-psutil, python-urwid, python-wcwidth   (for s-tui)
# Note: OCCT 17 is GUI-only in Arch — the `occt` launcher ignores --mode and
# --test, and the console binaries under Resources/ exit 101 with no output.

# --- Coding agent ----------------------------------------------------------
# oh-my-pi-bin            (AUR: PREBUILT release binary)
#       Use the -bin package, never the source `oh-my-pi`: the source package
#       pulls bun, cargo, cmake, rust and clang and recompiles on every upgrade,
#       and omp ships roughly daily. -bin has no build() step at all and takes
#       seconds. Both install /usr/bin/omp and conflict with each other.

# --- Kernels ---------------------------------------------------------------
# linux          (mainline — the default; boots first in GRUB)
# linux-lts      (fallback; picked from the GRUB menu)
#   Both installed as UKIs in /boot/EFI/Linux/. See README.md for the GRUB
#   + UKI layout, which ignores /etc/grub.d/10_linux on purpose.
# amd-ucode      (microcode, embedded into each UKI)

# --- Notes ----------------------------------------------------------------
# obsidian                 (vault at ~/Vault, synced by Syncthing)
# syncthing                (2.1.6, matches the cluster container version)
#   Syncthing runs as a user service with linger enabled, so it keeps syncing
#   while logged out. The peer is the k3s pod, not the beelink host.
