PORTNAME=	omarchy
DISTVERSIONPREFIX=	v
DISTVERSION=	0.1.0
CATEGORIES=	x11-wm wayland

MAINTAINER=	you@example.com
COMMENT=	Omarchy Hyprland desktop experience for FreeBSD
WWW=		https://github.com/omacom/omarchy

LICENSE=	MIT
LICENSE_FILE=	${WRKSRC}/LICENSE

# This is NOT a metaport: USES=metaport forces NO_INSTALL, but we ship a
# whole tree of omarchy-* helper scripts and FreeBSD overrides. So pull the
# deps via RUN_DEPENDS and install our own files with a custom do-install.
#
# bootstrap/install.sh (the standalone installer) drives this exact Makefile
# too -- RUN_DEPENDS and do-install below are the ONLY place package/script
# lists live. For local development (no cut release tag yet), install.sh
# builds its own distfile from the working tree and runs NO_CHECKSUM=yes
# make install; a real release just needs DISTVERSION bumped, a matching
# git tag pushed, and `make makesum` run to fill in distinfo.
USE_GITHUB=	yes
GH_ACCOUNT=	klimb
GH_PROJECT=	freebsd-omarchy

NO_BUILD=	yes
NO_ARCH=	yes
USES=		shebangfix
SHEBANG_FILES=	scripts/* overrides/bin/*

# Core desktop: compositor, seat/audio backend, terminal, portals, wl utils.
# bash is required: every omarchy-* helper is a #!/bin/bash script. socat and
# xdg-terminal-exec are used by the launch/monitor helpers. The Linux-compat
# shims (uwsm-app, setsid, systemd-cat, flock, base64) are written to the
# user's ~/.local/bin by omarchy-setup, not installed here.
# NOTE: verify every origin on the target box with `make search name=<pkg>`.
RUN_DEPENDS=	Hyprland:x11-wm/hyprland \
		hyprlock:x11/hyprlock \
		seatd:sysutils/seatd \
		bash:shells/bash \
		foot:x11/foot \
		xdg-terminal-exec:deskutils/xdg-terminal-exec \
		grim:x11/grim \
		slurp:x11/slurp \
		socat:net/socat \
		wl-copy:x11/wl-clipboard \
		hyprpicker:x11/hyprpicker \
		hyprsunset:accessibility/hyprsunset \
		xdg-desktop-portal-hyprland>0:x11/xdg-desktop-portal-hyprland \
		xdg-desktop-portal-gtk>0:x11/xdg-desktop-portal-gtk \
		xdg-open:devel/xdg-utils \
		nautilus:x11-fm/nautilus \
		ffmpegthumbnailer:multimedia/ffmpegthumbnailer \
		pipewire>0:multimedia/pipewire \
		wireplumber>0:multimedia/wireplumber \
		git:devel/git \
		tailscale:security/tailscale \
		gum:devel/gum

# Shell/CLI experience Omarchy expects.
RUN_DEPENDS+=	starship:shells/starship \
		fzf:textproc/fzf \
		bat:textproc/bat \
		eza:sysutils/eza \
		fd:sysutils/fd \
		rg:textproc/ripgrep \
		jq:textproc/jq \
		btop:sysutils/btop \
		zoxide:sysutils/zoxide \
		nvim:editors/neovim \
		emacs:editors/emacs@wayland \
		gdate:sysutils/coreutils

# Media + desktop utilities present in omarchy-base.packages, confirmed in ports.
# wf-recorder (wlr-screencopy) + ffmpeg back the video-only screen recording
# override that replaces the Linux-only gpu-screen-recorder.
RUN_DEPENDS+=	convert:graphics/ImageMagick7 \
		mpv:multimedia/mpv \
		wf-recorder:multimedia/wf-recorder \
		ffmpeg:multimedia/ffmpeg \
		pamixer:audio/pamixer \
		fastfetch:sysutils/fastfetch \
		wtype:x11/wtype \
		unzip:archivers/unzip \
		qrencode:graphics/libqrencode \
		gnome-keyring-daemon:security/gnome-keyring \
		bash-completion>0:shells/bash-completion

# Fonts for the Omarchy look.
RUN_DEPENDS+=	nerd-fonts>0:x11-fonts/nerd-fonts \
		noto-basic>0:x11-fonts/noto-basic \
		font-awesome>0:x11-fonts/font-awesome

OPTIONS_DEFINE=		QUICKSHELL WAYBAR ALACRITTY IMV CHROMIUM
OPTIONS_DEFAULT=	QUICKSHELL ALACRITTY IMV CHROMIUM
QUICKSHELL_DESC=	Omarchy QML top bar (QuickShell)
WAYBAR_DESC=		Waybar top bar (fallback if QuickShell is unavailable)
ALACRITTY_DESC=		Alacritty terminal (alternative to foot)
IMV_DESC=		imv image viewer
CHROMIUM_DESC=		Chromium browser (large build)

QUICKSHELL_RUN_DEPENDS=	quickshell:x11/quickshell		# verify origin
WAYBAR_RUN_DEPENDS=	waybar:x11/waybar
ALACRITTY_RUN_DEPENDS=	alacritty:x11/alacritty
IMV_RUN_DEPENDS=	imv:graphics/imv
CHROMIUM_RUN_DEPENDS=	chrome:www/chromium

# Dynamic pkg-plist (Porter's Handbook 8.4): every script under scripts/
# ships to bin/, every FreeBSD override under overrides/bin/ ships to a share
# dir omarchy-setup copies from after cloning the dotfiles. Deliberately
# dynamic so a new helper just needs to be added to one of those two
# directories -- no Makefile or plist edit, and nothing to keep in sync.
do-install:
	${MKDIR} ${STAGEDIR}${PREFIX}/bin
	cd ${WRKSRC}/scripts && for f in *; do \
		${INSTALL_SCRIPT} $$f ${STAGEDIR}${PREFIX}/bin/$$f; \
		${ECHO_CMD} bin/$$f >> ${TMPPLIST}; \
	done
	${MKDIR} ${STAGEDIR}${PREFIX}/share/omarchy-freebsd/overrides/bin
	cd ${WRKSRC}/overrides/bin && for f in *; do \
		${INSTALL_SCRIPT} $$f ${STAGEDIR}${PREFIX}/share/omarchy-freebsd/overrides/bin/$$f; \
		${ECHO_CMD} share/omarchy-freebsd/overrides/bin/$$f >> ${TMPPLIST}; \
	done

.include <bsd.port.mk>
