# Release Notes

## 1.00 — Production release

First release in which the shipped Expert Advisor compiles, runs, and has been verified
against a live terminal rather than only against a compiler.

### Headline

Before this phase the product did not build. The entry point targeted the Phase 1
architectural scaffold, whose method bodies were intentionally left as declarations, while
the fully implemented stack built in Phases 2–5 sat unreachable behind it.

| | Before | After |
|---|---|---|
| Compile errors | 101 | 0 |
| Compile warnings | 21 | 0 |
| Entry points producing `.ex5` | 13 of 15 | 17 of 17 |
| Runtime assertions | none | 74, all passing |
| Verified backtest | none | EURUSD and XAUUSD, no faults |
| Verified optimisation | none | 1,176 genetic passes, no faults |

`CProductionEngine` (1,316 lines) had never been included by any compiled target. Forcing
it through the compiler surfaced 19 errors immediately; running it surfaced six more that
no compiler could have found.

---

### Defects found and fixed

Every one of these compiled cleanly with zero warnings. They were found by running the
code.

**Double free at teardown.** `CProductionEngine::Release` deleted the sizer, limit guard
and protection manager, and also the risk engine that owns all three. Surfaced as
`invalid pointer access` on the first genuine teardown. The fix makes the ownership
asymmetry explicit and handles the construction-failure path, so each pointer is freed
exactly once either way.

**Tick throttle starved the Strategy Tester.** `InpTickThrottleMs` gates the pipeline on
*real* elapsed time. A backtest replays a month in seconds, so a 250 ms gate rejected
almost every simulated tick: 124,635 ticks processed in 0.24 s with **zero trades**, and a
clean "Test passed". A throttle that changes how many bars a strategy sees is not a
performance control, it is a correctness bug. Now disabled in the tester.

**News fail-safe blocked 94% of backtest ticks.** The calendar is deliberately unavailable
in the tester (it returns today's events regardless of the simulated bar, which would be
look-ahead bias). With no CSV supplied the source could never become available, so the
fail-safe blocked everything: 117,742 of 124,635 ticks declined as `NEWS_BLOCKED`. The
policy is now environment-aware — fail closed live, and in the tester fail closed only when
a CSV was actually supplied and failed to load. When news cannot be modelled the run says
so plainly rather than silently trading nothing.

**Gold position sizing was 10x too large.** Money-per-lot was derived from
`SYMBOL_TRADE_TICK_VALUE`. This broker reports XAUUSD with `tick_size` 0.01 and
`tick_value` 0.10 against a 100 oz contract, understating real loss tenfold. Measured
consequence: a trade configured for **0.5% risk lost 5.01%** and tripped the daily loss
guard on a single position. Now obtained from the terminal's `OrderCalcProfit`, which
prices the fill with the same code the broker uses.

Effect on the same one-month gold backtest:

| | Before | After |
|---|---|---|
| Trades | 1 | 50 |
| Max drawdown | 5.01% | 1.67% |
| Worst loss | 5.01% | ~0.5% (as configured) |
| `OnTester` fitness | rejected | 0.735 |

**Wrong sizing model selected silently.** `ENUM_SRP_RISK_MODE` and
`ENUM_SRP_SIZING_MODEL` both describe sizing and number their members differently — value 3
means percent-of-equity in one and Kelly in the other — yet both were stored under the same
config key. The preset requested percent-of-equity and the engine built a **Kelly** sizer,
which then refused all 28 valid signals for want of a sample and reported zero trades with
no error. The snapshot field is now typed as the sizing enum so a mismatch is a compile
error, and the startup log prints the model by name.

**Streak statistics reported money as counts.** `STAT_MAX_CONWINS` is the *profit* of the
longest winning streak, not its length. Using it exported a 56-trade pass as having 360
consecutive wins and −221 consecutive losses, and fed those figures into the optimisation
criterion's streak penalty — so passes were ranked partly on a number denominated in
currency. Counts now come from `STAT_MAX_CONPROFIT_TRADES` and `STAT_MAX_CONLOSS_TRADES`,
with streak money kept in its own column.

**Trade duration and R-multiple were always zero.** The engine never populated `open_time`
on closed trades, so two analytics silently reported nothing. Now read from the position's
opening deal, with risk priced through the same conversion used to size the trade.

**Broker-relative validation was skipped.** No symbol specification was supplied to the
validator, so stop-level, volume-step and trade-mode rules reported as skipped. A stop
inside the broker minimum would have passed validation and failed later at `OrderSend`. The
entry point now resolves the spec at init.

---

### Added

**Production integration harness.** 74 runtime assertions covering the configuration round
trip, validation, the full engine lifecycle, and the optimisation engine. Runs two ways
from one shared body — as a chart script, and as a tester-launchable EA so runtime
verification can be automated from a command line. It never sends an order: the engine is
halted before ticking, so `OrderSend` is unreachable by construction.

The most valuable single assertion compares money-per-lot against `OrderCalcProfit`. That
mismatch does not throw; it just trades the wrong size.

**Decline diagnostics.** The decision engine now keeps a per-reason tally, and any run
that takes no entries explains itself:

```
declines by reason: NO_SIGNAL=98259 SESSION_BLOCKED=6424 LOW_CONFIDENCE=3948
```

"It never traded" was the most common question with no honest answer. Now it has one.

**`OnTester` wired end to end.** The optimisation criterion, Monte Carlo simulator and
tester integration are constructed by the engine and reachable from the terminal's
optimiser. Verified: 1,176 genetic passes, 1,008 ranked across 91 distinct fitness values,
168 correctly rejected by the minimum-trade gate.

**New configuration keys.** Capital base, Kelly minimum sample, auto-lot ratios, minimum
lot, state folder, and total exposure ceiling — closing gaps where a subsystem previously
had no configurable input.

**Build and verification tooling.** `_build\build.ps1`, `test.ps1`, `backtest.ps1`,
`optimize.ps1`.

**Documentation.** Installation, Deployment, Backtesting, Optimization, User Manual,
Developer, API, Project Architecture, and these notes.

---

### Removed

About 2,400 lines that could never run. Every item was flagged in the phase design
documents.

| File | Lines | Reason |
|---|---|---|
| `Trade\Engine\CPositionController.mqh` | 903 | Parallel position stack; 102 compile errors; duplicated `CEnginePositionManager` |
| `Trade\Engine\CPositionRegistry.mqh` | 559 | Query half of the same dead stack |
| `Decision\Types\DecisionTypes.mqh` | 390 | Duplicated struct names from the live `DecisionStructs.mqh`; included nowhere |
| `Experts\EngineCompileTest.mq5` | 146 | Stale API, 100 errors; superseded by `EngineCompileCheck` |
| `Trade\Engine\TradeEngine.mqh` | 68 | Sub-umbrella for the deleted stack only |
| `Utilities\CJsonStateStore.mqh` | 76 | Declaration-only; superseded by `CRiskStateStore` |
| `ScalpingRobotPro\…\SRPVersion.mqh` | 43 | Orphaned; redefined `SRP_PRODUCT_NAME` |

---

### Changed

**The umbrella header is now the implemented stack.** `ScalpRobotPro.mqh` includes the
production path in twelve dependency-ordered layers and deliberately **excludes** the
Phase 1 scaffold. MQL5 links a body only when a function is called, so including bodiless
declarations compiles but breaks the moment a consumer touches one — a trap rather than a
convenience. Every base class, interface and DTO the scaffold defines is live and included.

**The entry point drives `CProductionEngine`.** It now populates and seals configuration,
validates it, screens incoherent optimisation passes, resolves the broker spec, and
forwards terminal events. Still an adapter with no trading logic.

**Configuration reporting.** The startup log names the sizing model instead of printing an
integer — a bare number is what let the vocabulary mismatch hide in plain sight.

---

### Verified

| Check | Result |
|---|---|
| Compile, all 17 targets | 0 errors, 0 warnings |
| Integration harness, EURUSD | 74 assertions, 0 failures |
| Integration harness, XAUUSD | 74 assertions, 0 failures |
| Backtest EURUSD M1, one month | 33 trades, 4.87% max DD, no faults |
| Backtest XAUUSD M1, one month | 50 trades, 1.67% max DD, no faults |
| Genetic optimisation, 1,176 passes | No faults; 91 distinct fitness values |
| Memory | No leaked-object or invalid-pointer reports |
| CSV export | 1,176 rows across 12 agent sandboxes |

Both backtests are one month on a demo feed. They demonstrate that the system runs
correctly end to end. They are **far too short to indicate an edge**, and are not presented
as performance results.

---

### Known limitations

- **Index symbols were unavailable on the test feed.** Defaults are NASDAQ-tuned, but
  verification used EURUSD and XAUUSD. Gold is a reasonable proxy — high volatility,
  2-digit quoting, large point values — but the shipped preset has not been measured on
  US100 itself. Validate before trading it.
- **News cannot be modelled in a backtest without a CSV.** A platform constraint, not a
  bug. Backtested results are an upper bound until you supply one.
- **Optimisation CSV is written per agent sandbox.** Concatenate the files; agents cannot
  see each other's folders.
- **R-multiple is indicative when several positions are open.** Risk attribution uses the
  most recent entry stop.
- **No live-account verification.** Everything here is compiler, harness and Strategy
  Tester. Demo forward testing remains mandatory.

---

### Upgrading

If you ran an earlier build, note that `risk.mode` is now interpreted in the sizing
vocabulary. A saved `.set` file may select a different model than intended — re-check
`InpSizingModel` after upgrading, and confirm it against the startup log, which now names
the model.

State files are unchanged and carry over.

---

Trading involves substantial risk of loss. Validate on a demo account before committing
real capital.
