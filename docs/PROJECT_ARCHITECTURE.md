# Project Architecture

The shape of the system as built and verified. `ARCHITECTURE.md` documents the original
Phase 1 reference design; this document describes what actually executes.

**212 files · ~47,900 lines · 17 compilable targets · 0 errors · 0 warnings**

---

## Layers

Dependency order, bottom-up. Each layer may use the ones below it and knows nothing of
those above.

```
┌─ 12  COMPOSITION ROOT ──────────────────────────────────────────────┐
│      Runtime\  CProductionEngine · CRuntimeConfig                   │
│      The only class that `new`s on the trading path.                │
├─ 11  OPTIMISATION ──────────────────────────────────────────────────┤
│      criterion · parameter screen · walk-forward · Monte Carlo ·    │
│      tester integration · environment guard                         │
├─ 10  TRADER INTERFACE ──────────────────────────────────────────────┤
│      enterprise logger · analytics · dashboard · chart overlay ·    │
│      trade manager                                                 │
├─  9  EXECUTION ─────────────────────────────────────────────────────┤
│      broker · execution engine · orders · positions · magic ·      │
│      CTradeEngine facade   ← the ONLY OrderSend                    │
├─  8  DECISION ──────────────────────────────────────────────────────┤
│      sessions · news · 10 strategy plugins · confirmation · vote    │
├─  7  RISK ──────────────────────────────────────────────────────────┤
│      state store · 6 sizing models · limit guard · protection ·    │
│      CRiskEngine                                                   │
├─  6  MARKET INTELLIGENCE ───────────────────────────────────────────┤
│      16 indicators · swing detector · market structure ·           │
│      zones · displacement · order blocks · liquidity               │
├─  5  CONFIGURATION ─────────────────────────────────────────────────┤
│      keys · sealed provider · validator · builder                   │
├─  4  INFRASTRUCTURE ────────────────────────────────────────────────┤
│      logger · event bus · clock · registry · state machine ·       │
│      error handler · throttle                                      │
├─  3  ABSTRACT BASES ────────────────────────────────────────────────┤
│      CModuleIdentity + 6 role bases                                 │
├─  2  UTILITIES ─────────────────────────────────────────────────────┤
│      math · string · time · price · buffer · file IO                │
├─  1  CONTRACTS ─────────────────────────────────────────────────────┤
│      19 interfaces                                                  │
└─  0  VOCABULARY ────────────────────────────────────────────────────┘
       constants · enums · DTOs
```

## The pipeline

```
OnTick
 ├─ 1 throttle              cheapest exit; disabled in the tester
 ├─ 2 refresh state         indicators, structure (bar-gated), account
 ├─ 3 manage open positions runs even while halted
 ├─ 4 risk gate             guards may forbid or demand flatten
 ├─ 5 decide                session → news → strategies → confirmation → vote
 ├─ 6 size and protect      volume, stop, target; risk re-verified after clamping
 ├─ 7 execute               the only OrderSend
 └─ 8 render                dashboard and overlay, last and optional
```

Two orderings carry weight.

**Management before entry.** An engine that hunts a new signal before trailing an open
winner will, on a fast tick, add risk while existing risk sits unprotected.

**Risk re-verified after clamping.** The broker may widen a stop to its minimum distance.
Sizing computed against the requested stop is then wrong. Re-checking after clamping is the
step most EAs omit, and the reason a position sized for 1% can quietly risk more.

## Communication — four channels, nothing else

| Channel | Carries | Mechanism |
|---|---|---|
| Constructor injection | the trading path | interface pointers, wired in the composition root |
| Immutable DTOs | data hand-off | `SDecisionInput`, `SSizingResult`, `SProtectionPlan`, … |
| Event bus | reporting, guards, alerts | 26 topics, one adapter per observer |
| Read-only view model | the dashboard | a copy, never pointers |

The dashboard is structurally incapable of affecting trading. A UI bug can garble a label;
it can never move a stop loss.

## Ownership

Every pointer is owned (and deleted) or borrowed (and never deleted). Teardown is strict
reverse construction order.

Ownership is **not uniform**, and the asymmetry is load-bearing:

```
CRiskEngine::SetSizer / SetLimitGuard / SetProtectionManager   TAKES ownership
CDecisionEngine::AddPlugin / SetConfirmationEngine             TAKES ownership
CDecisionEngine::SetCollaborators                              BORROWS
CProductionEngine accessors                                    BORROW
```

Getting this wrong produced a double free that no compiler caught and only a real teardown
revealed. `Release()` now handles both the ownership-transferred and construction-failed
paths so each pointer is freed exactly once either way.

## Instrument agnosticism

Every distance is in **points**, never pips or price. Switching instrument is a preset
change, not a code change.

The one place this nearly failed is risk conversion. Money-per-lot derived from
`SYMBOL_TRADE_TICK_VALUE` is textbook and wrong on some instruments: this broker reports
gold with `tick_size` 0.01 and `tick_value` 0.10 against a 100 oz contract, understating
loss tenfold and sizing gold positions 10x too large.

The engine now asks the terminal via `OrderCalcProfit`, which prices the fill with the
broker's own contract specification — correct across FX, metals, indices and crypto with no
special cases. The integration harness asserts the two agree.

## Environment awareness

One policy object decides what runs where, and it is consulted rather than guessed at.

| Subsystem | Live | Backtest | Optimisation |
|---|---|---|---|
| Dashboard, overlay | on | visual only | off |
| File logging | on | on | off |
| Log verbosity | configured | configured | forced off |
| Notifications | on | off | off |
| State persistence | on | off | off |
| Calendar news | on | off | off |
| Tick throttle | on | off | off |

Three of these are correctness, not performance:

- **State persistence off in the tester** — state leaking from pass N into pass N+1
  silently biases every later pass and invalidates the optimisation.
- **Calendar news off in the tester** — MQL5 returns *today's* events regardless of the
  simulated bar. Consulting it is look-ahead bias.
- **Tick throttle off in the tester** — it measures real time; a backtest replays a month
  in seconds, so it would discard nearly every simulated tick.

## Extension points

New behaviour is a new file plus one wiring line. Existing logic is not edited.

| To add | Derive from | Register in |
|---|---|---|
| Strategy | `CStrategyPlugin` | `BuildDecision` |
| Sizing model | `CSizerBase` | `CreateSizer` |
| Indicator | `CIndicatorBase` | `BuildIndicators` + context |
| Risk limit | extend `CRiskLimitGuard` | `BuildRisk` |
| News source | extend `CNewsEngine` | `BuildDecision` |
| Log channel | channel enum | `CEnterpriseLogger` |

Each base leaves exactly **one** abstract method, so a strategy author writes signal logic
and nothing else.

## Testability

| Inject a fake | To test |
|---|---|
| `IClock` | any historical moment, deterministically |
| `ITradeExecutor` | the whole pipeline with no broker |
| `IConfigProvider` | any configuration |
| `IStateStore` | restart recovery |
| `INewsProvider` | blackout behaviour |
| `IIndicator` | strategies against synthetic series |

No module calls `TimeCurrent()` directly. That one rule makes the session, schedule and news
subsystems deterministically testable.

`CRuntimeConfig::Load(NULL, …)` yields documented defaults, so every module is
constructible in a harness with no configuration at all.

## Verification

| Layer | What it proves | Current |
|---|---|---|
| Compile, 17 targets | the code is well formed | 0 errors, 0 warnings |
| Phase harnesses (13) | each subsystem in isolation | all pass |
| Integration harness | the graph builds, ticks, tears down | 74 assertions, 0 failures |
| Backtest | the strategy runs on history | EURUSD, XAUUSD — no faults |
| Optimisation | fitness ranks and exports | 1,176 passes — no faults |

**Compiling is not verifying.** Every defect found in this phase compiled cleanly with zero
warnings: a double free, a throttle that discarded 99% of ticks, a fail-safe that blocked
94% of them, sizing 10x too large, the wrong sizing model, and statistics reporting currency
as counts. Six defects, zero compiler complaints.

That is what the runtime harness exists for.

## The Phase 1 scaffold

`Core\CTradingEngine`, `Core\CEngineBootstrapper` and `Core\CDecisionPipeline` are the
reference design this product grew from. Bodies were intentionally left as declarations;
Phases 2–5 built the implemented equivalents that now execute.

The umbrella header **excludes** them deliberately. MQL5 links a body only when a function
is called, so including bodiless declarations compiles but breaks the moment a consumer
touches one. Every base class, interface and DTO the scaffold defines is live and included.

## Safety properties

Not configurable, by design:

- One door to the broker
- Foreign positions never touched — magic **and** symbol filtered
- Volume always rounds down
- Risk re-verified after broker stop-level clamping
- One market snapshot per pass
- Deal tickets deduplicated
- Broker filling mode resolved, not assumed
- All price arithmetic tick-size aware
- Latched guards survive restarts; drawdown measured from a persisted all-time peak
- Kill switch clears only by human action
- Configuration contradictions abort `OnInit`
- Wiring verified at startup, not on tick 10,000
- Optimisation runs never polluted by persisted state

News deserves a specific note. When the source is unreachable the behaviour is an
**explicit configured choice**, never an accident of control flow — and in the tester, where
the calendar is structurally unavailable, the run states plainly that news is not being
modelled rather than silently declining every trade.
