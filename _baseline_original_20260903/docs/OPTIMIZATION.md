# Optimization Guide

Optimising is easy. Optimising without fooling yourself is the hard part, and it is what
this subsystem is built for.

## The problem being solved

Ask the tester to maximise net profit across a parameter grid and it will reliably hand
back the set that best fits the noise in your sample. It will show a large profit, a
brutal drawdown, and one trade carrying most of the result. Then it will lose money live.

Scalping Robot Pro ships four defences:

1. **A composite criterion** that penalises the shapes that do not survive.
2. **A parameter screen** that skips incoherent combinations before they cost time.
3. **Walk-forward analysis** that asks whether an edge survives out of sample.
4. **Monte Carlo simulation** that asks what else could have happened.

## Running an optimisation

1. Strategy Tester → **Optimization: Genetic algorithm**.
2. **Criterion: Custom max** — this routes ranking through `OnTester` and is what
   activates the composite criterion. Without it you are optimising net profit again.
3. On the Inputs tab, tick the parameters to vary and set start / step / stop.
4. Start.

Measured reference: 1,176 passes across 12 agents on one month of M1 gold completed in
about ten minutes.

### What to vary, and what not to

Vary few things. Each added dimension multiplies the search space and the opportunity to
fit noise.

Reasonable first pass:

```
InpFastMaPeriod     5  →  15  step 2
InpSlowMaPeriod    18  →  36  step 3
InpTpRiskReward   1.2  → 2.4  step 0.2
InpRiskPercent   0.25  → 1.0  step 0.25
```

Do **not** optimise:

- **Risk limits.** Daily loss, drawdown, exposure ceilings. These are risk policy, not
  parameters. Optimising them means selecting the sample where the safety net was never
  needed.
- **The kill switch.**
- **News windows.** Set from how your instrument actually reacts, not from what scored
  best on one sample.
- **Dashboard and logging.** No effect on results, only on speed.

## The composite criterion

Selected by `InpOptCriterion`. Options: net profit, profit factor, expectancy, Sharpe,
recovery factor, and the custom composite (default).

The composite starts from risk-adjusted return and applies three penalties:

| Penalty | Weight input | What it punishes |
|---|---|---|
| Drawdown | `InpOptDrawdownPenalty` | Deep equity troughs |
| Concentration | `InpOptConcentrationPenalty` | One trade carrying the profit |
| Streak | `InpOptStreakPenalty` | Long losing runs relative to trade count |

Set a weight to 0.0 to disable a penalty, above 1.0 to sharpen it.

Passes with fewer than `InpOptMinTrades` trades (default 30) are rejected outright rather
than ranked. A six-trade fluke cannot top the table.

### Why this is not a matter of taste

Two passes from the project's own verification suite:

| | Curve-fitted | Stable |
|---|---|---|
| Trades | 35 | 140 |
| Net profit | 5,000 | 2,500 |
| Max drawdown | 40% | 7% |
| Largest win as share of net | 84% | 16% |
| Worst losing streak | 9 | 5 |

On net profit the curve-fitted set wins by 2x. On the composite criterion the stable set
ranks higher. Both orderings are asserted in the integration harness, so the claim is
tested rather than argued.

The first set is what optimising on profit selects. The second is what you would rather
have traded.

## The parameter screen

`InpOptRejectIncoherent` (default true). During an optimisation, sets that cannot produce
a meaningful result are rejected in `OnInit` with `INIT_PARAMETERS_INCORRECT`, so the
tester discards them instead of spending minutes simulating them.

Rejected shapes include:

- Fast MA period at or above slow MA period — the most common wasted pass in a two-MA grid
- Take profit inside the spread — unreachable by construction
- Per-trade risk at or above the daily loss cap — one loss ends every day

Measured: 168 of 1,176 passes were rejected by the minimum-trade gate in a reference run.

## Walk-forward analysis

The single most useful check available, and the one that separates an edge from a
coincidence.

The idea: optimise on a window, then measure on the *next* window that the optimiser never
saw. Repeat, rolling forward. Walk-forward efficiency is out-of-sample performance divided
by in-sample performance.

| Efficiency | Reading |
|---|---|
| > 0.7 | Robust |
| 0.5 – 0.7 | Acceptable |
| 0.3 – 0.5 | Weak; likely partly fitted |
| < 0.3 | Curve-fitted. Discard. |

Efficiency near or above 1.0 is not a triumph — it usually means the windows overlap or
the sample is too small to distinguish.

Configure with `InpOptWfIsDays` (default 90), `InpOptWfOosDays` (default 30) and
`InpOptWfMinEfficiency` (default 0.5). The analyzer also requires a minimum number of
out-of-sample trades per window and *excludes* thin windows rather than averaging them in —
a window with three trades tells you nothing and must not dilute the verdict.

The verdict is explicit. From the verification suite, a set with strong in-sample scores
and no out-of-sample edge is reported as:

```
curve-fitted: in-sample brilliance, no out-of-sample edge
```

## Monte Carlo simulation

Your backtest is one ordering of your trades. Monte Carlo resamples that distribution
thousands of times to ask what else the same edge could plausibly have produced.

Enable with `InpOptMonteCarloEnabled`. It runs on a single backtest, never per
optimisation pass — a thousand extra simulations per pass would dominate run time, and the
integration enforces that itself.

| Input | Default | Meaning |
|---|---|---|
| `InpOptMonteCarloRuns` | 1000 | Simulated equity paths |
| `InpOptMonteCarloSeed` | 0 | 0 = random; fixed = reproducible |
| `InpOptMonteCarloRuinPercent` | 30 | Drawdown counted as ruin |

Outputs: probability of profit, risk of ruin, median and worst-case drawdown, and
percentile bands on final equity.

**Risk of ruin is the number that matters.** A system with positive expectancy and a 20%
risk of ruin is not tradeable at that size. Halve the risk and re-run.

Set a fixed seed when reporting a result to someone else; the harness asserts that the
same seed reproduces the same risk of ruin.

## Reading the exported CSV

One row per pass. Columns:

```
timestamp, symbol, timeframe, fitness, trades, wins, losses, win_rate,
net_profit, gross_profit, gross_loss, profit_factor, expectancy, payoff_ratio,
largest_win, largest_loss, max_dd_money, max_dd_percent, recovery_factor,
sharpe, max_con_wins, max_con_losses, max_con_loss_money
```

During a multi-agent optimisation each agent writes into its own sandbox:

```
<terminal>\Tester\Agent-127.0.0.1-300N\MQL5\Files\ScalpRobotPro\Optimization\
```

Concatenate them; headers are identical. A 1,176-pass reference run produced exactly
1,176 data rows across twelve files.

`fitness = -1000000` marks a pass rejected by the minimum-trade gate.

A note on the streak columns: `max_con_wins` and `max_con_losses` are **counts**, and
`max_con_loss_money` is the currency lost in the worst run. MQL5's `STAT_MAX_CONWINS`
is the *money* of the longest winning streak, not its length — an easy confusion that
once exported a 56-trade pass as having 360 consecutive wins, and fed that figure into
the streak penalty. The counts come from `STAT_MAX_CONPROFIT_TRADES` and
`STAT_MAX_CONLOSS_TRADES`.

## A workable procedure

1. Pick one instrument and one timeframe.
2. Choose at most four parameters.
3. Genetic optimisation, Custom max criterion, on the in-sample period.
4. Take the top ten by fitness — not the single best. The best is the most likely to be
   fitted.
5. Discard any with drawdown you could not hold, or a dominant single trade.
6. Walk-forward the survivors. Keep those above 0.5 efficiency.
7. Monte Carlo the finalist. Check risk of ruin at intended size.
8. Forward test on demo for two to four weeks.
9. Only then go live, at minimum size.

Steps 6 through 8 are the ones that get skipped, and they are the ones that matter.

## Honest limits

- Optimisation cannot find an edge that is not there. It can only tune one that is.
- Any result from a single instrument over a single year is one observation.
- Re-optimising whenever performance dips is just fitting the recent past. Decide in
  advance how often you will re-optimise, and stick to it.
- The tester cannot model your broker's behaviour at the cash open, requotes, or a
  weekend gap. Demo forward testing is not optional.

---

Optimised parameters describe the past. Trading involves substantial risk of loss.
