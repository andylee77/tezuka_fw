#!/bin/sh
set -e

COMMON_DIR=$(dirname $0)
BIN_DIR=$1
# Args from BR2_ROOTFS_POST_IMAGE_SCRIPT_ARG in board config file
BOARD_DIR="$2"
DTB_NAME="$3"
dfu_suffix=$HOST_DIR/bin/dfu-suffix

DEVICE_VID=0x0456
DEVICE_PID=0xb673

cp $BOARD_DIR/plutomaia.its $BIN_DIR/plutomaia.its

echo "# entering $BIN_DIR for the next command"
(cd $BIN_DIR && mkimage -f plutomaia.its pluto.itb)

echo "generating the pluto.frm"
md5sum $BIN_DIR/pluto.itb | cut -d ' ' -f 1 > $BIN_DIR/pluto.md5
cat $BIN_DIR/pluto.itb $BIN_DIR/pluto.md5 > $BIN_DIR/pluto.frm

echo "generating pluto.dfu"
cp $BIN_DIR/pluto.itb $BIN_DIR/plutocopy.itb
$dfu_suffix -a $BIN_DIR/pluto.itb -v $DEVICE_VID -p $DEVICE_PID
mv $BIN_DIR/pluto.itb $BIN_DIR/pluto.dfu

echo "generating the boot.img"
cp $BOARD_DIR/bitstream/fsbl.elf $BIN_DIR
cp $BIN_DIR/u-boot $BIN_DIR/u-boot.elf
echo "img : {[bootloader] $BIN_DIR/fsbl.elf $BIN_DIR/u-boot.elf}" > $BIN_DIR/boot.bif
bootgen -image $BIN_DIR/boot.bif -w -o i $BIN_DIR/boot.img

echo "generating the boot.frm"
cat $BIN_DIR/boot.img $BIN_DIR/uboot-env.bin $COMMON_DIR/target_mtd_info.key | \
	tee $BIN_DIR/boot.frm | md5sum | cut -d ' ' -f1 | tee -a $BIN_DIR/boot.frm

echo "generating boot.dfu"
cp $BIN_DIR/boot.img $BIN_DIR/boot.bin.tmp
$dfu_suffix -a $BIN_DIR/boot.bin.tmp -v $DEVICE_VID -p $DEVICE_PID
mv $BIN_DIR/boot.bin.tmp $BIN_DIR/boot.dfu

echo "generating uboot-env.dfu"
cp $BIN_DIR/uboot-env.bin $BIN_DIR/uboot-env.bin.tmp
$dfu_suffix -a $BIN_DIR/uboot-env.bin.tmp -v $DEVICE_VID -p $DEVICE_PID
mv $BIN_DIR/uboot-env.bin.tmp $BIN_DIR/uboot-env.dfu

echo "generatind sd"
SDIMGDIR=$BIN_DIR/sdimg
mkdir -p $SDIMGDIR
echo "img : {[bootloader] $BIN_DIR/fsbl.elf $BIN_DIR/system_top.bit $BIN_DIR/u-boot.elf}" > $SDIMGDIR/boot.bif
bootgen -image $SDIMGDIR/boot.bif -w -o i $SDIMGDIR/BOOT.bin

if [ -e $BOARD_DIR/bitstream/overclock/ ]; then
    mkdir -p $SDIMGDIR/overclock
    for filename in $BOARD_DIR/bitstream/overclock/*.elf ; do
        echo "img : {[bootloader] $filename $BIN_DIR/system_top.bit $BIN_DIR/u-boot.elf}" > $SDIMGDIR/boot.bif    
        NAME=`basename -- "$filename" .elf`
        bootgen -image $SDIMGDIR/boot.bif -w -o i $SDIMGDIR/overclock/"BOOT_"$NAME
    done
fi

# SYSTEM TOP.BIN when need to launch from USB or SD without BOOT.BIN
#echo "img : {$SDIMGDIR/system_top.bit }" >  $SDIMGDIR/system.bif
#bootgen -image $SDIMGDIR/system.bif -process_bitstream bin -arch zynq -w -o i $SDIMGDIR/system_top.bin

rm $SDIMGDIR/boot.bif
mkimage -A arm -T ramdisk -C gzip -d $BIN_DIR/rootfs.cpio.gz $SDIMGDIR/uramdisk.image.gz
mkimage -A arm -O linux -T kernel -C none -a 0x2080000 -e 2080000 -n "Linux kernel" -d $BIN_DIR/zImage $SDIMGDIR/uImage
cp $BIN_DIR/$DTB_NAME $SDIMGDIR/devicetree.dtb
cp $COMMON_DIR/uboot-env.txt $SDIMGDIR/uEnv.txt

# Fishball P25: keep U-Boot's initrd/FDT relocation below the P25 DMA
# carve-outs (0x19000000-0x22FFFFFF). With the shared default of 0x20000000
# the ~24 MB ramdisk lands on p25-pre-diff-iq-dma@1f000000, the kernel fails
# to reserve it, and the FPGA DMA writes into free RAM
# (maia-sdr doc/changes/053, finding F20).
if [ "$DTB_NAME" = "fishball-p25.dtb" ]; then
    sed -i 's/^initrd_high=0x20000000/initrd_high=0x18000000/; s/^fdt_high=0x20000000/fdt_high=0x18000000/' $SDIMGDIR/uEnv.txt
fi

# Fishball bench dual image (maia-sdr doc/HW_VALIDATION_SUITE.md 2.4).
# Only for the P25 build of a board that carries a hwval XSA: adds
# sdimg/bench/images/hwval/ (BOOT.bin with the hwval bitstream +
# fishball-hwval.dtb) and sdimg/bench/images/p25/ (the production pair
# built above), each with a SHA256SUMS manifest, for `fbench boot`.
# Every other board/defconfig, and a P25 build without the hwval XSA,
# produces exactly what it produced before (stale copies are removed).
HWVAL_XSA=$BOARD_DIR/bitstream/hwval/system_top.xsa
BENCH_IMG=$SDIMGDIR/bench/images
rm -rf $BENCH_IMG/p25 $BENCH_IMG/hwval $BIN_DIR/hwval
rmdir $BENCH_IMG $SDIMGDIR/bench 2>/dev/null || true
if [ "$DTB_NAME" = "fishball-p25.dtb" ] && [ -f "$HWVAL_XSA" ]; then
    if [ ! -f $BIN_DIR/fishball-hwval.dtb ]; then
        echo "WARNING: $HWVAL_XSA exists but $BIN_DIR/fishball-hwval.dtb was not built" >&2
        echo "WARNING: (new DTS in BR2_LINUX_KERNEL_CUSTOM_DTS_PATH? run 'make linux-rebuild')." >&2
        echo "WARNING: skipping sdimg/bench/images/{p25,hwval}." >&2
    else
        echo "generating bench dual image (sdimg/bench/images/p25 + hwval)"
        mkdir -p $BIN_DIR/hwval
        # A timing-clean XSA carries system_top.bit; a (never promoted)
        # bad-timing XSA carries system_top_bad_timing.bit instead.
        if ! unzip -p $HWVAL_XSA system_top.bit > $BIN_DIR/hwval/system_top.bit || \
           [ ! -s $BIN_DIR/hwval/system_top.bit ]; then
            echo "ERROR: $HWVAL_XSA has no system_top.bit (bad-timing XSA?); not building the hwval image" >&2
            exit 1
        fi
        echo "img : {[bootloader] $BIN_DIR/fsbl.elf $BIN_DIR/hwval/system_top.bit $BIN_DIR/u-boot.elf}" > $BIN_DIR/hwval/boot.bif
        bootgen -image $BIN_DIR/hwval/boot.bif -w -o i $BIN_DIR/hwval/BOOT.bin

        mkdir -p $BENCH_IMG/p25 $BENCH_IMG/hwval
        cp $SDIMGDIR/BOOT.bin $BENCH_IMG/p25/BOOT.bin
        cp $SDIMGDIR/devicetree.dtb $BENCH_IMG/p25/devicetree.dtb
        cp $BIN_DIR/hwval/BOOT.bin $BENCH_IMG/hwval/BOOT.bin
        cp $BIN_DIR/fishball-hwval.dtb $BENCH_IMG/hwval/devicetree.dtb
        (cd $BENCH_IMG/p25 && sha256sum BOOT.bin devicetree.dtb > SHA256SUMS)
        (cd $BENCH_IMG/hwval && sha256sum BOOT.bin devicetree.dtb > SHA256SUMS)
    fi
fi

cd $BIN_DIR && zip -r tezuka.zip boot.dfu boot.frm pluto.frm pluto.dfu sdimg/*
