# HP-12C CE multi firmware: what the current build has, and the gap to the target

Read-only check, 2026-10-10 (Europe/Madrid), with the native core (whole-calculator engine).
Nothing was flashed or changed.

Target (Jose): one firmware switching between **12C**, **15C in 15.2 (long-memory) mode**, and
**16C with our Path-C extended memory**.

## Files looked at

| File | MD5 | CE 2.C | Note |
|------|-----|--------|------|
| `/workspace/HP12c-multi.bin` | `c2a2e17284294db8c792c76d677606d2` | BDBDh | current keeper (install guide `HP12c-multi-install.md`) |
| `/workspace/hp-multiunit-12-15-16.bin` | – | – | older base, same three ROMs |
| notes `HP12c-multi-notes.md` | describe `ca56b586…` (8080h) and `343a918c…` (FEFEh) | | earlier keepers of the same lineage; ROMs and switcher unchanged |

## Core status

* The core recognises the multi (paint routine at flash `0x18D92`) as family `VC_FAMILY_MULTI`,
  boots it in the whole engine (cold start shows `Pr Error`, then a working 12C: `1 2 ENTER 3 +` → `15.00`).
* The calculator's own switch works in the emulator: off, **g-ENTER-ON** → `1.L2.C3.H`, **4** →
  `12 15.2  16`, then a key under the label: matrix keys 3-4 (PMT, FV) = 15.2, 5-6 (CHS, 7) = 16,
  key 1 (i) = 12 (tested from 16C mode back to 12C). Each switch is a cold start (`Pr Error`): user memory is cleared.
* `vc_model()` follows the switch at run time; `vc_model_variant()` gives 120 / 150 / 152 / 160.
  Detection is by ROM content, not address (the selected Nut ROM's flash address is at SRAM
  `0x20000010`; addresses differ between builds). Tested by `tests/test_multi.c`.
* Not available in multi or 15C firmware: the fast program runner (16C CE firmware only).
  The app uses the whole engine for these, which is the normal mode anyway.

## Per mode: current build vs target

| Mode | Current build | Target | Gap |
|------|---------------|--------|-----|
| 12C | 12C ROM (flash `0x4180`), works | 12C | none |
| 15C | **one** 15C mode, labelled 15.2. ROM at flash `0x7180` has the long-memory markers (Nut words `0x356`/`0xBE9` = `0x040`), so it is the 15.2 / long-memory ROM. There is no 15.0 mode. `g MEM` after the switch shows `94 99 00-0`. | 15C in 15.2 mode | Mode exists. Open question for Jose: its ROM is a different revision from the 15.2 ROM in our 15C 3-ROM builds (776 Nut words differ; that build shows `19 174 00-0` after reset). Decide which 15.2 ROM is wanted. |
| 16C | 16C ROM (flash `0xE180`), **stock memory**: `f MEM` → `P-0  r-101` at WSIZE 16 (203-nibble pool) | 16C with Path-C extended memory (our dedicated B7B7 build shows `P-0 r-0616`) | **Missing.** See below. |

## What giving the multi Path-C extended memory takes

1. **Nut ROM**: the multi's 16C ROM differs from our Path-C 16C ROM in 60 Nut words
   (first ones at 0x0B0, 0x1D4, 0x1DB-0x1DD, 0x1E6-0x1EC, 0x1FF-0x200, 0x250-0x253, 0x2B1 ...:
   f MEM, clear-pool curtain, register-select patches). Copy those words into the multi's
   16C ROM (file `0xA180`).
2. **ARM side**: Path-C adds the extended-register select / chip-base code (EXT pool inside the
   2 KB VoyagerSave window at `0x20000180`, `zero_ext` clear length, `new_select` upper bound).
   In the multi this must be (a) reassembled against the multi's helpers (call targets differ,
   as with the debounce menus), (b) gated on the active ROM being 16C, because the 15.2 ROM
   uses its own long-memory RAM, and (c) checked against the SRAM the 15.2 mode uses so the
   two do not overlap (they never run at the same time, and a switch cold-starts, so sharing
   the area is possible).
3. Cave space after the menus (`0x1A570`… is partly used by the debounce menus), then CE 2.C byte last.
4. Test in this core: `test_multi` already switches modes; add `f MEM` = Path-C value in 16C mode,
   and STO/RCL of the top register, then on the calculator.

## Also found

The 15C 3-ROM builds (`hp15c-3rom-…-C8C8.bin`) are multi-ROM too (15 / 15.2 / 16, menu `15 15.2  16`).
The core loads them as 15C family and `vc_model()` follows their switch as well (15.0 `g MEM` `19 78 00-0`,
15.2 `19 174 00-0`, 16 → 16C).

## App consequences (built into the model abstraction)

* The firmware picks a **family**; the **active model** can change while running. The app polls
  `vc_model()` after every display update and swaps the keyboard skin, legends, shortcut
  map and display quirks when it changes.
* Key matrix positions are the same on all three models, so the key code the user presses does
  not depend on the skin; only legends and the hardware-keyboard map change.
* Saved memory files: a `.16c` file only makes sense in 16C mode; the app names files by the
  active model (`.12c`, `.15c`, `.16c`) and warns before loading one into another mode.
