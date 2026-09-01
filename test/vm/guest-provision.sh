#!/bin/sh
# guest-provision.sh — idempotent first-boot setup for the blank FreeBSD VM.
#
# Run once on the guest console (or re-run any time). It enables key-based SSH
# so the rest of provisioning happens over `ssh -p 2222` from the host.
#
# The host serves this dir over HTTP; the guest reaches the host at 10.0.2.2
# (QEMU user-mode networking). Override KEY_URL to point elsewhere.
set -eu

: "${KEY_URL:=http://10.0.2.2:8000/vm_key.pub}"

echo "==> Installing authorized_keys from $KEY_URL"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
fetch -qo /root/.ssh/authorized_keys "$KEY_URL"
chmod 600 /root/.ssh/authorized_keys

echo "==> Enabling key-based root SSH"
sysrc sshd_enable=YES
# Default sshd_config ships "#PermitRootLogin no" (commented), so an appended
# active directive takes effect; keep it key-only.
if ! grep -q '^PermitRootLogin prohibit-password' /etc/ssh/sshd_config; then
	echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config
fi
service sshd start 2>/dev/null || service sshd restart

echo "==> SSH ready. From the host run:"
echo "    ssh -i vm_key -p 2222 root@127.0.0.1"
