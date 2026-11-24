# Common steps for the kali/, ubuntu/ and mint/ installers. Source this file; don't run it.
# Every installer runs as the normal user and uses sudo only for system parts.

SHARED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
F="$SHARED/files"
L="$HOME/.local/share/layouts"
BIN="$HOME/.local/bin"
STATE="$HOME/.local/share/linux-desktop-setup"
OS_RELEASE="${OS_RELEASE:-/etc/os-release}"

say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

need_user() { [ "$(id -u)" -ne 0 ] || { echo "Run this as your normal user, not with sudo."; exit 1; }; }

os_id() { ( . "$OS_RELEASE" 2>/dev/null; echo "${ID:-unknown}" ); }
os_like() { ( . "$OS_RELEASE" 2>/dev/null; echo "${ID:-} ${ID_LIKE:-}" ); }

desktop() {   # xfce | gnome | cinnamon | mate | kde | other
  case "${XDG_CURRENT_DESKTOP:-}" in
    *XFCE*|*Xfce*) echo xfce ;;
    *Cinnamon*) echo cinnamon ;;
    *MATE*) echo mate ;;
    *GNOME*|*Unity*) echo gnome ;;
    *KDE*) echo kde ;;
    *) echo other ;;
  esac
}

remember() { mkdir -p "$STATE"; echo "$1" > "$STATE/profile"; }
mark()     { mkdir -p "$STATE"; touch "$STATE/$1"; }
marked()   { [ -f "$STATE/$1" ]; }

# ---------------------------------------------------------------- packages
APT_UPDATED=
apt_available() {   # is this package in the configured repositories?
  local c; c=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')
  [ -n "$c" ] && [ "$c" != "(none)" ]
}
apt_install() {     # install the packages that exist here; warn about the rest
  local want=() p
  [ -n "$APT_UPDATED" ] || { sudo apt-get update; APT_UPDATED=1; }
  for p in "$@"; do
    if [ "${p#/}" != "$p" ] || apt_available "$p"; then want+=("$p"); else warn "Package '$p' isn't available here – skipped."; fi
  done
  [ ${#want[@]} -eq 0 ] || sudo apt-get install -y "${want[@]}"
}

install_touchegg() {
  if dpkg -s touchegg >/dev/null 2>&1; then
    note "Touchégg is already installed."
  elif apt_available touchegg; then
    apt_install touchegg; mark installed-touchegg
  elif [ "$(dpkg --print-architecture)" = amd64 ]; then
    apt_install "$F/touchegg_2.0.18_amd64.deb"; mark installed-touchegg
  else
    warn "Touchégg isn't available for this computer – 4-finger swipes skipped."; return 1
  fi
  sudo systemctl enable --now touchegg
}

install_touchegg_config() {   # 4-finger gestures (workspaces, volume)
  install -d "$HOME/.config/touchegg"
  [ -f "$HOME/.config/touchegg/touchegg.conf" ] && ! marked touchegg-config && \
    cp "$HOME/.config/touchegg/touchegg.conf" "$HOME/.config/touchegg/touchegg.conf.bak"
  install -m 644 "$F/touchegg.conf" "$HOME/.config/touchegg/touchegg.conf"
  mark touchegg-config
  if ! command -v wpctl >/dev/null && command -v pactl >/dev/null; then   # PulseAudio instead of PipeWire
    sed -i 's|wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+|pactl set-sink-volume @DEFAULT_SINK@ +5%|g;
            s|wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-|pactl set-sink-volume @DEFAULT_SINK@ -5%|g' \
        "$HOME/.config/touchegg/touchegg.conf"
    note "Volume gestures set up for PulseAudio."
  fi
  pkill -x -u "$USER" touchegg 2>/dev/null || true
  nohup touchegg >/dev/null 2>&1 &
}

remove_touchegg_stuff() {
  pkill -x -u "$USER" touchegg 2>/dev/null
  if marked touchegg-config; then
    if [ -f "$HOME/.config/touchegg/touchegg.conf.bak" ]; then
      mv "$HOME/.config/touchegg/touchegg.conf.bak" "$HOME/.config/touchegg/touchegg.conf"
    else
      rm -f "$HOME/.config/touchegg/touchegg.conf"
    fi
  fi
  if marked installed-touchegg; then
    sudo systemctl disable --now touchegg 2>/dev/null
    sudo apt-get remove -y touchegg
  fi
}

# ---------------------------------------------------------------- 4-finger tap = play/pause (any desktop)
install_tap4() {
  apt_install python3 playerctl
  sudo install -m 755 "$F/bin/tap4-playpause" /usr/local/bin/tap4-playpause
  sed "s/@USER@/$USER/" "$F/tap4-playpause.service" | sudo tee /etc/systemd/system/tap4-playpause.service >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable --now tap4-playpause
}
remove_tap4() {
  sudo systemctl disable --now tap4-playpause 2>/dev/null
  sudo rm -f /etc/systemd/system/tap4-playpause.service /usr/local/bin/tap4-playpause
  sudo systemctl daemon-reload
}

# ---------------------------------------------------------------- Super+Shift+S snipping tool + Super+V clipboard history
SNIP_CMD="flameshot gui"
CLIP_CMD="copyq menu"
gs_list_add() {   # gs_list_add SCHEMA KEY ITEM – add ITEM to a string-list setting (backed up by gs_set)
  local cur new
  gs_has "$1" "$2" || return 0
  cur=$(gsettings get "$1" "$2")
  new=$(python3 - "$cur" "$3" <<'PY2'
import ast, sys
cur, item = sys.argv[1], sys.argv[2]
items = ast.literal_eval(cur.replace("@as ", "", 1)) if cur.strip() not in ("", "@as []") else []
if item not in items: items.append(item)
print("[" + ", ".join(repr(i) for i in items) + "]")
PY2
)
  gs_set "$1" "$2" "$new"
}
gs_list_drop() {  # gs_list_drop SCHEMA KEY ITEM – take ITEM out of a string-list setting
  local cur new
  gs_has "$1" "$2" || return 0
  cur=$(gsettings get "$1" "$2")
  new=$(python3 - "$cur" "$3" <<'PY2'
import ast, sys
cur, item = sys.argv[1], sys.argv[2]
items = ast.literal_eval(cur.replace("@as ", "", 1)) if cur.strip() not in ("", "@as []") else []
print("[" + ", ".join(repr(i) for i in items if i != item) + "]")
PY2
)
  [ "$new" = "$cur" ] || gs_set "$1" "$2" "$new"
}

flameshot_settings() {
  install -d "$HOME/.config/flameshot" "$HOME/Pictures/Screenshots"
  python3 - "$HOME/.config/flameshot/flameshot.ini" <<'PY2'
import configparser, os, sys
p = sys.argv[1]
c = configparser.ConfigParser(); c.optionxform = str
if os.path.exists(p): c.read(p)
if "General" not in c: c["General"] = {}
c["General"].update({"showStartupLaunchMessage": "false", "checkForUpdates": "false",
                     "copyOnDoubleClick": "true", "saveAfterCopy": "false",
                     "savePath": os.path.expanduser("~/Pictures/Screenshots"), "savePathFixed": "false",
                     "disabledTrayIcon": "true", "showHelp": "true"})
with open(p, "w") as f: c.write(f, space_around_delimiters=False)
PY2
}

copyq_settings() {   # Windows-style Win+V: list at the mouse, picking an item pastes it
  pgrep -x -u "$USER" copyq >/dev/null || { nohup copyq >/dev/null 2>&1 & sleep 2; }
  local kv
  for kv in autostart=true tray_item_paste=true activate_pastes=true activate_closes=true activate_focuses=true \
            close_on_unfocus=true tray_items=25 tray_images=true maxitems=300 check_clipboard=true check_selection=false; do
    copyq config "${kv%%=*}" "${kv#*=}" >/dev/null 2>&1 || warn "CopyQ setting ${kv%%=*} not applied"
  done
  if [ "${XDG_SESSION_TYPE:-}" = wayland ]; then   # CopyQ sees the clipboard reliably on Wayland only via XWayland
    sed -i 's|^Exec=copyq|Exec=env QT_QPA_PLATFORM=xcb copyq|' "$HOME/.config/autostart/com.github.hluk.copyq.desktop" 2>/dev/null || true
    CLIP_CMD="env QT_QPA_PLATFORM=xcb copyq menu"
  fi
}

other_clipboard_managers_off() {   # two clipboard managers fight over the clipboard: keep only CopyQ
  local f=/etc/xdg/autostart/xfce4-clipman-plugin-autostart.desktop u="$HOME/.config/autostart/xfce4-clipman-plugin-autostart.desktop"
  if [ -f "$f" ] || [ -f "$u" ]; then
    mkdir -p "$STATE" "$HOME/.config/autostart"
    if [ -f "$u" ]; then cp "$u" "$STATE/clipman-autostart.bak"; else cp "$f" "$u"; mark clipman-override; fi
    if grep -q '^Hidden=' "$u"; then sed -i 's/^Hidden=.*/Hidden=true/' "$u"; else echo "Hidden=true" >> "$u"; fi
  fi
  pkill -x -u "$USER" xfce4-clipman 2>/dev/null || true
}

snip_clip_shortcuts() {   # snip_clip_shortcuts DESKTOP
  local g=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings c=/org/cinnamon/desktop/keybindings/custom-keybindings n
  case "$1" in
    xfce)
      xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>v' -n -t string -s "$CLIP_CMD"
      xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super><Shift>s' -n -t string -s "$SNIP_CMD"
      mark xfce-shortcuts ;;
    gnome)   # GNOME opens its notification list with Super+V (and Super+M) – leave it on Super+M
      gs_list_drop org.gnome.shell.keybindings toggle-message-tray '<Super>v'
      for n in snip clip; do
        local schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$g/lds-$n/"
        if [ $n = snip ]; then gs_set "$schema" name "'Snipping tool'"; gs_set "$schema" command "'$SNIP_CMD'"; gs_set "$schema" binding "'<Super><Shift>s'"
        else gs_set "$schema" name "'Clipboard history'"; gs_set "$schema" command "'$CLIP_CMD'"; gs_set "$schema" binding "'<Super>v'"; fi
        gs_list_add org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$g/lds-$n/"
      done ;;
    cinnamon)
      for n in snip clip; do
        local schema="org.cinnamon.desktop.keybindings.custom-keybinding:$c/lds-$n/"
        if [ $n = snip ]; then gs_set "$schema" name "'Snipping tool'"; gs_set "$schema" command "'$SNIP_CMD'"; gs_set "$schema" binding "['<Super><Shift>s']"
        else gs_set "$schema" name "'Clipboard history'"; gs_set "$schema" command "'$CLIP_CMD'"; gs_set "$schema" binding "['<Super>v']"; fi
        gs_list_add org.cinnamon.desktop.keybindings custom-list "lds-$n"
      done ;;
    mate)    # Marco's numbered command slots: use the first two free ones
      local used=0 i
      for i in $(seq 1 12); do
        [ "$used" -ge 2 ] && break
        gs_has org.mate.Marco.keybinding-commands "command-$i" || continue
        [ "$(gsettings get org.mate.Marco.keybinding-commands "command-$i")" = "''" ] || continue
        if [ "$used" = 0 ]; then gs_set org.mate.Marco.keybinding-commands "command-$i" "'$SNIP_CMD'"; gs_set org.mate.Marco.global-keybindings "run-command-$i" "'<Shift><Mod4>s'"
        else gs_set org.mate.Marco.keybinding-commands "command-$i" "'$CLIP_CMD'"; gs_set org.mate.Marco.global-keybindings "run-command-$i" "'<Mod4>v'"; fi
        used=$((used + 1))
      done ;;
    *) note "No shortcuts set on this desktop – start them from the menu: Flameshot, CopyQ." ;;
  esac
}

snip_clip_install() {
  say "Snipping tool (Super+Shift+S) and clipboard history (Super+V)"
  dpkg -s flameshot >/dev/null 2>&1 || mark installed-flameshot
  dpkg -s copyq >/dev/null 2>&1 || mark installed-copyq
  apt_install flameshot copyq
  command -v flameshot >/dev/null && flameshot_settings
  command -v copyq >/dev/null && { other_clipboard_managers_off; copyq_settings; }
  snip_clip_shortcuts "$(desktop)"
}

snip_clip_remove() {
  if marked xfce-shortcuts; then
    xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>v' -r 2>/dev/null
    xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super><Shift>s' -r 2>/dev/null
  fi
  local u="$HOME/.config/autostart/xfce4-clipman-plugin-autostart.desktop"
  if [ -f "$STATE/clipman-autostart.bak" ]; then cp "$STATE/clipman-autostart.bak" "$u"
  elif marked clipman-override; then rm -f "$u"; fi
  if marked installed-copyq; then
    copyq exit >/dev/null 2>&1; rm -f "$HOME/.config/autostart/com.github.hluk.copyq.desktop"; sudo apt-get remove -y copyq
  fi
  marked installed-flameshot && { pkill -x -u "$USER" flameshot 2>/dev/null; sudo apt-get remove -y flameshot; }
}

# ---------------------------------------------------------------- desktop settings (GNOME / Cinnamon / MATE)
gs_has() { gsettings list-keys "$1" 2>/dev/null | grep -qx "$2"; }
gs_set() {   # gs_set SCHEMA KEY VALUE – remembers the old value once, so uninstall can put it back
  local schema=$1 key=$2 value=$3 old
  if ! gs_has "$schema" "$key"; then note "($schema $key not on this system – skipped)"; return 0; fi
  mkdir -p "$STATE"
  if ! grep -q "^$schema $key " "$STATE/gsettings-backup" 2>/dev/null; then
    old=$(gsettings get "$schema" "$key")
    echo "$schema $key $old" >> "$STATE/gsettings-backup"
  fi
  gsettings set "$schema" "$key" "$value"
}
gs_restore() {
  [ -f "$STATE/gsettings-backup" ] || return 0
  while read -r schema key old; do
    gsettings set "$schema" "$key" "$old" 2>/dev/null && note "restored $schema $key"
  done < "$STATE/gsettings-backup"
  rm -f "$STATE/gsettings-backup"
}

touchpad_settings() {   # tap to click + natural scrolling through the desktop's own settings
  case "$1" in
    gnome)    gs_set org.gnome.desktop.peripherals.touchpad tap-to-click true
              gs_set org.gnome.desktop.peripherals.touchpad natural-scroll true ;;
    cinnamon) gs_set org.cinnamon.desktop.peripherals.touchpad tap-to-click true
              gs_set org.cinnamon.desktop.peripherals.touchpad natural-scroll true ;;
    mate)     gs_set org.mate.peripherals-touchpad tap-to-click true
              gs_set org.mate.peripherals-touchpad natural-scroll true ;;
  esac
}

# ---------------------------------------------------------------- the full XFCE setup (Kali, Xubuntu, Mint XFCE)
xi_version() {
  python3 - <<'PY' 2>/dev/null
import ctypes, ctypes.util
X = ctypes.CDLL(ctypes.util.find_library("X11")); Xi = ctypes.CDLL(ctypes.util.find_library("Xi"))
X.XOpenDisplay.restype = ctypes.c_void_p
d = X.XOpenDisplay(None); a, b = ctypes.c_int(2), ctypes.c_int(4)
Xi.XIQueryVersion.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
Xi.XIQueryVersion(d, ctypes.byref(a), ctypes.byref(b)); print(f"{a.value}.{b.value}")
PY
}

xfce_full_install() {   # xfce_full_install LAYOUT DEFAULT_LABEL   (LAYOUT = ops | floating | default)
  local LAYOUT=$1 LABEL=$2
  command -v xfconf-query >/dev/null || { warn "xfconf-query not found – this part needs the XFCE desktop."; return 1; }
  [ "${XDG_SESSION_TYPE:-}" = x11 ] || warn "Made for an X11 session (you have: ${XDG_SESSION_TYPE:-unknown})."

  say "Installing packages (asks for your password)"
  apt_install wmctrl xdotool python3 x11-utils playerctl xfce4-panel-profiles xfce4-docklike-plugin \
              xfce4-netload-plugin xfce4-whiskermenu-plugin xfce4-cpugraph-plugin xfce4-genmon-plugin \
              xfce4-pulseaudio-plugin xfce4-power-manager-plugins xfce4-notifyd
  install_touchegg || true

  say "Touchpad: tap to click + natural scrolling"
  sudo install -D -m 644 "$F/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf

  say "4-finger tap = play / pause"
  install_tap4

  say "Installing scripts and settings"
  install -d "$BIN" "$HOME/.local/share/applications" "$HOME/.config/autostart"
  install -m 755 "$F/bin/maximize-all" "$F/bin/switch-app" "$F/bin/swipe-switcher" "$F/bin/layout-toggle" "$F/bin/topbar-toggle" "$F/bin/topbar-watch" "$BIN/"
  sudo ln -sf "$BIN/layout-toggle" /usr/local/bin/layout-toggle   # the panel button finds them before a re-login
  sudo ln -sf "$BIN/topbar-toggle" /usr/local/bin/topbar-toggle
  install_touchegg_config
  cat > "$HOME/.config/autostart/swipe-switcher.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Swipe app switcher
Comment=3-finger left/right swipe opens the app switcher with previews
Exec=python3 $BIN/swipe-switcher
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  cat > "$HOME/.config/autostart/topbar-watch.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Top bar watcher
Comment=Keeps the top bar hidden while a maximized window is visible
Exec=python3 $BIN/topbar-watch
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  cat > "$HOME/.local/share/applications/layout-toggle.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Switch desktop layout
Comment=Go to the next desktop layout ($LABEL, Ops, Floating)
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
  # the "default" layout = whatever the panel looks like right now (saved only the first time)
  [ -f "$L/kali-default.tar.bz2" ] || xfce4-panel-profiles save "$L/kali-default.tar.bz2"
  [ -f "$L/kali-original.tar.bz2" ] || cp "$L/kali-default.tar.bz2" "$L/kali-original.tar.bz2"

  local IFACE VPN=yes
  IFACE="$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')"
  [ -x "${VPN_SCRIPT:-/usr/share/kali-themes/xfce4-panel-genmon-vpnip.sh}" ] || VPN=no
  python3 - "$L" "${IFACE:-wlan0}" "$VPN" "$LABEL" <<'PY'
"""Fit the layouts to this computer: network card for the speed meter, VPN chip only on Kali,
the right name for the default layout, and give the default layout the grid button + auto-hide."""
import io, re, sys, tarfile
L, iface, vpn, label = sys.argv[1], sys.argv[2], sys.argv[3] == "yes", sys.argv[4]

def read(p):
    with tarfile.open(p, "r:bz2") as t:
        return {m.name: t.extractfile(m).read() for m in t.getmembers() if m.isfile()}

def write(p, files):
    with tarfile.open(p, "w:bz2") as t:
        for n, d in files.items():
            ti = tarfile.TarInfo(n); ti.size = len(d); ti.mode = 0o644
            t.addfile(ti, io.BytesIO(d))

def fit(files):
    out = {}
    for n, d in files.items():
        if n.startswith("netload-"):
            d = re.sub(rb"(?m)^Network_Device=.*$", b"Network_Device=" + iface.encode(), d)
        if n.startswith("launcher-") and n.endswith(".desktop"):
            d = d.replace(b"Name=Kali default layout", b"Name=" + label.encode() + b" layout")
        out[n] = d
    if not vpn:   # Kali's VPN-IP script isn't here: take the chip (plugin 15) off the panels
        cfg = out["config.txt"].decode().splitlines()
        cfg = [re.sub(r"<15>, |, <15>", "", l) if re.match(r"/panels/panel-\d+/plugin-ids ", l) else l for l in cfg]
        out["config.txt"] = ("\n".join(cfg) + "\n").encode()
    return out

for name in ("ops", "floating"):
    write(f"{L}/{name}.tar.bz2", fit(read(f"{L}/{name}.tar.bz2")))

ops = read(f"{L}/ops.tar.bz2")
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
  xfce4-panel-profiles load "$L/kali-default.tar.bz2"   # the default layout, now with the grid button
  sleep 2
  if [ "$LAYOUT" = default ]; then "$BIN/topbar-toggle" apply; else "$BIN/layout-toggle" "$LAYOUT"; fi

  say "Starting the 3-finger switcher and the top bar watcher"
  pkill -u "$USER" -f '[s]wipe-switcher$' 2>/dev/null || true
  pkill -u "$USER" -f 'bin/topbar-watch$' 2>/dev/null || true
  nohup python3 "$BIN/swipe-switcher" >/dev/null 2>&1 &
  nohup python3 "$BIN/topbar-watch" >/dev/null 2>&1 &
  local XI; XI=$(xi_version)
  case "$XI" in 2.4|2.[5-9]|[3-9].*) ;; *)
    warn "Your X server reports XInput ${XI:-unknown}; the 3-finger switcher needs 2.4. 3-finger swipes won't work here." ;;
  esac
  remember xfce
}

xfce_full_uninstall() {
  say "Putting the original panel back"
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
  pkill -u "$USER" -f '[s]wipe-switcher$' 2>/dev/null
  pkill -u "$USER" -f 'bin/topbar-watch$' 2>/dev/null
  sudo rm -f /etc/X11/xorg.conf.d/30-touchpad.conf /usr/local/bin/layout-toggle /usr/local/bin/topbar-toggle
  rm -f "$HOME/.config/autostart/swipe-switcher.desktop" "$HOME/.config/autostart/topbar-watch.desktop" "$BIN/topbar-watch" "$BIN/swipe-switcher" "$BIN/maximize-all" "$BIN/switch-app" \
        "$BIN/layout-toggle" "$BIN/topbar-toggle" "$HOME/.local/share/applications/layout-toggle.desktop"
  rm -rf "$L"
}

# ---------------------------------------------------------------- other desktops
gnome_install() {
  say "Packages"
  apt_install python3 playerctl
  say "Touchpad: tap to click + natural scrolling"
  touchpad_settings gnome
  say "Battery percentage + Windows-style dock (bottom, hides when a window covers it)"
  gs_set org.gnome.desktop.interface show-battery-percentage true
  gs_set org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"
  gs_set org.gnome.shell.extensions.dash-to-dock extend-height false
  gs_set org.gnome.shell.extensions.dash-to-dock dock-fixed false
  gs_set org.gnome.shell.extensions.dash-to-dock intellihide true
  say "4-finger tap = play / pause"
  install_tap4
  remember gnome
}

cinnamon_install() {
  say "Packages"
  apt_install python3 playerctl
  say "Touchpad: tap to click + natural scrolling"
  touchpad_settings cinnamon
  say "4-finger tap = play / pause"
  install_tap4
  remember cinnamon
}

mate_install() {
  say "Packages"
  apt_install python3 playerctl
  say "Touchpad: tap to click + natural scrolling"
  touchpad_settings mate
  say "4-finger swipes (workspaces, volume)"
  install_touchegg && install_touchegg_config
  say "4-finger tap = play / pause"
  install_tap4
  remember mate
}

other_install() {
  warn "Your desktop (${XDG_CURRENT_DESKTOP:-unknown}) isn't one this package customizes."
  note "Installing only the part that works everywhere: 4-finger tap = play / pause."
  install_tap4
  remember other
}

# ---------------------------------------------------------------- one entry point per direction
install_for_this_desktop() {   # install_for_this_desktop LAYOUT DEFAULT_LABEL
  case "$(desktop)" in
    xfce)     xfce_full_install "$1" "$2" ;;
    gnome)    gnome_install ;;
    cinnamon) cinnamon_install ;;
    mate)     mate_install ;;
    *)        other_install ;;
  esac
  snip_clip_install
}

uninstall_everything() {
  local profile; profile=$(cat "$STATE/profile" 2>/dev/null || echo unknown)
  say "Removing the setup ($profile)"
  [ "$profile" = xfce ] && xfce_full_uninstall
  snip_clip_remove
  gs_restore
  remove_touchegg_stuff
  remove_tap4
  rm -rf "$STATE"
  say "Done. Log out and back in to finish."
}
