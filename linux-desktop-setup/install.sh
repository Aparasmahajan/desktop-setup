#!/usr/bin/env bash
# Linux desktop setup – run this one; it picks Kali, Ubuntu or Linux Mint and your desktop.
#   ./install.sh [ops|floating|default]
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/shared/lib.sh"
need_user
id=$(os_id); like=$(os_like)
case "$id" in
  kali)      dist=kali ;;
  ubuntu)    dist=ubuntu ;;
  linuxmint) dist=mint ;;
  *) case " $like " in
       *" ubuntu "*) dist=ubuntu ;;            # Ubuntu-based (Pop!_OS, Zorin, elementary, ...)
       *" debian "*) dist=ubuntu ;;            # other Debian-based: same desktop-based choices
       *) echo "This package is for Kali, Ubuntu and Linux Mint (Debian-based). Found: $id"; exit 1 ;;
     esac
     warn "$id isn't tested – using the Ubuntu installer (it picks by desktop)." ;;
esac
say "Found: $id, desktop: $(desktop) → running $dist/install.sh"
exec "$DIR/$dist/install.sh" "$@"
