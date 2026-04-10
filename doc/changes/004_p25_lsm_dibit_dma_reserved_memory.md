# 004 -- P25 LSM Dibit DMA Reserved Memory + rxbuffer Node

**Date:** 2026-04-10
**Branch:** fishball-dev
**Related:** maia-sdr Phase 6E.9 / 6E.10
(`doc/changes/018_phase6e9_lsm_top_integration.md` +
`doc/changes/019_phase6e10_vivado_bake.md` in the maia-sdr repo)

---

## What

Add a fourth reserved-memory carve-out and matching `maia-sdr,rxbuffer`
device-tree node so the P25 firmware can stream the HDL LSM demod's
dibit output from the FPGA to userspace via the existing `maia-kmod`
rxbuffer driver.

This is the kernel-side counterpart to maia-sdr Phase 6E.9 (the FPGA
gateware that wires `LsmDemod` into `P25Core` alongside the existing
C4FM chain and gives it a parallel `lsm_dibit_dma` ring at
`0x1A000000`) and Phase 6E.10 (the Vivado bake that rolls that
gateware into the XSA).

## Why

The Phase 6E.9 gateware produces a second 4800 sym/s dibit stream from
the HDL LSM demod, parallel to the existing C4FM dibit stream, and
writes packed 64-bit dibit words into a 32 KB ring (8 x 4 KB
sub-buffers) at physical `0x1A000000`. The two rings share the same
control DDC output so the PS can drain both in parallel and A/B the
two decoders on a single live RF capture -- essential for bring-up
against a simulcast site (Clay County NAC 0x8A1, 860.9625 MHz) where
the C4FM chain does not lock and the LSM chain is the whole reason
Phase 6E exists.

Without a `reserved-memory` entry the kernel will happily allocate
generic pages out of `0x1A000000`, and userspace cannot map it as a
coherent DMA window. Without the matching `maia-sdr,rxbuffer` node
the maia-kmod driver does not create a `/dev/p25-lsm-dibit` chardev
for p25-httpd to open, and `RxBuffer::new("p25-lsm-dibit")` fails
during `IpCore::take()`.

These two pieces are the entire DT delta needed for Phase 6E.9/6E.10
to work on hardware. Everything else (the FPGA bitstream with the new
`lsm_*` AXI register bank, the `m_axi_lsm_dibit` HP1 master, and the
p25-httpd PS-side accessors + IRQ plumbing + NID poller task) is
already in place from the parallel maia-sdr commits.

## Files changed

- `board/tezuka/fishball7020/dts/fishball-p25.dtsi`

## The diff

```dts
reserved-memory {
    /* ... existing p25_dibit_dma @ 0x17000000 (32 KB ring) ... */
    /* ... existing p25_traffic_dma @ 0x18000000 (32 KB ring) ... */
    /* ... existing p25_iq_dma @ 0x19000000 (256 KB ring) ... */

    /* Phase 6E.9/6E.10: HDL LSM control-channel dibit ring DMA,
       8 x 4 KB = 32 KB at 0x1a000000. Parallel to p25_dibit_dma
       (the C4FM dibit ring) so the PS can A/B both demods on one
       RF capture. Geometry mirrors p25_dibit_dma exactly. Must
       match FPGA config (p25_hdl/config.py lsm_dibit_dma_*). */
    p25_lsm_dibit_dma: p25-lsm-dibit-dma@1a000000 {
        no-map;
        reg = <0x1a000000 0x8000>;
        label = "p25_lsm_dibit_dma";
    };
};

p25-lsm-dibit {
    compatible = "maia-sdr,rxbuffer";
    memory-region = <&p25_lsm_dibit_dma>;
    buffer-size = <0x1000>;
};
```

## Address map (after this change)

| Phys base    | Size    | Label                  | Driver                 | /dev node              |
|--------------|---------|------------------------|------------------------|------------------------|
| `0x17000000` | 32 KB   | `p25_dibit_dma`        | `maia-sdr,rxbuffer`    | `/dev/p25-dibit`       |
| `0x18000000` | 32 KB   | `p25_traffic_dma`      | `maia-sdr,rxbuffer`    | `/dev/p25-traffic`     |
| `0x19000000` | 256 KB  | `p25_iq_dma`           | `maia-sdr,rxbuffer`    | `/dev/p25-iq`          |
| `0x1A000000` | 32 KB   | `p25_lsm_dibit_dma`    | `maia-sdr,rxbuffer`    | `/dev/p25-lsm-dibit` (NEW) |

The 32 KB size is a hard requirement from the FPGA gateware: the
`lsm_dibit_dma` ring uses 8 sub-buffers x 4 KB each (matching
`lsm_dibit_dma_num_buffers_log2 = 3` and
`lsm_dibit_dma_buffer_size = 0x1000` in `maia-hdl/p25_hdl/config.py`).
Sub-buffer 0 must start at `0x1A000000` because the ring base address
is hard-coded in the gateware (`lsm_dibit_dma_address = 0x1A00_0000`)
and the ring-write logic aligns on the total ring size.

The maia-kmod rxbuffer driver computes
`num_buffers = reserved_mem.size / buffer_size`, so
`0x8000 / 0x1000 = 8` matches the FPGA-side count exactly. The driver
also asserts that `reserved_mem.size % drvdata->buffer_size == 0`; we
satisfy that.

Geometry is byte-identical to `p25_dibit_dma` (same 8 x 4 KB layout),
so the existing kernel-side rxbuffer handling carries over without
any driver changes.

## Verification

After flashing this firmware, on the target:

```sh
# 1. /dev/p25-lsm-dibit exists with the right geometry
ls -l /dev/p25-lsm-dibit
cat /sys/class/maia-sdr/p25-lsm-dibit/device/buffer_size   # -> 0x1000
cat /sys/class/maia-sdr/p25-lsm-dibit/device/num_buffers   # -> 8

# 2. The carve-out is reserved (not in the kernel's general page pool)
cat /proc/iomem | grep -i 1a00_0000

# 3. p25-httpd opens it without errors
grep -i 'lsm.*open\|p25-lsm-dibit' /var/log/p25-httpd.log

# 4. HDL LSM NID events are being logged (one per ~14 ms)
grep -i 'p25_hdl_lsm.*NID event' /var/log/p25-httpd.log | head
```

If the device-tree node is missing or sized wrong, p25-httpd will
fail to start with an `RxBuffer::new("p25-lsm-dibit")` error and
neither the HDL LSM dibit reader task nor the HDL LSM NID poller
task will spawn. The C4FM dibit pipeline and the Phase 6D PS-side
LSM pipeline will continue to run unaffected.

## What does NOT change

- `0x17000000` (dibit), `0x18000000` (traffic), and `0x19000000` (iq)
  reservations are unchanged.
- The `p25_core: p25-core@7c460000` UIO node and its `intc` IRQ
  wiring are unchanged. The new `lsm_dibit_dma` interrupt is
  multiplexed into the same `interrupt_out` line at bit 3 of the
  IP-core `interrupts` register; the user-space p25-httpd IRQ
  handler decodes that bit (Phase 6E.9/6E.10 `fpga.rs` change).
- The AD9361 IIO driver, `rx_dma`/`tx_dma` IIO axi-dmac nodes, SPI
  bus, GPIOs, USB PHY, MAC PHY, QSPI partitioning are all untouched.
- All non-Z7020 board files (e200, e310, libre, nano, fishball7010,
  pluto) are untouched.

## Tezuka build pipeline

This change requires no changes to `build.sh`, `build.bat`, the
defconfig, or any package recipe. The Buildroot kernel rebuild
automatically picks up the modified DTSI on the next `build.bat --p25`
because the post-image script regenerates `devicetree.dtb` from the
fishball-p25.dts -> .dtsi chain. The maia-kmod driver is already in
the P25 build (same module the dibit/traffic/iq rxbuffers use).

The Phase 6E.10 XSA
(`board/tezuka/fishball7020/bitstream/p25/system_top.xsa`) is being
rebuilt against the new gateware in the maia-sdr Phase 6E.10 Vivado
bake and will land in a separate shipping-artefact commit; no FPGA
package changes are needed in this repo beyond copying in the new
XSA when Vivado finishes.
