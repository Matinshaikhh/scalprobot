# Core Trading Engine

Professional trade execution for MetaTrader 5. Six classes, ~3,400 lines, fully implemented.

No trading strategy. No signals, no indicators, no entry logic, no position sizing. This layer
executes instructions and reports precisely what happened.

---

## Classes

| Class | Responsibility | Lines |
|---|---|---|
| `CMagicNumberManager` | Ownership identity; decides what is "ours" | ~190 |
| `CBrokerManager` | Environment truth; all pre-trade legality checks | ~700 |
| `CExecutionEngine` | The **only** `OrderSend`; retry, idempotence, telemetry | ~640 |
| `COrderManager` | Market + pending order construction, modify, delete | ~780 |
| `CEnginePositionManager` | Close, partial, modify stops, reverse, bulk close | ~830 |
| `CTradeEngine` | Facade owning all five; implements `ITradeExecutor` | ~700 |

Location: `MQL5/Include/ScalpRobotPro/Trade/Engine/`

---

## Feature coverage

| Requirement | Implementation |
|---|---|
| Market Orders | `COrderManager::SendMarketOrder`, `CTradeEngine::Buy/Sell` |
| Pending Orders | Buy/Sell Limit, Buy/Sell Stop, Stop-Limit, with expiration |
| Modify Orders | `ModifyPendingOrder` (price + SL/TP + expiration) |
| Delete Orders | Single, all, by type |
| Partial Close | By volume and by percent, with legal-remainder enforcement |
| Close All | `CloseAll` — returns actual count closed |
| Close Symbol | `CloseSymbol` |
| Reverse Position | Mode-aware: 1 deal netting, 2 deals hedging |
| Retry Failed Orders | Classified retry + progressive backoff + idempotence guard |
| Slippage Protection | `deviation` field + post-fill measurement + excess flag |
| Spread Protection | `CheckSpread`, absolute limit, evaluated pre-trade |
| Margin Check | `OrderCalcMargin` + free-margin floor + margin-level floor |
| Execution Speed Logging | Per-send latency, worst/average, `SExecutionStatistics` |
| Netting Support | Close via opposing deal, `position=0`, single-deal reverse |
| Hedging Support | Close via `position=ticket`, close-then-open reverse |

---

## Architecture

```
                    ┌──────────────────────────┐
   caller ─────────>│      CTradeEngine        │  facade, ITradeExecutor
                    │  (owns all five below)   │
                    └───────────┬──────────────┘
            ┌───────────────────┼───────────────────┐
            v                   v                   v
   ┌────────────────┐  ┌─────────────────┐  ┌──────────────────────┐
   │ COrderManager  │  │ CEnginePosition │  │  CBrokerManager      │
   │ orders         │  │ Manager         │  │  environment truth   │
   │ (not yet       │  │ positions       │  │  pre-trade checks    │
   │  filled)       │  │ (already filled)│  └──────────────────────┘
   └───────┬────────┘  └────────┬────────┘
           └──────────┬─────────┘
                      v
           ┌─────────────────────┐      ┌──────────────────────┐
           │  CExecutionEngine   │─────>│ CMagicNumberManager  │
           │  ONLY OrderSend     │      │ ownership + comments │
           └─────────────────────┘      └──────────────────────┘
```

**Orders vs positions.** `COrderManager` handles things not yet filled; `CEnginePositionManager`
handles things already filled. That split follows MT5's own object model — conflating them is why
many EAs mishandle pending orders on netting accounts.

---

## Netting vs hedging: where it actually matters

This is the part most implementations get wrong, so it is handled explicitly rather than assumed.

### Closing

```
HEDGING   request.position = ticket    ← addresses that specific position
NETTING   request.position = 0         ← opposing deal nets exposure to zero
```

Omitting `position` on a hedging account **opens an opposing position instead of closing**.

### Reversing

```
HEDGING   close(volume) then open(new_volume)      2 deals, 2 commissions,
                                                    brief flat window
NETTING   single deal of (current + target)         1 deal, no flat window
```

On netting, one deal flips net exposure directly. Sending a close followed by an open would cost
double commission and leave a window in which the account is unintentionally flat.

If the hedging reversal's close succeeds but the reopen fails, the account is **flat, not
reversed**. That is a materially different state, so it is reported as an explicit error rather
than a plain `false`.

---

## Retry policy — the table that prevents order storms

Retrying is only correct for *transient* failures. Retrying a deterministic rejection wastes time
and floods the server.

```
RETRY                              NEVER RETRY
  REQUOTE                            INVALID_STOPS      (fix the stops)
  PRICE_CHANGED                      INVALID_VOLUME     (fix the volume)
  PRICE_OFF                          NO_MONEY           (margin won't appear)
  TIMEOUT                            MARKET_CLOSED
  CONNECTION                         INVALID_FILL       (resolve filling mode)
  TOO_MANY_REQUESTS                  POSITION_CLOSED    (already gone)
  LOCKED                             LIMIT_POSITIONS
  ERROR (generic)                    LONG_ONLY / SHORT_ONLY / CLOSE_ONLY
                                     FIFO_CLOSE / HEDGE_PROHIBITED
```

Each retry refreshes the market price (a stale price guarantees another requote) and applies
progressive backoff (`backoff_ms × attempt`).

### The idempotence guard

The most expensive bug class in automated execution: a `TIMEOUT` or `CONNECTION` failure means the
outcome is **unknown**, not failed. The order may well have executed.

Before retrying an entry, `DetectPriorSuccess()` searches deal history for a matching
symbol + magic + direction + volume `DEAL_ENTRY_IN` within the attempt window. If found, it
adopts that result instead of sending again.

Without this, one lost reply becomes two positions. Prevented duplicates are counted in
`SExecutionStatistics.idempotence_saves`.

---

## Safety properties

| Property | Mechanism |
|---|---|
| Never touches foreign positions | `CMagicNumberManager::IsOurs` is the single ownership authority; `ReadPosition`/`ReadOrder` refuse anything else |
| Volume never rounds up | `NormalizeVolume` floors, then clamps; returns 0 below broker minimum rather than sending a doomed order |
| Filling mode never assumed | Resolved from the `SYMBOL_FILLING_MODE` bit mask; prefers IOC on market execution so thin liquidity yields a partial fill instead of a rejection |
| Prices always tick-aligned | Round to tick size **then** digits — skipping the first step yields prices metals brokers reject |
| Partial close leaves a legal remainder | Refuses if the remainder would fall below broker minimum, which would create an unmanageable stub |
| No server spam | No-op suppression on both stop and order modification; trailing stops would otherwise issue thousands of pointless requests per hour |
| Freeze level respected | Modification/close deferred rather than retried against a certain rejection |
| Pending price side validated | Buy-stop above ask, buy-limit below ask, etc. — wrong side is rejected or silently converted depending on broker |
| Stops on the correct side | Verified against current price before sending, catching calculator sign errors |
| Predictable rejections filtered | `OrderCheck` pre-flight on first attempt only |
| Flatten ordering is deliberate | Pending orders deleted **before** positions closed, so no order can trigger and re-establish exposure mid-flatten |
| Bulk operations report honestly | `CloseAll` snapshots tickets first (the live list mutates), returns the real count, and logs loudly when positions remain |

---

## Usage

```cpp
STradeEngineConfig config;
config.symbol                   = _Symbol;
config.magic_base               = 20260806;
config.max_spread_points        = 300.0;
config.min_free_margin_percent  = 30.0;
config.max_retry_attempts       = 3;
config.max_slippage_points      = 50.0;

CTradeEngine *engine = new CTradeEngine(config, clock, eventBus, logger);
if(!engine.Initialize())
   return INIT_FAILED;          // pre-flight failed; do not trade

SExecutionReport report;
if(engine.Buy(0.10, sl, tp, "entry", report))
   PrintFormat("filled @ %.2f, slip %.1f pt, %I64u ms",
               report.executed_price, report.slippage_points, report.latency_ms);
```

The engine implements `ITradeExecutor`, so it also drops directly into the existing pipeline
wherever that interface is expected.

### Telemetry

```cpp
SExecutionStatistics stats;
engine.GetExecutionStatistics(stats);
// total_sends · successes · failures · retries · partial_fills
// idempotence_saves · avg/worst slippage · avg/worst latency · success rate
```

`CExecutionEngine::ReportHealth` degrades below 85% success and goes critical below 50%, so
sustained rejection becomes visible instead of silent.

---

## Two naming decisions worth knowing

**1. `CEnginePositionManager`, not `CPositionManager`.** The architecture layer already defines
`Trade/CPositionManager.mqh`, whose job is to apply `IPositionRule` objects (break-even, trailing,
partial, time-stop). This new class is the lower-level execution primitive that rule engine calls.
Two responsibilities, so two classes — reusing the name would have created a collision and an
overloaded god-object.

**2. `CTradeEngine` implements `ITradeExecutor` rather than replacing `CTradeExecutor`.**
`Trade/CTradeExecutor.mqh` remains as the architecture's declaration. `CTradeEngine` satisfies the
same contract with a working implementation plus a richer direct API, so either can be injected
wherever `ITradeExecutor` is expected.

Also implemented this pass: `CErrorHandler` was already complete in the scaffold, and
`CExecutionEngine` reuses its static `RetcodeToText` rather than duplicating the retcode table.

---

## Verification status

**Not compiled.** MetaTrader 5 is installed at `C:\Program Files\MetaTrader 5\` but has never been
run, so no terminal data folder exists and `MetaEditor64.exe /compile` produces no output and no
`.ex5` — it fails identically on a trivial 5-line script, so this is an environment limitation, not
a property of this code. I could not verify compilation and am not claiming otherwise.

A harness is included at `MQL5/Scripts/ScalpRobotPro/EngineCompileCheck.mq5`. It instantiates every
class and touches the entire API surface, with all order-sending calls inside `if(false)` so
signatures are compile-checked without touching an account.

**To verify:** launch MetaTrader 5 once (creating the data folder), copy `MQL5/Include/ScalpRobotPro`
and `MQL5/Scripts/ScalpRobotPro` into it, then compile the harness in MetaEditor. Run it on a demo
chart — it prints environment facts, permission checks, margin math and ownership resolution without
placing a trade.

**What was verified statically:** every referenced enum, constant and struct field was confirmed
against `Core/Types/` by search; `CErrorHandler::RetcodeToText` was confirmed `static` before being
called unqualified; `STradeRequest` field names and types were confirmed against the struct
definition.

**Fixed during self-review:** `RecordSuccess` originally set `failure_detail` on excess slippage
while leaving `success = true` — a contradictory report. Excess slippage now has its own
`excess_slippage` flag, since the send genuinely did succeed.

---

## Conflict to resolve before compiling

A **second, parallel implementation** of the same engine exists in `Trade/Engine/`, which I did not
create and did not modify:

```
CPositionRegistry.mqh     (525 lines)  read model  — overlaps CEnginePositionManager
CPositionController.mqh   (843 lines)  commands    — overlaps CEnginePositionManager
TradeEngine.mqh            (65 lines)  umbrella header
```

There is **no duplicate class name**, so the two sets coexist without a redefinition error. The
problem is `TradeEngine.mqh`: it includes `CTradeEngine.mqh` and documents an API that does not
match my implementation —

| `TradeEngine.mqh` expects | My `CTradeEngine` provides |
|---|---|
| `CTradeEngine(symbol, errors, publisher, clock, log)` | `CTradeEngine(STradeEngineConfig, clock, publisher, logger)` |
| `Build(magic)` then `Initialize()` | `Initialize()` only (builds internally) |
| `ConfigureSpreadProtection(...)` etc. | configured via `STradeEngineConfig` |
| `OpenMarket(..., STradeGateResult&)` | `Buy()` / `Sell()` with `SExecutionReport&` |
| `Refresh()` | `RefreshAll()` |

`STradeGateResult` is referenced but defined nowhere in the folder.

**Including `TradeEngine.mqh` will therefore fail to compile.** Use the umbrella
`ScalpRobotPro.mqh` (which I updated to include my six files) or include
`Trade/Engine/CTradeEngine.mqh` directly.

**Recommended resolution — pick one stack:**
- *Keep mine:* delete `TradeEngine.mqh`, `CPositionRegistry.mqh`, `CPositionController.mqh`.
- *Keep the other:* delete `CEnginePositionManager.mqh` and my `CTradeEngine.mqh`, then implement
  the API `TradeEngine.mqh` documents.

I left both in place rather than deleting files I did not author. The read-model /
command-object split in `CPositionRegistry` + `CPositionController` is arguably the cleaner
decomposition; my `CEnginePositionManager` combines both roles in one class.

---

## Not included, by design

No strategy, signals, indicators, sizing, or risk rules. Position sizing belongs to
`Risk/IPositionSizer`; stop calculation to `Risk/IStopLevelCalculator`; entry decisions to
`Strategies/IStrategy`. This layer executes and reports — nothing more.
