# Backtesting Guide

How to produce a backtest of Scalping Robot Pro that means something, and how to
recognise one that does not.

## Setup

1. **View → Strategy Tester** (Ctrl+R).
2. Expert: `ScalpRobotPro\ScalpRobotPro`.
3. Symbol and period: your instrument on M1.
4. Date range: at least six months. Twelve is better.
5. Model: see below.
6. Deposit and leverage: match the account you intend to trade.

## Choosing a model

| Model | Speed | What it is honest about |
|---|---|---|
| Every tick based on real ticks | slowest | Everything. The only model to trust for a final result. |
| Every tick | slow | Generated ticks; intrabar shape is approximated. |
| 1 minute OHLC | fast | Bar extremes only. Fine for exploring parameters. |
| Open prices only | fastest | Almost nothing. Useful for smoke tests. |

Measured on this project: a one-month M1 run on 124,635 ticks completes in about three
seconds using 1-minute OHLC. Real ticks for the same period requires a multi-gigabyte
download first.

Use OHLC to explore. Use real ticks before believing anything.

## Two things that will silently invalidate a result

### 1. News filtering is inactive unless you supply a CSV

MQL5's economic calendar returns *today's* events regardless of which historical bar is
being simulated. Using it in a backtest is look-ahead bias, so the engine refuses and
states plainly what it is doing:

```
Scalping Robot Pro: news filtering is INACTIVE for this test. The terminal calendar
cannot be used in the tester without look-ahead bias, and no news CSV was supplied.
Results do not account for news. Set the news CSV input to model it.
```

Consequence: the backtest trades straight through releases the live robot would sit out.
Results are an upper bound.

To model news, export a CSV of historical events and set `InpNewsCsvFile`. When a CSV is
supplied and fails to load, the fail-safe blocks — because at that point the failure is
real rather than structural.

### 2. The tick throttle is disabled in the tester, deliberately

`InpTickThrottleMs` limits how often the pipeline runs, to keep CPU sane on a fast-ticking
index. It measures *real* elapsed time.

A backtest replays a month in seconds, so a 250 ms real-time gate would reject almost
every simulated tick. That is not a performance optimisation; it changes how many bars the
strategy sees. Measured before this was fixed: 124,635 ticks processed in 0.24 s with
**zero trades**, reporting a clean pass. A throttle that alters strategy input is a
correctness bug, so it is switched off in the tester and the setting only affects live
runs.

If you see a backtest finish suspiciously fast with no trades, this class of problem is
the first thing to suspect.

## Reading the output

Beyond the terminal's own report, the EA prints its own analytics:

```
ALL report XAUUSD
  trades=50 wins=37 losses=13 be=0 winRate=74.00%
  net=178.15 gross+=819.37 gross-=641.22 commission=0.00 swap=0.00
  profitFactor=1.278 expectancy=3.56 payoff=0.449 avgR=1.387
  sharpe=0.094 sortino=0.142 recovery=1.070
  avgWin=22.15 avgLoss=49.32 bestWin=80.58 worstLoss=-50.82
  maxDD=166.57 (1.67%) peak=10228.31
  duration avg=4m 53s longest=26m 40s shortest=40s
  streaks: wins=17 losses=3
```

Plus monthly and yearly breakdowns, which matter more than the total: a system that made
all its money in one month is not the same as one that ground it out across twelve.

### What to look at, in order

**Trade count.** Below thirty, stop reading. The optimisation criterion rejects such
passes outright for the same reason.

**Maximum drawdown percent.** The number that determines whether you could actually hold
the position. A 40% drawdown ends most accounts regardless of the final profit.

**Worst losing streak.** `streaks: losses=N`. Ask honestly whether you would keep the
robot running through N consecutive losses. Most people would not, which makes the
backtest's recovery hypothetical.

**Largest win as a share of net profit.** If one trade carried most of the result, the
edge is unproven. The composite criterion penalises this explicitly.

**Profit factor.** Below 1.1 is noise. Above 3.0 on a short sample usually means
curve-fitting rather than skill.

**avgR.** Average R-multiple: profit measured in units of risk actually committed. This
is derived from the real stop distance priced through the terminal, so it is comparable
across instruments in a way that currency profit is not.

## Zero trades

Always explained. The engine prints a decline tally:

```
Scalping Robot Pro: no entries were taken in this run.
  ticks=114238 managed actions=0
  decision engine: 9 plugin(s) | eval=114238 actionable=28 declined=114210
  declines by reason: NO_SIGNAL=98259 SESSION_BLOCKED=6424
                      CONFIRMATION_FAILED=5579 LOW_CONFIDENCE=3948
  risk engine: model=RiskPercent ceiling=0.50% approvals=0 rejections=28
```

Read it before changing settings.

| Dominant reason | Meaning | If it is wrong |
|---|---|---|
| `NO_SIGNAL` | No strategy saw a setup. Normal as the bulk. | Enable more strategies, or loosen their thresholds. |
| `SESSION_BLOCKED` | Outside permitted sessions. | Check session toggles and `InpBrokerGmtOffset`. |
| `NEWS_BLOCKED` | News blackout, or fail-safe with no source. | See above. |
| `LOW_CONFIDENCE` | Signals below `InpMinConfidence`. | Lower it, or reduce `InpMinConfirmations`. |
| `CONFIRMATION_FAILED` | Signal found, confirmation refused. | Inspect confirmation settings. |

If `actionable` is non-zero but `approvals=0`, the decision layer agreed and the *risk*
layer refused. Check `rejections` and the risk line: usually sizing cannot produce a legal
volume, or a guard has tripped.

## Instrument differences are real

The same configuration on two symbols is not the same test. Measured over January 2025
on M1 with shipped defaults:

| | EURUSD | XAUUSD |
|---|---|---|
| Trades | 33 | 50 |
| Win rate | 39.4% | 74.0% |
| Max drawdown | 4.87% | 1.67% |

Neither is a recommendation — one month is far too short to conclude anything. The point
is that defaults tuned for one instrument class behave differently on another, and
distances expressed in points scale very differently between a 5-digit major and a 2-digit
metal.

### A note on risk conversion

Position sizing divides by "money lost per lot if the stop is hit". Deriving that from
`SYMBOL_TRADE_TICK_VALUE` is the textbook approach and it is wrong on some instruments:
this broker reports gold with `tick_size` 0.01 and `tick_value` 0.10 against a 100 oz
contract, understating real loss tenfold.

Measured consequence before the fix: a trade configured for 0.5% risk lost **5.01%** and
tripped the daily loss guard on a single position.

The engine now asks the terminal via `OrderCalcProfit`, which prices the fill with the
same code the broker uses. The integration harness asserts the two agree, because a
disagreement here does not throw — it just trades the wrong size.

If you port this to another broker, run the integration check first. That one assertion
is the most valuable in the suite.

## Optimisation runs

Passes are exported to CSV, one row each. During a multi-agent optimisation each agent
writes into its own sandbox:

```
<terminal>\Tester\Agent-127.0.0.1-300N\MQL5\Files\ScalpRobotPro\Optimization\
```

That is a platform constraint: agents cannot see each other's folders. Concatenate the
files to analyse the whole run — headers are identical. A measured 1,176-pass run produced
exactly 1,176 data rows across twelve agent files.

Columns cover fitness, trade counts, win rate, profit factor, expectancy, payoff, largest
win and loss, drawdown in money and percent, recovery factor, Sharpe, streak counts and
the money of the worst losing streak.

## Checklist before trusting a backtest

- [ ] Real ticks, not OHLC, for the final run
- [ ] At least six months, ideally spanning different regimes
- [ ] At least thirty trades
- [ ] Deposit, leverage and account currency match the intended live account
- [ ] News modelled via CSV, or its absence explicitly accepted
- [ ] Maximum drawdown survivable at intended size
- [ ] Worst losing streak psychologically survivable
- [ ] No single trade dominating net profit
- [ ] Walk-forward efficiency above 0.5 (see `OPTIMIZATION.md`)
- [ ] Monthly breakdown reasonably consistent, not one lucky month

---

A backtest is a hypothesis, not a forecast. Past results do not indicate future
performance, and trading involves substantial risk of loss.
