#!/bin/sh
# lab.sh — orchestrate the physical FreeBSD 15.1 test laptop over the LAN.
#
# Subcommands:
#   serve              Serve this dir over HTTP so the laptop can fetch lab_key.
#   bootstrap-hint     Print the one-line command to run on the laptop console.
#   ssh [args...]      SSH into the laptop as root (key-based).
#   sync               Push the freebsd-omarchy repo into the laptop (tar over SSH).
#   install            Run the repo's bootstrap installer on the laptop.
#   provision          sync + install in one go.
#   baseline           (Re)record the current package set as the vanilla baseline.
#   rollback           Delete every package added since the baseline; pkg autoremove.
#
# Config via env: HOST (laptop IP), HOST_IP (this Mac's LAN IP for `serve`).
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(dirname "$(dirname "$DIR")")}"
HOST="${HOST:-}"       # test laptop IP — required (export HOST=...)
HOST_IP="${HOST_IP:-}"  # this machine's LAN IP for `serve` — required for serve/bootstrap-hint
SSH_OPTS="-i $DIR/lab_key \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=$DIR/known_hosts"

cmd="${1:-}"
[ $# -gt 0 ] && shift || true

# Fail early with a helpful message when a required address is not configured.
case "$cmd" in
serve|bootstrap-hint)
	: "${HOST_IP:?set HOST_IP to this machine's LAN IP, e.g. HOST_IP=192.0.2.10}" ;;
ssh|sync|install|provision|baseline|rollback)
	: "${HOST:?set HOST to the test laptop's IP, e.g. HOST=192.0.2.20}" ;;
esac

case "$cmd" in
serve)
	pgrep -f 'http.server 8000' >/dev/null 2>&1 && { echo "already serving"; exit 0; }
	echo "Serving $DIR on http://$HOST_IP:8000 (Ctrl-C to stop)"
	cd "$DIR" && exec python3 -m http.server 8000 --bind 0.0.0.0
	;;
bootstrap-hint)
	echo "On the laptop console, run:"
	echo "  fetch -o /tmp/gp.sh http://$HOST_IP:8000/guest-provision.sh && sh /tmp/gp.sh"
	;;
ssh)
	# shellcheck disable=SC2086
	exec ssh $SSH_OPTS root@"$HOST" "$@"
	;;
sync)
	echo "==> Pushing $REPO -> $HOST:/root/freebsd-omarchy"
	# --no-mac-metadata/--no-xattrs: keep macOS com.apple.* xattrs out of the tar
	# stream so bsdtar on the guest does not error restoring them.
	# shellcheck disable=SC2086
	COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs \
		--exclude=./test --exclude=./.git -C "$REPO" -cf - . | ssh $SSH_OPTS root@"$HOST" \
		'rm -rf /root/freebsd-omarchy && mkdir -p /root/freebsd-omarchy && tar -C /root/freebsd-omarchy -xf -'
	echo "==> Done."
	;;
install)
	# shellcheck disable=SC2086
	exec ssh $SSH_OPTS root@"$HOST" 'sh /root/freebsd-omarchy/bootstrap/install.sh'
	;;
provision)
	"$0" sync
	"$0" install
	;;
baseline)
	# shellcheck disable=SC2086
	exec ssh $SSH_OPTS root@"$HOST" \
		'{ pkg -N >/dev/null 2>&1 && pkg query %n | sort || : ; } > /root/.omarchy-baseline-pkgs; \
		 echo "baseline: $(wc -l < /root/.omarchy-baseline-pkgs | tr -d " ") packages"'
	;;
rollback)
	echo "==> Rolling back $HOST to the recorded package baseline"
	# shellcheck disable=SC2086
	exec ssh $SSH_OPTS root@"$HOST" 'sh -s' <<-'EOSH'
		set -eu
		base=/root/.omarchy-baseline-pkgs
		[ -f "$base" ] || { echo "no baseline recorded; run ./lab.sh baseline first" >&2; exit 1; }
		if ! pkg -N >/dev/null 2>&1; then echo "no packages installed; already vanilla"; exit 0; fi
		cur=$(mktemp); pkg query %n | sort > "$cur"
		extra=$(comm -13 "$base" "$cur")
		rm -f "$cur"
		if [ -z "$extra" ]; then echo "no packages to remove"; else
			echo "removing:"; echo "$extra" | sed 's/^/  /'
			# shellcheck disable=SC2086
			pkg delete -y $extra
			pkg autoremove -y
		fi
	EOSH
	;;
*)
	sed -n '2,20p' "$0"
	exit 1
	;;
esac
