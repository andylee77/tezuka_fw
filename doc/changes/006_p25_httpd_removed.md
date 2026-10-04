# 006 — p25-httpd removed; the Maia packages follow maia-sdr's main

**Date:** 2026-10-04. **Branch:** fishball-dev. **Related:** maia-sdr's cleanup
(`doc/CLEANUP_INVENTORY.md`), which removed `p25-httpd/` from maia-sdr once the scanner had
replaced it on both units' image.

## What changed

- **`package/p25-httpd/`** and its `Config.in` line are gone; no defconfig selected it since the
  scanner package replaced it. `build.sh` no longer looks for p25-httpd sources.
- **`package/scanner/scanner.mk`** syncs only `scanner/`: the scanner builds against its own PAC
  (`scanner/core-pac`), so the `p25-httpd/p25-pac` copy is dropped.
- **`package/maia-httpd`, `package/maia-wasm`** fetch maia-sdr's `main` (the branch that tracks
  upstream) instead of `fishball-dev`, which maia-sdr deleted. Their sources are identical on
  both. Only the Maia images (`fishball_maiasdr*` and the other `*maiasdr*` defconfigs) use them.
- **Kept:** `post-build-p25.sh`'s guard that strips a p25-httpd left in Buildroot's persistent
  target by an earlier build, and `S50p25-httpd-certificates`, whose file names the units' HTTPS
  certificates carry.
- **Texts:** README, CLAUDE.md, `build.bat`, `S91nfs-mount`, and the comments in the P25 and
  hwval device trees and the hwval bitstream README name the scanner and maia-sdr's
  `scanner-hdl/` paths.

## Effect on images

The next P25 image builds as before. The device-tree comments changed, so `build.sh` rebuilds
the kernel package once.
