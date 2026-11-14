#!/usr/bin/env bash
# Kali Linux (XFCE) desktop setup – one command:
#   ./install.sh                 install everything, start on the Ops layout
#   ./install.sh floating        ... start on the Floating layout
#   ./install.sh default         ... keep Kali's own layout (switch later with the grid button)
#
# What it sets up:
#   - touchpad: tap to click, tap-and-drag, natural scrolling (every touchpad)
#   - gestures: 3 fingers ←/→ app switcher with previews (↑/↓ while open = rows), ↓ show desktop, ↑ maximize all
#                          4 fingers ←/→ workspaces, ↑/↓ volume
#   - three desktop layouts (Kali default, Ops, Floating) + a grid button on the top bar to switch
#   - auto-hiding dock at the bottom, top bar that hides behind maximized windows
#   - 4-finger tap = play / pause music or video
#   - battery percentage, 4 workspaces
# Run it as your normal user (not root). It asks for your password once, for the system parts.
set -euo pipefail

LAYOUT="${1:-ops}"
case "$LAYOUT" in default|ops|floating) ;; *) echo "usage: $0 [ops|floating|default]"; exit 1 ;; esac

DIR="$(cd "$(dirname "$0")" && pwd)"
F="$DIR/files"
L="$HOME/.local/share/layouts"
BIN="$HOME/.local/bin"

say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

[ "$(id -u)" -ne 0 ] || { echo "Run this as your normal user, not with sudo."; exit 1; }
[ "${XDG_CURRENT_DESKTOP:-}" = XFCE ] || warn "This is made for the XFCE desktop (you have: ${XDG_CURRENT_DESKTOP:-unknown})."
[ "${XDG_SESSION_TYPE:-}" = x11 ] || warn "Gestures and panels are made for an X11 session (you have: ${XDG_SESSION_TYPE:-unknown})."
command -v xfconf-query >/dev/null || { echo "xfconf-query not found – is this Kali with XFCE?"; exit 1; }

# ---------------------------------------------------------------- system parts (sudo)
say "Installing packages (asks for your password)"
sudo apt-get update
sudo apt-get install -y wmctrl xdotool python3 x11-utils playerctl xfce4-panel-profiles \
     xfce4-docklike-plugin xfce4-netload-plugin "$F/touchegg_2.0.18_amd64.deb"

say "Touchpad: tap to click + natural scrolling"
sudo install -D -m 644 "$F/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf

say "Starting the gesture service"
sudo systemctl enable --now touchegg

say "4-finger tap = play / pause"
sudo install -m 755 "$F/bin/tap4-playpause" /usr/local/bin/tap4-playpause
sed "s/@USER@/$USER/" "$F/tap4-playpause.service" | sudo tee /etc/systemd/system/tap4-playpause.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now tap4-playpause

# ---------------------------------------------------------------- your files
say "Installing scripts and settings"
install -d "$BIN" "$HOME/.config/touchegg" "$HOME/.local/share/applications"
install -m 755 "$F/bin/maximize-all" "$F/bin/switch-app" "$F/bin/swipe-switcher" "$F/bin/layout-toggle" "$F/bin/topbar-toggle" "$BIN/"
# so the panel button finds them right away, even before you log out and in once
sudo ln -sf "$BIN/layout-toggle" /usr/local/bin/layout-toggle
sudo ln -sf "$BIN/topbar-toggle" /usr/local/bin/topbar-toggle
[ -f "$HOME/.config/touchegg/touchegg.conf" ] && cp "$HOME/.config/touchegg/touchegg.conf" "$HOME/.config/touchegg/touchegg.conf.bak"
install -m 644 "$F/touchegg.conf" "$HOME/.config/touchegg/touchegg.conf"

install -d "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/swipe-switcher.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Swipe app switcher
Comment=3-finger left/right swipe opens the app switcher with previews
Exec=python3 $BIN/swipe-switcher
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

cat > "$HOME/.local/share/applications/layout-toggle.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Switch desktop layout
Comment=Go to the next desktop layout (Kali default, Ops, Floating)
Exec=$BIN/layout-toggle
Icon=view-grid-symbolic
Terminal=false
Categories=Settings;
EOF

say "Installing desktop layouts"
if [ -d "$L" ] && [ ! -f "$L/.from-installer" ]; then
  mv "$L" "$L.bak-$(date +%Y%m%d-%H%M%S)"; warn "Your old layouts folder was kept as $L.bak-*"
fi
install -d "$L"; touch "$L/.from-installer"
install -m 644 "$F/layouts/ops.tar.bz2" "$F/layouts/floating.tar.bz2" \
               "$F/layouts/ops-panel.css" "$F/layouts/floating-panel.css" "$L/"

# Kali's own layout = whatever the panel looks like right now (saved only the first time)
[ -f "$L/kali-default.tar.bz2" ] || xfce4-panel-profiles save "$L/kali-default.tar.bz2"
[ -f "$L/kali-original.tar.bz2" ] || cp "$L/kali-default.tar.bz2" "$L/kali-original.tar.bz2"   # untouched copy for uninstall.sh

IFACE="$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"
python3 - "$L" "${IFACE:-wlan0}" <<'PY'
"""Give the saved Kali layout the grid button + auto-hide, and point Ops' network meter at this laptop's interface."""
import io, re, sys, tarfile
L, iface = sys.argv[1], sys.argv[2]

def read(p):
    with tarfile.open(p, "r:bz2") as t:
        return {m.name: t.extractfile(m).read() for m in t.getmembers() if m.isfile()}

def write(p, files):
    with tarfile.open(p, "w:bz2") as t:
        for n, d in files.items():
            ti = tarfile.TarInfo(n); ti.size = len(d); ti.mode = 0o644
            t.addfile(ti, io.BytesIO(d))

ops = read(f"{L}/ops.tar.bz2")
ops = {n: (re.sub(rb"(?m)^Network_Device=.*$", b"Network_Device=" + iface.encode(), d) if n.startswith("netload-") else d)
       for n, d in ops.items()}
write(f"{L}/ops.tar.bz2", ops)

menu_files = {n: d for n, d in ops.items() if n.startswith("launcher-34/")}
menu_cfg = [l for l in ops["config.txt"].decode().splitlines() if l.startswith("/plugins/plugin-34")]

d = read(f"{L}/kali-default.tar.bz2")
cfg = d["config.txt"].decode().splitlines()
if any("layout-default.desktop" in l for l in cfg):
    sys.exit(0)  # already has the button
used = {int(m) for l in cfg for m in re.findall(r"^/plugins/plugin-(\d+)", l)}
new_id = 34 if 34 not in used else max(used) + 1
actions = [int(m.group(1)) for l in cfg if (m := re.match(r"^/plugins/plugin-(\d+) 'actions'$", l))]

out = []
for l in cfg:
    if l.startswith("/panels/panel-1/autohide-behavior"):
        continue
    if l.startswith("/panels/panel-1/plugin-ids "):
        ids = [int(x) for x in re.findall(r"<(\d+)>", l)]
        pos = ids.index(actions[0]) if actions and actions[0] in ids else len(ids)
        ids.insert(pos, new_id)
        l = "/panels/panel-1/plugin-ids [" + ", ".join(f"<{i}>" for i in ids) + "]"
    out.append(l)
out.append("/panels/panel-1/autohide-behavior uint32 1")
out += [l.replace("/plugins/plugin-34", f"/plugins/plugin-{new_id}", 1) for l in menu_cfg]
d["config.txt"] = ("\n".join(out) + "\n").encode()
for n, data in menu_files.items():
    d[n.replace("launcher-34/", f"launcher-{new_id}/", 1)] = data
write(f"{L}/kali-default.tar.bz2", d)
PY

say "Battery percentage and 4 workspaces"
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/show-panel-label -n -t int -s 1
xfconf-query -c xfwm4 -p /general/workspace_count -s 4

say "Switching to the $LAYOUT layout"
echo default > "$L/current"
xfce4-panel-profiles load "$L/kali-default.tar.bz2"   # Kali layout with the grid button
sleep 2
if [ "$LAYOUT" = default ]; then "$BIN/topbar-toggle" apply; else "$BIN/layout-toggle" "$LAYOUT"; fi

say "Starting gestures"
pkill -x -u "$USER" touchegg 2>/dev/null || true
pkill -u "$USER" -f '[s]wipe-switcher$' 2>/dev/null || true
nohup touchegg >/dev/null 2>&1 &
nohup python3 "$BIN/swipe-switcher" >/dev/null 2>&1 &

XI=$(python3 - <<'PY' 2>/dev/null
import ctypes, ctypes.util
X = ctypes.CDLL(ctypes.util.find_library("X11")); Xi = ctypes.CDLL(ctypes.util.find_library("Xi"))
X.XOpenDisplay.restype = ctypes.c_void_p
d = X.XOpenDisplay(None); a, b = ctypes.c_int(2), ctypes.c_int(4)
Xi.XIQueryVersion.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
Xi.XIQueryVersion(d, ctypes.byref(a), ctypes.byref(b)); print(f"{a.value}.{b.value}")
PY
)
case "$XI" in 2.4|2.[5-9]|[3-9].*) ;; *)
  warn "Your X server reports XInput ${XI:-unknown}; the 3-finger switcher needs 2.4 (Kali 2022+). 3-finger swipes won't work here." ;;
esac

say "Done!"
cat <<EOF

  Gestures and layouts work now.
  Tap-to-click and natural scrolling start after you log out and back in once.

  Switch layouts / auto-hide:  the grid icon on the top bar (left of the lock)
  From a terminal:             layout-toggle ops | floating | default
                               topbar-toggle auto | hide | show
  Remove everything:           $DIR/uninstall.sh
EOF
