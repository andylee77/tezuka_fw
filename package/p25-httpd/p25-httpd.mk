################################################################################
#
# p25-httpd - Fishball P25 Trunking Radio
#
################################################################################

P25_HTTPD_VERSION = v0.1.0
P25_HTTPD_SITE = /mnt/fishball-p25
P25_HTTPD_SITE_METHOD = local

CROSS_COMPILE = arm-none-linux-gnueabihf-
TOOLCHAINS = "$(HOST_DIR)/bin/$(CROSS_COMPILE)gcc"

define P25_HTTPD_BUILD_CMDS
$(shell bash -c "PATH=\"$(HOST_DIR)/bin:$(PATH)\" && \
  cd $(P25_HTTPD_SRCDIR)/p25-httpd && \
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
