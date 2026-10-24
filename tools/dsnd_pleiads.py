#!/usr/bin/env python3
"""Pleiads sound effects (Tehkan CPU board 370-17-0100, Pleiades.pdf p.22-23) as a discrete-engine program, built from
the schematic (vault: Projects/Arcade-Phoenix_MiSTer/Claude/phoenix_schematic_facts.md). MAME's pleiads.cpp model is
borrowed from Naughty Boy / Pop Flamer ("the real values are unknown") and is not used.

Sources: LATCH1 = LS374 <27> (6000 write), LATCH2 = LS374 <34> (6800 write), LATCH3 bit 0 = the 8085 SOD pin (SIM).
  6000: D0-3 LS163 <28> divider tone (mixer R55), D4 C22 sweep -> 556 <15> CV, D5 <15> T2 RESET, D6 / D7 4066 IN1 / IN2.
  6800: D0-3 LS163 <41> divider tone (mixer R56; NOT played: MAME's TMS3615 notes stand in, user's choice), D4 C43 sweep
  -> 556 <45> CV, D5 <45> T2 RESET, D6 / D7 7910 MSL / MT (the undumped Epson 7910 is not modelled).
  SOD: 4066 IN3 / IN4 envelopes (C17 / C18), C17 also sweeps 556 <22> T1, whose output gates them (the shot sound).
Noise: 556 <22> T2 clocks the 18-bit 4006 <14> (XNOR of stages 17 / 18, LS136 + LS14); its input bit gates 4066 IN1 /
IN2 (C20 / C19 envelopes), summed into the LM324 <43> band-pass (mixer R96).
Mixer: passive, seven legs through coupling caps into R97 10K + 10K pot (the 7910 leg R84 is outside).

555 timers: exact phase timers (unit 10 ms); the high time (Ra + Rb) C ln((5 - CV/2) / (5 - CV)) is a degree-7 fit in
the normalised CV (period error < 0.3 %), low time Rb C ln 2. Supply 5 V, output high 3.3 V, the CV pin's internal
5K / 10K divider (2/3 Vcc through 3.33K) loaded by the external resistors."""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dsnd import FS, ONE, LATCH1, LATCH2, LATCH3, q, par, rc_exp   # noqa: E402
from dsnd_phoenix import Phoenix                                   # noqa: E402

VCC, V555, TTL1, VD = 5.0, 3.3, 3.4, 0.6
U = 0.01                                              # timer unit 10 ms
CVT = VCC * 2 / 3                                     # CV pin Thevenin: 3.33 V through 3.33K
RCV = 1.0 / (1.0 / 5e3 + 1.0 / 10e3)
LN2 = math.log(2.0)


def k_exp(tau):
    return 1.0 - math.exp(-1.0 / (FS * tau))


def th_fit(ra, rb, c, lo, hi, deg, tol=3e-3):
    """555 high time (units U) as a polynomial in x = (CV - mid) / half; tol = max period error"""
    cv = np.linspace(lo, hi, 4000)
    x = (cv - (lo + hi) / 2) / ((hi - lo) / 2)
    y = (ra + rb) * c * np.log((VCC - cv / 2) / (VCC - cv)) / U
    p = np.polyfit(x, y, deg)
    tl = rb * c * LN2 / U
    err = np.max(np.abs((np.polyval(p, x) + tl) / (y + tl) - 1.0))
    assert err < tol and np.abs(p).max() < 64, (err, np.abs(p).max())
    return list(p), (lo + hi) / 2, 2.0 / (hi - lo)


class Pleiads(Phoenix):
    def div_tone(self, out, latch, fclk):
        """LS163 loaded with D0-3 at each carry, clocked at fclk; LS74 toggles per carry: out 0 / 1.0 square at
        fclk / (2 (16 - N)); N = 15 holds the carry, the flip-flop stops"""
        self.op("LDLM", 0, self.src(latch, 0), imm=0x0F | (16 << 8))
        self.op("ST", out + "_d")
        self.op("LDI", imm=16 << 16)
        self.op("SUB", out + "_d")
        self.op("ST", out + "_p")                     # clocks per carry, Q16
        self.op("LD", out + "_ph")
        self.op("ADDI", imm=int(round(fclk / FS * 65536)))
        self.op("ST", out + "_ph")
        self.op("LD", out + "_d")
        self.op("CMPI", imm=15 << 16)
        self.op("LDI", imm=0)
        self.op("STF", out + "_ph")                   # N = 15: no carry edges
        self.op("LD", out + "_ph")
        self.op("CMP", out + "_p")
        self.op("SUB", out + "_p")
        self.op("STF", out + "_ph")
        self.op("LDI", imm=ONE)
        self.op("SUB", out)
        self.op("STF", out)

    def astable_cv(self, out, cv, ra, rb, c, lo, hi, deg, vhigh, reset=None, wrap=None, tol=3e-3):
        """556 half with a driven CV pin (register cv, volts). out = vhigh while high. reset = (source, bit), low =
        RESET: output low, the cap discharged (first high from 0 V, approximated at the nominal CV). wrap: register
        set to 1.0 on the sample where a cycle starts (the output rises), else 0"""
        p, mid, inv = th_fit(ra, rb, c, lo, hi, deg, tol)
        tl = rb * c * LN2 / U
        self.op("LD", cv)
        self.op("ADDI", imm=q(-mid))
        self.op("MULI", imm=q(inv))                   # CV comes from bounded caps: inside the fit range
        self.op("ST", out + "_x")
        self.poly(out + "_th", out + "_x", p)
        self.op("LD", out + "_th")
        self.op("ADDI", imm=q(tl))
        self.op("ST", out + "_per")
        if wrap:
            self.op("LDI", imm=0)
            self.op("ST", wrap)
        self.op("LD", out + "_t")
        self.op("ADDI", imm=q(1.0 / (FS * U)))
        self.op("CMP", out + "_per")
        self.op("SUB", out + "_per")
        self.op("STF", out + "_t")
        self.op("ADD", out + "_per")
        self.op("STNF", out + "_t")
        if wrap:
            self.op("LDI", imm=ONE)
            self.op("STF", wrap)
        if reset:
            extra = (ra + rb) * c * math.log(VCC / (VCC - CVT / 2)) / U
            self.op("BIT", 1, self.src(*reset))      # F = reset active (pin low)
            self.op("LDI", imm=q(-extra))
            self.op("STF", out + "_t")
        self.op("LD", out + "_t")
        self.op("CMP", out + "_th")
        self.op("LDI", imm=q(vhigh))
        self.op("LDIF", imm=0)
        self.op("ST", out)
        if reset:
            self.op("BIT", 1, self.src(*reset))
            self.op("LDI", imm=0)
            self.op("STF", out)

    def envelope(self, reg, drive, v_hi, tau_hi, tau_on, tau_off, sw):
        """diode-charged cap: drive high -> toward v_hi through tau_hi; low -> toward 0 through tau_on while the
        switch register sw is 1.0, tau_off otherwise (0 = holds). drive = (source, bit)"""
        self.op("LD", sw)
        self.op("CMPI", imm=q(0.5))
        self.op("LDI", imm=q(k_exp(tau_off)) if tau_off else 0)
        self.op("LDIF", imm=q(k_exp(tau_on)))
        self.op("ST", "_k")
        self.op("BIT", 0, self.src(*drive))
        self.op("LD", "_k")
        self.op("LDIF", imm=q(k_exp(tau_hi)))
        self.op("ST", "_k")
        self.op("LDI", imm=0)
        self.op("LDIF", imm=q(v_hi))
        self.op("RCM", reg, self.r("_k"))

    def cv_node(self, out, ins):
        """CV pin voltage: Millman of the internal 3.33 V / 3.33K and ins = [(register or constant, r)]"""
        self.mix_r(out, ins + [(CVT, RCV)])


def pleiads():
    b = Pleiads("pleiads")
    f555 = 1.44 / ((20e3 + 2 * 20e3) * 1e-9)           # 556 <7>: 24 kHz divider clocks

    # ---- divider tones: R55 = 6000. The 6800 tone (LS163 <41>, mixer R56) is not played: the user chose MAME's TMS3615
    # notes for the 6800 nibble instead (2026-10-23), and the two play the same writes at different pitches.
    # Board version: b.div_tone("tb", LATCH2, f555), and MACI "tb" x rt / 47e3 x TTL1 in the mixer.
    b.div_tone("ta", LATCH1, f555)

    # ---- 6800 D4 / D5: C43 sweep, 556 <45> ----------------------------------------------------------------------
    b.op("BIT", 0, b.src(LATCH2, 4))                   # D4 = 1: 7405 sinks, R57 1K discharges C43
    b.op("LDI", imm=q(k_exp(500e3 * 6.8e-6)))
    b.op("LDIF", imm=q(k_exp(1e3 * 6.8e-6)))
    b.op("ST", "_k")
    b.op("LDI", imm=q(VCC))
    b.op("LDIF", imm=0)
    b.op("RCM", "c43", b.r("_k"))
    b.cv_node("cv45a", [("c43", 2e3)])                                   # R93 2K
    b.astable_cv("t45a", "cv45a", 510e3, 510e3, 0.1e-6, 1.2, 4.4, 4, V555, tol=3e-2)   # LFO
    b.cv_node("cv45b", [("c43", 1e3), ("t45a", 10e3)])                    # R92 1K, R91 10K from OUT1
    b.astable_cv("t45b", "cv45b", 47e3, 100e3, 0.01e-6, 0.7, 4.52, 7, V555, reset=(LATCH2, 5))
    b.rcfilter("s45", "t45b", 2e3, 0.047e-6)                             # R94 2K, C29

    # ---- 6000 D4 / D5: C22 sweep, 556 <15> ----------------------------------------------------------------------
    b.op("BIT", 0, b.src(LATCH1, 4))                   # D4 = 0: R36 1K + D8 charge C22; 1: R34 500K discharges it
    b.op("LDI", imm=q(k_exp(1e3 * 6.8e-6)))
    b.op("LDIF", imm=q(k_exp(500e3 * 6.8e-6)))
    b.op("ST", "_k")
    b.op("LDI", imm=q(VCC - VD))
    b.op("LDIF", imm=0)
    b.op("RCM", "c22", b.r("_k"))
    b.cv_node("cv15a", [("c22", 1e3)])                                   # R15 1K
    b.astable_cv("t15a", "cv15a", 200e3, 510e3, 0.1e-6, 0.75, 4.2, 4, V555, tol=3e-2)   # LFO
    b.cv_node("cv15b", [("c22", 1e3), ("t15a", 10e3)])                    # R14 1K, R13 10K from OUT1
    b.astable_cv("t15b", "cv15b", 1e3, 300e3, 0.01e-6, 0.7, 4.1, 5, V555, reset=(LATCH1, 5))
    b.rcfilter("s15", "t15b", 2e3, 0.047e-6)                             # R33 2K, C21

    # ---- noise: 556 <22> T2 (CV2 open) clocks the 4006 ----------------------------------------------------------
    per = (201e3 * 0.01e-6 * LN2 + 1e3 * 0.01e-6 * LN2)
    b.op("LD", "nz_ph")
    b.op("ADDI", imm=q(1.0 / (FS * per)))
    b.op("ST", "nz_ph")
    b.op("CMPI", imm=ONE)
    at = b.skip_if(False)
    b.op("ADDI", imm=-ONE)
    b.op("ST", "nz_ph")
    # 18 stages left-aligned in nz_sr (stage 1 = bit 14 .. stage 18 = bit 31): a shift drops stage 18 off the top
    b.op("LD", "nz_sr")
    b.op("MULI", imm=2 << 24)
    b.op("ADD", "nz_in")
    b.op("ST", "nz_sr")
    # 4006 D1 input = XNOR(stage 17, stage 18) = sign bits of 2 x sr and sr; the 4066 C1 / C2 gate
    b.op("CMPI", imm=0)
    b.op("LDI", imm=0)
    b.op("LDIF", imm=1)
    b.op("ST", "_a")                                   # stage 18 = 0
    b.op("LD", "nz_sr")
    b.op("MULI", imm=2 << 24)
    b.op("CMPI", imm=0)
    b.op("LDI", imm=0)
    b.op("LDIF", imm=1)
    b.op("SUB", "_a")
    b.op("ABS")                                        # stage 17 ^ stage 18
    b.op("CMPI", imm=1)                                # F = XOR
    b.op("LDI", imm=1 << 14)
    b.op("LDIF", imm=0)
    b.op("ST", "nz_in")                                # the next bit into stage 1
    b.op("LDI", imm=ONE)
    b.op("LDIF", imm=0)
    b.op("ST", "sw12")                                 # 4066 C1 / C2 closed while D1 is high
    b.land(at)
    b.init("nz_in", (1 << 14) / ONE)                   # register 0 at power-on (RESET OUT zaps it): D1 = XNOR(0, 0) = 1
    b.init("sw12", 1.0)

    # ---- 4066 IN1 / IN2 (6000 D6 / D7), band-pass -> mixer R96 --------------------------------------------------
    b.envelope("c20", (LATCH1, 6), VCC - VD, 330 * 2.2e-6, 20e3 * 2.2e-6, 0, "sw12")
    b.envelope("c19", (LATCH1, 7), VCC - VD, 330 * 6.8e-6, 47e3 * 6.8e-6, 0, "sw12")
    b.op("LD", "c20")
    b.op("MACI", "c19", imm=ONE)
    b.op("MULI", imm=q(0.5))                           # R45 / R44 10K: Thevenin (V1 + V2) / 2
    b.op("MUL", "sw12")                                # switches open: R49 / R48 pull both to 0
    b.op("ST", "bp_in")
    r1, r2, r3, c = 5e3, 470.0, 200e3, 0.047e-6        # MFB band-pass (#unverified topology, see facts note)
    f0 = math.sqrt((r1 + r2) / (r1 * r2 * r3)) / (2 * math.pi * c)
    qf = 0.5 * math.sqrt(r3 * (r1 + r2) / (r1 * r2))
    b.filter2("bp", "bp_in", f0, 1.0 / qf, kind="bp")
    b.op("LD", "bp")
    b.op("MULI", imm=q(-r3 / (2 * r1)))                # peak gain -20
    b.op("ADDI", imm=q(VCC))                           # + input at the 5 V reference
    b.op("MAXI", imm=0)
    b.op("MINI", imm=q(10.5))                          # LM324 on 12 V
    b.op("ST", "s96")

    # ---- SOD: 4066 IN3 / IN4, 556 <22> T1 sweep and gate -> mixer R17 -------------------------------------------
    b.op("LD", "t22a")
    b.op("CMPI", imm=q(1.0))
    b.op("LDI", imm=0)
    b.op("LDIF", imm=ONE)
    b.op("ST", "sw34")                                 # C3 / C4 = <22> OUT1 (last sample)
    b.envelope("c17", (LATCH3, 0), VCC - VD, 330 * 6.8e-6, (33e3 + 10e3) * 6.8e-6, 0, "sw34")
    b.envelope("c18", (LATCH3, 0), (VCC - VD) * 10e3 / 10.33e3, par(330, 10e3) * 2.2e-6,
               par(10e3, 30e3) * 2.2e-6, 10e3 * 2.2e-6, "sw34")
    b.op("LD", "c17")                                  # <36> 10->8 x3, <43> 13->14 inverting about 5 V
    b.op("MULI", imm=q(3.0))
    b.op("MINI", imm=q(10.5))
    b.op("ST", "_v8")
    b.op("LDI", imm=q(10.0))
    b.op("SUB", "_v8")
    b.op("MAXI", imm=0)
    b.op("ST", "v14")
    b.cv_node("cv22", [("v14", 20e3), (0.0, 20e3)])                       # R102 20K, R103 20K (to ground)
    b.astable_cv("t22a", "cv22", 33e3, 47e3, 0.01e-6, 2.45, 3.85, 2, V555, tol=1e-2)   # sweep
    g = 1.0 / 33e3 + 1.0 / 20e3 + 1.0 / 10e3          # OUT3 R22 33K, OUT4 R23 20K into R24 10K
    b.op("LD", "c17")
    b.op("MULI", imm=q(1.0 / 33e3 / g))
    b.op("MACI", "c18", imm=q(1.0 / 20e3 / g))
    b.op("MUL", "sw34")
    b.op("MULI", imm=q(1.0 + 39e3 / 10e3))             # <36> 12->14
    b.op("MINI", imm=q(10.5))
    b.op("ST", "s17")

    # ---- passive mixer: seven legs into R97 10K + 10K pot (Millman); the six 10u coupling caps (corners ~1 Hz) are one
    # DC block on the sum, C16 0.047u (R17 leg, ~170 Hz) keeps its own high pass; R84 = the 7910 leg (outside)
    rt = par(20e3, 20e3, 20e3, 33e3, 20e3, 47e3, 20e3, 20e3)
    b.crfilter("h17", "s17", 20e3, 0.047e-6)
    b.op("LD", "h17")
    b.op("MULI", imm=q(rt / 20e3))
    b.op("MACI", "s96", imm=q(rt / 20e3))
    b.op("MACI", "ta", imm=q(rt / 20e3 * TTL1))
    b.op("MACI", "s15", imm=q(rt / 33e3))
    b.op("MACI", "s45", imm=q(rt / 20e3))
    b.op("ST", "mx_s")
    b.crfilter("mx", "mx_s", 20e3, 10e-6)
    b.output("mx", 0.5)                                # 2 V at the pot = full scale
    return b.finish()


if __name__ == "__main__":
    p = pleiads()
    print(f"pleiads: {len(p.code)} words, worst path {p.worst_path()} units, {len(p.regs)} registers")
    if len(sys.argv) > 1:
        Path(sys.argv[1]).write_bytes(p.binary())
