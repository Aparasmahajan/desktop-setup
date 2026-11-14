#!/usr/bin/env bash
# Linux Mint – picks the right setup for your edition:
#   Cinnamon:  tap to click, natural scrolling, 4-finger tap = play/pause.
#              (Mint already has its own gestures: System Settings → Gestures.)
#   XFCE:      the full setup, same as Kali (layouts, 3-finger switcher, gestures, ...)
#   MATE:      tap to click, natural scrolling, 4-finger swipes, 4-finger tap = play/pause
#   ./install.sh [ops|floating|default]     (layout choice only matters on Mint XFCE)
set -euo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/shared/lib.sh"
need_user
LAYOUT="${1:-ops}"
case "$LAYOUT" in default|ops|floating) ;; *) echo "usage: $0 [ops|floating|default]"; exit 1 ;; esac
say "Linux Mint setup for the $(desktop) edition"
install_for_this_desktop "$LAYOUT" "Default"
say "Done!"
case "$(desktop)" in
  cinnamon) note "Swipe gestures: System Settings → Gestures (built into Mint – workspaces, desktop, volume, …)." ;;
  xfce)     note "Switch layouts / auto-hide: the grid icon on the top bar. Log out and back in once for the touchpad settings." ;;
esac
note "Remove everything: $(cd "$(dirname "$0")" && pwd)/uninstall.sh"
