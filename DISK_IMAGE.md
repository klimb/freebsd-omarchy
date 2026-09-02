# freebsd-omarchy installer image

This document covers two complementary distribution strategies:

1. **Pre-built disk image** — flash a complete system to an SSD in ~3 min (no
   installer, no questions).
2. **Custom installer USB** — boots like a traditional installer but asks the
   absolute minimum — fewer questions than any other OS installer, on par with
   the Omarchy Linux installer. Decides everything else automatically.

Both are planned. Neither is implemented yet; the current path is
`bootstrap/install.sh`.

---

## Why a disk image

The bootstrap script (`bootstrap/install.sh`) pulls ~400 packages from the
network and runs `omarchy-setup`; on a fast connection this takes 10-20 minutes.
A pre-built disk image eliminates the download step entirely: the image already
contains a complete, configured system. The user's machine is write speed
limited (~2-3 min on a USB3 drive).
- We want to streamline the default FreeBSD installation process, reduce
  questions asked of the user, and reduce overall install time to a couple of
  minutes.

## Approach

**Pre-built UFS disk image** — the same method used by NomadBSD and GhostBSD.

```
[build host: FreeBSD amd64]
  1. Install FreeBSD in a clean VM/machine
  2. Run bootstrap/install.sh + omarchy-setup as a target user
  3. pkg clean -a                    ← reclaim ~500 MB of pkg cache
  4. makefs(8) → raw UFS filesystem
  5. mkimg(8)  → GPT-wrapped raw disk image
  6. zstd      → omarchy-<version>-amd64.img.zst (~2-4 GB)

[end user]
  zstd -d omarchy-<version>-amd64.img.zst | dd of=/dev/da0 bs=1M
  # ~2-3 min on a USB3 SSD

  first boot:
    → RC script runs growfs(8) to expand rootfs to full disk
    → prompts for username + password (or runs bsdinstall adduser)
    → desktop auto-starts on next login
```

All tools (`makefs`, `mkimg`, `growfs`) are in FreeBSD base — no third-party
build dependencies.

## Build pipeline (planned — not yet implemented)

The build pipeline will live in `build/` with these components:

| File | Purpose |
|---|---|
| `build/build-image.sh` | Top-level build script; runs on a FreeBSD amd64 host |
| `build/firstboot.sh` | RC script installed into the image; runs once on first boot |
| `build/mkimage.conf` | Partition layout / `makefs` + `mkimg` parameters |

### build-image.sh outline

```sh
# 1. Run install.sh inside a clean chroot or reference VM
# 2. pkg clean -a
# 3. Remove install artifacts (/tmp/*, /root/.cache, /var/cache/pkg)
# 4. Stamp /etc/omarchy-image-version
# 5. makefs -t ffs -o label=omarchy <image.ufs> <rootdir>
# 6. mkimg -s gpt -p freebsd-boot:=<bootcode> \
#          -p freebsd-ufs:=<image.ufs> \
#          -o omarchy-<ver>-amd64.img
# 7. zstd -T0 -19 omarchy-<ver>-amd64.img
```

### firstboot.sh outline

```sh
#!/bin/sh
# /usr/local/etc/rc.d/omarchy-firstboot
# KEYWORD: firstboot
#
# Runs exactly once (firstboot RC keyword) on the user's machine.

# Expand the UFS root to the full partition
growfs /

# Collect user credentials and create the desktop account
bsdinstall adduser
# ... pw useradd, video group, doas, etc.

# Disable self after first run (firstboot RC handles this automatically)
```

The `# KEYWORD: firstboot` directive causes FreeBSD's RC system to run this
script on the first boot after imaging and never again — no sentinel files
needed.

## Image sizing

| Layer | Approx size |
|---|---|
| FreeBSD 15.x base | ~900 MB |
| All omarchy packages (~400 pkgs) | ~3.5 GB |
| Omarchy configs + overrides | ~50 MB |
| **Raw image** | **~5 GB** |
| **Compressed (zstd -19)** | **~2-3 GB** |

The image is built at a fixed size (e.g. 10 GB) so it fits any SSD ≥ 10 GB;
`firstboot.sh` runs `growfs` to fill whatever space is actually available.

## Comparison to other approaches

| Approach | Install time | Build complexity | Notes |
|---|---|---|---|
| **Pre-built disk image** (this doc) | ~3 min | Low | No network; needs `dd` |
| mfsBSD + embedded pkg repo | ~5 min | Medium | Traditional installer UX; needs poudriere |
| `bootstrap/install.sh` (current) | 10-20 min | None | Requires network; works today |
| FreeBSD `make release` custom ISO | ~5 min | Very high | Full ports/src tree needed |

## Publishing a GitHub Release

GitHub Releases hosts the image as a release asset (free, up to 2 GB per file,
served via GitHub's CDN). Each release maps to a git tag.

### Prerequisites

```sh
# Install the GitHub CLI (once, on your Mac)
brew install gh

# Authenticate (once)
gh auth login
```

### Tag and release

```sh
# On your Mac, from the repo root.
VERSION="1.0.0"   # bump for each build

# 1. Tag the commit that produced this image
git tag "v$VERSION"
git push origin "v$VERSION"

# 2. Create the release and upload the image in one step
gh release create "v$VERSION" \
    --title "freebsd-omarchy v$VERSION" \
    --notes "Pre-built FreeBSD + Omarchy disk image. Flash to any ≥10 GB SSD.

## Install
\`\`\`
# On the target machine (e.g. from a FreeBSD live USB):
fetch https://github.com/klimb/freebsd-omarchy/releases/download/v$VERSION/omarchy-${VERSION}-amd64.img.zst
zstd -d omarchy-${VERSION}-amd64.img.zst | dd of=/dev/da0 bs=1M status=progress
\`\`\`
Boot and follow the first-boot setup wizard." \
    "omarchy-${VERSION}-amd64.img.zst"
```

`gh release create` uploads the file, creates the release page, and prints the
URL. The asset download URL is always:

```
https://github.com/klimb/freebsd-omarchy/releases/download/v<VERSION>/omarchy-<VERSION>-amd64.img.zst
```

### Generating a SHA256 checksum

```sh
sha256sum "omarchy-${VERSION}-amd64.img.zst" > "omarchy-${VERSION}-amd64.img.zst.sha256"
# Then add the .sha256 file as a second asset in the gh release create command above.
```

Users verify with:

```sh
sha256sum -c omarchy-${VERSION}-amd64.img.zst.sha256
```

### Size limit note

GitHub Release assets are capped at **2 GB per file**. If the compressed image
exceeds this, split it:

```sh
# Split into 1.9 GB chunks
split -b 1900m "omarchy-${VERSION}-amd64.img.zst" "omarchy-${VERSION}-amd64.img.zst.part"
# Upload all part* files as assets; users cat them back together before piping to dd.
```

Or switch the asset storage to Cloudflare R2 (free 10 GB) and link the download
URL from the release notes instead.

---

## Custom installer USB

A bootable USB that installs FreeBSD + Omarchy from scratch. The goal is the
fewest questions of any OS installer — on par with the Omarchy Linux installer.
Only what the system absolutely cannot decide for you is asked:

| Prompt | Why it can't be skipped |
|---|---|
| Username | identity — no safe default |
| Password | login + disk encryption key — must come from the user |
| Install target disk | destructive — must confirm the right disk |
| WiFi SSID + passphrase | only if no ethernet is present |

Everything else is decided automatically.

### Automatic decisions

| Choice | Value |
|---|---|
| Filesystem | UFS2 with soft updates (no ZFS) |
| Partition scheme | GPT if UEFI firmware present, MBR if legacy BIOS |
| Disk | largest available NVMe/SSD (`/dev/nvd0` or `/dev/ada0`) |
| Layout | 512 KB freebsd-boot + 2 GB swap + remainder root |
| Encryption | GELI on the root partition; password = the one the user typed |
| Hostname | same as username |
| Timezone | detected from IP geolocation (or UTC as fallback) |
| Network | DHCP on first ethernet/wifi (wifi: prompted for SSID/PSK if no wire) |
| Shell | bash |
| Root password | same as the desktop user's password |

### Boot environment: mfsBSD

The installer USB is built on [mfsBSD](https://mfsbsd.vx.sk/) — a minimal
FreeBSD system that boots entirely from RAM, leaving all disks free to
partition. The installer script replaces mfsBSD's default shell.

```
[build machine]
  1. Download mfsBSD special edition (includes FreeBSD base sets)
  2. Add omarchy-install.sh + pre-fetched pkg repo to the image
  3. Set /etc/rc.local to exec omarchy-install.sh on first boot
  4. mfsBSD build tools produce omarchy-installer-<ver>-amd64.iso
```

### Installer script flow (`build/omarchy-install.sh`)

```
boot → omarchy-install.sh starts automatically

  ┌──────────────────────────────────────────────┐
  │  Welcome to freebsd-omarchy                  │
  │                                              │
  │  Username:  _                                │
  │  Password:  _  (••••)                        │
  │                                              │
  │  Install to: nvd0  512 GB  [Y/n]             │
  │  (WiFi SSID + passphrase if no ethernet)     │
  └──────────────────────────────────────────────┘
  # that's it — everything below is automatic

  → detect target disk (largest non-removable; shown above for confirmation)
  → if no ethernet: scan wifi, prompt SSID + passphrase; connect before pkg step

  → gpart destroy -F da0 && gpart create -s gpt da0
  → gpart add -t freebsd-boot -s 512k
  → gpart add -t freebsd-swap -s 2g
  → gpart add -t freebsd-ufs  (remainder)

  → geli init -l 256 -J <password> /dev/da0p3
  → geli attach -j <password> /dev/da0p3  → /dev/da0p3.eli

  → newfs -U /dev/da0p3.eli
  → mount /dev/da0p3.eli /mnt

  → bsdinstall distextract          (extract base.txz + kernel.txz from USB)
  → chroot /mnt:
      sysrc geli_devices="da0p3"
      echo '/dev/da0p3.eli  /  ufs  rw  1  1' >> /etc/fstab
      echo '/dev/da0p3p2    none  swap  sw  0  0' >> /etc/fstab
      pw useradd <username> -m -s /usr/local/bin/bash -G video,wheel
      echo '<username>:<password>' | chpasswd
      pw lock root
      # run install.sh from the embedded pkg repo (no network needed)
      INSTALL_FROM_LOCAL=1 sh /installer/bootstrap/install.sh
      omarchy-setup

  → umount /mnt && geli detach /dev/da0p3.eli
  → reboot
```

### Embedded package repo

To avoid network dependency during install, the ISO embeds a local pkg repo
containing all ~400 required packages (built by poudriere or mirrored from the
FreeBSD CDN). `install.sh` detects `INSTALL_FROM_LOCAL=1` and points `pkg` at
the local repo path.

This is the main reason install time can reach 3-5 minutes — package
extraction from a local USB 3 source rather than a remote CDN.

### Testing

The installer and resulting system can be validated end-to-end in a QEMU VM
(attach the image or ISO as a virtual disk, automate prompts via serial
console). Everything except the Hyprland compositor itself is fully
VM-testable: partitioning, GELI, package extraction, `omarchy-setup`, service
enablement, user creation. Compositor startup requires real DRM hardware — that
constraint already exists today and is independent of the installer.

The existing `test/vm/` and `test/lab/` infrastructure is the natural home for
installer test automation.

### Build pipeline (planned)

```
build/
  omarchy-install.sh     custom installer script (runs inside mfsBSD)
  build-installer.sh     host script: fetches mfsBSD, injects our files, produces .iso
  mirror-pkgs.sh         mirrors required pkg set from FreeBSD CDN into build/repo/
```

---

## Status

Not yet implemented. The current install path is `bootstrap/install.sh`.

Tracked in [ROADMAP.md](ROADMAP.md).

