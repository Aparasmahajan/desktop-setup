#!/usr/bin/env bash
# Undo everything install.sh did and put Kali's own panel back.
set -uo pipefail
L="$HOME/.local/share/layouts"
BIN="$HOME/.local/bin"
say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
[ "$(id -u)" -ne 0 ] || { echo "Run this as your normal user, not with sudo."; exit 1; }

say "Putting Kali's own panel back"
sed -i '/layout-toggle/d' "$HOME/.config/gtk-3.0/gtk.css" 2>/dev/null
for f in "$L/kali-original.tar.bz2" "$L/kali-default.tar.bz2"; do
  [ -f "$f" ] && { xfce4-panel-profiles load "$f"; break; }
done
xfconf-query -c xfwm4 -p /general/workspace_names -t string -s 1 -t string -s 2 -t string -s 3 -t string -s 4 \
  -t string -s 5 -t string -s 6 -t string -s 7 -t string -s 8 -t string -s 9 -t string -s 0
xfconf-query -c xfwm4 -p /general/margin_top -n -t int -s 0
xfconf-query -c xfwm4 -p /general/show_dock_shadow -s true
xfconf-query -c xfce4-desktop -p /desktop-icons/style -s 2
for k in show-home show-trash show-filesystem show-removable; do
  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/$k -s true
done

say "Removing gestures and touchpad settings (asks for your password)"
pkill -x -u "$USER" touchegg 2>/dev/null
pkill -u "$USER" -f '[s]wipe-switcher$' 2>/dev/null
sudo systemctl disable --now touchegg 2>/dev/null
sudo systemctl disable --now tap4-playpause 2>/dev/null
sudo rm -f /etc/systemd/system/tap4-playpause.service /usr/local/bin/tap4-playpause
sudo systemctl daemon-reload
sudo apt-get remove -y touchegg xfce4-docklike-plugin
sudo rm -f /etc/X11/xorg.conf.d/30-touchpad.conf /usr/local/bin/layout-toggle /usr/local/bin/topbar-toggle

say "Removing scripts and settings"
rm -f "$HOME/.config/autostart/swipe-switcher.desktop" "$BIN/swipe-switcher" "$BIN/maximize-all" "$BIN/switch-app" "$BIN/layout-toggle" "$BIN/topbar-toggle" "$HOME/.local/share/applications/layout-toggle.desktop"
if [ -f "$HOME/.config/touchegg/touchegg.conf.bak" ]; then
  mv "$HOME/.config/touchegg/touchegg.conf.bak" "$HOME/.config/touchegg/touchegg.conf"
else
  rm -rf "$HOME/.config/touchegg"
fi
rm -rf "$L"

say "Done. Log out and back in to finish (touchpad goes back to Kali's defaults)."
