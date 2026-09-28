################################################################################
#
# p25-httpd - Fishball P25 Trunking Radio
#
################################################################################

P25_HTTPD_VERSION = v0.1.0
P25_HTTPD_SITE = /mnt/maia-sdr
P25_HTTPD_SITE_METHOD = local

# Sync only p25-httpd/ (its path dependencies p25-json / p25-pac and
# every include_str! live inside it), without its cargo target dir. The
# whole maia-sdr checkout is ~8 GB (cargo target dirs, the HDL venv,
# Vivado projects, bench data): every image build spent many minutes
# copying it and raced with host builds ("file has vanished").
P25_HTTPD_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = \
	--include=/p25-httpd/ --exclude=/p25-httpd/target/ --exclude=/*

CROSS_COMPILE = arm-none-linux-gnueabihf-
TOOLCHAINS = "$(HOST_DIR)/bin/$(CROSS_COMPILE)gcc"

#
# RUSTFLAGS: armv7-unknown-linux-gnueabihf defaults to vfpv3-d16 with NEON
# disabled. Cortex-A9 in the Zynq-7020 supports VFPv3-D32 + NEON; turning
# both on lets rustc/LLVM emit SIMD f32 ops in the JMBE vocoder + DSP
# inner loops. Re-baking with these flags after a clean target/release
# tree triggers a full rebuild (cargo treats RUSTFLAGS as part of the
# fingerprint).
#
# CC_/AR_armv7_unknown_linux_gnueabihf: C sources built by the cc crate
# (rusqlite's bundled SQLite, change 072) use the Buildroot toolchain;
# cc's default, arm-linux-gnueabihf-gcc, does not exist here.
#
define P25_HTTPD_BUILD_CMDS
$(shell bash -c "PATH=\"$(HOST_DIR)/bin:$(PATH)\" && \
  cd $(P25_HTTPD_SRCDIR)/p25-httpd && \
  RUSTFLAGS=\"-C target-cpu=cortex-a9 -C target-feature=+neon,+vfp3\" \
  CC_armv7_unknown_linux_gnueabihf=$(HOST_DIR)/bin/$(CROSS_COMPILE)gcc \
  AR_armv7_unknown_linux_gnueabihf=$(HOST_DIR)/bin/$(CROSS_COMPILE)ar \
  cargo build --release --target armv7-unknown-linux-gnueabihf \
  --config target.armv7-unknown-linux-gnueabihf.linker='\"'$(TOOLCHAINS)'\"' ")
endef

define P25_HTTPD_INSTALL_TARGET_CMDS
	$(shell bash -c "xz -f -k $(P25_HTTPD_SRCDIR)/p25-httpd/target/armv7-unknown-linux-gnueabihf/release/p25-httpd")
	$(INSTALL) -D \
		$(P25_HTTPD_SRCDIR)/p25-httpd/target/armv7-unknown-linux-gnueabihf/release/p25-httpd.xz \
		$(TARGET_DIR)/usr/bin/
endef

$(eval $(generic-package))
