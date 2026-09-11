#!/bin/sh
#
# prepare-system.sh — FreeBSD system prerequisites a port can never do for
# itself (pkg-plist installs files; it cannot flip rc.conf, load a kernel
# module, change a user's group or login shell, or write doas.conf). Run this
# once, then install the omarchy port (bootstrap/install.sh does both).
#
# Run as root, or as a regular wheel user. Vanilla FreeBSD has no doas
# installed; when run as a non-root wheel user without doas, this script
# bootstraps doas via `su` (prompts once for the root password), then uses
# doas for every subsequent privileged step.
#
# Environment overrides: none.

set -eu

USER_NAME="$(id -un)"

log() { printf '==> %s\n' "$*"; }

# Bootstrap doas on a fresh box. Vanilla FreeBSD ships neither doas nor sudo,
# and doas has no PAM policy of its own -- without pam.d/doas every auth hits
# PAM's default-deny "other" rule and fails. Do the minimum here (install
# binary, write PAM policy, drop a permit-persist rule for USER_NAME) via a
# single su -- root sh; the full doas config (nopass shutdown/acpiconf, ownership
# fixups) still runs later in step 4 below. Requires USER_NAME to be in wheel
# (FreeBSD's PAM restricts `su` to wheel members).
if [ "$(id -u)" -ne 0 ] && ! command -v doas >/dev/null 2>&1; then
	log "No doas found; bootstrapping via su (enter root password when prompted)"
	su - root <<EOSU
set -eu
pkg install -y doas
mkdir -p /usr/local/etc/pam.d
if [ ! -f /usr/local/etc/pam.d/doas ]; then
	printf 'auth\t\tinclude\t\tsystem\naccount\t\tinclude\t\tsystem\nsession\t\tinclude\t\tsystem\npassword\tinclude\t\tsystem\n' > /usr/local/etc/pam.d/doas
	chown root:wheel /usr/local/etc/pam.d/doas
	chmod 0644 /usr/local/etc/pam.d/doas
fi
if ! grep -qF 'permit persist $USER_NAME as root' /usr/local/etc/doas.conf 2>/dev/null; then
	printf 'permit persist %s as root\n' '$USER_NAME' >> /usr/local/etc/doas.conf
	chown root:wheel /usr/local/etc/doas.conf
	chmod 0644 /usr/local/etc/doas.conf
fi
EOSU
fi

if [ "$(id -u)" -ne 0 ] && ! command -v doas >/dev/null 2>&1; then
	echo "error: doas bootstrap failed; is $USER_NAME in the wheel group?" >&2
	exit 1
fi
priv() {
	if [ "$(id -u)" -eq 0 ]; then "$@"
	else doas "$@"; fi
}

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

# 1. GPU/DRM kernel module. Wayland compositors (Hyprland/Aquamarine) need a
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

# 2. Minimal services.
log "Enabling seatd and dbus"
priv sysrc seatd_enable=YES
priv sysrc dbus_enable=YES
priv service seatd start || true
priv service dbus start || true

# 3. Group membership. FreeBSD seatd grants access via the `video` group
# (it owns /var/run/seatd.sock); `video` also gates GPU/DRM access. There is
# no `seat` group on FreeBSD (that is a systemd-logind concept).
log "Adding $USER_NAME to the video group (seatd + GPU access)"
priv pw groupmod video -m "$USER_NAME"

# 4. Privilege escalation. The "Update > FreeBSD" menu entry
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
		priv mkdir -p "$(dirname "$DOAS_PAM")"
		printf 'auth\t\tinclude\t\tsystem\naccount\t\tinclude\t\tsystem\nsession\t\tinclude\t\tsystem\npassword\tinclude\t\tsystem\n' |
			priv tee "$DOAS_PAM" >/dev/null
		priv chown root:wheel "$DOAS_PAM"
		priv chmod 0644 "$DOAS_PAM"
	fi
fi

log "System prepared. Next: install the omarchy port (bootstrap/install.sh does this)."
