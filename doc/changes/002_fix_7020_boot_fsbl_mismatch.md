# Change 002 — Fix Z7020 Boot Failure (CRLF + Board Path)

**Date:** 2026-03-09
**Branch:** `fishball-dev`

## Symptom

Board drops to `FISHBALL>` U-Boot prompt on boot instead of booting Linux.
After fixing, Linux boots but shows `Bad inittab entry` and mount errors.

## Root Cause: CRLF Line Endings (Primary)

**Every text file in the repo has CRLF line endings** (Git `core.autocrlf` on Windows).
The `build.sh` CRLF→LF conversion was too narrow (limited patterns + `-maxdepth 4`)
and missed critical files:

1. **`common/uboot-env.txt`** (209 CRLF, 0 LF) → becomes `uEnv.txt` on SD card
   - Uses backslash `\` line continuation for multi-line U-Boot variables
   - CRLF breaks the continuation: `\` followed by `\r\n` instead of `\n`
   - Critical variables garbled: `sdboot`, `sdboot_ram`, `adi_loadvals`, `preboot`
   - Result: `run sdboot` fails → U-Boot drops to `FISHBALL>` prompt

2. **`overlay_base/etc/inittab`** (45 CRLF) → Bad inittab entries, mount failures
3. **`overlay_base/etc/init.d/*`** (all CRLF) → init script argument parsing errors
4. **`fishball7020/uboot-env.txt`** (64 CRLF) → QSPI env would also be broken

### Why It Worked Before

Upstream (F5OEO) builds on **Linux** — all files have LF endings natively.
This is the first build from the **Windows Docker pipeline**, where Git's
`core.autocrlf` converts LF→CRLF on checkout. The original `build.sh` CRLF
fix was insufficient (limited to `-maxdepth 4` and specific file patterns,
missing `*.txt`, overlay files, `inittab`, etc.).

## Secondary Fix: POST_IMAGE_SCRIPT_ARGS Path

The `BR2_ROOTFS_POST_IMAGE_SCRIPT_ARGS` pointed to `fishball7010` — this was
actually **by upstream design** (the 7020 defconfig was a copy of 7010 that
shared most files). Both boards have the same PS configuration, so the 7010
FSBL works fine on 7020 hardware.

However, we changed it to `fishball7020` for correctness — the 7020 board
should use its own FSBL and bitstream files. This wasn't the cause of the
boot failure, but it's the right thing to do.

## What fishball7020 Shares From fishball7010

The upstream 7020 defconfig was **designed** to share files from fishball7010.
These references are intentional and correct:

| Config Key | Points To | Why Shared |
|-----------|-----------|------------|
| `BR2_GLOBAL_PATCH_DIR` | `fishball7010/patches` | U-Boot patches — same for both boards |
| `BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES` | `fishball7010/kernel/fragment/frag1.config` | Kernel config fragment — same for both |
| `BR2_TARGET_UBOOT_CUSTOM_CONFIG_FILE` | `fishball7010/u-boot-config/zynq_pluto_defconfig` | U-Boot defconfig — same PS config |

Files that are 7020-specific (already in `fishball7020/`):

| File | Purpose |
|------|---------|
| `dts/fishball.dtsi` | Linux DTS — model = "Z7020/AD9361" |
| `dts/fishball.dts` | Top-level Linux DTS |
| `dts/zynq-7000.dtsi` | Zynq SoC base include |
| `u-boot-dts/zynq-pluto-sdr.dts` | U-Boot DTS — model = "7020-AD9361" |
| `bitstream/fsbl.elf` | Z7020 FSBL |
| `bitstream/maia-iio/system_top.xsa` | Z7020 FPGA bitstream |
| `uboot-env.txt` | QSPI U-Boot environment |
| `plutomaia.its` | FIT image description (added in this change) |

## Files Changed

| File | Change |
|------|--------|
| `build.sh` | Rewrote CRLF fix: removed `-maxdepth 4`, exclude binary files instead of whitelisting text patterns. Covers all text files including overlays, inittab, *.txt, *.its |
| `configs/fishball_maiasdr_7020_defconfig` | `BR2_ROOTFS_POST_IMAGE_SCRIPT_ARGS`: `fishball7010` → `fishball7020` |
| `board/tezuka/fishball7020/plutomaia.its` | **New file** — copied from fishball7010 (required by post-image.sh) |

## Verification

After rebuild and reflash:
```bash
# Board should boot to Linux login prompt (no FISHBALL> drop)
# No "Bad inittab entry" errors
# No garbled mount/swapon output
ssh root@192.168.120.50 'cat /sys/firmware/devicetree/base/model'
# Expected: FISH Ball PlutoSDR Rev.A (Z7020/AD9361)
```
