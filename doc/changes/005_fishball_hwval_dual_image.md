# 005 -- Fishball hwval Device Tree + Bench Dual Image on SD

**Date:** 2026-09-26
**Branch:** fishball-dev
**Related:** maia-sdr hardware-validation suite
(`doc/HW_VALIDATION_SUITE.md` sections 2.4, 6.1, 6.2, 11 and
`doc/changes/053_hw_validation_bench.md` in the maia-sdr repo)

---

## What

Firmware-side support for the `hwval` validation bitstream:

1. A new device tree pair, `fishball-hwval.dts` / `fishball-hwval.dtsi`,
   that matches the `hwval` block design: UIO `hwval-core@7c460000` and
   three static DDR windows instead of the P25 ring carve-outs.
2. `fishball_p25_7020_defconfig` builds `fishball-hwval.dtb` next to
   `fishball-p25.dtb`.
3. `post-image.sh` writes a bench dual image on the SD card when
   `board/tezuka/fishball7020/bitstream/hwval/system_top.xsa` exists:
   `bench/images/hwval/` (validation `BOOT.bin` + `devicetree.dtb`) and
   `bench/images/p25/` (the production pair of the same build), each with
   a `SHA256SUMS` manifest.
4. `board/tezuka/fishball7020/bitstream/hwval/README.md` documents where the
   XSA comes from.

## Why

The hardware-validation bench (`fbench`) measures ring loss, memory
integrity, clock stability and the AD9361 interface with a dedicated
bitstream (`hwval_core`) instead of going through `p25-httpd`. The `hwval`
image reuses the production kernel and rootfs; only `BOOT.bin` (FSBL +
bitstream + U-Boot) and `devicetree.dtb` differ. `fbench boot <unit>
hwval|p25` swaps those two files on the card from `/mnt/sd/bench/images/<name>/`
after checking the sha256 manifest, so both pairs must be on the card.

## Files changed

- `board/tezuka/fishball7020/dts/fishball-hwval.dts` (new)
- `board/tezuka/fishball7020/dts/fishball-hwval.dtsi` (new)
- `board/tezuka/fishball7020/bitstream/hwval/README.md` (new)
- `configs/fishball_p25_7020_defconfig`
- `board/tezuka/common/post-image.sh`

## Device tree deltas vs fishball-p25

`fishball-hwval.dts` is `fishball-p25.dts` with the include switched to
`fishball-hwval.dtsi`. `fishball-hwval.dtsi` is `fishball-p25.dtsi` with
exactly two changes:

- `reserved-memory` and the rxbuffer nodes are replaced by the hwval windows:

```dts
reserved-memory {
    hwval_ringv2_mem: hwval-ringv2@20000000 {
        no-map;
        reg = <0x20000000 0x1000000>;
        label = "hwval_ringv2";
    };
    hwval_legacy_mem: hwval-legacy@22000000 {
        no-map;
        reg = <0x22000000 0x1000000>;
        label = "hwval_legacy";
    };
    hwval_memtest_mem: hwval-memtest@24000000 {
        no-map;
        reg = <0x24000000 0x4000000>;
        label = "hwval_memtest";
    };
};

hwval-ringv2 {
    compatible = "maia-sdr,rxbuffer";
    memory-region = <&hwval_ringv2_mem>;
    buffer-size = <0x100000>;
};

hwval-legacy {
    compatible = "maia-sdr,rxbuffer";
    memory-region = <&hwval_legacy_mem>;
    buffer-size = <0x100000>;
};
```

- The UIO node is renamed; `compatible`, `reg`, `clocks` and `interrupts`
  are unchanged, so `/sys/class/uio/uioN/name` reads `hwval-core`:

```dts
hwval_core: hwval-core@7c460000 {
    compatible = "uio_pdrv_genirq";
    reg = <0x7c460000 0x1000>;
    clocks = <&clkc 15>;
    interrupt-parent = <&intc>;
    interrupts = <0 55 IRQ_TYPE_LEVEL_HIGH>;
};
```

Everything else is identical to the P25 tree: AD9361 PHY (LVDS 1R1T),
`cf-ad9361-lpc`, the DDS core `cf-ad9361-dds-core-lpc@79024000` (the `hwval`
bitstream builds `axi_ad9361` with `DAC_DDS_DISABLE=0`, so the DDS driver
now finds a working tone generator), `rx_dma` / `tx_dma`, XADC, SD, USB,
GEM, QSPI, GPIOs, model string.

## Address map (hwval image)

| Phys base | Size | Node | Driver | /dev node |
|---|---|---|---|---|
| `0x20000000` | 16 MiB | `hwval-ringv2` | `maia-sdr,rxbuffer` | `/dev/hwval-ringv2` (16 x 1 MiB) |
| `0x22000000` | 16 MiB | `hwval-legacy` | `maia-sdr,rxbuffer` | `/dev/hwval-legacy` (16 x 1 MiB) |
| `0x24000000` | 64 MiB | `hwval-memtest` | reserved only | -- |
| `0x7C460000` | 4 KiB | `hwval-core` | `uio_pdrv_genirq` | `/dev/uioN`, IRQ SPI 55 |

All windows are above U-Boot's `initrd_high` / `fdt_high` (0x2000_0000).
maia-kmod computes `num_buffers = size / buffer-size = 16` for both rings.
The rxbuffer nodes need `maia-sdr.ko` loaded, exactly like the P25 rings.

## defconfig

```diff
-BR2_LINUX_KERNEL_CUSTOM_DTS_PATH="... fishball-p25.dtsi ... fishball-p25.dts ... zynq-7000.dtsi "
+BR2_LINUX_KERNEL_CUSTOM_DTS_PATH="... fishball-p25.dtsi ... fishball-p25.dts ... fishball-hwval.dtsi ... fishball-hwval.dts ... zynq-7000.dtsi "
```

Buildroot compiles every `.dts` in the list, so `output/images/` gains
`fishball-hwval.dtb`. `BR2_ROOTFS_POST_IMAGE_SCRIPT_ARGS` still names
`fishball-p25.dtb`, so the production `devicetree.dtb` is unchanged.

## post-image.sh

A block after the `devicetree.dtb` / `uEnv.txt` copies and before the
final `zip`:

- Always removes stale `sdimg/bench/images/{p25,hwval}` and
  `images/hwval/` first, so any build without the hwval inputs produces
  exactly the previous output.
- Runs only when `DTB_NAME` is `fishball-p25.dtb` **and**
  `$BOARD_DIR/bitstream/hwval/system_top.xsa` exists. Other boards and the
  Maia defconfig (same `fishball7020` board dir) are skipped.
- If `fishball-hwval.dtb` was not built, prints a warning (run
  `make linux-rebuild`) and skips; the production image is unaffected.
- `unzip -p` extracts `system_top.bit`; an XSA without it (a bad-timing
  XSA) is a hard error.
- `bootgen` with the same `fsbl.elf` / `u-boot.elf` as `sdimg/BOOT.bin`,
  then copies both pairs and writes `SHA256SUMS` (`sha256sum BOOT.bin
  devicetree.dtb`, relative names) in each directory.

The final `zip -r tezuka.zip ... sdimg/*` picks up `sdimg/bench/` as well.

## Build

The DTS list change is not picked up by an already-built kernel, so the
first build after this change needs a kernel rebuild:

```bat
cd C:\Users\Andy\Projects\Tezuka\tezuka_fw
build.bat --interactive --p25
```

then inside the container (working directory `/home/br-user/tezuka_build`):

```bash
bash $SRC_MOUNT/build.sh        # 1: sync new DTS + defconfig, normal build
                                #    (post-image warns: no fishball-hwval.dtb yet)
(source sourceme.first && cd buildroot && make linux-rebuild)   # 2: builds fishball-hwval.dtb
bash $SRC_MOUNT/build.sh        # 3: post-image writes sdimg/bench/images/*,
                                #    output copied to output_images/
```

(`build.bat --p25 --clean` also works, at full-build cost.) Later builds
only need `build.bat --p25`.

## Verification

Build host:

```bash
ls output_images/bench/images/hwval output_images/bench/images/p25
(cd output_images/bench/images/hwval && sha256sum -c SHA256SUMS)
```

On a unit booted into the hwval pair:

```sh
cat /sys/class/uio/uio*/name                 # -> hwval-core
ls -l /dev/hwval-ringv2 /dev/hwval-legacy
cat /sys/class/maia-sdr/hwval-ringv2/device/num_buffers   # -> 16
ls /proc/device-tree/reserved-memory/        # hwval-ringv2@20000000 ...
grep -i 2000_0000 /proc/iomem
```

`p25-httpd` still starts from `S60p25-httpd` and exits at `IpCore::take`
(product ID is not `p25f`); that is intended.

## What does NOT change

- `fishball-p25.dts(i)`, the production `sdimg/BOOT.bin`,
  `sdimg/devicetree.dtb`, `uImage`, `uramdisk.image.gz`, `uEnv.txt`,
  `pluto.frm`, `boot.frm` and the DFU images.
- `package/fishball_fpga_p25` (no new Buildroot package; post-image reads
  the hwval XSA directly on every build).
- All other boards and defconfigs.
