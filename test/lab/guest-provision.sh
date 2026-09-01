#!/bin/sh
# guest-provision.sh — one-time SSH bootstrap for the physical FreeBSD laptop.
#
# Run once on the laptop console (or re-run any time). It authorizes the host's
# lab_key for root and enables key-based SSH so all further work happens over
# `ssh` from the host Mac.
#
# The host serves this dir over HTTP (see `lab.sh serve`). Set KEY_URL to the
# host's LAN IP:port, e.g.
#   KEY_URL=http://<host-ip>:8000/lab_key.pub sh gp.sh
set -eu

: "${KEY_URL:?set KEY_URL to the lab_key.pub URL, e.g. KEY_URL=http://HOST_IP:8000/lab_key.pub}"

echo "==> Installing authorized_keys from $KEY_URL"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
fetch -qo /root/.ssh/authorized_keys "$KEY_URL"
chmod 600 /root/.ssh/authorized_keys

echo "==> Enabling key-based root SSH"
sysrc sshd_enable=YES
# Default sshd_config ships "#PermitRootLogin no" (commented), so an appended
# active directive takes effect; keep it key-only (no passwords over the wire).
if ! grep -q '^PermitRootLogin prohibit-password' /etc/ssh/sshd_config; then
	echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config
fi
service sshd start 2>/dev/null || service sshd restart

echo "==> Recording pristine package baseline -> /root/.omarchy-baseline-pkgs"
# A vanilla box has no packages; capture whatever is present (likely empty) so
# `lab.sh rollback` can delete anything installed after this point.
if pkg -N >/dev/null 2>&1; then
	pkg query %n | sort > /root/.omarchy-baseline-pkgs
else
	: > /root/.omarchy-baseline-pkgs
fi

echo "==> SSH ready. From the host run:  ./lab.sh ssh"
