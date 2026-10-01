#!/bin/sh
# P25-specific rootfs adjustments. Runs AFTER the shared
# post-build.sh, so it can reach into TARGET_DIR to delete or
# tighten files the upstream Tezuka overlay drops in.
#
#   1. Strip the legacy DATV daemons that overlay_tezuka pulls in.
#      `mosquitto` (MQTT broker) + `S95bgcript` (which launches
#      `api_controller.sh` + a handful of DATV watchers) burn ~50 %
#      of one A9 core for the first ~5 min after boot while
#      api_controller dumps the entire AD9361 IIO sysfs to MQTT
#      topics, then settle to <1 % chronic overhead. The scanner does
#      not consume any MQTT topic and talks to the FPGA via the IIO
#      kernel interface directly, so none of this is needed for the
#      P25 image.
#
#   2. Enforce strict mode bits on the root SSH authorized_keys
#      file. dropbear is somewhat permissive but locked-down is
#      correct — and the overlay file's perms come straight from
#      the host filesystem (Windows, in our case), which gives
#      group/other read by default.
#
#   3. Keep only the web daemon the defconfig selects.
set -e

# ── 1. Disable legacy DATV init scripts ──────────────────────────
rm -f ${TARGET_DIR}/etc/init.d/S50mosquitto
rm -f ${TARGET_DIR}/etc/init.d/S95bgcript

# ── 2. SSH key permissions ────────────────────────────────────────
if [ -f ${TARGET_DIR}/root/.ssh/authorized_keys ]; then
	chmod 700 ${TARGET_DIR}/root/.ssh
	chmod 600 ${TARGET_DIR}/root/.ssh/authorized_keys
fi

# ── 3. Only the selected web daemon ───────────────────────────────
# Buildroot never empties the target directory, so a daemon an earlier build installed (with
# its init script) stays in the image after the defconfig drops it, and would start too.
drop_unless_selected() {
	grep -q "^$1=y" "${BR2_CONFIG}" && return
	rm -f "${TARGET_DIR}/etc/init.d/$2" "${TARGET_DIR}/usr/bin/$3" "${TARGET_DIR}/usr/bin/$3.xz"
}
drop_unless_selected BR2_PACKAGE_SCANNER S60scanner scanner
drop_unless_selected BR2_PACKAGE_P25_HTTPD S60p25-httpd p25-httpd
drop_unless_selected BR2_PACKAGE_MAIA_HTTPD S60maia-httpd maia-httpd
