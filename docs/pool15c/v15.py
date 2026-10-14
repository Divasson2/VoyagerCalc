"""v15.py - tiny ctypes harness around the native Voyager core (docs/pool15c/lib/libvoyagercore.so,
built from core/src unchanged) for the HP-15C pool study. Whole-calculator engine.
Key tokens: physical key names of the 15C keyboard (matrix code = 10*row + col):
  row0  SQRT EX 10X YX 1/X CHS 7 8 9 /      (A..E = f SQRT .. f 1/X)
  row1  SST GTO SIN COS TAN EEX 4 5 6 *
  row2  RS GSB RDN XY BSP ENTER 1 2 3 -
  row3  ON f g STO RCL - 0 . S+ +
A run of digits is typed digit by digit.
"""
import ctypes, os, re
HERE = os.path.dirname(os.path.abspath(__file__))
FW = "/workspace/Firmware/hp15c-3rom-mute120-fsm5-rel80-opt5cycle-debounce-menu-stopwatch-48fix-keys-batt-trim4-show-C8C8.bin"
lib = ctypes.CDLL(os.path.join(HERE, "lib", "libvoyagercore.so"))
lib.vc_create.restype = ctypes.c_void_p
for n in ("vc_destroy", "vc_load_firmware", "vc_start", "vc_press_key", "vc_release_key", "vc_run_ms",
          "vc_save_memory", "vc_load_memory", "vc_model", "vc_model_variant", "vc_get_display", "vc_get_annunciators"):
    getattr(lib, n).argtypes = None
lib.vc_destroy.argtypes = [ctypes.c_void_p]
lib.vc_load_firmware.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
lib.vc_start.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
lib.vc_press_key.argtypes = lib.vc_release_key.argtypes = [ctypes.c_void_p, ctypes.c_int]
lib.vc_run_ms.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
lib.vc_save_memory.argtypes = lib.vc_load_memory.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.vc_model.argtypes = lib.vc_model_variant.argtypes = [ctypes.c_void_p]
lib.vc_get_display.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
lib.vc_get_annunciators.argtypes = [ctypes.c_void_p]; lib.vc_get_annunciators.restype = ctypes.c_uint32

NAMES = ["SQRT", "EX", "10X", "YX", "1/X", "CHS", "7", "8", "9", "/",
         "SST", "GTO", "SIN", "COS", "TAN", "EEX", "4", "5", "6", "*",
         "RS", "GSB", "RDN", "XY", "BSP", "ENTER", "1", "2", "3", "-",
         "ON", "f", "g", "STO", "RCL", "ENT2", "0", ".", "S+", "+"]
CODE = {n: i for i, n in enumerate(NAMES)}
CODE.update({"A": 0, "B": 1, "C": 2, "D": 3, "E": 4})     # A..E (after f, or in USER mode / after STO/RCL/DIM/GSB...)

class Calc:
    def __init__(self, variant=150, fw=FW):
        self.c = lib.vc_create()
        b = open(fw, "rb").read()
        assert lib.vc_load_firmware(self.c, b, len(b)) == 0
        assert lib.vc_start(self.c, 1, 0) == 0
        self.tap(30); lib.vc_run_ms(self.c, 1500); self.tap(24)     # ON, then <- clears 'Pr Error'
        if variant != self.variant(): self.switch(variant)
    def variant(self): return lib.vc_model_variant(self.c)
    def tap(self, k, down=80, up=250):
        lib.vc_press_key(self.c, k); lib.vc_run_ms(self.c, down); lib.vc_release_key(self.c, k); lib.vc_run_ms(self.c, up)
    def switch(self, variant):
        pick = {150: 0, 152: 3, 160: 5}[variant]
        self.tap(30, 120, 600); lib.vc_run_ms(self.c, 500)
        if self.display().strip(): self.tap(30, 120, 600); lib.vc_run_ms(self.c, 500)
        c = self.c
        lib.vc_press_key(c, 32); lib.vc_press_key(c, 25); lib.vc_run_ms(c, 100); lib.vc_press_key(c, 30); lib.vc_run_ms(c, 300)
        lib.vc_release_key(c, 30); lib.vc_run_ms(c, 200); lib.vc_release_key(c, 25); lib.vc_release_key(c, 32); lib.vc_run_ms(c, 800)
        self.tap(16, 120, 600); self.tap(pick, 120, 600); lib.vc_run_ms(c, 2000); self.tap(24, 120, 600)
        assert self.variant() == variant, "switch failed: %d" % self.variant()
    def keys(self, s):
        for t in s.split():
            if re.fullmatch(r"\d{2,}", t):
                for ch in t: self.tap(CODE[ch])
            elif t.startswith("wait:"): lib.vc_run_ms(self.c, int(t[5:]))
            else: self.tap(CODE[t])
        return self
    def display(self):
        b = ctypes.create_string_buffer(32); lib.vc_get_display(self.c, b, 32); return b.value.decode("utf-8", "replace")
    def ann(self): return lib.vc_get_annunciators(self.c)
    def mem(self):
        b = ctypes.create_string_buffer(2048); lib.vc_save_memory(self.c, b); return bytearray(b.raw)
    def load(self, m): lib.vc_load_memory(self.c, bytes(m))
    def gmem(self):
        """g MEM: the display while it is held (pressed g, then MEM held 300 ms)."""
        self.tap(32); lib.vc_press_key(self.c, 34); lib.vc_run_ms(self.c, 300)
        d = self.display(); lib.vc_release_key(self.c, 34); lib.vc_run_ms(self.c, 2500)
        return d.strip()
    def save(self, name):
        m = self.mem(); open(os.path.join(HERE, "dumps", name + ".bin"), "wb").write(m); return m

# ---------------------------------------------------------------- memory helpers
def reg(m, k):                    # Nut register k (dump 0x70 + 8k), 56 bits LE
    o = 0x70 + 8 * k; return int.from_bytes(m[o:o + 7], "little")
def hexreg(v): return "%014x" % v
def nut_off(k): return 0x70 + 8 * k
def diff(a, b, lo=0x70, hi=0x7F0):
    """registers (Nut index) that differ between dumps a and b, user area by default"""
    out = []
    for k in range((hi - 0x70) // 8):
        o = 0x70 + 8 * k
        if a[o:o + 7] != b[o:o + 7]: out.append(k)
    return out
def cpu_diff(a, b): return [i for i in range(0, 0x70) if a[i] != b[i]]
def bcd(v):
    """15C number register: nibble 13 = sign (0/9), 12..3 = mantissa, 2..0 = exponent (900+ = negative)"""
    s = "%014x" % v
    if not re.fullmatch(r"[09][0-9]{13}", s): return "(non-BCD)"
    if v == 0: return "0"
    sign = "-" if s[0] == "9" else ""
    mant = s[1:11]; ex = int(s[11:14])
    if ex >= 500: ex -= 1000
    return sign + ("%.10g" % float(mant[0] + "." + mant[1:] + "e" + str(ex)))
