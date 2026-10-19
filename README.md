# BIT90 for MEGA65 — R3/R3A and R6 builds

This repository contains the VHDL sources and build scripts required to create
BIT90 FPGA bitstreams for the MEGA65 R3/R3A and R6 boards. It recreates the PAL
BIT90 home computer with its Z80 CPU, TMS9929A-compatible video, SN76489 audio,
keyboard, joysticks, configurable memory and FAT32 SD-card support.

The source snapshot is self-contained for synthesis, including the embedded
PAL V3.1 and XBasic ROM packages. It does not require a pre-existing Vivado
project, checkpoint, external ROM file or third-party source download.

## Requirements

- AMD Vivado with support for Artix-7 `xc7a200tfbg484-2`.
- Vivado 2025.2.1 was used for the verified R3 and R6 builds.
- The `vivado` command must be available in the shell. On Windows, the Vivado
  command prompt can be used.

Vivado supplies the UNISIM primitives and XPM memory components. All included
VHDL files are compiled as VHDL 2008.

## Build

Run one of these commands from the repository root:

```sh
vivado -mode batch -source scripts/build_r3.tcl
vivado -mode batch -source scripts/build_r6.tcl
```

The scripts run synthesis, implementation, DRC and final setup/hold timing
checks. A timing violation makes the build fail even if Vivado has already
written a bitstream.

| Board | Top entity | Generated bitstream |
| --- | --- | --- |
| R3 / R3A | `bit90_m2_r3` | `build/bit90_m2_r3.bit` |
| R6 | `bit90_m2_r6` | `build/bit90_m2_r6.bit` |

The R3 script recreates its generated Vivado project in `BIT90-MEGA65-R3/`.
The R6 script uses the non-project flow. Both generated areas are ignored by
Git. The scripts use 12 jobs; edit `-jobs 12` if the host needs a lower limit.

## Hardware behavior

- 720x576p50 video over HDMI and VGA.
- SN76489 audio over HDMI and, on R6, the 3.5 mm audio output.
- Original 18 KB configuration plus selectable 32 KB and 64 KB modes.
- Optional XBasic extension.
- Both MEGA65 joystick ports.
- ColecoVision-compatible cartridge images and controller input, including
  keyboard digits for cartridge keypad prompts.
- FAT32 SD browser with VFAT long-filename display.
- R3/R3A prefers the internal SD slot; R6 prefers the external slot. If the
  preferred slot cannot be initialized, the other detected slot is tried.
- WAV tape loading, ASCII BASIC loading, cartridge loading and `.BIT` memory
  dump loading/saving under `/BIT90` on the SD card.

The core's HELP overlay provides configuration, file browsers and an interactive
keyboard map. SD-card media are organized as follows:

```text
/BIT90/TAPES   (*.WAV)
/BIT90/CARTS   (*.COL, *.ROM, *.BIN)
/BIT90/BASIC   (*.BAS, *.BIT)
```

## Repository layout

- `rtl/`: BIT90 core, T80 CPU, VDP18, audio, video and storage sources.
- `constraints/`: MEGA65 R3/R3A and R6 pin/timing constraints.
- `scripts/sources.tcl`: deterministic source order.
- `scripts/build_r3.tcl`: complete R3/R3A build.
- `scripts/build_r6.tcl`: complete R6 build.
- `scripts/create_r3_project.tcl`: generated R3 Vivado project setup.

This is a build-source repository. Generated Vivado projects, bitstreams,
checkpoints, reports, local development helpers, test media, tools and release
archives are intentionally excluded. Packaging `.cor` files for the MEGA65 core
menu is a separate release step.

## Source and license notices

Copyright and license notices in imported source files are preserved. The T80,
VDP18, Tyto-derived, Digilent and SN76489 sources retain their respective
notices; this repository does not replace those notices with a blanket license.
`rtl/vdp18/COPYING` accompanies the VDP18 source.

The embedded ROM packages contain the firmware required for a reproducible
build. No new copyright or license is asserted for those firmware images.

BIT90 and ColecoVision are referenced for compatibility and identification.
This project is not affiliated with their original manufacturers.
