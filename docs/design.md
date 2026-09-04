# FreeBSD Omarchy Port — Design Document

**Date:** 2026-08-31
**Goal:** Replicate the Omarchy visual/WM experience on FreeBSD, stripped to essentials.

---

## Goals

- Install the `freebsd-omarchy` port and end up with a usable Hyprland desktop, no manual dotfile wrangling.
- Start from a fresh, minimal FreeBSD install (no X/Wayland, no display manager, no desktop), just a base system and a TTY login.
- Workflow: install FreeBSD, `pkg install omarchy` (or build the port), log in on a TTY, run `omg`, land in a themed desktop.
- Fonts, themes, wallpapers, terminal, top bar, and keybinds preconfigured to match Omarchy out of the box.
- Pull in only what the desktop needs; nothing from the "out of scope" list below.

---

## Scope

**In scope:** Hyprland compositor, QuickShell top bar, themed terminal, dotfiles, fonts, wallpapers, Wayland utilities, and a TTY-launch workflow (`start-hyprland` from login shell).

**Out of scope:** Docker, Bluetooth, CUPS/printing, SDDM/display manager, NetworkManager, systemd services, NVIDIA/hardware-specific drivers, Plymouth boot splash, gaming, office apps.

---

## Architecture

```
TTY Login
  └─ ~/.local/bin/start-hyprland
       └─ Hyprland (Wayland compositor)
            ├─ QuickShell (top bar)
            ├─ Foot / Ghostty / Alacritty (terminal)
            ├─ PipeWire + WirePlumber (audio/screen backend)
            ├─ Wayland utils (grim, slurp, wl-clipboard, hyprpicker, hyprsunset)
            └─ XDG Desktop Portal (Hyprland)
```

---

## Package Mapping

### From `pkg install` (already in FreeBSD ports)

| Category | Packages |
|---|---|
| **Compositor** | `hyprland`, `seatd` |
| **Terminals** | `foot`, `alacritty` |
| **Audio/Media** | `pipewire`, `wireplumber` |
| **Wayland Utils** | `wl-clipboard`, `grim`, `slurp`, `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-gtk` |
| **Shell/CLI** | `starship`, `zoxide`, `fzf`, `bat`, `eza`, `fd-find`, `ripgrep`, `jq`, `btop`, `lazygit`, `tmux`, `neovim` |
| **Fonts** | `noto-fonts`, `nerd-fonts`, `font-awesome` |
| **Image Viewer** | `imv` |
| **Browser** | `chromium` |
| **Dev Tools** | `git`, `cmake`, `qt6-base`, `qt6-declarative`, `qt6-wayland`, `qt6-shadertools` |

### Build from source

| Package | Notes |
|---|---|
| **QuickShell** | Qt6/QML bar toolkit. cmake build. Deps: qt6base, qt6declarative, libdrm, cli11. No Linux-specific APIs. Fallback: use `waybar` from pkg if build is painful. |
| **hyprpicker** | Color picker. Small C++ project, trivial build. |
| **hyprsunset** | Night light. Small C++ project, trivial build. |
| **Ghostty** | Terminal. Zig-based, FreeBSD support is WIP — use foot/alacritty if it won't build. |

### Omarchy dotfiles to copy from repo

| Source path | Destination |
|---|---|
| `config/hypr/*` | `~/.config/hypr/` |
| `config/foot/*` | `~/.config/foot/` |
| `config/alacritty/*` | `~/.config/alacritty/` |
| `config/ghostty/*` | `~/.config/ghostty/` |
| `config/kitty/*` | `~/.config/kitty/` |
| `config/btop/*` | `~/.config/btop/` |
| `config/lazygit/*` | `~/.config/lazygit/` |
| `config/tmux/*` | `~/.config/tmux/` |
| `config/starship.toml` | `~/.config/starship.toml` |
| `config/imv/*` | `~/.config/imv/` |
| `config/omarchy/*` | `~/.config/omarchy/` (themes, wallpapers) |
| `config/chromium-flags.conf` | `~/.config/chromium-flags.conf` |
| `shell/*` | `~/.config/shell/` or source from `.zshrc` |
| `themes/*` | `~/.config/omarchy/themes/` |
| `default/*` | default wallpapers/assets |

---

## FreeBSD Port Implementation

Verified against the FreeBSD ports tree and Omarchy upstream:

- **Not a metaport.** `USES=metaport` (`Mk/Uses/metaport.mk`) forces `NO_INSTALL=yes`, so a pure metaport cannot ship our `omg`/`omarchy-setup` scripts. Instead the port uses `USE_GITHUB` + `NO_BUILD` + `NO_ARCH` with a custom `do-install`, pulling the desktop via `RUN_DEPENDS` (the pattern used by `x11/gnome`, `x11-wm/xfce4`).
- **Hyprland already ships a launcher.** `x11-wm/hyprland` (currently `0.56.2`) installs `bin/start-hyprland`, `share/wayland-sessions/hyprland.desktop`, and `share/xdg-desktop-portal/hyprland-portals.conf`. To avoid a plist conflict our launcher is named **`omg`**. It is built with `CMAKE_ON=NO_SYSTEMD` and uses `seatd`; `XDG_RUNTIME_DIR` falls back to `/var/run/user/UID`.
- **Version alignment.** Hyprland lags upstream at `0.56.2`; Omarchy's `quattro` branch already carries `0.56` compatibility shims, so pin to `quattro`.
- **Corrected port origins.** `grim`→`x11/grim`, `slurp`→`x11/slurp` (not `graphics/*`), `xdg-desktop-portal-hyprland`→`x11/xdg-desktop-portal-hyprland`, portal frontend→`deskutils/xdg-desktop-portal`. All other origins must be confirmed with `make search name=<pkg>` on the target box.
- **Top bar.** Omarchy's bar is a QuickShell/QML bar (repo is ~28% QML); `config/` also carries a `waybar/` fallback. The port exposes both via `OPTIONS_DEFINE= QUICKSHELL WAYBAR`.

Skeleton (`x11-wm/omarchy/Makefile`):

```makefile
USE_GITHUB=	yes
GH_ACCOUNT=	<you>
GH_PROJECT=	freebsd-omarchy
NO_BUILD=	yes
NO_ARCH=	yes
USES=		shebangfix
RUN_DEPENDS=	Hyprland:x11-wm/hyprland seatd:sysutils/seatd foot:x11/foot \
		grim:x11/grim slurp:x11/slurp wl-copy:x11/wl-clipboard \
		xdg-desktop-portal-hyprland>0:x11/xdg-desktop-portal-hyprland \
		pipewire>0:multimedia/pipewire wireplumber>0:multimedia/wireplumber
OPTIONS_DEFINE=	QUICKSHELL WAYBAR
do-install:
	${INSTALL_SCRIPT} ${WRKSRC}/scripts/omg ${STAGEDIR}${PREFIX}/bin/
	${INSTALL_SCRIPT} ${WRKSRC}/scripts/omarchy-setup   ${STAGEDIR}${PREFIX}/bin/
```

---

## Launcher Script

**`omg`** (installed to `${PREFIX}/bin` by the port; the design's
original `~/.local/bin/start-hyprland` name would collide with the file the
`x11-wm/hyprland` port already installs)

```sh
#!/bin/sh

# Seat access (FreeBSD uses seatd instead of systemd-logind)
export LIBSEAT_BACKEND=seatd

# Wayland / XDG
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

# Qt Wayland
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# Chromium / Electron
export ELECTRON_OZONE_PLATFORM_HINT=wayland

exec Hyprland
```

---

## rc.d Services Required

Only the bare minimum for Hyprland + audio:

| Service | rc.conf line |
|---|---|
| **seatd** | `seatd_enable="YES"` |
| **dbus** | `dbus_enable="YES"` |

PipeWire and WirePlumber run as user services — launch them from Hyprland's `autostart.lua` or a wrapper script, not rc.d.

**User must be in the `video` group** (FreeBSD seatd owns the seatd socket as
`root:video`, and `video` also gates GPU/DRM access; there is no `seat` group):
```sh
pw groupmod -m <user> video
```

---

## Dotfile Adaptations

Most configs work as-is. Known changes needed:

1. **Hyprland autostart & the `uwsm-app` problem.** Omarchy's `default/hypr/autostart.lua` fires on `hyprland.start` and launches *everything* through `o.launch`, which expands to `uwsm-app -- <cmd>` (`default/hypr/helpers.lua`). It also calls `systemctl --user import-environment` and `dbus-update-activation-environment --systemd`. None of `uwsm`, `systemctl`, or systemd exist on FreeBSD, and PipeWire is not socket-activated.

   Rather than patch upstream files (which `omarchy-setup`'s `git reset --hard` would revert), the adaptation is:
   - **Ship a `uwsm-app` shim** (`[ "$1" = -- ] && shift; exec "$@"`) so all of Omarchy's `uwsm-app -- cmd` call sites work unchanged.
   - **Generate a FreeBSD `~/.config/hypr/autostart.lua`** (the user override, loaded after defaults) that starts what systemd would have socket-activated: `pipewire`, `pipewire-pulse`, `wireplumber`, and the `xdg-desktop-portal-hyprland` backend via `o.exec_on_start` (direct, no uwsm).
   - The leftover `systemctl`/`dbus-update-activation-environment --systemd` calls in the default autostart fail harmlessly (missing command / no systemd) and need no patching.
   - **Export `OMARCHY_PATH`** (to the cloned source) and prepend `$OMARCHY_PATH/bin` + `~/.local/bin` to `PATH` in `omg`, so `hyprland.lua` finds `default/hypr/bootstrap.lua` and the `omarchy-*` helpers/shim resolve.

   > Follow-up: many `omarchy-*` helper scripts in `bin/` are `#!/bin/bash` with Linux-isms (`pacman`, `systemctl`, `power-profiles-daemon`, `udiskie`); non-core ones fail harmlessly, but a fully polished desktop needs an audit pass over the launch/theme helpers.

2. **Path adjustments** — FreeBSD installs to `/usr/local/` not `/usr/`. Grep configs for hardcoded `/usr/bin/` or `/usr/share/` and fix.

3. **Chromium flags** — verify Wayland flags work on FreeBSD Chromium build. Likely identical.

4. **Shell config** — any `pacman`/`yay` aliases → remove. Any systemd aliases (like `systemctl suspend`) → replace with FreeBSD equivalents (`zzz` for suspend).

---

## Helper Script Audit (`bin/omarchy-*`)

All ~300 `omarchy-*` helpers are `#!/bin/bash`, so **`shells/bash` is a hard runtime dependency**. Triage of the startup and core-desktop scripts against FreeBSD:

| Script / tool | Issue on FreeBSD | Resolution |
|---|---|---|
| every `omarchy-*` | `#!/bin/bash` | add `shells/bash` dep |
| `omarchy-launch-shell` (the bar) | wraps QuickShell in `systemd-cat` | `systemd-cat` shim |
| `omarchy-launch-terminal` | execs `xdg-terminal-exec` + `setsid` | `x11/xdg-terminal-exec` dep + `setsid` shim |
| `o.launch` (all app launches) | `uwsm-app -- cmd` | `uwsm-app` shim |
| launch scripts (pervasive) | `setsid` (not in base) | `setsid` shim |
| `omarchy-theme-set` | `flock`, `base64 -w 0` | `flock` + `base64`→openssl shims |
| `omarchy-hyprland-monitor-watch` | `socat`, `flock` | `net/socat` dep + `flock` shim |
| `omarchy-cmd-terminal-cwd` | reads `/proc/PID/cwd` | falls back to `$HOME`; optional linprocfs later |
| `omarchy-launch-browser` | `systemd-run --user` | follow-up (bind a direct browser launch) |
| `omarchy-powerprofiles-*` | power-profiles-daemon (systemd) | fails harmlessly (non-core) |
| `omarchy-provision-first-run` | systemd user units, GNOME/GTK hooks | steps fail harmlessly; retries each login |

**Linux-compat shim bundle.** `omarchy-setup` writes five POSIX-sh shims to `~/.local/bin` (which `omg` puts on `PATH`), so the upstream scripts run unchanged and updates never clobber them:

- `uwsm-app` — strip leading `--`, `exec` the command.
- `setsid` — strip flags, `exec` (Hyprland already reaps children).
- `systemd-cat` — strip logging flags, `exec` (stdio inherits to the compositor log).
- `flock` — best-effort no-op locking (a child cannot hold a lock on a caller-owned fd), returns "acquired".
- `base64` — map GNU `-d`/`-w` usage onto `openssl base64 -A`.

Keeping shims in `~/.local/bin` (not `${PREFIX}/bin`) avoids plist conflicts with any real `setsid`/`flock`/`base64` a user later installs.

> Remaining follow-up: audit the theme/`omarchy-theme-set-*` retint helpers and the `omarchy-menu` tree, and decide the browser-launch replacement for `systemd-run --user`.

---

## QuickShell Build Steps

```sh
# Install deps
pkg install cmake qt6-base qt6-declarative qt6-wayland qt6-shadertools \
            qt6-svg libdrm pkgconf spirv-tools cli11 jemalloc cpptrace

# Clone and build
git clone https://github.com/quickshell-mirror/quickshell
cd quickshell
cmake -B build \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(sysctl -n hw.ncpu)
cmake --install build
```

If this fails due to minor Linux-isms, patch and PR upstream. Fallback: install `waybar` from pkg and theme it.

---

## Install Script Outline

```sh
#!/bin/sh
set -e

# 1. System packages
pkg install -y hyprland seatd foot alacritty pipewire wireplumber \
  wl-clipboard grim slurp xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  starship zoxide fzf bat eza fd-find ripgrep jq btop lazygit tmux neovim \
  imv chromium git cmake qt6-base qt6-declarative qt6-wayland qt6-shadertools \
  qt6-svg libdrm pkgconf spirv-tools noto nerd-fonts font-awesome

# 2. Enable services
sysrc seatd_enable=YES
sysrc dbus_enable=YES
service seatd start
service dbus start

# 3. User groups (FreeBSD seatd uses the video group; no seat group exists)
pw groupmod video -m "$USER"

# 4. Clone omarchy for dotfiles + themes
OMARCHY_SRC="$HOME/.local/src/omarchy"
git clone --depth 1 -b quattro https://github.com/omacom/omarchy "$OMARCHY_SRC"

# 5. Symlink configs
for dir in hypr foot alacritty ghostty kitty btop lazygit tmux imv omarchy; do
  ln -sfn "$OMARCHY_SRC/config/$dir" "$HOME/.config/$dir"
done
ln -sf "$OMARCHY_SRC/config/starship.toml" "$HOME/.config/starship.toml"
ln -sf "$OMARCHY_SRC/config/chromium-flags.conf" "$HOME/.config/chromium-flags.conf"

# 6. Install launcher
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/start-hyprland" << 'EOF'
#!/bin/sh
export LIBSEAT_BACKEND=seatd
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export ELECTRON_OZONE_PLATFORM_HINT=wayland
exec Hyprland
EOF
chmod +x "$HOME/.local/bin/start-hyprland"

# 7. Build QuickShell (optional — skip if waybar preferred)
# cd "$OMARCHY_SRC" && ... (see QuickShell Build Steps above)

echo "Done. Log in on TTY and run: start-hyprland"
```

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| **Hyprland needs a real DRM/KMS GPU** | Cannot run in any FreeBSD VM | Validate the desktop on real hardware (see below) |
| QuickShell won't build on FreeBSD | Lose the exact Omarchy top bar | Use Waybar with Omarchy color scheme |
| Hyprland FreeBSD port lags upstream | Missing features Omarchy configs expect | Pin to compatible version, or build from source |
| xdg-desktop-portal-hyprland buggy on FreeBSD | Screen sharing / file dialogs broken | Acceptable loss for now |
| Some Omarchy Lua configs reference Linux paths | Broken autostart / keybinds | Grep & patch during dotfile copy step |
| Ghostty won't build on FreeBSD | One less terminal option | Use foot (already the Omarchy default) |

---

## Validation Status

Validated in a **FreeBSD 15.1-RELEASE arm64 QEMU/hvf VM** (tooling under `test/vm/`):

- All 33 package names resolve in `FreeBSD:15:aarch64`; `hyprland`, `foot`, `pipewire`, `seatd` install cleanly.
- `bootstrap/install.sh` + `omarchy-setup` run end to end: shims installed, `autostart.lua` generated, Omarchy `quattro` configs staged, `omg` installed.
- Bug caught & fixed: FreeBSD `seatd` grants access via the **`video`** group (owns `/var/run/seatd.sock`); there is no `seat` group.

**Not testable in a VM — needs real hardware:** the live graphical session.
Hyprland's backend library **Aquamarine** takes its buffer allocator from **gbm/DRM**. FreeBSD has no virtio-gpu KMS driver (and no `vkms`-style virtual DRM), so no `/dev/dri` exists in any FreeBSD guest (arm64 or amd64, QEMU or bhyve). Aquamarine then aborts with `Cannot open backend: no allocator available` — even headless, and even though software EGL (`llvmpipe`, surfaceless) is present. A `wayvnc` path is therefore not viable for Hyprland.

**Recommended real-hardware test:** a machine with an Intel (`i915`) or AMD (`amdgpu`) GPU supported by `graphics/drm-kmod`, booting FreeBSD on a TTY, then `omg`. The VM remains the CI/build/config validator.

---

## References

- Omarchy repo: https://github.com/omacom/omarchy (branch: `quattro`)
- QuickShell: https://github.com/quickshell-mirror/quickshell
- Hyprland FreeBSD wiki: https://wiki.hyprland.org
- FreeBSD Wayland guide: https://wiki.freebsd.org/Wayland
