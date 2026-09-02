# FreeBSD Omarchy — Porting Roadmap

Omarchy targets Arch Linux + systemd. This tracks the platform mismatches that
break menu items / helpers on FreeBSD, grouped by area, with the fix approach.

Status legend: **done** (fixed + deployed), **wip** (in progress), **todo**,
**excluded** (won't fix — no sensible FreeBSD equivalent).

Run `omarchy-doctor-freebsd` on the machine for a live, categorized audit of
which Linux-only commands each helper still depends on.

## Fix strategy

Two update-safe mechanisms (Omarchy's clone is `git reset --hard`-ed on every
`omarchy-setup` run, so we never hand-edit it durably):

1. **Command shims** in `~/.local/bin` (written by `omarchy-setup`) for Linux
   command *names* that don't collide with an `omarchy-*` helper (e.g.
   `systemctl`, `ttfx`). `~/.local/bin` is on the session PATH.
2. **Clone patches / overrides** applied by `omarchy-setup` *after* the reset,
   for `omarchy-*` helpers themselves (the clone's `bin/` is first on PATH, so a
   shim cannot shadow them). Done today for shebangs, the screensaver, etc.

---

## Areas

### Power / session — **done**
`systemctl` (92 uses), `systemd-run` (16), `systemd-inhibit` (6). No systemd.
- Shims: `systemctl` (suspend→`acpiconf -s3`, reboot/poweroff→`shutdown`,
  enable/disable→`sysrc`, start/stop/restart→`service`, `is-active`/`is-enabled`
  checks, `--user`→no-op), `systemd-run` (honors `--on-active` as a delay, runs
  detached), `systemd-inhibit` (passthrough).
- `install.sh` grants passwordless `doas` for `shutdown` + `acpiconf` so the GUI
  power menu (no controlling tty) can suspend/reboot/shut down.
- Hibernate auto-hides (`omarchy-hibernation-available` reads Linux `/sys/power`).

### Screensaver — **done**
`ttfx` (7) is TerminalTextEffects renamed. FreeBSD ships it as
`py312-terminaltexteffects` (the `tte` command) with identical flags.
- Package added to bootstrap; `ttfx`→`tte` shim.
- `omarchy-setup` patches `omarchy-screensaver` + `omarchy-system-lock` to detect
  the effect by its `screensaver.txt` input-file marker (since `tte`'s process
  name is `python`, not `ttfx`) and swaps Linux `pidwait` for `pkill`.
- `omarchy-setup` seeds `~/.config/omarchy/branding/screensaver.txt` from
  `logo.txt` (upstream creates it in a first-run unit we don't run), otherwise
  `ttfx -i .../screensaver.txt` has no input file. Verified end-to-end on the
  laptop: `tte` renders the FreeBSD branding and `pgrep`/`pkill -f screensaver.txt`
  find and stop the process.

### WiFi — **wip** (FreeBSD-specific, `wpa_supplicant`)
`nmcli` (14), `NetworkManager` (26), `rfkill` (9), plus `ip`/`iw`/`/sys/class/net`.
FreeBSD uses `wpa_supplicant` + `ifconfig wlanN` (+ DHCP via rc.conf), not
NetworkManager. wpa_cli's control socket is root-only, so anything the bar (an
unprivileged process) reads must come from `ifconfig`/`route`.

Delivered as FreeBSD overrides (in `overrides/bin/`, copied over the clone by
`omarchy-setup`) and helpers:
- **done** `omarchy-network-status` — bar status line + `--verbose` details from
  `ifconfig`/`route`/`netstat` (SSID, signal %, freq, ip/prefix/gateway,
  rx/tx bytes, bitrate, ping). Verified.
- **done (untested live)** `omarchy-restart-wifi` — `service netif restart wlanN`
  via doas. Not exercised over SSH (it drops the link); verify from the console.
- **done** `omarchy-wifi-freebsd` — a `wpa_supplicant` selector wired into the
  menu (Setup → Network → Wi-Fi). Scans with `ifconfig wlanN list scan` (native
  net80211, no root needed to read), picks with `fzf`, connects via `wpa_cli`
  (add/set/select_network, `save_config` with `update_config=1`), then re-runs
  DHCP. `scan`/`status` subcommands verified live; the interactive connect needs
  a console test (it can briefly drop the link, so it wasn't exercised over SSH).

- **done** network **panel** connection state (`shell/plugins/panels/network/Panel.qml`).
  The panel derived its whole connected state (`kind`, `signalStrength`, hero
  label, bar icon) from `Quickshell.Networking`, whose only backend is
  NetworkManager-over-D-Bus — absent on FreeBSD — so it showed "NOT CONNECTED"
  with a dead icon even while the same panel displayed a live SSID/IP and
  real-time throughput/ping from `omarchy-network-status`. `omarchy-setup` step
  3e patches `Panel.qml` (post-reset, update-safe) to fall back to that status
  data (`root.info`) for the connected kind and signal% when NetworkManager is
  absent.

Still TODO:
- The panel's **scan/connect list** (`wifiNetworks`, `wifiStationAvailable`) is
  still NetworkManager-only, so it stays empty on FreeBSD. The working connect
  flow lives in the menu entry above (`omarchy-wifi-freebsd`) instead.
- `omarchy-network-band`, `omarchy-network-password`, `omarchy-network-qr`
  (nmcli connection-profile model).

### Bluetooth — **todo**
`bluetoothctl` (3), `bluez` (3). FreeBSD's stack is `ng_ubt`/`hccontrol`/`bthidd`,
not BlueZ. Affected: `omarchy-bluetooth-device`, `omarchy-bluetooth-power`,
`omarchy-restart-bluetooth`. Plan: evaluate a FreeBSD reimplementation
(`service bluetooth`, `hccontrol` inquiry/pairing) or hide if impractical.

### Display / power keys — **wip**
- **done** Display brightness keys (`XF86MonBrightness*`). FreeBSD override
  `omarchy-brightness-display` drives the internal panel through `backlight(8)`
  (`/dev/backlight/backlight0`, group `video`), which takes an absolute
  percentage; `off`/`on` still map to Hyprland DPMS. Verified live on the laptop
  (set/±5%/±1%/100%/min). Caveats: `backlight` only accepts integer percent, so
  `±1%` precise steps may not move on panels with few raw levels, and `1%`
  ("minimum") can map to raw 0 (fully off) on Intel panels. External DDC/Apple
  displays are not handled (no `ddcutil` path); those key events adjust the
  internal panel.
- **done** Brightness key bindings. On some laptops (e.g. ThinkPads) the
  brightness Fn keys emit `KEY_F5`/`KEY_F6` (xkb `F5`/`F6`), not
  `XF86MonBrightness*`, so Omarchy's default binds never fire (verified with
  `libinput debug-events`). Opt in with `OMARCHY_BRIGHTNESS_FN_KEYS=1`:
  `omarchy-setup` then binds `F5`→down / `F6`→up in `~/.config/hypr/bindings.lua`
  (a user-override file that survives clone updates). Off by default so hardware
  with proper `XF86` keysyms isn't hijacked. Verified live: keys change the panel
  and show the brightness OSD.
- **todo** Keyboard backlight (`XF86KbdBrightness*`) — upstream reads
  `/sys/class/leds/*kbd_backlight*`, absent on FreeBSD; the helper degrades to a
  no-op ("no keyboard backlight device"). Same for the `micmute` LED.
- **todo** `acpi` (6) → `acpiconf`/`sysctl` for battery + thermal.

### Security — **todo**
`fprintd` (8) fingerprint — `libfprint` support on FreeBSD is limited; likely
hide the fingerprint menu entries.

---

## Excluded (won't fix)
- **Docker** (34) — Linux-specific; not supported on FreeBSD. Preferred
  alternative: [Sylve](https://github.com/AlchemillaHQ/Sylve), a
  FreeBSD-native VM/container manager. Omarchy's Docker menu entries should
  either be hidden on FreeBSD or replaced with Sylve equivalents.
- **Plymouth** (26) — boot splash; no FreeBSD equivalent.
- **pacman / yay / paru / makepkg** — Arch package tooling; replaced by the
  `omarchy-pkg-*-freebsd` helpers (pkg). AUR entries hidden in the menu.
- **flatpak** (5) — not on FreeBSD.
- **fwupdmgr** — firmware update daemon; not on FreeBSD.

## Package gap audit (omarchy-base.packages vs our deps) — **done 2026-09**

Cross-referenced omarchy's upstream `install/omarchy-base.packages` against the
FreeBSD port Makefile and bootstrap. Results:

**Added** (confirmed in FreeBSD ports, now in Makefile + bootstrap):

| Package | Port | Why |
|---|---|---|
| `ImageMagick7` | `graphics/ImageMagick7` | Theme/wallpaper color extraction |
| `mpv` | `multimedia/mpv` | Video player |
| `pamixer` | `audio/pamixer` | Volume control CLI (keybind scripts) |
| `fastfetch` | `sysutils/fastfetch` | System info on shell open |
| `wtype` | `x11/wtype` | Wayland keyboard input simulator |
| `unzip` | `archivers/unzip` | ZIP extraction |
| `qrencode` | `graphics/qrencode` | QR code (omarchy-network-qr) |
| `gnome-keyring` | `security/gnome-keyring` | Credential store |
| `bash-completion` | `shells/bash-completion` | Tab completion |

**Still to verify on target box** (`make search name=<pkg>` needed):

- `hyprsunset` → `x11/hyprsunset`? (night light; listed as "partial" below)
- `yt-dlp` → `www/yt-dlp`? (note: now pulls npm/deno build deps as of 2026-03)
- `udiskie` → `sysutils/udiskie`? (USB automount, used in autostart)
- `ddcutil` → `sysutils/ddcutil`? (monitor brightness via DDC/CI)
- `gum` → `sysutils/gum`? (Charm interactive prompts)
- `cups` → `print/cups`? (printing support — consider as optional port flavor)
- `noto-fonts-emoji` — may be a sub-package of `x11-fonts/noto`

**Excluded — Linux-specific, no FreeBSD equivalent:**
`bluez`/`bluetoothctl` (FreeBSD has own BT stack), `brightnessctl` (use
`backlight(8)`), `inotify-tools` (use kqueue), `power-profiles-daemon` (systemd),
`uwsm` (shimmed), `ufw`/`NetworkManager`, `gpu-screen-recorder` (V4L2/NVENC),
`wireless-regdb`/`linux-firmware`.

---

## Already working (present via packages)
`pactl`, `wpctl` (pipewire/wireplumber), `grim`, `slurp`, `gsettings`.
Partial (need the right package): `playerctl`, `hyprsunset`, `mise`, `satty`,
`dconf`, `upower`.
