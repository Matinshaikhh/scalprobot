#!/usr/bin/env python
"""xspstudy - Phase A falsification arithmetic over the XSP per-instance CSV.

PURE POST-PROCESSING. It reads one file and prints numbers; it never re-runs the
tape. That is the whole point of storing four reward tiers, four holding caps and
the raw spread per instance: the entire barrier-geometry surface and both cost
models are RECOMPUTATIONS here, so no result in this report was selected by
running the tester again and keeping the better answer.

WHAT IT REFUSES
  hard (exit 2)  no '# xsp:' preamble; schema version mismatch; the 45-column
                 header does not match this script's expectation; no data rows.
                 In each case the columns cannot be trusted to be the columns,
                 so any number printed would be arithmetic on the wrong field.
  soft (exit 1)  no trailing provenance/census block (the pass died mid-run);
                 RECONCILED=NO; quotable=no; segment UNDECLARED; tick model not
                 REAL_TICKS. The numbers are printed for debugging and every
                 table is stamped NOT QUOTABLE.

THE TWO INEQUALITIES, and why they are not the plan's pair.
The plan wrote 'p_hat > BE_WR' and 'p_hat - p_rw > 2 SE' with BE_WR and p_rw
both cost-adjusted, which makes them algebraically the same claim twice. The
corrected pair separates two genuinely different questions:

  (1) IS THERE A SIGNAL AT ALL - cost-free, against the driftless-walk null.
      A driftless walk on the bid path touches +T before -S with probability
      S/(S+T). Every instance in a tier has T = R*S by construction, so
                p_rw = 1/(1+R)                       EXACTLY, no averaging.
      Claim (1) is  p_hat - p_rw > 2*SE,  SE = sqrt(p_hat(1-p_hat)/n).

  (2) IS IT TRADABLE - the same signal against cost.
      net win = T - c, net loss = S + c, so with k = c/S,
                BE_net = (1 + k)/(1 + R)
      and because BE_net is LINEAR in k, the sample's break-even is exactly
      (1 + mean(k))/(1 + R). The whole effect of cost is one number, mean(c/S) -
      which is audit 8.1's arithmetic ('a 200pt stop needs 2.62pt of edge, a
      600pt stop only 0.87pt') expressed per instance.
      Claim (2) is  p_hat > BE_net.

  p_rw does NOT move with cost. Cost changes what must be cleared, not what a
  driftless walk does. Reporting a cost-adjusted null would double-count it.

WIN RATE IS THE SECONDARY METRIC, NOT THE PRIMARY ONE. It is defined only over
barrier-resolved instances, so it silently excludes every time exit - and if
time exits lean negative, a flattering win rate is exactly what that exclusion
produces. The primary metric is EXPECTANCY IN R over every instance whose
outcome at the cap was OBSERVED (targets, stops and time exits with a known
mark), which is also what audit 9.3 asks a component to improve by more than
its standard error. Unresolved instances are counted and excluded, never
treated as flat.

Usage:
  python xspstudy.py --csv <file> [--commission 7.0] [--stress 1.5]
                     [--primary-tier 1.5] [--primary-cap 3600]
                     [--min-n 200] [--explore-min-n 100] [--quiet-surface]
"""
import argparse
import csv
import math
import os
import sys

SCHEMA = "xsp-instance-v1"
NEVER = -1
NO_MARK = -999.0
R_TIERS = (("r100", 1.0), ("r150", 1.5), ("r200", 2.0), ("r300", 3.0))
CAPS = (300, 900, 1800, 3600)

# The schema, duplicated from CXspRecorder::Columns() ON PURPOSE. A version
# string alone would let a column be RENAMED or REORDERED without changing the
# version, and the failure mode of that is silent: every cut afterwards reads a
# neighbouring field. Asserting the full list turns it into a refusal.
EXPECTED_COLUMNS = [
    "instance_id", "fingerprint", "setup", "direction",
    "event_bar_epoch", "trigger_epoch", "trigger_time_server",
    "ref_entry_bid", "fill_price", "spread_pts_at_trigger",
    "invalidation", "level_price", "pool_kind", "stop_pts", "atr_pts_at_event",
    "sec_to_stop", "sec_to_tgt_r100", "sec_to_tgt_r150", "sec_to_tgt_r200",
    "sec_to_tgt_r300",
    "mfe_pts", "mae_pts", "mfe_r", "mae_r", "sec_to_mfe",
    "r_at_cap_300", "r_at_cap_900", "r_at_cap_1800", "r_at_cap_3600",
    "tracked_seconds", "ticks_seen",
    "vol_decile", "spread_decile", "h1_trend", "h4_trend",
    "h1_aligned", "h4_aligned", "h1_range_pos", "session", "minute_of_day",
    "broker_tick_volume", "tickvol_slot_median", "tickvol_slot_samples",
    "tickvol_ratio", "tickvol_confirm_pass",
]

INT_COLS = ("instance_id", "event_bar_epoch", "trigger_epoch", "sec_to_stop",
            "sec_to_tgt_r100", "sec_to_tgt_r150", "sec_to_tgt_r200",
            "sec_to_tgt_r300", "sec_to_mfe", "tracked_seconds", "ticks_seen",
            "vol_decile", "spread_decile", "h1_aligned", "h4_aligned",
            "minute_of_day", "broker_tick_volume", "tickvol_slot_samples",
            "tickvol_confirm_pass")
FLOAT_COLS = ("ref_entry_bid", "fill_price", "spread_pts_at_trigger",
              "invalidation", "level_price", "stop_pts", "atr_pts_at_event",
              "mfe_pts", "mae_pts", "mfe_r", "mae_r",
              "r_at_cap_300", "r_at_cap_900", "r_at_cap_1800", "r_at_cap_3600",
              "h1_range_pos", "tickvol_slot_median", "tickvol_ratio")

FAILURES = []
NOTES = []


def refuse(msg):
    print("REFUSED: " + msg)
    sys.exit(2)


def soft(msg):
    FAILURES.append(msg)


def note(msg):
    NOTES.append(msg)


# --------------------------------------------------------------------------
# reading
# --------------------------------------------------------------------------
def load(path):
    """Split the file into preamble comments, header, rows and trailing block.

    CXspCsv writes every comment as '# <text>' with commas turned into
    semicolons, so a comment can never be mistaken for a 45-field row.
    """
    if not os.path.isfile(path):
        refuse("no such file: %s" % path)
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        raw = [ln.rstrip("\r\n") for ln in fh]

    pre, post, header, body = [], [], None, []
    for ln in raw:
        if ln.strip() == "":
            continue
        if ln.startswith("#"):
            (pre if header is None else post).append(ln[1:].strip())
        elif header is None:
            header = ln
        else:
            body.append(ln)
    return pre, header, body, post


def kv(lines, prefix):
    """Pull 'a=b; c=d' fields out of the first comment line starting prefix."""
    for ln in lines:
        if not ln.startswith(prefix):
            continue
        out = {}
        for part in ln[len(prefix):].split(";"):
            if "=" in part:
                k, v = part.split("=", 1)
                out[k.strip()] = v.strip()
        return out, ln
    return None, ""


def parse_rows(header, body):
    cols = [c.strip() for c in header.split(",")]
    if cols != EXPECTED_COLUMNS:
        extra = [c for c in cols if c not in EXPECTED_COLUMNS]
        missing = [c for c in EXPECTED_COLUMNS if c not in cols]
        refuse("header does not match this script's schema.\n"
               "  file has %d columns, expected %d\n"
               "  unexpected: %s\n  missing: %s\n"
               "  Fix CXspRecorder::Columns() and this list together, and bump "
               "XSP_SCHEMA_VERSION." % (len(cols), len(EXPECTED_COLUMNS),
                                        ", ".join(extra) or "-",
                                        ", ".join(missing) or "-"))
    rows, bad = [], 0
    for raw in csv.reader(body):
        if len(raw) != len(cols):
            bad += 1
            continue
        r = dict(zip(cols, raw))
        try:
            for c in INT_COLS:
                r[c] = int(r[c])
            for c in FLOAT_COLS:
                r[c] = float(r[c])
        except ValueError:
            bad += 1
            continue
        rows.append(r)
    if bad:
        soft("%d row(s) were malformed and dropped - the file is not the sample "
             "it claims" % bad)
    if not rows:
        refuse("no parseable data rows")
    return rows


# --------------------------------------------------------------------------
# integrity: invariants the INSTRUMENT must satisfy, checked on real data
# --------------------------------------------------------------------------
def integrity(rows):
    """Every check here is an invariant of CXspBarrierTracker, not a property
    of the market. A violation means the measurement is wrong, so it is
    reported as a failure rather than as an interesting feature of the data.
    """
    bad = {}

    def flag(name, r):
        bad.setdefault(name, []).append(r["instance_id"])

    for r in rows:
        if not r["stop_pts"] > 0:
            flag("stop_pts <= 0", r)
        if r["mfe_pts"] < -1e-9:
            flag("mfe_pts < 0", r)
        if r["mae_pts"] > 1e-9:
            flag("mae_pts > 0", r)
        if r["spread_pts_at_trigger"] < -1e-9:
            flag("spread < 0", r)
        if r["sec_to_mfe"] > r["tracked_seconds"]:
            flag("sec_to_mfe > tracked_seconds", r)
        # The stop CLOSES the instance, so no barrier time can post-date it.
        ts = r["sec_to_stop"]
        prev = None
        for key, _ in R_TIERS:
            tt = r["sec_to_tgt_" + key]
            if tt != NEVER and ts != NEVER and tt > ts:
                flag("target stamped after the stop", r)
            if tt != NEVER and prev is not None and prev != NEVER and tt < prev:
                flag("higher tier reached before a lower one", r)
            prev = tt
        # A recorded stop means the adverse excursion reached at least the stop.
        if ts != NEVER and r["mae_pts"] > -r["stop_pts"] + 0.01:
            flag("stop recorded but mae never reached it", r)
        if r["stop_pts"] > 0:
            if abs(r["mfe_r"] - r["mfe_pts"] / r["stop_pts"]) > 0.01:
                flag("mfe_r disagrees with mfe_pts/stop_pts", r)
    return bad


# --------------------------------------------------------------------------
# the derivation: one (reward tier, holding cap) cell from stored times
# --------------------------------------------------------------------------
def resolve(row, tier_key, tier_r, cap):
    """Outcome and gross value in R for one instance in one cell.

    ORDER OF TESTS. The target is tested FIRST, and that is not an optimistic
    choice - it is forced by the tracker. A stop closes the instance and retires
    it, so no tick after the stop can stamp a target time. A target time that
    exists therefore always precedes or ties the stop, and the tie means the
    target was reached on an earlier tick inside the same second. integrity()
    asserts this on the real data rather than trusting the argument.

    NO MARK AT THE CAP means the tracker never saw a tick at or after that age:
    the run ended underneath the instance. That is UNRESOLVED - genuinely not
    observed - and is excluded rather than scored as flat.
    """
    tt = row["sec_to_tgt_" + tier_key]
    ts = row["sec_to_stop"]
    if tt != NEVER and tt <= cap:
        return "target", tier_r
    if ts != NEVER and ts <= cap:
        return "stop", -1.0
    mark = row["r_at_cap_%d" % cap]
    if mark < -900.0:
        return "unresolved", None
    return "time", mark


def cost_ratio(row, comm, stress):
    """Round-trip cost in units of the stop distance.

    ONE spread, not two. Barriers are measured on the BID for both directions;
    a long gives up the spread entering and a short gives it up exiting, so
    relative to the bid path the round trip costs exactly one spread either way.
    Charging two would overstate the toll by a factor of two on the one quantity
    the whole study turns on.
    """
    return (row["spread_pts_at_trigger"] * stress + comm) / row["stop_pts"]


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def stdev(xs):
    if len(xs) < 2:
        return float("nan")
    m = mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))


def cell(rows, tier_key, tier_r, cap, comm, stress):
    """One (reward tier, holding cap) geometry, both metrics, one pass."""
    tgt = stp = tex = unres = 0
    net, gross, k_bar, k_obs = [], [], [], []
    for r in rows:
        oc, val = resolve(r, tier_key, tier_r, cap)
        if oc == "unresolved":
            unres += 1
            continue
        k = cost_ratio(r, comm, stress)
        if oc == "target":
            tgt += 1
            k_bar.append(k)
        elif oc == "stop":
            stp += 1
            k_bar.append(k)
        else:
            tex += 1
        gross.append(val)
        net.append(val - k)
        k_obs.append(k)

    n_bar = tgt + stp
    n_obs = len(net)
    c = {"tier": tier_r, "cap": cap, "n_total": len(rows), "n_bar": n_bar,
         "n_obs": n_obs, "targets": tgt, "stops": stp, "time_exits": tex,
         "unresolved": unres,
         "unres_frac": unres / len(rows) if rows else float("nan"),
         "p_rw": 1.0 / (1.0 + tier_r)}
    c["p_hat"] = tgt / n_bar if n_bar else float("nan")
    c["se_p"] = (math.sqrt(c["p_hat"] * (1 - c["p_hat"]) / n_bar)
                 if n_bar else float("nan"))
    c["k_bar"] = mean(k_bar)
    c["k_obs"] = mean(k_obs)
    # BE_net is LINEAR in k, so the sample break-even is exact at mean(k) -
    # no Jensen gap to apologise for.
    c["be_net"] = ((1.0 + c["k_bar"]) / (1.0 + tier_r)
                   if n_bar else float("nan"))
    c["edge_pp"] = c["p_hat"] - c["p_rw"]
    c["exp_net"] = mean(net)
    c["exp_gross"] = mean(gross)
    c["sd_net"] = stdev(net)
    c["se_exp"] = (c["sd_net"] / math.sqrt(n_obs)
                   if n_obs > 1 else float("nan"))
    c["t_exp"] = (c["exp_net"] / c["se_exp"]
                  if n_obs > 1 and c["se_exp"] > 0 else float("nan"))
    wins = sum(x for x in net if x > 0)
    loss = -sum(x for x in net if x < 0)
    c["pf"] = wins / loss if loss > 0 else float("inf") if wins > 0 else float("nan")
    # A target worth less than the cost is not a win. It makes BE_net exceed 1
    # and the win-rate framing meaningless, so it is named rather than printed
    # as an impossible threshold.
    c["target_below_cost"] = bool(n_bar) and c["k_bar"] >= tier_r
    return c


def verdict(c, min_n):
    """The pre-declared decision, in the pre-declared order.

    KILL comes before UNDERPOWERED on purpose: a setup at or below the driftless
    walk with the required sample is dead, and 'collect more data' is exactly the
    rescue the plan's kill gate exists to forbid.
    """
    if c["n_bar"] < min_n:
        return "UNDERPOWERED", "n=%d < %d resolved" % (c["n_bar"], min_n)
    if c["p_hat"] <= c["p_rw"]:
        return "DEAD", ("p_hat %.4f <= p_rw %.4f at n=%d - killed by the "
                        "pre-declared gate" % (c["p_hat"], c["p_rw"], c["n_bar"]))
    claim1 = c["edge_pp"] > 2.0 * c["se_p"]
    claim2 = c["p_hat"] > c["be_net"]
    if claim1 and claim2:
        return "EDGE", "beats the null by >2SE and clears break-even"
    if claim1:
        return "SIGNAL, NOT TRADABLE", ("beats the null by >2SE but p_hat %.4f "
                                        "<= BE_net %.4f" % (c["p_hat"], c["be_net"]))
    if claim2:
        return "NOT SIGNIFICANT", ("clears break-even but edge %.4f <= 2SE %.4f"
                                   % (c["edge_pp"], 2.0 * c["se_p"]))
    return "NO EDGE", "fails both inequalities"


def f(x, w=8, d=4):
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "n/a".rjust(w)
    if isinstance(x, float) and math.isinf(x):
        return "inf".rjust(w)
    return ("%*.*f" % (w, d, x))


def cell_block(name, c, min_n, indent="  "):
    v, why = verdict(c, min_n)
    out = []
    out.append("%s%s" % (indent, name))
    out.append("%s  sample     total=%-6d observed=%-6d barrier=%-6d "
               "time_exit=%-5d unresolved=%d (%.1f%%)"
               % (indent, c["n_total"], c["n_obs"], c["n_bar"], c["time_exits"],
                  c["unresolved"], 100.0 * c["unres_frac"]))
    out.append("%s  win rate   p_hat=%s  p_rw=%s  edge=%s  2SE=%s"
               % (indent, f(c["p_hat"]), f(c["p_rw"]), f(c["edge_pp"]),
                  f(2.0 * c["se_p"])))
    out.append("%s  cost       mean(c/S)=%s  BE_net=%s  gap=%s  (targets %d "
               "stops %d)"
               % (indent, f(c["k_bar"]), f(c["be_net"]),
                  f(c["be_net"] - c["p_rw"]), c["targets"], c["stops"]))
    out.append("%s  expectancy E_net=%s R  sd=%s  SE=%s  t=%s  PF=%s  "
               "(E_gross=%s R)"
               % (indent, f(c["exp_net"]), f(c["sd_net"]), f(c["se_exp"]),
                  f(c["t_exp"], 7, 2), f(c["pf"], 6, 2), f(c["exp_gross"])))
    if c["target_below_cost"]:
        out.append("%s  NOTE the mean cost exceeds the target: %.2f R of cost "
                   "against a %.2f R target, so a 'win' is a loss and the "
                   "win-rate framing does not apply here."
                   % (indent, c["k_bar"], c["tier"]))
    out.append("%s  VERDICT    %s - %s" % (indent, v, why))
    return "\n".join(out), v


def surface(rows, comm, stress, label, min_n):
    """The whole 4x4 geometry, from ONE traversal of the same file.

    EXPLORATORY BY CONSTRUCTION, and the multiplicity is stated rather than
    left for the reader to work out: at 16 cells, the chance that at least one
    clears a 2SE bar by luck alone is 1 - 0.95**16 = 56%. A cell that looks good
    HERE is not a finding; it is a hypothesis for a fresh slice.
    """
    print("  %s - expectancy in R per instance, net of cost" % label)
    print("      cap ->" + "".join("%12s" % ("%ds" % c) for c in CAPS))
    for key, r in R_TIERS:
        line = "      R=%-4.1f " % r
        for cap in CAPS:
            c = cell(rows, key, r, cap, comm, stress)
            line += "%12s" % (f(c["exp_net"], 8, 4) if c["n_obs"] else "n/a")
        print(line)
    print("  %s - p_hat minus BE_net (positive = clears break-even)" % label)
    print("      cap ->" + "".join("%12s" % ("%ds" % c) for c in CAPS))
    for key, r in R_TIERS:
        line = "      R=%-4.1f " % r
        for cap in CAPS:
            c = cell(rows, key, r, cap, comm, stress)
            ok = c["n_bar"] >= min_n
            val = (f(c["p_hat"] - c["be_net"], 8, 4) if c["n_bar"] else "n/a")
            line += "%12s" % (val if ok else val.strip() + "*")
        print(line)
    print("      * n below the minimum resolved sample - not decidable")


CUTS = [
    ("h1_aligned", lambda r: "h1_aligned=%d" % r["h1_aligned"]),
    ("h4_aligned", lambda r: "h4_aligned=%d" % r["h4_aligned"]),
    ("confirmation", lambda r: "tickvol_pass=%d" % r["tickvol_confirm_pass"]),
    ("direction", lambda r: r["direction"]),
    ("session", lambda r: r["session"]),
    ("vol decile", lambda r: ("vol=unranked" if r["vol_decile"] < 0 else
                              "vol=%s" % ("low(0-2)" if r["vol_decile"] <= 2 else
                                          "mid(3-6)" if r["vol_decile"] <= 6 else
                                          "high(7-9)"))),
    ("spread decile", lambda r: ("spread=unranked" if r["spread_decile"] < 0 else
                                 "spread=%s" % ("low(0-2)" if r["spread_decile"] <= 2
                                                else "mid(3-6)" if r["spread_decile"] <= 6
                                                else "high(7-9)"))),
    ("pool kind", lambda r: "pool=%s" % r["pool_kind"]),
]


def cuts(rows, key, tier_r, cap, comm, stress, explore_min_n):
    """Every cut below is EXPLORATORY. Reportable at n >= explore_min_n and
    re-testable only on a FRESH slice - never on VAL. A cut that looks good on
    the same data that suggested it has been fitted, not measured.
    """
    for name, fn in CUTS:
        groups = {}
        for r in rows:
            groups.setdefault(fn(r), []).append(r)
        shown = []
        for gname in sorted(groups):
            c = cell(groups[gname], key, tier_r, cap, comm, stress)
            if c["n_bar"] < explore_min_n:
                shown.append("      %-18s n=%-5d BELOW REPORTING THRESHOLD (%d)"
                             % (gname, c["n_bar"], explore_min_n))
                continue
            v, _ = verdict(c, explore_min_n)
            shown.append("      %-18s n=%-5d p_hat=%s BE_net=%s E_net=%s "
                         "t=%s  %s"
                         % (gname, c["n_bar"], f(c["p_hat"], 7),
                            f(c["be_net"], 7), f(c["exp_net"], 8),
                            f(c["t_exp"], 6, 2), v))
        print("    by %s" % name)
        for s in shown:
            print(s)


def gates(pre, post):
    """Everything that decides whether this file may be quoted at all."""
    xsp, xsp_line = kv(pre, "xsp:")
    if xsp is None:
        refuse("no leading '# xsp:' preamble. Either this is not an XSP study "
               "file, or the run died before OnInit finished writing it.")
    schema = xsp.get("schema", "")
    if schema != SCHEMA:
        refuse("schema is '%s', this script reads '%s'. Refusing rather than "
               "guessing which columns moved." % (schema, SCHEMA))

    prov, prov_line = kv(post, "provenance:")
    census, census_line = kv(post, "xsp_census:")
    if prov is None or census is None:
        # The measured half of the provenance is written by Finalise(). Its
        # absence means the pass never reached OnTester or OnDeinit - i.e. the
        # sample in this file is a PREFIX of the window it names, and nothing
        # in the rows themselves would ever reveal that.
        soft("no trailing provenance/census block - the pass did not finish, so "
             "the rows are a prefix of the declared window")
    if census is not None:
        rec = census.get("RECONCILED", "?")
        if rec != "yes":
            soft("RECONCILED=%s - the EA's own three identities do not add up, "
                 "so instances were lost or double counted" % rec)
    if prov is not None:
        if prov.get("quotable", "no") != "yes":
            soft("provenance says quotable=%s" % prov.get("quotable"))
        seg = prov.get("segment", "?")
        if "UNDECLARED" in seg.upper():
            soft("segment is %s - a run that does not say which half of the "
                 "data it used cannot be quoted for either" % seg)
        tm = prov.get("tick_model_inferred", "?")
        if "REAL_TICKS" not in tm.upper():
            soft("tick model inferred as %s, not REAL_TICKS - audit 6.2 measured "
                 "generated spread at 4.0-4.4pt against 9.5-33.5pt real, so this "
                 "run understates cost about threefold" % tm)
        if prov.get("forward", "no") != "no":
            soft("forward=%s - part of the declared window went to a forward "
                 "segment" % prov.get("forward"))
        if prov.get("optimisation", "no") != "no":
            soft("optimisation=%s - this file is one pass of a search"
                 % prov.get("optimisation"))
    return xsp, prov, census, xsp_line, prov_line, census_line


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--csv", required=True)
    ap.add_argument("--commission", type=float, default=7.0,
                    help="round-turn commission in points (audit 9.3: 7)")
    ap.add_argument("--stress", type=float, default=1.5,
                    help="pessimistic spread multiplier (audit 9.3: 1.5)")
    # THE PRIMARY CELL IS AN ARGUMENT, NOT A DISCOVERY. It must match the row
    # already in CHANGELOG.md; it is printed back so a report cannot be read
    # without seeing which cell was pre-declared as deciding.
    ap.add_argument("--primary-tier", type=float, default=1.5)
    ap.add_argument("--primary-cap", type=int, default=3600)
    ap.add_argument("--min-n", type=int, default=200)
    ap.add_argument("--explore-min-n", type=int, default=100)
    ap.add_argument("--quiet-surface", action="store_true")
    a = ap.parse_args()

    pkey = None
    for key, r in R_TIERS:
        if abs(r - a.primary_tier) < 1e-9:
            pkey = key
    if pkey is None:
        refuse("--primary-tier %.2f is not one of the recorded tiers %s"
               % (a.primary_tier, [r for _, r in R_TIERS]))
    if a.primary_cap not in CAPS:
        refuse("--primary-cap %d is not one of the recorded caps %s"
               % (a.primary_cap, list(CAPS)))

    pre, header, body, post = load(a.csv)
    if header is None:
        refuse("no header row - the file holds comments only")
    xsp, prov, census, xsp_line, prov_line, census_line = gates(pre, post)
    rows = parse_rows(header, body)

    print("=" * 78)
    print("XSP PHASE A - falsification arithmetic")
    print("=" * 78)
    print("  file      : %s" % os.path.abspath(a.csv))
    print("  rows      : %d instances" % len(rows))
    print("  schema    : %s" % xsp.get("schema"))
    print("  build     : %s" % xsp.get("build"))
    for k in ("symbol", "timeframe", "segment", "tick_model_inferred",
              "spread_avg_pts", "spread_min_pts", "spread_max_pts",
              "commission_pts", "ticks", "quotable"):
        if prov and k in prov:
            print("  %-10s: %s" % (k[:10], prov[k]))
    if census:
        for k in ("setup_bars", "opened", "rows", "orphans", "unresolved",
                  "RECONCILED"):
            if k in census:
                print("  %-10s: %s" % (k[:10], census[k]))

    print("")
    print("--- instrument integrity ---")
    bad = integrity(rows)
    if not bad:
        print("  every tracker invariant holds on all %d rows" % len(rows))
    else:
        for name, ids in sorted(bad.items()):
            soft("integrity: %s on %d row(s)" % (name, len(ids)))
            print("  FAIL %-42s %d row(s), e.g. instance %s"
                  % (name, len(ids), ids[0]))

    print("")
    print("--- sample ---")
    setups = sorted(set(r["setup"] for r in rows))
    for s in setups:
        sub = [r for r in rows if r["setup"] == s]
        print("  %-16s %5d instances  %s"
              % (s, len(sub),
                 " ".join("%s=%d" % (d, sum(1 for r in sub if r["direction"] == d))
                          for d in sorted(set(r["direction"] for r in sub)))))
    spreads = [r["spread_pts_at_trigger"] for r in rows]
    stops = [r["stop_pts"] for r in rows]
    print("  spread at trigger  mean=%.2f min=%.2f max=%.2f pts"
          % (mean(spreads), min(spreads), max(spreads)))
    print("  stop distance      mean=%.2f min=%.2f max=%.2f pts"
          % (mean(stops), min(stops), max(stops)))
    # The single number audit 8.1 turns on: cost as a fraction of the stop.
    for name, st in (("observed", 1.0), ("pessimistic", a.stress)):
        ks = [cost_ratio(r, a.commission, st) for r in rows]
        print("  cost model %-12s c = %.1fx spread + %.1f pts -> mean(c/S)=%.4f "
              "(min %.4f max %.4f)"
              % (name, st, a.commission, mean(ks), min(ks), max(ks)))
    unranked_v = sum(1 for r in rows if r["vol_decile"] < 0)
    unranked_s = sum(1 for r in rows if r["spread_decile"] < 0)
    thin = sum(1 for r in rows if r["tickvol_slot_samples"] < 3)
    print("  labels unavailable vol_decile=-1 on %d, spread_decile=-1 on %d, "
          "tickvol baseline<3 sessions on %d" % (unranked_v, unranked_s, thin))
    print("    -1 means the ranking window held too few samples to rank against."
          " It is NOT decile zero and is excluded from those cuts, not read low.")

    print("")
    print("=" * 78)
    print("PRIMARY CELL (pre-declared): R=%.1f, holding cap %ds"
          % (a.primary_tier, a.primary_cap))
    print("  null p_rw = 1/(1+R) = %.4f exactly - every instance in a tier has "
          "T = R*S" % (1.0 / (1.0 + a.primary_tier)))
    print("  this must be the cell named in CHANGELOG.md before the run. Every "
          "other cell below is exploratory.")
    print("=" * 78)
    primary = {}
    for label, st in (("observed  (spread as recorded)", 1.0),
                      ("pessimistic (spread x%.1f)" % a.stress, a.stress)):
        print("")
        print("  cost model: %s + %.1f pts commission" % (label, a.commission))
        for s in ["ALL"] + setups:
            sub = rows if s == "ALL" else [r for r in rows if r["setup"] == s]
            c = cell(sub, pkey, a.primary_tier, a.primary_cap, a.commission, st)
            block, v = cell_block(s, c, a.min_n, indent="    ")
            print(block)
            primary[(s, st)] = (c, v)

    if not a.quiet_surface:
        print("")
        print("--- the 4x4 geometry surface (EXPLORATORY) ---")
        for s in ["ALL"] + setups:
            sub = rows if s == "ALL" else [r for r in rows if r["setup"] == s]
            print("")
            print("  %s (n=%d)" % (s, len(sub)))
            surface(sub, a.commission, a.stress, "pessimistic", a.min_n)

    print("")
    print("--- exploratory cuts at the primary cell, pessimistic cost ---")
    print("  Reportable at n >= %d resolved. Any cut that looks good here is a "
          "hypothesis for a FRESH slice, never a result." % a.explore_min_n)
    for s in setups:
        print("")
        print("  %s" % s)
        sub = [r for r in rows if r["setup"] == s]
        cuts(sub, pkey, a.primary_tier, a.primary_cap, a.commission, a.stress,
             a.explore_min_n)

    print("")
    print("=" * 78)
    if FAILURES:
        print("NOT QUOTABLE - %d problem(s) with this file:" % len(FAILURES))
        for m in FAILURES:
            print("  * " + m)
        print("  Every number above is printed for DEBUGGING. An unquotable run "
              "is not a measurement.")
    else:
        print("QUOTABLE - preamble, provenance, census and instrument "
              "invariants all check out.")
    for m in NOTES:
        print("  note " + m)

    # The one-line summary, in the same shape as the harness's other verdicts so
    # a scripted caller can grep for it.
    parts = []
    for s in setups:
        c, v = primary[(s, a.stress)]
        parts.append("%s=%s(n=%d,E=%+.4fR)" % (s, v.replace(" ", "_"),
                                               c["n_bar"], c["exp_net"]))
    print("XSP_STUDY VERDICT primary=R%.1f/%ds cost=pessimistic %s QUOTABLE=%s"
          % (a.primary_tier, a.primary_cap, " ".join(parts),
             "no" if FAILURES else "yes"))
    print("=" * 78)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
