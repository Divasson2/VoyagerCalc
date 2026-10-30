# VoyagerCalc

Calculator app for macOS, iPadOS and iOS that runs your own 12C / 15C / 16C CE firmware on
a native emulator of the calculator's ARM chip. MIT licence (`LICENSE`).
Not affiliated with HP Inc.

* `core/`: the portable C core (Cortex-M4 + SAM4L model), CLI and tests. See `core/README.md`.
* `app/`: the SwiftUI app and Xcode project. See `app/README.md` (how to open and run it).
* `Package.swift`: core + Swift wrapper + model data as a Swift package (`swift test`, also on Linux).
* `art/`: photo faces made from the shop's product photos: originals, sources (`art/SOURCES.md`), pipeline (`art/README.md`).
* `docs/`: reports (multi firmware). `screens/`: screenshots. `PROGRESS.md`: status.

> **HP logo badge: done (0.5).** The HP badge at the top right of each photo face is covered by
> the app's own three-panel logo (12C / 15C / 16C, `art/icon/AppIcon-square-1024.png`; painted
> by `art/tools/make_faces.py`, square in `art/tools/badges.json`).
> **Still before any App Store submission:** the 15C and 16C faces still carry HP's
> "Collector's Edition" script under the logo, and the key layout/legends are HP's design;
> decide what to do with those, and confirm the rights to the 15C CE / 16C CE front pictures
> (see `art/SOURCES.md`).

Keys: click a key for the key, its gold legend above for f + key, its blue legend on the key's
front for g + key (e.g. the gold LBL over SST, then A = f LBL A). ⌘-click / right-click latches
a key (Mac), long-press latches it (iOS). Keyboard: Shift alone = f, Option alone = g,
Option + key = g + key.

Program documentation (0.5.6): double-click a line in the inspector's program list to comment it;
File ▸ Program Info… for the title, description and label / register / flag notes (labels,
registers and flags used are detected from the program); File ▸ Export Program Documentation
(PDF)… (A4 or US Letter) or Export Listing as Text…. Notes are saved as "<memory file>.voyagerdoc"
next to the memory file (File ▸ Save / Open Program Notes…). The 12C program is listed too.

**PDF fonts (0.5.7, bundled in 0.6.7):** the documentation PDF shows the program display in seven segments and the
15C keystrokes as key caps. Since 0.6.7 the two HP15C Simulator fonts (display and key caps) are part of the app
(Contents/Resources, `app/Resources/Fonts/`) and the PDF always uses them; there is nothing to install or choose.

**Fonts credit:** the documentation PDF fonts included with the app are the key-cap font by Eric Rechlin and the
seven-segment display font by Torsten Manz (HP15C Simulator Font © 2005 Torsten Manz, Freeware). The files are renamed
copies (name table only) and keep their copyright notices. See `art/fonts/README.md`.

**Photographs credit:** HP-15C and HP-16C calculator photographs (front and back) by Warren Young.
