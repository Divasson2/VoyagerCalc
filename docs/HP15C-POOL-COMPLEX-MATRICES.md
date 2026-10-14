# HP-15C CE memory pool: complex stack, matrices, SOLVE/∫ workspace (15.0 and 15.2)

Read-only analysis, 2026-10-11 (Europe/Madrid). Nothing was built for the Mac and nothing was flashed.
Everything was measured in the box emulator: the native core (`core/src`, unchanged, built as a private
`.so` in `docs/pool15c/lib/`), whole-calculator engine, firmware
`/workspace/Firmware/hp15c-3rom-mute120-fsm5-rel80-opt5cycle-debounce-menu-stopwatch-48fix-keys-batt-trim4-show-C8C8.bin`
(MD5 `73da4c38…`). The 15.0 and 15.2 modes are picked with the calculator's own switch (g-ENTER-ON, 4, then the model key).
FinancePac (15.2) was used as a real-world check.

**Credit:** Jose's map of the 32 system registers (spreadsheet image, 2026-10-11) gave the names and the
nibble columns. The measurements below confirm it and add a few details and corrections (see §2).

Scripts, dumps (63 × 2 KB) and the diagram are in `docs/pool15c/` (index in §8). `verify.py` re-checks the
whole map against the live calculator: **174 checks, 0 failed** (both modes).

Marks: **[V]** = verified in the emulator. **[I]** = inferred, not proven.

---------------------------------------------------------------------------------------------------

## 1. Addressing (how to find a register in the 2 KB image)

* Image: `0x00–0x6F` CPU struct; `0x70–0x16F` the **32 system registers** S00–S1F (8 bytes each: 7 data
  bytes, little-endian, then a pad byte); `0x170–0x7EF` RAM; `0x7F0–0x7FF` signature and counters.
* The firmware's pool pointers are Nut register addresses `p`. **Dump offset of register p = 0x70 + 8·(p − 0x10)** [V]
  (for example R2 at p = 0xA0 is at 0x4F0, and the top register 0xFF is at 0x7E8).
* A value is 14 BCD nibbles: nibble 13 = sign (0 / 9), nibbles 12..3 = mantissa, nibbles 2..0 = exponent
  (≥ 500 means negative: 1000 − e) [V]. In Jose's columns: P1 P2 = the pad byte, then S, 1…0, S E E.
* Outside the pool [V]: X = CPU register M (`0x20`), Y Z T = S00 S01 S02 (`0x70 0x78 0x80`), R0 = S10 (`0xF0`),
  R1 = S11 (`0xF8`), I = S12 (`0x100`), LASTx = S13 (`0x108`).

## 2. The system registers (Jose's map, checked)

| S | Offset | Jose's name | What the emulator shows |
|---|--------|-------------|-------------------------|
| 00–02 | 0x70–0x80 | y z t | **[V]** real Y, Z, T. |
| 03 | 0x88 | Pointer | 0 at rest; scratch during SOLVE/∫ [V] (meaning [I]). |
| 04 | 0x90 | Display | **[V]** changes with every display update and with FIX/SCI/ENG (digit mask). |
| 05, 06 | 0x98, 0xA0 | ? | `08` and `0c`, constant in every test here (modes, flags, matrices, program, SOLVE). Not decoded. |
| 07 | 0xA8 | Exponent | **Correction:** nibble 13 = angle mode (0 DEG, 4 RAD, 5 GRAD), nibble 12 = USER (F = on) [V]. Low nibbles `eae` constant; used as scratch by matrix multiply [V]. |
| 08 | 0xB0 | 0 | 0 in all tests. |
| 09, 0A | 0xB8, 0xC0 | Control L / R | Display/entry control and scratch [V]. **Addition: S0A nibble 8 bit 0 (byte 0xC4 bit 0) = a copy of flag 8, Complex mode** [V]; **0.6.4 correction: the firmware's own flag 8 is the CPU-struct status bit at image 0x4C bit 3; it rewrites 0xC4 from it at the next key / power-on (docs/BUG-0.6.3-FLAG8-WRITE.md)** (set by SF 8 and by f I / Re≷Im, cleared by CF 8). S0A nibbles 1 and 3 also follow RAD/GRAD [V]. |
| 0B–0F | 0xC8–0xE8 | 0 | 0 in all tests. |
| 10–13 | 0xF0–0x108 | R0 R1 I LASTx | **[V]** |
| 14 | 0x110 | ran | **[V]** nibbles 12..3 = the RAN# seed (STO RAN# 0.5 → `05000000000000`). Nibbles 2..0 = **current line number, 3 BCD digits** (line 255 → `255`, 400 → `400`, checked with FinancePac on 15.2). Nibble 13 'Run': F after GTO label and after a program run (SOLVE); the line digits are then stale until SST/BST recounts them [V]; that F means "line number needs recount" is [I]. |
| 15 | 0x118 | **map** | **[V]** byte 6 = Data (R2 start), 5 = mA, 4 = mB, 3 = mC, 2 = mD, 1 = mE (start of each matrix), byte 0 = **Pool** = first uncommitted register (00 = 0x100). Each start is also the end of the previous block. |
| 16 | 0x120 | Return1 / last line | **[V]** low byte = lowest program register, nibble 2 = byte within it (1–7): the program end. 0 = no program. |
| 17 | 0x128 | Return2 / curr. byte | **[V]** low 3 nibbles = current program pointer (same format). With pending GSB returns the upper nibbles fill up (`…04ef1ee5fe` with two returns): **return stack [I]**, encoding not decoded. |
| 18 | 0x130 | 0 | 0. |
| 19 | 0x138 | **dimension** | **[V]** byte 6 = A rows, 5 = A cols, 4 = B rows, 3 = B cols, 2 = C rows, 1 = C cols, byte 0 unused. **Binary bytes, not BCD** (12 → `0c`, 99 → `63`). |
| 1A | 0x140 | **flags** | **[V]** byte 6 = D rows, 5 = D cols, 4 = E rows, 3 = E cols; nibble 5 ('R', byte 0x142 high nibble) = RESULT matrix, A..E as 0xA..0xE (default A); nibble 4 ('F') bit 1 = flag 9; byte 1 (nibbles 3,2) = flags 0–7 (bit n = flag n). **Correction:** flag 8 is not here, it is in S0A (above). Byte 0: 0x80 right after a 15.2 cold start, cleared by the first keys [V]; meaning unknown. |
| 1B–1F | 0x148–0x168 | 0 | 0 in all tests. |

No mode marker in the image [V]: the two cold-start images differ only in S1A byte 0 and CPU byte 0x4D. 0x4D is also 0
or 8 in later 15.0 and 15.2 dumps, so it is transient CPU state. Take 15.0 or 15.2 from the core (`vc_model_variant`).
From a file alone, map.b6 < 0xA0 proves 15.2; otherwise it is ambiguous.

## 3. The pool: layout and formulas

From the bottom (low address) to the top [V], both modes:

```
pool_base ─┬─ SOLVE/∫ workspace  (0, 5 or 23 regs; only right after SOLVE/∫ ran, see §3.4)
           ├─ imaginary stack    (5 regs if flag 8: LASTx, T, Z, Y, X)
 map.b6 ───┼─ R2 .. R(DIM(i))    (storage; R0 and R1 are outside the pool, in S10/S11)
 map.b5 ───┼─ matrix A  (rows·cols registers, row-major)
 map.b4 ───┼─ matrix B
 map.b3 ───┼─ matrix C
 map.b2 ───┼─ matrix D
 map.b1 ───┼─ matrix E
 map.b0 ───┼─ free (uncommitted)
 S16 low ──┼─ program (7 bytes per register, line 1 = byte 6 of 0xFF, growing down)
      0xFF ┘ (dump 0x7E8; 0x100 = the end, dump 0x7F0)
```

| | 15.0 | 15.2 |
|---|---|---|
| pool_base | Nut 0xA0 (dump 0x4F0) | Nut 0x40 (dump 0x1F0) |
| Pool registers (0x100 − base) | 96 | 192 |
| Cold start `g MEM` | `19 78 00-0` | `19 174 00-0` |
| Largest DIM (i) | 97 (memory-limited: map.b0 wraps to 00) | 99 (a cap: 94 still free) |
| Largest matrix | 78 elements (n×1); 8×8 square | each side ≤ 99 (100×1 → Error 10); 13×13 square |
| RAM never used by the 15C | dump 0x170–0x4EF | dump 0x170–0x1EF |

Formulas (every value is a Nut address; `pool` = map.b0, with 00 meaning 0x100) [V, checked by verify.py]:

* `complex = byte[0x4C] & 8` (CPU status bit; 0xC4 bit 0 is its copy, 0.6.4)
* `storage = map.b5 − map.b6`  (R2..R(DIM)); **DIM (i) = storage + 1**; storage registers = DIM (i) + 1 (R0..R(DIM)).
* Rn (n ≥ 2) is at `map.b6 + n − 2`.
* Matrix k ∈ {A..E}: start = map.b(5−k), rows/cols from S19/S1A, element (i, j) at `start + (i−1)·cols + (j−1)` (row-major).
  Also `start(k+1) − start(k) = rows·cols`.
* Imaginary stack (if complex): `map.b6 − 5 … map.b6 − 1` = **LASTx, T, Z, Y, X** (X is the top one, next to R2).
* Workspace = `map.b6 − pool_base − 5·complex`, only if it is 5/23/28 **and** S14 nibble 13 = F and S03 ≠ 0 (SOLVE/∫ just ran, 0.6.4); otherwise those registers are a free gap (g MEM counts them as free).
* Program: if S16 nibble 2 ≠ 0: `prog_regs = 0x100 − (S16 & 0xFF)`, `prog_bytes = (0xFF − (S16 & 0xFF))·7 + nibble 2(S16)`; otherwise 0.
* **free (g MEM 2nd field) = (0x100 − pool_base) − storage − Σ rows·cols − 5·complex − prog_regs.**
  **g MEM = `DIM(i)  free  prog_regs-(7·prog_regs − prog_bytes)`** (FinancePac: `96 33 64-5` ✓).
  Use this formula, not `program_low − map.b0`: it is also right while a workspace is present and right after a 15.2 cold start.

### 3.1 Complex mode (flag 8)  [V]
* SF 8, f I or Re≷Im takes **5 registers from the pool**: the whole window (R2.., matrices) moves up by 5
  (map bytes all +5), g MEM free −5 (78 → 73; 174 → 169). Values move with it.
* f I/Re≷Im set flag 8 themselves (C annunciator on).
* CF 8 gives the 5 back: everything moves down by 5 and the imaginary parts are lost.
* Order checked with five different imaginary parts: base+0 LASTx, +1 T, +2 Z, +3 Y, +4 X.
* The real X stays in the CPU register M (0x20). Only its imaginary part is in the pool.

### 3.2 Matrices  [V]
* All 0×0 at cold start: map bytes 1..5 equal, S19 = 0, S1A dimension bytes = 0, RESULT = A.
* **DIM** inserts/removes registers at the end of that matrix. Matrices above it, and the free boundary, move up/down. Elements keep their linear (row-major) order: when A goes from 2×3 to 3×3, the 6 old values stay first and 3 zeros are added. When A goes from 3×3 to 2×2, the first 4 values are kept.
* The program does not move. Its registers stay at the top, byte for byte. A DIM that does not fit gives Error 10.
* **MATRIX 0** sets every dimension to 0, zeroes the elements, collapses map bytes 1..5 onto map.b6 and keeps RESULT. **MATRIX 1** sets R0 = R1 = 1.
* USER mode `STO A` stores at (R0, R1) and steps R1 then R0: storage order = row-major.
* **Descriptor** (RCL MATRIX A, or a matrix result in X): `1a000000000000`, nibble 13 = 1 (not a valid BCD sign), nibble 12 = letter 0xA..0xE, all else 0. The same raw value is seen in X, Y and LASTx. The display shows `A  2  3` with the live dimensions, so the dimensions are not inside the descriptor.
* `RESULT C` writes 0xC to S1A nibble 5. `RCL MATRIX B, RCL MATRIX A, ×` wrote B·A into C, and C was re-dimensioned to 1×3 automatically.

### 3.3 Interaction  [V]
SF 8 with matrices moves everything up by 5 (complex sits below R2). DIM (i) moves the matrices too (they sit above storage).
The program block never moves.

### 3.4 SOLVE / ∫ workspace  [V]
* SOLVE takes **5** registers, ∫ takes **23**. With flag 8 set, SOLVE took 5 + 5.
* They go at the very bottom, below the imaginary stack, and push the whole window up.
* After the run they **stay in place until the next key** (g MEM itself already packs them away). g MEM never counts them.
* An inspector snapshot taken right after SOLVE/∫ (or during the run) shows them, so they must be labelled.
* Not measured: SOLVE nested inside ∫ (the manual says 28) [I].

### 3.5 15.2 "double memory"  [V]
* Same system registers, same map/dimension format, same rules: only `pool_base` (0x40 instead of 0xA0) and the limits differ.
* **Quirk:** right after a 15.2 cold start the map still says `b2…b2 a0`, as on 15.0. R2.. are at 0xA0 and 0x40–0x9F is free *below* them.
* The first reallocation (DIM, SF 8, f I, program entry) packs everything down to 0x40 (R2 values move from 0xA0 to 0x45 etc.).
* g MEM is right in both states with the formula above. A pool bar must therefore draw "free" wherever the gap is, not assume it is only below the program.

## 4. A bug found in the current inspector (core/src/inspect.c)

* `dim15()` computes the storage size from map byte 0 (Pool) instead of byte 5 (mA). With any matrix dimensioned the inspector lists the matrix elements as extra registers:
  * `v150_24_fillA`: `regs 28`, and "R20…R25" are A's elements 11…23.
  * Correct: 20.
* Fix: `last = w[5]` (one line). R2 = `w[6]` stays correct, also in complex mode.
* `vc_inspect()` takes flag 8 from the C annunciator, so a loaded or saved image shows no flag 8 (`--load v150_34…` → flags 0x00). Use byte 0xC4 bit 0.

## 5. Proposed display

**Core API (C, read-only, same style as `vc_inspect_*`):**
```
typedef struct { int base, top, data, start[5], pool, rows[5], cols[5], result, complex, scratch,
                 storage, dim_i, matrices, prog_low, prog_regs, prog_bytes, free; } vc_pool15;
int vc_inspect_pool15(vc_calc *c, vc_pool15 *out);
int vc_inspect_imag(vc_calc *c, int reg /*VC_REG_X..LASTX*/, vc_value *out);   /* flag 8 only */
int vc_inspect_matrix(vc_calc *c, int m /*0..4*/, int row, int col, vc_value *out);
```
`docs/pool15c/pool15.py` is the reference: `decode()` gives exactly these fields. Port it 1:1 and test it against the dumps in `docs/pool15c/dumps/`.

**Inspector:**
1. Header: a **Complex** tag when flag 8 is set (like the flag tags).
2. Stack: each row (X, Y, Z, T, LAST X) gets an imaginary column, `3 + 4i` style, or "Re / Im" columns. It is shown only when complex.
3. **Matrices** section (15C): five rows A–E: `A  2×3  (6 regs, Nut B2–B7)`.
   * A 0×0 matrix is greyed.
   * The RESULT matrix gets a "RESULT" badge.
   * A row expands to a rows×cols grid of values (copy as TSV). Read from S15/S19/S1A only.
   * A matrix descriptor in a stack register is shown as "matrix A (2×3)" instead of the raw value.
4. **Memory pool bar** (one horizontal bar, proportional), segments in pool order:
   * workspace (only right after SOLVE/∫, labelled "SOLVE/∫ workspace, freed at next key"), complex 5, R2..R(dim), A..E, free, program;
   * the free gap below R2 right after a 15.2 cold start.
   * Caption = computed g MEM text (`19 67 00-0`) and the pool size (96 or 192, + R0/R1). Hover gives addresses.
5. Storage list: R2..R(dim) only (after the fix).

**PDF (program documentation):**
* **Memory configuration** block on page 1, from the memory file:
  * DIM (i) and storage registers;
  * matrices A–E with their dimensions now, and RESULT;
  * complex on/off (5 registers);
  * flags set;
  * pool use as the g MEM line plus a small bar;
  * "needs at least" = storage + matrices + complex + program + workspace, if the program uses SOLVE (5) or ∫ (23).
* **Matrices and complex** table, from the listing like Labels/Registers. Exact mnemonics the core prints [V, `prog_ops.py`]:
  * `DIM A`…`DIM E`, `DIM (i)`, `MATRIX 0..9`, `RESULT A..E`;
  * `STO/RCL MATRIX A..E`, `STO/RCL A..E` (USER element), `STO/RCL g A..E`, `RCL DIM A..E`, `STO/RCL RESULT`;
  * `I`, `Re≷Im`, `SF/CF/F? 8`;
  * plus `SOLVE`/`∫ʸₓ` (workspace).

  Columns: Item (Matrix A / Complex / DIM (i)) · Operations · Steps · Notes. Notes are things like "dimensioned by the program (step 006, from the stack)", "MATRIX 1 sets R0=R1=1", "flag 8 = complex mode".

  ProgramAnalysis already records DIM/RESULT/STO/RCL (g, MATRIX) on matrices. Missing:
  * `MATRIX n`, `I`, `Re≷Im`, `DIM (i)` (dropped today);
  * a "complex" meaning for flag 8;
  * a correction: `RCL DIM (i)` is wrongly counted as a use of register (i).
  * Dimensions set by a program come from the stack, so the PDF can say "DIM A at step 6", not the size [I: static analysis cannot know it].

**Effort (estimate):** about 4 days in total.

| Task | Estimate |
|---|---|
| Core: `vc_inspect_pool15` + imaginary + matrix element + the `dim15`/flag-8 fixes + C tests on the saved dumps | 1 day |
| Swift snapshot + Inspector UI (complex column, Matrices section with grid, pool bar) | 1.5 days |
| ProgramAnalysis additions + PDF block/table | 1 day |
| On-Mac check (light/dark, iOS layout) | 0.5 day |

## 6. Open points
* S05/S06, S1A byte 0 (15.2 cold-start 0x80) and the S17 return-stack encoding are not decoded.
* SOLVE nested in ∫ was not measured.
* The 15.2 cold-start window at 0xA0 might be an artifact of the C8C8 mode switch rather than the 15.2 ROM itself [I]. E3E3's 15.2 mode was not tested.

## 7. Plain-language summary
* Pool layout, from the bottom: storage registers (R2 and up), then matrices A–E (each one block, row by row), then free space. The program sits at the top and grows down.
* Complex mode puts 5 imaginary registers (LASTx, T, Z, Y, X) just below R2 and moves everything else up by 5.
* SOLVE and ∫ briefly borrow 5 or 23 registers at the very bottom.
* One system register, 0x118, holds the start of each block. 0x138 and 0x140 hold the matrix sizes (one byte each), the RESULT letter and flags 0–7 and 9. Flag 8 is a single bit at 0xC4.
* 15.2 is the same with a pool twice as big (192 registers from Nut 0x40 instead of 96 from 0xA0).

## 8. Files in docs/pool15c/
* `v15.py`: ctypes harness (boot, mode switch, key tokens, held g MEM, dumps).
* `pool15.py`: the reference decoder (`python3 pool15.py dump.bin` prints the full map).
* `verify.py`: decoder vs live calculator.
* `diagram.py` → `pool-map.png`.
* Experiments, each saving its dumps in `dumps/` (prefix v150_/v152_):
  * `find_regs.py`, `dim_i.py`, `dim_max.py`: storage and DIM (i);
  * `complex.py`, `cx_order.py`: flag 8;
  * `matrices.py [150|152]`, `mx_dims.py`, `mx_max.py`: matrices;
  * `prog_ops.py`: listing mnemonics;
  * `scratch*.py`: SOLVE/∫;
  * `fill.py`: pool bounds, FinancePac;
  * `sysregs.py`: modes, RAN#, line counter.
* `lib/libvoyagercore.so`: built from core/src as is.
