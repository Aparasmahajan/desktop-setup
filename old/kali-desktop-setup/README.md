# Kali desktop setup

One-command setup for a fresh Kali Linux (XFCE) install: Windows-style touchpad,
touchpad gestures, and three desktop layouts you can switch between.

## Needs

- Kali Linux 2022 or newer with the XFCE desktop (Kali's default), X11 session
- a laptop touchpad, internet for a few small Kali packages, your password once

## Install

```bash
tar xzf kali-desktop-setup.tar.gz
```

```bash
cd kali-desktop-setup && ./install.sh
```

It asks for your password once. Takes about a minute (needs internet for a few small Kali packages).

Start on a different layout: `./install.sh floating` or `./install.sh default`.

Log out and back in once afterwards so tap-to-click and natural scrolling turn on.

## What you get

| | |
|---|---|
| Tap to click, natural scrolling | every touchpad |
| 3 fingers ← / → | app switcher with previews: slide to pick (↑/↓ for rows), lift to switch, stops at the last app |
| 3 fingers ↓ / ↑ | show desktop / maximize all windows |
| 4 fingers ← / → | next / previous workspace |
| 4 fingers ↑ / ↓ | volume |
| 4-finger tap | play / pause music or video |
| Layouts | **Kali default**, **Ops** (one bar + dock), **Floating** (rounded pills + dock) |
| Grid icon on the top bar | pick a layout, or turn top-bar auto-hide on/off |
| Dock | hidden at the bottom – move the pointer to the bottom edge |
| Top bar | hides behind maximized windows – move the pointer to the top edge |

Terminal: `layout-toggle ops | floating | default`, `topbar-toggle auto | hide | show`.

## Remove

```bash
./uninstall.sh
```

`GUIDE.md` explains every step by hand, if you'd rather do it yourself.
