# Tezuka Firmware — Changelog (andylee77 fork)

Tracking log for the `fishball-dev` branch of the Fishball Z7020 firmware.
Upstream: [F5OEO/tezuka_fw](https://github.com/F5OEO/tezuka_fw)

---

## [2026-04-11] Bitstream refresh — maia-sdr Phase 6G.1 + Phase 6 closeout

**Branch:** fishball-dev
**Related:** maia-sdr Phase 6G.1 (`doc/changes/031_phase6g1_hdl_dc_blocker.md`),
maia-sdr Phase 6 closeout (`doc/changes/032_phase6_closeout.md`)
**Tezuka commits:** `08f7607` (Phase 6G.1 XSA refresh)

### What changed in Tezuka

Just the bitstream artefact at
`board/tezuka/fishball7020/bitstream/p25/system_top.xsa` was
refreshed to the maia-sdr Phase 6G.1 bake (commit `08f7607` here).
No source / DTS / config changes — the new XSA carries the HDL
DC blocker on the LSM IQ input that maia-sdr commit `3ea56fb`
added, runtime bypassable through a new `lsm_control[2]`
register field.

### What changed on the maia-sdr side that this XSA enables

The maia-sdr `fishball-p25` branch closed out Phase 6
(LSM trunking control channel decode) on 2026-04-11. The full
phase rollup, deferral list, and Phase 7 plan live in
`doc/changes/032_phase6_closeout.md` over there. The pieces
that the firmware operator should know about:

1. **HDL DC blocker on the LSM IQ input** (Phase 6G.1) —
   in this XSA. Defaults to ON at p25-httpd startup, runtime
   bypassable via the new `/api/lsm_control` endpoint.
2. **TG dedup in `/api/grants`** (maia-sdr commit `6dfef49`) —
   was showing the same TG repeated 5+ times across stale
   channels; now each TG appears exactly once at its current
   channel.
3. **Source RadioId preservation across grant updates**
   (maia-sdr commit `1e29839`) — the dashboard's caller ID
   no longer drops to None on every periodic
   `GroupVoiceChannelGrantUpdate` refresh.
4. **`/api/lsm_control` runtime read/write endpoint** (Phase
   6G.2) — DC blocker can be A/B tested at runtime via
   `curl 'http://192.168.2.1:8080/api/lsm_control?dc_block=0|1'`
   without ssh + devmem on the board.

### How to deploy

Items (1) is in this XSA — already shipped via `08f7607` and
flashed in the previous firmware build. Items (2)-(4) are
PS-only changes in `p25-httpd` and need ONE more Tezuka
firmware rebuild to get them onto the board. The XSA does not
need to be rebuilt:

```bash
cd C:\Users\Andy\Projects\Tezuka\tezuka_fw && build.bat --p25
```

Buildroot will pick up the latest `p25-httpd` source from the
maia-sdr fork (`fishball-p25` branch HEAD) and rebuild only
the binary. After flashing the resulting `.frm` / `.zip`,
verify with:

```bash
curl http://192.168.2.1:8080/api/system | python -m json.tool
# build field should read: 2026-04-11-phase6-closeout-lsm_control-runtime-toggle

curl http://192.168.2.1:8080/api/lsm_control
# should return all three lsm_*_enable bits = true
```

### What this concludes

maia-sdr Phase 6 — the multi-month port of an LSM Simulcast P25
control channel decoder onto the Fishball Z7020 — is now done.
The radio decodes the Clay County NAC 0x8A1 LSM control
channel end-to-end at ~76-80 % steady-state TSBK CRC pass with
~88 % opcode coverage, real-time TG tracking, and the standard
trunking dashboard surface area. Phase 7 (voice channel
follow + LDU/IMBE + RTP audio out) is the next session and
will start on the maia-sdr side with a second DDC instance in
`p25_top.py` plus a new `voice_control` register bank — that
WILL need a Tezuka rebuild + new device-tree entry for a
second `voice_dibit_dma` ring, but those are Phase 7 problems.

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

## [2026-04-10] Change 004 — P25 LSM Dibit DMA Reserved Memory + rxbuffer Node

**Doc:** `doc/changes/004_p25_lsm_dibit_dma_reserved_memory.md`
**Branch:** fishball-dev
**Related:** maia-sdr Phase 6E.9 / 6E.10
(`doc/changes/018_phase6e9_lsm_top_integration.md`,
`019_phase6e10_vivado_bake.md`)

### What

Add a fourth `reserved-memory` carve-out and matching `maia-sdr,rxbuffer`
device-tree node to expose the Phase 6E.9 HDL LSM demod's dibit ring DMA
to userspace as `/dev/p25-lsm-dibit`. This is the kernel-side bridge
that lets the p25-httpd Phase 6E.9/6E.10 HDL LSM dibit reader task and
NID poller drain the new ring and read the new `lsm_*` AXI register bank.

### Files changed

- `board/tezuka/fishball7020/dts/fishball-p25.dtsi`
  - New `p25_lsm_dibit_dma: p25-lsm-dibit-dma@1a000000` reserved-memory
    node (`reg = <0x1a000000 0x8000>`, 32 KB, `no-map`).
  - New `p25-lsm-dibit` node with `compatible = "maia-sdr,rxbuffer"`,
    `memory-region = <&p25_lsm_dibit_dma>`, `buffer-size = <0x1000>`.
  - Yields 8 sub-buffers x 4 KB at runtime, matching the FPGA-side
    `lsm_dibit_dma_num_buffers_log2 = 3` and
    `lsm_dibit_dma_buffer_size = 0x1000`. Geometry is byte-identical
    to the existing `p25_dibit_dma` (C4FM) ring.

### Why

The Phase 6E.9 gateware wires `LsmDemod` into `P25Core` alongside the
existing C4FM chain, producing a second 4800 sym/s dibit stream on the
control channel, and gives it a dedicated 32 KB ring at `0x1A000000`.
The two rings share the same control DDC output so the PS can drain
both in parallel and A/B the two decoders on a single live RF capture --
essential for bring-up against the Clay County NAC 0x8A1 simulcast site
where the C4FM chain does not lock and the LSM chain is the whole
reason Phase 6E exists.

Without a `reserved-memory` entry the kernel will happily allocate
generic pages out of `0x1A000000`, and without the matching
`maia-sdr,rxbuffer` node the maia-kmod driver does not create the
`/dev/p25-lsm-dibit` chardev that p25-httpd's Phase 6E.10 `fpga.rs`
`IpCore::take()` expects to open.

### Verification (queued)

This change is queued behind the next `build.bat --p25` Tezuka firmware
rebuild (and the parallel maia-sdr Phase 6E.10 Vivado bake that produces
the new XSA). After flashing:

- `ls -l /dev/p25-lsm-dibit` should exist with the rxbuffer driver bound
- `cat /sys/class/maia-sdr/p25-lsm-dibit/device/buffer_size` -> `0x1000`
- `cat /sys/class/maia-sdr/p25-lsm-dibit/device/num_buffers` -> `8`
- `cat /proc/iomem | grep 1a00_0000` should show the carve-out reserved
- `/var/log/p25-httpd.log` should show "HDL LSM dibit reader task started
  (Phase 6E)" and "HDL LSM NID poller task started (Phase 6E)"
- Against the Clay County control channel the NID poller should start
  logging NID events at ~14 ms cadence with `nac=0x8A1` and
  `valid=true`, `n_errors<=11`, `drop_count=0`

If anything is missing the rest of p25-httpd (the C4FM dibit pipeline,
the Phase 6D PS-side LSM pipeline, the web dashboard) keeps running
unaffected -- only the HDL LSM reader + NID poller tasks fail to spawn.

### What does NOT change

- The `p25_dibit_dma@17000000`, `p25_traffic_dma@18000000`, and
  `p25_iq_dma@19000000` reservations are untouched.
- The `p25_core: p25-core@7c460000` UIO node and IRQ wiring are
  unchanged. The new `lsm_dibit_dma` interrupt is multiplexed into the
  same `interrupt_out` line at bit 3 of the IP-core `interrupts`
  register; userspace decodes the bit in `p25-httpd/src/fpga.rs`.
- AD9361, `rx_dma`/`tx_dma`, SPI, GPIOs, USB, MAC, QSPI are untouched.
- All non-Z7020 board files (e200, e310, libre, nano, fishball7010,
  pluto) are untouched.

---

## [2026-04-09] Change 003 — P25 IQ DMA Reserved Memory + rxbuffer Node

**Doc:** `doc/changes/003_p25_iq_dma_reserved_memory.md`
**Branch:** fishball-dev
**Related:** maia-sdr Phase 6C/6D (`docs/changes/013_phase6c_iq_dma.md`,
`014_phase6d_lsm_rust_port.md`)

### What

Add a third `reserved-memory` carve-out and matching `maia-sdr,rxbuffer`
device-tree node to expose the Phase 6C post-DDC IQ ring DMA to userspace
as `/dev/p25-iq`. This is the kernel-side bridge that lets the Phase 6D
Rust LSM demod in `p25-httpd/src/lsm/` consume raw 62.5 kSPS IQ samples
from the FPGA.

### Files changed

- `board/tezuka/fishball7020/dts/fishball-p25.dtsi`
  - New `p25_iq_dma: p25-iq-dma@19000000` reserved-memory node
    (`reg = <0x19000000 0x40000>`, 256 KB, `no-map`).
  - New `p25-iq` node with `compatible = "maia-sdr,rxbuffer"`,
    `memory-region = <&p25_iq_dma>`, `buffer-size = <0x8000>`.
  - Yields 8 sub-buffers × 32 KB at runtime, matching the FPGA-side
    `iq_dma_num_buffers_log2 = 3` and `iq_dma_buffer_size = 0x8000`.

### Why

The Phase 6C gateware writes 62.5 kSPS interleaved 16-bit signed I/Q
into a hard-coded 256 KB ring at `0x19000000`. Without a `reserved-memory`
entry the kernel will allocate generic pages out of that region, and
without the matching `maia-sdr,rxbuffer` node the maia-kmod driver does
not create the `/dev/p25-iq` chardev that p25-httpd expects to open.

### Verification (queued)

This change is queued behind the next `build.bat --p25` Tezuka firmware
rebuild. After flashing:

- `ls -l /dev/p25-iq` should exist with the rxbuffer driver bound
- `cat /sys/class/maia-sdr/p25-iq/device/buffer_size` → `0x8000`
- `cat /sys/class/maia-sdr/p25-iq/device/num_buffers` → `8`
- `cat /proc/iomem | grep 19000000` should show the carve-out reserved
- `/var/log/p25-httpd.log` should show "LSM IQ reader task started
  (Phase 6D)" and per-IRQ wakeups at ~7.6 Hz

If anything is missing the rest of p25-httpd (the dibit pipeline + web
dashboard) keeps running unaffected — the LSM reader task simply fails
to spawn.

### What does NOT change

- The `p25_dibit_dma@17000000` and `p25_traffic_dma@18000000`
  reservations are untouched.
- The `p25_core: p25-core@7c460000` UIO node and IRQ wiring are
  unchanged. The new iq_dma interrupt is multiplexed into the same
  `interrupt_out` line at bit 2 of the existing IP-core `interrupts`
  register; userspace decodes the bit in `p25-httpd/src/fpga.rs`.
- AD9361, `rx_dma`/`tx_dma`, SPI, GPIOs, USB, MAC, QSPI are untouched.
- All non-Z7020 board files (e200, e310, libre, nano, fishball7010,
  pluto) are untouched.

---

## [2026-03-09] Change 002 — Fix Z7020 Boot Failure (CRLF + Board Path)

**Doc:** `doc/changes/002_fix_7020_boot_fsbl_mismatch.md`

### Problem
Board drops to `FISHBALL>` U-Boot prompt on boot instead of booting Linux.

**Root cause: CRLF line endings.** Every text file has CRLF (Git `core.autocrlf`
on Windows). The original `build.sh` CRLF fix was too narrow (`-maxdepth 4`,
limited file patterns) and missed `common/uboot-env.txt` (209 CRLF lines).
This file becomes `uEnv.txt` on the SD card and uses `\` line continuation —
CRLF breaks the continuation, garbling the `sdboot` and other boot variables.
Upstream builds on Linux (LF natively) so this never surfaced before.

The `POST_IMAGE_SCRIPT_ARGS` pointing to `fishball7010` was actually **by upstream
design** — both boards share the same PS config. Changed to `fishball7020` for
correctness, but this was not the boot failure cause.

### Fix
- **Rewrote CRLF conversion** in `build.sh`: removed `-maxdepth 4`, switched to
  excluding binary files instead of whitelisting text patterns — covers all overlay
  files, inittab, `*.txt`, `*.its`, init scripts at any depth
- Changed `BR2_ROOTFS_POST_IMAGE_SCRIPT_ARGS` from `fishball7010` → `fishball7020`
- Created `board/tezuka/fishball7020/plutomaia.its` (required by post-image.sh)

### Status
- [x] Build 002 — Linux boots, login prompt reached
- [x] Rebuild with full CRLF fix (inittab/init scripts)
- [x] Verified clean boot — no Bad inittab, no mount errors, no FISHBALL> drop

---

## Pending / Future

- [ ] Flash and verify model string on hardware
- [ ] Test Maia SDR web interface
- [ ] Explore maia-httpd IQ streaming patches
- [ ] Investigate overclock variants
- [ ] Sync with upstream changes as needed
