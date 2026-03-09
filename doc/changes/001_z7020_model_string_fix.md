# Change 001 — Z7020 Model String Fix

> **Date:** March 8, 2026  
> **Author:** Andy Lee  
> **Branch:** main (fork: andylee77/tezuka_fw)  
> **Status:** Applied ✅  
> **PR-able to upstream:** Yes — no Z7010 files modified  

---

## Summary

The `fishball_maiasdr_7020_defconfig` (Z7020 build) was reusing the Z7010 device tree sources, causing `iio_info` and U-Boot to incorrectly report the board as Z7010.

This fix creates dedicated DTS files for the Z7020 board with the correct model strings, and updates the defconfig to reference them.

---

## Problem

When running `iio_info` on a FISH Ball Z7020 with Tezuka firmware, the output showed:

```
hw_model: FISH Ball PlutoSDR Rev.A (Z7010-AD9361)
```

The FPGA bitstream was correctly built for Z7020, but the identification strings in the device tree were wrong because the Z7020 defconfig shared the Z7010 DTS files.

---

## Root Cause

`fishball_maiasdr_7020_defconfig` pointed `BR2_LINUX_KERNEL_CUSTOM_DTS_PATH` and `BR2_TARGET_UBOOT_CUSTOM_DTS_PATH` to `board/tezuka/fishball7010/dts/` and `board/tezuka/fishball7010/u-boot-dts/`, which contained Z7010 model strings.

---

## Fix (Option B — Proper Isolation)

Created separate DTS files for Z7020 so both Z7010 and Z7020 builds remain correct independently.

### New Files

| File | Description |
|------|-------------|
| `board/tezuka/fishball7020/dts/fishball.dtsi` | Linux DTS include — model: `FISH Ball PlutoSDR Rev.A (Z7020/AD9361)` |
| `board/tezuka/fishball7020/dts/fishball.dts` | Linux DTS — copied from fishball7010 (no changes) |
| `board/tezuka/fishball7020/dts/zynq-7000.dtsi` | Zynq base DTS — copied from fishball7010 (no changes) |
| `board/tezuka/fishball7020/u-boot-dts/zynq-pluto-sdr.dts` | U-Boot DTS — model: `FISH Ball SDR Board (7020-AD9361)` |

### Modified Files

| File | Change |
|------|--------|
| `configs/fishball_maiasdr_7020_defconfig` | `BR2_LINUX_KERNEL_CUSTOM_DTS_PATH` → `fishball7020/dts/...` |
| `configs/fishball_maiasdr_7020_defconfig` | `BR2_TARGET_UBOOT_CUSTOM_DTS_PATH` → `fishball7020/u-boot-dts/...` |

### Unchanged

- All `board/tezuka/fishball7010/` files — completely untouched
- FPGA bitstreams, uboot-env, kernel config, patches — unchanged
- `fishball_maiasdr_defconfig` (Z7010 build) — unchanged

---

## Expected Result After Build

### `iio_info` output:
```
hw_model: FISH Ball PlutoSDR Rev.A (Z7020-AD9361)
```

### Device tree model (via SSH):
```bash
cat /sys/firmware/devicetree/base/model
# FISH Ball PlutoSDR Rev.A (Z7020/AD9361)
```

### U-Boot boot message:
```
FISH Ball SDR Board (7020-AD9361)
```

---

## Build Notes

After applying this change, a rebuild requires `linux-dirclean` and `uboot-dirclean` to force Buildroot to pick up the new DTS files. See the project build scripts for details.

---

## Model String Comparison (After Fix)

| Build | Linux DTS model | U-Boot DTS model |
|-------|----------------|-----------------|
| Z7010 (`fishball_maiasdr_defconfig`) | `FISH Ball PlutoSDR Rev.A (Z7010/AD9361)` | `FISH Ball SDR Board (7010-AD9363)` |
| Z7020 (`fishball_maiasdr_7020_defconfig`) | `FISH Ball PlutoSDR Rev.A (Z7020/AD9361)` | `FISH Ball SDR Board (7020-AD9361)` |
