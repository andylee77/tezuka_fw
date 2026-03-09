# Tezuka Firmware — Developer Log

Reference for scripts, tools, and infrastructure in the `andylee77/tezuka_fw` fork.

---

## Repository Layout

```
tezuka_fw/
├── CHANGELOG.md              ← Project tracking log (changes, builds)
├── DEVLOG.md                 ← This file (scripts, tools reference)
├── build.bat                 ← Windows build launcher
├── build.sh                  ← Docker inner build script
├── getbuildroot.sh           ← Downloads Buildroot (upstream)
├── make_all.sh               ← Upstream multi-target build script
├── sourceme.first            ← Sets BR2_EXTERNAL for Buildroot
├── update_bitstream.sh       ← FPGA bitstream updater
│
├── board/tezuka/
│   ├── fishball7010/         ← Z7010 board files (upstream, untouched)
│   ├── fishball7020/         ← Z7020 board files (NEW — our fork)
│   │   ├── dts/
│   │   │   ├── fishball.dts      ← Top-level device tree
│   │   │   ├── fishball.dtsi     ← Main DTS include (model: Z7020/AD9361)
│   │   │   └── zynq-7000.dtsi   ← Zynq SoC base definitions
│   │   └── u-boot-dts/
│   │       └── zynq-pluto-sdr.dts  ← U-Boot device tree (model: 7020-AD9361)
│   ├── common/               ← Shared overlays, post-build scripts
│   └── ...                   ← Other board targets (pluto, e200, etc.)
│
├── configs/                  ← Buildroot defconfigs
│   ├── fishball_maiasdr_7020_defconfig  ← Our target (MODIFIED)
│   └── ...
│
├── doc/
│   ├── changes/
│   │   └── 001_z7020_model_string_fix.md  ← Detailed fix documentation
│   └── schematics/           ← Hardware schematics (PDFs)
│
├── package/                  ← Buildroot external packages
│   ├── maia-httpd/           ← Maia SDR HTTP daemon
│   ├── maia-wasm/            ← Maia SDR web UI (WASM)
│   ├── maia-kmod/            ← Maia kernel module
│   ├── fishball_fpga_7020/   ← FPGA bitstream package
│   └── ...
│
├── output_images/            ← Build output (gitignored)
│   ├── BOOT.bin              ← First-stage bootloader
│   ├── devicetree.dtb        ← Device tree blob
│   ├── uImage                ← Linux kernel
│   ├── uramdisk.image.gz     ← Root filesystem
│   ├── uEnv.txt              ← U-Boot environment
│   ├── tezuka.zip            ← Complete firmware package
│   └── overclock/            ← Overclock BOOT.bin variants
│
└── tools/                    ← Utility scripts
    ├── jtag-recovery/        ← Brick recovery via JTAG
    └── m8100k/               ← GPSDO config utility
```

---

## Scripts Created (andylee77 fork)

### `build.bat` — Windows Build Launcher

**Location:** `tezuka_fw/build.bat`
**Created:** 2026-03-08 | **Commit:** `7505426`

Launches Docker with the build environment. Handles Windows path conversion,
Docker image/volume management, and argument parsing.

```
Usage:
  build.bat                  Full build (reuses cache)
  build.bat --clean          Delete cache, start fresh (1-3 hrs)
  build.bat --interactive    Open Docker shell for manual work
```

**Key details:**
- Docker image: `br_tezuka:2025.02.3`
- Docker volume: `tezuka-build` (persistent build cache on ext4)
- Mounts Windows project dir into container
- Uses `-i` (not `-it`) for VS Code compatibility
- Interactive mode uses `-it` for proper TTY

---

### `build.sh` — Docker Inner Build Script

**Location:** `tezuka_fw/build.sh`
**Created:** 2026-03-08 | **Commit:** `7505426`

Runs inside the Docker container. Handles the actual build process.

**Steps:**
1. **Rsync source** from Windows mount → Docker volume (preserves buildroot cache)
2. **Fix CRLF** line endings (Windows → Linux)
3. **Git repo setup** in volume for version tagging (`v0.2.4-dev`)
4. **Download Buildroot** if not cached (`getbuildroot.sh`)
5. **Set BR2_EXTERNAL** via `sourceme.first`
6. **Apply defconfig** (`fishball_maiasdr_7020_defconfig`)
7. **Build firmware** with `CMAKE_POLICY_VERSION_MINIMUM=3.5 make`
8. **Copy output** back to Windows mount (`output_images/`)

**Environment variables:**
- `SRC_MOUNT` — Path to Windows project mount (set by build.bat)
- `BUILD_HOME` — `/home/br-user/tezuka_build` (Docker volume)
- `DEFCONFIG` — `fishball_maiasdr_7020_defconfig`

**Why Docker volume?** Buildroot needs ext4 (symlinks, case-sensitivity, fast I/O).
Building directly on Windows NTFS mount is ~10-50x slower and breaks symlinks.

---

## Infrastructure

### Docker Image: `br_tezuka:2025.02.3`

Pre-built image with all Buildroot dependencies (GCC, make, Rust toolchain,
wasm-pack, Bootgen, etc.). Size: 2.54 GB.

To rebuild from scratch (if needed):
```bash
cd buildroot/support/docker
docker build -t br_tezuka:2025.02.3 .
```

### Docker Volume: `tezuka-build`

Persistent ext4 filesystem storing:
- `buildroot/` — Downloaded Buildroot + build cache (~15 GB)
- `output_images/` — Last build output
- ARM toolchain, downloaded sources, compiled packages

**Inspect contents:**
```bash
docker run --rm -v tezuka-build:/data alpine ls -la /data/
```

**Extract images from volume:**
```bash
docker run --rm -v tezuka-build:/data -v "%cd%:/out" alpine cp -a /data/output_images/. /out/output_images/
```

**Delete cache (fresh start):**
```bash
docker volume rm tezuka-build
```

### Git Remotes

| Remote | URL | Purpose |
|--------|-----|---------|
| `origin` | `https://github.com/andylee77/tezuka_fw.git` | Your fork |
| `upstream` | `https://github.com/F5OEO/tezuka_fw.git` | Original project |

### Branches

| Branch | Purpose |
|--------|---------|
| `main` | Tracks upstream, clean for syncing |
| `fishball-dev` | Active development (Fishball Z7020 changes) |

---

## Build Cheat Sheet

```bash
# Full build (from Windows)
build.bat

# Interactive Docker shell (for debugging)
build.bat --interactive

# Inside interactive shell:
cd /home/br-user/tezuka_build/buildroot
make menuconfig                          # Browse/edit config
make linux-rebuild                       # Rebuild kernel only
make uboot-rebuild                       # Rebuild U-Boot only
make maia-wasm-dirclean && make          # Force rebuild maia-wasm

# Check current defconfig
make savedefconfig
diff defconfig ../configs/fishball_maiasdr_7020_defconfig

# Clean everything (nuclear option)
build.bat --clean
```

---

## Related Repositories

| Repo | Branch | Purpose |
|------|--------|---------|
| `andylee77/tezuka_fw` | `fishball-dev` | This firmware (Buildroot + board files) |
| `andylee77/maia-sdr` | `fishball-dev` | Maia SDR fork (maia-httpd, maia-wasm) |
| `andylee77/maia-hdl` | — | Maia HDL fork (FPGA gateware) |

---

## Session Log

| Date | Session | What was done |
|------|---------|---------------|
| 2026-03-08 | Initial setup | Forked repo, created `fishball-dev` branch, pointed maia packages to fork |
| 2026-03-08 | Change 001 | Z7020 model string fix — new DTS files, defconfig update |
| 2026-03-08 | Build infra | Created `build.bat`/`build.sh`, set up Docker build pipeline |
| 2026-03-08 | Build 001 | First successful firmware build (~3 min cached), output verified |
