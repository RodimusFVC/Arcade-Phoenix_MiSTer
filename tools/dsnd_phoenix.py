#!/usr/bin/env python3
"""Phoenix sound board (Centuri CPU board 364-62-0900, schematic sheet 17) as a discrete-engine program.

Sources: LATCH1 = sound control A (6000-63FF write), LATCH2 = sound control B (6800-6BFF write).
Output = MAME's mix without the melody chip: 0.6 x discrete (effects 1 / 2, NODE_90) + 0.4 x custom noise.
The MM6221AA melody (control B bits 6-7) is rtl/sound/tms36xx.sv, added in the board at 0.5.

Effect 1 (control B: D0-3 counter preload, D4 FREQ, D5 FILT): C7 two-state RC (MAME DST_RCDISC4 type 1, R22 470R as
  on real boards) -> LM324 <52> -> CV of 555 <48> (R25 47k, R26 47k, C8 1n) -> LS163 <13> preload / LS74 <21> /2
  (MAME DISCRETE_NOTE) -> x 3.4 V (FILT: x 100k / 110k, then R19 // R20 x C5 low pass).
Effect 2 (control A: D0-3 preload, D4-5 FREQ): 555 <44> (R40 47k, R41 100k, C18 + C16 / C17 by D4 / D5) and 555 <51>
  (510k, 510k, C20 1u as on real boards) through R42 / R45 / R46 (5.1k as on real boards) / C22 to the CV of 555 <50>
  (R47 20k, R48 20k, C23 1n) -> LS163 <14> / LS74 <21> -> x 3.4 V (D5: x 1.7 V).
Mix: R19 + R21 / C6 and R38 + R47 / C31 into VR1 10k with the noise inputs' R67 / R68 20k, C32 to the LM380
  (MAME phoenix_mixer, cAmp 100k x C32, gain 40000).
Noise (control A D6 / D7): MAME phoenix_sound_device (its own guesswork, "very ALPHA"): C24 / C25 envelopes, NE555
  noise clock 588 + 6325 x level Hz, 18-bit 4006 polynomial (XNOR of bits 16 / 17), path 2 sampled at 400 Hz.
  The schematic's noise-rate summer (LM324 <46> pins 5-7) and band-pass (LM324 <52> pins 2-4) are not readable in
  the scan; their behaviour stays MAME's.

555 VCOs: phase accumulators; the frequency is a degree-5 fit of 1 / ((R1 + R2) C ln((5 - CV / 2) / (5 - CV)) +
R2 C ln 2) over the CV range (max error 0.11 cent). Falling edges carry MAME's x_time (the sample fraction after the
edge) into the counters' energy output."""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dsnd import Board, FS, ONE, LATCH1, LATCH2, q, par   # noqa: E402

TTL1 = 3.4                                            # DEFAULT_TTL_V_LOGIC_1
VCC = 5.0


def k_exp(tau):
    """MAME RC_CHARGE_EXP at the engine rate"""
    return 1.0 - math.exp(-1.0 / (FS * tau))


def vco_fit(r1, r2, c, lo, hi, deg=5):
    """polynomial in CV (volts) -> 555 cycles per engine sample"""
    cv = np.linspace(lo, hi, 4000)
    y = (r1 + r2) * c * np.log((VCC - cv / 2) / (VCC - cv)) + r2 * c * math.log(2.0)
    p = np.polyfit(cv, 1.0 / (y * FS), deg)
    err = np.max(np.abs(np.polyval(p, cv) * y * FS - 1.0))
    assert err < 2e-4, err
    return list(p)                                    # highest power first


class Phoenix(Board):
    # ---- helpers ----------------------------------------------------------------------------------------------
    def sel(self, reg, src, bit, v0, v1):
        """reg = bit ? v1 : v0 (constants); leaves F = bit"""
        self.op("BIT", 0, self.src(src, bit))
        self.op("LDI", imm=q(v0))
        self.op("LDIF", imm=q(v1))
        self.op("ST", reg)

    def poly(self, out, x, coeffs):
        """out = polynomial(M[x]) by Horner"""
        self.op("LDI", imm=q(coeffs[0]))
        for c in coeffs[1:]:
            self.op("MUL", x)
            self.op("ADDI", imm=q(c))
        self.op("ST", out)

    def vco_note(self, n, cv, fit, data_src, edges=1):
        """555 VCO -> DISCRETE_NOTE (count to 15 from the preload in data_src[3:0], then toggle), energy output in n.
        n_c1 = counter (Q24 counts), n_c2 = toggle 0 / 1.0, n_ph = 555 phase (cycles)"""
        self.poly(n + "_inc", cv, fit)
        self.op("LDLM", 0, self.src(data_src, 0), imm=0x0F | (24 << 8))   # preload as Q24 counts
        self.op("ST", n + "_d")
        self.op("LD", n + "_c2")
        self.op("ST", n + "_l2")                      # last count2
        self.op("LDI", imm=0)
        self.op("ST", n + "_x")
        self.op("LD", n + "_ph")
        self.op("ADD", n + "_inc")
        self.op("ST", n + "_ph")
        for _ in range(edges):
            self.op("LD", n + "_ph")
            self.op("CMPI", imm=ONE)
            at = self.skip_if(False)                  # no falling edge in this sample (left)
            self.op("ADDI", imm=-ONE)
            self.op("ST", n + "_ph")
            self.op("ST", n + "_x")                   # phase past the edge; / inc below = MAME x_time
            self.op("LD", n + "_d")                   # data == 15: the counter never moves (MAME DSS_NOTE)
            self.op("CMPI", imm=15 << 24)
            at2 = self.skip_if(True)
            self.op("LD", n + "_c1")
            self.op("ADDI", imm=ONE)
            self.op("ST", n + "_c1")
            self.op("CMPI", imm=16 << 24)             # count1 > 15: reload, toggle count2
            at3 = self.skip_if(False)
            self.op("LD", n + "_d")
            self.op("ST", n + "_c1")
            self.op("LDI", imm=ONE)
            self.op("SUB", n + "_c2")
            self.op("ST", n + "_c2")
            self.land(at3)
            self.land(at2)
            self.land(at)
        # energy output: unchanged -> count2; rose -> x_time; fell -> 1 - x_time (MAME DISC_OUT_IS_ENERGY)
        self.op("LD", n + "_inc")
        self.op("RCP")
        self.op("MUL", n + "_x")
        self.op("MINI", imm=ONE)
        self.op("ST", n + "_x")                       # x_time (1.0 when no edge: unused then)
        self.op("LD", n + "_c2")
        self.op("ST", n)
        self.op("SUB", n + "_l2")
        self.op("CMPI", imm=1)                        # rose
        self.op("LD", n + "_x")
        self.op("STF", n)
        self.op("LD", n + "_l2")
        self.op("SUB", n + "_c2")
        self.op("CMPI", imm=1)                        # fell
        self.op("LDI", imm=ONE)
        self.op("SUB", n + "_x")
        self.op("STF", n)

    def astable(self, out, th_parts, tl_parts, th1, vhigh):
        """555 astable without CV (MAME DSD_555_ASTBL, threshold 2/3, trigger 1/3, cap from 0 V at reset): timer in
        seconds x 100; th_parts / tl_parts = [(constant, None) or (constant, (source, bit))] summed for the
        capacitor switch network; out = vhigh while high (energy fraction at the edges not modelled: LFO rates)"""
        U = 0.01
        self.op("LDI", imm=0)
        for k, s in th_parts:
            if s is None:
                self.op("ADDI", imm=q(k / U))
        self.op("ST", out + "_th")
        for k, s in th_parts:
            if s is not None:
                self.op("BIT", 0, self.src(*s))
                self.op("LD", out + "_th")
                self.op("ADDI", imm=q(k / U))
                self.op("STF", out + "_th")
        self.op("LDI", imm=0)
        for k, s in tl_parts:
            if s is None:
                self.op("ADDI", imm=q(k / U))
        self.op("ST", out + "_tl")
        for k, s in tl_parts:
            if s is not None:
                self.op("BIT", 0, self.src(*s))
                self.op("LD", out + "_tl")
                self.op("ADDI", imm=q(k / U))
                self.op("STF", out + "_tl")
        self.op("LD", out + "_th")
        self.op("ADD", out + "_tl")
        self.op("ST", out + "_per")
        self.op("LD", out + "_t")
        self.op("ADDI", imm=q(1.0 / (FS * U)))
        self.op("CMP", out + "_per")
        self.op("SUB", out + "_per")
        self.op("STF", out + "_t")
        self.op("ADD", out + "_per")
        self.op("STNF", out + "_t")
        self.op("LD", out + "_t")                    # the wrapped timer: high while t < th
        self.op("CMP", out + "_th")
        self.op("LDI", imm=q(vhigh))
        self.op("LDIF", imm=0)
        self.op("ST", out)
        th0 = sum(k for k, s in th_parts if s is None)
        self.init(out + "_t", (th0 - th1) / U)        # first high = cap from 0 V to 2/3 (ln 3)

    def mix_r(self, out, ins, r_gnd=0.0):
        """DST_MIXER IS_RESISTOR, no caps: ins = [(register or constant, r)], optional rF to ground (Millman)"""
        g = sum(1.0 / r for _, r in ins) + (1.0 / r_gnd if r_gnd else 0.0)
        first = True
        for v, r in ins:
            k = 1.0 / (r * g)
            if isinstance(v, str):
                if first:
                    self.op("LD", v)
                    self.op("MULI", imm=q(k))
                else:
                    self.op("MACI", v, imm=q(k))
            else:
                if first:
                    self.op("LDI", imm=q(v * k))
                else:
                    self.op("ADDI", imm=q(v * k))
            first = False
        self.op("ST", out)


def phoenix():
    b = Phoenix("phoenix")

    # ---- Effect 1 -----------------------------------------------------------------------------------------------
    r1, r2, r3, c7, vp = 470.0, 100e3, 33e3, 6.8e-6, 12.0
    v = vp - 0.5
    r = par(r1, r3)
    v_1 = v / (r2 + r) * r + 0.5                       # FREQ high: R22 // R24 against R23
    k_1 = k_exp(par(r2, r) * c7)
    v_0 = v / (r2 + r3) * r3 + 0.5                     # FREQ low: R24 against R23
    k_0 = k_exp(par(r2, r3) * c7)
    b.sel("_t", LATCH2, 4, v_0, v_1)
    b.op("LDI", imm=q(k_0))
    b.op("LDIF", imm=q(k_1))
    b.op("ST", "_k")
    b.op("LD", "_t")
    b.op("RCM", "e1_c7", b.r("_k"))                    # e1_c7 = C7 voltage (0.55 .. 3.35 V, below the 10.5 V clip)
    b.vco_note("e1n", "e1_c7", vco_fit(47e3, 47e3, 1e-9, 0.5, 3.45), LATCH2, edges=1)
    b.sel("_lv", LATCH2, 5, TTL1, TTL1 * 100e3 / 110e3)
    b.op("LD", "e1n")
    b.op("MUL", "_lv")
    b.op("ST", "e1")
    b.op("RC", "e1f", imm=q(k_exp(par(10e3, 100e3) * 0.047e-6)))   # R19 // R20, C5
    b.op("BIT", 0, b.src(LATCH2, 5))
    b.op("LD", "e1")
    b.op("LDF", "e1f")
    b.op("ST", "e1s")

    # ---- Effect 2 -----------------------------------------------------------------------------------------------
    ln2, ln3 = math.log(2.0), math.log(3.0)
    c18, c16, c17 = 0.01e-6, 0.47e-6, 1e-6
    b.astable("e2a", [((47e3 + 100e3) * c18 * ln2, None), ((47e3 + 100e3) * c16 * ln2, (LATCH1, 4)),
                      ((47e3 + 100e3) * c17 * ln2, (LATCH1, 5))],
              [(100e3 * c18 * ln2, None), (100e3 * c16 * ln2, (LATCH1, 4)), (100e3 * c17 * ln2, (LATCH1, 5))],
              (47e3 + 100e3) * c18 * ln3, 4.0)                                       # 555 <44>
    b.astable("e2b", [(1.02e6 * 1e-6 * ln2, None)], [(510e3 * 1e-6 * ln2, None)], 1.02e6 * 1e-6 * ln3, 4.0)  # <51>
    b.mix_r("e2m1", [("e2a", 10e3), ("e2b", 5.1e3 + 5.1e3), (VCC, 5e3)], r_gnd=10e3)       # NODE_35
    b.mix_r("e2m2", [("e2b", 5.1e3), ("e2m1", 5.1e3)])                                   # NODE_36
    b.op("LD", "e2m2")
    b.op("RC", "e2c22", imm=q(k_exp(par(5.1e3, 5.1e3 + par(10e3, 5e3, 10e3)) * 100e-6)))   # NODE_37
    b.mix_r("e2cv", [("e2a", 10e3), ("e2c22", 5.1e3), (VCC, 5e3)], r_gnd=10e3)          # NODE_38
    b.vco_note("e2n", "e2cv", vco_fit(20e3, 20e3, 1e-9, 1.5, 4.0), LATCH1, edges=2)
    b.sel("_lv", LATCH1, 5, TTL1, TTL1 / 2)
    b.op("LD", "e2n")
    b.op("MUL", "_lv")
    b.op("ST", "e2s")

    # ---- Mixer (MAME phoenix_mixer) -----------------------------------------------------------------------------
    rf = 10e3
    rs = [10e3 + 47e3, 10e3 + 20e3, 20e3, 20e3]
    r_tot = 1.0 / (sum(1.0 / x for x in rs) + 1.0 / rf)
    for name, src, rin, c in (("m1", "e1s", rs[0], 10e-6), ("m2", "e2s", rs[1], 10e-6)):
        b.op("LD", src)
        b.op("SUB", name + "_c")
        b.op("MULI", imm=q(k_exp(par(rin, rf) * c)))
        b.op("ADD", name + "_c")
        b.op("ST", name + "_c")                       # input coupling cap
        b.op("LD", src)
        b.op("SUB", name + "_c")
        b.op("ST", name)
    b.op("LD", "m1")
    b.op("MULI", imm=q(r_tot / rs[0]))
    b.op("MACI", "m2", imm=q(r_tot / rs[1]))
    b.op("ST", "mx")
    b.op("RC", "mx_amp", imm=q(k_exp(100e3 * 10e-6)))   # cAmp: 100k x C32
    b.op("LD", "mx")
    b.op("SUB", "mx_amp")
    b.op("MULI", imm=q(40000.0 / 32768.0 * 0.6))
    b.op("OUT")

    # ---- Noise (MAME phoenix_sound_device) ----------------------------------------------------------------------
    # level fractions 0 .. 1.0; C24: D6 high -> 0 through R52 x C24, low -> 1 through (R51 + R49) x C24; vc24 = 1 - level
    # C25: D7 high -> 1 through (R50 + R53) x C25, low -> 0 through R54 x C25
    for reg, bit, t_hi, v_hi, t_lo, v_lo in (("n24", 6, 20e3 * 6.8e-6, 0.0, 1330.0 * 6.8e-6, 1.0),
                                             ("n25", 7, 1330.0 * 6.8e-6, 1.0, 47e3 * 6.8e-6, 0.0)):
        b.sel("_t", LATCH1, bit, v_lo, v_hi)
        b.op("LDI", imm=q(k_exp(t_lo)))
        b.op("LDIF", imm=q(k_exp(t_hi)))
        b.op("ST", "_k")
        b.op("LD", "_t")
        b.op("RCM", reg, b.r("_k"))
    b.op("LDI", imm=ONE)
    b.op("SUB", "n24")
    b.op("ST", "v24")                                  # vc24
    b.op("ADD", "n25")
    b.op("MULI", imm=q(0.5))
    b.op("MULI", imm=q(6325.0 / FS))
    b.op("ADDI", imm=q(588.0 / FS))
    b.op("ADD", "nz_ph")
    b.op("ST", "nz_ph")
    b.op("CMPI", imm=ONE)
    at = b.skip_if(False)
    b.op("ADDI", imm=-ONE)
    b.op("ST", "nz_ph")
    # 18-bit 4006 polynomial, integer state: new bit = XNOR(bit 16, bit 17), shifted in at bit 0 = the output
    b.op("LD", "nz_sr")
    b.op("CMPI", imm=1 << 17)                          # F = bit 17
    b.op("LDI", imm=0)
    b.op("LDIF", imm=1)
    b.op("ST", "nz_b17")
    b.op("LD", "nz_sr")
    b.op("CMPI", imm=1 << 17)
    b.op("ADDI", imm=-(1 << 17))
    b.op("STF", "nz_sr")                               # nz_sr = bits 0-16
    b.op("LD", "nz_sr")
    b.op("CMPI", imm=1 << 16)                          # F = bit 16
    b.op("LDI", imm=0)
    b.op("LDIF", imm=1)
    b.op("SUB", "nz_b17")
    b.op("ABS")                                        # bit16 ^ bit17
    b.op("ST", "nz_x")
    b.op("LDI", imm=1)
    b.op("SUB", "nz_x")
    b.op("ST", "nz_bit")                               # XNOR = the new bit = MAME polybit
    b.op("LD", "nz_sr")
    b.op("MULI", imm=2 << 24)
    b.op("ADD", "nz_bit")
    b.op("ST", "nz_sr")
    b.land(at)
    b.op("LD", "nz_lp")                                # 400 Hz sample-and-hold of the bit
    b.op("ADDI", imm=q(400.0 / FS))
    b.op("ST", "nz_lp")
    b.op("CMPI", imm=ONE)
    at = b.skip_if(False)
    b.op("ADDI", imm=-ONE)
    b.op("ST", "nz_lp")
    b.op("LD", "nz_bit")
    b.op("ST", "nz_lbit")
    b.land(at)
    b.op("LDI", imm=0)
    b.op("ST", "ns")
    b.op("LD", "nz_bit")
    b.op("CMPI", imm=1)
    b.op("LD", "ns")
    b.op("ADD", "v24")
    b.op("STNF", "ns")                                 # polybit 0: + vc24
    b.op("LD", "nz_lbit")
    b.op("CMPI", imm=1)
    b.op("LD", "ns")
    b.op("ADD", "n25")
    b.op("STNF", "ns")                                 # low-passed bit 0: + vc25
    b.op("LD", "ns")
    b.op("MULI", imm=q(0.5 * 32767.0 / 32768.0 * 0.4))
    b.op("OUT")
    b.init("nz_lp", 1.0)                               # MAME's 400 Hz counter fires on the first sample
    return b.finish()


if __name__ == "__main__":
    p = phoenix()
    print(f"phoenix: {len(p.code)} words, worst path {p.worst_path()} units, {len(p.regs)} registers")
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_bytes(p.binary())
