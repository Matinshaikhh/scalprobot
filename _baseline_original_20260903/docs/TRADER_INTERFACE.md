# Trader Interface — Phase 4

The layer the trader actually sees, and the layer that records what happened.
Eleven files, 6,105 lines, `MQL5/Include/ScalpRobotPro/Interface/`.
**Compiles 0 errors, 0 warnings.**

Five subsystems: Professional Dashboard, Chart Objects, Trade Manager,
Enterprise Logging, Performance Analytics. One facade, `CTraderInterface`,
composes them.

---

## The governing constraint

This layer touches the chart and the disk, and it runs on every tick of a
scalping EA. Three rules follow from that, and they explain most of the design:

1. **The UI cannot reach the engine.** Every widget reads one struct,
   `SDashboardModel`, whose fields are all copies. There is no pointer from any
   visual class to a position, an executor or the trading engine. A UI defect can
   garble a label; it cannot move a stop loss.
2. **The trade manager decides, it does not execute.** Every method returns an
   `STradeIntent`. Order sending stays in the Phase 1 trade engine. This is what
   lets nine management rules be verified without a broker connection.
3. **Nothing here may block trading.** A full disk, a refused file handle, a
   sandbox with writes disabled — all are counted and swallowed. Logging failure
   is never allowed to stop position management.

---

## Files

| File | Lines | Responsibility |
|---|---|---|
| `Types/InterfaceEnums.mqh` | 142 | Shared vocabulary. All prefixed. |
| `Types/InterfaceStructs.mqh` | 297 | Passive DTOs, including the UI firewall struct. |
| `Dashboard/CUiTheme.mqh` | 229 | 3 themes, semantic tone → colour. |
| `Dashboard/CObjectPainter.mqh` | 523 | The only class that calls `ObjectCreate`. |
| `Dashboard/CDashboardPanel.mqh` | 375 | Renders the 18 required metrics. |
| `Chart/CChartOverlay.mqh` | 674 | The 15 draw layers. |
| `Manager/CTradeManager.mqh` | 915 | The 9 management rules. |
| `Logging/CLogChannelWriter.mqh` | 440 | One channel, one format, RAII handle. |
| `Logging/CEnterpriseLogger.mqh` | 893 | Routes to 6 channels, exports 3 formats. |
| `Analytics/CPerformanceAnalytics.mqh` | 1,088 | The 10 required metrics + reports. |
| `CTraderInterface.mqh` | 529 | Composition root and call sequencing. |

---

## Professional Dashboard

All 18 requested metrics: Balance, Equity, Margin, Floating Profit, Today /
Weekly / Monthly Profit, Win Rate, Profit Factor, Average RR, Spread, Latency,
Current Session, News Countdown, Current Strategy, Open Trades, Risk %, Lot Size.

Three classes rather than one, because they change for different reasons:

- **`CUiTheme`** — appearance. Widgets request a *meaning*
  (`SRP_UI_TONE_NEGATIVE`), never a colour, so a light-mode variant is a config
  change instead of an edit to every widget.
- **`CObjectPainter`** — the *only* class in the codebase that calls
  `ObjectCreate`. It tracks exactly what it created and deletes only that, so
  the EA cannot wipe a chart object belonging to a foreign indicator. Creation
  is idempotent: repainting mutates properties rather than recreating objects,
  which is what keeps a per-tick dashboard from flickering.
- **`CDashboardPanel`** — layout and formatting only. Throttled by wall clock.

## Chart Objects

All 15 requested layers: Entries, Stop Loss, Take Profit, Trailing Stop, Order
Blocks, Fair Value Gaps, Liquidity, BOS, CHOCH, Support, Resistance, Trend Lines,
Session Boxes, Trade Labels, Statistics.

`CChartOverlay` **reads Phase 2 output and recomputes nothing** — it consumes the
zone registry, swing detector and structure state. It is a view, not a second
analysis engine.

Two decisions that matter in practice:

- **Per-layer visibility.** Each layer clears and redraws only its own object
  group, so hiding order blocks does not disturb the session boxes.
- **Bar-gated redraw.** Zones do not move intrabar. Redrawing dozens of
  rectangles per tick is the most expensive thing a chart UI can do, so the
  analysis layers redraw on a new bar; trade markup updates as levels move.

Object counts are capped (zones, swings, labels). An unbounded overlay
eventually becomes both unreadable and slow.

## Trade Manager

All 9 requested behaviours: Break Even, Trailing Stop (fixed and ATR), ATR Exit,
Time Exit, Emergency Exit, Scale In, Scale Out, Reverse, Maximum Holding Time.

**Fixed priority order:**

```
emergency > max-hold > time exit > ATR exit > scale out
          > profit protection (break-even / trail) > scale in
```

Capital preservation outranks profit optimisation, and *adding* exposure is
always considered last.

**The one-way stop rule** is enforced centrally in `IsBetterStop()`. No
individual rule can propose a stop that moves against the position — a trailing
stop that can retreat is not a trailing stop. Because it is one gate rather than
a check duplicated in each rule, a new rule cannot forget it.

The manager keeps its own tracking state (peak excursion, which stages have
fired) because a broker position object carries none of that, and both the ATR
exit and profit lock measure from the best excursion. Stage flags are set by
`Notify*` confirmations from the trade engine, so they reflect what actually
happened rather than what was intended.

## Enterprise Logging

Six channels — Errors, Trades, Indicators, Risk Events, Performance, Execution
Time — each to its own file. Three formats — CSV, TXT, JOURNAL — selectable per
channel.

Separation is the point: a risk audit buried under a million indicator lines is
not an audit, and indicator tracing must be switchable off without losing the
error log.

- **Typed front door.** Callers use `LogTrade` / `LogRiskEvent` /
  `LogExecutionTime`, so a numeric column means the same thing in every row. A
  CSV where `value_a` is sometimes a price and sometimes a lot size is useless.
  Per-channel CSV headers name the columns accordingly.
- **It implements `ILogger`.** Every Phase 1–3 module already holds an
  `ILogger*`, so the whole existing codebase can be pointed at this with **zero
  changes to those modules**; severity maps to a channel automatically.
- **`JOURNAL` writes no file.** It narrates to the MT5 Experts tab, which is the
  only export that survives a sandbox with file writing disabled. Errors are
  mirrored there by default so a live operator sees them immediately.
- Daily rotation, append-on-restart (a mid-session restart must not destroy the
  morning's audit trail), and buffered flushing.
- A 256-record ring buffer backs export, so an operator can dump the session
  without disturbing a single open log file.

## Performance Analytics

All 10 requested metrics: Profit Factor, Sharpe Ratio, Sortino Ratio, Recovery
Factor, Maximum Drawdown, Average Win, Average Loss, Trade Duration, Monthly
Report, Yearly Report.

**Push model.** Trades are pushed in on close; the class never queries
`HistoryDeals`. An analytics class that reads deal history is untestable, and in
the Strategy Tester it re-reads everything on every call. Pushing one
`SClosedTrade` is O(1) and behaves identically live, in the tester and in a
harness. `AddTrade` derives duration, R-multiple and running balance when the
caller omits them.

**Two honesty rules, enforced everywhere:**

1. Ratios with an empty denominator return `0.0`, never infinity. A profit factor
   of "inf" after two winning trades is a lie that sells software and loses
   accounts.
2. Sharpe and Sortino need a sample. Below the configured minimum they return
   `0.0` rather than a number computed from three data points, and `is_valid`
   reports which windows are trustworthy.

Stated rather than hidden: **Sharpe here is per-trade, not annualised**, and
Sortino uses downside deviation about zero. An unlabelled Sharpe is uncomparable
between products. With no losing trade in the sample, Sortino stays at zero
instead of reporting a fabricated ceiling.

**Drawdown** is computed from the balance curve the trades imply, peak to trough.
The balance curve advances across the whole history while the peak is seeded from
the *window's* opening balance — otherwise a monthly report on an account that
has since doubled would measure its drawdown against the original deposit and
report none at all.

Only periods that actually contain trades are emitted in the monthly and yearly
breakdowns; a table with eleven empty rows tells the trader nothing.

A period cache backs today/week/month profit, invalidated on push **and** when
the window start moves — a cached "today" served after midnight is worse than no
cache at all.

---

## Composition

`CTraderInterface` is the facade the EA talks to. Without it, `OnInit` would have
to construct seven objects in the right order and tear them down in reverse —
seven chances to leak a chart object or a file handle.

**Ownership is total and explicit.** The facade `new`s and `delete`s theme,
painter, panel, overlay, trade manager, logger and analytics. It *borrows* the
Phase 2 analysis modules (zones, swings, structure, ATR), which belong to the
engine. Destruction is strictly reverse of construction; the painter is deleted
after panel and overlay because both reference it.

Per-tick call sequence:

```
Render(model)        -> panel.Refresh (time-throttled)
                     -> overlay.DrawAnalysis (bar-gated)
ApplyAnalytics(model)-> fills only the analytics-owned fields
ManagePosition(pos)  -> manager.Track, overlay markup, manager.Evaluate
                     -> returns STradeIntent for the caller to execute
OnTradeClosed(trade) -> analytics.AddTrade, logger, untrack, clear markup
```

`ApplyAnalytics` overwrites only what analytics owns; account and market fields
belong to the caller. Latency comes from the execution-time channel, which is
the only component that has measured it.

---

## Verification

| Harness | Covers | Result |
|---|---|---|
| `P4PanelCheck.mq5` | theme, painter, panel, all 18 metrics | 0 / 0 |
| `P4OverlayManagerCheck.mq5` | 15 layers, 9 rules, one-way stop rule | 0 / 0 |
| `P4LogAnalyticsCheck.mq5` | 6 channels, 3 formats, 10 metrics | 0 / 0 |
| `Phase4CompileCheck.mq5` | full facade integration | 0 / 0 |

Full-project regression: **all 11 authored harnesses at 0 errors, 0 warnings**
(Phases 1–4).

The analytics harness uses a synthetic series with a hand-computable answer
(gross profit 500, gross loss 175, PF 2.857, win rate 57.14%) so the output can
be checked by eye rather than merely compiling. It also asserts the boundary
cases: empty analytics, a single trade below the minimum sample, a profit factor
with no losses, and an out-of-range month.

The trade manager harness asserts the one-way stop rule directly: it moves the
stop deep into profit and re-evaluates, confirming no rule proposes pulling it
back.

### Known pre-existing failures (not authored here, unchanged)

- `Experts/ScalpRobotPro/EngineCompileTest.mq5` — 100 errors. Expects a
  different `CTradeEngine` API from the parallel engine stack.
- `Experts/ScalpRobotPro/ScalpRobotPro.mq5` — 1 error.
  `CTradingEngine::Start` is declaration-only in the Phase 1 architecture
  scaffold.

Both predate Phase 4 and are untouched by it.

---

## Naming

Phase 4 renames only its own symbols; no earlier phase was modified. MQL5 places
enum members in the **global** namespace, and three prior phases had already
claimed the obvious names, so every Phase 4 enumerator carries an `SRP_UI_`,
`SRP_TM_`, `SRP_LOG4_` or `SRP_PA_` prefix. `SRP_LOG4_*` in particular exists
because Phase 1's logger already owns `SRP_LOG_*`.
