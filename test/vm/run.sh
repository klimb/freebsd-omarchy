#!/bin/sh
# Launch the FreeBSD 15.1 arm64 VM on Apple Silicon (QEMU + hvf).
#
# Usage:
#   ./run.sh serial   # headless, console on this terminal (setup/build)
#   ./run.sh gui       # graphical window with virtio-gpu (desktop test)
#
# SSH into it once sshd is enabled:  ssh -p 2222 <user>@127.0.0.1
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
: "${MEM:=8192}"
: "${CPUS:=4}"
: "${SSH_PORT:=2222}"
MODE="${1:-serial}"

set -- \
	-machine virt,accel=hvf \
	-cpu host \
	-smp "$CPUS" \
	-m "$MEM" \
	-drive "if=pflash,format=raw,unit=0,file=$DIR/edk2-code.fd,readonly=on" \
	-drive "if=pflash,format=raw,unit=1,file=$DIR/edk2-vars.fd" \
	-drive "if=virtio,format=qcow2,file=$DIR/disk.qcow2" \
	-netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22" \
	-device virtio-net,netdev=net0 \
	-device virtio-rng-pci

case "$MODE" in
serial)
	exec qemu-system-aarch64 "$@" -nographic
	;;
gui)
	exec qemu-system-aarch64 "$@" \
		-device virtio-gpu-gl-pci \
		-display cocoa,gl=on \
		-device qemu-xhci -device usb-kbd -device usb-tablet \
		-serial mon:stdio
	;;
*)
	echo "usage: $0 [serial|gui]" >&2
	exit 1
	;;
esac
