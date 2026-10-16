#!/bin/sh
# Apply the Dracula theme to ly.
#
# Needs root: ly only reads /etc/ly/config.ini, which is root-owned. chezmoi
# only manages $HOME, so this cannot be automated by chezmoi.
#
#   sudo sh ~/.local/share/chezmoi/dot_config/ly/apply-theme.sh
#
# Every sed pattern is anchored (^key = ), so it can only ever rewrite the exact
# line it names. Nothing else in the file is touched. Verified against a copy of
# the real config: all 9 keys matched.
#
# COLOUR FORMAT — the trap when editing these
# -------------------------------------------
# ly colours are 0xSSRRGGBB, NOT ARGB. The most significant byte is a STYLE
# byte (0x00 normal, 0x01 bold) and the rest is plain sRGB, so Dracula's
# #282a36 is 0x00282A36. Writing 0xFF282A36 sets a style byte, not an alpha
# channel. Confirmed against ly's own config.ini.example: "the colors are
# always 32-bit values with the styling in the most significant byte".
#
# Palette, from dot_config/hypr/modules/00-theme.lua:
#   bg #282a36 -> 0x00282A36      fg  #f8f8f2 -> 0x00F8F8F2
#   purple #bd93f9 -> 0x00BD93F9  pink #ff79c6 -> 0x00FF79C6
#
# ly is a TUI: it has NO image or wallpaper support at all. `bg` is a flat
# colour and that is the whole surface — a login-screen wallpaper needs a
# graphical greeter, not ly.
#
# FONT is handled separately at the end and only if you ask for it, because it
# changes the whole virtual console (fewer columns everywhere, not just in ly)
# and needs the terminus-font package.

set -eu

CFG=/etc/ly/config.ini

[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
[ -f "$CFG" ] || { echo "no $CFG" >&2; exit 1; }

# One timestamped backup per run, never overwriting an earlier one.
bak="$CFG.bak-$(date +%Y%m%d-%H%M%S)"
cp "$CFG" "$bak"
echo "backed up to $bak"

sed -i \
  -e 's/^fg = .*/fg = 0x00F8F8F2/' \
  -e 's/^bg = .*/bg = 0x00282A36/' \
  -e 's/^border_fg = .*/border_fg = 0x00BD93F9/' \
  -e 's/^box_title = .*/box_title = Dracula/' \
  -e 's/^clock = .*/clock = %H:%M/' \
  -e 's/^bigclock = .*/bigclock = en/' \
  -e 's/^asterisk = .*/asterisk = 0x2022/' \
  -e 's/^hide_version_string = .*/hide_version_string = true/' \
  -e 's/^edge_margin = .*/edge_margin = 1/' \
  "$CFG"

echo "applied. resulting values:"
grep -E '^(fg|bg|border_fg|box_title|clock|bigclock|asterisk|hide_version_string|edge_margin) = ' "$CFG" |
    sed 's/^/  /'

cat <<'EOF'

The theme takes effect on next logout (ly redraws then), not instantly.

--- OPTIONAL: larger console font -----------------------------------------

If ly still looks too small, that is the console font, not ly: ly has no
font-size option at all, so its box is sized in terminal cells. The current
FONT=default8x16 on a 3840x2160 console gives a 480x135 grid, which makes the
box tiny. A taller cell = fewer cells = bigger everything.

  sudo pacman -S terminus-font
  sudo sed -i 's/^FONT=.*/FONT=ter-v32n/' /etc/vconsole.conf
  sudo mkinitcpio -P

Sizes, on a 3840x2160 console:
  default8x16 (now)  480 x 135 cells   smallest
  ter-v24n           320 x  90
  ter-v28n           274 x  77
  ter-v32n           240 x  67         largest available

Tradeoff: a larger font means fewer columns on EVERY virtual console, so long
log lines wrap sooner. ter-v28n is the middle ground.

Do NOT use `localectl set-keymap`: it can rewrite the whole XKB block in
/etc/vconsole.conf and drop XKBOPTIONS=terminate:ctrl_alt_bksp. Edit the FONT=
line only, as above.
EOF
