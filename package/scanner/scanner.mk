################################################################################
#
# scanner - the Fishball scanner (P25 and DMR trunking)
#
################################################################################

SCANNER_VERSION = v0.1.0
SCANNER_SITE = /mnt/maia-sdr
SCANNER_SITE_METHOD = local

# Sync only scanner/ and the register PAC it builds against (p25-httpd/p25-pac), without the
# cargo target dirs or the scanner's test fixtures: the whole maia-sdr checkout is several GB.
SCANNER_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = \
	--include=/scanner/ --exclude=/scanner/target/ --exclude=/scanner/tests/ \
	--include=/p25-httpd/ --include=/p25-httpd/p25-pac/ --exclude=/p25-httpd/p25-pac/target/ \
	--exclude=/p25-httpd/* --exclude=/*

SCANNER_CROSS_COMPILE = arm-none-linux-gnueabihf-
SCANNER_LINKER = "$(HOST_DIR)/bin/$(SCANNER_CROSS_COMPILE)gcc"

# The Cortex-A9 has VFPv3-D32 and NEON (the target's default is vfpv3-d16 without NEON): the
# vocoders and DSP loops vectorise with them. The cc crate builds rusqlite's bundled SQLite with
# the Buildroot toolchain.
define SCANNER_BUILD_CMDS
$(shell bash -c "PATH=\"$(HOST_DIR)/bin:$(PATH)\" && \
  cd $(SCANNER_SRCDIR)/scanner && \
  RUSTFLAGS=\"-C target-cpu=cortex-a9 -C target-feature=+neon,+vfp3\" \
  CC_armv7_unknown_linux_gnueabihf=$(HOST_DIR)/bin/$(SCANNER_CROSS_COMPILE)gcc \
  AR_armv7_unknown_linux_gnueabihf=$(HOST_DIR)/bin/$(SCANNER_CROSS_COMPILE)ar \
  cargo build --release --locked --target armv7-unknown-linux-gnueabihf \
  --config target.armv7-unknown-linux-gnueabihf.linker='\"'$(SCANNER_LINKER)'\"' ")
endef

define SCANNER_INSTALL_TARGET_CMDS
	$(shell bash -c "xz -f -k $(SCANNER_SRCDIR)/scanner/target/armv7-unknown-linux-gnueabihf/release/scanner")
	$(INSTALL) -D \
		$(SCANNER_SRCDIR)/scanner/target/armv7-unknown-linux-gnueabihf/release/scanner.xz \
		$(TARGET_DIR)/usr/bin/
endef

define SCANNER_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(SCANNER_PKGDIR)/S60scanner $(TARGET_DIR)/etc/init.d/S60scanner
endef

$(eval $(generic-package))
