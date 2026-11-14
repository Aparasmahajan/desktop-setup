#!/usr/bin/env bash
# Undo everything this setup installed and put the original settings back.
set -uo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/shared/lib.sh"
need_user
uninstall_everything
