#!/bin/sh
# vm.sh — orchestrate the FreeBSD 15.1 test VM reproducibly.
#
# Subcommands:
#   boot [serial|gui]  Boot the VM (serial console by default).
#   serve              Serve this dir over HTTP for the guest bootstrap fetch.
#   bootstrap-hint     Print the one-line command to run on the guest console.
#   ssh [args...]      SSH into the VM as root (key-based).
#   sync               Push the freebsd-omarchy repo into the VM (tar over SSH).
#   install            Run the repo's bootstrap installer inside the VM.
#   provision          sync + install in one go.
#
# Prereqs: ./run.sh, vm_key(.pub) present; guest-provision.sh already run once
# on the console to enable SSH.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(dirname "$(dirname "$DIR")")}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_OPTS="-i $DIR/vm_key -p $SSH_PORT \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=$DIR/known_hosts"

cmd="${1:-}"
[ $# -gt 0 ] && shift || true

case "$cmd" in
boot)
	exec "$DIR/run.sh" "${1:-serial}"
	;;
serve)
	pgrep -f 'http.server 8000' >/dev/null 2>&1 && { echo "already serving"; exit 0; }
	cd "$DIR" && exec python3 -m http.server 8000 --bind 127.0.0.1
	;;
bootstrap-hint)
	echo "On the guest console, run:"
	echo "  fetch -o /tmp/gp.sh http://10.0.2.2:8000/guest-provision.sh && sh /tmp/gp.sh"
	;;
ssh)
	# shellcheck disable=SC2086
	exec ssh $SSH_OPTS root@127.0.0.1 "$@"
	;;
sync)
	echo "==> Pushing $REPO -> VM:/root/freebsd-omarchy"
	# --no-mac-metadata/--no-xattrs: keep macOS com.apple.* xattrs out of the
	# tar stream so bsdtar on the guest does not error restoring them.
	# Exclude test/ (disk images + lab secrets live here) and .git from the push.
	# shellcheck disable=SC2086
	COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs \
		--exclude=./test --exclude=./.git -C "$REPO" -cf - . | ssh $SSH_OPTS root@127.0.0.1 \
		'rm -rf /root/freebsd-omarchy && mkdir -p /root/freebsd-omarchy && tar -C /root/freebsd-omarchy -xf -'
	echo "==> Done."
	;;
install)
	# shellcheck disable=SC2086
	exec ssh $SSH_OPTS root@127.0.0.1 'sh /root/freebsd-omarchy/bootstrap/install.sh'
	;;
provision)
	"$0" sync
	"$0" install
	;;
*)
	sed -n '2,20p' "$0"
	exit 1
	;;
esac
