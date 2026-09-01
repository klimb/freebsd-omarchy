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

There is no `omarchy` package in the official FreeBSD repo yet — it lives here,
in this repo. Start from a fresh, minimal FreeBSD install and run as your
**normal user** (not root — Hyprland refuses to run as root) with `sudo` or
`doas` available.

### Quick start (bootstrap script)

```sh
# 1. Get this repo
pkg install -y git       # if you don't already have it (run as root/doas)
git clone https://github.com/klimb/freebsd-omarchy
cd freebsd-omarchy

# 2. One-shot installer
sh bootstrap/install.sh
```

`bootstrap/install.sh` does everything for you:

- installs all packages (Hyprland, seatd, terminals, PipeWire, portals, fonts,
  CLI tools, …);
- installs `drm-kmod` and auto-detects your GPU, enabling the right KMS driver
  (`i915kms` for Intel, `amdgpu` for AMD) at boot;
- enables and starts `seatd` and `dbus`;
- adds you to the `video` group (seatd + GPU access);
- installs and configures `doas`, and sets your login shell to `bash`;
- clones the Omarchy dotfiles and applies the FreeBSD fixes (`omarchy-setup`).

When it finishes, **reboot** (to load the GPU driver and pick up the group and
shell changes), then start the desktop:

```sh
omarchy-session
```

### Alternative: build the port

If you'd rather go through the ports tree:

```sh
# Copy the port into your ports tree and build it
cp -R port/x11-wm/omarchy /usr/ports/x11-wm/omarchy
cd /usr/ports/x11-wm/omarchy && make install clean
```

The port pulls in the desktop via its dependencies and installs `omarchy-session`
and `omarchy-setup`. Then follow the printed `pkg-message`: enable `seatd`/`dbus`,
add yourself to the `video` group, load a KMS driver for your GPU, reboot, run
`omarchy-setup`, and finally `omarchy-session`.

## Start Omarchy

Log in to FreeBSD over a console and type:

```sh
omarchy-session
```

## Layout

```
bootstrap/install.sh     One-shot installer: packages, GPU/KMS, services, dotfiles
port/x11-wm/omarchy/     FreeBSD port (Makefile, pkg-descr, pkg-message, distinfo)
scripts/omarchy-session  TTY launcher: sets the FreeBSD Wayland env and execs Hyprland
scripts/omarchy-setup    Per-user tool: clones Omarchy dotfiles + applies FreeBSD fixes
docs/design.md           Design document
```
