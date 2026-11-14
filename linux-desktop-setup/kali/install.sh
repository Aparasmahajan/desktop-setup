#!/usr/bin/env bash
# Kali Linux (XFCE) – the full setup:
#   touchpad (tap, natural scrolling), 3-finger app switcher with previews, 4-finger swipes and tap,
#   three layouts (Kali default, Ops, Floating) with the grid button, auto-hiding dock and top bar.
#   ./install.sh [ops|floating|default]     (default: ops)
set -euo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/shared/lib.sh"
need_user
LAYOUT="${1:-ops}"
case "$LAYOUT" in default|ops|floating) ;; *) echo "usage: $0 [ops|floating|default]"; exit 1 ;; esac
[ "$(desktop)" = xfce ] || warn "Kali's setup is made for XFCE (you have: ${XDG_CURRENT_DESKTOP:-unknown})."
install_for_this_desktop "$LAYOUT" "Kali default"
say "Done!"
cat <<MSG

  Gestures and layouts work now. Log out and back in once so tap-to-click and natural scrolling turn on.
  Switch layouts / top-bar auto-hide: the grid icon on the top bar (left of the lock)
  From a terminal: layout-toggle ops | floating | default    topbar-toggle auto | hide | show
  Remove everything: $(cd "$(dirname "$0")" && pwd)/uninstall.sh
MSG
