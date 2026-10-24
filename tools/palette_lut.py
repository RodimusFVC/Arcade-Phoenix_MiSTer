#!/usr/bin/env python3
"""Phoenix-family colour LUT: MAME compute_res_net (resnet.cpp) + palette_t::normalize_range(0, 255), per 2-bit
R/G/B level -> 8-bit RGB. Network (phoenix_v.cpp): open-collector PROM bits, 100R pull-up to 5 V, 270R to ground,
bit 0 through R0 (270R Phoenix / Pleiads, 180R Survival), bit 1 through 1R.
normalize_range scales by the darkest / brightest pen of the PROM palette: ASSUMED to be level 0 / level 3 on every
channel (black and white present). Prints the SystemVerilog case table for rtl/boards/phoenix/phoenix_board.sv."""
import sys

VOL = 0.05


def res_net(t, r0):
    rtot, v = 0.0, 0.0
    for i, r in enumerate((r0, 1.0)):
        if not (t >> i) & 1:                       # low input conducts; high = open collector, no current
            rtot += 1 / r
            v += VOL / r
    rtot += 1 / 100.0
    v += 5.0 / 100.0                               # rBias 100R to vBias 5 V
    rtot += 1 / 270.0                              # rGnd
    v = v / rtot
    return int(v * 255 / 5.0 + 0.4)


def clamp(x):
    return max(0, min(255, x))


def lut(r0):
    lv = [res_net(t, r0) for t in range(4)]
    cols = {(r, g, b): (lv[r], lv[g], lv[b]) for r in range(4) for g in range(4) for b in range(4)}
    ys = [299 * r + 587 * g + 114 * b for r, g, b in cols.values()]
    ymin, ymax, tmin, tmax = min(ys), max(ys), 0, 255
    out = {}
    for k, (r, g, b) in cols.items():
        y = 299 * r + 587 * g + 114 * b
        u = int((b - int(y / 1000)) * 492 / 1000)
        v = int((r - int(y / 1000)) * 877 / 1000)
        target = tmin + int((y - ymin) * (tmax - tmin + 1) / (ymax - ymin))
        out[k] = (clamp(target + int(1140 * v / 1000)), clamp(target - int(395 * u / 1000) - int(581 * v / 1000)),
                  clamp(target + int(2032 * u / 1000)))
    return lv, out


for name, r0 in (("phoenix / pleiads", 270.0), ("survival", 180.0)):
    lv, out = lut(r0)
    print(f"// {name}: res_net levels {lv}")
    for (r, g, b), (R, G, B) in sorted(out.items()):
        print(f"6'b{r:02b}{g:02b}{b:02b}: rgb = 24'h{R:02X}{G:02X}{B:02X};")
