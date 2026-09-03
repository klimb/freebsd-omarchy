#!/bin/sh
#
# install.sh — standalone bootstrap for Omarchy on FreeBSD, for people who do
# not want to use the x11-wm/omarchy port. Installs packages, enables the
# minimal services, fixes group membership, and runs the dotfile setup.
#
# Run as root, or as a regular user with doas already installed and configured,
# from a fresh FreeBSD install:
#     sh install.sh
#
# Environment overrides:
#   OMARCHY_BRANCH  Omarchy branch (default: quattro)

set -eu

OMARCHY_BRANCH="${OMARCHY_BRANCH:-quattro}"

# Only doas is supported for the root-only steps (this script installs+
# configures it below for later runs); sudo is not used anywhere in this repo.
if [ "$(id -u)" -ne 0 ] && ! command -v doas >/dev/null 2>&1; then
	echo "error: need root or doas to install packages" >&2
	exit 1
fi
priv() {
	if [ "$(id -u)" -eq 0 ]; then "$@"
	else doas "$@"; fi
}

USER_NAME="$(id -un)"

log() { printf '==> %s\n' "$*"; }

# 0. Switch the FreeBSD package repo from the default "quarterly" branch to
# "latest". "latest" tracks the ports tree continuously, so it carries far more
# (and newer) packages than the frozen quarterly snapshot. This also flips the
# FreeBSD-kmods repo (kmods_quarterly_* -> kmods_latest_*) for newer drm-kmod.
# Edit the base config in place, then force-refresh the repo catalogue.
if [ -f /etc/pkg/FreeBSD.conf ] && grep -q 'quarterly' /etc/pkg/FreeBSD.conf; then
	log "Switching pkg repo from 'quarterly' to 'latest'"
	priv sed -i '' -e 's|quarterly|latest|g' /etc/pkg/FreeBSD.conf
	priv pkg update -f
fi

# 1. System packages. Origins map to the pkg names FreeBSD ships.
# bash is required (every omarchy-* helper is #!/bin/bash); socat and
# xdg-terminal-exec back the launch/monitor helpers; vips (vipsthumbnail) backs
# the theme/image picker; figlet renders the FreeBSD presentation banner;
# chromium is Omarchy's browser (webapps launch in its --app mode);
# emacs-wayland is the preferred (Wayland-native) editor; hyprlock is the screen
# locker (Omarchy's QuickShell lock can't PAM-auth as non-root on FreeBSD);
# nautilus is the file manager (Super+Shift+F) and xdg-utils backs `xdg-open`
# (the shell `open` function, e.g. `open .`); coreutils provides GNU `gdate`,
# which omarchy-reminder needs for `date -d` (FreeBSD base date has no -d).
# ffmpegthumbnailer gives nautilus video (mp4/webm/...) thumbnail previews.
# tailscale backs the Setup > Network > Tailscale menu entry (mesh VPN).
PKGS="hyprland seatd bash foot alacritty pipewire wireplumber wl-clipboard grim slurp \
hyprpicker xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-terminal-exec xdg-utils socat \
starship zoxide fzf bat eza fd-find ripgrep jq btop lazygit tmux neovim imv git vips figlet gawk lua54 coreutils \
noto-basic nerd-fonts font-awesome dbus py312-terminaltexteffects cmatrix \
ImageMagick7 mpv wf-recorder ffmpeg pamixer fastfetch wtype unzip libqrencode gnome-keyring bash-completion chromium emacs-wayland hyprlock nautilus ffmpegthumbnailer tailscale"

log "Installing packages"
priv pkg install -y $PKGS

# QuickShell (Omarchy top bar) may not be packaged; try, but do not fail.
if ! priv pkg install -y quickshell 2>/dev/null; then
	log "quickshell package not available; install waybar as a fallback"
	priv pkg install -y waybar || true
fi

# 2. GPU/DRM kernel module. Wayland compositors (Hyprland/Aquamarine) need a
# DRM render node (/dev/dri/*), which only exists once the KMS driver is
# loaded. FreeBSD ships these out-of-tree in drm-kmod; pick the module for the
# installed GPU and load it now + at boot.
log "Installing DRM kernel module (drm-kmod)"
priv pkg install -y drm-kmod
gpuinfo="$(pciconf -lv 2>/dev/null | grep -iA4 'class=0x0300' || true)"
if printf '%s' "$gpuinfo" | grep -qi intel; then
	KMS=i915kms
elif printf '%s' "$gpuinfo" | grep -qiE 'amd|ati|radeon'; then
	KMS=amdgpu
else
	KMS=""
fi
if [ -n "$KMS" ]; then
	log "Enabling $KMS at boot and loading it now"
	priv sysrc kld_list+="$KMS"
	priv kldload "$KMS" 2>/dev/null || true
else
	log "No Intel/AMD GPU detected; set kld_list manually for your GPU (see: pkg info -D drm-kmod)"
fi

# 3. Minimal services.
log "Enabling seatd and dbus"
priv sysrc seatd_enable=YES
priv sysrc dbus_enable=YES
priv service seatd start || true
priv service dbus start || true

# 4. Group membership. FreeBSD seatd grants access via the `video` group
# (it owns /var/run/seatd.sock); `video` also gates GPU/DRM access. There is
# no `seat` group on FreeBSD (that is a systemd-logind concept).
log "Adding $USER_NAME to the video group (seatd + GPU access)"
priv pw groupmod video -m "$USER_NAME"

# 5. Privilege escalation. The "Update > FreeBSD" menu entry
# (omarchy-update-freebsd) and everyday admin use doas; install it and grant the
# install user a persist rule so `pkg upgrade` prompts for their own password.
# Skipped when installing as root (there is no unprivileged user to grant).
if [ "$USER_NAME" != "root" ]; then
	log "Installing and configuring doas for $USER_NAME"
	priv pkg install -y doas
	DOAS_CONF=/usr/local/etc/doas.conf
	DOAS_RULE="permit persist $USER_NAME as root"
	if ! { [ -f "$DOAS_CONF" ] && grep -qF "$DOAS_RULE" "$DOAS_CONF"; }; then
		printf '%s\n' "$DOAS_RULE" | priv tee -a "$DOAS_CONF" >/dev/null
	fi
	# The GUI power menu (suspend/reboot/shutdown) runs with no controlling
	# terminal, so a password prompt cannot be answered. Grant passwordless doas
	# for just those power commands (this mirrors what polkit allows a local
	# desktop session on Linux). More specific "cmd" rules must come last so
	# doas's last-match-wins evaluation prefers them over the persist rule above.
	for pc in "shutdown" "acpiconf"; do
		NP_RULE="permit nopass $USER_NAME as root cmd $pc"
		if ! { [ -f "$DOAS_CONF" ] && grep -qF "$NP_RULE" "$DOAS_CONF"; }; then
			printf '%s\n' "$NP_RULE" | priv tee -a "$DOAS_CONF" >/dev/null
		fi
	done
	priv chown root:wheel "$DOAS_CONF"
	priv chmod 0644 "$DOAS_CONF"
	# The security/doas package ships no PAM policy; without it PAM hits the
	# default-deny "other" rule and every auth fails. Point doas at the system
	# password stack so it authenticates against the user's own password.
	DOAS_PAM=/usr/local/etc/pam.d/doas
	if [ ! -f "$DOAS_PAM" ]; then
		printf 'auth\t\tinclude\t\tsystem\naccount\t\tinclude\t\tsystem\nsession\t\tinclude\t\tsystem\npassword\tinclude\t\tsystem\n' |
			priv tee "$DOAS_PAM" >/dev/null
		priv chown root:wheel "$DOAS_PAM"
		priv chmod 0644 "$DOAS_PAM"
	fi
fi

# Make bash the login shell so the terminal loads Omarchy's bash config (aliases
# like `ls` -> eza --icons, the prompt, etc.); FreeBSD's default /bin/sh never
# does. omarchy-setup writes the ~/.bashrc that sources Omarchy's bashrc.
if [ "$USER_NAME" != "root" ] && command -v bash >/dev/null 2>&1; then
	BASH_BIN="$(command -v bash)"
	grep -qxF "$BASH_BIN" /etc/shells 2>/dev/null ||
		printf '%s\n' "$BASH_BIN" | priv tee -a /etc/shells >/dev/null
	if [ "$(getent passwd "$USER_NAME" | awk -F: '{print $NF}')" != "$BASH_BIN" ]; then
		log "Setting $USER_NAME login shell to bash"
		priv pw usermod "$USER_NAME" -s "$BASH_BIN"
	fi
fi

# 6. FreeBSD helper overrides. Install our reimplementations of wholly
# Linux-specific omarchy-* helpers (network status, wifi restart, ...) to a
# share dir; omarchy-setup copies them over the clone after cloning/resetting.
OVR_SRC="$(dirname "$0")/../overrides"
OVR_DST=/usr/local/share/omarchy-freebsd/overrides
if [ -d "$OVR_SRC/bin" ]; then
	log "Installing FreeBSD helper overrides to $OVR_DST"
	priv mkdir -p "$OVR_DST/bin"
	priv cp "$OVR_SRC"/bin/* "$OVR_DST/bin/"
	priv chmod +x "$OVR_DST"/bin/*
fi

# 7. Dotfiles: reuse omarchy-setup if the port installed it, else run it inline.
if command -v omarchy-setup >/dev/null 2>&1; then
	OMARCHY_BRANCH="$OMARCHY_BRANCH" omarchy-setup
else
	log "Running bundled omarchy-setup"
	OMARCHY_BRANCH="$OMARCHY_BRANCH" sh "$(dirname "$0")/../scripts/omarchy-setup"
fi

# 7. Provide the launcher on the default login PATH if the port did not install
# it. ~/.local/bin is NOT on FreeBSD's default PATH, so the user-typed entry
# point must live in /usr/local/bin (the shims it needs stay in ~/.local/bin,
# which omarchy-session prepends to PATH itself).
if ! command -v omarchy-session >/dev/null 2>&1 && [ ! -x /usr/local/bin/omarchy-session ]; then
	priv cp "$(dirname "$0")/../scripts/omarchy-session" /usr/local/bin/omarchy-session
	priv chmod +x /usr/local/bin/omarchy-session
	log "Installed omarchy-session to /usr/local/bin"
fi

# FreeBSD system-update helper backing the menu's "Update > FreeBSD" entry.
if [ ! -x /usr/local/bin/omarchy-update-freebsd ]; then
	priv cp "$(dirname "$0")/../scripts/omarchy-update-freebsd" /usr/local/bin/omarchy-update-freebsd
	priv chmod +x /usr/local/bin/omarchy-update-freebsd
	log "Installed omarchy-update-freebsd to /usr/local/bin"
fi

# FreeBSD pkg install/remove helpers backing the menu's Package entries, the
# wpa_supplicant wifi selector, the tailscale setup entry, the ports/src tree
# bootstrappers, plus the porting audit tool.
for helper in omarchy-pkg-install-freebsd omarchy-pkg-remove-freebsd omarchy-wifi-freebsd \
	omarchy-setup-network-tailscale omarchy-setup-freebsd-src omarchy-setup-freebsd-ports omarchy-doctor-freebsd; do
	if [ ! -x "/usr/local/bin/$helper" ]; then
		priv cp "$(dirname "$0")/../scripts/$helper" "/usr/local/bin/$helper"
		priv chmod +x "/usr/local/bin/$helper"
		log "Installed $helper to /usr/local/bin"
	fi
done

log "Done. Log out/in for group changes, then run: omarchy-session"
