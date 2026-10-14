# VoyagerCalc: the app

SwiftUI app for macOS, iPadOS and iOS. It runs your own CE firmware (12C, 15C or 16C,
including multi-model builds) on the native C core in `../core`. MIT licence (`../LICENSE`).
No firmware and no HP artwork are included.

## Open and run it in Xcode (Mac)

1. Open `app/VoyagerCalc.xcodeproj` in Xcode. Keep the whole
   `VoyagerCalc` folder: the project uses `../core`.
2. At the top of the window, choose the scheme **VoyagerCalc-macOS** and **My Mac**.
3. Press **⌘R**. The project is set to "Sign to Run Locally", so you do not need a team.
4. On first launch click **Choose Firmware File…** and pick your `.bin` file, for example
   `~/Firmware/Voyager16-ext-path-c-trim4-show-B7B7.bin`. The app remembers it.
5. Tests: choose **VoyagerCalc-macOS** (or **VoyagerCalcTests**) and press **⌘U**. The tests look for
   firmware in `~/Firmware` (or `$VC_FIRMWARE_DIR`) and write PNG snapshots to
   `$TMPDIR/VoyagerCalcScreens`.

iPhone / iPad: choose the **VoyagerCalc-iOS** scheme and a simulator, then ⌘R. Pick the firmware from
Files. To run it on your own iPhone, select the VoyagerCalc-iOS target, open
*Signing & Capabilities*, and choose your team.

## Using it

* **Face:** if photo faces are present in `Resources/Faces/` (not included in this repository), the
  calculator is that photo with the live display drawn on its empty LCD glass; otherwise, and with
  **Face → Drawn**, it is the app's own vector drawing. **Face → Drawn** in the menu switches to our own vector
  drawing. On an **iPhone held upright** the app always shows the drawn face with the keyboard in
  two stacked halves, because the landscape photo would be too small to tap there. Turn the phone
  sideways to get the photo. Mac, iPad and iPhone in landscape use the photo.
* **Keys:** click or tap them. On the photo, each key answers over its cap, its gold legend and
  half of the gap beside it. A pressed key sinks and darkens. A key stays down while you hold the
  mouse button or your finger. On a Mac, hover over a key to see its keyboard shortcut.
* **Keyboard (Mac and iPad):** digits, `. + - * /`, **Return** = ENTER, **Delete** = ⬅ (back-arrow
  / CLx), **A–F** = hex digits (16C), **Shift** tapped on its own = **f**, **Option** tapped on its own
  = **g**, and Option+key = g then that key. Shift still types `* + _ %`. **Esc** = ON.
  * 16C: GSB U, GTO T, HEX H, DEC K, OCT O, BIN I, R/S R, SST →, R↓ ↓, x≷y W, STO S, RCL L,
    CHS N or _, × also X, ENTER also =.
  * 15C: √x Q, eˣ E, 10ˣ W, yˣ Y, 1/x V, CHS N, SST →, GTO T, SIN I, COS O, TAN P, EEX K,
    R/S R, GSB U, R↓ ↓, x≷y J, STO S, RCL L, Σ+ Z.
  * 12C: n M, i I, PV P, PMT J, FV V, CHS N, yˣ Y, 1/x E, %T T, Δ% D, % %, EEX K, R/S R, SST →,
    R↓ ↓, x≷y W, CLx Delete, STO S, RCL L, Σ+ Z.
* **Menu** (Mac menu bar, and the ⋯ button on every platform):
  * Turbo (⌘T)
  * ON / OFF
  * Service Menu (g-ENTER-ON)
  * Open / Save Memory File (⌘O / ⌘S)
  * Keyboard (Automatic, or pick a face yourself)
  * Face (Photo / Drawn)
  * Choose Firmware
  * Reset Calculator
  * About
* **Speed:** real calculator speed by default. Turbo runs the chip as fast as the Mac allows
  (about 25× on the box).
* **Memory:** the calculator keeps its memory between launches, like the real one. When you
  quit, the app turns it off and saves its 2 KB memory. Memory files are VoyagerSave `.16c` /
  `.15c` / `.12c` (2048 bytes). Files and AirDrop work on iOS too.
* **Multi firmware:** switch models on the calculator itself (g-ENTER-ON, 4, pick). The keyboard
  face follows what runs. The app also remembers which model ran, and comes back to it on the
  next launch.

## Layout

| Path | What |
|---|---|
| `Sources/Core` | Swift side of the core: `VoyagerCalculator` (C wrapper), `CalculatorMachine` (boot, restore, finger-held keys, model switch), `CalculatorEngine` (own thread, real time / turbo) |
| `Sources/Models` | `CalculatorModel` and the 16C / 15C / 12C faces **as data**: legends, key codes, shortcuts, colours, annunciators, file type; `PhotoFace` + `PhotoFaceGeometry.swift` (generated: measured key and LCD rectangles on the photos) |
| `Sources/App` | app state, firmware store (bookmark on Mac, copy on iOS), state store, memory files, keyboard router, `@main` |
| `Sources/Views` | calculator: `PhotoFaceView` (photo face, default), drawn face (`CalculatorView`, `KeyView`), `LCDView`, welcome, About, hardware keyboard |
| `Resources/Faces` | the three empty-LCD photo faces the app bundles (made by `../art/tools/make_faces.py`) |
| `Tests/KitTests` | wrapper / machine / model tests (also run on Linux with `swift test` from the repo root) |
| `Tests/AppTests` | snapshot renders of the faces (macOS) |
| `VoyagerCalc.xcodeproj` | written by `tools/genproj.py` (re-run it after adding files); `project.yml` is the same for XcodeGen |
| `tools/preview.py` | box preview renderer (Pillow port of the photo face and the drawing), used when no Mac is at hand; `tools/preview_lcd/` has display states from the real core |

## App Store notes (not submitted, just risks)

* Emulators are allowed (guideline 4.7). This one runs only firmware that you supply, and the
  app contains no ROM.
* **The photo faces still show the HP logo. It must be replaced or removed before any
  submission** (Jose will supply a replacement). Also confirm the rights to the 15C CE / 16C CE
  front pictures (`../art/SOURCES.md`).
* Do not use HP names or logos in the app name, icon or screenshots. Keep "Not affiliated with
  HP Inc." in About (it is there). The model numbers describe compatibility only. Apple may
  still ask about them (guideline 5.2).
* iOS uses the interpreter only (no JIT, no downloaded code), so guideline 2.5.2 is fine.
* The bundle id `com.josegonzalezdivasson.VoyagerCalc` is a placeholder. Change it before
  signing with your team.
