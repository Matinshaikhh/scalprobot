# Scalping Robot Pro — Architecture

UML-style architecture documentation for the MQL5 Expert Advisor skeleton.

Version: 1.00 · Architecture revision ARCH-2026-08 · 148 files (1 `.mq5`, 147 `.mqh`)

> **Scope.** This document describes *structure*, not trading rules. Method bodies containing
> business logic are intentionally absent. What is present is complete: every type, every
> contract, every ownership rule and every communication path.

---

## 1. Design goals and how they are enforced

| Goal | Mechanism | Enforced by |
|---|---|---|
| No spaghetti | One ordered pipeline, no cross-module reach-through | `CDecisionPipeline` |
| Single responsibility | One reason to change per class | 147 focused headers |
| Open/Closed | New behaviour = new file + factory line | Factories + role interfaces |
| Liskov | Bases add preconditions only, never remove them | Template-method bases |
| Interface segregation | Small role contracts; stateless roles stay parentless | 19 interfaces |
| Dependency inversion | Everything depends on interfaces; one composition root | `CEngineBootstrapper` |
| Testability | Clock, config, executor, news all injectable | Constructor injection |
| No leaks | Exactly one owner per object; RAII for handles | `CModuleRegistry`, `CIndicatorBase` |

---

## 2. The MQL5 constraint that shapes everything

MQL5 permits **at most one parent** per class or interface — confirmed in the
[MQL5 language book](https://www.mql5.com/en/book/oop/classes_and_interfaces/classes_inheritance):
unlike C++, multiple inheritance is not supported. Interfaces declared with the
[`interface` keyword](https://www.mql5.com/en/book/oop/classes_and_interfaces/classes_abstract_interfaces)
are bound by the same rule.

*Content rephrased for compliance with licensing restrictions.*

Three consequences run through the whole design:

1. **Role interfaces that need a lifecycle inherit `IModule` singly.**
   `IStrategy : IModule`, `IFilter : IModule`, `IRiskGuard : IModule`, `IIndicator : IModule`,
   `IPositionRule : IModule`, `ITradeExecutor : IModule`, `INewsProvider : IModule`,
   `INotifier : IModule`, `IStateStore : IModule`. One concrete class is legally both a role
   and a managed module.

2. **Stateless roles stay parentless.** `IPositionSizer`, `IStopLevelCalculator`, `IClock`,
   `IConfigProvider`, `ILogSink`, `IWidget`, `IEventPublisher`, `IEventListener` own nothing
   and have nothing to initialise. Forcing `IModule` on them would be interface pollution.

3. **Observation is composed, not inherited.** A class already inheriting `IStrategy` cannot
   also inherit `IEventListener`. So `IModule` declares `HandleEvent()`, and
   `CEventListenerAdapter` — the only real listener — wraps an `IModule*` plus a topic mask and
   forwards matching events. Composition solving what inheritance cannot express.

```
        IModule  ......... HandleEvent(payload)
           ^                        ^
           |  (single parent)       |  forwards to
     +-----+-----+                 |
  IStrategy  IFilter  ...    CEventListenerAdapter ---> registered with CEventBus
```

---

## 3. Layer map

Dependencies point **downward only**. No cycles. Include order in `ScalpRobotPro.mqh` is
exactly this order.

```
L17  Orchestration     CDecisionPipeline · CTradingEngine · CEngineBootstrapper
L16  Optimization      COptimizationGuard · COptimizationCriterion · CParameterSetValidator
L15  Dashboard         CDashboardManager · 9 widgets · painter · theme · layout · view model
L14  Statistics        CStatisticsEngine · CPerformanceCalculator · CEquityCurveTracker
                       CSessionStatistics · CTradeJournal
L13  Trade             CTradeExecutor · CPositionManager · CPositionRepository
                       4 rules · CTradeRequestBuilder · CTradeTransactionRouter
L12  Risk              CRiskManager · 3 sizers · 4 calculators · 5 guards
                       CRiskGuardChain · CKillSwitch · CLotNormalizer · CStopLevelValidator
L11  Filters           CFilterChain · 7 filters · CFilterFactory
L10  Strategies        CStrategyOrchestrator · 4 strategies · CSignalAggregator · factory
L9   News              CNewsService · CNewsBlackoutEvaluator · 2 providers · CNewsFilter
L8   Analysis          CSessionCalendar · CMarketRegimeAnalyzer
L7   Indicators        CIndicatorManager · 7 wrappers · CIndicatorFactory
L6   Data              CSymbolInfoProvider · CAccountInfoProvider · CMarketDataService
L5   Configuration     CConfigKeys · CInputConfiguration · validator · builder
L4   Infrastructure    CLogger · 4 sinks · CEventBus · CServerClock · CModuleRegistry
                       CEngineStateMachine · CErrorHandler · CHealthMonitor · CTickThrottle
L3   Bases             CModuleIdentity · 6 abstract bases
L2   Utilities         Math · String · Time · Price · CircularBuffer · File IO · state store
L1   Contracts         19 interfaces
L0   Types             Constants · Enums · Structs
```

---

## 4. Class inventory by folder

### Core/Types (3)
`Constants.mqh` · `Enums.mqh` (24 enums) · `Structs.mqh` (19 DTOs)

Key DTO: **`SDecisionContext`** bundles market, account, exposure, news and daily snapshots.
Every strategy and filter receives this one immutable struct, so adding a data source never
changes a single strategy or filter signature.

### Core/Interfaces (19)
`IModule` · `ILogger` · `ILogSink` · `IClock` · `IEventPublisher` · `IEventListener`
`IConfigProvider` · `IStateStore` · `IStrategy` · `IFilter` · `IRiskGuard` · `IIndicator`
`IPositionSizer` · `IStopLevelCalculator` · `IPositionRule` · `ITradeExecutor`
`INewsProvider` · `INotifier` · `IWidget`

### Core/Base (7)
`CModuleIdentity` (composed shared state) · `CStrategyBase` · `CFilterBase` · `CIndicatorBase`
`CRiskGuardBase` · `CPositionRuleBase` · `CWidgetBase`

Each base implements its role's plumbing and leaves **one** abstract method (`OnEvaluate`,
`OnCreateHandle`, `OnRender`). Template Method throughout.

### Core (13)
`CTradingEngine` · `CEngineBootstrapper` · `CDecisionPipeline` · `CEngineStateMachine`
`CModuleRegistry` · `CErrorHandler` · `CHealthMonitor` · `CTickThrottle` · `CServerClock`
`CMarketDataService` · `CMarketRegimeAnalyzer` · `CSymbolInfoProvider` · `CAccountInfoProvider`
Plus `Core/Events`: `CEventBus` · `CEventListenerAdapter`

### Remaining folders
| Folder | Count | Contents |
|---|---|---|
| Configuration | 4 | keys, provider, validator, builder |
| Indicators | 9 | MA, RSI, ATR, ADX, Bollinger, MACD, Stochastic, manager, factory |
| Strategies | 7 | momentum, mean-reversion, breakout, volatility-expansion, aggregator, orchestrator, factory |
| Filters | 10 | spread, session, schedule, holiday, volatility, trend, frequency, chain, factory, calendar |
| Risk | 17 | manager, 3 sizers, 4 level calculators, normalizer, validator, 5 guards, chain, kill switch |
| Trade | 9 | executor, request builder, repository, manager, 4 rules, transaction router |
| News | 5 | service, blackout evaluator, calendar provider, CSV provider, filter adapter |
| Statistics | 5 | engine, calculator, equity tracker, session stats, journal |
| Dashboard | 14 | manager, view model, theme, layout, painter, 9 widgets |
| Logger | 9 | logger, formatter, 4 sinks, notification service, 2 notifiers |
| Utilities | 9 | math, string, time, price, buffer, name factory, file reader/writer, state store |
| Optimization | 3 | guard, criterion, parameter validator |

---

## 5. The decision pipeline — how a tick becomes a trade

`CDecisionPipeline` **sequences** stages and contains no trading rules. Any stage may abort.

```
OnTick
  │
  ├─ CTickThrottle.ShouldProcess()            skip? ──> return  (new bar always passes)
  │
  ├─ CEngineStateMachine.CanManagePositions() ──> CPositionManager.ManageAll()
  │                                               (runs in TRADING, MANAGING_ONLY, PAUSED, HALTED)
  │
  └─ CEngineStateMachine.CanOpenNewPositions() ──> pipeline pass:

     STAGE                        MODULE                     ABORTS ON
     ─────────────────────────────────────────────────────────────────────────
     1  capture snapshot          CMarketDataService         bad/stale prices
     2  refresh indicators        CIndicatorManager          any buffer not ready
     3  label regime              CMarketRegimeAnalyzer      —
     4  sample account            CAccountInfoProvider       trading not permitted
     5  read exposure             CPositionRepository        —
     6  evaluate news             CNewsBlackoutEvaluator     blackout active
     7  account permission        CRiskGuardChain            first guard refusal
     8  resolve signal            CStrategyOrchestrator      no actionable consensus
     9  filter chain              CFilterChain               first blocking veto
    10  size + levels             CRiskManager               not approved
    11  build request             CTradeRequestBuilder       incoherent inputs
     ─────────────────────────────────────────────────────────────────────────
                                  │
                                  └─> CTradeExecutor.OpenPosition()  ← only OrderSend in product
```

**Why one snapshot per pass.** Without it, strategy A reads bid at microsecond *X* and filter B
reads it at *X+n*. On M1 gold those differ, so a trade can be approved against prices that no
longer exist. One read, one truth, for the whole pass.

**Why management runs even when entries are forbidden.** Open risk must be tended to whether or
not new risk is permitted.

### Risk stage ordering (deliberate)

```
1 resolve stop distance        (size depends on it)
2 size position                (needs stop distance)
3 resolve take profit          (may depend on stop, for RR mode)
4 validate levels vs broker    (may shift them)
5 normalise volume             (step, bounds, margin — always rounds DOWN)
6 re-verify risk after clamp   ← the step most EAs omit
```

Step 6 matters: if the broker's stop level forced the stop wider, a position sized for 1% now
risks more. `CRiskManager.EnforceRiskCeiling()` re-checks and shrinks.

---

## 6. Module communication — the four permitted channels

Nothing communicates outside these four channels. That constraint is the architecture.

### Channel 1 — Constructor injection (synchronous, compile-time)
Used for the trading path. Collaborators arrive as interface pointers; nobody looks anything up.

```
CRiskManager(CSymbolInfoProvider*, ILogger*)
CTradeExecutor(CSymbolInfoProvider*, CErrorHandler*, IEventPublisher*, IClock*, ILogger*)
CPositionManager(ITradeExecutor*, CPositionRepository*, CSymbolInfoProvider*,
                 CStrategyOrchestrator*, CStopLevelValidator*, IEventPublisher*, ILogger*)
```

### Channel 2 — Immutable DTOs (data hand-off)
Modules exchange structs, never live references to each other's internals.

```
CMarketDataService ──SMarketSnapshot──> CMarketRegimeAnalyzer ──annotates──> SDecisionContext
SDecisionContext ──const&──> IStrategy ──SSignal──> CSignalAggregator ──SSignal──> CFilterChain
SSignal + SDecisionContext ──> CRiskManager ──SRiskDecision──> CTradeRequestBuilder
STradeRequest ──> ITradeExecutor ──STradeResult──> event bus
```

Strategies and filters receive `const SDecisionContext&` and **must not mutate it**.

### Channel 3 — Event bus (asynchronous, one-to-many)
26 topics in `ENUM_SRP_EVENT`. Producers hold `IEventPublisher` and cannot touch the
subscription table (Interface Segregation). Only the kernel subscribes.

```
                    ┌──────────────────────────────────────────┐
   CTradeExecutor ──>│                                          │──> CStatisticsEngine
CTradeTransaction ──>│   CEventBus  (defers re-entrant publish) │──> CTradeJournal
        Router       │                                          │──> CSessionStatistics
   CRiskGuardChain ──>│   dispatch ──> CEventListenerAdapter*   │──> CConsecutiveLossGuard
     CKillSwitch ──>│                  (one per observer)       │──> CTradeFrequencyFilter
CEngineStateMachine ─>│                                          │──> CNotificationService
                    └──────────────────────────────────────────┘
```

**Re-entrancy is handled explicitly.** A listener may publish while being dispatched; such
publications are queued in `m_deferred` and drained after the current dispatch, so recursion
is impossible rather than merely unlikely.

**Why this channel exists.** Statistics, journalling, notifications and the dashboard are
*observers*. The pipeline does not know they exist and does not slow down for them. Reporting
can be extended indefinitely without touching the trading path.

### Channel 4 — Read-only view model (UI firewall)
`CDashboardViewModel` holds **copies**, never pointers. Widgets receive `const&` and nothing
else — they are structurally incapable of reaching the engine, executor or a position.

```
pipeline ──writes──> CDashboardManager ──populates──> CDashboardViewModel
                                                            │ const&
                                              9 × IWidget ──┘  (read only)
```

A UI bug can garble a label but can never move a stop loss. This also decouples refresh rates:
the dashboard repaints on a throttle; chart rendering can never slow execution.

---

## 7. Ownership model — exactly one owner per object

Leaks and double-frees are prevented structurally, not by discipline.

| Owner | Owns | Deletes |
|---|---|---|
| `CEngineBootstrapper` | logger, clock, bus, registry, error handler, health monitor, pipeline, config, view model, engine, adapters | yes |
| `CModuleRegistry` | every `IModule` | yes, reverse registration order |
| `CLogger` | its `ILogSink` set | yes |
| `CIndicatorManager` | its `IIndicator` set | yes |
| `CStrategyOrchestrator` | its `IStrategy` set | yes |
| `CFilterChain` | its `IFilter` set | yes |
| `CRiskGuardChain` | its `IRiskGuard` set | yes |
| `CPositionManager` | its `IPositionRule` set | yes |
| `CRiskManager` | sizer, level calculators, normalizer, validator | yes |
| `CNewsService` | its `INewsProvider` | yes |
| `CDashboardManager` | widgets, painter, theme, layout | yes |
| **everyone else** | **nothing** — all pointers are borrowed | **never** |

Rules:
- **Reverse-order teardown.** `CModuleRegistry.ShutdownAll()` unwinds in exact reverse, because
  module B may have borrowed a pointer to module A.
- **Partial-failure safety.** `m_initialized_count` records how far `InitializeAll()` got; only
  those modules get `Shutdown()`.
- **RAII for OS/terminal resources.** `CIndicatorBase` destructor calls `IndicatorRelease`;
  `CFileWriter`/`CFileReader` destructors close handles. A leaked file handle locks a file until
  the terminal restarts.
- **The `.mq5` never deletes the engine** — it is borrowed from the bootstrapper.

---

## 8. Engine state machine

State is **one value**, not a set of booleans. Scattered `m_paused` / `m_halted` / `m_ready`
flags produce combinations nobody reasoned about — the classic road to spaghetti.

```
CREATED ──> INITIALIZING ──> READY ──┬──> TRADING <────────> MANAGING_ONLY
                                     │        \    ↕            /
                                     │         PAUSED <────────'
                                     └────────────┴──> HALTED (terminal, restart only)

any state ──> SHUTDOWN   (OnDeinit must always work)
any live  ──> HALTED     (kill switch is unconditional by design)
```

Every transition is validated against an explicit table; illegal transitions are refused and
logged. Intent-revealing queries (`CanOpenNewPositions()`, `CanManagePositions()`) are used
everywhere instead of raw state comparisons.

---

## 9. Patterns and where they earn their place

| Pattern | Applied in | Problem solved |
|---|---|---|
| Composition Root | `CEngineBootstrapper` | one place says `new`; graph is auditable |
| Template Method | all 6 bases | uniform preconditions, one extension point |
| Strategy | `IPositionSizer`, `IStopLevelCalculator` | swap sizing/level model by config |
| Chain of Responsibility | `CFilterChain`, `CRiskGuardChain` | short-circuit on first veto |
| Composite | `CLogger`, `CDashboardManager`, chains | treat many as one |
| Observer | `CEventBus` + adapters | reporting without touching trading path |
| Adapter | `CEventListenerAdapter`, `CNewsFilter` | bridge incompatible contracts, zero duplication |
| Factory | 4 factories | construction separated from coordination |
| Facade | `CTradingEngine` | `.mq5` talks to one thin object |
| Repository | `CPositionRepository` | cached read model, magic-filtered |
| State | `CEngineStateMachine` | legal transitions only |
| Value Object | 19 structs | data crosses boundaries without coupling |

---

## 10. Safety properties designed in

Each addresses a specific, common failure mode in commercial EAs.

| Property | Mechanism |
|---|---|
| Guards survive restart | latched trips persisted via `IStateStore` — a guard that forgets it fired is not a guard |
| Drawdown measured from all-time peak | `CEquityCurveTracker` persists the peak; session-high resets silently break a "20% max DD" claim |
| Risk honoured after broker clamping | `CRiskManager` step 6 re-verifies and shrinks |
| Volume never rounds up | `CLotNormalizer` floors; rounding up doubles risk at 0.01→0.02 |
| Never touches foreign positions | `CPositionRepository` filters by magic **and** symbol |
| No double-counted trades | `CTradeTransactionRouter` deduplicates deal tickets |
| Retries never duplicate a position | `CTradeExecutor` idempotence handling when a reply is lost |
| News failure is an explicit choice | `news.fail_safe_block` — silent degradation to "allow all" is worse than no filter |
| Invalid stops prevented once | `CStopLevelValidator` is the single clamping authority (retcode 10016) |
| Broker filling mode not assumed | resolved from `SYMBOL_FILLING_MODE` at init |
| Point/pip errors eliminated | all arithmetic in `CPriceUtils` with `SSymbolSpec`; tick-size aware |
| Config errors caught before tick 1 | `CConfigValidator` cross-field rules abort `OnInit` |
| Wiring mistakes caught at init | `CDecisionPipeline.VerifyWiring()` — not a null deref on tick 10,000 |
| Kill switch needs a human | `ClearByOperator()` is called by no automation |
| Chart left clean | `CObjectNameFactory` namespacing + exact per-widget object ownership |
| Optimisation not polluted | `COptimizationGuard` disables persistence, UI, journal, notifications |

---

## 11. Testability

Because every dependency is an interface, each module can be exercised in isolation:

| Inject a fake | To test |
|---|---|
| `IClock` | sessions, schedule, holidays, news, time stops at any historical moment |
| `ITradeExecutor` | the entire pipeline with zero broker contact |
| `IConfigProvider` | any settings combination without touching `input` variables |
| `INewsProvider` | blackout logic against synthetic events |
| `IIndicator` | strategy logic against scripted indicator values |
| `IStateStore` | restart and recovery behaviour |
| `ILogSink` | assert on emitted diagnostics |

`CPerformanceCalculator` is entirely static and pure — every formula is verifiable against a
known trade set. That matters because these numbers are what customers judge and what the
optimiser optimises against.

---

## 12. Why the `.mq5` file is deliberately boring

It does exactly three things: declares the `input` block, copies it into `SInputSnapshot`, and
forwards six terminal callbacks. No logic, no calculations, no `OrderSend`, no drawing, and no
state beyond two pointers.

MQL5 `input` variables are file-scoped globals and an `.mq5` file cannot be unit-tested or
reused. Any logic placed there is permanently untestable and permanently coupled to the
terminal. Confining the file to adaptation puts 100% of behaviour in classes that can be
instantiated, injected with fakes and verified.

```
OnInit             ──> CollectInputs() ──> CEngineBootstrapper.Build() ──> CTradingEngine.Start()
OnTick             ──> CTradingEngine.OnTickEvent()
OnTimer            ──> CTradingEngine.OnTimerEvent()        (news, health, persistence — off tick path)
OnTradeTransaction ──> CTradingEngine.OnTradeTransactionEvent()
OnChartEvent       ──> CTradingEngine.OnChartEventReceived()
OnTester           ──> CTradingEngine.OnTesterEvent()
OnDeinit           ──> CTradingEngine.Stop() ──> ReleaseGraph()
```

---

## 13. Extension recipes

Adding behaviour touches new files plus one factory line. Existing logic is never edited.

| To add | Create | Register in |
|---|---|---|
| Strategy | `CXStrategy : CStrategyBase`, implement `OnEvaluate` | `CStrategyFactory` |
| Filter | `CXFilter : CFilterBase`, implement `OnEvaluate` | `CFilterFactory` + priority |
| Indicator | `CXIndicator : CIndicatorBase`, implement `OnCreateHandle` | `CIndicatorFactory` |
| Risk guard | `CXGuard : CRiskGuardBase`, implement `OnAllowsNewEntry` | bootstrapper → `CRiskGuardChain` |
| Management rule | `CXRule : CPositionRuleBase`, implement `OnEvaluate` | bootstrapper → `CPositionManager` |
| Sizing model | `CXSizer : IPositionSizer` | `CRiskManager.SetSizer()` |
| Log destination | `CXSink : ILogSink` | `CLogger.AddSink()` |
| Dashboard panel | `CXWidget : CWidgetBase` | `CDashboardManager.AddWidget()` |
| News source | `CXProvider : INewsProvider` | `CNewsService.SetProvider()` |
| Event topic | add to `ENUM_SRP_EVENT` | subscribe adapter in bootstrapper |

---

## 14. Known issue to resolve before implementation

A stray, orphaned file exists outside the project tree:

```
MQL5/Include/ScalpingRobotPro/Core/Types/SRPVersion.mqh   ← misspelled folder ("Scalping…")
```

It is **not** part of this architecture and nothing references it. It redefines
`SRP_PRODUCT_NAME` and declares `SRP_COPYRIGHT`, which would collide with
`ScalpRobotPro/Core/Types/Constants.mqh` if it were ever included. It was left in place rather
than deleted, since it was not generated as part of this scaffold.

**Recommendation:** delete the `ScalpingRobotPro` folder, or fold `CVersionInfo` into
`Core/Types/Constants.mqh` and remove the duplicate macros.

---

## 15. Current state

Complete: folder structure, all class names, all 147 headers with full declarations, the
`.mq5` entry point with a complete input block and wiring, ownership and communication rules.

Absent by design: method bodies containing trading logic. The next step is implementing them
base-class-first (`CModuleIdentity` → bases → utilities → data providers → indicators →
strategies/filters → risk → trade → statistics → dashboard), compiling after each layer.

No placeholders. No TODO comments. No stub returns pretending to be logic.
