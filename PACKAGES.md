# Host-specific packages are installed manually; chezmoi never installs
# packages. This list is the reference for the Arch desktop.
#
# --- Desktop stack (Wayland/Hyprland) -------------------------------------
# hyprland, hyprpaper, hypridle, hyprlock, hyprpolkitagent,
# xdg-desktop-portal-hyprland, waybar, fuzzel, dunst, wl-clipboard,
# wl-clip-persist, cliphist, grim, slurp, satty, yazi
#
# --- Shell -----------------------------------------------------------------
# zsh, zsh-completions
#
# --- Fonts -----------------------------------------------------------------
# ttf-hack-nerd            (terminal + waybar glyphs)
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

# --- Coding agent ----------------------------------------------------------
# oh-my-pi-bin            (AUR: PREBUILT release binary)
#       Use the -bin package, never the source `oh-my-pi`: the source package
#       pulls bun, cargo, cmake, rust and clang and recompiles on every upgrade,
#       and omp ships roughly daily. -bin has no build() step at all and takes
#       seconds. Both install /usr/bin/omp and conflict with each other.
