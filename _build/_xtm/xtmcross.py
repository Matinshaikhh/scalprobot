"""xtmcross.py - is the LBMA fix the same asset as COMEX GC, or not?

xtmrecon section 4 measured corr(daily log returns) = 0.734 between the
LBMA PM fix and the GC=F daily close, against a 0.80 floor that the recon
script itself declared would mean "one of the two series is not gold".
The floor was tripped, so it gets adjudicated here instead of excused.

Two candidate explanations:

  A. SAMPLING OFFSET. The PM fix is a 15:00 London auction print (10:00
     NY). Yahoo's GC=F daily bar closes at the 17:00 NY electronic close.
     The two 24-hour windows therefore overlap by only about 17 of 24
     hours. For a driftless random walk with uniform intensity the
     correlation of two windows of length T offset by D is (T-D)/T, which
     at T=24h, D=7h gives 0.71 - within a whisker of what was measured.

  B. DATA DEFECT. One series is mis-scaled, mis-dated, stale, or is not
     gold at all.

These make OPPOSITE predictions at longer horizons, which is what makes
this decidable rather than a matter of opinion. Under A the offset is
FIXED at ~7 hours, so as the measurement window T grows the non-overlap
fraction D/T shrinks and correlation must climb toward 1: about 0.93 at
5 days, 0.97 at 10, 0.99 at 20. Under B the defect scales with the data,
so correlation stays flat or degrades.

A second, independent discriminator: LEVELS. A timing offset cannot move
the price level. If the two series are the same metal, log(fix/futures)
must be small and slowly varying - it is the cost-of-carry basis, which
moves with interest rates over months, not with noise over days. A
mis-scaled or wrong-asset series cannot produce that.

This file computes NO signal and NO serial-dependence statistic. Horizon
correlations between two contemporaneous price series are a measurement
of instrument identity, not of predictability: nothing here relates a
past return to a future one.
"""

import json
import math
import os
import sys
import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
SEAL = datetime.date(2026, 3, 1)


def say(s=""):
    print(s)
    sys.stdout.flush()


def load_lbma(name):
    rows = json.load(open(os.path.join(DATA, name), "r", encoding="utf-8"))
    out = {}
    for r in rows:
        v = r.get("v") or []
        if v and isinstance(v[0], (int, float)) and v[0] > 0:
            out[datetime.date.fromisoformat(r["d"])] = float(v[0])
    return out


def load_yahoo(name):
    d = json.load(open(os.path.join(DATA, name), "r", encoding="utf-8"))
    r = d["chart"]["result"][0]
    out = {}
    for t, c in zip(r["timestamp"], r["indicators"]["quote"][0]["close"]):
        if c is not None:
            out[datetime.datetime.fromtimestamp(t, datetime.UTC).date()] = float(c)
    return out


def corr(xs, ys):
    n = len(xs)
    mx = math.fsum(xs) / n
    my = math.fsum(ys) / n
    cxy = math.fsum((a - mx) * (b - my) for a, b in zip(xs, ys))
    cxx = math.fsum((a - mx) ** 2 for a in xs)
    cyy = math.fsum((b - my) ** 2 for b in ys)
    return cxy / math.sqrt(cxx * cyy)


def main():
    pm = load_lbma("gold_pm.json")
    am = load_lbma("gold_am.json")
    gc = load_yahoo("yahoo_gcf_d.json")

    #--- Common trading days only, both series present, before the seal.
    days = sorted(d for d in set(pm) | set(am)
                  if d in gc and d < SEAL)
    fix = {d: (pm[d] if d in pm else am[d]) for d in days}
    say("XTM_CROSS  instrument identity: LBMA fix vs COMEX GC front-month")
    say("  common days=%d  %s .. %s" % (len(days), days[0], days[-1]))
    say()

    # ------------------------------------------------------------- 1
    say("1. HORIZON TEST - does correlation climb the way an OFFSET must?")
    say("   Prediction under a fixed ~7h offset D on window T: (T-D)/T.")
    say()
    say("    horizon   pairs     corr   offset-model   defect-model")
    D = 7.0
    for k in (1, 2, 5, 10, 20, 60):
        a, b = [], []
        i = 0
        while i + k < len(days):
            d0, d1 = days[i], days[i + k]
            #--- Reject a pair straddling a hole: k trading days must not
            #--- span more than k calendar days plus weekends and a
            #--- holiday allowance, or the two series may be sampling
            #--- different spans and the comparison is meaningless.
            if (d1 - d0).days <= k * 1.6 + 5:
                a.append(math.log(fix[d1] / fix[d0]))
                b.append(math.log(gc[d1] / gc[d0]))
            i += k
        if len(a) > 30:
            pred = (24.0 * k - D) / (24.0 * k)
            say("    %3dd    %6d   %.4f      %.3f          flat~0.73"
                % (k, len(a), corr(a, b), pred))
    say()
    say("   A rising column that tracks the offset model confirms the two")
    say("   series are the same asset sampled at different clock times.")
    say("   A column that stays near 0.73 would mean a real defect.")

    # ------------------------------------------------------------- 2
    say()
    say("2. LEVEL TEST - the basis, which a timing offset cannot create")
    bas = [(d, 1e4 * math.log(fix[d] / gc[d])) for d in days]
    vals = sorted(v for _, v in bas)
    n = len(vals)
    say("   log(fix/GC) in basis points:")
    say("     n=%d  p1=%.0f  p10=%.0f  med=%.0f  p90=%.0f  p99=%.0f"
        % (n, vals[n // 100], vals[n // 10], vals[n // 2],
           vals[9 * n // 10], vals[99 * n // 100]))
    #--- If this is a real cost-of-carry basis it drifts slowly with rates.
    #--- Its year-by-year median should move smoothly and stay inside a
    #--- band of a few tens of bp, never flipping scale.
    say("   median basis by year (bp) - should drift, never jump scale:")
    yrs = {}
    for d, v in bas:
        yrs.setdefault(d.year, []).append(v)
    line = "     "
    for y in sorted(yrs):
        s = sorted(yrs[y])
        line += "%d:%+d " % (y, s[len(s) // 2])
        if len(line) > 68:
            say(line)
            line = "     "
    if line.strip():
        say(line)

    # ------------------------------------------------------------- 3
    say()
    say("3. SAME-SERIES CONTROL - AM fix vs PM fix on the same day")
    say("   These are the SAME auction house, same metal, 4h apart. Their")
    say("   1-day return correlation is the ceiling any two differently-")
    say("   timed gold series can reach. If AM-vs-PM is also well under")
    say("   1.0, then 0.73 for a 7h offset is ordinary, not anomalous.")
    both = sorted(d for d in set(pm) & set(am) if d < SEAL)
    a, b = [], []
    for i in range(1, len(both)):
        if (both[i] - both[i - 1]).days <= 5:
            a.append(math.log(pm[both[i]] / pm[both[i - 1]]))
            b.append(math.log(am[both[i]] / am[both[i - 1]]))
    say("   pairs=%d  corr(PM 1d, AM 1d)=%.4f" % (len(a), corr(a, b)))
    say("   (offset model for a 4h gap: %.3f)" % ((24.0 - 4.0) / 24.0))

    say()
    say("XTM_CROSS VERDICT=see section 1 slope and section 2 basis")
    return 0


if __name__ == "__main__":
    sys.exit(main())
