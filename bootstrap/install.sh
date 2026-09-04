#!/bin/sh
#
# install.sh — bootstrap Omarchy on FreeBSD from a fresh install, no ports
# tree or GitHub release required up front.
#
# This is a thin orchestrator: every package dependency and every installed
# script lives in port/x11-wm/omarchy/Makefile (RUN_DEPENDS + do-install) --
# nowhere else. This script just (1) does the OS-level prep a port can never
# do for itself, (2) makes sure a ports tree exists, (3) builds a distfile
# from THIS working tree (so local/uncommitted changes install exactly like
# a real port, without needing a cut release tag), and (4) runs the dotfile
# setup.
#
# Run as root, or as a regular user with doas already installed and configured,
# from a fresh FreeBSD install:
#     sh install.sh
#
# Environment overrides:
#   OMARCHY_BRANCH  Omarchy branch (default: quattro)

set -eu

OMARCHY_BRANCH="${OMARCHY_BRANCH:-quattro}"
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$DIR")"
PORT_DIR=/usr/ports/x11-wm/omarchy

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

# 1. OS-level prerequisites (pkg repo, GPU/drm-kmod, seatd/dbus, video group,
# doas) -- none of this is a package, so a port cannot do it.
log "Preparing the system"
sh "$DIR/prepare-system.sh"

# 2. A GH_ACCOUNT-sourced port fetches its distfile via bsd.port.mk, which
# lives in the ports tree's Mk/ infrastructure. Reuse the same helper the
# Setup > FreeBSD > Ports menu action installs (idempotent: no-op if
# /usr/ports is already a git checkout).
log "Ensuring /usr/ports exists"
sh "$DIR/../scripts/omarchy-setup-freebsd-ports"

# 3. Stage our port into the tree (always overwritten -- it is not tracked by
# the tree's own git history) and build a distfile straight from this
# checkout, so uncommitted/local changes install exactly like a tagged
# release would, without needing to cut one. NO_CHECKSUM=yes below skips
# verifying it against distinfo, which only carries real checksums once a
# release has actually been tagged and `make makesum` has been run.
log "Staging the port into $PORT_DIR"
priv rm -rf "$PORT_DIR"
priv mkdir -p "$PORT_DIR"
priv sh -c "cp -R '$REPO/port/x11-wm/omarchy/.' '$PORT_DIR/'"

# DISTFILES is the exact filename expected in DISTDIR; WRKSRC's basename is
# the directory name the tarball must extract into. For USE_GITHUB these are
# NOT the same string (DISTFILES carries the GH_TUPLE-style name, e.g.
# klimb-freebsd-omarchy-v0.1.0_GH0.tar.gz, while WRKSRC is
# ${GH_PROJECT}-${PORTVERSION}, e.g. freebsd-omarchy-0.1.0) -- ask make for
# both rather than assuming either.
DISTFILES=$(make -C "$PORT_DIR" -V DISTFILES)
DISTDIR=$(make -C "$PORT_DIR" -V DISTDIR)
WRKSRC_NAME=$(basename "$(make -C "$PORT_DIR" -V WRKSRC)")
log "Building distfile $DISTFILES from the working tree"
TMP=$(mktemp -d)
mkdir -p "$TMP/$WRKSRC_NAME"
tar --exclude=./test --exclude=./.git -C "$REPO" -cf - . | tar -C "$TMP/$WRKSRC_NAME" -xf -
tar -C "$TMP" -czf "$TMP.tar.gz" "$WRKSRC_NAME"
priv mkdir -p "$DISTDIR"
priv cp "$TMP.tar.gz" "$DISTDIR/$DISTFILES"
rm -rf "$TMP" "$TMP.tar.gz"

# 4. Build + install: pulls every RUN_DEPENDS package and runs do-install
# (every script in scripts/ + overrides/bin/). BATCH=yes accepts
# OPTIONS_DEFAULT without a dialog. `reinstall` (not `install`) so re-running
# this script after local edits works -- plain `install` refuses outright
# once omarchy is already registered.
log "Building and installing the port"
priv env BATCH=yes NO_CHECKSUM=yes make -C "$PORT_DIR" reinstall clean

# 5. Dotfiles: clone Omarchy and apply the FreeBSD adaptations. Installed to
# PATH by the port's do-install above.
log "Running omarchy-setup"
OMARCHY_BRANCH="$OMARCHY_BRANCH" omarchy-setup

# 6. Make bash the login shell so the terminal loads Omarchy's bash config
# (aliases like `ls` -> eza --icons, the prompt, etc.); FreeBSD's default
# /bin/sh never does. Only possible now that bash (a RUN_DEPENDS) is
# actually installed.
if [ "$USER_NAME" != "root" ] && command -v bash >/dev/null 2>&1; then
	BASH_BIN="$(command -v bash)"
	grep -qxF "$BASH_BIN" /etc/shells 2>/dev/null ||
		printf '%s\n' "$BASH_BIN" | priv tee -a /etc/shells >/dev/null
	if [ "$(getent passwd "$USER_NAME" | awk -F: '{print $NF}')" != "$BASH_BIN" ]; then
		log "Setting $USER_NAME login shell to bash"
		priv pw usermod "$USER_NAME" -s "$BASH_BIN"
	fi
fi

log "Done. Log out/in for group changes, then run: omg"

