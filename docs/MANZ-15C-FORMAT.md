# Torsten Manz HP-15C Simulator program files (.15c / .txt)

Implemented in `app/Sources/Core/Manz15CProgram.swift` (our own code, written from the HP-15C keycode rules; the GPL
simulator source was only read as a reference). Reference spec used: the box's `/workspace/manz/FORMAT.md`.

- Reading: BOM decides the encoding (UTF-16LE/BE, UTF-8), else UTF-8, else Windows-1252. Only the `{ ... }` keycodes of each
  step line count; the mnemonic text is ignored. `.d` / `,d` tokens (row-less digit keys after f/g/STO/RCL/GTO…) and `u`
  (USER-mode step) are handled; step `000` is skipped and steps are renumbered. Errors name the file line.
- Notes: `#T` title, `#D` description, `#L` labels (`L-1..-5` = A..E, `L10..19` = .0-.9), `#R` registers, `#F` flags go into
  the program notes.
- Import keys each step into the emulated HP-15C in program mode; the firmware itself encodes the steps. Fit is checked against
  free memory first; on any error the calculator memory is restored.
- Writing: UTF-16LE with BOM, CRLF, the simulator's header (`Created with version 4.6.00`), `   %03d {%12s } %s` per step.
  The `u` mark is kept only while the program is still the one last imported (the calculator listing has no USER flag).
