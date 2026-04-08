#!/usr/bin/env bash
###############################################################################
# build.sh — Tezuka Firmware Build Script (runs inside Docker)
#
# Syncs source from the Windows mount into the Docker volume's ext4
# filesystem, then builds using Buildroot. The Docker volume preserves
# the build cache (toolchain, packages) across runs.
#
# Launched by build.bat — do not run directly on Windows.
#
# Environment:
#   SRC_MOUNT   Path to Windows project mount (read-only)
#   BUILD_HOME  /home/br-user/tezuka_build (Docker volume, ext4)
###############################################################################
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
BUILD_HOME="/home/br-user/tezuka_build"
SRC_MOUNT="${SRC_MOUNT:-/mnt/src}"
DEFCONFIG="${DEFCONFIG:-fishball_maiasdr_7020_defconfig}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[BUILD]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
info() { echo -e "${CYAN}[INFO]${NC} $*"; }

# ── Step 1: Sync source from Windows mount to Docker volume ──────────────────
log "=== Tezuka Firmware Build (Fishball Z7020) ==="
echo ""
info "Source (Windows mount): $SRC_MOUNT"
info "Build dir (ext4 volume): $BUILD_HOME"
info "Defconfig: $DEFCONFIG"
echo ""

if [ ! -d "$SRC_MOUNT/board" ]; then
    err "Source mount not found at $SRC_MOUNT"
    err "This script should be launched by build.bat"
    exit 1
fi

mkdir -p "$BUILD_HOME"

log "Step 1: Syncing source from Windows mount to Docker volume..."
info "  (preserves buildroot/ cache, syncs board/, configs/, package/, etc.)"

rsync -a --delete \
    --exclude='buildroot/' \
    --exclude='output_images/' \
    --exclude='.git/' \
    --exclude='*.zip' \
    "$SRC_MOUNT/" "$BUILD_HOME/"

log "  ✓ Source synced"

# ── Step 2: Fix Windows CRLF line endings ─────────────────────────────────────
log "Step 2: Fixing CRLF line endings..."
# Strip CRLF from all text files in our source tree (excludes buildroot/ cache
# and binary files). No maxdepth limit — overlay files are 6-7 levels deep.
find "$BUILD_HOME" -not -path '*/buildroot/*' -not -path '*/.git/*' -type f \
    -not -name '*.elf' -not -name '*.bit' -not -name '*.xsa' -not -name '*.bin' \
    -not -name '*.gz' -not -name '*.zip' -not -name '*.pdf' -not -name '*.png' \
    -not -name '*.jpg' -not -name '*.ico' -not -name '*.lz4' \
    -exec sed -i 's/\r$//' {} +
log "  ✓ CRLF→LF conversion complete"

# ── Step 3: Set up git repo for version tagging ──────────────────────────────
cd "$BUILD_HOME"
if ! git describe --tags >/dev/null 2>&1; then
    log "Step 3: Creating git repo in build volume for version tagging..."
    [ ! -d "$BUILD_HOME/.git" ] && git init -q
    git config user.email "build@tezuka"
    git config user.name "tezuka-build"
    git add -A >/dev/null 2>&1 || true
    git commit -q --allow-empty -m "tezuka fishball-dev build"
    git tag -a "v0.2.4-dev" -m "tezuka fishball-dev" 2>/dev/null || true
    log "  ✓ Git repo ready"
else
    log "Step 3: Git repo already exists ($(git describe --tags 2>/dev/null || echo 'no tags'))"
fi

# ── Step 4: Download buildroot if needed ──────────────────────────────────────
cd "$BUILD_HOME"
if [ ! -d "buildroot" ]; then
    log "Step 4: Downloading buildroot (first time, ~2 min)..."
    bash getbuildroot.sh
    log "  ✓ Buildroot downloaded and patched"
else
    log "Step 4: Buildroot already cached ✓"
fi

# ── Step 5: Set up BR2_EXTERNAL ───────────────────────────────────────────────
log "Step 5: Setting up BR2_EXTERNAL..."
unset BR2_EXTERNAL
export BR2_EXTERNAL=""
source "$BUILD_HOME/sourceme.first"
info "  BR2_EXTERNAL=$BR2_EXTERNAL"

# ── Step 6: Configure and build ──────────────────────────────────────────────
cd "$BUILD_HOME/buildroot"

# Fix PATH (remove entries with spaces — buildroot requirement)
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v ' ' | tr '\n' ':' | sed 's/:$//')

log "Step 6: Applying defconfig ($DEFCONFIG)..."
make "$DEFCONFIG"
log "  ✓ Defconfig applied"

echo ""
log "Step 7: Building firmware..."
info "  First build: 1-3 hours | Cached rebuild: 20-40 min"
info "  Building on ext4 filesystem for proper symlink support"
echo ""

CMAKE_POLICY_VERSION_MINIMUM=3.5 make

# ── Step 8: Copy output back to Windows mount ─────────────────────────────────
echo ""
log "=== Build Complete ==="
echo ""

NATIVE_SDIMG="$BUILD_HOME/buildroot/output/images/sdimg"
# SRC_MOUNT is read-only, so we write to a writable output path
# The bat file mounts the project dir — we need a writable mount for output
# For now, copy to a location inside the volume and report
OUTPUT_VOLUME="$BUILD_HOME/output_images"

if [ -d "$NATIVE_SDIMG" ]; then
    log "Build output:"
    ls -lh "$NATIVE_SDIMG"
    echo ""

    mkdir -p "$OUTPUT_VOLUME"
    cp -a "$NATIVE_SDIMG/." "$OUTPUT_VOLUME/"

    if [ -f "$BUILD_HOME/buildroot/output/images/tezuka.zip" ]; then
        cp "$BUILD_HOME/buildroot/output/images/tezuka.zip" "$OUTPUT_VOLUME/"
    fi

    log "✓ Images staged in Docker volume at: $OUTPUT_VOLUME"
    echo ""

    # Try to copy to Windows mount if writable
    WIN_OUTPUT="$SRC_MOUNT/output_images"
    if mkdir -p "$WIN_OUTPUT" 2>/dev/null; then
        cp -a "$NATIVE_SDIMG/." "$WIN_OUTPUT/"
        [ -f "$BUILD_HOME/buildroot/output/images/tezuka.zip" ] && \
            cp "$BUILD_HOME/buildroot/output/images/tezuka.zip" "$WIN_OUTPUT/"
        log "✓ Images copied to Windows: $WIN_OUTPUT"
    else
        warn "Windows mount is read-only. Images are in Docker volume."
        info "To extract: docker run --rm -v tezuka-build:/data -v \"%cd%:/out\" alpine cp -a /data/output_images/. /out/output_images/"
    fi
else
    err "Build output not found at $NATIVE_SDIMG"
    err "Build may have failed. Check output above."
    exit 1
fi

echo ""
log "=== Next Steps ==="
info "1. Copy output_images/sdimg/ contents to a FAT32 SD card"
info "2. Boot Fishball Z7020 from SD card"
info "3. Verify model string:"
info "   ssh root@192.168.120.50 'cat /sys/firmware/devicetree/base/model'"
info "   Expected: FISH Ball PlutoSDR Rev.A (Z7020/AD9361)"
echo ""
