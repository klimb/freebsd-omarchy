![Omarchy on FreeBSD](docs/omarchy-freebsd-logo.png)

# freebsd-omarchy

My favorite open-source operating system is FreeBSD. I also love OpenBSD (and
I've run GNU/Linux and created Linux distros since its dark early days).

The best UNIX UI in 2026, in my opinion, is Hyprland on top of Wayland. The
Omarchy Linux distribution gets it exactly right (except for the whole Linux
thing).

This project ports Omarchy's beautiful UI and its opinionated, chef's-choice
software to FreeBSD. BSD just needs to look good. Everything else is already
better.

This is my favorite operating system: the latest stable FreeBSD + the Omarchy
desktop experience.

Have fun!

[![Omarchy running on FreeBSD](docs/demo.jpg)](https://github.com/klimb/freebsd-omarchy/raw/main/docs/demo.mp4)

## Install

Assuming FreeBSD is already installed, running as your **normal user** (not root —
Hyprland refuses to run as root) with `doas` available:

```sh
# 1. GPU driver — Hyprland needs a real DRM/KMS device (/dev/dri)
doas pkg install -y drm-kmod
doas sysrc kld_list+="i915kms"    # Intel (use amdgpu for AMD)
doas reboot

# 2. Install the port and set up your dotfiles
doas pkg install -y omarchy
omarchy-setup
```

## Start Omarchy

Log in to FreeBSD over a console and type:

```sh
omarchy-session
```

## Layout

```
port/x11-wm/omarchy/     FreeBSD port (Makefile, pkg-descr, pkg-message, distinfo)
scripts/omarchy-session  TTY launcher: sets the FreeBSD Wayland env and execs Hyprland
scripts/omarchy-setup    Per-user tool: clones Omarchy dotfiles + applies FreeBSD fixes
docs/design.md           Design document
```
