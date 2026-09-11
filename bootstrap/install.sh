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

# doas may not exist yet on a fresh box; prepare-system.sh below installs and
# configures it via a one-time `su` bootstrap. priv() is only ever called
# after that step returns, so it will always find doas here.
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

# 4. Pre-install every RUN_DEPENDS from the binary pkg repo. FreeBSD's ports
# tree defaults to building missing deps from source; USE_PACKAGE_DEPENDS_ONLY
# only looks for pre-built local .pkg files in /usr/ports/packages/. Neither
# does what we want (grab prebuilt binaries from pkg.FreeBSD.org).
#
# CRITICAL: install by pkg NAME not by origin. Some FreeBSD ports produce
# multiple package flavors from a single origin (e.g. multimedia/ffmpeg
# produces BOTH `ffmpeg` (with X11) and `ffmpeg-nox11`, both conflicting on
# /usr/local/bin/ffmpeg). Passing `pkg install multimedia/ffmpeg` lets pkg
# pick either flavor -- if it picks nox11 but another dep needs the x11 one,
# pkg's SAT solver drops both AND every transitive dependent (hyprland,
# quickshell, nautilus, mpv, ...) silently. `make install` then descends
# into each dropped port and starts a source build -- exactly what we don't
# want. Passing pkg NAMES lets the solver resolve flavors correctly.
#
# Extract the pkg name from each RUN_DEPENDS entry `<check>:<origin>`.
# In FreeBSD ports RUN_DEPENDS syntax, <check> is a binary/path check UNLESS
# it embeds a version constraint (`pkg>0`, `pkg>=1.2`, etc.), in which case
# the substring before the operator IS the real pkg name. For a binary check
# the LHS is often NOT the pkg name (e.g. `rg:textproc/ripgrep`,
# `nvim:editors/neovim`, `wl-copy:x11/wl-clipboard`), so fall back to the
# origin's basename -- matches the actual pkg name for the vast majority of
# ports and is unambiguous for pkg's SAT solver.
log "Installing RUN_DEPENDS from binary pkg repo"
DEPS=$(make -C "$PORT_DIR" -V RUN_DEPENDS -V BUILD_DEPENDS -V LIB_DEPENDS \
	| tr ' ' '\n' \
	| awk -F: '
		NF>=2 && $2 ~ /^[a-zA-Z0-9_-]+\/[a-zA-Z0-9._@-]+$/ {
			if ($1 ~ /[<>=]/) {
				split($1, a, /[<>=]/)
				print a[1]
			} else {
				# strip @flavor before taking origin basename
				sub(/@.*$/, "", $2)
				n = split($2, b, "/")
				print b[n]
			}
		}' \
	| sort -u)
# shellcheck disable=SC2086
priv pkg install -y $DEPS

# pkg install's SAT solver silently DROPS packages when it hits a conflict
# (e.g. ffmpeg vs ffmpeg-nox11, git vs git-lite vs git-tiny -- all flavors
# of the same origin, mutually exclusive on /usr/local/bin/*). Whatever it
# drops then falls out of the "installed" set entirely. If we let `make
# install` on our port proceed at that point, it will descend into the
# dropped port's dir and BUILD IT FROM SOURCE -- a hard no. Verify every
# expected pkg name is now present; retry any drops one-by-one (individual
# pkg install has less to solve for and picks the right variant); fail
# hard if any are still missing so the user sees the real problem instead
# of hours of cc(1).
verify_installed() {
	MISSING=""
	for name in $DEPS; do
		pkg info -e "$name" >/dev/null 2>&1 || MISSING="$MISSING $name"
	done
}
verify_installed
if [ -n "$MISSING" ]; then
	log "pkg dropped some deps silently; retrying individually:$MISSING"
	for name in $MISSING; do
		priv pkg install -y "$name" || true
	done
	verify_installed
fi
if [ -n "$MISSING" ]; then
	echo "error: these packages could not be installed from the binary" >&2
	echo "repo (would trigger a source build; aborting):" >&2
	printf '  %s\n' $MISSING >&2
	exit 1
fi

# Some pkg post-install scripts (fontconfig, gsettings-desktop-schemas,
# gdk-pixbuf, ...) touch $HOME/.cache while running as root. On a stock
# fresh box with our own doas.conf that is harmless (doas resets $HOME to
# root's), but if the invoking user's doas rule uses `keepenv` those scripts
# see $HOME=/home/$USER and end up creating $HOME/.cache with root:$USER
# ownership -- which then breaks starship, emacs, chromium, etc. at first
# login with "cannot create cache dir: permission denied". Reclaim ownership
# of the common user cache/config roots defensively.
if [ "$USER_NAME" != "root" ]; then
	for d in .cache .local .config; do
		if [ -e "$HOME/$d" ] && [ "$(stat -f %Su "$HOME/$d")" != "$USER_NAME" ]; then
			log "Fixing ownership of $HOME/$d (created as root by pkg post-install)"
			priv chown -R "$USER_NAME:$USER_NAME" "$HOME/$d"
		fi
	done
fi

# 5. Build + install our port: no deps to fetch anymore, so this is just
# extract + do-install (every script in scripts/ + overrides/bin/).
# BATCH=yes accepts OPTIONS_DEFAULT without a dialog. `reinstall` (not
# `install`) so re-running this script after local edits works -- plain
# `install` refuses outright once omarchy is already registered.
log "Building and installing the port"
priv env BATCH=yes NO_CHECKSUM=yes make -C "$PORT_DIR" reinstall clean

# 6. Dotfiles: clone Omarchy and apply the FreeBSD adaptations. Installed to
# PATH by the port's do-install above.
log "Running omarchy-setup"
OMARCHY_BRANCH="$OMARCHY_BRANCH" omarchy-setup

# 7. Make bash the login shell so the terminal loads Omarchy's bash config
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

