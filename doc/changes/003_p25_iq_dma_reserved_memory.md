# 003 -- P25 IQ DMA Reserved Memory + rxbuffer Node

**Date:** 2026-04-09
**Branch:** fishball-dev
**Related:** maia-sdr Phase 6C/6D
(`doc/changes/013_phase6c_iq_dma.md` + `doc/changes/014_phase6d_lsm_rust_port.md`
in the maia-sdr repo)

---

## What

Add a third reserved-memory carve-out and matching `maia-sdr,rxbuffer`
device-tree node so the P25 firmware can stream raw post-DDC IQ samples
from the FPGA to userspace via the existing `maia-kmod` rxbuffer driver.

This is the kernel-side counterpart to maia-sdr Phase 6C (the FPGA gateware
that adds the third ring DMA at `0x1900_0000`) and Phase 6D (the Rust LSM
demod in `p25-httpd/src/lsm/` that consumes it).

## Why

The Phase 6C gateware writes 62.5 kSPS post-DDC interleaved 16-bit signed
I/Q samples into a 256 KB ring (8 × 32 KB sub-buffers) at physical
`0x19000000`. Without a `reserved-memory` entry the kernel will happily
allocate generic pages out of that region, and userspace cannot map it as
a coherent DMA window. Without the matching `maia-sdr,rxbuffer` node the
maia-kmod driver does not create a `/dev/p25-iq` chardev for p25-httpd to
open.

These two pieces are the entire DT delta needed for Phase 6D to work.
Everything else (the FPGA bitstream, the AXI-Lite register bank for
`iq_dma_control`/`iq_dma_status`, the Rust LSM pipeline) is already in
place from Phase 6C and the parallel maia-sdr commits.

## Files changed

- `board/tezuka/fishball7020/dts/fishball-p25.dtsi`

## The diff

```dts
reserved-memory {
    /* ... existing p25_dibit_dma @ 0x17000000 (32 KB ring) ... */
    /* ... existing p25_traffic_dma @ 0x18000000 (32 KB ring) ... */

    /* Phase 6C/6D: post-DDC IQ ring DMA, 8 x 32 KB = 256 KB at
       0x19000000. Carries 62.5 kSPS interleaved 16-bit signed I/Q
       (~128 ms per sub-buffer, ~1 s of audio in flight). Must
       match FPGA config (p25_hdl/config.py iq_dma_*). */
    p25_iq_dma: p25-iq-dma@19000000 {
        no-map;
        reg = <0x19000000 0x40000>;
        label = "p25_iq_dma";
    };
};

p25-iq {
    compatible = "maia-sdr,rxbuffer";
    memory-region = <&p25_iq_dma>;
    buffer-size = <0x8000>;
};
```

## Address map (after this change)

| Phys base    | Size    | Label              | Driver                 | /dev node     |
|--------------|---------|--------------------|------------------------|---------------|
| `0x17000000` | 32 KB   | `p25_dibit_dma`    | `maia-sdr,rxbuffer`    | `/dev/p25-dibit` |
| `0x18000000` | 32 KB   | `p25_traffic_dma`  | `maia-sdr,rxbuffer`    | `/dev/p25-traffic` |
| `0x19000000` | 256 KB  | `p25_iq_dma`       | `maia-sdr,rxbuffer`    | `/dev/p25-iq` (NEW) |

The 256 KB size is a hard requirement from the FPGA gateware: the iq_dma
ring uses 8 sub-buffers × 32 KB each (matching
`iq_dma_num_buffers_log2 = 3` and `iq_dma_buffer_size = 0x8000` in
`maia-hdl/p25_hdl/config.py`). Sub-buffer 0 must start at `0x19000000`
because the ring base address is hard-coded in the FPGA gateware
(`iq_dma_address = 0x1900_0000`).

The maia-kmod rxbuffer driver computes `num_buffers = reserved_mem.size /
buffer_size`, so `0x40000 / 0x8000 = 8` matches the FPGA-side count
exactly. The driver also asserts that `reserved_mem.size %
drvdata->buffer_size == 0`; we satisfy that.

## Verification

After flashing this firmware, on the target:

```sh
# 1. /dev/p25-iq exists with the right geometry
ls -l /dev/p25-iq
cat /sys/class/maia-sdr/p25-iq/device/buffer_size   # → 0x8000
cat /sys/class/maia-sdr/p25-iq/device/num_buffers   # → 8

# 2. The carve-out is reserved (not in the kernel's general page pool)
cat /proc/iomem | grep -i 1900_0000

# 3. p25-httpd opens it without errors
grep -i 'iq.*open\|p25-iq' /var/log/p25-httpd.log
```

If the device-tree node is missing or sized wrong, p25-httpd will fail to
start with an `RxBuffer::new("p25-iq")` error and the LSM reader task
will not spawn. The dibit pipeline will continue to run unaffected.

## What does NOT change

- `0x17000000` (dibit) and `0x18000000` (traffic) reservations are
  unchanged.
- The `p25_core: p25-core@7c460000` UIO node and its `intc` IRQ wiring
  are unchanged. The new iq_dma interrupt is multiplexed into the same
  `interrupt_out` line at bit 2 of the IP-core `interrupts` register;
  the user-space p25-httpd irq handler decodes that bit (Phase 6D
  `fpga.rs` change).
- The AD9361 IIO driver, `rx_dma`/`tx_dma` IIO axi-dmac nodes, SPI bus,
  GPIOs, USB PHY, MAC PHY, QSPI partitioning are all untouched.
- All non-Z7020 board files (e200, e310, libre, nano, fishball7010,
  pluto) are untouched.

## Tezuka build pipeline

This change requires no changes to `build.sh`, `build.bat`, the
defconfig, or any package recipe. The Buildroot kernel rebuild
automatically picks up the modified DTSI on the next `build.bat --p25`
because the post-image script regenerates `devicetree.dtb` from the
fishball-p25.dts → .dtsi chain. The maia-kmod driver is already in the
P25 build (it's the same module the dibit/traffic rxbuffers use).

The Phase 6C XSA (`board/tezuka/fishball7020/bitstream/p25/system_top.xsa`,
857 KB → 871 KB) was rebuilt against the new gateware in the maia-sdr
Phase 6C commit and committed to this repo separately; no FPGA package
changes are needed in this repo for Phase 6D.
