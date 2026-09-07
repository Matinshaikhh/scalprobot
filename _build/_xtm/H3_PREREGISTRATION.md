# XTM 0.1 — H3 Pre-Registration: Daily Gold Time-Series Momentum

**Document type:** Pre-registration (sealed design before signal computation)  
**Hypothesis ID:** H3  
**Instrument class:** XAU (gold) daily time-series  
**Data seal date:** 2026-03-01 (consistent with xtmrecon.py)  
**Pre-registration date:** [TO BE FILLED — upon document creation]  
**Author:** ScalpRobotPro Research  

---

## 0. Executive Summary

This document pre-registers the **first decisive falsification test** of H3: that daily gold returns exhibit time-series momentum sufficient to generate positive expectancy after realistic costs over a medium-term holding period.

**Critical finding from reconnaissance:** H3 is NOT yet a hypothesis — it is a question. The `xtmrecon.py` script correctly computed data integrity, coverage, and statistical power, but deliberately computed NO signal, NO serial dependence statistic, and NO P&L. This pre-registration converts the question into a testable hypothesis with fixed gates.

**Verdict up front:** If H3 cannot survive this pre-registration due to instrument/carry/data limitations, it will be killed and replaced by a different hypothesis. No optimization, no curve-fitting, no parameter sweeping.

---

## 1. Executable Instrument Resolution

### 1.1 The Problem

LBMA PM fix is **not directly tradable**. It is an auction reference price, not an executable venue. A pre-registered study must specify what instrument executes the signal, because costs differ materially:

| Instrument | Swap/Carry | Spread (realistic) | Commission | Basis Risk |
|------------|-----------|-------------------|------------|------------|
| XAUUSD CFD (MetaQuotes Demo) | 0.00 (demo), unknown live | 13–17 pts median, stressed to 20–26 pts | 0 (demo), ~7 pts RT pessimistic | None (same symbol) |
| COMEX GC Futures | Embedded in term structure | ~0.1–0.2% bid-ask | Exchange + broker fees | N/A (this IS the futures price) |
| Spot gold via other venue | Broker-specific | Venue-specific | Venue-specific | None |

### 1.2 Evidence from Repository

**AUDIT.md section 7.3** explicitly addresses this:
> "Do NOT integrate [futures] yet. Only justified if a validated harness shows edge limited by inability to see aggressive volume."

**xtmcross.py findings:**
- LBMA PM fix vs COMEX GC correlation = 0.734 at 1-day horizon
- Correlation rises to 0.99+ at 60-day horizon following the offset model exactly
- Median basis = -2 bp, drifts smoothly with rates (cost-of-carry, not defect)
- **Verdict:** Same asset, different sampling times (PM fix = 15:00 London / 10:00 NY; GC close = 17:00 NY)

**Swap evidence:**
- EA code reads `SYMBOL_SWAP_LONG` and `SYMBOL_SWAP_SHORT` but never USES them in decision logic
- Demo account shows swap = 0.00 in all backtest reports
- AUDIT.md: "Commission and swap are 0.00 in every report on this demo account"
- **No live-account swap specification exists in this repository**

### 1.3 Resolution

**Primary instrument for H3 test: XAUUSD CFD on MetaQuotes-Demo feed**, with the following explicit caveats:

1. **Swap modeling:** Since live swap rates are unknown, the study will compute results under THREE cost scenarios:
   - **Zero-swap baseline:** swap_long = swap_short = 0.00 (demo reality)
   - **Pessimistic stress:** swap = ±0.50 USD per lot per night (to be sourced from public broker spec sheets post-study)
   - **Break-even bound:** maximum swap consistent with passing the kill gates

2. **Spread stress:** Use the AUDIT.md observed real-tick median of 13.7 points, stressed by 1.5× = **20.5 points round-trip entry/exit cost**. This is the same stress factor used in xspresidual.py.

3. **Commission:** Add **7 points round-trip** as a pessimistic commission model (consistent with xspresidual.py).

4. **Total cost per round-trip:** 20.5 (spread stress) + 7.0 (commission) = **27.5 points base cost**, plus swap × holding days.

**Rationale:** XAUUSD CFD is the only instrument with existing infrastructure in this repository. If H3 shows edge under these costs, futures integration can be justified. If H3 dies here, no amount of futures sophistication would have saved it.

---

## 2. Data Specification

### 2.1 Primary Price Series

**Source:** LBMA Gold Price PM fix (USD), merged with AM fix where PM unavailable  
**Coverage:** 1972-01-03 to 2026-02-27 (post-float, pre-seal)  
**Observations:** n = 13,692 days  
**Span:** 54.2 years  
**File:** `_build/_xtm/data/gold_pm.json` (verified by xtmrecon.py)

### 2.2 Carry Series

**Source:** Yahoo Finance ^IRX (13-week T-bill discount rate)  
**Coverage:** 1970-01-02 to 2026-02-27  
**Missing days:** 372 of 13,692 (2.72%) — forward-filled per xtmrecon.py convention  
**File:** `_build/_xtm/data/yahoo_irx_d.json`

### 2.3 Seal

**Withheld validation period:** 2026-03-01 onward (130 observations)  
**Contamination declaration:** Per xtmrecon.py, the author has seen the tail of the fetched data and knows the approximate gold level in September 2026. Direction of knowledge is recorded here to prevent post-hoc flattering.

### 2.4 Study/Validation Split

- **Study period:** 1972-01-03 to 2016-12-31 (44.0 years, ~11,088 days)
- **Validation period:** 2017-01-01 to 2026-02-27 (9.2 years, ~2,604 days)
- **Rationale:** 80/20 split by time, not by trade count. Validation period includes the 2020 volatility regime and the 2022–2025 inflation/CTA crowding era.

---

## 3. Signal Definition (Primary Test)

### 3.1 Entry Rule

**Long signal:** Sign of past 60-day log return is positive  
**Short signal:** Sign of past 60-day log return is negative  

Formally:
```
ret_60[t] = log(P[t] / P[t-60])
position[t] = sign(ret_60[t])  # ∈ {-1, 0, +1}
```

If `ret_60[t] == 0`, position = 0 (flat).

**Rebalancing frequency:** Daily. Position is re-evaluated at each day's close using the close price. Holding period is implicitly 1 day, rolled forward if signal persists.

### 3.2 Holding Period

**Primary test holding period:** 20 calendar days

After entry at close on day `t`, exit at close on day `t+20`, regardless of intermediate price action. No stop-loss, no take-profit, no trailing — this isolates the momentum premium from exit engineering.

**Rationale for 60/20 split:**
- 60-day lookback ≈ 3 months, a standard "medium-term" momentum horizon
- 20-day hold ≈ 1 month, long enough to capture trend continuation but short enough to avoid full mean-reversion cycles
- Both are round numbers, not optimized

### 3.3 Volatility Scaling (Secondary Arm)

**Primary test uses NO volatility scaling** — raw signal only.

**Secondary arm (pre-declared, non-gating):** Inverse-60-day-volatility weighting:
```
vol_60[t] = stdev( daily log returns over [t-59, t] )
position_size[t] = target_vol / vol_60[t]
```
where `target_vol` is set to match the unconditional volatility of the raw signal arm for comparability.

**Purpose:** Tests whether risk-managed scaling improves Sharpe without altering directionality. Results are descriptive only; kill gates apply to the raw arm.

---

## 4. Cost Model

### 4.1 Explicit Costs (per round-trip)

| Component | Value | Source |
|-----------|-------|--------|
| Spread (stressed) | 20.5 points | AUDIT.md real-tick median 13.7 × 1.5 stress |
| Commission | 7.0 points | xspresidual.py convention |
| **Base cost (ex-swap)** | **27.5 points** | Sum |
| Swap (baseline) | 0.00 / day | Demo account observation |
| Swap (pessimistic) | ±0.50 / day | To be sourced post-study |

**Point value:** 1 point = 0.01 USD/oz, 1 lot = 100 oz → $1.00 per point per lot (AUDIT.md verified)

**Cost in return terms:** Convert points to log returns using the entry price:
```
cost_return[t] = log( (P[t] - 27.5) / P[t] )  # for long
```
For short, invert the sign. Over 20 days, cumulative cost = base cost + 20 × daily swap.

### 4.2 Carry Adjustment

Gold pays no dividend. A long position implicitly foregoes the cash rate. The study will compute TWO return series:

1. **Price returns:** log(P_exit / P_entry) — ignores carry
2. **Excess returns:** log(P_exit / P_entry) - (IRX_rate / 252) × holding_days

**Primary gate uses excess returns.** A "risk premium" that vanishes after subtracting the cash rate is not a premium — it is the risk-free rate misattributed to skill.

---

## 5. Metrics (Pre-Declared)

### 5.1 Primary Metric

**Expectancy in R per trade**, net of pessimistic cost (27.5 points + swap).

Definition:
```
R_per_trade = (exit_return - entry_return - cost) / σ_entry
```
where `σ_entry` is the 60-day annualized volatility at entry (for scaling to R units).

**Why R?** Makes the metric comparable across regimes and to the XSP studies (which used R-normalized exits).

### 5.2 Secondary Metrics (Descriptive Only)

- Annualized Sharpe ratio (excess returns)
- Maximum drawdown (peak-to-trough, cumulative returns)
- Win rate (% trades > 0 R)
- Average trade duration (days)
- Turnover (trades per year)

### 5.3 Control: Block Bootstrap

**Method:** Non-overlapping block bootstrap with block sizes [20, 60, 120] days.

**Purpose:** Preserve serial structure while destroying any momentum signal. Generate null distribution of mean(R) under the hypothesis "no serial dependence".

**Block counts (from xtmrecon.py):**
- 20-day blocks: 684 blocks in study set
- 60-day blocks: 228 blocks
- 120-day blocks: 114 blocks

**Permutations:** 200 (consistent with xspresidual.py default)

---

## 6. Kill Gates (Pre-Declared, Non-Negotiable)

H3 is declared **DEAD** if ANY of the following conditions hold in the STUDY period:

### Gate 1: Negative Expectancy
```
mean(net R per trade) ≤ 0.0    AND    n_trades ≥ 200
```
Minimum 200 trades ensures the result is not a small-sample artefact.

### Gate 2: Marginal t-Statistic
```
0.0 < t_stat ≤ 2.0    AND    n_trades ≥ 200
```
Where `t_stat = mean(R) / (sd(R) / sqrt(n))`. A t below 2.0 is not statistically distinguishable from zero at conventional levels.

### Gate 3: Bootstrap Failure
```
p_value(block_bootstrap) > 0.05
```
Where p-value is the fraction of permuted datasets yielding mean(R) ≥ observed mean(R). If the observed result is not in the top 5% of the null distribution, it is not robust.

### Gate 4: Decomposition Failure
```
beta=0 arm mean(R) ≥ 1.0 × raw_arm mean(R)
```
Test: Randomize the sign of the signal (preserve magnitude, destroy direction). If the randomized arm performs as well as or better than the directional signal, the direction carries no information.

### Gate 5: Cross-Instrument Failure (Future Work)
NOT APPLICABLE to this pre-registration. Reserved for future panel testing across FX, equity, energy, metals (non-gold), and rates using the fetch_panel.sh infrastructure.

---

## 7. Underpower Declaration

From xtmrecon.py:
```
Full study span: 54.2 years
Minimum detectable Sharpe Ratio at t=2.0: SR = 0.27
Literature prior for commodity momentum: SR ~ 0.2–0.4
```

**Explicit declaration:** This study is powered to the EDGE of the expected effect size. A "significant" result with t ≈ 2.0–3.0 is NOT a discovery — it is the boundary of resolvability. Conversely, a non-significant result does not prove absence of edge; it may reflect insufficient power.

**Mitigation:** If the study yields 0 < t ≤ 2.0, declare INCONCLUSIVE rather than DEAD. Do NOT loosen gates. Do NOT optimize parameters. Extend the study by waiting for more data (calendar time) or by switching to a higher-frequency instrument (if justified by a separate hypothesis).

---

## 8. Predicted Failure Modes (Pre-Declared)

The following failure modes are anticipated. If H3 dies, the autopsy should check these first:

1. **Post-2010 degradation:** CTA crowding may have arbitraged away simple momentum signals. Expect Sharpe to decline in the validation period (2017–2026) relative to study (1972–2016).

2. **Low-volatility whipsaw:** Momentum strategies underperform in range-bound, low-vol regimes. The 2010s may be a graveyard for this signal.

3. **Swap bleed:** If live swap rates are significantly positive for longs (contango), a long-biased momentum strategy may die from carry costs even if price returns are positive.

4. **Sign flip risk:** Momentum can reverse abruptly. A 20-day hold may capture the reversal rather than the continuation if the lookback is too slow.

---

## 9. Implementation Plan (Sealed)

### 9.1 File Creation

Create `_build/_xtm/xtmstudy.py` with the following constraints:

1. **NO parameter search.** All constants (60, 20, 27.5 points, etc.) are hardcoded from this document.

2. **Output format:** Print study-period results ONLY. Validation period is computed but NOT printed until study gates pass.

3. **Bootstrap control:** Implement block bootstrap with seed=20260907 (date of pre-registration) for reproducibility.

4. **No look-ahead:** All calculations must be strictly causal. No future price information may influence entry.

### 9.2 Execution Sequence

1. Run `python xtmrecon.py` — verify data integrity (already done)
2. Run `python xtmcross.py` — verify instrument identity (already done)
3. Create `xtmstudy.py` — implement pre-registered rules
4. Run `python xtmstudy.py` — compute study-period results
5. Compare against kill gates
6. If ALL gates pass: unseal validation period, print full results
7. If ANY gate fails: declare H3 DEAD, write autopsy, select next hypothesis

---

## 10. Contamination Statement

**Declared:** The author has seen the tail of the LBMA and ^IRX data files (through September 2026) during reconnaissance. The approximate level of gold and interest rates in Q2–Q3 2026 is known.

**Direction of knowledge:** [TO BE FILLED BY AUTHOR — e.g., "Gold is higher in Sept 2026 than Feb 2026; rates are lower"]

**Mitigation:** The study ends 2016-12-31. The validation period (2017–2026) is printed only if study gates pass. Knowledge of the tail cannot influence the study results if the code is written correctly.

---

## 11. Decision Tree

```
                         ┌─────────────────┐
                         │  Run xtmstudy   │
                         └────────┬────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    │                           │
           Gate 1 FAIL                  All gates PASS
        (mean R ≤ 0)                 (or 0 < t ≤ 2.0)
                    │                           │
                    ▼                           │
            ┌───────────┐                       │
            │ H3 = DEAD │                       │
            │ Autopsy   │                       │
            │ Next H    │                       │
            └───────────┘                       │
                                                │
                                    ┌───────────┴───────────┐
                                    │                       │
                              Unseal VAL              Gate 2/3/4 FAIL
                            Print full report          (marginal or
                                    │                  non-robust)
                                    │                       │
                                    ▼                       ▼
                            ┌───────────┐           ┌───────────┐
                            │ H3 = LIVE │           │ H3 = DEAD │
                            │ Proceed   │           │ (weak)    │
                            │ to G5     │           │ Next H    │
                            └───────────┘           └───────────┘
```

**G5 note:** Gate 5 (cross-instrument panel) is NOT part of this pre-registration. It is reserved for future work IF H3 survives G1–G4.

---

## 12. References

1. `xtmrecon.py` — Data reconnaissance, statistical power analysis
2. `xtmcross.py` — LBMA vs COMEX instrument identity verification
3. `AUDIT.md` — Forensic audit of Phase A, spread/stamp findings
4. `xspresidual.py` — Pre-registration template, cost conventions, bootstrap implementation
5. CHANGELOG.md — Project history, Phase A/B/C verdicts

---

## 13. Signatures

**Pre-registration author:** [ScalpRobotPro Research]  
**Date:** [2026-09-07]  
**Commit hash:** [TO BE FILLED — git commit of this document before running xtmstudy.py]

**Seal enforcement:** This document must be committed to version control BEFORE `xtmstudy.py` is created or executed. Any modification after execution invalidates the pre-registration.

---

## Appendix A: Parameter Summary Table

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Lookback (K) | 60 days | Medium-term momentum, round number |
| Hold period | 20 days | One month, round number |
| Rebalance | Daily | Close-to-close execution |
| Spread stress | 20.5 points | AUDIT.md 13.7 × 1.5 |
| Commission | 7.0 points | xspresidual.py convention |
| Base cost | 27.5 points | Sum of above |
| Swap (baseline) | 0.00/day | Demo observation |
| Swap (pessimistic) | ±0.50/day | To be sourced |
| Minimum trades | 200 | Gate threshold |
| t_crit | 2.0 | Standard significance |
| Bootstrap perms | 200 | xspresidual.py default |
| Block sizes | [20, 60, 120] days | Match hold/lookback scales |
| Seed | 20260907 | Pre-registration date |
| Study end | 2016-12-31 | 80/20 time split |
| VAL start | 2017-01-01 | Remainder |
| Seal date | 2026-03-01 | Consistent with xtmrecon.py |

---

**END OF PRE-REGISTRATION**
