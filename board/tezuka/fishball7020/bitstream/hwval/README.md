# hwval validation bitstream

`system_top.xsa` in this directory is the Fishball hardware-validation
(`hwval`) bitstream used by the `fbench` bench (Tier 1). It is **not** a
production image.

## Where it comes from

It is built in the maia-sdr repo (branch `fishball-p25`):

```bash
cd C:/Users/Andy/Projects/MAIA_SDR/maia-sdr
./build_fpga_hwval_pretty.sh        # wraps build_fpga.bat --hwval
```

`build_fpga.bat --hwval` builds `maia-hdl/projects/fishball7020_hwval`
(`hwval_core` from `scanner-hdl/hwval_hdl/`) and copies
`fishball_hwval.sdk/system_top.xsa` here. It only ever produces a
timing-clean XSA: for hwval a timing failure is a hard error and
`system_top_bad_timing.xsa` is never promoted. The matching register map is
`maia-sdr/bench/share/hwval_regs.json`.

Design contract: maia-sdr `doc/HW_VALIDATION_SUITE.md` sections 6 and 11.

## How the firmware build uses it

There is no Buildroot package for this XSA. When it exists,
`board/tezuka/common/post-image.sh` (P25 defconfig only, i.e.
`DTB_NAME=fishball-p25.dtb`) extracts `system_top.bit` from it, runs
`bootgen` with the same `fsbl.elf` and `u-boot.elf` as the production image
and writes:

| SD card path | Content |
|---|---|
| `bench/images/hwval/BOOT.bin` | FSBL + hwval bitstream + U-Boot |
| `bench/images/hwval/devicetree.dtb` | `fishball-hwval.dtb` |
| `bench/images/hwval/SHA256SUMS` | `sha256sum BOOT.bin devicetree.dtb` |
| `bench/images/p25/` | the production `BOOT.bin` + `devicetree.dtb` of the same build, `SHA256SUMS` |

The kernel and rootfs are shared; only `BOOT.bin` and `devicetree.dtb` are
swapped by `fbench boot <unit> hwval|p25`. Without this XSA the P25 build
output is unchanged. See `doc/changes/005_fishball_hwval_dual_image.md`.
