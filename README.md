# tezuka_fw — Fishball Z7020 Fork

[![Upstream](https://img.shields.io/badge/upstream-F5OEO%2Ftezuka__fw-blue)](https://github.com/F5OEO/tezuka_fw)

Fork of [F5OEO/tezuka_fw](https://github.com/F5OEO/tezuka_fw) targeting the
**OpenSDRLab Fishball Z7020** (Zynq-7020 SoC + AD9361 RF transceiver).

Built on [Buildroot](https://buildroot.org/) with
[Maia SDR](https://maia-sdr.org/) for spectrum analysis.

## What this fork adds

- **Z7020-specific device tree** — correct model string (`Z7020/AD9361`) in both
  Linux and U-Boot, under `board/tezuka/fishball7020/`
- **Windows Docker build pipeline** — `build.bat` / `build.sh` for building on
  Windows via Docker with a persistent ext4 volume
- **CRLF boot fix** — robust line-ending conversion that catches all overlay files
  (upstream assumes Linux-native LF)
- **Maia SDR packages** pointed at [`andylee77/maia-sdr`](https://github.com/andylee77/maia-sdr)
  fork (`fishball-dev` branch)

See [CHANGELOG.md](CHANGELOG.md) for the full history and
[doc/changes/](doc/changes/) for detailed write-ups of each change.

## Quick start

### Prerequisites

- Windows 10/11 with Docker Desktop
- Docker image `br_tezuka:2025.02.3` (see [DEVLOG.md](DEVLOG.md) for build instructions)

### Build

```bat
build.bat                   # Full build (~3 min incremental, 1-3 hrs from scratch)
build.bat --interactive     # Open a shell inside the Docker build environment
build.bat --clean           # Delete build cache and start fresh
```

Build output lands in `output_images/`.

### Flash to SD card

1. Format an SD card as FAT32
2. Copy the contents of `output_images/` to the card
3. Boot the Fishball Z7020 from SD

### Verify

```bash
ssh root@192.168.120.50 'cat /sys/firmware/devicetree/base/model'
# Expected: FISH Ball PlutoSDR Rev.A (Z7020/AD9361)
```

## Building on Linux

If you're on Linux (or WSL2) you can build without Docker:

```bash
git clone https://github.com/andylee77/tezuka_fw
cd tezuka_fw
./getbuildroot.sh
source sourceme.first
cd buildroot
make fishball_maiasdr_7020_defconfig && make
```

See upstream [Buildroot requirements](https://buildroot.org/downloads/manual/manual.html#requirement-mandatory)
for host dependencies. Maia SDR additionally needs:

```bash
sudo apt install pkg-config libssl-dev libclang-dev
```

## Repository layout

```text
board/tezuka/fishball7020/   Z7020-specific DTS and U-Boot files (this fork)
board/tezuka/common/         Shared overlays and post-build scripts
configs/                     Buildroot defconfigs
package/                     External Buildroot packages (maia-httpd, maia-wasm, etc.)
doc/changes/                 Detailed change documentation
output_images/               Build output (gitignored)
```

## Branches

| Branch         | Purpose                                                    |
|----------------|------------------------------------------------------------|
| `main`         | Tracks upstream `F5OEO/tezuka_fw` — kept clean for syncing |
| `fishball-dev` | Active development branch                                  |

## Related repositories

| Repo                                                          | Purpose                             |
|---------------------------------------------------------------|-------------------------------------|
| [andylee77/maia-sdr](https://github.com/andylee77/maia-sdr)  | Maia SDR fork (httpd + wasm + FPGA) |
| [F5OEO/tezuka_fw](https://github.com/F5OEO/tezuka_fw)        | Upstream firmware project           |

## Credits

This fork builds on the work of:

- **F5OEO** — original tezuka_fw project
- **Daniel Estevez** — [Maia SDR](https://maia-sdr.org/)
- The PlutoSDR and Buildroot open-source communities
