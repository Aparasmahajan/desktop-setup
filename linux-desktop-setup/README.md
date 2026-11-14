# Linux desktop setup – Kali, Ubuntu, Linux Mint

Windows-style touchpad and desktop for Debian-based Linux. One installer finds out which
system and desktop you have and sets up what fits.

## Install

```bash
tar xzf linux-desktop-setup.tar.gz
```

```bash
cd linux-desktop-setup && ./install.sh
```

It asks for your password once (needs internet for a few small packages). Log out and back in
afterwards. On XFCE you can pick the starting layout: `./install.sh floating` or `./install.sh default`.

You can also run a system's own installer directly: `kali/install.sh`, `ubuntu/install.sh`, `mint/install.sh`.

## What you get on each system

| | Kali / Xubuntu / Mint XFCE | Ubuntu (GNOME) | Mint Cinnamon | Ubuntu MATE / Mint MATE |
|---|---|---|---|---|
| Tap to click, natural scrolling | ✅ | ✅ | ✅ | ✅ |
| 4-finger tap = play / pause | ✅ | ✅ | ✅ | ✅ |
| 4 fingers ←/→ workspaces, ↑/↓ volume | ✅ | GNOME's own swipes | Mint's own gestures | ✅ |
| 3-finger app switcher with previews (↑/↓ rows) | ✅ | – | – | – |
| 3 fingers ↓ desktop / ↑ maximize all | ✅ | – | – | – |
| Layouts (default, Ops, Floating) + grid button | ✅ | – | – | – |
| Auto-hiding dock and top bar | ✅ | dock at the bottom, hides behind windows | – | – |
| Battery percentage | ✅ | ✅ | – | – |

Other Ubuntu/Debian-based systems (Pop!_OS, Zorin, …) use the Ubuntu installer, which picks by
desktop. KDE and others get only the 4-finger tap. Non-Debian systems (Fedora, Arch) aren't supported.

## Needs

- Kali 2022+, Ubuntu 22.04+, or Linux Mint 21+ (64-bit Intel/AMD for the bundled gesture app)
- XFCE features need an X11 session (the default on Kali, Xubuntu and Mint)
- a touchpad that senses 4 fingers for the 4-finger gestures (most do)

## Remove

```bash
./uninstall.sh
```

Puts back every setting it changed (it saves the old values first) and removes what it installed.
Apps that came with your system (like Mint's gesture app) are left alone.

## Inside

| Folder | |
|---|---|
| `install.sh`, `uninstall.sh` | detect Kali / Ubuntu / Mint and run the right one |
| `kali/`, `ubuntu/`, `mint/` | each system's installer and uninstaller |
| `shared/lib.sh` | the steps they share |
| `shared/files/` | scripts, gesture settings, layouts, the tap service, the gesture app installer |
| `GUIDE-kali-by-hand.md` | every Kali step written out to do by hand |

Tested by simulated runs on Kali, Ubuntu (GNOME), Xubuntu, Mint Cinnamon, Mint MATE and Kubuntu,
and for real on Kali. Ubuntu and Mint haven't been installed on real hardware yet.
