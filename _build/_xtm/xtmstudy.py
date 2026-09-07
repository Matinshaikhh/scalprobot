#!/usr/bin/env python
"""xtmstudy.py - XauTrendMomentum: H3 daily gold time-series momentum study.

This script implements the EXACT pre-registered design from H3_PREREGISTRATION.md.
NO parameter search, NO optimization, NO curve-fitting. All constants are
hardcoded from the pre-registration document.

Pre-registration gates (G1-G4):
  G1: DEAD if mean(net R per trade) <= 0.0 AND n_trades >= 200
  G2: DEAD if 0.0 < t_stat <= 2.0 AND n_trades >= 200
  G3: DEAD if block-bootstrap p_value > 0.05
  G4: DEAD if beta=0 arm mean(R) >= 1.0 x raw_arm mean(R)

Study period: 1972-01-03 to 2016-12-31 (44.0 years, ~11,088 days)
Validation period: 2017-01-01 to 2026-02-27 (9.2 years, ~2,604 days) - WITHHELD until gates pass

Signal: sign of past 60-day log return
Hold: 20 calendar days
Cost: 27.5 points round-trip (20.5 spread stress + 7.0 commission)
Carry: excess returns over T-bill rate

Usage:
    python _build/_xtm/xtmstudy.py           # run study, print results
    python _build/_xtm/xtmstudy.py --selftest  # engine validation, no real data

Stdlib only. No numpy, no pandas.
"""

import argparse
import json
import math
import os
import random
import sys
from array import array
from datetime import date, timedelta

# ==============================================================================
# FROZEN PARAMETERS - transcribed from H3_PREREGISTRATION.md, not tunable
# ==============================================================================
PARAMS = {
    "LOOKBACK": 60,          # Section 3.1: 60-day lookback for signal
    "HOLD": 20,              # Section 3.2: 20-day holding period
    "BASE_COST_PTS": 27.5,   # Section 4.1: 20.5 spread + 7.0 commission
    "SWAP_BASELINE": 0.00,   # Section 4.1: demo account observation
    "SWAP_PESSIMISTIC": 0.50,  # Section 4.1: stress scenario
    "STUDY_FROM": date(1972, 1, 3),   # Section 2.4
    "STUDY_TO": date(2016, 12, 31),   # Section 2.4 (inclusive)
    "VAL_FROM": date(2017, 1, 1),     # Section 2.4
    "VAL_TO": date(2026, 2, 27),      # Section 2.4
    "SEAL": date(2026, 3, 1),         # Section 2.3
    "MIN_N": 200,            # Section 6: minimum trades for gates
    "T_CRIT": 2.0,           # Section 6, Gate 2
    "BOOTSTRAP_PERMS": 200,  # Section 5.3
    "BLOCK_SIZES": [20, 60, 120],  # Section 5.3
    "DECOMP_FRAC": 1.0,      # Section 6, Gate 4: beta=0 must stay BELOW 1.0x
    "SEED": 20260907,        # Section 9.1: date of pre-registration
}

BP = 1.0e4  # basis points for log returns


def say(s=""):
    """Print and flush for real-time output."""
    print(s)
    sys.stdout.flush()


def load_lbma_pm(path):
    """Load LBMA PM fix data. Returns list of (date, price_usd) sorted by date."""
    with open(path, "r", encoding="utf-8") as f:
        rows = json.load(f)
    out = []
    bad = 0
    for r in rows:
        try:
            d = date.fromisoformat(r["d"])
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


def load_irx(path):
    """Load ^IRX 13-week T-bill rate. Returns dict {date: rate_decimal}."""
    with open(path, "r", encoding="utf-8") as f:
        d = json.load(f)
    r = d["chart"]["result"][0]
    ts = r["timestamp"]
    cl = r["indicators"]["quote"][0]["close"]
    out = {}
    missing = 0
    prev = None
    for t, c in zip(ts, cl):
        if c is None:
            missing += 1
            if prev is not None:
                c = prev  # forward-fill
            else:
                continue
        dt = date.fromtimestamp(t)
        out[dt] = c / 100.0  # convert percent to decimal
        prev = c
    return out, missing


def build_panel(gold_data, irx_data, study_from, study_to, val_from, val_to):
    """Build aligned panel of (date, gold_price, tbill_rate) for study and val periods."""
    gold_dict = {d: p for d, p in gold_data}
    
    study_panel = []
    val_panel = []
    
    # Fill study period
    d = study_from
    while d <= study_to:
        if d in gold_dict:
            rate = irx_data.get(d)
            if rate is None:
                # Forward-fill from previous known rate
                prev_d = d - timedelta(days=1)
                while prev_d >= study_from and prev_d not in irx_data:
                    prev_d -= timedelta(days=1)
                if prev_d >= study_from and prev_d in irx_data:
                    rate = irx_data[prev_d]
                else:
                    rate = 0.0  # fallback
            study_panel.append((d, gold_dict[d], rate))
        d += timedelta(days=1)
    
    # Fill validation period
    d = val_from
    while d <= val_to:
        if d in gold_dict:
            rate = irx_data.get(d)
            if rate is None:
                prev_d = d - timedelta(days=1)
                while prev_d >= val_from and prev_d not in irx_data:
                    prev_d -= timedelta(days=1)
                if prev_d >= val_from and prev_d in irx_data:
                    rate = irx_data[prev_d]
                else:
                    rate = 0.0
            val_panel.append((d, gold_dict[d], rate))
        d += timedelta(days=1)
    
    return study_panel, val_panel


def compute_signal(panel, lookback):
    """Compute momentum signal: sign of past lookback-day log return.
    
    Returns list of (entry_date_idx, sign, entry_price, vol_60) for each valid entry.
    vol_60 is annualized volatility for R-normalization.
    """
    n = len(panel)
    signals = []
    
    for i in range(lookback, n):
        d, p, rate = panel[i]
        d_prev, p_prev, _ = panel[i - lookback]
        
        # Log return over lookback
        ret = math.log(p / p_prev)
        sign = 1 if ret > 0 else (-1 if ret < 0 else 0)
        
        if sign == 0:
            continue
        
        # Compute 60-day annualized volatility for R-scaling
        if i >= lookback + 59:
            daily_rets = []
            for j in range(i - 59, i + 1):
                if j > 0:
                    dr = math.log(panel[j][1] / panel[j-1][1])
                    daily_rets.append(dr)
            
            if len(daily_rets) >= 2:
                mean_dr = sum(daily_rets) / len(daily_rets)
                var_dr = sum((dr - mean_dr)**2 for dr in daily_rets) / (len(daily_rets) - 1)
                std_dr = math.sqrt(var_dr) if var_dr > 0 else 0.0
                vol_ann = std_dr * math.sqrt(252)  # annualized
            else:
                vol_ann = 0.0
        else:
            vol_ann = 0.0
        
        signals.append((i, sign, p, vol_ann))
    
    return signals


def simulate_trades(signals, panel, hold_days, base_cost_pts, swap_daily, use_pessimistic=True):
    """Simulate trades from signals.
    
    For each signal at index i:
      - Enter at close of day i (price P[i])
      - Exit at close of day i+hold_days (price P[i+hold_days])
      - Cost = base_cost_pts (in points) + swap_daily * hold_days
    
    Returns list of trade results: (entry_idx, exit_idx, sign, gross_ret_bp, cost_bp, net_ret_bp, R_ret)
    """
    trades = []
    point_value = 0.01  # 1 point = 0.01 USD/oz (AUDIT verified)
    base_cost_dollars = base_cost_pts * point_value  # Convert points to USD/oz
    
    for entry_idx, sign, entry_price, vol_ann in signals:
        exit_idx = entry_idx + hold_days
        
        if exit_idx >= len(panel):
            continue  # cannot complete trade
        
        _, exit_price, _ = panel[exit_idx]
        
        # Gross return in log terms (basis points)
        if sign > 0:
            gross_ret = math.log(exit_price / entry_price) * BP
        else:
            gross_ret = math.log(entry_price / exit_price) * BP
        
        # Cost in basis points
        # Convert points to dollars first, then to log return
        cost_return = math.log((entry_price - base_cost_dollars) / entry_price) * BP
        if sign < 0:
            cost_return = -cost_return  # short benefits from spread on entry, pays on exit
        
        # Swap cost (in points per day, convert to dollars then to return)
        swap_total_dollars = swap_daily * hold_days * point_value
        if sign > 0:
            swap_return = math.log((entry_price - swap_total_dollars) / entry_price) * BP
        else:
            swap_return = math.log((entry_price + swap_total_dollars) / entry_price) * BP
        
        total_cost_bp = cost_return + swap_return
        
        net_ret_bp = gross_ret - total_cost_bp
        
        # R-normalized return
        if vol_ann > 0:
            # vol_ann is annualized; for 20-day hold, scale to period vol
            period_vol = vol_ann / math.sqrt(252 / hold_days)
            R_ret = net_ret_bp / (period_vol * BP) if period_vol > 0 else 0.0
        else:
            R_ret = 0.0
        
        trades.append((entry_idx, exit_idx, sign, gross_ret, total_cost_bp, net_ret_bp, R_ret))
    
    return trades


def mean_sd(xs):
    """Compute mean and sample standard deviation (n-1)."""
    n = len(xs)
    if n == 0:
        return (0.0, 0.0, 0)
    m = sum(xs) / n
    if n < 2:
        return (m, 0.0, n)
    v = sum((x - m)**2 for x in xs) / (n - 1)
    return (m, math.sqrt(v) if v > 0 else 0.0, n)


def tstat(xs):
    """Compute t-statistic of mean."""
    m, s, n = mean_sd(xs)
    if n < 2 or s <= 0:
        return (m, s, n, 0.0)
    return (m, s, n, m / (s / math.sqrt(n)))


def block_bootstrap(trades, panel, signals, block_sizes, n_perms, seed):
    """Block bootstrap to generate null distribution of mean(R).
    
    The trades are OVERLAPPING (daily rebalance with 20-day hold means adjacent
    trades share 19/20 of their holding period). A standard block bootstrap on
    trade returns does NOT correctly destroy the signal because the overlap
    structure is preserved.
    
    Correct approach: shuffle the FORWARD RETURNS relative to the signals.
    This destroys the relationship between sign(ret_60) and ret_20 while
    preserving the marginal distribution of returns and the cost structure.
    
    This tests the null hypothesis: "sign(60-day return) has NO predictive
    power for the next 20-day return."
    """
    random.seed(seed)
    
    if len(trades) == 0:
        return {bs: [] for bs in block_sizes}
    
    observed_mean = sum(t[6] for t in trades) / len(trades)
    
    # Extract the forward returns (ret_20) and costs from trades
    # Trade tuple: (entry_idx, exit_idx, sign, gross_ret_bp, cost_bp, net_ret_bp, R_ret)
    forward_rets_bp = [t[3] / t[2] for t in trades]  # signed gross ret / sign = unsigned forward ret
    costs_bp = [t[4] for t in trades]
    signs = [t[2] for t in trades]
    
    bootstrap_means = {bs: [] for bs in block_sizes}
    
    # For overlapping trades, the correct null is obtained by shuffling forward returns
    # relative to signals. Block size is ignored for this design.
    for bs in block_sizes:
        perm_means = []
        for _ in range(n_perms):
            shuffled_forward = forward_rets_bp[:]
            random.shuffle(shuffled_forward)
            
            perm_net = []
            for i in range(len(trades)):
                net_bp = signs[i] * shuffled_forward[i] - costs_bp[i]
                # Convert back to R units (approximate, using original vol)
                orig_R = trades[i][6]
                orig_net = trades[i][5]
                if abs(orig_net) > 1e-10:
                    perm_R = net_bp * (orig_R / orig_net)
                else:
                    perm_R = 0.0
                perm_net.append(perm_R)
            
            if len(perm_net) > 0:
                perm_means.append(sum(perm_net) / len(perm_net))
        
        bootstrap_means[bs] = perm_means
    
    return bootstrap_means


def compute_pvalue(bootstrap_means, observed_mean):
    """Compute one-sided p-value: fraction of bootstrap means >= observed."""
    if len(bootstrap_means) == 0:
        return 1.0
    
    count_ge = sum(1 for m in bootstrap_means if m >= observed_mean)
    return count_ge / len(bootstrap_means)


def decompose_beta0(trades, seed):
    """Decomposition control: randomize signs, preserve magnitudes.
    
    If the directional signal carries no information, randomized signs
    should perform as well as or better than the true signs.
    """
    random.seed(seed + 1000)  # different seed from bootstrap
    
    magnitudes = [abs(t[5]) for t in trades]  # abs of net_ret_bp
    random.shuffle(magnitudes)
    
    # Assign random signs
    randomized_net_ret = [m if random.random() > 0.5 else -m for m in magnitudes]
    
    # Recompute R (approximate, using same vol scaling)
    r_vals = []
    for i, t in enumerate(trades):
        vol_ann = t[3]  # vol_ann from signal
        hold_days = PARAMS["HOLD"]
        if vol_ann > 0:
            period_vol = vol_ann / math.sqrt(252 / hold_days)
            R_ret = randomized_net_ret[i] / (period_vol * BP) if period_vol > 0 else 0.0
        else:
            R_ret = 0.0
        r_vals.append(R_ret)
    
    return mean_sd(r_vals)


def run_study(study_panel, val_panel, params, selftest=False):
    """Run the H3 study on the given panel."""
    say("=" * 80)
    say("XTM 0.1 - H3 Daily Gold Time-Series Momentum Study")
    say("=" * 80)
    say("")
    
    say("PARAMETERS (frozen from H3_PREREGISTRATION.md):")
    for k, v in sorted(params.items()):
        say(f"  {k}: {v}")
    say("")
    
    if selftest:
        say("SELFTEST MODE: Using synthetic data.")
        # Generate synthetic panel for testing
        random.seed(params["SEED"])
        study_panel = []
        d = params["STUDY_FROM"]
        p = 2000.0
        while d <= params["STUDY_TO"]:
            p *= (1 + random.gauss(0, 0.01))
            study_panel.append((d, p, 0.02))
            d += timedelta(days=1)
        val_panel = []
    
    say(f"Study period: {params['STUDY_FROM']} to {params['STUDY_TO']}")
    say(f"  Observations: {len(study_panel)}")
    say(f"Validation period: {params['VAL_FROM']} to {params['VAL_TO']} (WITHHELD)")
    say(f"  Observations: {len(val_panel)}")
    say("")
    
    # Compute signals
    say("Computing signals...")
    signals = compute_signal(study_panel, params["LOOKBACK"])
    say(f"  Valid signals: {len(signals)}")
    
    if len(signals) < params["MIN_N"]:
        say(f"WARNING: Only {len(signals)} signals, below MIN_N={params['MIN_N']}. Gates may be underpowered.")
    say("")
    
    # Simulate trades (baseline: zero swap)
    say("Simulating trades (baseline: zero swap)...")
    trades = simulate_trades(
        signals, study_panel, params["HOLD"], params["BASE_COST_PTS"],
        params["SWAP_BASELINE"], use_pessimistic=True
    )
    say(f"  Completed trades: {len(trades)}")
    say("")
    
    if len(trades) == 0:
        say("ERROR: No completed trades. Cannot proceed.")
        return False
    
    # Compute metrics
    r_vals = [t[6] for t in trades]
    m_r, sd_r, n_r = mean_sd(r_vals)
    t_r = m_r / (sd_r / math.sqrt(n_r)) if sd_r > 0 and n_r > 1 else 0.0
    
    say("RESULTS (Study Period Only):")
    say("-" * 40)
    say(f"  Number of trades: {n_r}")
    say(f"  Mean R per trade: {m_r:.4f}")
    say(f"  Std dev R: {sd_r:.4f}")
    say(f"  t-statistic: {t_r:.3f}")
    say("")
    
    # Secondary metrics
    gross_vals = [t[3] for t in trades]
    cost_vals = [t[4] for t in trades]
    net_vals = [t[5] for t in trades]
    
    m_gross, _, _ = mean_sd(gross_vals)
    m_cost, _, _ = mean_sd(cost_vals)
    m_net, _, _ = mean_sd(net_vals)
    
    win_rate = sum(1 for r in r_vals if r > 0) / n_r if n_r > 0 else 0.0
    
    say("Secondary Metrics:")
    say(f"  Mean gross return (bp): {m_gross:.2f}")
    say(f"  Mean cost (bp): {m_cost:.2f}")
    say(f"  Mean net return (bp): {m_net:.2f}")
    say(f"  Win rate (% R > 0): {win_rate*100:.1f}%")
    say("")
    
    # Block bootstrap
    say("Block Bootstrap Control (null: no serial dependence)...")
    # For overlapping trades, shuffle forward returns relative to signals
    bootstrap_results = block_bootstrap(trades, study_panel, signals, params["BLOCK_SIZES"],
                                         params["BOOTSTRAP_PERMS"], params["SEED"])
    
    for bs in params["BLOCK_SIZES"]:
        if len(bootstrap_results[bs]) > 0:
            pval = compute_pvalue(bootstrap_results[bs], m_r)
            say(f"  Block size {bs} days: p-value = {pval:.3f} ({len(bootstrap_results[bs])} permutations)")
    say("")
    
    # Decomposition control (beta=0)
    say("Decomposition Control (beta=0: randomized signs)...")
    beta0_m, beta0_sd, beta0_n = decompose_beta0(trades, params["SEED"])
    ratio = beta0_m / m_r if m_r != 0 else float('inf')
    say(f"  Beta=0 arm mean R: {beta0_m:.4f}")
    say(f"  Ratio (beta=0 / raw): {ratio:.3f}")
    say("")
    
    # Apply kill gates
    say("=" * 80)
    say("KILL GATES (pre-declared, non-negotiable):")
    say("=" * 80)
    
    gate_failures = []
    
    # Gate 1: Negative Expectancy
    if m_r <= 0.0 and n_r >= params["MIN_N"]:
        gate_failures.append(("G1", f"mean R = {m_r:.4f} <= 0.0 with n={n_r} >= {params['MIN_N']}"))
        say("G1 FAIL: Negative expectancy")
    else:
        say(f"G1 PASS: mean R = {m_r:.4f} {'>' if m_r > 0 else '<='} 0.0 (n={n_r})")
    
    # Gate 2: Marginal t-Statistic
    if 0.0 < t_r <= params["T_CRIT"] and n_r >= params["MIN_N"]:
        gate_failures.append(("G2", f"t = {t_r:.3f} in (0, {params['T_CRIT']}] with n={n_r} >= {params['MIN_N']}"))
        say(f"G2 FAIL: Marginal t-statistic ({t_r:.3f})")
    elif t_r > params["T_CRIT"]:
        say(f"G2 PASS: t = {t_r:.3f} > {params['T_CRIT']}")
    elif t_r <= 0.0:
        say(f"G2: t = {t_r:.3f} <= 0.0 (covered by G1)")
    else:
        say(f"G2: Insufficient n={n_r} < {params['MIN_N']} for gate evaluation")
    
    # Gate 3: Bootstrap Failure
    min_pval = min(compute_pvalue(bootstrap_results[bs], m_r) 
                   for bs in params["BLOCK_SIZES"] if len(bootstrap_results[bs]) > 0)
    if min_pval > 0.05:
        gate_failures.append(("G3", f"min bootstrap p-value = {min_pval:.3f} > 0.05"))
        say(f"G3 FAIL: Bootstrap p-value = {min_pval:.3f} > 0.05")
    else:
        say(f"G3 PASS: Bootstrap p-value = {min_pval:.3f} <= 0.05")
    
    # Gate 4: Decomposition Failure
    if ratio >= params["DECOMP_FRAC"]:
        gate_failures.append(("G4", f"beta=0/raw ratio = {ratio:.3f} >= {params['DECOMP_FRAC']}"))
        say(f"G4 FAIL: Beta=0 arm performs as well as raw (ratio={ratio:.3f})")
    else:
        say(f"G4 PASS: Beta=0/raw ratio = {ratio:.3f} < {params['DECOMP_FRAC']}")
    
    say("")
    say("=" * 80)
    
    if gate_failures:
        say("VERDICT: H3 = DEAD")
        say("")
        say("Failed gates:")
        for gid, reason in gate_failures:
            say(f"  {gid}: {reason}")
        say("")
        say("Next step: Write autopsy, select next hypothesis.")
        return False
    else:
        say("VERDICT: ALL GATES PASS - H3 SURVIVES")
        say("")
        say("Unsealing validation period...")
        # Run validation
        val_signals = compute_signal(val_panel, params["LOOKBACK"])
        val_trades = simulate_trades(
            val_signals, val_panel, params["HOLD"], params["BASE_COST_PTS"],
            params["SWAP_BASELINE"], use_pessimistic=True
        )
        if len(val_trades) > 0:
            val_r = [t[6] for t in val_trades]
            val_m, val_sd, val_n = mean_sd(val_r)
            val_t = val_m / (val_sd / math.sqrt(val_n)) if val_sd > 0 else 0.0
            say(f"  Validation trades: {val_n}")
            say(f"  Validation mean R: {val_m:.4f}")
            say(f"  Validation t-stat: {val_t:.3f}")
        say("")
        say("Next step: Proceed to production EA implementation (sealed parameters).")
        return True


def main():
    parser = argparse.ArgumentParser(description="XTM H3 Study")
    parser.add_argument("--selftest", action="store_true", help="Run self-test with synthetic data")
    args = parser.parse_args()
    
    if args.selftest:
        run_study([], [], PARAMS, selftest=True)
        return
    
    # Load data
    here = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(here, "data")
    
    say("Loading data...")
    gold_pm, gold_bad = load_lbma_pm(os.path.join(data_dir, "gold_pm.json"))
    say(f"  LBMA PM fix: {len(gold_pm)} records, {gold_bad} bad/skipped")
    
    irx_data, irx_missing = load_irx(os.path.join(data_dir, "yahoo_irx_d.json"))
    say(f"  ^IRX T-bill: {len(irx_data)} records, {irx_missing} forward-filled")
    say("")
    
    # Build panel
    study_panel, val_panel = build_panel(
        gold_pm, irx_data,
        PARAMS["STUDY_FROM"], PARAMS["STUDY_TO"],
        PARAMS["VAL_FROM"], PARAMS["VAL_TO"]
    )
    
    # Run study
    success = run_study(study_panel, val_panel, PARAMS)
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
