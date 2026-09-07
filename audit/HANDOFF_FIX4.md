# HANDOFF — Harness v2, Fix 4 (complete, verified) and Fix 5 (complete, verified)

Written 2026-09-03, updated 2026-09-04. Hand this to a fresh session together
with `audit/AUDIT.md`. Everything below is verified against the tree as it
stands, not recalled.

**Update 2026-09-04 (fourth).** Fix 5 is compiled, deployed and behaviourally
verified: four runs on 2026.09.01–02 real ticks establish that two runs sharing
a pin produce identical geometry *and* identical deal streams, that a different
pin scales every derived distance and changes the orders, and that an unpinned
run labels itself unquotable. §7's table carries the numbers and the one caveat
that goes with them. All five harness-v2 fixes are now built and verified; the
only sub-task still open in §7 is fix 1's stand-down/rearm confirmation.

**Update 2026-09-04 (third).** Fix 5 is built across ten files and pins all
three spread-sampling sites from one input, `InpPinSpreadSample` (default
`0.0` = the live tick = 1.10 behaviour unchanged). It is static-checked only:
`srpcheck` resolves the configuration chain and the touched `StringFormat`
sites are arity-correct, but **nothing has been compiled or run**. What §6
below asked for was delivered as written, with one addition it did not
anticipate — the audit named one sampling site and there are three, so the
engine's second `CSymbolClassifier::Resolve` and `CScalpController` are
pinned too. The reproducibility check in §7 is now runnable and is the
outstanding item, together with fix 1's stand-down/rearm confirmation.

**Update 2026-09-04 (second).** Fix 4 is compiled, deployed and behaviourally
verified: the identity test in §7 shows the 1.00 and 1.10 binaries placing the same
46 orders at the same modelled times and prices. Task 18 (`CHANGELOG.md`) is done.
Task 17 is done except for fix 1's stand-down/rearm confirmation, which the identity
test had to switch off in order to isolate fix 4, and fix 5's reproducibility check,
which cannot run before fix 5 exists. §5 below is kept as the record of what was
built and why. Deltas from the plan as written are in §9.

---

## 1. Where the project stands

The **forensic audit is complete and delivered**: `audit/AUDIT.md` (1,349 lines).
Verdict **C — fundamental redesign**. Do not re-open it; read it for context.

**Step 2 is authorised and underway.** Step 2 is defined in AUDIT.md §8.0 and §11 as
**five measurement-harness fixes and no strategy logic**:

| # | Fix | State |
|---|-----|-------|
| 1 | Separate the daily stand-down flag from the drawdown latch, so a −2% day stands the EA down for the session and rearms next session instead of ending the run | **done** |
| 2 | Measure slippage on server-side SL/TP fills, not only on EA-sent orders | **done** |
| 3 | Commission as a parameter with a non-zero default, feeding the scalp controller's target-viability and early-exit thresholds | **done** |
| 4 | Stamp tick model, cost assumptions and IS/OOS status into every report header at generation time | **done** — compiled, deployed, identity-tested (§7) |
| 5 | Make the derived-distance chain reproducible: log the init spread sample and the twelve values derived from it, and allow each to be pinned | **done, verified** — compiled, deployed, and confirmed by the four-run pass in §7; §6 records what was built |

Then: compile + behavioural verification (task 17), and `CHANGELOG.md`
(task 18 — **done**, `CHANGELOG.md` at the project root, entry zero is the
audit).

---

## 2. Constraints that bind this work

**The Step 2 scope rule, verbatim from AUDIT.md:** "Each of these is independently
verifiable and **none of them changes a trading decision**."

**A scope-honesty admission already made to Matin — do not re-gloss it.** Fixes 1 and 3
*do* change what a run does, through their defaults: fix 1 lets a run continue past a
−2% day, and fix 3 makes trades pay $6/lot, which tightens the cost gate and reduces
trade count. Neither changes an entry rule, exit rule, stop, target or sizing formula.
Fix 4 is clean — a passive observer that counts and formats.

**Project standing rules.** Inspect before modifying. Never blindly optimise
parameters. **Never overwrite originals — version major changes.** Analyse why trades
lose rather than chasing win rate. No martingale, grid recovery, averaging down or
revenge trading. No artificial risk inflation. Prefer expectancy, profit factor,
robustness and controlled drawdown over raw return. Never claim profitability without
sufficient evidence. Avoid curve fitting. Keep dev and OOS data separate. Prefer
simple, explainable logic. Keep a clear changelog. Explain the hypothesis before any
major strategy change.

**Data rule, verbatim:** "Never fabricate or approximate data and present it as real.
For XAUUSD, understand that spot/CFD volume is not centralized. Clearly distinguish
between broker tick volume, broker real volume, futures volume and genuine
options/order-flow data."

**Reporting requirement for every result:** trades, win rate, profit factor, net
profit, gross profit, gross loss, max drawdown, average win, average loss, expectancy
per trade, average R, largest win, largest loss, max consecutive wins, max consecutive
losses, monthly performance, trade frequency, long/short split, performance by session,
performance by regime, testing period, spread/commission assumptions, and **whether the
result is in-sample or out-of-sample**.

**Operational rule, verbatim:** "When the Write or Edit tool has content size limits,
always comply silently. Never suggest bypassing these limits via alternative tools.
Never ask the user whether to switch approaches. Complete all chunked operations
without commentary."

---

## 3. Environment facts (all learned the hard way — do not retest)

- **Windows binaries cannot be executed** from the agent workspace. `MetaEditor64.exe`
  → `Exec format error`. No `wine`, `wine64`, `powershell`, `pwsh`.
  **Matin must run `_build\build.ps1`** for the authoritative `0 errors, 0 warnings`
  compile, and must run the backtests. The agent then reads the resulting logs.
- **No outbound network.** `pip install` → `ProxyError 403`, so **scipy is
  unavailable**; use `math.erf` and `numpy.random.default_rng`.
- `/tmp` does not persist between bash calls. Write intermediates under the outputs
  mount.
- **Static check, run after every edit:**
  ```
  python3 _build/srpcheck.py MQL5 --baseline=_baseline_original_20260903/MQL5 \
    "--chain=scalp_commission_points=SCALP_COMMISSION_POINTS,daily_limit_terminal=GUARD_DAILY_LIMIT_TERMINAL"
  ```
  Last known good: `CHECKS=27 FAILED=0 VERDICT=PASS`. It is baseline-calibrated: the
  MQL5 built-in allowlist is harvested from the untouched tree in
  `_baseline_original_20260903/`, so an incomplete harvest costs sensitivity, never
  precision. `--chain=field=KEY` asserts a config field is plumbed end to end.
- **Tester-agent log rule:** tester agents restart ticket numbering every run, so
  tickets collide across files. Key every cross-file analysis on **(agent, file)**,
  never on ticket alone. Logs live under
  `MetaTrader 5/Tester/Agent-127.0.0.1-30NN/MQL5/Files/ScalpRobotPro/Logs/`.
- Broker fact worth remembering: `SYMBOL_TRADE_STOPS_LEVEL` is **0**, so every
  stops-level clamp in the tree (`*1.5`, `*1.2`) is a no-op.
- XAUUSD on this spec: contract size 100, point 0.01, so **one point is exactly $1.00
  per lot** — measured, by pairing 163 Entry→TradeClosed rows on price, `net ==
  points × volume × 1.0000` to the cent. A commission expressed in points therefore
  reads directly as USD per round-turn lot.

---

## 4. Fix 4 — what already exists

**One new file, `MQL5/Include/ScalpRobotPro/Runtime/CRunProvenance.mqh`, 419 lines.**
It compiles nothing yet because four declared methods have no bodies.

Already written and complete:

- `ENUM_SRP_TICK_MODEL` — `UNKNOWN, LIVE, OPEN_PRICES, OHLC_M1, GENERATED, REAL_TICKS`
- `ENUM_SRP_DATA_SEGMENT` — `UNDECLARED=0, DEV, OOS`; **UNDECLARED is deliberately the
  default** so a run that does not declare its segment self-flags in its own header
- `#define SRP_PROV_TICK_BUCKETS 257`, `SRP_PROV_SPREAD_BUCKETS 65`,
  `SRP_PROV_SPREAD_TRACK 64`
- class `CRunProvenance`, full private member set, full public declaration list
- `CRunProvenance()`, `Configure(symbol,timeframe)`, `Reset()`
- `ObserveTick(const MqlTick &tick,const double point)` — buckets on
  `tick.time - tick.time%60`, so **no `iTime` call, no timeframe dependence, no
  repaint risk**; measures spread as `(tick.ask-tick.bid)/point` from the **tick**, not
  `SYMBOL_SPREAD`, because in a generated pass `SYMBOL_SPREAD` can be derived while
  ask−bid is what the strategy actually paid
- `CloseBar()` — files the finished minute into both histograms; the partial final
  minute is deliberately not filed
- `MedianOf(hist,buckets)` — lower median by cumulative count, returns **−1** when
  there is nothing to average so "no observation" is distinguishable from "observed
  zero"; `MedianTicksPerBar()`, `MedianSpreadsPerBar()`, `AverageSpreadPoints()`
- `SetCostModel(init_spread,commission,execution,reward_ratio,target_min,early_exit_min)`,
  `SetSegment(segment)`
- `TickModel()` — the inference ladder: not tester → `LIVE`; `m_bars<30` → `UNKNOWN`;
  median ticks/min ≤1 → `OPEN_PRICES`; ≤8 → `OHLC_M1`; else median **distinct spreads
  per minute** ≤1 → `GENERATED`; else `REAL_TICKS`
- `IsGeneratedTape()`, `SegmentContradicted()`, `TickModelText()`, `SegmentText()`

**Two design points to preserve, not re-litigate.**

*Why the tick model is inferred at all:* **MQL5 exposes no API for the tester's
tick-generation mode.** The only alternative is an operator's word, and an operator's
word is what produced the problem. Both measurements are printed next to the verdict so
the inference is auditable rather than trusted.

*The known blind spot, already documented in the code:* a real tick feed whose spread
happens to be fixed reads as `GENERATED`. That error direction is the safe one — it
accuses a good tape of being synthetic, never the reverse. Keep this stated in the
printed output.

*Why `SegmentContradicted()` only fires in two directions:* `MQL_FORWARD` is the one
piece of segment evidence the terminal will give up. A forward pass labelled DEV is a
contradiction; declaring OOS inside an optimisation is a contradiction, because an
optimiser searches and searched data is by definition no longer out of sample. OOS
declared in a plain non-forward pass is legitimate — that is exactly what a separate
hold-out run looks like.

---

## 5. Fix 4 — what remains, in order

### 5.1 Finish `CRunProvenance.mqh`

Four methods are **declared but undefined**; the file will not compile until they exist:

```cpp
string CostModelText(void) const;
string Header(void)        const;
string HeaderCsv(void)     const;
string Warnings(void)      const;
```

Write the bodies at the marker `//--- SRP_PROV_APPEND_2` (currently line 415), then
**delete both markers** — `//--- SRP_PROV_APPEND_1` (line 159, inside the class, just
before `};`) and `//--- SRP_PROV_APPEND_2`.

What each must contain:

- **`CostModelText()`** — commission, execution cost, min-reward/cost ratio, the
  sampled init spread, and the two *derived* values `m_cost_target_min` and
  `m_cost_early_exit_min`. If `m_cost_declared` is false, say so explicitly rather than
  printing zeros.
- **`Header()`** — the multi-line block. Must carry: product name + version + harness
  version; symbol and timeframe; `MQLInfoInteger` flags (`MQL_TESTER`,
  `MQL_OPTIMIZATION`, `MQL_VISUAL_MODE`, `MQL_FORWARD`); observed span
  `m_first_tick`→`m_last_tick`; ticks and minutes observed; median ticks/min and median
  distinct spreads/min **as raw numbers**; `TickModelText()` with the words "INFERRED,
  the terminal does not report this"; spread min/avg/max in points;
  `CostModelText()`; `SegmentText()`; and `Warnings()`.
- **`HeaderCsv()`** — one line, comma-free field values (or quoted), for the CSV
  preamble and for grepping across many runs.
- **`Warnings()`** — the explicit list. At minimum: generated tape while the system is
  a scalper (`IsGeneratedTape()`); `m_cost_declared==false`; commission `<= 0`;
  `m_segment==UNDECLARED`; `SegmentContradicted()`; `m_bars<30`.

### 5.2 Expose the cost model from `CScalpController`

`MQL5/Include/ScalpRobotPro/Profiles/CScalpController.mqh`

- **There are no public cost getters.** Public section begins at `:340`. Members:
  `m_stops_level :262`, `m_target_min_points :272`, `m_commission_points :277`,
  `m_max_spread_target_ratio :284`, `m_early_exit_min_points :287`. The ctor leaves
  `m_commission_points(0.0)` at `:483` — **leave that alone**, it is the honest
  "unconfigured" state.
- The cost model currently prints **only when `m_metrics.blocked_cost>0`** (`:1409-1417`).
  Fix 4 needs it unconditionally. Add `string DescribeCostModel(void) const`.
- **`Initialize()` (`:775-810`) samples the spread three separate times into locals and
  stores none of them.** Add a member `m_init_spread_points`, set it **once** at the top
  of the derived-value block, and have all three sites use it. The arithmetic is
  identical — three `SymbolInfoInteger` calls inside one function return the same value —
  so this changes no number; it removes a latent inconsistency and makes the sample
  reportable. Note it in the changelog as such.
- Cost consumers to keep in agreement — `:795` target viability
  (`const double round_trip=spread+m_commission_points+m_execution_cost_points;`),
  `:804` early-exit floor, `:1080` cost block.

### 5.3 Add the data-segment declaration

No `run.*` key namespace exists; **use `general.*`**. `general.direction_mode` is an
existing enum key and is the exact template — enums are stored as `int` in the runtime
struct and cast at point of use. Nine sites, verified:

| File | Line | What to add, modelled on |
|---|---|---|
| `Experts/ScalpRobotPro/ScalpRobotPro.mq5` | new input near the other run-level inputs; assign in the snapshot block near `:576` | `snapshot.daily_limit_terminal = InpDailyLimitTerminal;` |
| `Configuration/CConfigKeys.mqh` | `:21` decl, `:339` defn | `static const string GENERAL_DIRECTION_MODE;` / `= "general.direction_mode";` |
| `Configuration/CConfigurationBuilder.mqh` | `:34` struct field | `ENUM_SRP_DIRECTION_MODE direction_mode;` |
| `Configuration/CConfigurationBuilder.mqh` | `:399` store write | `config.SetInt(CConfigKeys::GENERAL_DIRECTION_MODE,(int)in.direction_mode);` |
| `Configuration/CConfigurationBuilder.mqh` | `:792` defaults | `in.direction_mode=SRP_DIRECTION_BOTH;` |
| `Runtime/CRuntimeConfig.mqh` | `:49` struct field (as `int`) | `int direction_mode;` |
| `Runtime/CRuntimeConfig.mqh` | `:330` Reset | `direction_mode=0;` |
| `Runtime/CRuntimeConfig.mqh` | `:526` read | `out.direction_mode = config.GetInt(CConfigKeys::GENERAL_DIRECTION_MODE,d.direction_mode);` |
| `Runtime/CRuntimeConfig.mqh` | `:792` Describe | `text+=" dailyLimitTerminal="+...;` |

Default **must** be `SRP_SEGMENT_UNDECLARED` (0) at every one of the three default
sites — EA input, builder defaults, `CRuntimeConfig::Reset` — so a config built from
inputs, from defaults, and from an empty store all agree. Fix 3 broke on exactly this
and the three-way agreement is what fixed it.

Add a **validator warning** (not an error) when the segment is UNDECLARED, in
`Configuration/CConfigValidator.mqh::ValidateGeneral` (`:116`). Fix 3's block at the end
of `ValidateCrossConstraints` (`:572`) is the tone to match. Validator map:
`SetSymbolSpec :76`, `ValidateAll :82`, `ValidateGeneral :116`, `ValidateRisk :134`,
`ValidateStopLevels :203`, `ValidateGuards :290`, `ValidateSchedule :353`,
`ValidateNews :379`, `ValidateFilters :407`, `ValidateStrategies :438`,
`ValidateIndicators :492`, `ValidateDashboard :537`, `ValidateCrossConstraints :572`,
`ValidateAgainstBroker :671`.

### 5.4 Wire the observer into `CProductionEngine`

`MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh`

- Add `#include "CRunProvenance.mqh"`, a `CRunProvenance m_prov;` member (by value — it
  owns no resources), `Configure()` + `SetSegment()` + `SetCostModel()` during build/start.
- **Observation point — `OnTickEvent()` (`:1579-1615`): immediately after `m_ticks++`
  (`:1583`) and BEFORE `PassesThrottle()`.** This matters. Placing it after the throttle
  would measure the throttle's sampling of the tape rather than the tape, and the tick
  model inference would be meaningless.
  ```cpp
  m_ticks++;
  MqlTick tk;
  if(SymbolInfoTick(m_config.symbol,tk))
     m_prov.ObserveTick(tk,m_point);   // use whatever point member exists
  if(!PassesThrottle())
     return;
  ```
- **Report surface — `Stop(const int deinit_reason)` (`:1449-1541`).** Print
  `m_prov.Header()` **first**, above the existing run summary, and log it. The existing
  summary prints ticks, managed actions, regime `Describe`/`DescribeDistribution`,
  decision `Describe`/`DescribeDeclines`/`DescribeFunnel`, the `ENTRY GATES:` line
  (`:1490-1497`), risk `Describe`, trade `DescribeStatistics`, accuracy `DescribeFunnel`,
  scalp `DescribeFunnel`/`DescribeMetrics`/`DescribeTiers`, then at `:1524-1539`
  `m_ui.PublishSessionReport()`, `m_ui.ExportAll()`, `m_ui.Shutdown()`, `Release()`.
- **Include fix 2's server-exit block in the header**: `ServerExitSummary()`,
  `ServerExitCount()`, `ServerExitSlippageAvg/Worst/Money()`. Fix 2's members
  (`m_srv_exits`, `m_srv_sl_exits`, `m_srv_tp_exits`, `m_srv_slip_sum`,
  `m_srv_slip_worst`, `m_srv_slip_money`) and `RecordServerExit` are already in place, and
  `Describe()` (`:2936`) already gained `ServerExitSummary()`. **This is the pairing that
  makes fix 4 worth doing:** 99.53% of stop fills (17,154 of 17,235) landed exactly on
  the stop price in the historical logs, which is the OHLC tick model, not execution
  quality — so a near-zero measured slippage figure next to a `GENERATED` tick-model
  verdict is self-explaining, whereas either alone is misleading.
- Slippage sign convention, already adopted in fix 2: **positive always means adverse**,
  for longs and shorts, on stops and targets alike.
- Also relevant: `OnTesterEvent()` (`:2752-2774`) feeds Monte Carlo then returns
  `m_tester.Evaluate()`; `RefreshAccountState()` (`:1664-1672`) calls
  `m_trade.RefreshAll()`; `RiskAllowsEntry()` (`:2084-2105`) holds the position cap.

### 5.5 Stamp the header into the exports

`MQL5/Include/ScalpRobotPro/Interface/CTraderInterface.mqh`

- `PublishSessionReport()` (`:466-483`) — print the header above
  `m_analytics.FormatReport(all)`. Note it returns early when there are no closed
  trades; **the header should still print in that case**, because "no trades" is a
  result that needs its conditions stated too.
- `ExportAll()` (`:485-506`) — writes `trades_<date>.csv`, `monthly_<date>.csv`,
  `session_log_<date>.csv` under `SRP_DATA_FOLDER\Reports`. Put `HeaderCsv()` in as a
  commented preamble line.
- `CLogChannelWriter` has the mechanism if you prefer the header route:
  `m_csv_header :40`, ctor param `:73/:120/:125`, `SetCsvHeader :85`, and it writes the
  header **only on first file creation** (`:261-262`).
- `OnTradeClosed` is at `:386` — the single call site of `LogTradeClosed`, which also
  does `m_analytics.AddTrade(trade)` and `m_manager.Untrack(trade.ticket)`.
- Logger: `LogAnalyticsReport` decl `:138`, defn `:663` in
  `Interface/Logging/CEnterpriseLogger.mqh`.

### 5.6 Version stamp

`MQL5/Include/ScalpRobotPro/Core/Types/Constants.mqh` — `SRP_PRODUCT_VERSION "1.00"` is
**line 12**. Bump it and add a separate `SRP_HARNESS_VERSION "harness-v2"` rather than
overloading the product version. Others in that file: `SRP_PRODUCT_NAME "Scalping Robot
Pro"`, `SRP_PRODUCT_SHORT "SRP"`, `SRP_PRODUCT_BUILD 1`, `SRP_DATA_FOLDER
"ScalpRobotPro"`, `SRP_OBJECT_PREFIX "SRP_"`, `SRP_TIMER_INTERVAL_MS 250`,
`SRP_DASHBOARD_REFRESH_MS 500`.

### 5.7 Verify

```
python3 _build/srpcheck.py MQL5 --baseline=_baseline_original_20260903/MQL5 \
  "--chain=data_segment=GENERAL_DATA_SEGMENT,scalp_commission_points=SCALP_COMMISSION_POINTS"
```
Expect `VERDICT=PASS`. Then ask Matin to run `_build\build.ps1` for the authoritative
compile.

---

## 6. Fix 5 — built 2026-09-04, verified the same day (see §7)

`MQL5/Include/ScalpRobotPro/Profiles/CMarketProfile.mqh` derives **twelve trading
distances from one spread sample taken at init**, with a `10.0` fallback if the sample
fails. Chain sites:

`:830` observed spread (fallback `10.0`) → `:833` multiple → `:834` `max_spread_points`,
`:839` `max_slippage_points`, `:860-864` `sl_min_points`, `:872` `smc_min_gap_points`,
`:878` structure-break buffer, `:884` `sl_fixed_points`, `:886` `tp_fixed_points`,
`:891` `breakeven_trigger_points`, `:893` `breakeven_offset_points`,
`:895` `trail_start_points`, `:897` `trail_distance_points`, `:899` `trail_step_points`.

(Those line numbers are pre-fix-5 and have since moved; the mask sites are now
`:1008-1117`. The named fields did not move.)

`Profiles/CProfileApplier.mqh` holds the snapshot copy and **lacks `sl_min`**.

**Approach:** add a single input `InpPinSpreadSample` (double, `0.0` = use the live
sample) to pin the **root** of the chain. All twelve values are pure functions of that
one number plus `spread_float` and `broker_min`, so one input is both sufficient and
more faithful to the actual defect than twelve separate pins. Log the sample and all
twelve derived values at init.

**AUDIT.md's own constraint on this fix, verbatim:** "**This is a reproducibility fix,
not a design fix** — the design flaw is that a static geometry is being used at all, and
that belongs to 8.2… Making it responsive to conditions is a strategy change and belongs
in step 6, not here."

**What was built, against that plan.** The input and the root pin are as described.
Four things the plan did not anticipate:

1. **Three sampling sites, not one.** `CSymbolClassifier::Resolve` from `OnInit`
   step 1, a *second* `Resolve` inside `CProductionEngine` feeding the regime and
   volatility bands, and `CScalpController::Initialize` feeding the cost model.
   One input pins all three. Pinning only the first would have produced a report
   claiming a reproducibility the cost model did not have.
2. **A `derived_mask` bitfield** (`ENUM_SRP_GEOM_DERIVED`), set as each assignment
   is made, so the log states which distances the code *actually* derived rather
   than which ones it could have. `sl_min_points` is excluded from the count and
   listed apart: it is an intermediate and never reaches the sealed config.
3. **A provenance verdict, not just a log.** `GEOMETRY   :` joins the fix-4 header
   and, under `MQL_TESTER` only, an unpinned run raises `! GEOMETRY NOT PINNED`,
   which denies `QUOTABLE`. Tester-only because a live run's geometry *should* fit
   its broker and an unclearable warning would make the verdict meaningless there.
4. **A negative pin is a validator ERROR.** It would fail the `>0` test, be
   silently ignored, and leave the run claiming to be pinned.

The double `Resolve` and `CProfileApplier`'s missing `sl_min_points` were **left in
place and documented in the source**. Either change would move a trading decision,
which this fix's scope forbids. Full detail in `CHANGELOG.md` under *Fix 5*.

---

## 7. Tasks 17 and 18

**17 — compile + behavioural verification.** Confirm: a run survives a −2% day and
rearms next session (fix 1); the server-exit slippage lines appear (fix 2); pinned
distances reproduce identically across two runs (fix 5); and **no entry or exit differs
from baseline on a period with no daily breach** — that is the test that fix 4 changed
nothing, and it is the one that matters.

**Status 2026-09-04 (second update).** Compile and deploy are done for all five
fixes; the identity test — the sub-task this section calls the one that matters —
is done and PASSED; the fix-5 pass is done and PASSED. One sub-task remains open.
Method and results are in `CHANGELOG.md` under *Verification — the fix-4 identity
test* and *Fix 5 — verified*; artefacts in `_build/_ab/` and `_build/_fix5/`.

| Sub-task | State |
|---|---|
| compile + deploy | **done for fixes 1–5** — 0 errors, 0 warnings; deployed to the MT5 tree. Fixes 1–4 were verified against sha256 `fe1d4db6…` (760,888 bytes); the fix-5 pass ran against sha256 `61e7c7b1…` (769,544 bytes) |
| no entry or exit differs from baseline (fix 4) | **done, PASS** — 46 trade events identical in modelled time, price and order; every funnel, gate and risk counter equal; both sides `final balance 4897.76 USD` |
| server-exit slippage lines appear (fix 2) | **done** — `server-side exits: 14 (SL 14 / TP 0) slip avg +14.21 pts, worst +76.00 pts, total +17.50 USD` |
| survives a −2% day and rearms (fix 1) | **not yet confirmed** — see below |
| pinned distances reproduce across two runs (fix 5) | **done, PASS** — four runs, 2026.09.01–02 real ticks, all `InpRunDataSegment=2`. A and B at `13.0` printed identical 38-line derivation blocks and identical 46-event deal streams (`final balance 9811.52` both). D at `40.0` scaled every derived distance by 40/13 and diverged at event 6 (43 events, `9899.31`), which is what rules out an inert input. C at `0.0` printed `LIVE, read once at init`, raised `! GEOMETRY NOT PINNED` and `! NOT REPRODUCIBLE`, and carried `geom_pinned=no`, `QUOTABLE: NO` |

**Read the fix-5 row with its caveat.** C's init tick was itself 13.00 pts on this
period, so the control placed the same orders as A. It proves the unpinned run
labels itself honestly; run D, not run C, proves the pin has effect. Both halves
are needed and only together do they close audit step 3.

**And the finding the pass produced along the way:** all four runs are
`QUOTABLE: NO`, and with the segment declared the only reason left is
`! STARTUP SPREAD SAMPLE 13.00 pts vs run average 34.17 pts`. That is the harness
working. A pinned run is reproducible; whether its sample represents the tape is a
separate question this fix does not answer, and answering it is strategy work.

**The fix-5 pass, as specified before it was run.** Compile and deploy first, then
three runs over one period,
XAUUSD, real ticks: two with the same positive `InpPinSpreadSample` and one with
the shipping `0.0`. Read in that order —

1. Both pinned runs must print the same `GEOMETRY DERIVATION` block: same sample,
   same twelve distances, same derived count, and `PINNED by InpPinSpreadSample`.
   Identical geometry is necessary but not sufficient, so do not stop here.
2. Both pinned runs must produce **identical deal streams**. `_build/abdiff.py`
   already compares two captures order by order with serial numbers normalised
   away, so point it at the two pinned captures rather than reading them by eye.
3. The unpinned control must print `read from the tick current at init`, raise
   `! GEOMETRY NOT PINNED`, and report `QUOTABLE   : NO`. If it reports `yes`,
   the warning is not reaching the verdict and the fix has failed at exactly the
   point it exists to cover.

A pinned run whose geometry matches but whose deals differ means something else
is still sampling live state, and that is a finding, not a nuisance — record it
rather than rerunning until it agrees.

**One deliberate deviation from the sentence above.** The test did not use "a period
with no daily breach". It used the period whose baseline behaviour is already on record
(2026.09.01 → 2026.09.02, real ticks) and neutralised fixes 1 and 3 by input instead:
`InpDailyLimitTerminal=true` restores the 1.00 latch and `InpScalpCommissionPoints=0.0`
restores the 1.00 cost model. The day limit was in fact breached on both sides
(2.04% against 2.00%) and both logged `EMERGENCY FLATTEN` and stopped, so the code path
fix 1 changes was *exercised and still agreed* rather than avoided — which is strictly
stronger than the breach-free period the sentence asks for. It also let the baseline
side reproduce 4897.76 USD, a figure two 1.00 passes reached on 2026-09-03, which is
what establishes that the staged binary and the generated input set are faithful.

**Why fix 1 is still open.** Neutralising it is exactly what the identity test did, so
that run cannot also confirm it. It needs its own pass: shipping default
`InpDailyLimitTerminal=false`, a multi-day period containing at least one −2% day, and
then read `SESSION STAND-DOWN (n): …, rearms after <date>`
([CProductionEngine.mqh:2981](../MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:2981))
and `standDowns=` in `Describe()`
([:3121](../MQL5/Include/ScalpRobotPro/Runtime/CProductionEngine.mqh:3121)) — the
run must reach the end of the period with entries taken *after* the stand-down, not
merely avoid halting. Weekly and monthly breach routing, which fix 1 also changes and
which no input can neutralise, is untested in either direction.

**Limits of the identity test, stated because they bound what it proves.** One trading
day, 25 signals, 15 entries; the run ends at the daily-limit latch, so nothing after
that point on that day was compared; and the agreement is on this period only —
fixes 2 and 4 are argued inert in general by inspection, not by this run.

**18 — `CHANGELOG.md`. DONE 2026-09-04**, at the project root. Entry zero is the
audit; entry one is `1.10 / harness-v2`, covering fixes 1–5, the honest note that
fixes 1 and 3 alter run behaviour through their defaults, the identity test above,
and the harness-script changes including the two harness defects the identity test
exposed. Updated again when fix 5 landed: fix 5 now has its own section, and the
`Sites` and `Verification commands` sections carry fix 5's line references and chain
check. Updated once more when fix 5's evidence pass ran: the entry's status line now
reads fixes 1–5 compiled, deployed and verified, and the fix-5 section ends in the
four-run result rather than in a list of what had not been run.
Note `docs/RELEASE_NOTES.md` already
documents 1.00 and was left alone — AUDIT.md §11 step 1 asks specifically for
`CHANGELOG.md`.

---

## 8. Two findings worth carrying forward

**The 85-position entry burst.** 2025-01-14 15:34:00, agent 3003: **85 BUY entries at
the identical price 2669.38 from ONE `VwapPullback` signal** (conf 0.89 × 0.63), 18.10
lots total, all stopped out together at 15:36:40 for ≈ **−$4,874**. Same shape on
2025-01-17 and 2025-01-30 (~83 rows, 1 signal, ≈ −$4,700 each), larger on 2025-01-03/06
(800–1,600 closes/day). **This is the plausible mechanism behind "loses 20–25 trades out
of 25"** — not 25 independent trades but a handful of signals fired dozens of times.

Those runs came from an **earlier, unidentified build; do not attribute the burst to the
current source.** The stale-count route is closed in the current tree: `OnTickEvent` →
`RefreshAccountState` → `CTradeEngine::RefreshAll` → `CEnginePositionManager::Refresh()`
rebuilds from a live `PositionsTotal()` scan every tick, before `SeekEntry`, and
`RiskAllowsEntry` (`:2092`) checks `PositionCount() >= max_positions`. Residual exposure
is a **high `max_positions`** — default **2** in the EA (`:117`), **3** in
`CRuntimeConfig` defaults and in the gold profile.

**`CTradeFrequencyFilter` is dead code.** `Filters/CTradeFrequencyFilter.mqh` is
referenced nowhere outside its own file. `filter.min_seconds_between_trades` (default
60) is plumbed through the EA (`:604`), the config keys (`:117/:426`), the builder
(`:579-580/:946`) and the validator (`:425-426`) — and then never enforced. Do not fix
this inside Step 2; it is a trading-behaviour change.

**Announced vs actual geometry mismatch.** The `ScalpEntry` log line announces a
geometry that differs from the one used: announced `target 150 pts` vs tracked
`target=137 pts`; announced `stop 97 pts` vs an actual 91-point stop distance. Directly
relevant to fix 5.

**Fix 5 did not close it, and should not be read as having done so.** Fix 5 makes
the *root* of the geometry reproducible and reports which distances descend from
it. The mismatch above is a different defect — a log line stating one number while
the tracker enforces another — and finding which of the two the broker actually
received means reading the deal stream, not the profile. Still open.

---

## 9. Deltas from the plan above, as built (2026-09-04)

Recorded because §5 is a plan and the tree is now the truth. Nothing here
changes the intent of a step; these are the places a fresh session would
otherwise waste time reconciling.

**§5.3's key landed as `general.data_segment`** — declared and defined as
`CConfigKeys::GENERAL_DATA_SEGMENT` in the General block. A `run.data_segment`
key was written first and removed: `run.*` would have been a singleton
namespace among 30, and `general.*` already holds the run-level plumbing this
sits beside. The EA input is `InpRunDataSegment` (`ScalpRobotPro.mq5:492`) and
was deliberately **not** renamed to match the key — the input name is what
`.set` files and `-Ini` overrides address, and renaming it would silently
invalidate every existing set file.

**§5.7's verify command needs its root argument.** This:

```bash
python _build/srpcheck.py MQL5 --chain=data_segment=GENERAL_DATA_SEGMENT
```

Omit `MQL5` and the checker takes the `--chain=` string as the root and dies
with a `FileNotFoundError` naming a path with `--chain=` inside it, which reads
as a broken checker rather than a missing argument. Also: `CHECKS=26` is
correct and complete for two chains — 8 fixed checks + 9 per chain. An earlier
note of 27 was a miscount, not a lost check.

**§5.2 gained derived-vs-configured tracking** beyond the plan:
`m_exec_cost_derived`, `m_target_min_derived`, `m_early_exit_min_derived`. The
header's "startup spread sample may not represent the run" warning is only
actionable if something actually descended from that sample; if all three
distances were configured explicitly, an unrepresentative sample cost the run
nothing and the warning would be noise.

**A latent misreport was fixed in passing.** `SetCostModel` was being fed
`m_config.scalp_target_min_points` and `scalp_early_exit_min_points`, which are
`0.0` in the ordinary derive-it case, so the header could print a `0.00 pts`
floor for a run that was enforcing a derived one. The effective values are now
read back from `CScalpController` after `Initialize()` via new accessors. Not a
defect introduced by fix 4 — fix 4 is what made it visible.

**`makeset.ps1` needed the three new enum ordinals**
(`SRP_SEGMENT_UNDECLARED/DEV/OOS`). Without them the new input would have been
written to the `.set` file as a bare name, arrived as `0`, and every scripted
OOS run would have reported itself UNDECLARED — the exact omission fix 4
exists to close, reintroduced by the harness.

**`walkforward.ps1` now forwards a segment and reports provenance.** New
`-Segment` (`UNDECLARED` default / `DEV` / `OOS`) → `-Ini
InpRunDataSegment=<ordinal>`; the summary table gained `tape` and `quotable`
columns parsed from each window's provenance block, and a warning counting
windows that produced no provenance block at all. The default is `UNDECLARED`
rather than `OOS` on purpose: the windows run the shipping config unfitted, but
those defaults were chosen with some of this history in view and a script
cannot know how much.

**Fix 5's own deltas.**

- **`walkforward.ps1` gained `-PinSpread <points>`** (default `0.0`) plus
  `spreadPts` and `pinned` columns, a warning counting windows that each
  derived their own geometry, and a warning for pinned windows that disagree
  about the sample — which would mean the override never reached them. The
  default is `0.0` so the script keeps producing what it produced yesterday,
  but **a walk-forward table without the pin was never comparable window to
  window**: window 1 could trade a 95-point stop and window 4 a 200-point
  stop, and the table read that as the edge changing over time. The pin value
  is formatted in invariant culture; a comma-decimal machine would otherwise
  write `InpPinSpreadSample=13,00`, and the `;`-separated override list would
  either read it as `13` or split on the comma.
- **Same input-name-vs-key split as `§5.3`.** Input `InpPinSpreadSample`, key
  `general.pin_spread_sample`. Deliberate, for the same reason: the input name
  is what `.set` files address.
- **`CProductionEngine` prints the derivation block too, not only the entry
  point.** The two print different structs — the entry point's profile and the
  engine's — and in the tester they agree because no tick arrives inside one
  `OnInit`. On a live feed `SYMBOL_SPREAD` moves asynchronously and they can
  differ, which is worth seeing rather than hiding behind one print.
- **The provenance header reports the *engine's* sample**, from the second
  `Resolve`. Stated here because "the spread sample" sounds singular and is
  not.






