#!/usr/bin/env bash
# Undo everything (works for Kali, Ubuntu and Linux Mint).
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/shared/lib.sh"
need_user
uninstall_everything
