# Developer Documentation

How the codebase is organised, how to extend it, and the constraints that shaped it.

## Layout

```
MQL5\
├── Experts\ScalpRobotPro\
│   ├── ScalpRobotPro.mq5          the product entry point (adapter only)
│   └── P6ProductionCheck.mq5      integration harness, tester-launchable
├── Scripts\ScalpRobotPro\         verification harnesses, one per phase
└── Include\ScalpRobotPro\
    ├── ScalpRobotPro.mqh          the single umbrella header
    ├── Core\                      types, 19 interfaces, 6 bases, events, kernel
    ├── Configuration\             keys, provider, validator, builder
    ├── Intelligence\              indicators, structure, smart money, risk
    ├── Decision\                  sessions, news, strategies, confirmation, vote
    ├── Trade\Engine\              broker, execution, orders, positions, facade
    ├── Interface\                 logging, analytics, dashboard, overlay, manager
    ├── Optimization\              criterion, screen, walk-forward, Monte Carlo, tester
    ├── Runtime\                   CRuntimeConfig, CProductionEngine
    ├── Utilities\                 math, string, time, price, buffer, file IO
    └── Tests\                     shared harness bodies
```

## The five ideas that keep this maintainable

**1. One composition root.** `CProductionEngine` is the only class that says `new` on the
trading path. Read `Build()` to know everything the product is made of. Every other class
receives collaborators through its constructor.

**2. One ordered pipeline.** `OnTickEvent` sequences eight stages and contains no trading
rules. One screen explains the entire control flow from tick to order.

**3. One snapshot per pass.** Market state is captured once and shared. Otherwise strategy
A reads bid at microsecond *X* and filter B reads it at *X+n* — on M1 gold those differ, so
a trade gets approved against prices that no longer exist.

**4. One door to the broker.** Only the execution engine calls `OrderSend`. Substitute a
simulating executor and the whole pipeline runs offline.

**5. One owner per object.** Every pointer is either owned (and deleted) or borrowed (and
never deleted). Teardown is strict reverse order.

## Ownership, and the trap in it

Ownership is documented per setter, and it is not uniform:

```
CRiskEngine::SetSizer / SetLimitGuard / SetProtectionManager   TAKES ownership
CDecisionEngine::AddPlugin / SetConfirmationEngine             TAKES ownership
CDecisionEngine::SetCollaborators                              BORROWS
```

This caused a real defect. `CProductionEngine::Release` deleted the sizer, limit guard and
protection manager *and* the risk engine that owned them — a double free that surfaced as
`invalid pointer access` the first time a genuine teardown ran. It never appeared in
compilation, and it never appeared in any harness that only constructed objects.

The fix makes the asymmetry explicit:

```cpp
if(m_risk!=NULL)
  {
   m_risk.Shutdown();
   delete m_risk;      // deletes sizer, guard and protection itself
   m_risk=NULL;
   m_protection=NULL;  // forgotten, not deleted
   m_limits=NULL;
   m_sizer=NULL;
  }
else
  {
   // Construction failed before the handover, so we are still the owner.
   if(m_protection!=NULL){ delete m_protection; m_protection=NULL; }
   if(m_limits!=NULL)    { delete m_limits;     m_limits=NULL;     }
   if(m_sizer!=NULL)     { delete m_sizer;      m_sizer=NULL;      }
  }
```

Either path frees each pointer exactly once. When adding a subsystem that hands ownership
to another, write both branches.

## The MQL5 constraint behind the design

MQL5 allows **one parent** per class or interface — no multiple inheritance, and
`interface` types follow the same rule. So role interfaces needing a lifecycle inherit
`IModule` singly, stateless roles stay parentless, and modules that must observe the event
bus **compose** a listener adapter instead of inheriting a second contract.

Composition where inheritance cannot reach — enforced by the language, not by taste.

Reference: [MQL5 inheritance](https://www.mql5.com/en/book/oop/classes_and_interfaces/classes_inheritance)
· [abstract classes and interfaces](https://www.mql5.com/en/book/oop/classes_and_interfaces/classes_abstract_interfaces).
*Content rephrased for compliance with licensing restrictions.*

A second consequence matters for dead code: **MQL5 links a function body only when that
function is called.** A declaration without a body compiles fine until something calls it.
That is why unused declaration-only classes can sit in a tree for months and only explode
when a new header includes them.

## Two enum vocabularies — read before touching sizing

`ENUM_SRP_RISK_MODE` (Core) and `ENUM_SRP_SIZING_MODEL` (Intelligence) both describe
position sizing and **number their members differently**:

```
RISK_MODE 3 == SRP_RISK_PERCENT_EQUITY
SIZING    3 == SRP_SIZING_KELLY
```

Both are stored under the same config key, `risk.mode`. The production engine consumes the
*sizing* vocabulary.

This caused a second real defect. The shipped preset assigned a `RISK_MODE` value, so the
engine built a **Kelly** sizer when percent-of-equity was requested. Kelly then refused all
28 valid signals for want of a sample, and the run reported zero trades with no error.

Two things now prevent recurrence: the snapshot field is typed as
`ENUM_SRP_SIZING_MODEL` so a mismatched assignment is a compile error, and the startup log
prints the model by name rather than as an integer. The integration harness asserts the
round trip.

If you unify the vocabularies, do it in one commit and update the validator, which
validates against the sizing numbering.

## Extending it

New behaviour means a new file plus one wiring line. Existing logic is not edited.

| To add | Derive from | Register in |
|---|---|---|
| Strategy | `CStrategyPlugin` | `CProductionEngine::BuildDecision` |
| Sizing model | `CSizerBase` | `CProductionEngine::CreateSizer` |
| Risk limit | extend `CRiskLimitGuard` | `BuildRisk` |
| Indicator | `CIndicatorBase` | `BuildIndicators` + `CStrategyContext` |
| Log channel | `ENUM_SRP_LOG4_CHANNEL` | `CEnterpriseLogger` |
| Dashboard row | — | `CDashboardPanel` |
| News source | extend `CNewsEngine` | `BuildDecision` |

Each base leaves exactly **one** abstract method, so a new strategy author writes signal
logic and nothing else.

### Adding a strategy

```cpp
class CMyStrategy : public CStrategyPlugin
  {
public:
   CMyStrategy(CStrategyContext *context,ILogger *logger)
     : CStrategyPlugin("MyStrategy",context,logger) { }

   virtual bool Evaluate(const SDecisionInput &snapshot,
                         SStrategySignal &signal) override
     {
      // Read the shared snapshot. Never query the terminal directly:
      // doing so would read prices from a different instant than every
      // other module in this pass.
      signal.decision   = SRP_DECISION_BUY;
      signal.confidence = 0.72;          // normalised 0..1
      signal.reason     = "why, in words a user can read";
      signal.risk_rating= SRP_RISK_MODERATE;
      return(true);
     }
  };
```

Then one line in `BuildDecision`, gated by a config flag so a disabled strategy is never
constructed:

```cpp
if(m_config.my_strategy_enabled)
   m_decision.AddPlugin(new CMyStrategy(m_context,nolog));
```

Confidence must be normalised, because weighted voting compares it across strategies.

### Adding a configuration setting

No hardcoded values anywhere downstream. Four edits:

1. `CConfigKeys` — declare and define the key string.
2. `SInputSnapshot` — add the field.
3. `CConfigurationBuilder` — write it in `Apply*`, and set a default in
   `ApplyNasdaqDefaults`.
4. `SRuntimeConfig` — add the field, a default in `Reset()`, and a read in `Load()`.

Then add the `input` in the .mq5 and copy it in `CollectInputs`. Every read passes the
corresponding default as its fallback, so a missing key yields the documented default
rather than a zero.

## Testing

```
_build\build.ps1  -Target all       compile every entry point
_build\test.ps1   [-Symbol X]       run the integration harness for real
_build\backtest.ps1 [-Symbol X]     run the EA over history
_build\optimize.ps1 [-Symbol X]     genetic optimisation, checks CSV export
```

`build.ps1` copies the tree to a space-free path first — the MetaEditor CLI fails on paths
containing spaces.

### Compiling is not verifying

The distinction is the most important thing in this section. Every one of these defects
compiled cleanly with zero warnings:

| Defect | Found by |
|---|---|
| Double free in teardown | Running the engine |
| Tick throttle starving the tester | Reading a 0.24 s runtime |
| News fail-safe blocking 94% of ticks | The decline tally |
| Gold risk understated 10x | Comparing against `OrderCalcProfit` |
| Wrong sizing model selected | Reading `model=Kelly` in a log |
| Streak stats reporting money as counts | Seeing 360 wins in 56 trades |

The harness (`Include\ScalpRobotPro\Tests\ProductionCheck.mqh`) exists to catch this
class. It builds the real graph, pumps 250 ticks through the real pipeline, asserts the
risk conversion against the terminal, and tears everything down. Current state: **74
assertions, 0 failures**.

The body lives in a header so the same assertions run two ways: as a chart script, and as
a tester-launchable EA. Only the Strategy Tester can be driven from a command line, and it
will not launch a script — that is what allows runtime verification to be automated.

It never sends an order: the engine is halted before ticking, so `OrderSend` is
unreachable by construction rather than by luck.

### Adding an assertion

```cpp
Check("what must be true", condition);
CheckNear("a numeric identity", actual, expected);
```

Prefer assertions that would fail loudly on a real defect over assertions that restate the
implementation. "Money-per-lot agrees with `OrderCalcProfit`" is worth more than the rest
of the suite combined, because that mismatch does not throw — it just trades the wrong
size.

## The Phase 1 scaffold

`Core\CTradingEngine`, `Core\CEngineBootstrapper` and `Core\CDecisionPipeline` are the
reference design this product grew from. Their method bodies were intentionally left as
declarations; Phases 2–5 built the implemented equivalents.

| Scaffold (declaration-only) | Implemented replacement |
|---|---|
| `Indicators\` | `Intelligence\Indicators\` |
| `Strategies\` | `Decision\Strategies\` |
| `Filters\`, `News\` | `Decision\Session\`, `Decision\News\` |
| `Risk\` | `Intelligence\Risk\` |
| `Trade\` rules, executor | `Trade\Engine\`, `Interface\Manager\` |
| `Dashboard\`, `Statistics\` | `Interface\Dashboard\`, `Interface\Analytics\` |
| `Core\CTradingEngine` | `Runtime\CProductionEngine` |

**The umbrella header deliberately does not include the scaffold.** Including bodiless
declarations compiles but breaks the moment any consumer touches one — a trap rather than a
convenience. Every base class, interface and DTO the scaffold defines *is* live and is
included.

If you want the scaffold as a reference, include it directly.

## Removed during the production review

| File | Reason |
|---|---|
| `CPositionController.mqh` (903 lines) | Parallel position stack, never compiled (102 errors), duplicated `CEnginePositionManager` |
| `CPositionRegistry.mqh` (559) | Query half of the same dead stack |
| `Trade\Engine\TradeEngine.mqh` | Sub-umbrella for the deleted stack only |
| `DecisionTypes.mqh` (390) | Duplicated struct names from the live `DecisionStructs.mqh`; included nowhere |
| `CJsonStateStore.mqh` | Declaration-only; superseded by `CRiskStateStore` on the same interface |
| `ScalpingRobotPro\...\SRPVersion.mqh` | Orphaned; redefined `SRP_PRODUCT_NAME` |
| `Experts\EngineCompileTest.mq5` | Stale API, 100 errors; superseded by `EngineCompileCheck` |

All were flagged in the phase design documents. Total: about 2,400 lines of code that could
never run.

## Conventions

- `SRP_` prefix on every enum member — MQL5 puts them in the global namespace.
- `C` classes, `I` interfaces, `S` structs, `ENUM_SRP_` enums.
- `m_` members, `Inp` inputs, `g_` file-scope globals (only in the .mq5).
- Include guards on every header: `SRP_<PATH>_<FILE>_MQH`.
- Distances in **points**, never pips or price.
- Comments explain *why*, not *what*. A comment restating the code is noise; a comment
  explaining why gold needed `OrderCalcProfit` prevents the next 10x sizing bug.

## Reading order

1. `README.md`
2. `docs\ARCHITECTURE.md` — layers, ownership tables, patterns
3. `Runtime\CProductionEngine.mqh` — `Build()`, then `OnTickEvent()`
4. `Decision\CDecisionEngine.mqh` — how a signal is resolved
5. `Intelligence\Risk\CRiskEngine.mqh` — `EvaluateEntry`, the five ordered steps
6. `Tests\ProductionCheck.mqh` — what is actually guaranteed
