"""pool15.py - reference decoder of the HP-15C CE memory pool from a 2048-byte Continuous Memory image
(15.0 and 15.2). Every rule here was found with the scripts in this folder and is checked by verify.py.

Addresses: the firmware's pool pointers are Nut register addresses p (0x30..0xFF);
dump offset of register p = 0x70 + 8 * (p - 0x10). System registers S00..S1F = dump 0x70..0x16F.
"""
import sys
POOL_BASE = {150: 0xA0, 152: 0x40}          # first pool register (Nut address); top = 0xFF
def off(p): return 0x70 + 8 * (p - 0x10)
def sreg(d, k): return int.from_bytes(d[0x70 + 8 * k:0x70 + 8 * k + 7], "little")
def nib(v, i): return (v >> (4 * i)) & 15

def variant_of(d):
    """The image does not say which ROM wrote it; take the mode from the core (vc_model_variant) when you can.
    From the image alone: R2 below Nut 0xA0 only happens in 15.2; otherwise 15.0 is assumed (ambiguous)."""
    if d[0x118 + 6] < 0xA0: return 152
    return 150

def decode(d, variant=None):
    v = variant or variant_of(d)
    base = POOL_BASE[v]
    mp = d[0x118:0x11F]                          # S15 'map': b0 pool(free) b1 E b2 D b3 C b4 B b5 A b6 data(R2)
    data, starts, pool = mp[6], [mp[5], mp[4], mp[3], mp[2], mp[1]], mp[0] or 0x100
    ends = starts[1:] + [pool]
    dims = [(d[0x138 + 6], d[0x138 + 5]), (d[0x138 + 4], d[0x138 + 3]), (d[0x138 + 2], d[0x138 + 1]),
            (d[0x140 + 6], d[0x140 + 5]), (d[0x140 + 4], d[0x140 + 3])]
    flagsreg = sreg(d, 0x1A)
    flags = [bool(d[0x141] >> f & 1) for f in range(8)]
    complex_ = bool(d[0x4C] & 8)                 # flag 8 = Nut status bit in the CE CPU struct (dump 0x4C bit 3); 0xC4 bit 0 is a copy (0.6.4)
    flags += [complex_, bool(d[0x142] & 2)]      # flag 9 = S1A nibble 4 bit 1 (dump 0x142 bit 1)
    result = "ABCDE"[nib(flagsreg, 5) - 0xA] if 0xA <= nib(flagsreg, 5) <= 0xE else "?"
    p16 = sreg(d, 0x16)
    if nib(p16, 2):
        prog_low = p16 & 0xFF; prog_regs = 0x100 - prog_low
        prog_bytes = (0xFF - prog_low) * 7 + nib(p16, 2)
    else: prog_low, prog_regs, prog_bytes = 0x100, 0, 0
    cx = 5 if complex_ else 0
    below = data - base - cx                     # SOLVE (5) / integrate (23) workspace, at the very bottom,
    ran = (d[0x116] >> 4) == 0xF and any(d[0x88:0x8F])   # ... only right after SOLVE / integrate ran
    scratch = below if below in (5, 23, 28) and ran else 0
    total = 0x100 - base
    storage = pool if False else starts[0] - data # R2..R(dim)
    dim_i = storage + 1
    mats = sum(r * c for r, c in dims)
    free = total - storage - mats - cx - prog_regs   # = g MEM 2nd field (scratch not counted, it is released at the next key)
    return dict(variant=v, base=base, data=data, starts=starts, ends=ends, pool=pool, dims=dims, result=result,
                flags=flags, complex=complex_, imag_at=(data - 5) if complex_ else None, scratch=max(0, scratch),
                storage=storage, dim_i=dim_i, matrices=mats, prog_low=prog_low, prog_regs=prog_regs, prog_bytes=prog_bytes,
                free=free, gmem="%d %d %02d-%d" % (dim_i, free, prog_regs, prog_regs * 7 - prog_bytes))

def bcd(v):
    s = "%014x" % v
    if v == 0: return "0"
    if not all(ch in "0123456789" for ch in s) or s[0] not in "09": return "<%s>" % s
    mant = s[1:11]; ex = int(s[11:14]); ex = ex - 1000 if ex >= 500 else ex
    return ("-" if s[0] == "9" else "") + "%.10g" % float(mant[0] + "." + mant[1:] + "e" + str(ex))
def rd(d, p): return int.from_bytes(d[off(p):off(p) + 7], "little")

def describe(d, variant=None):
    r = decode(d, variant); out = []
    out.append("HP-15C %s  pool Nut %02X..FF (%d registers) + R0, R1" % ("15.2" if r["variant"] == 152 else "15.0", r["base"], 0x100 - r["base"]))
    out.append("g MEM (computed): %s" % r["gmem"])
    out.append("flags set: %s   complex: %s   RESULT: %s" % ([i for i, f in enumerate(r["flags"]) if f], r["complex"], r["result"]))
    if r["scratch"]: out.append("SOLVE/integrate workspace: Nut %02X..%02X (%d regs, freed at the next key)" % (r["base"], r["base"] + r["scratch"] - 1, r["scratch"]))
    if r["complex"]:
        p = r["imag_at"]; out.append("imaginary stack Nut %02X..%02X: LASTx %s  T %s  Z %s  Y %s  X %s" % ((p, p + 4) + tuple(bcd(rd(d, p + i)) for i in range(5))))
    out.append("R2..R%d: Nut %02X..%02X" % (r["dim_i"], r["data"], r["starts"][0] - 1) if r["storage"] else "R2..: none (DIM (i) = 1)")
    for i, L in enumerate("ABCDE"):
        rr, cc = r["dims"][i]
        if rr * cc:
            vals = [bcd(rd(d, r["starts"][i] + k)) for k in range(rr * cc)]
            rows = [" ".join(vals[j * cc:(j + 1) * cc]) for j in range(rr)]
            out.append("matrix %s %dx%d at Nut %02X..%02X: [%s]" % (L, rr, cc, r["starts"][i], r["ends"][i] - 1, " | ".join(rows)))
        else: out.append("matrix %s 0x0" % L)
    fr = "free: %d" % r["free"] + ("" if r["scratch"] else " (Nut %02X..%02X)" % (r["pool"], r["prog_low"] - 1))
    pr = "program: %d regs (Nut %02X..FF), %d bytes" % (r["prog_regs"], r["prog_low"], r["prog_bytes"]) if r["prog_regs"] else "program: empty"
    out.append(fr + "   " + pr)
    return "\n".join(out)

if __name__ == "__main__":
    for f in sys.argv[1:]:
        print("==", f); print(describe(bytearray(open(f, "rb").read())))
