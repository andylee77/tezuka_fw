# Tezuka Firmware — Changelog (andylee77 fork)

Tracking log for the `fishball-dev` branch of the Fishball Z7020 firmware.
Upstream: [F5OEO/tezuka_fw](https://github.com/F5OEO/tezuka_fw)

---

## [2026-03-08] Project Setup

### Fork & Repository
- Forked `F5OEO/tezuka_fw` → `andylee77/tezuka_fw`
- Created `fishball-dev` branch for Fishball Z7020 development
- Set up upstream tracking: `upstream` → `F5OEO/tezuka_fw`, `origin` → `andylee77/tezuka_fw`
- Working copy: `C:\Users\Andy\Projects\Tezuka\tezuka_fw`

### Build Environment
- Docker image: `br_tezuka:2025.02.3` (Buildroot 2025.05)
- Docker volume: `tezuka-build` (persistent ext4 build cache, ~3 min incremental builds)
- Build scripts: `build.bat` (Windows launcher) + `build.sh` (Docker inner script)
- Defconfig: `fishball_maiasdr_7020_defconfig`
- Maia packages point to `andylee77` fork (commit `2cb4003`)

---

## [2026-03-08] Change 001 — Z7020 Model String Fix

**Commit:** `202e487` on `fishball-dev`
**Doc:** `doc/changes/001_z7020_model_string_fix.md`

### Problem
The `fishball_maiasdr_7020_defconfig` was reusing the Z7010 device tree sources,
causing `iio_info` and U-Boot to incorrectly identify the board as:
- `"FISH Ball PlutoSDR Rev.A (Z7010/AD9361)"` ← wrong

### Fix
Created dedicated DTS files for the Z7020 under `board/tezuka/fishball7020/`:

| File | Purpose |
|------|---------|
| `board/tezuka/fishball7020/dts/fishball.dtsi` | Main DTS include — model = `"Z7020/AD9361"` |
| `board/tezuka/fishball7020/dts/fishball.dts` | Top-level DTS |
| `board/tezuka/fishball7020/dts/zynq-7000.dtsi` | Zynq SoC base (from ADI kernel) |
| `board/tezuka/fishball7020/u-boot-dts/zynq-pluto-sdr.dts` | U-Boot DTS — model = `"7020-AD9361"` |

Updated `configs/fishball_maiasdr_7020_defconfig` to point to the new paths.
Z7010 files under `board/tezuka/fishball7010/` are untouched.

### Verification
After flashing:
```bash
ssh root@192.168.120.50 'cat /sys/firmware/devicetree/base/model'
# Expected: FISH Ball PlutoSDR Rev.A (Z7020/AD9361)
```

---

## [2026-03-08] Build 001 — First Firmware Build

**Build time:** ~3 minutes (cached volume from previous development)
**Output:** `output_images/`

| File | Size | Description |
|------|------|-------------|
| `BOOT.bin` | 3.0 MB | First-stage bootloader + U-Boot |
| `devicetree.dtb` | 25 KB | Device tree blob (Z7020 model string) |
| `uImage` | 6.2 MB | Linux kernel image |
| `uramdisk.image.gz` | 22 MB | Root filesystem (ramfs) |
| `uEnv.txt` | 8.5 KB | U-Boot environment |
| `tezuka.zip` | 91 MB | Complete firmware package |
| `overclock/BOOT_fsbl40_32` | 3.0 MB | Overclock variant (40/32) |
| `overclock/BOOT_fsbl58_36` | 3.0 MB | Overclock variant (58/36) |

### Build Packages Rebuilt
- **U-Boot** — with new Z7020 DTS (`zynq-pluto-sdr.dts` from `fishball7020/`)
- **Linux kernel** — with new `fishball.dtb` (Z7020 model)
- **Busybox** — recompiled with updated config
- **maia-wasm** — fetched from `andylee77/maia-sdr` fork (`fishball-dev` branch)

### Deployment
1. Copy `output_images/` contents to a FAT32-formatted SD card
2. Boot Fishball Z7020 from SD card
3. Verify model string via SSH

---

## Pending / Future

- [ ] Flash and verify model string on hardware
- [ ] Test Maia SDR web interface
- [ ] Explore maia-httpd IQ streaming patches
- [ ] Investigate overclock variants
- [ ] Sync with upstream changes as needed
