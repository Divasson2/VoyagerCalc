# 0.5.2 bugs: Error 10 after Read from Calculator, and Write to Calculator failing

Status: fixes prepared on the box (`swift test`: 43 tests, 0 failures). Not built or deployed
to the Mac (Jose asked for no builds until he says so).
Evidence: `docs/bug052/` (copy of `~/Library/Logs/VoyagerCalc-usb.log`, the images rebuilt
from it with `parse_log.py`, FinancePac, and the repro scripts `repro*.py` and `mem.py`).
Note: the log is at `~/Library/Logs/` and says "sandboxed: false", so the sessions in it came
from `VoyagerCalc-0.5.2-nosandbox.app`. The sandboxed app's container log folder is empty.
The backups in `~/Documents/VoyagerCalc Backups/` could not be read from here (macOS
privacy protection on ~/Documents). Each backup is the same as the dump just before it in the log.

## 1. Error 10 at g MEM: two different 15C memory layouts

- The 15.0 and 15.2 ROMs are both "HP-15C", but 15.2 has double memory (about 194 registers
  against about 98). Each ROM works out the free registers from its own memory size.
- FinancePac is a 15.2 image. g MEM (read while RCL is held) gives:
  - 15.2 mode, on C8C8 and on E3E3: `96 33 64-5` (96 data registers, 33 free, 64 used by the program).
  - 15.0 mode, on C8C8: `Error 10` ("insufficient memory").
  - DIM (i) can't fix it: the program alone needs more than 15.0 has.
- The USB read is correct.
  - 33 reports: 32 × 63 bytes + 32 = 2048. No shifted bytes, no extra report header byte,
    no missing or doubled chunks.
  - The calculator's dump of FinancePac (`read7`) differs from the file only in the CPU-state
    header (0x00..0x6F) and in byte 0x7FB, which changes from one read to the next.
- Neither the load path nor the trial load changes the memory. 0 bytes differ in 0x100..0x7DF
  with both "load while on" (putMemory) and "load while off". The trial runs on a scratch machine.
- So the cause is the mismatch Jose found: calculator and app on different 15C modes. With both
  on 15.2, g MEM is fine.

### Telling 15.0 and 15.2 memory apart (implemented)
- The image stores no "mode" byte. The free count is computed by the ROM, and the CPU-state
  pointers in the header can be stale, so neither is a reliable marker.
- The test that matters comes from the firmware itself. `CalculatorMachine.checkMemory` now
  presses g MEM in the trial load on 15C models. Error 10 gives a new verdict,
  `.needsMoreMemory`.
- `identifyMemory` then returns only the variants it really fits. FinancePac on C8C8 gives `[152]`.
- AppModel shows a new choice, `.switchThenLoad`: "The memory from X is for the HP-15C (15.2)
  … (g MEM gives Error 10, and DIM (i) cannot fix it)". Its buttons are
  **Switch to 15C (15.2) and Load** / Save Backup First… / Cancel. The load runs after the
  switch succeeds.
- A small image fits both modes and loads with no warning. Tested with a dump read from Jose's
  calculator in 15.0 mode: `19 78 00-0` in 15.0, `19174 00-0` in 15.2.
- Tests: `testFinancePacNeeds152`, and `testFinancePacFits15C` now checks 15.2 only.
- Still to do: the Write confirmation can't tell the calculator's mode from its dump. It should
  warn when the emulator's image needs 15.2: "set the calculator to 15.2 (g-ENTER-ON, 4) first".

## 2. Write to Calculator: kIOReturnBadArgument (0xE00002C2)

All four logged writes fail the same way, including Jose's 18:20 retry with both on 15.2:
```
SetReport(Output, id 0, 64) success   22 43 00 …     block 0   (+16 ms)
SetReport(Output, id 0, 64) success   22 43 01 …     block 1   (+131 ms: the calculator is busy)
SetReport(Output, id 0, 64) success   22 43 02 …     block 2   (+2 ms)
SetReport(Output, id 0, 64) 0xE00002C2 22 43 03 …    block 3
IOHIDDeviceClose            0xE00002C2               (the device handle itself is now invalid)
```
Then the calculator's display is off, and at 18:08:26 "0 devices": it has dropped off USB.

**Not a framing error.** Our reports are the same as VoyagerInterface's restore:
- 64 bytes passed to IOHIDDeviceSetReport, output report, report ID 0;
- the device reports MaxOutputReportSize = 64;
- each report is `[0x22, 'C', block, 32 bytes]`, 35 of 64 bytes;
- 64 blocks, with a 1 ms pause between them.

Blocks 0–2, framed identically, succeed. Close failing too shows the device had gone away:
"bad argument" refers to a device handle that no longer exists.

**Root cause.**
- The firmware copies each 'C' block into the running calculator's SRAM at once
  (0x20000018 + 32·block). A later read shows our block 1 bytes in the calculator.
- Image bytes 0x00..0x6F are the live CPU state of the firmware's Nut emulator. The CPU struct
  sits at SRAM 0x20000020 and holds the registers, the return stack and the power-state byte at 0x30.
- Our write sends the emulator's image saved while off: byte 0x30 = `04`. A calculator that is
  on and in USB mode has `0C`, and every image read over USB has `0C` too.
- Block 1 overwrites the calculator's live CPU state with the emulator's "off" state. The
  calculator stops in mid-transfer (the 131 ms stall), its display goes off and it leaves USB.
  Block 3 then hits a dead handle.
- VoyagerInterface gets away with it because it writes files that were read over USB, whose
  CPU state is "on, in USB mode".
- This does not depend on the 15C mode, which fits the 18:20 retry.

**Fix (`CalculatorLink.writeMemory`).**
- Read the calculator first.
- Build the image to send from three parts: the calculator's own bytes 0x00..0x6F (CPU state),
  the emulator's 0x70..0x7DF (Nut RAM: registers, program, flags), and the calculator's
  0x7E0..0x7FF (trailer).
- Send only the 32-byte blocks that change. Blocks 0–2 and 63 are never sent.
- Verify 0x70..0x7DF only. A whole-image compare would always fail, because byte 0x7FB changes
  between reads and the CPU state isn't ours.
- A retry resends only the blocks that still differ.

Tests (fake calculator that, like the real one, stops when 0x00..0x6F changes):
- `testWriteKeepsTheCalculatorsCPUState`: the 0.5.2 sequence kills the fake; the new one doesn't.
- `testWriteVerifies`: only blocks 3…62 are sent.
- Also updated: `testWriteRetriesAfterADroppedBlock`, `testWriteMismatchIsReported`.

Not provable from the box: the core doesn't emulate the CE's USB loop. Jose's next write will
confirm it. If it still fails, the log will show which block now fails.

## Side findings
- The calculator doesn't support GetReport for input reports: it returns 0xE0005000 every time.
  Replies come only on the interrupt pipe, so the run-loop input callback added in 0.5.2 is what
  makes Read work. Keep it.
- Ready to build when Jose says so: version 0.5.2 (or bump to 0.5.3), same Mac rules.
