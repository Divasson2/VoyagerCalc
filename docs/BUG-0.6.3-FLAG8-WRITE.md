# 0.6.3 bug: Write to Calculator loses HP-15C flag 8; read-back shows the imaginary stack as "SOLVE"

Seen by Jose (notarized 0.6.3, sandboxed, 15C 15.2): flag 8 set in the app, Write to Calculator onto an
empty (memory-reset) calculator: flag 8 not set on the calculator. Read back into the app: 5 registers in
the pool bar labelled SOLVE, flag 8 off. Fixed in 0.6.4.

## Root cause (checked by running the CE firmware in the core: C8C8 15.0 and 15.2, docs/pool15c/flag8_{write,orphan,poweron}.py)
- Flag 8 is not kept in the Nut RAM. The firmware holds it as a status bit of its Nut CPU, in the CPU struct
  (SRAM 0x20000020): image byte **0x4C bit 3** (struct + 0x2C). Across all 80 pool dumps this bit equals
  flag 8 exactly. S0A nibble 8 (byte 0xC4 bit 0), which 0.6.0 took as flag 8, is only a copy.
- Experiments, empty target + the user area 0x70..0x7EF of a "SF 8" image (what 0.6.3 sends):
  - 0xC4 = 1, 0x4C bit 3 = 0 (0.6.3's write): flag 8 off (no C annunciator); at the next key, and at
    power-on, the firmware rewrites 0xC4 to 0. The map stays moved up by 5 (R2 at 0x45 on 15.2).
  - 0x4C bit 3 = 1 (with or without 0xC4): flag 8 on, C annunciator, 0xC4 = 1 after the next key, kept
    across OFF/ON.
- Since 0.5.2 the write keeps the calculator's whole CPU state (0x00..0x6F) because overwriting it with the
  emulator's "off" state stopped the calculator. So the empty calculator's status bit (0) won: flag 8 lost,
  while the RAM said "5 imaginary registers below R2".
- In that state the firmware counts the 5 registers as free (g MEM 19 174 on 15.2, 19 78 on 15.0) and SF 8
  reuses them. The app's decoder took complex from 0xC4 (now 0) and called every 5/23/28-register block below
  R2 the SOLVE/∫ workspace, hence "SOLVE".

## Fix (0.6.4)
- Serialisation: `CalculatorLink.writeMemory(_:flag8:)` / `merge(_:into:flag8:)`. For 15C images the app passes
  the emulator's flag 8 (0x4C bit 3); the merge sets or clears only that bit in the calculator's own CPU state
  (and the 0xC4 copy), nothing else of 0x00..0x6F. The read-back must show the bit, otherwise it is a mismatch
  and the write is retried / reported. Block 2 (0x40..0x5F) is now sent when the bit changes.
- Classification (core/src/inspect.c, docs/pool15c/pool15.py): complex = 0x4C bit 3. A block below R2 is the
  SOLVE/∫ workspace only if its size is 5/23/28 **and** SOLVE/∫ just ran (S14 nibble 13 = F and S03 ≠ 0, as in
  every after-SOLVE/∫ dump); otherwise it is a free gap, as the firmware counts it.
- Not verified on hardware: that the CE accepts a 'C' block that changes only that status bit while in USB
  mode (the 0.5.2 stop came from the power-state byte 0x30 in block 1). The fake calculator assumes it does.
  If Jose's next write disconnects at block 2, this is why.

## Tests
- core: test_pool15 80 dumps / 1385 checks, test_inspect 4188 checks: 0 failed (box).
- CalculatorLinkTests.testWriteCarriesFlag8, testFlag8RoundTripThroughTheFirmware (E3E3 15.2: SF 8 in the
  emulator, write into Jose's empty USB read, load into the firmware, power-cycle: complex, imaginary stack,
  no workspace; the 0.6.3 path gives flag 8 off and the 5 as free, not SOLVE).
- Pool15Tests.testParseRealImageWithComplexOn (Jose's real E3E3 image put in complex mode by the firmware
  rules), testLostFlag8IsNotASolveWorkspace.
