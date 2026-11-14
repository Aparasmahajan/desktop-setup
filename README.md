# Linux setup (Kali XFCE)

Everything for this laptop's desktop setup: touchpad, gestures, the 3-finger app switcher,
the three desktop layouts, and a one-command installer for a fresh Kali.

## What's in this folder

| Item | What it is |
|---|---|
| `linux-desktop-setup.tar.gz` | **The installer package** for Kali, Ubuntu and Linux Mint – copy it to a new PC (keep it on USB/cloud before reinstalling) |
| `linux-desktop-setup/` | The same package, unpacked: `install.sh` (auto-detects), `kali/`, `ubuntu/`, `mint/`, `shared/` |
| `kali-touchpad-setup.md` | Full step-by-step guide to do the Kali setup by hand |
| `current-config/` | Exact copies of the files running on this laptop right now (see below) |
| `old/` | The earlier Kali-only package (replaced by `linux-desktop-setup`) |
| `kali-setup-files/` | Older layout files shared with friends earlier |
| `dock-ideas.*`, `desktop-layouts*` | The design mockups we picked from |

## Install on a fresh PC (Kali, Ubuntu or Linux Mint)

```bash
tar xzf linux-desktop-setup.tar.gz
```

```bash
cd linux-desktop-setup && ./install.sh
```

Then log out and back in once. What you get depends on the system – see `linux-desktop-setup/README.md`.

## `current-config/` – where each file lives on the laptop

| File here | Lives at |
|---|---|
| `system/30-touchpad.conf` | `/etc/X11/xorg.conf.d/30-touchpad.conf` (tap to click, natural scrolling) |
| `system/tap4-playpause` | `/usr/local/bin/tap4-playpause` (4-finger tap = play/pause) |
| `system/systemd/tap4-playpause.service` | `/etc/systemd/system/tap4-playpause.service` (starts it at boot) |
| `home/.local/bin/swipe-switcher` | 3-finger gestures: app switcher with previews, rows, show desktop, maximize all |
| `home/.local/bin/layout-toggle` | switch layouts: `layout-toggle default`/`ops`/`floating` |
| `home/.local/bin/topbar-toggle` | top bar: `topbar-toggle auto`/`hide`/`show` |
| `home/.local/bin/maximize-all` | helper for 3 fingers up |
| `home/.local/bin/switch-app` | older step-by-step app switcher (not used by gestures any more) |
| `home/.config/touchegg/touchegg.conf` | 4-finger gestures (workspaces, volume) |
| `home/.config/autostart/swipe-switcher.desktop` | starts the 3-finger switcher at login |
| `home/.local/share/layouts/` | saved layouts (Kali default, Ops, Floating), their styles, backups |
| `home/.local/share/applications/layout-toggle.desktop` | "Switch desktop layout" menu entry |
| `home/.config/gtk-3.0/gtk.css` | loads the current layout's style |
| `settings.txt` | the desktop settings that were changed (battery %, workspaces, panels, …) |

To restore one file by hand, copy it back to the "Lives at" path (`home/` = your home folder,
`system/` needs `sudo`).
