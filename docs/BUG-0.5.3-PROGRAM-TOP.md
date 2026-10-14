# 0.5.3 bug: Write to Calculator turns program lines 1-14 into f LBL 0

Seen by Jose on E3E3 in 15.2 mode (calculator and app on the same mode). Fixed on the box for
0.5.4 (`swift test`: 44 tests, 0 failures). Not built or deployed.
Evidence: `docs/bug053/` (copy of the Mac's `~/Library/Logs/VoyagerCalc-usb.log` and the dumps
rebuilt from it with `parse2.py`).

## Root cause
- 0.5.3 kept the calculator's own bytes outside 0x70..0x7DF, and the read-back compared only
  0x70..0x7DF. That boundary was wrong: the user memory runs up to 0x7EF.
- On the 15C and 16C the program grows down from the top of memory. FinancePac's lines 1-14 are
  the 14 bytes at 0x7E0..0x7EF (7 bytes per register, plus a pad byte).
- The calculator was empty before the write, so those bytes stayed 00, and 00 is `f LBL 0`.
  From line 15 (0x7DF and below) everything was written.
- The read-back didn't look at 0x7E0..0x7EF, so "success" was reported.
- Log, 18:42 write: only blocks 3, 4, 5, 6, 8, 9 were sent (the rest already matched). The
  read-back equals what was sent, but 0x7E0..0x7EF is all zeros where FinancePac has
  `c1 58 c6 f2 fd f1 fa 00 07 ce bd ce b2 08 c1 00`. Loaded in the core (E3E3 15.2), the
  read-back lists lines 1-14 as f LBL 0, then line 15 "÷" (`10`), exactly as Jose saw.
- E3E3 and C8C8 are not different. The RAM map is identical on C8C8 15.0 / 15.2 / 16C and
  E3E3 12C / 15.2 / 16C:
  - Nut CPU struct at SRAM 0x20000020 = image 0x08..0x6F;
  - its RAM at struct + 0x68 = image 0x70, 240 registers up to 0x7EF;
  - 0x7F0..0x7F7: a constant signature register (`af 54 39 fe d9 67 bc`, then a pad byte);
  - 0x7F8..0x7FF: live counters (0x7FA / 0x7FB change between reads).
- The C8C8 write at 18:34 also has zeros at 0x7E0..0x7EF in its read-back, so it most likely
  lost lines 1-14 the same way, unnoticed. The earlier C8C8 tests went well because the
  calculator already held FinancePac, so the kept bytes happened to be right.
- 16C images use 0x7E0 too: there is a pointer register there (`f9 07`, `ec 05`, ...).

## Fix (0.5.4)
- `CalculatorLink.memoryRange` = 0x70..<0x7F0: everything the firmware calls RAM.
  - Kept from the calculator: only the CPU struct (0x00..0x6F) and the trailer (0x7F0..0x7FF).
  - Block 63 is now sent.
  - The read-back compares the whole user area.
- `CalculatorMachine.memoryCompareRange` (trial-load check) = 0x100..<0x7F0, so the trial load
  checks the program top too.
- Tests: `testWriteKeepsTheProgramTop`.
  - FinancePac (15.2) and pi-1010 (16C) are written into an empty E3E3 15.2 dump read from
    Jose's calculator. The whole user area matches and the trailer is kept.
  - On E3E3 15.2, FinancePac lists 407 lines starting with f LBL 7, with no f LBL 0 in lines 1-14.
  - A dropped block 63 is now reported as a mismatch.
  - Updated: testWriteVerifies (blocks 3...63 sent), testWriteRetriesAfterADroppedBlock.
