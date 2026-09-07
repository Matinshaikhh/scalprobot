"""xtmrecon.py - XauTrendMomentum : reconnaissance, NOT a test.

WHAT THIS SCRIPT IS FORBIDDEN TO COMPUTE, and the reason the ban is written
into the file rather than into a promise:

  * any trailing-return signal, any sign(r_k), any momentum position
  * any autocorrelation, variance ratio, or serial-dependence statistic
  * any P&L, any Sharpe of any rule, anything conditioned on past returns

H3 is a claim about serial dependence in gold. Measuring serial dependence
here and then "pre-registering" a test of it afterwards would be fraud with
extra steps - it is exactly the failure XSP 0.1's own null correction was
written to prevent. This file establishes only what a pre-registration is
allowed to know in advance:

  1. that the data exists, covers what it claims, and agrees with an
     independent source
  2. the UNCONDITIONAL volatility, which is a denominator, not a signal
  3. how many independent observations that volatility implies, and
     therefore what effect size the study can and cannot detect

Point 3 is the one that matters. A test too weak to reject its own null is
not a test, and the honest time to discover that is before the gates are
fixed, not after they fail.

Sources, all free and public, fetched 2026-09-06:
  gold_am.json / gold_pm.json  LBMA official Gold Price, USD/GBP/EUR,
                               1968-01-02 onward. The authoritative fix.
  yahoo_gcf_d.json             COMEX GC front-month continuous, 2000-08-30
                               onward. Independent cross-check only.
  yahoo_irx_d.json             13-week US T-bill discount rate, 1970-01-02
                               onward. Gold yields nothing, so the carry of
                               a long position IS the cash rate; a trend
                               study on price returns rather than excess
                               returns would credit the strategy with the
                               risk-free rate it never earned.
"""

import json
import math
import os
import sys
import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")

#--- The seal. The existing project sealed 2026-03-01 onward as VAL for the
#--- minute study; the same wall is applied here even though this is a
#--- different dataset, because it is the same WALL-CLOCK PERIOD and a look
#--- is a look. Everything at or after this date is withheld from every
#--- number this script prints.
SEAL = datetime.date(2026, 3, 1)

#--- Gold was not a freely floating asset before the Smithsonian Agreement.
#--- The 1968-1971 London price moved inside a two-tier system underwritten
#--- by central bank intervention, which is a different data-generating
#--- process, not an early sample of this one. 1972-01-01 is chosen on that
#--- mechanical ground and for no statistical reason.
FLOAT_START = datetime.date(1972, 1, 1)


def say(s=""):
    print(s)
    sys.stdout.flush()


def load_lbma(name):
    """LBMA publishes [{"d":"YYYY-MM-DD","v":[usd,gbp,eur]}]. Only USD is
    used. `v` may be null, short, or carry a nonsense value - the 1968-04-02
    record has GBP equal to USD to the cent, which is a transcription
    artefact of a fix published before the LBMA kept machine records."""
    p = os.path.join(DATA, name)
    rows = json.load(open(p, "r", encoding="utf-8"))
    out = []
    bad = 0
    for r in rows:
        try:
            d = datetime.date.fromisoformat(r["d"])
            v = r.get("v") or []
            usd = v[0] if len(v) > 0 else None
            if usd is None or not isinstance(usd, (int, float)) or usd <= 0:
                bad += 1
                continue
            out.append((d, float(usd)))
        except Exception:
            bad += 1
    out.sort(key=lambda x: x[0])
    return out, bad


def load_yahoo(name):
    p = os.path.join(DATA, name)
    d = json.load(open(p, "r", encoding="utf-8"))
    r = d["chart"]["result"][0]
    ts = r["timestamp"]
    cl = r["indicators"]["quote"][0]["close"]
    out = []
    for t, c in zip(ts, cl):
        if c is None:
            continue
        dt = datetime.datetime.fromtimestamp(t, datetime.UTC).date()
        out.append((dt, float(c)))
    out.sort(key=lambda x: x[0])
    return out


def dedup(series):
    """Last value wins on a duplicated date. Counted, never silent."""
    seen = {}
    for d, v in series:
        seen[d] = v
    n_dup = len(series) - len(seen)
    return sorted(seen.items()), n_dup


def sd(xs):
    n = len(xs)
    if n < 2:
        return 0.0
    m = math.fsum(xs) / n
    return math.sqrt(math.fsum((x - m) ** 2 for x in xs) / (n - 1))


def main():
    say("XTM_RECON  XauTrendMomentum reconnaissance")
    say("  Data integrity, coverage and STATISTICAL POWER only.")
    say("  No signal, no serial-dependence statistic, no P&L is computed")
    say("  anywhere in this file. See the module docstring for why.")
    say()

    # ---------------------------------------------------------------- 1
    say("1. SOURCES AND INTEGRITY")
    am, am_bad = load_lbma("gold_am.json")
    pm, pm_bad = load_lbma("gold_pm.json")
    am, am_dup = dedup(am)
    pm, pm_dup = dedup(pm)
    say("  LBMA AM  n=%-6d %s .. %s  unusable=%d dup=%d"
        % (len(am), am[0][0], am[-1][0], am_bad, am_dup))
    say("  LBMA PM  n=%-6d %s .. %s  unusable=%d dup=%d"
        % (len(pm), pm[0][0], pm[-1][0], pm_bad, pm_dup))

    #--- The PM fix is the settlement reference the whole gold market quotes
    #--- against, so it is the primary. AM fills a PM gap: on days when only
    #--- one auction cleared, dropping the day would silently shorten a
    #--- holding period, which is worse than mixing two fixes four hours
    #--- apart on a series whose daily sd is ~1%.
    pmd = dict(pm)
    amd = dict(am)
    alld = sorted(set(pmd) | set(amd))
    px = []
    filled = 0
    for d in alld:
        if d in pmd:
            px.append((d, pmd[d]))
        else:
            px.append((d, amd[d]))
            filled += 1
    say("  merged   n=%-6d %s .. %s  (PM primary, %d days filled from AM)"
        % (len(px), px[0][0], px[-1][0], filled))

    #--- Absurd-print screen. Not an outlier filter: a 1979 or 2020 gold day
    #--- can legitimately move 10%. This only catches transcription damage,
    #--- at a threshold no real session has ever reached.
    jumps = []
    for i in range(1, len(px)):
        gap = (px[i][0] - px[i - 1][0]).days
        if gap > 10:
            continue
        r = math.log(px[i][1] / px[i - 1][1])
        if abs(r) > 0.25:
            jumps.append((px[i][0], px[i - 1][1], px[i][1], r))
    say("  |1-day log move| > 25%%: %d" % len(jumps))
    for d, a, b, r in jumps[:6]:
        say("    %s  %.2f -> %.2f  (%.1f%%)" % (d, a, b, 100 * r))

    # ---------------------------------------------------------------- 2
    say()
    say("2. THE SEAL")
    held = [x for x in px if x[0] >= SEAL]
    px = [x for x in px if x[0] < SEAL]
    say("  withheld: %d observations from %s onward" % (len(held), SEAL))
    say("  DECLARED CONTAMINATION: the fetched files carry data past the")
    say("  seal and their tail was visible in the terminal when downloaded,")
    say("  so the approximate level of gold in Sept 2026 is known to me.")
    say("  It is declared here rather than concealed. The direction of that")
    say("  knowledge is recorded in the pre-registration so it cannot be")
    say("  used after the fact to flatter a result.")
    say("  study set: n=%d  %s .. %s" % (len(px), px[0][0], px[-1][0]))

    px = [x for x in px if x[0] >= FLOAT_START]
    say("  post-float set (from %s): n=%d  %s .. %s"
        % (FLOAT_START, len(px), px[0][0], px[-1][0]))

    # ---------------------------------------------------------------- 3
    say()
    say("3. COVERAGE AND GAPS")
    gaps = {}
    for i in range(1, len(px)):
        g = (px[i][0] - px[i - 1][0]).days
        gaps[g] = gaps.get(g, 0) + 1
    say("  business-day gap histogram (days between consecutive fixes):")
    for g in sorted(gaps):
        if gaps[g] >= 5 or g > 5:
            say("    %2d day(s): %d" % (g, gaps[g]))
    years = (px[-1][0] - px[0][0]).days / 365.25
    say("  span=%.1f years  observations/year=%.1f"
        % (years, len(px) / years))

    # ---------------------------------------------------------------- 4
    say()
    say("4. INDEPENDENT CROSS-CHECK (LBMA fix vs COMEX GC front-month)")
    gc = load_yahoo("yahoo_gcf_d.json")
    gc = [x for x in gc if x[0] < SEAL]
    gcd = dict(gc)
    pairs = []
    prev = None
    for d, v in px:
        if d in gcd:
            if prev is not None and (d - prev[0]).days <= 5:
                pairs.append((prev, (d, v, gcd[d])))
            prev = (d, v, gcd[d])
        else:
            prev = None
    la = [math.log(b[1] / a[1]) for a, b in pairs]
    lb = [math.log(b[2] / a[2]) for a, b in pairs]
    if len(la) > 30:
        ma = math.fsum(la) / len(la)
        mb = math.fsum(lb) / len(lb)
        cov = math.fsum((x - ma) * (y - mb) for x, y in zip(la, lb))
        va = math.fsum((x - ma) ** 2 for x in la)
        vb = math.fsum((y - mb) ** 2 for y in lb)
        corr = cov / math.sqrt(va * vb) if va > 0 and vb > 0 else float("nan")
        say("  overlapping days=%d  corr(daily log returns)=%.4f"
            % (len(la), corr))
        say("  LBMA daily sd=%.4f%%   GC daily sd=%.4f%%"
            % (100 * sd(la), 100 * sd(lb)))
        say("  (a fix is a single auction print and GC is a continuous")
        say("   futures close four hours later, so a correlation near 0.9")
        say("   is agreement, not a defect; anything under ~0.8 would mean")
        say("   one of the two series is not gold.)")
    else:
        say("  insufficient overlap")

    # ---------------------------------------------------------------- 5
    say()
    say("5. CARRY SERIES COVERAGE (13-week T-bill)")
    irx = load_yahoo("yahoo_irx_d.json")
    irx_s = [x for x in irx if x[0] < SEAL]
    say("  ^IRX n=%d  %s .. %s" % (len(irx_s), irx_s[0][0], irx_s[-1][0]))
    have = set(d for d, _ in irx_s)
    miss = sum(1 for d, _ in px if d not in have)
    say("  study days with no same-day rate print: %d of %d (%.2f%%)"
        % (miss, len(px), 100.0 * miss / len(px)))
    say("  -> carried forward from the previous print; a T-bill rate is a")
    say("     level, not a return, so a stale print costs precision and")
    say("     cannot manufacture one.")
    rr = [v for d, v in irx_s if d >= FLOAT_START]
    say("  rate over the study span: min=%.2f%% med=%.2f%% max=%.2f%%"
        % (min(rr), sorted(rr)[len(rr) // 2], max(rr)))

    # ---------------------------------------------------------------- 6
    say()
    say("6. UNCONDITIONAL VOLATILITY BY DECADE  (a denominator, not a signal)")
    rets = []
    for i in range(1, len(px)):
        if (px[i][0] - px[i - 1][0]).days > 10:
            continue
        rets.append((px[i][0], math.log(px[i][1] / px[i - 1][1])))
    decs = [(datetime.date(1972, 1, 1), datetime.date(1980, 1, 1), "1972-79"),
            (datetime.date(1980, 1, 1), datetime.date(1990, 1, 1), "1980s"),
            (datetime.date(1990, 1, 1), datetime.date(2000, 1, 1), "1990s"),
            (datetime.date(2000, 1, 1), datetime.date(2010, 1, 1), "2000s"),
            (datetime.date(2010, 1, 1), datetime.date(2020, 1, 1), "2010s"),
            (datetime.date(2020, 1, 1), SEAL, "2020-26")]
    say("   period      n    ann.vol   years")
    tot_y = 0.0
    for a, b, lab in decs:
        sub = [r for d, r in rets if a <= d < b]
        if not sub:
            continue
        yy = (min(b, px[-1][0]) - max(a, px[0][0])).days / 365.25
        tot_y += yy
        say("   %-8s %5d   %6.2f%%   %5.1f"
            % (lab, len(sub), 100 * sd(sub) * math.sqrt(len(sub) / yy), yy))
    allr = [r for _, r in rets]
    ann = sd(allr) * math.sqrt(len(allr) / tot_y)
    say("   %-8s %5d   %6.2f%%   %5.1f" % ("ALL", len(allr), 100 * ann, tot_y))

    # ---------------------------------------------------------------- 7
    say()
    say("7. POWER - what this sample can and cannot detect")
    say("  For a rule held continuously, t = SR_annual * sqrt(years).")
    say("  That identity is all the power analysis a time-series study")
    say("  needs, and it does not depend on the holding period: cutting")
    say("  the sample into shorter trades raises the trade count without")
    say("  adding one second of independent information.")
    say()
    say("   span            years   min detectable SR at t=2.0")
    for lab, yy in (("full study", tot_y),
                    ("one decade", 10.0),
                    ("drop-best-decade", tot_y - 10.0),
                    ("XSP DEV window", 0.766)):
        say("   %-16s %5.1f   %.2f" % (lab, yy, 2.0 / math.sqrt(yy)))
    say()
    say("  Read that last row against what the minute studies were asked")
    say("  to do. Nine months can only resolve a Sharpe above 2.3; no")
    say("  honest intraday edge is that large, so H1 and H2 were being")
    say("  asked a question their sample could not answer either way.")
    say("  Their DEAD verdicts stand - a gross t of 0.29 is nowhere near")
    say("  any bar - but the horizon, not the hypothesis, was the flaw.")
    say()
    say("  Conversely: a %.0f-year span resolves SR=%.2f at t=2.0."
        % (tot_y, 2.0 / math.sqrt(tot_y)))
    say("  The literature's prior for single-commodity time-series momentum")
    say("  is SR ~ 0.2-0.4, which straddles that line. This study is")
    say("  powered to the edge of the effect it seeks and NOT beyond it.")
    say("  That is a reason to fix the gates now, and a reason NOT to")
    say("  treat a marginal t as a discovery.")

    # ---------------------------------------------------------------- 8
    say()
    say("8. BLOCK COUNTS (for the block-bootstrap control)")
    for k in (20, 60, 120):
        say("   %3d-day non-overlapping blocks in the study set: %d"
            % (k, len(rets) // k))

    say()
    say("XTM_RECON n=%d span=%.1fy ann_vol=%.2f%% VERDICT=DATA_READY"
        % (len(px), tot_y, 100 * ann))
    return 0


if __name__ == "__main__":
    sys.exit(main())
