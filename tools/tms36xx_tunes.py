#!/usr/bin/env python3
"""Fill the tune ROM of rtl/sound/tms36xx.sv from MAME's devices/sound/tms36xx.cpp tune tables.
ROM layout: tune 1 at 0, tune 2 at 576, tune 3 at 1152 (96 steps x 6 harmonics), tune 4 (13 notes x 6) at 1728.
Entries are MAME's macro values ((int)((FSCALE << n) * ratio), FSCALE 1024), evaluated with C truncation.
    tms36xx_tunes.py <tms36xx.cpp> <tms36xx.sv>"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
c = open(src).read()
FSCALE = int(re.search(r'#define FSCALE\s+(\d+)', c).group(1))
macros = {}
for m in re.finditer(r'#define (\w+)\(n\)\s+\(int\)\(\(FSCALE<<(\(n-1\)|n)\)(?:\*([\d.]+))?\)', c):
    name, sh, ratio = m.group(1), m.group(2), float(m.group(3) or 1.0)
    macros[name] = (sh == "(n-1)", ratio)
assert set(macros) == {"C", "Cx", "D", "Dx", "E", "F", "Fx", "G", "Gx", "A", "Ax", "B"}, sorted(macros)


def value(tok):
    tok = tok.strip()
    if tok == "0":
        return 0
    m = re.fullmatch(r'(\w+)\((\d+)\)', tok)
    minus1, ratio = macros[m.group(1)]
    n = int(m.group(2))
    return int((FSCALE << (n - 1 if minus1 else n)) * ratio)


rom = []
for t, length in ((1, 96), (2, 96), (3, 96), (4, 13)):
    body = re.search(r'static const int tune%d\[(\d+)\*6\] = \{(.*?)\};' % t, c, re.S)
    assert int(body.group(1)) == length
    text = re.sub(r'/\*.*?\*/', '', body.group(2), flags=re.S)
    vals = [value(v) for v in text.split(",") if v.strip()]
    assert len(vals) <= length * 6, (t, len(vals))
    vals += [0] * (length * 6 - len(vals))         # C zero-fills a short initialiser
    assert max(vals) < 1 << 15
    rom += vals
assert len(rom) <= 2048
lines = [f"        tune_rom[{a}] = 15'd{v};\n" for a, v in enumerate(rom + [0] * (2048 - len(rom)))]   # every entry
s = open(dst).read()
a, b = s.index("// TUNES-BEGIN"), s.index("// TUNES-END")
a = s.index("\n", a) + 1
open(dst, "w").write(s[:a] + "".join(lines) + s[b:])
print(f"{len(rom)} entries, {sum(1 for v in rom if v)} non-zero, {len(lines)} lines")
