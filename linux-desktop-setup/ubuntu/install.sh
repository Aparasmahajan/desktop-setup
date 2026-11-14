#!/usr/bin/env bash
# Ubuntu – picks the right setup for your desktop:
#   Ubuntu (GNOME):  tap to click, natural scrolling, battery %, dock at the bottom that hides when
#                    a window covers it, 4-finger tap = play/pause. (GNOME already has its own
#                    3/4-finger swipes for workspaces and the overview.)
#   Xubuntu (XFCE):  the full setup, same as Kali (layouts, 3-finger switcher, gestures, ...)
#   Ubuntu MATE:     tap to click, natural scrolling, 4-finger swipes, 4-finger tap = play/pause
#   ./install.sh [ops|floating|default]     (layout choice only matters on Xubuntu)
set -euo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/shared/lib.sh"
need_user
LAYOUT="${1:-ops}"
case "$LAYOUT" in default|ops|floating) ;; *) echo "usage: $0 [ops|floating|default]"; exit 1 ;; esac
say "Ubuntu setup for the $(desktop) desktop"
install_for_this_desktop "$LAYOUT" "Default"
say "Done!"
case "$(desktop)" in
  gnome) note "GNOME's own gestures: 3 fingers ←/→ = workspaces, 3 fingers ↑ = overview (Settings → Mouse & Touchpad)." ;;
  xfce)  note "Switch layouts / auto-hide: the grid icon on the top bar. Log out and back in once for the touchpad settings." ;;
esac
note "Remove everything: $(cd "$(dirname "$0")" && pwd)/uninstall.sh"
