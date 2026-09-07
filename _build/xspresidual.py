#!/usr/bin/env python
"""xspresidual.py - XauStructurePro Research: the barrier-free DEV falsification
test for H1 (dollar-residual reversion) and H2 (scheduled-liquidity reversion).

Pre-registered in CHANGELOG.md under 'XSP 0.2'. Every constant in PARAMS below
is transcribed from that entry and printed at the top of every report so the
two can be compared line by line. Nothing here searches for a threshold.

Input: the two minute files written by MQL5/Scripts/XauStructurePro/
XSPExportMinutes.mq5 into the terminal's Common\\Files\\XauStructurePro folder.
Deploy and verify them with _build\\exportminutes.ps1 first.

    python _build\\xspresidual.py               # the study
    python _build\\xspresidual.py --selftest    # engine validation, no real data
    python _build\\xspresidual.py --perms 200   # permutation count (default 200)

Stdlib only: this machine has no numpy and no tzdata for zoneinfo, so the
rolling statistics are incremental by hand and the DST rules are coded below
from their statutory definitions and printed for audit.

NO TRADING CODE. This file reads CSV and prints numbers.
"""

import argparse
import csv
import math
import os
import random
import re
import sys
import time
from array import array
from datetime import datetime, timedelta, timezone


# --------------------------------------------------------------------------
# PARAMS - transcribed from CHANGELOG 'XSP 0.2'. Not tunable, not swept.
# --------------------------------------------------------------------------
PARAMS = {
    "schema": "xsp-minute-v1",
    "dev_from": "2025.05.27 00:00",
    "dev_to": "2026.03.01 00:00",   # EXCLUSIVE; VAL is 2026.03.01+ and sealed
    "W_BETA": 480, "MIN_BETA": 400,
    "W_SIG": 480, "MIN_SIG": 400,
    "L": 15, "H": 30, "Z_CRIT": 2.0,
    "STRESS": 1.5, "COMMISSION_PTS": 7.0,
    "GAP_BREAK_MIN": 5,             # gap > 5 clock minutes breaks the series
    "SPAN_SLACK_MIN": 5,            # an L- or H-window may span L+5 / H+5 min
    "MIN_N": 200,                   # gate 3
    "T_CRIT": 2.0,                  # gate 2
    "DECOMP_FRAC": 1.0,             # gate 4: beta=0 arm must stay BELOW 1.0x
    "MECH_FRAC": 0.5,               # gate 5: shuffled control must stay < 0.5x
    "PERMS": 200,
    "H2_T_CRIT": 2.58,              # Bonferroni over 5 anchors
    "H2_MIN_N": 150,
    "H2_PRE_MIN": 15, "H2_POST_MIN": 30,
    "GRID_L": (5, 15, 30, 60),
    "GRID_H": (5, 15, 30, 60),
    "GRID_Z": (1.5, 2.0, 2.5),
    "NULL_R": (0.5, 0.75, 1.0, 1.5, 2.0, 3.0),
    "NULL_CAPS_S": (300, 900, 1800, 3600),
    "VR_H": (1, 2, 5, 15, 30, 60, 120, 240, 480),
    "SEED": 20260905,
}

PHASE_A = {"xau_ticks": 60541601, "xau_minutes": 268353,
           "atr14_m15_p10": 295.1, "atr14_m15_med": 590.5, "atr14_m15_p90": 1303.5,
           "spread_med_pts": 17.0}

BP = 1.0e4          # log returns are carried in basis points: scale-free, and
                    # it keeps products O(1) instead of O(1e-8)
VAL_GUARD = "2026.03.01"

# --------------------------------------------------------------------------
# Small statistics helpers. Written out rather than imported so the exact
# convention is visible: sample sd with n-1, and a t built from it.
# --------------------------------------------------------------------------


def mean_sd(xs):
    n = len(xs)
    if n == 0:
        return (0.0, 0.0, 0)
    m = math.fsum(xs) / n
    if n < 2:
        return (m, 0.0, n)
    v = math.fsum((x - m) * (x - m) for x in xs) / (n - 1)
    return (m, math.sqrt(v) if v > 0.0 else 0.0, n)


def tstat(xs):
    m, s, n = mean_sd(xs)
    if n < 2 or s <= 0.0:
        return (m, s, n, 0.0)
    return (m, s, n, m / (s / math.sqrt(n)))


def quantile(sorted_xs, p):
    """Nearest-rank, no interpolation - the value returned is one that was
    actually observed. Same convention as the MQL5 exporter."""
    n = len(sorted_xs)
    if n == 0:
        return float("nan")
    i = int(math.floor(p * (n - 1) + 0.5))
    return sorted_xs[max(0, min(n - 1, i))]


def qsummary(xs):
    if not xs:
        return "n=0"
    s = sorted(xs)
    return "n=%d p10=%.4g med=%.4g p90=%.4g mean=%.4g" % (
        len(s), quantile(s, 0.10), quantile(s, 0.50), quantile(s, 0.90),
        math.fsum(s) / len(s))


def spearman(xs, ys):
    """Rank correlation with average ranks for ties. Used only for descriptive
    lines; nothing gates on it."""
    n = len(xs)
    if n < 3:
        return (0.0, 0.0)
    def ranks(v):
        order = sorted(range(n), key=lambda i: v[i])
        r = [0.0] * n
        i = 0
        while i < n:
            j = i
            while j + 1 < n and v[order[j + 1]] == v[order[i]]:
                j += 1
            avg = (i + j) / 2.0 + 1.0
            for k in range(i, j + 1):
                r[order[k]] = avg
            i = j + 1
        return r
    rx, ry = ranks(xs), ranks(ys)
    mx = math.fsum(rx) / n
    my = math.fsum(ry) / n
    sxy = math.fsum((rx[i] - mx) * (ry[i] - my) for i in range(n))
    sxx = math.fsum((rx[i] - mx) ** 2 for i in range(n))
    syy = math.fsum((ry[i] - my) ** 2 for i in range(n))
    if sxx <= 0 or syy <= 0:
        return (0.0, 0.0)
    rho = sxy / math.sqrt(sxx * syy)
    return (rho, rho * math.sqrt(max(n - 1, 1)))


# --------------------------------------------------------------------------
# The clock. zoneinfo has no tz database on this machine, so the two DST rules
# H2 needs are coded from their statutory definitions and the transition dates
# they produce are printed in the report for audit.
#
#   United States : DST from the 2nd Sunday of March 02:00 local standard
#                   (07:00 UTC) to the 1st Sunday of November 02:00 local
#                   daylight (06:00 UTC). EST = UTC-5, EDT = UTC-4.
#   European Union: DST from the last Sunday of March 01:00 UTC to the last
#                   Sunday of October 01:00 UTC. GMT/BST = UTC+0/+1 in London,
#                   EET/EEST = UTC+2/+3 on an EET broker clock.
#
# The broker's own offset is NOT assumed from that: it is fitted from the data
# in derive_server_offsets() and only then compared with the EU rule.
# --------------------------------------------------------------------------
EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


def to_epoch(dt_utc):
    return int((dt_utc - EPOCH).total_seconds())


def utc_dt(epoch):
    return EPOCH + timedelta(seconds=int(epoch))


def nth_sunday(year, month, n):
    d = datetime(year, month, 1, tzinfo=timezone.utc)
    while d.weekday() != 6:
        d += timedelta(days=1)
    return d + timedelta(days=7 * (n - 1))


def last_sunday(year, month):
    """Walks to the last day of the month, then BACK to Sunday. Forward from
    the 28th overshoots: October 2025's 28th is a Tuesday, so the next Sunday
    is November 2nd while the last Sunday of October is the 26th - a one-week
    error in the EU DST date, which would move every H2 anchor by an hour for
    that week."""
    d = datetime(year, month, 28, tzinfo=timezone.utc)
    while (d + timedelta(days=1)).month == month:
        d += timedelta(days=1)
    while d.weekday() != 6:
        d -= timedelta(days=1)
    return d


def us_dst_bounds(year):
    s = nth_sunday(year, 3, 2) + timedelta(hours=7)
    e = nth_sunday(year, 11, 1) + timedelta(hours=6)
    return (to_epoch(s), to_epoch(e))


def eu_dst_bounds(year):
    s = last_sunday(year, 3) + timedelta(hours=1)
    e = last_sunday(year, 10) + timedelta(hours=1)
    return (to_epoch(s), to_epoch(e))


def ny_offset(utc_epoch):
    a, b = us_dst_bounds(utc_dt(utc_epoch).year)
    return -4 if a <= utc_epoch < b else -5


def london_offset(utc_epoch):
    a, b = eu_dst_bounds(utc_dt(utc_epoch).year)
    return 1 if a <= utc_epoch < b else 0


def eu_offset(utc_epoch):
    a, b = eu_dst_bounds(utc_dt(utc_epoch).year)
    return 3 if a <= utc_epoch < b else 2


CSV_HEADER = "epoch,o,h,l,c,ticks,spread_med_pts,spread_p90_pts,spread_n"


class Minutes(object):
    """One symbol's exported minute stream, columns held in typed arrays.

    Typed arrays rather than lists of tuples: 270k minutes x 9 fields as Python
    objects is ~500 MB of pointer soup, and the same data in array('d') is 20.
    """

    __slots__ = ("path", "sym", "digits", "point", "ts", "o", "hi", "lo", "cl",
                 "tk", "sm", "sp", "sn", "idx", "prov", "refused_val",
                 "refused_early", "bad", "declared_rows", "hdr_ok", "nonmono")

    def __init__(self, path):
        self.path = path
        self.sym = "?"
        self.digits = -1
        self.point = 0.0
        self.ts = array("q")
        self.o = array("d")
        self.hi = array("d")
        self.lo = array("d")
        self.cl = array("d")
        self.tk = array("q")
        self.sm = array("d")
        self.sp = array("d")
        self.sn = array("q")
        self.idx = {}
        self.prov = {}
        self.refused_val = 0
        self.refused_early = 0
        self.bad = 0
        self.declared_rows = -1
        self.hdr_ok = False
        self.nonmono = 0

    def __len__(self):
        return len(self.ts)


def load_minutes(path, ep_from, ep_to):
    """Reads one export file. Any row dated ep_to or later is REFUSED, counted
    and never touched again - VAL is sealed and that is enforced here as well as
    in the exporter, because two independent refusals is the point of a seal."""
    m = Minutes(path)
    prev = -1
    with open(path, "r", encoding="ascii", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\r\n")
            if not line:
                continue
            if line[0] == "#":
                #--- 'source' is captured and printed for one reason: the
                #--- selftest writes files in this exact schema whose source
                #--- field says NOT MARKET DATA. Without carrying that field
                #--- into the report, a run pointed at synthetic input would
                #--- produce a page that is structurally indistinguishable
                #--- from a real one. Non-greedy to the ';' or line end.
                for key, pat in (("schema", r"schema=([^;\s]+)"),
                                 ("symbol", r"symbol=([^;\s]+)"),
                                 ("digits", r"digits=(\d+)"),
                                 ("point", r"point=([0-9.]+)"),
                                 ("price", r"price=([^;\s]+)"),
                                 ("source", r"source=(.+?)\s*$")):
                    mt = re.search(pat, line)
                    if mt and key not in m.prov:
                        m.prov[key] = mt.group(1)
                mt = re.search(r"xsp_export_totals:.*?rows=(\d+)", line)
                if mt:
                    m.declared_rows = int(mt.group(1))
                if "xsp_export_totals:" in line:
                    m.prov["totals"] = line[2:]
                continue
            if line.startswith("epoch,"):
                m.hdr_ok = (line == CSV_HEADER)
                continue
            f = line.split(",")
            if len(f) != 9:
                m.bad += 1
                continue
            try:
                e = int(f[0])
                vals = (float(f[1]), float(f[2]), float(f[3]), float(f[4]),
                        int(f[5]), float(f[6]), float(f[7]), int(f[8]))
            except ValueError:
                m.bad += 1
                continue
            if e >= ep_to:
                m.refused_val += 1
                continue
            if e < ep_from:
                m.refused_early += 1
                continue
            if e <= prev:
                m.nonmono += 1
                continue
            prev = e
            m.idx[e] = len(m.ts)
            m.ts.append(e)
            m.o.append(vals[0]); m.hi.append(vals[1]); m.lo.append(vals[2])
            m.cl.append(vals[3]); m.tk.append(vals[4]); m.sm.append(vals[5])
            m.sp.append(vals[6]); m.sn.append(vals[7])
    m.sym = m.prov.get("symbol", "?")
    m.digits = int(m.prov.get("digits", -1))
    m.point = float(m.prov.get("point", 0.0))
    return m


class Series(object):
    """A flat stream of VALID minutes with a new-segment flag per element.

    Flat rather than a list of segments because the permutation control has to
    rebuild the stream 200 times: resetting rolling state on a flag costs one
    branch per minute, while re-splitting arrays costs an allocation per pass.
    `nsp` is the inclusive prefix sum of `ns`, which turns "does the window from
    i to j cross a break?" into one subtraction.
    """

    __slots__ = ("ts", "cl", "hi", "lo", "g", "e", "sm", "ns", "nsp", "sst",
                 "acct")

    def __init__(self):
        self.ts = array("q")
        self.cl = array("d")
        self.hi = array("d")
        self.lo = array("d")
        self.g = array("d")
        self.e = array("d")
        self.sm = array("d")
        self.ns = array("b")
        self.nsp = array("i")
        self.sst = array("i")
        self.acct = {}

    def __len__(self):
        return len(self.ts)

    def seal(self):
        run = 0
        start = 0
        self.nsp = array("i")
        self.sst = array("i")
        for i, v in enumerate(self.ns):
            run += v
            if v:
                start = i
            self.nsp.append(run)
            self.sst.append(start)
        return self

    def breaks_between(self, i, j):
        """Number of segment restarts in (i, j]."""
        return self.nsp[j] - self.nsp[i]


def build_series(xau, eur=None, gap_break_s=300):
    """Applies the pre-registered validity rule.

    Minute t is VALID iff both symbols recorded a tick in t and in t-1. The
    "gap from the previous valid minute is at most 5 clock minutes" clause is
    implemented as a SEGMENT BREAK, not as an exclusion: read literally it
    would invalidate the first minute after every weekend, and then the next,
    and nothing would ever be valid again. So a gap over 5 minutes starts a new
    segment - no return, beta window, L window or forward horizon ever spans
    one. This is the one place the pre-registration's wording needed an
    interpretation, and this is it, stated rather than buried.
    """
    s = Series()
    acct = {"xau_minutes": len(xau), "no_prev_xau": 0, "no_eur": 0,
            "no_prev_eur": 0, "bad_price": 0, "segments": 0, "valid": 0}
    xidx = xau.idx
    eidx = eur.idx if eur is not None else None
    prev_valid = None
    log = math.log
    for i in range(len(xau)):
        t = xau.ts[i]
        jp = xidx.get(t - 60)
        if jp is None:
            acct["no_prev_xau"] += 1
            continue
        if eidx is not None:
            k = eidx.get(t)
            if k is None:
                acct["no_eur"] += 1
                continue
            kp = eidx.get(t - 60)
            if kp is None:
                acct["no_prev_eur"] += 1
                continue
        c_t = xau.cl[i]
        c_p = xau.cl[jp]
        if c_t <= 0.0 or c_p <= 0.0:
            acct["bad_price"] += 1
            continue
        gv = log(c_t / c_p) * BP
        if eidx is not None:
            ec = eur.cl[k]
            ep = eur.cl[kp]
            if ec <= 0.0 or ep <= 0.0:
                acct["bad_price"] += 1
                continue
            ev = log(ec / ep) * BP
        else:
            ev = 0.0
        nw = 1 if (prev_valid is None or (t - prev_valid) > gap_break_s) else 0
        if nw:
            acct["segments"] += 1
        s.ts.append(t); s.cl.append(c_t); s.hi.append(xau.hi[i])
        s.lo.append(xau.lo[i]); s.g.append(gv); s.e.append(ev)
        s.sm.append(xau.sm[i]); s.ns.append(nw)
        prev_valid = t
    acct["valid"] = len(s.ts)
    s.acct = acct
    return s.seal()


RECOMPUTE_EVERY = 4096   # exact re-sum of the sigma window, drift bound


def run_cell(s, L, H, Z, use_beta=True, point=0.01, collect=False,
             stress=None, params=PARAMS, probe=None):
    """One cell of the pre-registered design, single pass, O(1) per minute.

    Windows, and what each one is allowed to see:
      beta   : the W_BETA valid minutes ending at i-1   (strictly past)
      eps    : the L valid minutes ending at i          (includes i, by design -
                                                         the dislocation IS the
                                                         current window)
      sigma  : the W_SIG eps values ending at i-1       (strictly past)
    Nothing reads a price later than i except the outcome at i+H, which is the
    thing being measured.
    """
    ts, cl, g, e, sm, ns = s.ts, s.cl, s.g, s.e, s.sm, s.ns
    n = len(ts)
    wb = params["W_BETA"]; mb = params["MIN_BETA"]
    wsg = params["W_SIG"]; msg = params["MIN_SIG"]
    stress = params["STRESS"] if stress is None else stress
    comm = params["COMMISSION_PTS"]
    slack = params["SPAN_SLACK_MIN"] * 60
    lspan = L * 60 + slack
    hspan = H * 60 + slack
    sqrt = math.sqrt
    fsum = math.fsum

    c = {"triggers": 0, "suppressed": 0, "skip_L": 0, "skip_span": 0,
         "skip_beta": 0, "skip_sigma": 0, "skip_horizon": 0, "skip_var": 0,
         "eps_computed": 0, "recomputes": 0, "resums": 0}
    nets = []
    raws = []
    rows = [] if collect else None
    probes = []
    drift = 0.0

    Sxy = Sxx = 0.0; nb = 0
    GL = EL = 0.0; nl = 0
    eh = []; head = 0; s1 = s2 = 0.0; pushes = 0
    next_allowed = -1
    beta = 0.0

    for i in range(n):
        if ns[i]:
            Sxy = Sxx = 0.0; nb = 0
            GL = EL = 0.0; nl = 0
            eh = []; head = 0; s1 = s2 = 0.0
            next_allowed = -1
        gi = g[i]; ei = e[i]
        GL += gi; EL += ei; nl += 1
        if nl > L:
            j = i - L
            GL -= g[j]; EL -= e[j]; nl = L
        #--- Periodic exact re-summation of the sliding sums, the same
        #--- treatment the sigma window below already gets, and for the same
        #--- reason. A sliding sum's error is a random walk in the ulp of its
        #--- intermediates: over a 90,000-minute segment - and DEV has them -
        #--- that reaches ~3e-13 bp and never comes back, because nothing in
        #--- an add-new/drop-old accumulator ever re-derives the truth. Pinned
        #--- to the exact value every RECOMPUTE_EVERY minutes, the error can
        #--- never represent more than that many updates, so a given minute
        #--- yields the same numbers whether it sits 100 or 90,000 minutes
        #--- into its segment. That is reproducibility, not cosmetics, and it
        #--- is what the drift figure in the report now measures.
        #---
        #--- Cadence is on i, not on a per-segment counter: the same indices
        #--- are re-summed on every arm, every permutation and every grid cell,
        #--- so no two runs can differ in where the pinning happened. The
        #--- probe stride (4001) is deliberately not a divisor of it, so the
        #--- independent check lands at varying distances from the last pin
        #--- rather than always reading a freshly exact accumulator.
        if i % RECOMPUTE_EVERY == 0 and nl > 0:
            lo_ = i - nl + 1
            gw = g[lo_:i + 1]; ew = e[lo_:i + 1]
            xg = fsum(gw); xe = fsum(ew)
            drift = max(drift,
                        abs(xg - GL) / max(fsum(abs(v) for v in gw), 1.0),
                        abs(xe - EL) / max(fsum(abs(v) for v in ew), 1.0))
            GL = xg; EL = xe
            c["resums"] += 1
        if probe is not None and i in probe:
            probes.append((i, nl, GL, EL, nb, Sxy, Sxx))

        ok = nl >= L
        if not ok:
            c["skip_L"] += 1
        elif ts[i] - ts[i - L + 1] > lspan:
            c["skip_span"] += 1
            ok = False
        if ok:
            # The warm-up requirement is applied in BOTH arms. The beta=0 arm
            # does not need a beta, but letting it start 400 minutes earlier in
            # every segment would hand gate 4 a different sample, and gate 4 is
            # a comparison.
            if nb < mb:
                c["skip_beta"] += 1
                ok = False
            elif use_beta:
                if Sxx <= 0.0:
                    c["skip_beta"] += 1
                    ok = False
                else:
                    beta = Sxy / Sxx
            else:
                beta = 0.0
        if ok:
            eps = GL - beta * EL
            c["eps_computed"] += 1
            cnt = len(eh) - head
            if cnt < msg:
                c["skip_sigma"] += 1
            else:
                var = (s2 - s1 * s1 / cnt) / (cnt - 1)
                if var <= 0.0:
                    c["skip_var"] += 1
                else:
                    z = eps / sqrt(var)
                    if z >= Z or z <= -Z:
                        c["triggers"] += 1
                        if i < next_allowed:
                            c["suppressed"] += 1
                        else:
                            j = i + H
                            if (j < n and s.nsp[j] == s.nsp[i]
                                    and ts[j] - ts[i] <= hspan):
                                d = -1.0 if z > 0.0 else 1.0
                                raw = d * (cl[j] - cl[i]) / point
                                cost = stress * sm[i] + comm
                                nets.append(raw - cost)
                                raws.append(raw)
                                if collect:
                                    rows.append((ts[i], ts[j], z, eps,
                                                 sqrt(var), beta, d, raw,
                                                 cost, raw - cost))
                                next_allowed = i + H
                            else:
                                c["skip_horizon"] += 1
            # eps enters the scale history whether or not it triggered
            eh.append(eps)
            s1 += eps; s2 += eps * eps
            pushes += 1
            if len(eh) - head > wsg:
                y = eh[head]; head += 1
                s1 -= y; s2 -= y * y
            if pushes % RECOMPUTE_EVERY == 0:
                win = eh[head:]
                x1 = fsum(win); x2 = fsum(v * v for v in win)
                #--- s1 is tracked on the sum-of-absolutes scale for the same
                #--- reason as GL and EL: it is a signed sum of eps and may
                #--- cancel to nothing, so its own value is not a scale. s2 is
                #--- a sum of squares and cannot cancel, so its value is.
                drift = max(drift, abs(x2 - s2) / max(abs(x2), 1.0),
                            abs(x1 - s1) / max(fsum(abs(v) for v in win), 1.0))
                s1, s2 = x1, x2
                c["recomputes"] += 1
                if head > wsg * 4:
                    eh = eh[head:]; head = 0

        Sxy += gi * ei; Sxx += ei * ei; nb += 1
        if nb > wb:
            j = i - wb
            Sxy -= g[j] * e[j]; Sxx -= e[j] * e[j]; nb = wb
        #--- The beta window, pinned on the same cadence. Placed after the
        #--- update, where the window is exactly [i-nb+1, i]; the probe for
        #--- this minute was taken before it, so what the independent check
        #--- verifies is still the state as the minute was JUDGED, not the
        #--- state after it was tidied.
        if i % RECOMPUTE_EVERY == 0 and nb > 0:
            blo_ = i - nb + 1
            xy = fsum(g[k] * e[k] for k in range(blo_, i + 1))
            xx = fsum(e[k] * e[k] for k in range(blo_, i + 1))
            drift = max(drift,
                        abs(xy - Sxy) / max(fsum(abs(g[k] * e[k])
                                                 for k in range(blo_, i + 1)),
                                            1.0),
                        abs(xx - Sxx) / max(xx, 1.0))
            Sxy = xy; Sxx = xx
            c["resums"] += 1

    m, sd, nn, t = tstat(nets)
    gm, gsd, _, gt = tstat(raws)
    return {"L": L, "H": H, "Z": Z, "use_beta": use_beta, "stress": stress,
            "n": nn, "mean": m, "sd": sd, "t": t,
            "gross_mean": gm, "gross_t": gt,
            "wins": sum(1 for v in nets if v > 0.0),
            "nets": nets, "rows": rows, "cnt": c, "drift": drift,
            "probes": probes}


def verify_windows(s, L, params, probes):
    """Independent check of the incremental sums and, more importantly, of the
    window BOUNDS. An off-by-one in either window would move a threshold by a
    whole minute of information and would not announce itself anywhere else.

    THE TOLERANCE IS SCALED TO sum|terms|, NOT TO |sum terms|, and that is the
    whole point of this docstring. `GL`, `EL` and `Sxy` are signed sums that
    legitimately pass through zero: if EURUSD ends a 15-minute window at the
    price it started, the exact sum of its returns is not "small", it is zero
    to the last bit. A relative test against such a result divides by noise.
    It happened on the real DEV data at 2025-07-16 23:41: exact EL was
    1.742e-13 bp over a window whose terms summed to 7.218 bp in absolute
    value - a summation condition number of 4e13 - and a 22-ulp accumulator
    drift of 3.464e-14 bp read as a 3.5% error against a denominator floored
    at 1e-12, which is seven orders of magnitude below the quantity's own
    scale. The engine was right and the check was wrong.

    sum|terms| is the correct scale: the forward error of a summation is
    bounded by n*eps*sum|x_k| regardless of how much the terms cancel. The
    1e-9 bar then sits about seven orders above achievable drift and seven
    orders below the smallest real defect this can suffer - dropping or
    double-counting one term, which moves the sum by an O(1) fraction of the
    same scale. Cancellation immunity costs a factor of ~7 in sensitivity and
    buys the difference between a test and a coin flip.
    """
    worst = 0.0
    nbad = 0
    checked = 0
    for (i, nl, GL, EL, nb, Sxy, Sxx) in probes:
        sst = s.sst[i]
        if nl != min(i - sst + 1, L):
            nbad += 1
        if nb != min(i - sst, params["W_BETA"]):
            nbad += 1
        lo = i - nl + 1
        if lo < sst:
            nbad += 1
            continue
        gw = s.g[lo:i + 1]
        ew = s.e[lo:i + 1]
        eGL = math.fsum(gw)
        eEL = math.fsum(ew)
        blo = i - nb
        eSxy = math.fsum(s.g[k] * s.e[k] for k in range(blo, i))
        eSxx = math.fsum(s.e[k] * s.e[k] for k in range(blo, i))
        #--- Each expectation carries the scale of its own summation. The 1.0
        #--- floor is the same one the sigma-drift metric uses: g and e are in
        #--- basis points and Sxx is bp-squared, so a scale under 1.0 means
        #--- there was nothing there to get wrong.
        sGL = math.fsum(abs(v) for v in gw)
        sEL = math.fsum(abs(v) for v in ew)
        sSxy = math.fsum(abs(s.g[k] * s.e[k]) for k in range(blo, i))
        for got, exp, scale in ((GL, eGL, sGL), (EL, eEL, sEL),
                                (Sxy, eSxy, sSxy), (Sxx, eSxx, eSxx)):
            rel = abs(got - exp) / max(scale, 1.0)
            worst = max(worst, rel)
            if rel > 1e-9:
                nbad += 1
            checked += 1
    return worst, nbad, checked


def perm_prep(base):
    """Precompute what every permutation needs: the day bucket of each minute
    and a map from epoch to that minute's EURUSD return."""
    day_of = array("i")
    donor = {}
    ts, e = base.ts, base.e
    for i in range(len(ts)):
        t = ts[i]
        day_of.append(t // 86400)
        donor[t] = e[i]
    days = sorted(set(day_of))
    return day_of, donor, days


def permuted_series(base, day_of, donor, days, rng):
    """EURUSD's whole days permuted; the XAUUSD side untouched.

    Destroys the contemporaneous XAU-EUR relationship while preserving both
    marginal distributions exactly - each EURUSD minute keeps its value and its
    time of day, only its DATE changes. A minute whose donor day has no minute
    at that time of day is dropped and counted: the control loses a few percent
    of the sample, which is reported rather than hidden, and it is why the
    control's n is compared with the residual arm's.
    """
    perm = list(days)
    rng.shuffle(perm)
    off = {}
    for a, b in zip(days, perm):
        off[a] = (b - a) * 86400
    s = Series()
    ts, cl, hi, lo = s.ts, s.cl, s.hi, s.lo
    g, e, sm, ns = s.g, s.e, s.sm, s.ns
    nsp, sst = s.nsp, s.sst
    bts, bcl, bhi, blo = base.ts, base.cl, base.hi, base.lo
    bg, bsm, bns = base.g, base.sm, base.ns
    get = donor.get
    prev = -(10 ** 12)
    run = 0
    start = 0
    k = 0
    miss = 0
    for i in range(len(bts)):
        t = bts[i]
        ev = get(t + off[day_of[i]])
        if ev is None:
            miss += 1
            continue
        nw = 1 if (bns[i] or (t - prev) > 300) else 0
        if nw:
            run += 1
            start = k
        ts.append(t); cl.append(bcl[i]); hi.append(bhi[i]); lo.append(blo[i])
        g.append(bg[i]); e.append(ev); sm.append(bsm[i]); ns.append(nw)
        nsp.append(run); sst.append(start)
        prev = t
        k += 1
    s.acct = {"valid": k, "donor_missing": miss, "segments": run}
    return s


def server_to_utc(e):
    """The broker clock is EET/EEST by the EU rule; derive_server_offset()
    checks that against the data before this is used for anything."""
    off = eu_offset(e - 2 * 3600)
    off = eu_offset(e - off * 3600)
    return e - off * 3600


def derive_server_offset(xau):
    """Fits the server's UTC offset from the weekly close, which market
    convention pins to 17:00 New York, and compares the fit with the EU rule.
    Nothing is assumed: if these disagree the report says so and H2's clock
    conversions are not trusted."""
    weeks = {}
    for t in xau.ts:
        wk = (t + 4 * 86400) // (7 * 86400)   # any stable weekly bucket
        if t > weeks.get(wk, -1):
            weeks[wk] = t
    fits = {}
    agree = 0
    disagree = 0
    nofit = 0
    for wk in sorted(weeks):
        e = weeks[wk]
        found = None
        for k in range(0, 15):
            utc = e - k * 3600
            loc = utc_dt(utc + ny_offset(utc) * 3600)
            if loc.weekday() == 4 and loc.hour == 16 and loc.minute >= 40:
                found = k
                break
        if found is None:
            nofit += 1
            continue
        fits[wk] = found
        rule = eu_offset(e - found * 3600)
        if rule == found:
            agree += 1
        else:
            disagree += 1
    return fits, agree, disagree, nofit


def rolling_sigma1(s, w=480, minn=400):
    """Sample sd of 1-minute log returns (bp) over the trailing w minutes
    ending at i-1. 0.0 means "not enough history" - never a fabricated value."""
    n = len(s.ts)
    g, ns = s.g, s.ns
    out = array("d")
    s1 = s2 = 0.0
    cnt = 0
    for i in range(n):
        if ns[i]:
            s1 = s2 = 0.0
            cnt = 0
        if cnt >= minn:
            var = (s2 - s1 * s1 / cnt) / (cnt - 1)
            out.append(math.sqrt(var) if var > 0.0 else 0.0)
        else:
            out.append(0.0)
        gi = g[i]
        s1 += gi
        s2 += gi * gi
        cnt += 1
        if cnt > w:
            j = i - w
            s1 -= g[j]
            s2 -= g[j] * g[j]
            cnt = w
    return out


def barrier_null(s, sig1, params, rng, per_day=40):
    """The empirical censored barrier null - the Phase A correction, measured.

    Random entries on the real minute paths, stop at S and target at R*S, every
    (R, cap) cell evaluated on the SAME entries so the columns are paired. S is
    a 1-sigma 15-minute move estimated from the trailing 480 minutes, so there
    is no absolute price constant here either.

    Two numbers per cell, and they answer different questions:
      p_hat  - target-first as a share of RESOLVED paths. This is the quantity
               1/(1+R) was standing in for, and the one to compare against it.
      E[R]   - expectancy in R units over ALL paths, timeouts marked to market
               at the cap. Immune to the censoring that made p_hat's textbook
               value wrong in the first place.
    Ambiguous minutes - both barriers breached inside one minute, order unknown
    from OHLC - are counted and charged as stops.
    """
    n = len(s.ts)
    ts, cl, hi, lo, nsp = s.ts, s.cl, s.hi, s.lo, s.nsp
    Rs = params["NULL_R"]
    caps = params["NULL_CAPS_S"]
    cap_max = max(caps)
    by_day = {}
    for i in range(n):
        if sig1[i] > 0.0:
            by_day.setdefault(ts[i] // 86400, []).append(i)
    entries = []
    for d in sorted(by_day):
        pool = by_day[d]
        rng.shuffle(pool)
        entries.extend(pool[:per_day])
    entries.sort()

    # acc[(dir, R, cap)] = [n, tgt, stp, amb, timeout, sum_R]
    acc = {}
    for dr in (1, -1):
        for R in Rs:
            for cp in caps:
                acc[(dr, R, cp)] = [0, 0, 0, 0, 0, 0.0]
    used = 0
    for i in entries:
        S = cl[i] * (sig1[i] / BP) * math.sqrt(15.0)
        if S <= 0.0:
            continue
        c0 = cl[i]
        base_nsp = nsp[i]
        t0 = ts[i]
        up = [c0 + R * S for R in Rs]
        dn = [c0 - R * S for R in Rs]
        stop_up = c0 + S      # short's stop
        stop_dn = c0 - S      # long's stop
        jt_l = [-1] * len(Rs)
        jt_s = [-1] * len(Rs)
        js_l = -1
        js_s = -1
        jlast = {cp: -1 for cp in caps}
        j = i + 1
        while j < n and nsp[j] == base_nsp:
            el = ts[j] - t0
            if el > cap_max:
                break
            for cp in caps:
                if el <= cp:
                    jlast[cp] = j
            h = hi[j]
            l = lo[j]
            if js_l < 0 and l <= stop_dn:
                js_l = j
            if js_s < 0 and h >= stop_up:
                js_s = j
            for k in range(len(Rs)):
                if jt_l[k] < 0 and h >= up[k]:
                    jt_l[k] = j
                if jt_s[k] < 0 and l <= dn[k]:
                    jt_s[k] = j
            j += 1
        used += 1
        for dr, jt, jstop in ((1, jt_l, js_l), (-1, jt_s, js_s)):
            for k, R in enumerate(Rs):
                for cp in caps:
                    a = acc[(dr, R, cp)]
                    a[0] += 1
                    tj = jt[k] if (jt[k] >= 0 and ts[jt[k]] - t0 <= cp) else -1
                    sj = jstop if (jstop >= 0 and ts[jstop] - t0 <= cp) else -1
                    if tj >= 0 and sj >= 0:
                        if tj < sj:
                            a[1] += 1; a[5] += R
                        elif sj < tj:
                            a[2] += 1; a[5] -= 1.0
                        else:
                            a[3] += 1; a[5] -= 1.0
                    elif tj >= 0:
                        a[1] += 1; a[5] += R
                    elif sj >= 0:
                        a[2] += 1; a[5] -= 1.0
                    else:
                        a[4] += 1
                        jl = jlast[cp]
                        if jl >= 0:
                            a[5] += dr * (cl[jl] - c0) / S
    return acc, used, len(entries)


def variance_ratio(s, hs, session_of=None):
    """VR(H) = Var(r_H) / (H * Var(r_1)) on NON-overlapping blocks.

    A block of H minutes counts only if the H clock minutes are all valid -
    ts[i+H]-ts[i] == H*60 with no segment break - so an "H-minute return" is
    never a return over a hole. That admissibility requirement selects for
    fully-covered stretches, which are the liquid ones; n is printed per H so
    the selection is visible rather than implied.
    """
    n = len(s.ts)
    ts, cl, nsp = s.ts, s.cl, s.nsp
    _, sd1, n1 = mean_sd(list(s.g))
    v1 = sd1 * sd1
    out = {}
    log = math.log
    for H in hs:
        blocks = []
        sess = {}
        i = 0
        need = H * 60
        rejected = 0
        while i + H < n:
            if nsp[i + H] == nsp[i] and ts[i + H] - ts[i] == need:
                r = log(cl[i + H] / cl[i]) * BP
                blocks.append(r)
                if session_of is not None:
                    sess.setdefault(session_of(ts[i]), []).append(r)
                i += H
            else:
                rejected += 1
                i += 1
        m, sd, nn = mean_sd(blocks)
        vr = (sd * sd) / (H * v1) if (v1 > 0 and H > 0) else float("nan")
        by = {}
        for k, v in sess.items():
            _, sk, nk = mean_sd(v)
            by[k] = (nk, (sk * sk) / (H * v1) if v1 > 0 else float("nan"))
        out[H] = {"n": nn, "vr": vr, "mean": m, "sd": sd,
                  "rejected": rejected, "by_session": by}
    return out, v1, n1


def m15_atr14(xau):
    """M15 bars aggregated from the exported minutes, then Wilder ATR(14) -
    the construction MQL5's iATR(sym, PERIOD_M15, 14) uses. Comparing its
    quantiles against Phase A's 295.1 / 590.5 / 1303.5 pts is an end-to-end
    check that this export is the same data the EA saw."""
    bars = {}
    for i in range(len(xau)):
        b = xau.ts[i] // 900
        r = bars.get(b)
        if r is None:
            bars[b] = [xau.hi[i], xau.lo[i], xau.cl[i], 1]
        else:
            if xau.hi[i] > r[0]:
                r[0] = xau.hi[i]
            if xau.lo[i] < r[1]:
                r[1] = xau.lo[i]
            r[2] = xau.cl[i]
            r[3] += 1
    atr = {}
    prev_c = None
    a = None
    trs = []
    for b in sorted(bars):
        h, l, c, _ = bars[b]
        tr = (h - l) if prev_c is None else (max(h, prev_c) - min(l, prev_c))
        prev_c = c
        if a is None:
            trs.append(tr)
            if len(trs) == 14:
                a = math.fsum(trs) / 14.0
        else:
            a = (a * 13.0 + tr) / 14.0
        if a is not None:
            atr[b] = a
    return bars, atr


def spread_by_hour(xau):
    by_srv = {}
    by_utc = {}
    for i in range(len(xau)):
        t = xau.ts[i]
        by_srv.setdefault((t // 3600) % 24, []).append(xau.sm[i])
        by_utc.setdefault((server_to_utc(t) // 3600) % 24, []).append(xau.sm[i])
    return by_srv, by_utc


def forward_dist(s, atr, horizons, point, params, step=1):
    """The cost-viability surface with no strategy in it: how big is the move
    over H minutes, in points and in ATR, and how often does it exceed the
    round-trip cost at all. `atr` is read from the last COMPLETED M15 bar."""
    n = len(s.ts)
    ts, cl, sm, nsp = s.ts, s.cl, s.sm, s.nsp
    stress = params["STRESS"]
    comm = params["COMMISSION_PTS"]
    out = {}
    for H in horizons:
        need = H * 60
        absfwd = []
        ratio = []
        pay = 0
        tot = 0
        signed = []
        for i in range(0, n - H, step):
            if nsp[i + H] != nsp[i] or ts[i + H] - ts[i] != need:
                continue
            fwd = (cl[i + H] - cl[i]) / point
            cost = stress * sm[i] + comm
            tot += 1
            if abs(fwd) > cost:
                pay += 1
            absfwd.append(abs(fwd))
            signed.append(fwd)
            a = atr.get(ts[i] // 900 - 1)
            if a and a > 0.0:
                ratio.append(abs(fwd) / (a / point))
        out[H] = {"n": tot, "pay": pay,
                  "frac_pay": (pay / tot if tot else float("nan")),
                  "abs": absfwd, "ratio": ratio, "signed": signed}
    return out


H2_ANCHORS = (("london_am_fix", "london", 10, 30),
              ("london_pm_fix", "london", 15, 0),
              ("comex_floor_open", "ny", 8, 20),
              ("comex_settlement", "ny", 13, 30),
              ("ny_1700_roll", "ny", 17, 0))


def local_to_utc(y, mo, d, hh, mi, zone):
    """Wall time in a zone -> UTC epoch, by finding the offset that is
    self-consistent. Anchors are mid-session, so there is no DST ambiguity."""
    naive = to_epoch(datetime(y, mo, d, hh, mi, tzinfo=timezone.utc))
    offfn = london_offset if zone == "london" else ny_offset
    for off in ((0, 1) if zone == "london" else (-5, -4)):
        u = naive - off * 3600
        if offfn(u) == off:
            return u
    return None


def h2_study(s, params, ep_from, ep_to, point):
    """Five named anchors, never scanned. Sign of the 15 minutes before,
    reversion over the 30 after, same cost model, one t per anchor."""
    sidx = {}
    for i in range(len(s.ts)):
        sidx[s.ts[i]] = i
    pre_n = params["H2_PRE_MIN"]
    post_n = params["H2_POST_MIN"]
    stress = params["STRESS"]
    comm = params["COMMISSION_PTS"]
    ts, cl, sm, nsp = s.ts, s.cl, s.sm, s.nsp
    n = len(ts)
    res = {}
    d0 = utc_dt(ep_from).date()
    d1 = utc_dt(ep_to).date()
    for name, zone, hh, mm in H2_ANCHORS:
        revs = []
        miss_minute = 0
        miss_pre = 0
        miss_post = 0
        flat = 0
        day = d0
        while day < d1:
            u = local_to_utc(day.year, day.month, day.day, hh, mm, zone)
            day = day + timedelta(days=1)
            if u is None:
                continue
            a = u + eu_offset(u) * 3600
            a -= a % 60
            i = None
            for k in range(0, 6):
                i = sidx.get(a + 60 * k)
                if i is not None:
                    break
            if i is None:
                miss_minute += 1
                continue
            if (i - pre_n < 0 or nsp[i] != nsp[i - pre_n]
                    or ts[i] - ts[i - pre_n] != pre_n * 60):
                miss_pre += 1
                continue
            if (i + post_n >= n or nsp[i + post_n] != nsp[i]
                    or ts[i + post_n] - ts[i] != post_n * 60):
                miss_post += 1
                continue
            pre = (cl[i] - cl[i - pre_n]) / point
            if pre == 0.0:
                flat += 1
                continue
            sgn = 1.0 if pre > 0.0 else -1.0
            fwd = (cl[i + post_n] - cl[i]) / point
            revs.append(-sgn * fwd - (stress * sm[i] + comm))
        m, sd, nn, t = tstat(revs)
        res[name] = {"n": nn, "mean": m, "sd": sd, "t": t,
                     "miss_minute": miss_minute, "miss_pre": miss_pre,
                     "miss_post": miss_post, "flat": flat}
    return res


SELFTEST_DIR = os.path.join("_build", "_xsp", "selftest")


def synth_minutes(days=45, seed=7, revert=0.0, beta_true=1.2,
                  eur_sd_bp=2.0, res_sd_bp=2.0, xau0=3300.0, eur0=1.08,
                  spread_pts=17.0, start=1748304000, mins_per_day=1380):
    """Synthetic XAU/EUR minute streams with a KNOWN structure, so the engine
    can be falsified before it is pointed at real data.

    Construction:  log(XAU_t) = k + beta_true*log(EUR_t) + r_t
                   r_t        = (1-revert)*r_{t-1} + noise
    so the no-intercept regression of 1-minute log returns recovers beta_true,
    and eps over L minutes telescopes to r_t - r_{t-L}. With revert>0 a positive
    eps is followed by a fall: exactly what the hypothesis claims, injected on
    purpose. With revert=0 the residual is a random walk and there is nothing
    to find, which is the case the gates must kill.

    Volatility is set near the real thing (about 3 bp per minute for XAU, from
    Phase A's ATR) so the selftest exercises the same order of magnitude - it is
    NOT a simulation of gold and no number out of it describes any market.
    """
    rng = random.Random(seed)
    x = Minutes("<synth-xau>")
    e = Minutes("<synth-eur>")
    x.prov = {"schema": "xsp-minute-v1", "symbol": "XAUUSD", "digits": "2",
              "point": "0.01", "price": "BID"}
    e.prov = {"schema": "xsp-minute-v1", "symbol": "EURUSD", "digits": "5",
              "point": "0.00001", "price": "BID"}
    x.sym, x.digits, x.point, x.hdr_ok = "XAUUSD", 2, 0.01, True
    e.sym, e.digits, e.point, e.hdr_ok = "EURUSD", 5, 0.00001, True
    lk = math.log(xau0) - beta_true * math.log(eur0)
    le = math.log(eur0)
    r = 0.0
    day0 = start // 86400
    for dd in range(days):
        d = day0 + dd
        if utc_dt(d * 86400).weekday() >= 5:
            continue
        for k in range(mins_per_day):
            t = d * 86400 + k * 60
            le += rng.gauss(0.0, eur_sd_bp) / BP
            r = (1.0 - revert) * r + rng.gauss(0.0, res_sd_bp) / BP
            px = math.exp(lk + beta_true * le + r)
            pe = math.exp(le)
            for m, p, pt in ((x, px, 0.01), (e, pe, 0.00001)):
                up = 1.0 + abs(rng.gauss(0.0, 1.0)) * 3.0e-5
                dn = 1.0 - abs(rng.gauss(0.0, 1.0)) * 3.0e-5
                m.idx[t] = len(m.ts)
                m.ts.append(t)
                m.o.append(round(p, m.digits)); m.hi.append(round(p * up, m.digits))
                m.lo.append(round(p * dn, m.digits)); m.cl.append(round(p, m.digits))
                m.tk.append(40); m.sm.append(spread_pts if pt == 0.01 else 8.0)
                m.sp.append((spread_pts if pt == 0.01 else 8.0) * 1.7)
                m.sn.append(40)
    x.declared_rows = len(x.ts)
    e.declared_rows = len(e.ts)
    return x, e


def write_minutes_csv(m, path):
    """Writes a Minutes object in the EXPORTER's format, byte-for-byte in the
    parts load_minutes() reads. The round trip is the only way to test the
    parser against the real schema without the real file."""
    with open(path, "w", encoding="ascii", newline="") as fh:
        fh.write("# xsp_export: schema=%s; symbol=%s; digits=%d; point=%.10f; "
                 "price=BID; from=synthetic; to=synthetic (exclusive); "
                 "source=xspresidual.py --selftest - NOT MARKET DATA\r\n"
                 % (m.prov["schema"], m.sym, m.digits, m.point))
        fh.write("# xsp_export_caveats: synthetic. No market produced these "
                 "numbers.\r\n")
        fh.write(CSV_HEADER + "\r\n")
        for i in range(len(m.ts)):
            fh.write("%d,%.*f,%.*f,%.*f,%.*f,%d,%.1f,%.1f,%d\r\n"
                     % (m.ts[i], m.digits, m.o[i], m.digits, m.hi[i],
                        m.digits, m.lo[i], m.digits, m.cl[i], m.tk[i],
                        m.sm[i], m.sp[i], m.sn[i]))
        fh.write("# xsp_export_totals: ticks=%d; minutes=%d; empty_days=0; "
                 "spread_samples_dropped=0; first=synthetic; last=synthetic; "
                 "rows=%d\r\n" % (sum(m.tk), len(m.ts), len(m.ts)))


def _st(name, ok, detail, state):
    state["n"] += 1
    if not ok:
        state["fail"] += 1
    print("  %-4s %-34s %s" % ("OK" if ok else "FAIL", name, detail))
    return ok


SELFTEST_SEEDS = (7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47)


def pool_cells(seeds, revert, params, days=45, use_beta=True):
    """Runs the primary cell on several independent synthetic universes and
    pools the trades.

    One 45-day universe yields under 200 observations, and at a per-trade sd of
    about 560 points that gives a standard error near 40 - so a single-universe
    null test passes or fails on a 2-sigma coin flip, which is not a test. This
    was found the hard way: the first null seed produced +94 points at t=2.2 and
    failed the check, and 60 further seeds put the pooled bias at +4.2 +/- 5.4.
    The answer to an underpowered test is more data, not a looser threshold.
    """
    raw = []
    net = []
    for sd in seeds:
        xn, en = synth_minutes(days=days, seed=sd, revert=revert)
        s = build_series(xn, en, params["GAP_BREAK_MIN"] * 60)
        r = run_cell(s, params["L"], params["H"], params["Z_CRIT"], use_beta,
                     0.01, collect=True, params=params)
        for row in r["rows"]:
            raw.append(row[7])
            net.append(row[9])
    gm, gsd, gn, gt = tstat(raw)
    nm, nsd, nn, nt = tstat(net)
    return {"n": nn, "gross_mean": gm, "gross_t": gt, "gross_sd": gsd,
            "mean": nm, "t": nt, "se": (nsd / math.sqrt(nn)) if nn else 0.0,
            "universes": len(seeds)}


def selftest(perms=3):
    """Falsifies the engine on data whose answer is known, before it is ever
    pointed at the market. A red line here invalidates every number the real
    run would print, so this runs first and its failure is fatal."""
    print("XSP_RESIDUAL SELFTEST")
    print("  Synthetic data. NOT a market measurement, NOT a backtest, and no")
    print("  number below describes gold, the dollar, or any tradable edge.")
    st = {"n": 0, "fail": 0}
    t0 = time.time()

    print("")
    print("1. EXPORT SCHEMA ROUND TRIP")
    os.makedirs(SELFTEST_DIR, exist_ok=True)
    xs, es = synth_minutes(days=45, seed=7, revert=0.02)
    px = os.path.join(SELFTEST_DIR, "xsp_minutes_XAUUSD.csv")
    pe = os.path.join(SELFTEST_DIR, "xsp_minutes_EURUSD.csv")
    write_minutes_csv(xs, px)
    write_minutes_csv(es, pe)
    ep_from = xs.ts[0]
    ep_to = xs.ts[-1] + 60
    rx = load_minutes(px, ep_from, ep_to)
    ry = load_minutes(pe, ep_from, ep_to)
    _st("header exact", rx.hdr_ok and ry.hdr_ok, CSV_HEADER, st)
    _st("rows round trip", len(rx) == len(xs) and rx.bad == 0,
        "wrote=%d read=%d bad=%d nonmono=%d" % (len(xs), len(rx), rx.bad,
                                                rx.nonmono), st)
    _st("provenance parsed", rx.sym == "XAUUSD" and rx.point == 0.01,
        "sym=%s point=%s digits=%d rows_declared=%d"
        % (rx.sym, rx.point, rx.digits, rx.declared_rows), st)
    _st("closes bit-identical", all(rx.cl[i] == xs.cl[i]
                                    for i in range(len(xs))),
        "%d values" % len(xs), st)
    cut = xs.ts[len(xs) // 2]
    rcut = load_minutes(px, ep_from, cut)
    _st("VAL seal refuses rows >= ep_to",
        len(rcut) > 0 and rcut.refused_val == len(xs) - len(rcut),
        "kept=%d refused=%d" % (len(rcut), rcut.refused_val), st)

    print("")
    print("2. VALIDITY RULE AND SEGMENTATION")
    s = build_series(rx, ry, PARAMS["GAP_BREAK_MIN"] * 60)
    a = s.acct
    nd = len(set(t // 86400 for t in xs.ts))
    _st("one segment per session", a["segments"] == nd,
        "segments=%d sessions=%d" % (a["segments"], nd), st)
    _st("first minute of each session dropped", a["no_prev_xau"] == nd,
        "no_prev_xau=%d" % a["no_prev_xau"], st)
    _st("valid count exact", len(s) == 1379 * nd,
        "valid=%d expected=%d" % (len(s), 1379 * nd), st)

    print("")
    print("3. WINDOWS, SIGNS AND NON-OVERLAP")
    L = PARAMS["L"]; H = PARAMS["H"]; Z = PARAMS["Z_CRIT"]
    probe = set(range(600, len(s), 1777))
    res = run_cell(s, L, H, Z, True, rx.point, collect=True, params=PARAMS,
                   probe=probe)
    worst, nbad, checked = verify_windows(s, L, PARAMS, res["probes"])
    _st("rolling sums and window bounds", nbad == 0 and worst < 1e-9,
        "worst_rel=%.2e values=%d probes=%d" % (worst, checked,
                                                len(res["probes"])), st)
    _st("sigma drift bounded", res["drift"] < 1e-9,
        "drift=%.2e sigma_resums=%d window_pins=%d"
        % (res["drift"], res["cnt"]["recomputes"], res["cnt"]["resums"]), st)
    betas = sorted(sxy / sxx for (_i, _nl, _gl, _el, _nb, sxy, sxx)
                   in res["probes"] if sxx > 0.0)
    bmed = quantile(betas, 0.5) if betas else float("nan")
    _st("beta recovered from returns", abs(bmed - 1.2) < 0.15,
        "median=%.4f injected=1.2000 samples=%d" % (bmed, len(betas)), st)
    ents = [r[0] for r in res["rows"]]
    gaps = [ents[k + 1] - ents[k] for k in range(len(ents) - 1)]
    _st("non-overlap enforced", (not gaps) or min(gaps) >= H * 60,
        "min gap=%ds required>=%ds triggers=%d suppressed=%d"
        % (min(gaps) if gaps else -1, H * 60, res["cnt"]["triggers"],
           res["cnt"]["suppressed"]), st)
    say_sig = pool_cells(SELFTEST_SEEDS, 0.02, PARAMS)
    _st("injected reversion detected (pooled)",
        say_sig["mean"] > 0.0 and say_sig["t"] > 4.0,
        "universes=%d n=%d net=%+.1f se=%.1f t=%.2f gross=%+.1f"
        % (say_sig["universes"], say_sig["n"], say_sig["mean"], say_sig["se"],
           say_sig["t"], say_sig["gross_mean"]), st)
    _st("single universe agrees in sign", res["mean"] > 0.0,
        "seed 7: n=%d net_mean=%+.1f t=%.2f gross_mean=%+.1f"
        % (res["n"], res["mean"], res["t"], res["gross_mean"]), st)

    print("")
    print("4. THE NULL CASE - what the gates must kill")
    print("     Pooled over %d independent universes: one is not enough to"
          % len(SELFTEST_SEEDS))
    print("     tell +90 points of luck from +90 points of bias.")
    nulp = pool_cells(SELFTEST_SEEDS, 0.0, PARAMS)
    _st("random-walk residual: gross ~ 0", abs(nulp["gross_t"]) < 3.0,
        "n=%d gross=%+.2f pts t=%+.2f (signal case gross was %+.1f)"
        % (nulp["n"], nulp["gross_mean"], nulp["gross_t"],
           say_sig["gross_mean"]), st)
    _st("random-walk residual: net < 0 after cost", nulp["mean"] < 0.0,
        "net=%+.2f +/- %.2f pts t=%+.2f  cost charged=%.1f"
        % (nulp["mean"], nulp["se"], nulp["t"],
           PARAMS["STRESS"] * 17.0 + PARAMS["COMMISSION_PTS"]), st)
    xn, en = synth_minutes(days=45, seed=11, revert=0.0)
    sn = build_series(xn, en, PARAMS["GAP_BREAK_MIN"] * 60)
    nul = run_cell(sn, L, H, Z, True, 0.01, params=PARAMS)
    _st("gate 1 kills the pooled null",
        h1_verdict({"mean": nulp["mean"], "t": nulp["t"], "n": nulp["n"]},
                   {"mean": 0.0}, 0.0, PARAMS)[0] == "DEAD",
        "one universe for contrast: seed 11 n=%d net=%+.1f t=%.2f"
        % (nul["n"], nul["mean"], nul["t"]), st)
    nob = run_cell(s, L, H, Z, False, 0.01, params=PARAMS)
    _st("gate-4 arms judge the same candidates",
        nob["cnt"]["eps_computed"] == res["cnt"]["eps_computed"],
        "beta=%d beta0=%d (means %.1f vs %.1f)"
        % (res["cnt"]["eps_computed"], nob["cnt"]["eps_computed"],
           res["mean"], nob["mean"]), st)

    print("")
    print("5. MECHANISM CONTROL (EURUSD days permuted)")
    rng = random.Random(PARAMS["SEED"])
    day_of, donor, days = perm_prep(s)
    pm = []
    lost = 0
    for _ in range(max(1, perms)):
        ps = permuted_series(s, day_of, donor, days, rng)
        lost = max(lost, ps.acct["donor_missing"])
        pm.append(run_cell(ps, L, H, Z, True, 0.01, params=PARAMS)["mean"])
    _st("control runs and keeps the sample",
        len(pm) == max(1, perms) and lost < 0.05 * len(s),
        "means=[%s] worst donor_missing=%d of %d"
        % (", ".join("%.1f" % v for v in pm), lost, len(s)), st)
    print("     INFO: on THIS synthetic data the control is expected to survive")
    print("     partly - the injected reversion lives in the residual, which")
    print("     leaks into XAU's own returns, so shuffling EURUSD cannot remove")
    print("     it. That is not a defect in the control; it is why gate 5 is a")
    print("     strict test of the DOLLAR framing rather than of reversion.")

    print("")
    print("6. THE GATES THEMSELVES")
    def mk(mean, t, n):
        return {"mean": mean, "t": t, "n": n}
    cases = ((mk(-0.5, 4.0, 900), mk(0.0, 0.0, 900), 0.0, "DEAD"),
             (mk(5.0, 1.5, 900), mk(0.0, 0.0, 900), 0.0, "DEAD"),
             (mk(5.0, 4.0, 100), mk(0.0, 0.0, 100), 0.0, "UNDERPOWERED"),
             (mk(5.0, 4.0, 900), mk(5.0, 4.0, 900), 0.0, "DECOMPOSITION FAIL"),
             (mk(5.0, 4.0, 900), mk(1.0, 1.0, 900), 2.5, "MECHANISM FAIL"),
             (mk(5.0, 4.0, 900), mk(1.0, 1.0, 900), 1.0, "SURVIVES"))
    for r_, nb_, ctrl, want in cases:
        got, _lines = h1_verdict(r_, nb_, ctrl, PARAMS)
        _st("gate -> " + want, got == want, "got " + got, st)

    print("")
    print("XSP_RESIDUAL_SELFTEST checks=%d failed=%d elapsed=%.1fs VERDICT=%s"
          % (st["n"], st["fail"], time.time() - t0,
             "PASS" if st["fail"] == 0 else "FAIL"))
    if st["fail"]:
        print("  The engine is wrong. Do not run it on the export.")
    return 0 if st["fail"] == 0 else 1


def h1_verdict(res, nob, ctrl_mean, params):
    """The five pre-registered gates, in the pre-registered order, as a pure
    function of the numbers.

    Pure on purpose: --selftest feeds it fabricated inputs and checks that each
    gate fires, so the machinery that reaches the conclusion is tested
    independently of the data that will feed it. No gate has a tunable in it
    that is not in PARAMS, and PARAMS is printed next to the CHANGELOG values.
    """
    mean = res["mean"]; t = res["t"]; n = res["n"]
    lines = []
    lines.append("gate 1  net mean > 0                 : mean=%+.2f pts" % mean)
    if mean <= 0.0:
        lines.append("        -> DEAD. The trade loses money after cost. No")
        lines.append("           further gate can revive that and none is run.")
        return "DEAD", lines
    lines.append("gate 2  t > %.2f with n >= %d        : t=%.2f n=%d"
                 % (params["T_CRIT"], params["MIN_N"], t, n))
    if t <= params["T_CRIT"] and n >= params["MIN_N"]:
        lines.append("        -> DEAD. Enough observations to see an effect of")
        lines.append("           this size, and it is not there.")
        return "DEAD", lines
    lines.append("gate 3  n >= %d                     : n=%d"
                 % (params["MIN_N"], n))
    if n < params["MIN_N"]:
        lines.append("        -> UNDERPOWERED. Not a pass and not a fail: the")
        lines.append("           design did not produce enough independent")
        lines.append("           observations to decide. Reporting it as a")
        lines.append("           result either way would be dishonest.")
        return "UNDERPOWERED", lines
    lines.append("gate 4  residual arm beats beta=0    : %+.2f vs %+.2f pts"
                 % (mean, nob["mean"]))
    if nob["mean"] >= params["DECOMP_FRAC"] * mean:
        lines.append("        -> DECOMPOSITION FAIL. Fading XAU's own move does")
        lines.append("           as well or better, so the EURUSD leg adds")
        lines.append("           nothing and the DOLLAR-residual claim is not")
        lines.append("           what is being measured.")
        return "DECOMPOSITION FAIL", lines
    lines.append("gate 5  control < %.0f%% of the arm    : %+.2f vs %+.2f pts"
                 % (100.0 * params["MECH_FRAC"], ctrl_mean, mean))
    if ctrl_mean >= params["MECH_FRAC"] * mean:
        lines.append("        -> MECHANISM FAIL. Shuffling EURUSD's days keeps")
        lines.append("           most of the effect, so the effect does not")
        lines.append("           come from the XAU-EUR relationship.")
        return "MECHANISM FAIL", lines
    lines.append("        -> SURVIVES all five. This is a DEV result on one")
    lines.append("           pre-registered cell; it is not a strategy, not a")
    lines.append("           backtest and not evidence of profitability.")
    return "SURVIVES", lines


class Tee(object):
    """Everything printed also goes to the report file, so what the operator
    reads on screen and what is archived cannot diverge."""

    __slots__ = ("buf",)

    def __init__(self):
        self.buf = []

    def __call__(self, line=""):
        print(line)
        self.buf.append(line)

    def save(self, path):
        with open(path, "w", encoding="ascii", errors="replace",
                  newline="") as fh:
            for ln in self.buf:
                fh.write(ln + "\r\n")


def default_common():
    ap = os.environ.get("APPDATA")
    if not ap:
        return os.path.join("_build", "_xsp")
    return os.path.join(ap, "MetaQuotes", "Terminal", "Common", "Files",
                        "XauStructurePro")


DEV_FROM = to_epoch(datetime(2025, 5, 27, tzinfo=timezone.utc))
DEV_TO = to_epoch(datetime(2026, 3, 1, tzinfo=timezone.utc))


def report(args):
    """The pre-registered run. Prints its own parameters first so they can be
    read against CHANGELOG 'XSP 0.2' without trusting this docstring."""
    say = Tee()
    stamp = time.strftime("%Y%m%d_%H%M%S")
    outdir = os.path.join("_build", "_xsp", "residual_" + stamp)
    os.makedirs(outdir, exist_ok=True)
    t_start = time.time()

    say("XSP_RESIDUAL " + stamp)
    say("XauStructurePro - H1 dollar-residual reversion, H2 scheduled")
    say("liquidity reversion. DEV ONLY. Pre-registered in CHANGELOG 'XSP 0.2'.")
    say("")
    say("WHAT THIS IS NOT: not a backtest, not an equity curve, not a strategy,")
    say("not order flow and not volume. It is a measurement on exported broker")
    say("bid quotes with one analytic round-trip cost. XAUUSD is an OTC CFD:")
    say("there is no consolidated tape, so 'ticks' below are THIS broker's")
    say("quote updates and nothing else.")
    say("")

    say("PARAMETERS AS THEY WILL BE USED (compare against the CHANGELOG)")
    for k in ("W_BETA", "MIN_BETA", "W_SIG", "MIN_SIG", "L", "H", "Z_CRIT",
              "STRESS", "COMMISSION_PTS", "GAP_BREAK_MIN", "SPAN_SLACK_MIN",
              "MIN_N", "T_CRIT", "DECOMP_FRAC", "MECH_FRAC", "PERMS",
              "H2_T_CRIT", "H2_MIN_N", "H2_PRE_MIN", "H2_POST_MIN", "SEED"):
        say("  %-16s %s" % (k, PARAMS[k]))
    say("  %-16s %s" % ("GRID_L", PARAMS["GRID_L"]))
    say("  %-16s %s" % ("GRID_H", PARAMS["GRID_H"]))
    say("  %-16s %s" % ("GRID_Z", PARAMS["GRID_Z"]))
    say("  %-16s %s" % ("DEV span", "%s .. %s (exclusive)"
                        % (utc_dt(DEV_FROM).strftime("%Y.%m.%d %H:%M"),
                           utc_dt(DEV_TO).strftime("%Y.%m.%d %H:%M"))))
    say("  %-16s %s" % ("perms this run", args.perms))
    if args.perms != PARAMS["PERMS"]:
        say("  DEVIATION: the pre-registration says %d permutation passes and"
            % PARAMS["PERMS"])
        say("  this run used %d. Gate 5's control mean is therefore noisier"
            % args.perms)
        say("  than pre-registered. Stated here so the report cannot be quoted")
        say("  as the pre-registered run when it is not.")
    say("")

    say("1. INPUT FILES")
    root = args.dir or default_common()
    paths = {}
    for sym in ("XAUUSD", "EURUSD"):
        paths[sym] = os.path.join(root, "xsp_minutes_" + sym + ".csv")
    for sym in ("XAUUSD", "EURUSD"):
        if not os.path.exists(paths[sym]):
            say("  MISSING " + paths[sym])
            say("")
            say("  Run:  powershell -File _build\\exportminutes.ps1")
            say("        attach XSPExportMinutes to any chart, wait for")
            say("        XSP_EXPORT symbols=2 of 2 VERDICT=PASS")
            say("        powershell -File _build\\exportminutes.ps1 -Verify")
            say("")
            say("XSP_RESIDUAL VERDICT=NO_DATA")
            say.save(os.path.join(outdir, "report.txt"))
            return 2
    mins = {}
    for sym in ("XAUUSD", "EURUSD"):
        p = paths[sym]
        m = load_minutes(p, DEV_FROM, DEV_TO)
        mins[sym] = m
        say("  %s" % p)
        say("    rows=%d declared=%d bad=%d nonmono=%d refused_VAL=%d "
            "refused_early=%d" % (len(m), m.declared_rows, m.bad, m.nonmono,
                                  m.refused_val, m.refused_early))
        say("    header_exact=%s schema=%s symbol=%s digits=%d point=%s "
            "price=%s" % (m.hdr_ok, m.prov.get("schema", "?"), m.sym,
                          m.digits, m.point, m.prov.get("price", "?")))
        say("    source=%s" % m.prov.get("source", "ABSENT"))
        if "totals" in m.prov:
            say("    " + m.prov["totals"][:160])
        else:
            say("    xsp_export_totals: ABSENT - this file was not written by "
                "XSPExportMinutes")
        if len(m):
            say("    span %s .. %s"
                % (utc_dt(m.ts[0]).strftime("%Y.%m.%d %H:%M"),
                   utc_dt(m.ts[-1]).strftime("%Y.%m.%d %H:%M")))
    say("")

    xau, eur = mins["XAUUSD"], mins["EURUSD"]
    fatal = []
    for m in (xau, eur):
        if not m.hdr_ok:
            fatal.append("%s header is not the pre-registered schema" % m.sym)
        if m.prov.get("schema") != "xsp-minute-v1":
            fatal.append("%s schema is %r" % (m.sym, m.prov.get("schema")))
        if m.prov.get("price") != "BID":
            fatal.append("%s price is %r, not BID" % (m.sym,
                                                      m.prov.get("price")))
        if m.point <= 0.0:
            fatal.append("%s point=%r" % (m.sym, m.point))
        if len(m) < 1000:
            fatal.append("%s has only %d rows" % (m.sym, len(m)))
        if m.bad or m.nonmono:
            fatal.append("%s bad=%d nonmono=%d" % (m.sym, m.bad, m.nonmono))
        if m.declared_rows >= 0 and m.declared_rows != len(m) + m.refused_val \
                + m.refused_early + m.bad + m.nonmono:
            fatal.append("%s row count does not reconcile with its own trailer"
                         % m.sym)
    if xau.refused_val or eur.refused_val:
        say("  NOTE: %d XAUUSD and %d EURUSD rows were dated 2026.03.01 or"
            % (xau.refused_val, eur.refused_val))
        say("  later and were refused here. VAL stays sealed, but the export")
        say("  should not have contained them - check the exporter's inputs.")
        say("")
    if fatal:
        for f in fatal:
            say("  FATAL " + f)
        say("")
        say("XSP_RESIDUAL VERDICT=BAD_INPUT")
        say.save(os.path.join(outdir, "report.txt"))
        return 2

    say("2. THE SAMPLE (pre-registered validity rule)")
    s = build_series(xau, eur, PARAMS["GAP_BREAK_MIN"] * 60)
    a = s.acct
    say("  XAUUSD minutes read          %d" % a["xau_minutes"])
    say("  dropped: no XAU minute at t-1 %d" % a["no_prev_xau"])
    say("  dropped: no EUR minute at t   %d" % a["no_eur"])
    say("  dropped: no EUR minute at t-1 %d" % a["no_prev_eur"])
    say("  dropped: non-positive price   %d" % a["bad_price"])
    say("  VALID minutes                 %d  in %d segments"
        % (a["valid"], a["segments"]))
    say("  (a segment break is a gap over %d clock minutes; no window, return"
        % PARAMS["GAP_BREAK_MIN"])
    say("   or horizon ever spans one)")
    if len(s) < 5000:
        say("")
        say("XSP_RESIDUAL VERDICT=NO_SAMPLE")
        say.save(os.path.join(outdir, "report.txt"))
        return 2
    say("")

    say("3. THE BROKER CLOCK (fitted, not assumed)")
    fits, agree, disagree, nofit = derive_server_offset(xau)
    say("  weekly closes fitted to 17:00 New York: agree_with_EU_rule=%d "
        "disagree=%d no_fit=%d" % (agree, disagree, nofit))
    offs = {}
    for wk in fits:
        offs[fits[wk]] = offs.get(fits[wk], 0) + 1
    say("  fitted UTC offsets: " + ", ".join("+%d h x%d weeks" % (k, offs[k])
                                             for k in sorted(offs)))
    y0 = utc_dt(DEV_FROM).year
    for y in (y0, y0 + 1):
        us = us_dst_bounds(y)
        eu = eu_dst_bounds(y)
        say("  %d DST: US %s -> %s   EU %s -> %s"
            % (y, utc_dt(us[0]).strftime("%m.%d %H:%MZ"),
               utc_dt(us[1]).strftime("%m.%d %H:%MZ"),
               utc_dt(eu[0]).strftime("%m.%d %H:%MZ"),
               utc_dt(eu[1]).strftime("%m.%d %H:%MZ")))
    clock_ok = (disagree == 0 and agree > 0)
    if not clock_ok:
        say("  WARNING: the fit and the EU rule disagree. H2's anchors are")
        say("  clock-defined, so its numbers below are NOT trusted and H2 is")
        say("  reported as INCONCLUSIVE regardless of its t.")
    say("")

    say("4. COST AND VOLATILITY (descriptive - nothing gates on this section)")
    say("  XAUUSD spread_med_pts    " + qsummary(list(xau.sm)))
    say("  XAUUSD spread_p90_pts    " + qsummary(list(xau.sp)))
    say("  EURUSD spread_med_pts    " + qsummary(list(eur.sm)))
    say("  round-trip cost charged  %.1f*spread_med + %.1f pts"
        % (PARAMS["STRESS"], PARAMS["COMMISSION_PTS"]))
    med_all = quantile(sorted(xau.sm), 0.5)
    say("  Phase A recorded spread_med=%.1f pts; this export's median of the"
        % PHASE_A["spread_med_pts"])
    say("  per-minute medians is %.1f pts (ratio %.3f)"
        % (med_all, med_all / PHASE_A["spread_med_pts"]))
    by_srv, by_utc = spread_by_hour(xau)
    say("  spread_med by server hour (median of the hour's minutes):")
    for base in (0, 8, 16):
        cells = []
        for h in range(base, base + 8):
            v = by_srv.get(h)
            cells.append("%02d:%s" % (h, ("%.0f" % quantile(sorted(v), 0.5))
                                      if v else "-"))
        say("    " + "  ".join(cells))
    bars, atr = m15_atr14(xau)
    av = sorted(v / xau.point for v in atr.values())
    say("  M15 ATR(14) from this export, in points: " + qsummary(av))
    say("  Phase A (the EA's own iATR, same span): p10=%.1f med=%.1f p90=%.1f"
        % (PHASE_A["atr14_m15_p10"], PHASE_A["atr14_m15_med"],
           PHASE_A["atr14_m15_p90"]))
    if av:
        say("  ratio of medians export/PhaseA = %.3f  (M15 bars=%d)"
            % (quantile(av, 0.5) / PHASE_A["atr14_m15_med"], len(bars)))
    say("")

    def session_of(server_epoch):
        h = (server_to_utc(server_epoch) // 3600) % 24
        if h >= 22 or h < 7:
            return "asia"
        if h < 12:
            return "london"
        if h < 16:
            return "overlap"
        if h < 21:
            return "newyork"
        return "late"

    say("5. IS THERE ANY MEAN REVERSION AT ALL? (variance ratio, no strategy)")
    vr, v1, n1 = variance_ratio(s, PARAMS["VR_H"], session_of)
    say("  1-minute log return sd = %.3f bp over n=%d minutes"
        % (math.sqrt(v1), n1))
    say("  VR(H) = Var(r_H) / (H * Var(r_1)) on NON-overlapping blocks.")
    say("  VR < 1 = mean reverting, 1 = random walk, > 1 = trending.")
    say("  %5s %8s %8s %10s" % ("H", "blocks", "VR", "rejected"))
    for H in PARAMS["VR_H"]:
        r = vr[H]
        say("  %5d %8d %8.4f %10d" % (H, r["n"], r["vr"], r["rejected"]))
    say("  VR(30) by session: " + ", ".join(
        "%s n=%d VR=%.3f" % (k, vr[30]["by_session"][k][0],
                             vr[30]["by_session"][k][1])
        for k in sorted(vr[30]["by_session"])))
    say("  A VR near 1 at every H would mean the whole H1 premise is absent")
    say("  from the unconditional series; H1 conditions on a residual, so it")
    say("  can still be true if this is 1.0. Printed because a VR far ABOVE 1")
    say("  would make a reversion story much less likely a priori.")
    say("")

    say("6. COULD ANY REVERSION PAY? (cost-viability surface, no strategy)")
    fd = forward_dist(s, atr, (5, 15, 30, 60, 120), xau.point, PARAMS)
    say("  P(|move over H| > round-trip cost), and the move's size in ATR:")
    say("  %5s %9s %9s %28s %22s"
        % ("H", "n", "P(pay)", "|move| pts", "|move|/ATR14(M15)"))
    for H in (5, 15, 30, 60, 120):
        d = fd[H]
        ab = sorted(d["abs"])
        rt = sorted(d["ratio"])
        say("  %5d %9d %8.3f   p50=%7.1f p90=%8.1f   p50=%5.3f p90=%5.3f"
            % (H, d["n"], d["frac_pay"], quantile(ab, 0.5), quantile(ab, 0.9),
               quantile(rt, 0.5), quantile(rt, 0.9)))
    say("  This is the ceiling on ANY %d-minute reversion trade: if the median"
        % PARAMS["H"])
    say("  move barely clears cost, only the tail can pay, and the tail is")
    say("  where the estimate is weakest. It gates nothing; it frames what a")
    say("  surviving mean would have to be made of.")
    say("")

    say("7. THE PRE-REGISTERED PRIMARY CELL - H1")
    L = PARAMS["L"]; H = PARAMS["H"]; Z = PARAMS["Z_CRIT"]
    say("  L=%d  H=%d  Z=%.2f  beta window=%d (min %d)  sigma window=%d (min %d)"
        % (L, H, Z, PARAMS["W_BETA"], PARAMS["MIN_BETA"], PARAMS["W_SIG"],
           PARAMS["MIN_SIG"]))
    say("  rule: eps = sum(dXAU) - beta*sum(dEUR) over the last %d valid" % L)
    say("        minutes, beta = no-intercept rolling slope on the %d minutes"
        % PARAMS["W_BETA"])
    say("        ending at t-1; z = eps / sd(eps history ending at t-1);")
    say("        |z| >= %.2f enters AGAINST eps and exits %d minutes later;"
        % (Z, H))
    say("        entries are thinned to non-overlapping windows; cost is")
    say("        charged once per round trip and never rebated.")
    probe = set(range(1000, len(s), 4001))
    tc = time.time()
    res = run_cell(s, L, H, Z, True, xau.point, collect=True, params=PARAMS,
                   probe=probe)
    say("  engine: %.1fs  worst accumulator drift=%.2e over %d sigma re-sums "
        "and %d window pins"
        % (time.time() - tc, res["drift"], res["cnt"]["recomputes"],
           res["cnt"]["resums"]))
    worst, nbad, checked = verify_windows(s, L, PARAMS, res["probes"])
    say("  independent window check: probes=%d values=%d worst_rel=%.2e bad=%d"
        % (len(res["probes"]), checked, worst, nbad))
    say("  (worst_rel is measured against each window's sum of ABSOLUTE terms,")
    say("  not against its signed total - a 15-minute return sum may cancel to")
    say("  1e-13 and a relative test against that divides by nothing.)")
    if nbad or worst > 1e-9 or res["drift"] > 1e-9:
        say("")
        say("  FATAL the incremental sums do not reproduce exact sums. Every")
        say("  number after this point would be unverified arithmetic.")
        say("XSP_RESIDUAL VERDICT=ENGINE_FAIL")
        say.save(os.path.join(outdir, "report.txt"))
        return 2
    c = res["cnt"]
    say("  sample accounting:")
    say("    minutes where eps was computable   %d" % c["eps_computed"])
    say("    skipped: L window short/holed      %d / %d"
        % (c["skip_L"], c["skip_span"]))
    say("    skipped: beta warm-up              %d" % c["skip_beta"])
    say("    skipped: sigma warm-up             %d" % c["skip_sigma"])
    say("    triggers                           %d" % c["triggers"])
    say("    dropped as overlapping             %d" % c["suppressed"])
    say("    dropped: horizon crossed a gap     %d" % c["skip_horizon"])
    say("    OBSERVATIONS n                     %d" % res["n"])
    nets = sorted(res["nets"])
    say("  net per trade, in XAUUSD points (0.01 each):")
    say("    mean=%+.2f  sd=%.2f  t=%.2f  median=%+.2f  p10=%+.1f  p90=%+.1f"
        % (res["mean"], res["sd"], res["t"], quantile(nets, 0.5),
           quantile(nets, 0.1), quantile(nets, 0.9)))
    say("    win rate=%.1f%%  sum=%+.0f pts  gross mean=%+.2f (t=%.2f)"
        % (100.0 * res["wins"] / max(res["n"], 1), math.fsum(nets),
           res["gross_mean"], res["gross_t"]))
    say("")

    say("8. GATE 4 CONTROL - the same rule with beta forced to zero")
    nob = run_cell(s, L, H, Z, False, xau.point, params=PARAMS)
    say("  beta=0 arm: n=%d mean=%+.2f t=%.2f  (candidates %d, same as the"
        % (nob["n"], nob["mean"], nob["t"], nob["cnt"]["eps_computed"]))
    say("  residual arm's %d - the warm-up is applied in both arms so this is"
        % c["eps_computed"])
    say("  a comparison of rules, not of samples)")
    say("")

    say("9. GATE 5 CONTROL - EURUSD's whole days permuted, %d times"
        % args.perms)
    say("  Each pass keeps every EURUSD minute's value and time of day and")
    say("  changes only its date, so both marginals are preserved exactly and")
    say("  only the contemporaneous XAU-EUR link is destroyed.")
    rng = random.Random(PARAMS["SEED"])
    day_of, donor, days = perm_prep(s)
    pmeans = []
    pts_ = []
    worst_missing = 0
    tc = time.time()
    for k in range(args.perms):
        ps = permuted_series(s, day_of, donor, days, rng)
        worst_missing = max(worst_missing, ps.acct["donor_missing"])
        pr = run_cell(ps, L, H, Z, True, xau.point, params=PARAMS)
        pmeans.append(pr["mean"])
        pts_.append(pr["t"])
        if (k + 1) % 10 == 0:
            sys.stderr.write("    perm %d/%d %.0fs\r"
                             % (k + 1, args.perms, time.time() - tc))
            sys.stderr.flush()
    sys.stderr.write("                                        \r")
    pm_sorted = sorted(pmeans)
    ctrl_mean = math.fsum(pmeans) / len(pmeans) if pmeans else 0.0
    say("  %d passes in %.0fs; worst donor_missing=%d of %d valid minutes"
        % (len(pmeans), time.time() - tc, worst_missing, len(s)))
    say("  control net mean: " + qsummary(pmeans))
    if pmeans:
        ge = sum(1 for v in pmeans if v >= res["mean"])
        say("  control t: " + qsummary(pts_))
        say("  passes whose mean reached the residual arm's %+.2f : %d of %d"
            % (res["mean"], ge, len(pmeans)))
        say("  empirical one-sided p from the permutation distribution = %.4f"
            % ((ge + 1.0) / (len(pmeans) + 1.0)))
        say("  control p95=%+.2f  max=%+.2f"
            % (quantile(pm_sorted, 0.95), pm_sorted[-1]))
    say("")

    say("10. H1 VERDICT - the five gates, in the pre-registered order")
    verdict, glines = h1_verdict(res, nob, ctrl_mean, PARAMS)
    for ln in glines:
        say("  " + ln)
    say("")

    say("11. THE CENSORED BARRIER NULL (the Phase A correction, measured)")
    say("  Phase A used p_rw = 1/(1+R), which is exact only for an UNCENSORED")
    say("  walk. Under a time cap it is wrong and the error grows with R. This")
    say("  measures the real thing: random entries on these same real paths,")
    say("  stop at S and target at R*S, where S is a 1-sigma 15-minute move")
    say("  from the trailing %d minutes. No absolute price constant."
        % PARAMS["W_SIG"])
    sig1 = rolling_sigma1(s, PARAMS["W_SIG"], PARAMS["MIN_SIG"])
    nsig = sum(1 for v in sig1 if v > 0.0)
    tc = time.time()
    acc, used, cand = barrier_null(s, sig1, PARAMS,
                                  random.Random(PARAMS["SEED"] + 1))
    say("  minutes with a usable sigma=%d; entries drawn=%d used=%d in %.0fs"
        % (nsig, cand, used, time.time() - tc))
    caps = PARAMS["NULL_CAPS_S"]
    pooled = {}
    for R in PARAMS["NULL_R"]:
        for cp in caps:
            x_ = acc[(1, R, cp)]
            y_ = acc[(-1, R, cp)]
            pooled[(R, cp)] = [x_[i] + y_[i] for i in range(6)]
    say("  p_hat = target-first share of RESOLVED paths (long+short pooled):")
    say("  %6s %9s" % ("R", "1/(1+R)")
        + "".join("%9s" % ("cap" + str(cp) + "s") for cp in caps))
    worst_dev = 0.0
    worst_cell = (0.0, 0)
    for R in PARAMS["NULL_R"]:
        cells = []
        for cp in caps:
            p = pooled[(R, cp)]
            rs = p[1] + p[2] + p[3]
            v = (p[1] / rs) if rs else float("nan")
            cells.append("%9.4f" % v)
            if rs and abs(v - 1.0 / (1.0 + R)) > worst_dev:
                worst_dev = abs(v - 1.0 / (1.0 + R))
                worst_cell = (R, cp)
        say("  %6.2f %9.4f" % (R, 1.0 / (1.0 + R)) + "".join(cells))
    say("  E[R] per path, timeouts marked to market at the cap:")
    say("  %6s %9s" % ("R", "")
        + "".join("%9s" % ("cap" + str(cp) + "s") for cp in caps))
    for R in PARAMS["NULL_R"]:
        cells = []
        for cp in caps:
            p = pooled[(R, cp)]
            cells.append("%9.4f" % (p[5] / p[0]) if p[0] else "%9s" % "-")
        say("  %6.2f %9s" % (R, "") + "".join(cells))
    p10 = pooled[(1.0, 1800)]
    say("  at R=1.0 cap=1800s: n=%d target=%d stop=%d ambiguous=%d timeout=%d"
        % (p10[0], p10[1], p10[2], p10[3], p10[4]))
    #--- The R=1.0 row reads 0.5000 at every cap and its E[R] reads 0.0000,
    #--- and neither is a measurement. Longs and shorts are drawn from the
    #--- same minutes with symmetric barriers, so a long's target-first path
    #--- IS the short's stop-first path on that same path: pooling makes
    #--- target == stop identically. Said out loud here because a reader
    #--- scanning for "matches the formula" would otherwise find the one row
    #--- that cannot disagree with it and take it as confirmation.
    say("  The R=1.00 row is 0.5000 at every cap BY CONSTRUCTION. Longs and")
    say("  shorts run on the same minutes with symmetric barriers, so a")
    say("  long's target-first path is the short's stop-first path and")
    say("  pooling forces target == stop. That row is a self-check on the")
    say("  tracker, not evidence about the market; its E[R]=0.0000 likewise.")
    say("  Per-direction split at R=1.00. The two rows are exact complements")
    say("  (short = 1 - long) for the same reason, so they are ONE number per")
    say("  cap, not two: how far the long row sits from 0.5000 is the sign and")
    say("  size of the drift over the span, at that holding time.")
    say("  %6s" % "dir" + "".join("%9s" % ("cap" + str(cp) + "s") for cp in caps))
    for dr, nm in ((1, "long"), (-1, "short")):
        cells = []
        for cp in caps:
            a_ = acc[(dr, 1.0, cp)]
            rs = a_[1] + a_[2] + a_[3]
            cells.append("%9.4f" % (a_[1] / rs) if rs else "%9s" % "-")
        say("  %6s" % nm + "".join(cells))
    say("  worst |p_hat - 1/(1+R)| over the grid = %.4f, at R=%.2f cap=%ds."
        % (worst_dev, worst_cell[0], worst_cell[1]))
    say("  That gap is the size of the error the textbook formula would have")
    say("  introduced, measured rather than argued. Ambiguous minutes (both")
    say("  barriers inside one minute, order unknown from OHLC) are charged")
    say("  as stops.")
    say("")

    say("12. H2 - SCHEDULED LIQUIDITY REVERSION AT FIVE NAMED ANCHORS")
    say("  Anchors were named in the pre-registration before any of this data")
    say("  was looked at, and are NOT scanned: London 10:30 and 15:00 fixes,")
    say("  COMEX floor open 08:20 NY, settlement 13:30 NY, and the 17:00 NY")
    say("  roll. Sign of the %d minutes before, faded for %d minutes after,"
        % (PARAMS["H2_PRE_MIN"], PARAMS["H2_POST_MIN"]))
    say("  same cost model. Threshold t > %.2f is Bonferroni over 5 anchors;"
        % PARAMS["H2_T_CRIT"])
    say("  uncorrected, five looks at 5% would give 1 - 0.95^5 = 22.6%.")
    h2 = h2_study(s, PARAMS, DEV_FROM, DEV_TO, xau.point)
    say("  %-18s %6s %9s %8s %7s %s"
        % ("anchor", "n", "mean", "sd", "t", "dropped(min/pre/post/flat)"))
    h2_live = []
    for name, _z, _hh, _mm in H2_ANCHORS:
        r = h2[name]
        say("  %-18s %6d %+9.2f %8.1f %+7.2f %d/%d/%d/%d"
            % (name, r["n"], r["mean"], r["sd"], r["t"], r["miss_minute"],
               r["miss_pre"], r["miss_post"], r["flat"]))
        if (r["n"] >= PARAMS["H2_MIN_N"] and r["t"] > PARAMS["H2_T_CRIT"]
                and r["mean"] > 0.0):
            h2_live.append(name)
    if not clock_ok:
        h2_verdict = "INCONCLUSIVE"
        say("  -> INCONCLUSIVE. The broker clock fit disagreed with the EU rule")
        say("     in section 3, so these anchors may be an hour off. Fix the")
        say("     clock before reading any of the numbers above.")
    elif h2_live:
        h2_verdict = "SURVIVES"
        say("  -> SURVIVES at: " + ", ".join(h2_live))
        say("     A positive mean here is reversion paying after cost. This is")
        say("     one DEV result at a pre-named clock time, not a strategy.")
    else:
        h2_verdict = "DEAD"
        say("  -> DEAD. No anchor clears t > %.2f with n >= %d and a positive"
            % (PARAMS["H2_T_CRIT"], PARAMS["H2_MIN_N"]))
        say("     mean after cost. A large NEGATIVE t would be continuation,")
        say("     not reversion, and is not a pass under the hypothesis as it")
        say("     was written - it is not re-read as one here.")
    say("")

    say("13. EXPLORATORY GRID - THIS DECIDES NOTHING")
    ncell = len(PARAMS["GRID_L"]) * len(PARAMS["GRID_H"]) * len(PARAMS["GRID_Z"])
    say("  %d cells. At 5%% each, the chance that at least one looks" % ncell)
    say("  significant by luck alone is 1 - 0.95^%d = %.1f%%. The primary cell"
        % (ncell, 100.0 * (1.0 - 0.95 ** ncell)))
    say("  above is the ONLY one that decides anything, and no parameter in it")
    say("  is changed on the strength of anything printed here. This is")
    say("  reported so a reader can see the shape of the surface - and so that")
    say("  if the primary cell is the surface's lone peak, that is visible")
    say("  rather than hidden.")
    grid = []
    tc = time.time()
    for gl in PARAMS["GRID_L"]:
        for gh in PARAMS["GRID_H"]:
            for gz in PARAMS["GRID_Z"]:
                g_ = run_cell(s, gl, gh, gz, True, xau.point, params=PARAMS)
                grid.append((gl, gh, gz, g_["n"], g_["mean"], g_["t"]))
    say("  %d cells in %.0fs" % (len(grid), time.time() - tc))
    say("  %4s %4s %5s %8s %9s %7s" % ("L", "H", "Z", "n", "mean", "t"))
    for row in grid:
        mark = "  <- primary" if (row[0] == L and row[1] == H
                                  and abs(row[2] - Z) < 1e-9) else ""
        say("  %4d %4d %5.2f %8d %+9.2f %+7.2f%s"
            % (row[0], row[1], row[2], row[3], row[4], row[5], mark))
    pos = [r for r in grid if r[5] > PARAMS["T_CRIT"] and r[4] > 0.0]
    say("  cells with mean>0 and t>%.2f: %d of %d (expected by chance alone at"
        % (PARAMS["T_CRIT"], len(pos), len(grid)))
    say("  5%% one-sided: about %.1f)" % (0.05 * len(grid)))
    if grid:
        best = max(grid, key=lambda r: r[5])
        say("  highest t in the grid: L=%d H=%d Z=%.2f t=%+.2f mean=%+.2f n=%d"
            % (best[0], best[1], best[2], best[5], best[4], best[3]))
        ls = sorted(set(r[0] for r in grid))
        say("  t by L (median over H,Z): " + ", ".join(
            "L=%d %.2f" % (v, quantile(sorted(r[5] for r in grid
                                              if r[0] == v), 0.5))
            for v in ls))
        hs_ = sorted(set(r[1] for r in grid))
        say("  t by H (median over L,Z): " + ", ".join(
            "H=%d %.2f" % (v, quantile(sorted(r[5] for r in grid
                                              if r[1] == v), 0.5))
            for v in hs_))
    say("")

    say("14. MULTIPLICITY, HONESTLY")
    say("  Two hypotheses were pre-registered and two were tested. At 5% each,")
    say("  the chance that at least one shows something by luck alone is")
    say("  1 - 0.95^2 = 9.75%. Neither verdict below is corrected for the")
    say("  other; both are reported so the reader can apply their own")
    say("  correction. Every earlier exploratory cut (S1, S2) stays rejected")
    say("  and none of its parameters was reused here.")
    say("")

    say("15. ARTIFACTS")
    rp = os.path.join(outdir, "report.txt")
    with open(os.path.join(outdir, "primary_cell.csv"), "w", newline="",
              encoding="ascii") as fh:
        w = csv.writer(fh)
        w.writerow(["entry_epoch", "exit_epoch", "z", "eps_bp", "sigma_bp",
                    "beta", "dir", "raw_pts", "cost_pts", "net_pts"])
        for r in res["rows"]:
            w.writerow(["%d" % r[0], "%d" % r[1], "%.6f" % r[2], "%.6f" % r[3],
                        "%.6f" % r[4], "%.6f" % r[5], "%d" % int(r[6]),
                        "%.2f" % r[7], "%.2f" % r[8], "%.2f" % r[9]])
    with open(os.path.join(outdir, "grid.csv"), "w", newline="",
              encoding="ascii") as fh:
        w = csv.writer(fh)
        w.writerow(["L", "H", "Z", "n", "mean_pts", "t"])
        for row in grid:
            w.writerow([row[0], row[1], "%.2f" % row[2], row[3],
                        "%.4f" % row[4], "%.4f" % row[5]])
    with open(os.path.join(outdir, "perm_means.csv"), "w", newline="",
              encoding="ascii") as fh:
        w = csv.writer(fh)
        w.writerow(["pass", "mean_pts", "t"])
        for k in range(len(pmeans)):
            w.writerow([k, "%.4f" % pmeans[k], "%.4f" % pts_[k]])
    with open(os.path.join(outdir, "barrier_null.csv"), "w", newline="",
              encoding="ascii") as fh:
        w = csv.writer(fh)
        w.writerow(["dir", "R", "cap_s", "n", "target", "stop", "ambiguous",
                    "timeout", "sum_R"])
        for key in sorted(acc):
            v = acc[key]
            w.writerow([key[0], "%.2f" % key[1], key[2], v[0], v[1], v[2],
                        v[3], v[4], "%.4f" % v[5]])
    for f in ("report.txt", "primary_cell.csv", "grid.csv", "perm_means.csv",
              "barrier_null.csv"):
        say("  " + os.path.join(outdir, f))
    say("")

    say("16. WHAT HAPPENS NEXT - decided by the gates, not by preference")
    alive = (verdict == "SURVIVES")
    if alive:
        say("  H1 survived all five gates on DEV. The next step is NOT an EA.")
        say("  It is: pre-register the barrier study in CHANGELOG (R grid")
        say("  including 0.5 and 0.75, the caps measured in section 11, and")
        say("  the stop rule) BEFORE writing it, then run it, and only then")
        say("  decide whether anything reaches VAL. VAL is one look at one")
        say("  frozen candidate and it has not been spent.")
    elif verdict == "UNDERPOWERED":
        say("  H1 is UNDERPOWERED, which is not a licence to loosen anything.")
        say("  The honest options are: a longer DEV span from the same broker,")
        say("  or dropping the cut. Lowering Z or lengthening H to manufacture")
        say("  observations would be fitting the design to the sample, and the")
        say("  pre-registration forbids it.")
    else:
        say("  H1 is %s. Under the pre-registration that is the end of this" % verdict)
        say("  cut: no parameter is retuned, no gate is relaxed, and the 48-cell")
        say("  grid in section 13 is not mined for a survivor.")
    if h2_verdict == "SURVIVES":
        say("  H2 survived at a pre-named anchor. Same rule: pre-register the")
        say("  follow-up before writing it.")
    elif h2_verdict == "INCONCLUSIVE":
        say("  H2 could not be judged - fix the clock and re-run only H2.")
    else:
        say("  H2 is DEAD as written.")
    if not alive and h2_verdict != "SURVIVES":
        say("")
        say("  BOTH pre-registered hypotheses failed. The recommendation is to")
        say("  STOP adding cuts to XAUUSD minute data from this broker rather")
        say("  than open a third one. Two independent, pre-registered, honestly")
        say("  gated failures on the same instrument and the same span are")
        say("  information: this feed, at this cost, over this period, does not")
        say("  show a reversion edge that survives its own cost. The next")
        say("  productive move is a different instrument or a different data")
        say("  class (real exchange volume, futures, options), NOT a fourth")
        say("  parameterisation of the same idea.")
    say("")
    #--- COMPLETE unconditionally: every fatal path above has already printed
    #--- its own VERDICT= token and returned, so a conditional here would be a
    #--- branch that cannot fire, and reading one is worse than not having it.
    say("XSP_RESIDUAL H1=%s H2=%s n=%d mean=%+.2f t=%.2f elapsed=%.0fs "
        "VERDICT=COMPLETE" % (verdict, h2_verdict, res["n"], res["mean"],
                              res["t"], time.time() - t_start))
    say.save(rp)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="xspresidual.py",
        description="XauStructurePro H1/H2 falsification on exported minutes. "
                    "DEV only - rows dated %s or later are refused." % VAL_GUARD)
    ap.add_argument("--dir", default=None,
                    help="folder holding xsp_minutes_XAUUSD.csv and "
                         "xsp_minutes_EURUSD.csv (default: the MT5 common "
                         "Files\\XauStructurePro folder)")
    ap.add_argument("--perms", type=int, default=PARAMS["PERMS"],
                    help="gate-5 permutation passes (pre-registered: %d)"
                         % PARAMS["PERMS"])
    ap.add_argument("--selftest", action="store_true",
                    help="falsify the engine on synthetic data and exit; runs "
                         "3 permutation passes regardless of --perms")
    args = ap.parse_args(argv)
    if args.perms < 1:
        ap.error("--perms must be at least 1")
    if args.selftest:
        return selftest(perms=3)
    return report(args)


if __name__ == "__main__":
    sys.exit(main())





























