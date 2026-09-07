# Scalping Robot Pro — MQL5 Expert Advisor

A modular, SOLID MetaTrader 5 scalping robot. 212 files, ~47,900 lines, 19 interfaces,
one ordered decision pipeline.

**Status: production release.** Compiles with zero errors and zero warnings across all 17
targets, passes 74 runtime assertions, and has been verified end to end against a live
terminal — backtested on two instruments and run through a 1,176-pass genetic optimisation
with no runtime faults.

Tuned for NASDAQ scalping on M1–M5, instrument-agnostic by construction: every distance is
expressed in points, so switching instrument is a preset change rather than a code change.

---

## Quick start

```
MQL5\Include\ScalpRobotPro\  ->  <Terminal Data Folder>\MQL5\Include\ScalpRobotPro\
MQL5\Experts\ScalpRobotPro\  ->  <Terminal Data Folder>\MQL5\Experts\ScalpRobotPro\
MQL5\Scripts\ScalpRobotPro\  ->  <Terminal Data Folder>\MQL5\Scripts\ScalpRobotPro\
```

Open `ScalpRobotPro.mq5` in MetaEditor and press F7. Expect `0 errors, 0 warnings`.

Then **verify before trading**. Attach `Scripts\ScalpRobotPro\P6ProductionCheck` to any
chart:

```
SRP_RESULT CHECKS=74 FAILED=0 VERDICT=PASS
```

Full detail in [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Documentation

| Document | Read it for |
|---|---|
| [INSTALLATION](docs/INSTALLATION.md) | Setup and first-run verification |
| [DEPLOYMENT](docs/DEPLOYMENT.md) | The staged path to live trading |
| [BACKTESTING](docs/BACKTESTING.md) | Producing a backtest that means something |
| [OPTIMIZATION](docs/OPTIMIZATION.md) | Optimising without fooling yourself |
| [USER_MANUAL](docs/USER_MANUAL.md) | Every input, and when to change it |
| [PROJECT_ARCHITECTURE](docs/PROJECT_ARCHITECTURE.md) | The system as built |
| [DEVELOPER](docs/DEVELOPER.md) | Extending it, and the traps in it |
| [API](docs/API.md) | Public class surfaces |
| [RELEASE_NOTES](docs/RELEASE_NOTES.md) | What changed and what was found |

Phase design documents — `ARCHITECTURE`, `MARKET_INTELLIGENCE`, `DECISION_ENGINE`,
`TRADING_ENGINE`, `TRADER_INTERFACE` — remain as the record of how each layer was designed.

## Decision flow

```
OnTick
 ├─ throttle              (disabled in the tester; it measures real time)
 ├─ manage open positions (runs even when entries are forbidden)
 └─ entry pipeline:
      1 snapshot  2 indicators  3 regime  4 risk gate
      5 decide (session → news → strategies → confirmation → vote)
      6 size and protect   7 execute   8 render
```

Management before entry is deliberate: an engine that hunts a new signal before trailing an
open winner will, on a fast tick, add risk while existing risk sits unprotected.

The risk stage re-verifies risk *after* broker stop-level clamping — the step most EAs omit,
and the reason a position sized for 1% can quietly risk more.

## The five ideas that make this maintainable

**One composition root.** `CProductionEngine` is the only class that says `new` on the
trading path. Read `Build()` to know everything the product is made of.

**One ordered pipeline.** `OnTickEvent` sequences eight stages and contains zero trading
rules. One screen explains the whole control flow.

**One snapshot per pass.** Otherwise strategy A reads bid at microsecond *X* and filter B
reads it at *X+n* — on M1 gold those differ, so a trade gets approved against prices that no
longer exist.

**One door to the broker.** Only the execution engine calls `OrderSend`. Substitute a
simulating executor and the whole pipeline runs offline.

**One owner per object.** Every pointer is owned and deleted, or borrowed and never deleted.
Teardown is strict reverse order.

## Compiling is not verifying

The most useful thing this project can tell you. Six defects were found in the production
phase. **Every one compiled cleanly with zero warnings:**

| Defect | Found by |
|---|---|
| Double free at teardown | Running the engine |
| Tick throttle discarding 99% of tester ticks | Noticing a 0.24 s runtime |
| News fail-safe blocking 94% of ticks | Reading the decline tally |
| Gold sizing 10x too large | Comparing against `OrderCalcProfit` |
| Wrong sizing model selected silently | Reading `model=Kelly` in a log |
| Streak stats reporting money as counts | Seeing 360 wins in 56 trades |

The sizing defect is the one worth dwelling on: a trade configured for **0.5% risk lost
5.01%**, because `SYMBOL_TRADE_TICK_VALUE` understates gold loss tenfold on this broker.
Correct textbook arithmetic, wrong answer. The engine now asks the terminal via
`OrderCalcProfit`, and the harness asserts the two agree — because that mismatch does not
throw, it just trades the wrong size.

This is why the 74-assertion runtime harness exists, and why it runs both as a chart script
and as a tester-launchable EA.

## When it does not trade

Always explained. Any run that takes no entries prints a tally naming the gate that refused:

```
declines by reason: NO_SIGNAL=98259 SESSION_BLOCKED=6424 LOW_CONFIDENCE=3948
```

Most "it stopped working" reports are a session filter, a news blackout, or a guard doing
exactly what it was configured to do.

## Configuration

Thirteen groups in the terminal dialog: General · Logging · Risk · Stop Loss / Take Profit ·
Trade Management · Account Protection · Sessions & Schedule · News Filter · Market Filters ·
Strategies · Indicators · Smart Money Concepts · Dashboard · Statistics · Optimisation.

No hardcoded values downstream. Inputs stop at the boundary: they are copied once into a
sealed configuration object, and every module reads an immutable provider.

## Safety properties

Latched guards survive restarts · drawdown measured from a persisted all-time peak · volume
always rounds down · foreign positions never touched (magic **and** symbol filtered) · deal
tickets deduplicated · stop-level clamping centralised · broker filling mode resolved rather
than assumed · all price arithmetic tick-size aware · config contradictions abort `OnInit` ·
wiring verified at startup · kill switch clears only by human action · optimisation runs
never polluted by persisted state.

News deserves a specific note: when the calendar is unreachable the behaviour is an
**explicit configured choice**, never an accident of control flow. A news filter that
silently degrades to "allow everything" is worse than none, because you believe you are
protected. In the tester, where the calendar is structurally unusable without look-ahead
bias, the run states plainly that news is not modelled instead of silently declining every
trade.

## Requirements

MetaTrader 5 build 3000+ · MQL5 with `interface` support · hedging or netting accounts.

## Verified

| Check | Result |
|---|---|
| Compile, all 17 targets | 0 errors, 0 warnings |
| Integration harness, EURUSD and XAUUSD | 74 assertions, 0 failures |
| Backtest EURUSD M1, one month | 33 trades, 4.87% max DD, no faults |
| Backtest XAUUSD M1, one month | 50 trades, 1.67% max DD, no faults |
| Genetic optimisation | 1,176 passes, 91 distinct fitness values, no faults |
| Memory | No leaked-object or invalid-pointer reports |

Both backtests are one month on a demo feed. They demonstrate the system runs correctly end
to end. They are **far too short to indicate an edge** and are not performance claims.

Index symbols were unavailable on the test feed, so the NASDAQ-tuned defaults were verified
on gold as a proxy — high volatility, 2-digit quoting, large point values. Validate on your
own instrument before trading it.

---

Trading involves substantial risk of loss. No amount of testing removes it. Validate any
configuration on a demo account before committing real capital.
