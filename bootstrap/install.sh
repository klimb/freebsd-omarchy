#!/bin/sh
#
# install.sh — standalone bootstrap for Omarchy on FreeBSD, for people who do
# not want to use the x11-wm/omarchy port. Installs packages, enables the
# minimal services, fixes group membership, and runs the dotfile setup.
#
# Run as a regular user with sudo/doas available, from a fresh FreeBSD install:
#     sh install.sh
#
# Environment overrides:
#   OMARCHY_BRANCH  Omarchy branch (default: quattro)
#   SUDO            privilege escalation command (default: autodetected)

set -eu

OMARCHY_BRANCH="${OMARCHY_BRANCH:-quattro}"

# Pick a privilege escalation tool for the root-only steps.
if [ "$(id -u)" -eq 0 ]; then
	SUDO="${SUDO:-}"
elif command -v doas >/dev/null 2>&1; then
	SUDO="${SUDO:-doas}"
elif command -v sudo >/dev/null 2>&1; then
	SUDO="${SUDO:-sudo}"
else
	echo "error: need root, sudo, or doas to install packages" >&2
	exit 1
fi

USER_NAME="$(id -un)"

log() { printf '==> %s\n' "$*"; }

# 0. Switch the FreeBSD package repo from the default "quarterly" branch to
# "latest". "latest" tracks the ports tree continuously, so it carries far more
# (and newer) packages than the frozen quarterly snapshot. This also flips the
# FreeBSD-kmods repo (kmods_quarterly_* -> kmods_latest_*) for newer drm-kmod.
# Edit the base config in place, then force-refresh the repo catalogue.
if [ -f /etc/pkg/FreeBSD.conf ] && grep -q 'quarterly' /etc/pkg/FreeBSD.conf; then
	log "Switching pkg repo from 'quarterly' to 'latest'"
	$SUDO sed -i '' -e 's|quarterly|latest|g' /etc/pkg/FreeBSD.conf
	$SUDO pkg update -f
fi

# 1. System packages. Origins map to the pkg names FreeBSD ships.
# bash is required (every omarchy-* helper is #!/bin/bash); socat and
# xdg-terminal-exec back the launch/monitor helpers; vips (vipsthumbnail) backs
# the theme/image picker; figlet renders the FreeBSD presentation banner;
# chromium is Omarchy's browser (webapps launch in its --app mode);
# emacs-wayland is the preferred (Wayland-native) editor; hyprlock is the screen
# locker (Omarchy's QuickShell lock can't PAM-auth as non-root on FreeBSD).
PKGS="hyprland seatd bash foot alacritty pipewire wireplumber wl-clipboard grim slurp \
hyprpicker xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-terminal-exec socat \
starship zoxide fzf bat eza fd-find ripgrep jq btop lazygit tmux neovim imv git vips figlet gawk lua54 \
noto-basic nerd-fonts font-awesome dbus py312-terminaltexteffects cmatrix \
ImageMagick7 mpv wf-recorder ffmpeg pamixer fastfetch wtype unzip libqrencode gnome-keyring bash-completion chromium emacs-wayland hyprlock"

log "Installing packages"
$SUDO pkg install -y $PKGS

# QuickShell (Omarchy top bar) may not be packaged; try, but do not fail.
if ! $SUDO pkg install -y quickshell 2>/dev/null; then
	log "quickshell package not available; install waybar as a fallback"
	$SUDO pkg install -y waybar || true
fi

# 2. GPU/DRM kernel module. Wayland compositors (Hyprland/Aquamarine) need a
# DRM render node (/dev/dri/*), which only exists once the KMS driver is
# loaded. FreeBSD ships these out-of-tree in drm-kmod; pick the module for the
# installed GPU and load it now + at boot.
log "Installing DRM kernel module (drm-kmod)"
$SUDO pkg install -y drm-kmod
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
	$SUDO sysrc kld_list+="$KMS"
	$SUDO kldload "$KMS" 2>/dev/null || true
else
	log "No Intel/AMD GPU detected; set kld_list manually for your GPU (see: pkg info -D drm-kmod)"
fi

# 3. Minimal services.
log "Enabling seatd and dbus"
$SUDO sysrc seatd_enable=YES
$SUDO sysrc dbus_enable=YES
$SUDO service seatd start || true
$SUDO service dbus start || true

# 4. Group membership. FreeBSD seatd grants access via the `video` group
# (it owns /var/run/seatd.sock); `video` also gates GPU/DRM access. There is
# no `seat` group on FreeBSD (that is a systemd-logind concept).
log "Adding $USER_NAME to the video group (seatd + GPU access)"
$SUDO pw groupmod video -m "$USER_NAME"

# 5. Privilege escalation. The "Update > FreeBSD" menu entry
# (omarchy-update-freebsd) and everyday admin use doas; install it and grant the
# install user a persist rule so `pkg upgrade` prompts for their own password.
# Skipped when installing as root (there is no unprivileged user to grant).
if [ "$USER_NAME" != "root" ]; then
	log "Installing and configuring doas for $USER_NAME"
	$SUDO pkg install -y doas
	DOAS_CONF=/usr/local/etc/doas.conf
	DOAS_RULE="permit persist $USER_NAME as root"
	if ! { [ -f "$DOAS_CONF" ] && grep -qF "$DOAS_RULE" "$DOAS_CONF"; }; then
		printf '%s\n' "$DOAS_RULE" | $SUDO tee -a "$DOAS_CONF" >/dev/null
	fi
	# The GUI power menu (suspend/reboot/shutdown) runs with no controlling
	# terminal, so a password prompt cannot be answered. Grant passwordless doas
	# for just those power commands (this mirrors what polkit allows a local
	# desktop session on Linux). More specific "cmd" rules must come last so
	# doas's last-match-wins evaluation prefers them over the persist rule above.
	for pc in "shutdown" "acpiconf"; do
		NP_RULE="permit nopass $USER_NAME as root cmd $pc"
		if ! { [ -f "$DOAS_CONF" ] && grep -qF "$NP_RULE" "$DOAS_CONF"; }; then
			printf '%s\n' "$NP_RULE" | $SUDO tee -a "$DOAS_CONF" >/dev/null
		fi
	done
	$SUDO chown root:wheel "$DOAS_CONF"
	$SUDO chmod 0644 "$DOAS_CONF"
	# The security/doas package ships no PAM policy; without it PAM hits the
	# default-deny "other" rule and every auth fails. Point doas at the system
	# password stack so it authenticates against the user's own password.
	DOAS_PAM=/usr/local/etc/pam.d/doas
	if [ ! -f "$DOAS_PAM" ]; then
		printf 'auth\t\tinclude\t\tsystem\naccount\t\tinclude\t\tsystem\nsession\t\tinclude\t\tsystem\npassword\tinclude\t\tsystem\n' |
			$SUDO tee "$DOAS_PAM" >/dev/null
		$SUDO chown root:wheel "$DOAS_PAM"
		$SUDO chmod 0644 "$DOAS_PAM"
	fi
fi

# Make bash the login shell so the terminal loads Omarchy's bash config (aliases
# like `ls` -> eza --icons, the prompt, etc.); FreeBSD's default /bin/sh never
# does. omarchy-setup writes the ~/.bashrc that sources Omarchy's bashrc.
if [ "$USER_NAME" != "root" ] && command -v bash >/dev/null 2>&1; then
	BASH_BIN="$(command -v bash)"
	grep -qxF "$BASH_BIN" /etc/shells 2>/dev/null ||
		printf '%s\n' "$BASH_BIN" | $SUDO tee -a /etc/shells >/dev/null
	if [ "$(getent passwd "$USER_NAME" | awk -F: '{print $NF}')" != "$BASH_BIN" ]; then
		log "Setting $USER_NAME login shell to bash"
		$SUDO pw usermod "$USER_NAME" -s "$BASH_BIN"
	fi
fi

# 6. FreeBSD helper overrides. Install our reimplementations of wholly
# Linux-specific omarchy-* helpers (network status, wifi restart, ...) to a
# share dir; omarchy-setup copies them over the clone after cloning/resetting.
OVR_SRC="$(dirname "$0")/../overrides"
OVR_DST=/usr/local/share/omarchy-freebsd/overrides
if [ -d "$OVR_SRC/bin" ]; then
	log "Installing FreeBSD helper overrides to $OVR_DST"
	$SUDO mkdir -p "$OVR_DST/bin"
	$SUDO cp "$OVR_SRC"/bin/* "$OVR_DST/bin/"
	$SUDO chmod +x "$OVR_DST"/bin/*
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
	$SUDO cp "$(dirname "$0")/../scripts/omarchy-session" /usr/local/bin/omarchy-session
	$SUDO chmod +x /usr/local/bin/omarchy-session
	log "Installed omarchy-session to /usr/local/bin"
fi

# FreeBSD system-update helper backing the menu's "Update > FreeBSD" entry.
if [ ! -x /usr/local/bin/omarchy-update-freebsd ]; then
	$SUDO cp "$(dirname "$0")/../scripts/omarchy-update-freebsd" /usr/local/bin/omarchy-update-freebsd
	$SUDO chmod +x /usr/local/bin/omarchy-update-freebsd
	log "Installed omarchy-update-freebsd to /usr/local/bin"
fi

# FreeBSD pkg install/remove helpers backing the menu's Package entries, the
# wpa_supplicant wifi selector, plus the porting audit tool.
for helper in omarchy-pkg-install-freebsd omarchy-pkg-remove-freebsd omarchy-wifi-freebsd omarchy-doctor-freebsd; do
	if [ ! -x "/usr/local/bin/$helper" ]; then
		$SUDO cp "$(dirname "$0")/../scripts/$helper" "/usr/local/bin/$helper"
		$SUDO chmod +x "/usr/local/bin/$helper"
		log "Installed $helper to /usr/local/bin"
	fi
done

log "Done. Log out/in for group changes, then run: omarchy-session"
