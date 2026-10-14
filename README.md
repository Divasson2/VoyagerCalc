# VoyagerCalc

A macOS app (SwiftUI) that runs the firmware of an HP-12C, HP-15C or HP-16C Collector's Edition
calculator, which **you supply yourself**, on a native emulator of the calculator's ARM chip. It
adds an inspector (stack, registers, flags, the 15C memory pool and matrices, the program listing),
program documentation as PDF or text, and reading and writing the memory of a real calculator over USB.

> **Disclaimer.** VoyagerCalc is an independent project. It is not affiliated with, authorised or
> endorsed by HP Inc. or Moravia. HP, HP-12C, HP-15C, HP-16C and other names are trademarks of
> their respective owners and are used only to describe compatibility. The software is provided
> "as is", without warranty of any kind; use it at your own risk, including when writing to a
> real calculator (the app makes a backup of the calculator's memory first).

## No HP firmware included

This repository and the app contain **no HP firmware, ROM images or memory dumps** and no
third-party programs. On first launch the app asks for a firmware file (`.bin`) that you have
the right to use, for example one taken from your own calculator. The app remembers your choice.

Optional fonts for the documentation PDF (Torsten Manz's freeware *HP15C Simulator* display font
and an HP 15C key-cap font) are not included either, because they have no redistribution licence.
If you have them, choose them in **File ▸ PDF Fonts**; the HP15C Simulator font is available from
Torsten Manz's HP-15C Simulator website. Without them the PDF uses system fonts.

## Download and install

1. Download `VoyagerCalc-<version>-macOS.zip` from the
   [Releases](https://github.com/Divasson2/VoyagerCalc/releases) page.
2. Unzip it and move **VoyagerCalc.app** to **Applications**.
3. Open it and choose your firmware file.

Requires macOS 14 or later.

## Build from source

Requirements: a Mac with Xcode 15 or later.

1. Clone the repository: `git clone https://github.com/Divasson2/VoyagerCalc.git`
2. Open `app/VoyagerCalc.xcodeproj` in Xcode (keep the whole folder: the project uses `core/`).
3. Choose the scheme **VoyagerCalc-macOS** and **My Mac**, then press **⌘R**. The project signs to run
   locally, so no developer team is needed.
4. Tests: **⌘U**. Tests that need a firmware file or a memory image are skipped unless you point
   `VC_FIRMWARE_DIR` / `VC_FIXTURES_DIR` at your own files.

The C core can also be built and tested on its own (`core/`, see `core/README.md`), and
`Package.swift` builds the core and model data as a Swift package.

Layout: `core/` the portable emulator core, `app/` the SwiftUI app and Xcode project, `art/` the
app icon and image tools, `docs/` technical notes (memory map of the HP-15C pool, USB link).

## Licence

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 José González Divassón.
