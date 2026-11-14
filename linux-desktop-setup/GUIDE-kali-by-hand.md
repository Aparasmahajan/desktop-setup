# Kali Linux (XFCE) – Windows-style touchpad + desktop layouts

Copy-paste guide for setting up a laptop touchpad on Kali Linux with the XFCE desktop so it works like Windows.

| Feature | What it does |
|---|---|
| Tap to click | A light tap = left click (no need to press down) |
| Natural scrolling | Two fingers up → page goes down (like a phone / Windows default) |
| 3 fingers left / right | App switcher with previews (like Windows): slide to pick, up/down for rows, lift to switch; stops at the last app; slide back to the start to stay on your current app |
| 3 fingers down | Show desktop (hide all windows) |
| 3 fingers up | Bring back all windows and maximize them |
| 4 fingers left / right | Go to next / previous desktop (workspace) |
| 4 fingers up / down | Volume up / down (keeps changing as you slide) |

---

## 0. Check you are on XFCE + X11

```bash
echo "$XDG_CURRENT_DESKTOP / $XDG_SESSION_TYPE"
```

It should print `XFCE / x11`. This guide is written for that setup (Kali's default).

---

## 1. Tap to click + natural scrolling (permanent)

**Why not just use Settings → Mouse and Touchpad?**
On many laptops the touchpad shows up as **several devices with the exact same name**
(for example three devices all called `SYNA30BD:00 06CB:CE08`). XFCE saves its setting by
device name and only applies it to the *first* one it finds, which is often not the real
touchpad. So the checkboxes in Settings seem to do nothing.

This file tells the X server to apply the settings to **every touchpad**, whatever its name:

```bash
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf >/dev/null <<'EOF'
Section "InputClass"
    Identifier "Touchpad: natural scrolling + tap to click"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "NaturalScrolling" "true"
    Option "Tapping" "on"
    Option "TappingDrag" "on"
EndSection
EOF
```

Log out and back in (or restart) for it to take effect.

> Want the old scroll direction instead? Change `"true"` to `"false"` on the NaturalScrolling line.

---

## 2. Install the gesture app (Touchégg) and helpers

Touchégg is not in Kali's package list, so install the official `.deb` from its GitHub
releases page: <https://github.com/JoseExposito/touchegg/releases>
(at the time of writing the latest is **2.0.18**).

```bash
cd /tmp
wget https://github.com/JoseExposito/touchegg/releases/download/2.0.18/touchegg_2.0.18_amd64.deb
```

```bash
sudo apt install ./touchegg_2.0.18_amd64.deb wmctrl xdotool
```

```bash
sudo systemctl enable --now touchegg
```

- `touchegg` = the gesture app (a background service + a small program that runs when you log in)
- `wmctrl` + `xdotool` = small tools used by the "maximize all" and app-switch gestures

---

## 3. Helper scripts (3 fingers up, 3 fingers left/right)

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/maximize-all <<'EOF'
#!/bin/sh
# Bring back windows hidden by "show desktop", then maximize every window on the current workspace.
wmctrl -k off
cur=$(wmctrl -d | awk '$2=="*"{print $1}')
active=$(xdotool getactivewindow 2>/dev/null)
for id in $(wmctrl -l | awk -v d="$cur" '$2==d {print $1}'); do
  wmctrl -i -r "$id" -b add,maximized_vert,maximized_horz
  wmctrl -i -a "$id"
done
[ -n "$active" ] && xdotool windowactivate "$active" 2>/dev/null
exit 0
EOF
chmod +x ~/.local/bin/maximize-all
```

**Next / previous app helper (for 3 fingers left/right):**

```bash
cat > ~/.local/bin/switch-app <<'EOF'
#!/bin/sh
# Go to the next / previous window on this workspace – one step per call, in a fixed order
# (the order the windows were opened, like a taskbar). Stops at the first / last app
# instead of wrapping around.
#   switch-app next     (3 fingers right – keeps stepping while you slide)
#   switch-app prev     (3 fingers left)
dir=${1:-next}
desk=$(wmctrl -d | awk '$2=="*" {print $1}')
ids=$(wmctrl -l | awk -v d="$desk" '$2==d {print $1}')
[ -n "$ids" ] || exit 0
n=$(printf '%s\n' "$ids" | wc -l)
act=$(xdotool getactivewindow 2>/dev/null)
act=$([ -n "$act" ] && printf '0x%08x' "$act")
i=$(printf '%s\n' "$ids" | awk -v a="$act" 'tolower($1)==tolower(a) {print NR; exit}')
if [ -z "$i" ]; then t=1
elif [ "$dir" = prev ]; then t=$(( i > 1 ? i - 1 : 1 ))
else t=$(( i < n ? i + 1 : n )); fi
[ "$t" = "$i" ] && exit 0          # already at the end: stay there
wmctrl -i -a "$(printf '%s\n' "$ids" | sed -n "${t}p")"
EOF
chmod +x ~/.local/bin/switch-app
```

---

**3-finger gestures (app switcher with previews, show desktop, maximize all).** Touchégg only
reports one direction per swipe, so this small listener reads 3-finger swipes straight from the
X server (XInput 2.4) and drives XFCE's Alt+Tab switcher – sideways moves through apps,
up/down moves between rows, lifting switches:

```bash
sudo apt install x11-utils wmctrl xdotool
```

```bash
cat > ~/.local/bin/swipe-switcher <<'EOF'
#!/usr/bin/env python3
"""Windows-style 3-finger gestures for XFCE (X11).

Reads 3-finger touchpad swipes straight from the X server (XInput 2.4 gesture events), so it
sees sideways AND up/down movement during one swipe:

  slide left / right   open XFCE's app switcher (with previews) and move through the apps;
                       stops at the first / last app; slide back to where you started to stay
                       on your current app
  then up / down       (switcher open) move the selection up / down a row
  lift the fingers     switch to the selected app

  swipe starts down    show the desktop (again: bring the windows back)
  swipe starts up      bring back and maximize all windows

  swipe-switcher          run (started automatically at login)
  swipe-switcher --log    also log to ~/.cache/swipe-switcher.log
"""
import ctypes
import ctypes.util
import os
import select
import subprocess
import sys
import time

FINGERS = 3
DECIDE = 25.0     # finger travel before deciding sideways vs up/down
STEP_X = 70.0     # sideways travel per app
STEP_Y = 70.0     # up/down travel per row
HOME = 20.0       # slide back to within this of the start = your current app
LOG = os.path.expanduser("~/.cache/swipe-switcher.log") if "--log" in sys.argv else None
MAXIMIZE_ALL = os.path.expanduser("~/.local/bin/maximize-all")

c_int, c_uint, c_ulong, c_double, c_void_p = ctypes.c_int, ctypes.c_uint, ctypes.c_ulong, ctypes.c_double, ctypes.c_void_p
X11 = ctypes.CDLL(ctypes.util.find_library("X11"))
Xi = ctypes.CDLL(ctypes.util.find_library("Xi"))

XI_GestureSwipeBegin, XI_GestureSwipeUpdate, XI_GestureSwipeEnd = 30, 31, 32
GenericEvent, XIAllMasterDevices, XIGrabModeAsync, XIAnyModifier = 35, 1, 1, -(1 << 31)


class XIEventMask(ctypes.Structure):
    _fields_ = [("deviceid", c_int), ("mask_len", c_int), ("mask", ctypes.POINTER(ctypes.c_ubyte))]


class XIGrabModifiers(ctypes.Structure):
    _fields_ = [("modifiers", c_int), ("status", c_int)]


class XGenericEventCookie(ctypes.Structure):
    _fields_ = [("type", c_int), ("serial", c_ulong), ("send_event", c_int), ("display", c_void_p),
                ("extension", c_int), ("evtype", c_int), ("cookie", c_uint), ("data", c_void_p)]


class XEvent(ctypes.Union):
    _fields_ = [("type", c_int), ("xcookie", XGenericEventCookie), ("pad", ctypes.c_long * 24)]


class XIState(ctypes.Structure):
    _fields_ = [("base", c_int), ("latched", c_int), ("locked", c_int), ("effective", c_int)]


class XIGestureSwipeEvent(ctypes.Structure):
    _fields_ = [("type", c_int), ("serial", c_ulong), ("send_event", c_int), ("display", c_void_p),
                ("extension", c_int), ("evtype", c_int), ("time", c_ulong), ("deviceid", c_int),
                ("sourceid", c_int), ("detail", c_int), ("root", c_ulong), ("event", c_ulong),
                ("child", c_ulong), ("root_x", c_double), ("root_y", c_double), ("event_x", c_double),
                ("event_y", c_double), ("delta_x", c_double), ("delta_y", c_double),
                ("delta_unaccel_x", c_double), ("delta_unaccel_y", c_double),
                ("mods", XIState), ("group", XIState), ("flags", c_int)]


X11.XOpenDisplay.restype = c_void_p
X11.XOpenDisplay.argtypes = [ctypes.c_char_p]
X11.XDefaultRootWindow.restype = c_ulong
X11.XDefaultRootWindow.argtypes = [c_void_p]
X11.XQueryExtension.argtypes = [c_void_p, ctypes.c_char_p, ctypes.POINTER(c_int), ctypes.POINTER(c_int), ctypes.POINTER(c_int)]
X11.XConnectionNumber.argtypes = [c_void_p]
X11.XPending.argtypes = [c_void_p]
X11.XNextEvent.argtypes = [c_void_p, ctypes.POINTER(XEvent)]
X11.XGetEventData.argtypes = [c_void_p, ctypes.POINTER(XGenericEventCookie)]
X11.XFreeEventData.argtypes = [c_void_p, ctypes.POINTER(XGenericEventCookie)]
X11.XFlush.argtypes = [c_void_p]
Xi.XIQueryVersion.argtypes = [c_void_p, ctypes.POINTER(c_int), ctypes.POINTER(c_int)]
Xi.XIGrabSwipeGestureBegin.argtypes = [c_void_p, c_int, c_ulong, c_int, c_int, c_int,
                                       ctypes.POINTER(XIEventMask), c_int, ctypes.POINTER(XIGrabModifiers)]


def log(*parts):
    if LOG:
        with open(LOG, "a") as f:
            f.write(time.strftime("%H:%M:%S ") + " ".join(map(str, parts)) + "\n")


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def xdo(*args):
    subprocess.run(["xdotool", *args], check=False)


def windows_on_this_workspace():
    """How many apps XFCE's switcher lists: windows on this workspace or pinned to all workspaces
    (minimized too), minus panels/desktop/'skip taskbar' windows. (A see-through window still
    takes a slot in the switcher, just with an empty preview.)"""
    try:
        cur = next(l.split()[0] for l in run("wmctrl", "-d").splitlines() if l.split()[1] == "*")
        count = 0
        for l in run("wmctrl", "-l").splitlines():
            wid, desk = l.split()[:2]
            if desk not in (cur, "-1"):
                continue
            props = run("xprop", "-id", wid, "_NET_WM_WINDOW_TYPE", "_NET_WM_STATE")
            if "SKIP_TASKBAR" in props or "_TYPE_DOCK" in props or "_TYPE_DESKTOP" in props:
                continue
            count += 1
        return max(count, 1)
    except Exception:
        return 2


def switcher_columns(n):
    """Apps per row in XFCE's switcher, worked out from the switcher window's shape."""
    time.sleep(0.03)
    for wid in run("xdotool", "search", "--onlyvisible", "--classname", "^xfwm4$").split():
        geo = run("xdotool", "getwindowgeometry", wid)
        try:
            w, h = map(int, geo.split("Geometry:")[1].split()[0].split("x"))
        except (IndexError, ValueError):
            continue
        if w < 100 or h < 100:
            continue
        best = min(range(1, n + 1), key=lambda c: abs(c / (-(-n // c) * 1.12) - w / h))
        return best
    return n


def toggle_show_desktop():
    showing = "= 1" in run("xprop", "-root", "_NET_SHOWING_DESKTOP")
    subprocess.run(["wmctrl", "-k", "off" if showing else "on"], check=False)


class Gesture:
    def __init__(self):
        self.reset()

    def reset(self):
        self.ax = self.ay = 0.0
        self.mode = None          # None (undecided), "switch", "done"
        self.seen = time.monotonic()

    # ---------------------------------------------------------------- switcher
    def open_switcher(self, right):
        xdo("keydown", "Alt_L")
        xdo("key", "Tab")         # show the switcher right away, on the previous app (index 1)
        self.index = 1
        self.n = windows_on_this_workspace()      # then count the apps while it's on screen
        if self.n < 2:
            xdo("key", "Escape", "keyup", "Alt_L")
            self.mode = "done"
            return
        self.right = right        # right: previous app first; left: oldest app first
        self.cols = switcher_columns(self.n)
        self.mode = "switch"
        log("switcher open: apps", self.n, "per row", self.cols, "right" if right else "left")

    def move_to(self, target):
        target = max(0, min(self.n - 1, target))      # never past the first / last app
        diff = target - self.index
        if diff:
            xdo("key", "--delay", "0", *(["Tab"] * diff if diff > 0 else ["shift+Tab"] * -diff))
            self.index = target
            log("move to", target, "of", self.n)

    def target(self):
        along = self.ax if self.right else -self.ax
        if along < HOME:
            col = 0                                   # back where you started: current app
        else:
            steps = int((along - HOME) // STEP_X)
            col = 1 + steps if self.right else max(1, self.n - 1 - steps)
            col = max(1, min(self.n - 1, col))
        rows = int(self.ay / STEP_Y) if self.ay >= 0 else -int(-self.ay / STEP_Y)
        last_row = (self.n - 1) // self.cols
        row = max(0, min(last_row, col // self.cols + rows))   # stay between the first and last row
        return min(self.n - 1, row * self.cols + col % self.cols)  # short last row: its last app

    # ---------------------------------------------------------------- events
    def begin(self):
        self.reset()

    def update(self, dx, dy):
        self.seen = time.monotonic()
        self.ax += dx
        self.ay += dy
        if self.mode is None and max(abs(self.ax), abs(self.ay)) >= DECIDE:
            if abs(self.ax) >= abs(self.ay):
                self.open_switcher(right=self.ax > 0)
            else:
                self.mode = "done"
                if self.ay > 0:
                    log("swipe down: show desktop")
                    toggle_show_desktop()
                else:
                    log("swipe up: maximize all")
                    subprocess.Popen([MAXIMIZE_ALL])
        if self.mode == "switch":
            self.move_to(self.target())

    def end(self):
        if self.mode == "switch":
            xdo("keyup", "Alt_L")                    # lifting the fingers picks the app
            log("switched, index", self.index)
        self.mode = "done"


def main():
    dpy = X11.XOpenDisplay(None)
    if not dpy:
        sys.exit("swipe-switcher: no X display")
    opcode, ev, err = c_int(), c_int(), c_int()
    if not X11.XQueryExtension(dpy, b"XInputExtension", ctypes.byref(opcode), ctypes.byref(ev), ctypes.byref(err)):
        sys.exit("swipe-switcher: no XInput")
    major, minor = c_int(2), c_int(4)
    Xi.XIQueryVersion(dpy, ctypes.byref(major), ctypes.byref(minor))
    if (major.value, minor.value) < (2, 4):
        sys.exit(f"swipe-switcher: needs XInput 2.4 (have {major.value}.{minor.value})")

    bits = (ctypes.c_ubyte * 5)()
    for e in (XI_GestureSwipeBegin, XI_GestureSwipeUpdate, XI_GestureSwipeEnd):
        bits[e >> 3] |= 1 << (e & 7)
    mask = XIEventMask(XIAllMasterDevices, len(bits), bits)
    mods = XIGrabModifiers(XIAnyModifier, 0)
    root = X11.XDefaultRootWindow(dpy)
    # grab swipes on the root window so we get them whichever app is under the pointer
    rc = Xi.XIGrabSwipeGestureBegin(dpy, XIAllMasterDevices, root, XIGrabModeAsync, XIGrabModeAsync,
                                    0, ctypes.byref(mask), 1, ctypes.byref(mods))
    X11.XFlush(dpy)
    log("started, XI", f"{major.value}.{minor.value}", "grab rc", rc, "status", mods.status)

    g = Gesture()
    fd = X11.XConnectionNumber(dpy)
    event = XEvent()
    while True:
        if not X11.XPending(dpy):
            select.select([fd], [], [], 0.5)
            if g.mode == "switch" and time.monotonic() - g.seen > 3:
                log("safety release")
                g.end()                               # never leave Alt held down
            continue
        X11.XNextEvent(dpy, ctypes.byref(event))
        cookie = event.xcookie
        if event.type != GenericEvent or cookie.extension != opcode.value:
            continue
        if not X11.XGetEventData(dpy, ctypes.byref(cookie)):
            continue
        try:
            if cookie.evtype in (XI_GestureSwipeBegin, XI_GestureSwipeUpdate, XI_GestureSwipeEnd):
                e = ctypes.cast(cookie.data, ctypes.POINTER(XIGestureSwipeEvent)).contents
                if e.detail == FINGERS:
                    if cookie.evtype == XI_GestureSwipeBegin:
                        g.begin()
                    elif cookie.evtype == XI_GestureSwipeUpdate:
                        g.update(e.delta_unaccel_x, e.delta_unaccel_y)
                    else:
                        g.end()
                if LOG and cookie.evtype != XI_GestureSwipeUpdate:
                    log("event", cookie.evtype, "fingers", e.detail, "sum", round(g.ax), round(g.ay))
        finally:
            X11.XFreeEventData(dpy, ctypes.byref(cookie))


if __name__ == "__main__":
    main()
EOF
chmod +x ~/.local/bin/swipe-switcher
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/swipe-switcher.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Swipe app switcher
Exec=python3 $HOME/.local/bin/swipe-switcher
Terminal=false
EOF
nohup python3 ~/.local/bin/swipe-switcher >/dev/null 2>&1 &
```

## 4. Gesture settings

```bash
mkdir -p ~/.config/touchegg
cat > ~/.config/touchegg/touchegg.conf <<'EOF'
<touchégg>
  <settings>
    <property name="animation_delay">150</property>
    <property name="action_execute_threshold">20</property>
    <property name="color">auto</property>
    <property name="borderColor">auto</property>
  </settings>

  <application name="All">
    <!-- 3-finger swipes (all directions) are handled by ~/.local/bin/swipe-switcher -->

    <!-- 4 fingers left/right: next/previous desktop (workspace) -->
    <gesture type="SWIPE" fingers="4" direction="LEFT">
      <action type="CHANGE_DESKTOP">
        <direction>next</direction>
        <animate>true</animate>
        <animationPosition>right</animationPosition>
      </action>
    </gesture>
    <gesture type="SWIPE" fingers="4" direction="RIGHT">
      <action type="CHANGE_DESKTOP">
        <direction>previous</direction>
        <animate>true</animate>
        <animationPosition>left</animationPosition>
      </action>
    </gesture>

    <!-- 4 fingers up/down: volume (keeps changing as you slide) -->
    <gesture type="SWIPE" fingers="4" direction="UP">
      <action type="RUN_COMMAND">
        <repeat>true</repeat>
        <command>wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+</command>
        <decreaseCommand>wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-</decreaseCommand>
      </action>
    </gesture>
    <gesture type="SWIPE" fingers="4" direction="DOWN">
      <action type="RUN_COMMAND">
        <repeat>true</repeat>
        <command>wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-</command>
        <decreaseCommand>wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+</decreaseCommand>
      </action>
    </gesture>
  </application>
</touchégg>
EOF
```

---

## 5. Start it

Touchégg starts by itself at every login. To start it right now without logging out:

```bash
nohup touchegg >/dev/null 2>&1 &
```

Make sure you have at least 2 desktops (workspaces), otherwise the 4-finger left/right swipe has nowhere to go:

```bash
xfconf-query -c xfwm4 -p /general/workspace_count -s 4
```

---

## 4-finger tap = play / pause

Not built into Kali (libinput only knows 1-, 2- and 3-finger taps), so a small system service
watches the touchpad for a quick 4-finger tap and tells the media player to play or pause
(YouTube in the browser, VLC, Spotify … via `playerctl`). Reading the touchpad needs root.

```bash
sudo apt install playerctl
```

```bash
sudo tee /usr/local/bin/tap4-playpause >/dev/null <<'EOF'
#!/usr/bin/env python3
"""4-finger tap on the touchpad = play / pause (like Windows).

Runs as a small system service (reading the touchpad needs root). It watches the touchpad for
four fingers that touch and lift quickly without moving, then tells the desktop's media
players (YouTube in the browser, VLC, Spotify, ...) to play or pause via playerctl.

  tap4-playpause --user NAME     run (the service passes the desktop user)
  tap4-playpause --user NAME -v  also print every touch to the log (journalctl -u tap4-playpause)
"""
import fcntl
import glob
import os
import pwd
import struct
import subprocess
import sys
import time

MAX_TAP_TIME = 0.35     # seconds from first touch to all fingers lifted
MAX_MOVE = 0.05         # fraction of the touchpad width/height the fingers may move
FINGERS = 4

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
ABS_X, ABS_Y, ABS_MT_POSITION_X = 0x00, 0x01, 0x35
BTN_LEFT, BTN_TOUCH = 0x110, 0x14A
TOOLS = {0x145: 1, 0x14D: 2, 0x14E: 3, 0x14F: 4, 0x148: 5}   # BTN_TOOL_FINGER .. QUINTTAP
BTN_TOOL_QUADTAP = 0x14F
EVENT = struct.Struct("llHHi")                               # struct input_event (64-bit)

args = sys.argv[1:]
USER = args[args.index("--user") + 1] if "--user" in args else None
VERBOSE = "-v" in args


def say(*parts):
    print(*parts, flush=True)


def has_bit(path, bit):
    try:
        words = open(path).read().split()
    except OSError:
        return False
    value = int("".join(w.rjust(16, "0") for w in words), 16)  # sysfs: 64-bit words, highest first
    return bool(value >> bit & 1)


def find_touchpad():
    """The event device that is a touchpad able to see 4 fingers."""
    for dev in sorted(glob.glob("/sys/class/input/event*")):
        caps = dev + "/device/capabilities/"
        if has_bit(caps + "key", BTN_TOOL_QUADTAP) and has_bit(caps + "abs", ABS_MT_POSITION_X):
            return "/dev/input/" + os.path.basename(dev)
    return None


def abs_range(fd, code):
    buf = bytearray(24)                                       # struct input_absinfo: 6 ints
    fcntl.ioctl(fd, 0x80184540 + code, buf)                   # EVIOCGABS(code)
    _value, lo, hi = struct.unpack("iii", bytes(buf[:12]))
    return max(1, hi - lo)


def media(*cmd):
    u = pwd.getpwnam(USER)
    env = {"DBUS_SESSION_BUS_ADDRESS": f"unix:path=/run/user/{u.pw_uid}/bus",
           "XDG_RUNTIME_DIR": f"/run/user/{u.pw_uid}", "HOME": u.pw_dir, "PATH": "/usr/bin:/bin"}
    return subprocess.run(["runuser", "-u", USER, "--", "playerctl", *cmd],
                          env=env, capture_output=True, text=True, timeout=5)


def play_pause():
    if not USER:
        say("no --user given, can't reach the desktop")
        return
    status = media("-a", "status").stdout.split()
    if "Playing" in status:
        media("-a", "pause")
        say("4-finger tap: paused")
    else:
        r = media("play")
        say("4-finger tap: play" + ("" if r.returncode == 0 else " (no media player found)"))


def main():
    path = find_touchpad()
    if not path:
        say("no touchpad with 4-finger support found")
        time.sleep(30)
        sys.exit(1)
    fd = os.open(path, os.O_RDONLY)
    w, h = abs_range(fd, ABS_X), abs_range(fd, ABS_Y)
    say(f"watching {path} ({w}x{h}) for 4-finger taps")

    touching = False
    t0 = x0 = y0 = None
    x = y = 0
    fingers = most = 0
    moved = clicked = False
    while True:
        data = os.read(fd, EVENT.size * 64)
        if not data:
            say("touchpad went away")
            sys.exit(1)                                    # systemd restarts us
        for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
            sec, usec, etype, code, value = EVENT.unpack_from(data, i)
            now = sec + usec / 1e6
            if etype == EV_ABS and code in (ABS_X, ABS_Y):
                if code == ABS_X:
                    x = value
                else:
                    y = value
                if touching and x0 is not None and (abs(x - x0) > MAX_MOVE * w or abs(y - y0) > MAX_MOVE * h):
                    moved = True
            elif etype == EV_KEY and code in TOOLS:
                if value:
                    fingers = TOOLS[code]
                    most = max(most, fingers)
            elif etype == EV_KEY and code == BTN_LEFT and value:
                clicked = True
            elif etype == EV_KEY and code == BTN_TOUCH:
                if value:
                    touching, t0, x0, y0 = True, now, None, None
                    most, moved, clicked = 0, False, False
                else:
                    touching = False
                    took = now - (t0 or now)
                    if VERBOSE:
                        say(f"touch: {most} fingers, {took:.2f}s, moved={moved}, clicked={clicked}")
                    if most == FINGERS and took <= MAX_TAP_TIME and not moved and not clicked:
                        play_pause()
            elif etype == EV_SYN and touching and x0 is None:
                x0, y0 = x, y                                  # where the touch started


if __name__ == "__main__":
    main()
EOF
sudo chmod 755 /usr/local/bin/tap4-playpause
```

```bash
sudo tee /etc/systemd/system/tap4-playpause.service >/dev/null <<EOF
[Unit]
Description=4-finger touchpad tap = play/pause media
After=systemd-udev-settle.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/tap4-playpause --user $USER
Restart=always
RestartSec=3
Nice=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now tap4-playpause
```

Check it: `journalctl -u tap4-playpause -f`, then tap with 4 fingers.

## Troubleshooting

**Gestures do nothing**

```bash
systemctl status touchegg --no-pager
```

```bash
pgrep -a touchegg
```

You need **both**: the service (`touchegg --daemon`) and the user program (`touchegg`).
To see what it detects, stop the user program and run it in a terminal, then swipe:

```bash
pkill -x touchegg; touchegg
```

**Volume gesture does nothing**: older setups use PulseAudio instead of PipeWire.
Check with `which wpctl pactl`. If only `pactl` exists, replace the volume commands with
`pactl set-sink-volume @DEFAULT_SINK@ +5%` and `pactl set-sink-volume @DEFAULT_SINK@ -5%`.

**Changed the config?** Touchégg reloads `~/.config/touchegg/touchegg.conf` automatically.
If not, restart it: `pkill -x touchegg; nohup touchegg >/dev/null 2>&1 &`

---

---

# Part 2 – Desktop layouts (Ops + Floating) with a one-click switch

Three layouts you can switch between at any time:

| Layout | Top | Bottom | Desktop |
|---|---|---|---|
| **Kali default** | Your normal Kali bar | – | Normal icons |
| **Ops** | One bar: Kali menu, workspaces **1 2 3 4**, clock in the middle, VPN IP (only while a VPN is connected), CPU graph, network speed, status icons, layout button | Auto-hiding dock ("Ghost strip") | No icons |
| **Floating** | Three rounded pills: menu + workspaces (left), clock (middle), status icons + layout button (right). Visible over the desktop and small windows, hides behind maximized windows | Same auto-hiding dock | Only Home and Trash |

You need two files shared next to this guide: **`kali-setup-files/ops-layout.tar.bz2`** and
**`kali-setup-files/floating-layout.tar.bz2`**. Put them in your Downloads folder first.

## 6. Install the add-ons

```bash
sudo apt install xfce4-docklike-plugin xfce4-netload-plugin xfce4-panel-profiles
```

## 7. Save your current layout (so you can always switch back)

```bash
mkdir -p ~/.local/share/layouts
xfce4-panel-profiles save ~/.local/share/layouts/kali-default.tar.bz2
cp ~/Downloads/ops-layout.tar.bz2 ~/.local/share/layouts/ops.tar.bz2
cp ~/Downloads/floating-layout.tar.bz2 ~/.local/share/layouts/floating.tar.bz2
echo default > ~/.local/share/layouts/current
```

Make your own Kali default layout auto-hide its top bar too (the shared Ops and Floating files already do):

```bash
xfconf-query -c xfce4-panel -p /panels/panel-1/autohide-behavior -n -t uint -s 1
xfce4-panel-profiles save ~/.local/share/layouts/kali-default.tar.bz2
```

## 8. Styles (rounded dock and pills)

```bash
cat > ~/.local/share/layouts/ops-panel.css <<'EOF'
/* Ops layout: Ghost strip dock (docklike plugin inside a see-through panel-2) */
#docklike-plugin, .docklike-plugin {
  background-color: rgba(13, 15, 23, 0.94);
  border: 1px solid #5b8fd9;
  border-radius: 14px;
  padding: 2px 8px;
}
EOF
```

```bash
cat > ~/.local/share/layouts/floating-panel.css <<'EOF'
/* Floating layout: rounded "island" pills at the top + the same Ghost strip dock */
.xfce4-panel.background {
  background-color: rgba(10, 12, 18, 0.92);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 16px;
}
#docklike-plugin, .docklike-plugin {
  background-color: rgba(13, 15, 23, 0.94);
  border: 1px solid #5b8fd9;
  border-radius: 14px;
  padding: 2px 8px;
}
EOF
```

## 9. The layout switch script

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/layout-toggle <<'EOF'
#!/bin/sh
# Switch between desktop layouts: default (Kali), ops, floating.
#   layout-toggle            go to the next layout (default -> ops -> floating -> default)
#   layout-toggle <name>     switch to that layout
L="$HOME/.local/share/layouts"
STATE="$L/current"
GTKCSS="$HOME/.config/gtk-3.0/gtk.css"
ORDER="default ops floating"
cur=$(cat "$STATE" 2>/dev/null || echo default)

next() { set -- $ORDER $ORDER; while [ "$1" != "$cur" ] && [ $# -gt 0 ]; do shift; done; echo "${2:-default}"; }
case "$1" in
  default|ops|floating) want=$1 ;;
  "") want=$(next) ;;
  *) echo "usage: layout-toggle [default|ops|floating]"; exit 1 ;;
esac
[ "$want" = "$cur" ] && { echo "Already on $want"; exit 0; }

file() { [ "$1" = default ] && echo "$L/kali-default.tar.bz2" || echo "$L/$1.tar.bz2"; }
ws()   { xfconf-query -c xfwm4 -p /general/workspace_names $(for n in "$@"; do printf ' -t string -s %s' "$n"; done); }
icons() { # style home trash filesystem removable
  xfconf-query -c xfce4-desktop -p /desktop-icons/style -s "$1"
  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-home -s "$2"
  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-trash -s "$3"
  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-filesystem -s "$4"
  xfconf-query -c xfce4-desktop -p /desktop-icons/file-icons/show-removable -s "$5"
}

# keep any tweaks you made to the layout you're leaving
xfce4-panel-profiles save "$(file "$cur")"

mkdir -p "$(dirname "$GTKCSS")"; touch "$GTKCSS"
sed -i '/layout-toggle/d' "$GTKCSS"
case "$want" in
  ops)
    echo "@import url(\"$L/ops-panel.css\"); /* layout-toggle */" >> "$GTKCSS"
    ws 1 2 3 4; icons 0 true true true true
    xfconf-query -c xfwm4 -p /general/margin_top -n -t int -s 0
    xfconf-query -c xfwm4 -p /general/show_dock_shadow -s true ;;
  floating)
    echo "@import url(\"$L/floating-panel.css\"); /* layout-toggle */" >> "$GTKCSS"
    ws 1 2 3 4; icons 2 true true false false
    xfconf-query -c xfwm4 -p /general/margin_top -n -t int -s 44
    xfconf-query -c xfwm4 -p /general/show_dock_shadow -s false ;;
  default)
    ws 1 2 3 4 5 6 7 8 9 0; icons 2 true true true true
    xfconf-query -c xfwm4 -p /general/margin_top -n -t int -s 0
    xfconf-query -c xfwm4 -p /general/show_dock_shadow -s true ;;
esac

xfce4-panel-profiles load "$(file "$want")"
echo "$want" > "$STATE"
"$HOME/.local/bin/topbar-toggle" apply   # top bar mode (auto/hide/show) + pill positions for this screen
notify-send -i view-grid-symbolic "Desktop layout" "Switched to $want" 2>/dev/null
exit 0
EOF
chmod +x ~/.local/bin/layout-toggle
```

Hide / show the top bar in any layout (needs `xdotool`, which Kali already has):

```bash
cat > ~/.local/bin/topbar-toggle <<'EOF'
#!/bin/sh
# Hide or show the top bar in any layout (Kali default, Ops, Floating).
#   topbar-toggle         flip between "auto" and "show"
#   topbar-toggle auto    visible over the desktop and small windows, hides when a window
#                         is maximized; move the pointer to the top edge to bring it back
#   topbar-toggle hide    always hidden; move the pointer to the top edge to bring it back
#   topbar-toggle show    always visible
#   topbar-toggle apply   re-apply the current mode (used by layout-toggle)
L="$HOME/.local/share/layouts"
layout=$(cat "$L/current" 2>/dev/null || echo default)
q() { xfconf-query -c xfce4-panel "$@"; }
if [ "$layout" = floating ]; then panels="1 3 4"; else panels="1"; fi

cur=$(q -p /panels/panel-1/autohide-behavior 2>/dev/null || echo 0)   # 0 show, 1 auto, 2 hide
case "$1" in
  show) ah=0 ;; auto) ah=1 ;; hide) ah=2 ;;
  apply) ah=$cur ;;
  "") if [ "$cur" = 0 ]; then ah=1; else ah=0; fi ;;
  *) echo "usage: topbar-toggle [auto|hide|show|apply]"; exit 1 ;;
esac

margin=0
if [ "$layout" = floating ]; then
  W=$(xdotool getdisplaygeometry 2>/dev/null | cut -d' ' -f1); [ -n "$W" ] || W=1920
  if [ "$ah" = 0 ]; then
    # always visible: float 8px below the edge (x/y = centre of each pill); keep windows below them
    q -p /panels/panel-1/position -s "p=0;x=96;y=24"
    q -p /panels/panel-3/position -s "p=0;x=$((W / 2));y=24"
    q -p /panels/panel-4/position -s "p=0;x=$((W - 146));y=24"
    margin=44
  else
    # auto/hidden: tuck into the top edge (6 = top-left, 9 = top-center, 2 = top-right) so the edge reveals them
    q -p /panels/panel-1/position -s 'p=6;x=0;y=0'
    q -p /panels/panel-3/position -s 'p=9;x=0;y=0'
    q -p /panels/panel-4/position -s 'p=2;x=0;y=0'
  fi
fi
for p in $panels; do q -p /panels/panel-$p/autohide-behavior -n -t uint -s "$ah"; done
xfconf-query -c xfwm4 -p /general/margin_top -n -t int -s "$margin"

if [ "$1" != apply ]; then
  case "$ah" in 0) msg="Top bar: always visible";; 1) msg="Top bar: hides behind maximized windows";; 2) msg="Top bar: always hidden";; esac
  notify-send -i view-grid-symbolic -t 1500 "$msg" "Move the pointer to the top edge to bring it back" 2>/dev/null
fi
exit 0
EOF
chmod +x ~/.local/bin/topbar-toggle
```

Menu entry (appears in the Kali app menu):

```bash
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/layout-toggle.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Switch desktop layout
Comment=Go to the next desktop layout (Kali default, Ops, Floating)
Exec=$HOME/.local/bin/layout-toggle
Icon=preferences-desktop-theme-global
Terminal=false
Categories=Settings;
EOF
```

**Log out and back in once** if the folder `~/.local/bin` didn't exist before step 9 –
Kali only adds it to your PATH at login, and the layout button needs it.

## 10. Try it

```bash
layout-toggle ops
```

```bash
layout-toggle floating
```

**Network speed shows nothing (Ops)?** Your Wi-Fi may not be called `wlan0`.
Check with `ip route | grep default` (the word after `dev`), then right-click the
network numbers on the top bar → Properties → pick that device.

## 11. Show battery percentage next to the battery icon

```bash
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/show-panel-label -s 1
```

(`0` = icon only, `1` = percentage, `2` = time left, `3` = both. Works in every layout.)

## Switching layouts

| How | |
|---|---|
| Button | the white grid icon left of the lock button – click it and pick a layout |
| Terminal | `layout-toggle`, or `layout-toggle default` / `ops` / `floating` |
| Top bar auto-hide (any layout) | The button menu → *Top bar: auto-hide on/off*. **Auto** = visible over the desktop and small windows, hides when a window is maximized; move the pointer to the top edge to bring it back. Also `topbar-toggle auto` / `hide` (always hidden) / `show` (always visible). Every layout starts in auto mode |

Takes 1–2 seconds; the panel blinks, your open windows are not touched.
Any change you make to a layout (moving icons, pinning apps) is kept when you switch away.
The Floating pills are placed for your screen width automatically.
**Don't switch twice in a row quickly** – wait for the first switch to finish.

**Tip:** to pin an app to the dock, open it, right-click its dock icon → *Pin to Dock*.

---

## Undo everything

```bash
layout-toggle default
```

```bash
sudo rm /etc/X11/xorg.conf.d/30-touchpad.conf
```

```bash
sudo systemctl disable --now tap4-playpause && sudo rm /usr/local/bin/tap4-playpause /etc/systemd/system/tap4-playpause.service
```

```bash
sudo systemctl disable --now touchegg && sudo apt remove touchegg
```

```bash
rm -r ~/.config/touchegg ~/.local/bin/maximize-all ~/.local/bin/switch-app ~/.local/bin/swipe-switcher ~/.config/autostart/swipe-switcher.desktop
```

```bash
rm -r ~/.local/share/layouts ~/.local/bin/layout-toggle ~/.local/bin/topbar-toggle ~/.local/share/applications/layout-toggle.desktop
sed -i '/layout-toggle/d' ~/.config/gtk-3.0/gtk.css
xfconf-query -c xfwm4 -p /general/margin_top -s 0
xfconf-query -c xfwm4 -p /general/show_dock_shadow -s true
```

---

## Touchpad gestures and screen edges at a glance

| Shortcut | Does |
|---|---|
| 3 fingers left / right | App switcher with previews – slide to pick, up/down for rows, lift to switch |
| 3 fingers down | Show desktop |
| 3 fingers up | Bring back and maximize all windows |
| 4 fingers left / right | Next / previous workspace |
| 4 fingers up / down | Volume up / down |
| 4-finger tap | Play / pause music or video |
| Tap | Click |
| Pointer to bottom edge | Show the dock |
| Pointer to top edge | Show the top bar (when it's hidden) |

