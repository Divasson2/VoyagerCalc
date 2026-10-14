# PROGRESS (Milestone 1: native C core, HP-16C CE)

Kept up to date while working, so the work can resume after an interruption.

- [x] 2026-10-10 16:55 Plan: Thumb-2 interpreter (src/cpu.c), memory/peripheral bus (src/machine.c),
      two engines mirroring the Python reference: "runner" (= voyager/runner16c.py) and
      "whole" (= voyager/wholecalc.py). API in include/voyager_core.h, CLI in tools/vcore.c.
- [x] 17:05 cpu.c (Thumb-2 interpreter), machine.c (runner + whole engines, API), sha256.c, tools/vcore.c, Makefile.
      Builds with clang 19 (installed on the box with apt), no warnings.
- [x] 17:08 Acceptance: B7B7 and B5B5 + miller-rabin, 2147483647 GSB A -> display "1 d", 2 KB memory
      byte-identical to voyagersim.py (md5 ee117c0d39b222485c47d1708d4f1286). f MEM P-2 r-0139.
- [x] 17:15 Random runner comparison (first CPU version): 300 seq B7B7 cold, 100 seq B7B7+mem, 100 seq B5B5+mem:
      all IDENTICAL (display + memory hash after every key).
- [x] 17:40 Whole engine: matched Unicorn's instruction counting (IT-block rule, see README) so the 10 ms
      time slices end on the same instruction as the Python model: per-slice log identical.
- [ ] rerun random runner comparisons with the final CPU; whole-engine random comparison; annunciator map;
      README; speed table.
- [x] 18:05 Final CPU: runner random 300+100+100 sequences IDENTICAL; whole random 60+40 IDENTICAL;
      long whole Miller-Rabin identical (hash 0c70f6962b2821cd, 126500 ms, 4614 sleeps).
      Annunciator bits f 6, g 9, C 21, G 14, PRGM 24. ASan/UBSan clean. README written.
      tests/run_all.sh repeats everything. Milestone 1 done.

## 2026-10-10 evening: models, LCD cells, multi firmware

* Model abstraction in the core: key tables for 12C / 15C / 16C (same matrix positions),
  `vc_firmware_family()`, run-time `vc_model()` / `vc_model_variant()` (follows the calculator's
  own model switch by recognising the running Nut ROM).
* 15C-family and HP-12C CE multi firmware now load and run in the whole engine.
* `vc_get_display_cells()` gives the drawn display (segments, points, commas, minus, raw
  annunciator bits) from the LCD memory; `tests/test_lcd.c`: 900/900 states identical to the Nut
  registers on the 16C.
* `tests/test_multi.c`: 12C → 15C (15.2) → 16C → 12C switching, OK on both multi builds.
* Report: `../docs/MULTI-FIRMWARE.md`.

## 2026-10-10 later
* Licence: MIT, SPDX headers everywhere. The app (milestone 2) is tracked in `../PROGRESS.md`.
