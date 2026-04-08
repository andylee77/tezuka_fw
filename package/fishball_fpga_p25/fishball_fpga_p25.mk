################################################################################
#
# fishball-p25-system-top-bit
#
################################################################################

FISHBALL_FPGA_P25_VERSION = v0.1.0
FISHBALL_FPGA_P25_SOURCE = system_top.xsa
FISHBALL_FPGA_P25_SITE = $(BR2_EXTERNAL_PLUTOSDR_PATH)/board/tezuka/fishball7020/bitstream/p25
FISHBALL_FPGA_P25_SITE_METHOD = local
FISHBALL_FPGA_P25_INSTALL_IMAGES = YES
FISHBALL_FPGA_P25_INSTALL_TARGET = NO

define FISHBALL_FPGA_P25_INSTALL_IMAGES_CMDS
	$(UNZIP) -o $(@D)/$(FISHBALL_FPGA_P25_SOURCE) '*.bit' -d $(@D)
	if [ -f $(@D)/system_top.bit ]; then \
		cp -f $(@D)/system_top.bit $(BINARIES_DIR); \
	elif [ -f $(@D)/system_top_bad_timing.bit ]; then \
		cp -f $(@D)/system_top_bad_timing.bit $(BINARIES_DIR)/system_top.bit; \
	fi
endef

$(eval $(generic-package))
