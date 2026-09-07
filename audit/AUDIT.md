# ScalpRobotPro — Forensic Audit, Failure Analysis and Redesign Proposal

**Symbol / timeframe:** XAUUSD, M1
**Audited build:** `C:\scalp robot\MQL5` as of 2026-09-03
**Preserved baseline:** `C:\scalp robot\_baseline_original_20260903\` (265 files, byte-identical copy)
**Files modified during this audit:** none. This was a read-only investigation.

**Verdict up front: C — the system needs a fundamental redesign.**
The reasoning is in section 12. The short version: every profitable
backtest in this project was produced by 1-minute OHLC tick generation,
which on this feed models the spread about three times too tight and
cannot represent price action shorter than 20 seconds — for a strategy
whose median holding time under real ticks is 22 seconds. Under real
ticks, with byte-identical inputs over identical days, the same EA goes
from profit factor 1.126 to 0.853. Nineteen defects are catalogued in
section 5 and three of them are Critical, so there is real repair work to
do; but fixing all of it would yield a correctly-implemented version of a
strategy that has never demonstrated an edge on data that can be trusted.
The measurement apparatus has to be rebuilt before the strategy question
can even be asked.

---

## 0. How to read this document, and what the evidence actually is

Every number below is traceable to a file on this machine. Where a claim
rests on the developer's own written notes rather than on something I
could re-run, it is labelled as such and the difference matters — one of
the more consequential findings is that the project's central calibration
dataset cannot exist on this terminal.

**Primary evidence used:**

| Source | What it is | Size / extent |
|---|---|---|
| `MQL5\Experts\`, `MQL5\Include\ScalpRobotPro\`, `MQL5\Scripts\` | the source tree | 209 `.mqh` + 26 `.mq5` = 235 files |
| `MetaTrader 5\Tester\Agent-127.0.0.1-30*\MQL5\Files\ScalpRobotPro\` | per-agent EA logs, CSV trade records, reports | 11 agents |
| `outputs\evidence\tester_20260903.log` | terminal tester journal | 38,396 lines |
| `outputs\evidence\tester_20260902.log` | terminal tester journal | 1,683 lines |
| `outputs\evidence\runs\*.core` | per-run input blocks, optimiser/report inputs stripped, for exact diffing | 8 distinct blocks preserved, covering 8 of the 11 runs |
| `outputs\evidence\an\closed.csv` | every parsed `TradeClosed` row from the January-2025 sweep | 50,967 rows |
| `Bases\MetaQuotes-Demo\ticks\XAUUSD\*.tkc` | real tick history | 594 MB |
| `Bases\MetaQuotes-Demo\history\XAUUSD\*.hcc` | bar history | 163 MB |

The two journals interleave single runs with optimisation passes, so a
reliable run count cannot be taken from either one in isolation. The
authoritative inventory of 11 runs in section 3.2 was assembled by
cross-referencing both journals against the eleven per-agent folders and
the saved reports, and each row there names its own source.

Two structural facts about this evidence shape everything that follows.

First, the 50,967-row trade population comes from a **1,078-pass genetic
optimisation over January 2025**. Those rows are pooled across parameter
sets, so their aggregate profitability is not any single strategy's
result and I do not treat it as one. What they measure reliably is
*mechanics*: how trades die, what R each exit reason yields, how long
positions live, and — decisively — the fingerprints the simulator leaves
on all three.

Second, only five runs in the entire project history used real ticks, and
they contain 196 trades between them. That is a small sample and I say so
in section 3 rather than dressing it up. The case does not rest on it
alone.

---

## 1. CURRENT EA ARCHITECTURE

### 1.1 What is actually the production EA

`MQL5\Experts\ScalpRobotPro\ScalpRobotPro.mq5` is the only production
entry point. It declares roughly 210 `input` variables, builds a
configuration snapshot, and hands everything to a single orchestrator,
`CProductionEngine`, which owns every subsystem and drives them from
`OnTick`. The other `.mq5` files in `Scripts\ScalpRobotPro\` are
compile-checks and probes, not trading programs — but they matter to this
audit, because for several important classes a compile-check script is
the *only* caller in the tree.

### 1.2 The live call graph

Transitive `#include` resolution from `ScalpRobotPro.mq5` gives **81
reachable `.mqh` files out of the 209 in the tree** — meaning **128 files,
61.2% of the header corpus, are never linked into the running EA.**
Widening the net to include every one of the 26 `.mq5` files, harnesses and
compile-checks included, reaches 119, so **90 headers (43.1%) are reachable
from nothing at all.** Most are declaration-only scaffolds: they compile
cleanly, define classes with the right method signatures, and are never
instantiated. This is the single most misleading property of the codebase,
because reading it gives the strong impression of a far more sophisticated
system than the one that runs.

The orphans cluster where it matters most: 17 in `Risk\`, 10 in
`Filters\`, 9 in `Trade\`, 9 in `Indicators\`, 7 in `Strategies\`, 5 in
`News\`. The directories a reader would check to satisfy themselves that
the system is protected are largely the dead ones.

The path a tick actually takes:

```
OnTick
 └─ CProductionEngine::OnTick                        (Runtime/CProductionEngine.mqh)
     ├─ RefreshAccountState  ─────────────────────► CRiskLimitGuard::UpdateAccountState
     │                                               (window rollover runs every tick)
     ├─ ManageOpenPositions ──────────────────────► CTradeManager  (break-even, trail,
     │                                               partials, timeout, early exit)
     │                                               ── runs even while halted ──
     └─ if(m_running) SeekEntry(is_new_bar)          :1539
         ├─ CRiskLimitGuard::RiskAllowsEntry                     gate 1
         ├─ CDecisionEngine::Evaluate                            gate 2
         │   ├─ CSessionManager::Evaluate     (live, blocks outside London/NY)
         │   ├─ CNewsFilter::Evaluate         (live in code, inert in every backtest)
         │   ├─ CMarketContext / CMarketProfile
         │   └─ weighted vote over strategy plugins
         │       ├─ CStructureStrategy   (BOS / CHoCH via CMarketStructure)
         │       ├─ CBlockStrategy       (order blocks via CBlockDetector)
         │       ├─ CGapStrategy         (fair value gaps)
         │       ├─ COrderFlowStrategy   (OBV + MFI + relative TICK volume)
         │       └─ (others, weighted)
         ├─ decision.actionable                                  gate 3
         ├─ risk_rating > max_risk_rating                         gate 4
         ├─ direction_mode                                        gate 5
         ├─ CAccuracyFilter                                       gate 6
         ├─ CScalpController                                      gate 7
         └─ CRiskEngine::EvaluateEntry                            gate 8
             └─ CPositionSizers → COrderManager → CExecutionEngine
```

### 1.3 Authoritative running configuration

This is not inferred. The EA dumps its own resolved config and the broker
spec to `Logs\performance_20260901.csv`:

```
RuntimeConfig XAUUSD PERIOD_M1  magic=20260808 sizing=SRP_SIZING_RISK_PERCENT
risk%=0.25 maxLot=5.00 maxPositions=3  sl=312pts tp=468pts maxSpread=52pts
guards: daily=2.00% weekly=4.00% monthly=8.00% maxDD=8.00%
decision: voteMode=3 minConfidence=0.55 minConfirmations=2
sessions: london=y ny=y tokyo=n sydney=n  interface: dashboard=on overlay=on

XAUUSD | HEDGING | digits=2 point=0.01 tickSize=0.01 | vol 0.0100..100.0000
step 0.0100 | stops=0 freeze=0 | filling=IOC | leverage=1:100 USD
```

Contract size verified empirically from the sizing log: `money_per_lot`
equals `stop_points × $1.00` exactly, so 1 lot = 100 oz and one point
(0.01) is worth $1.00 per lot.

Two consequences worth flagging immediately. `stops=0` means
`SYMBOL_TRADE_STOPS_LEVEL` is zero on this broker, so every
minimum-distance safeguard in the code that is expressed in terms of the
stops level is a no-op. And the configured `sl=312pts / tp=468pts` never
reach an order — grepping the trade logs for "312" or "468" returns zero
occurrences, because the scalp tier overrides both on every trade
(section 5.4).

A third consequence is easy to miss because these look like chosen
numbers. They are not. `maxSpread=52`, `sl=312` and `tp=468` are all
arithmetic descendants of a single spread measurement taken once at
initialisation — 13.0 points on the day this dump was produced. Section
5.5 gives the full derivation and shows that three of the values printed
above can be reproduced exactly from that one tick.

---

## 2. CURRENT STRATEGY EXPLANATION, IN PLAIN ENGLISH

Stripped of the framework, here is what the EA does.

On each new M1 bar during London or New York hours, it asks several
detectors whether they see a setup. The detectors look for a break of
market structure, an order block, a fair value gap, and a volume/momentum
condition built from OBV, MFI and volume relative to a 20-bar average.
Each detector returns a direction and a confidence between 0 and 1. A
weighted vote combines them; the result must clear a 0.55 composite
confidence floor and be backed by at least two confirmations.

If a direction survives the vote, a higher-timeframe check is consulted,
then an "accuracy filter" and a "scalp controller" each get a veto, then
the risk engine sizes the trade at 0.25% of equity and sends a market
order with a server-side stop and target.

Once in the trade, a manager watches it: it moves the stop to break-even
plus a fixed offset once price has travelled far enough, trails the stop
after that, can take partial profit, closes the position early if the
move stalls, and closes it outright on a timeout. At most three positions
may be open. Daily, weekly and monthly loss limits plus a maximum
drawdown limit sit on top.

### 2.1 The parts of that description that do not survive contact with the code

**The higher-timeframe "context" is an EMA slope over two closed bars.**
That is the entire multi-timeframe component. It cannot express trend,
structure or regime in any meaningful sense, and — critically — its 0.55
composite floor can never reject a break-of-structure signal, because the
minimum score such a signal can present is 0.756. The HTF gate is
therefore decorative for the strategy's dominant setup.

**"Order flow" is tick volume, and the code says so.** The header of
`Decision\Strategies\COrderFlowStrategy.mqh` states plainly that "a
retail MT5 feed has no exchange order book and no real trade tape for a
CFD/spot symbol like XAUUSD… Claiming true institutional order-flow data
on this stack would be fiction." That is the correct posture and it
deserves credit. I verified it independently: `MarketBookAdd`,
`MarketBookGet` and `MqlBookInfo` appear **nowhere** in the tree, and no
caller anywhere requests `VOLUME_REAL` — the volume indicator's `kind`
parameter defaults to `VOLUME_TICK` at every construction site. The EA
uses broker tick counts exclusively.

**The break-of-structure detector re-fires on the same event.**
`Intelligence\Structure\CMarketStructure.mqh:244-245` tests for a break
with a *level comparison* — `current_price > last_high.price + buffer` —
which stays true for as long as price remains beyond the level, instead of
firing once on the crossing. Line `:281` then re-stamps
`m_state.last_event_time` on every such evaluation. The staleness gate, the
de-duplication fingerprint and the freshness bonus all key off that
timestamp, so all three are defeated at once.

The buffer that is supposed to prevent this makes it worse. It resolves to
**13 points** (section 5.5), and the code comment at
`CMarketProfile.mqh:874-875` states the intent exactly: *"A break must
clear the level by more than the spread, or every touch reads as a
break."* Under real ticks the spread is 9.5–33.5 points, so the buffer is
frequently *below* the spread and ordinary spread flicker registers as a
structural break. The stated design intent and the implementation
contradict each other.

Observed consequence on 2026-09-01: **13 of 15 trades came from
`BreakOfStructure` firing on six consecutive M1 bars** — one structural
event resampled once per bar, sized as if it were six independent signals.

**The configured stop and target are not the ones used.** The scalp
controller overrides both on every trade (section 5.4), which is why
stop distances in a single session ranged from 95 to 236 points.

**The intended holding horizon is contradicted three times over.** The
GOLD profile sets `time_stop_minutes = 60` and `max_hold_minutes = 240`
(`CMarketProfile.mqh:589-590`) — its author believed gold needed up to four
hours. `InpScalpMaxHoldSeconds = 300` at `.mq5:324` cuts that to five
minutes. The early-exit rule then closes 33.9% of real-tick trades before
they get anywhere, and the observed median hold is **22 seconds**. Three
layers each shorten the horizon and none of them agree, and the shortest
one wins.

**The news filter never filtered anything in any backtest.** The gate is
live in `CDecisionEngine::Evaluate`, but the tester journal records
`news filter DISABLED (tester has no news CSV) - no news blackout will
refuse any trade` on every run. So every backtest in this project traded
straight through every economic release.

**No martingale, grid, averaging-down or loss-multiplier logic exists.**
I looked specifically. Position size is a clean function of equity and
stop distance. Whatever else is wrong here, the risk model is not
dishonest.

---

## 3. COMPLETE FAILURE ANALYSIS

### 3.1 The controlled experiment

This is the centre of the audit. Two runs exist whose trading inputs are
byte-identical and whose tick model differs. After stripping optimiser and
reporting inputs, `diff` of the two input blocks is **empty** — 209
identical trading parameters. Both traded exactly 2026-01-05 → 2026-01-15
and both halted within three minutes of each other on 2026-01-15.

| | 1-minute OHLC | Real ticks |
|---|---|---|
| trades | 166 | 124 |
| win rate | 43.37% | 41.94% |
| **profit factor** | **1.126** | **0.853** |
| net | +289.90 (dep 10,000) | −25.10 (dep 1,000) |
| average R | +0.182 | −0.013 |
| payoff ratio | 1.470 | 1.181 |
| max drawdown | 3.53% | 3.25% |
| **average spread at entry** | **4.4 pts** | **13.7 pts** |
| exits: TP / SL / early / timeout | 65 / 91 / 4 / 6 | 8 / 71 / 42 / 3 |
| **share of trades reaching target** | **39.2%** | **6.5%** |
| fastest exit | 20 s | 1 s |

Order counts reconcile exactly, which confirms that TP and SL are
server-side and that early/timeout exits are market closes: OHLC = 176
orders = 166 entries + 10 closes (4 early + 6 timeout); real ticks = 169
orders = 124 entries + 45 closes (42 early + 3 timeout). Deposits
differed (10,000 vs 1,000) so cash is not comparable and I do not compare
it; R and profit factor are scale-free and are. The coarser 0.01-lot step
at the smaller deposit introduces up to about 8% sizing quantisation on
the real-tick run, which is noise on the margin, not the effect.

The mechanism is visible in one row of that table. Under OHLC the target
is reached 39.2% of the time; under real ticks, 6.5%. The strategy's
edge, as measured, was the simulator letting price glide to the take
profit along an interpolated path that never wobbled enough to trip an
early exit.

### 3.2 The full run inventory: profitability tracks modelled spread and nothing else

| # | Period requested | Model | Days traded | Halted | Trades | WR% | PF | Net | avg R | maxDD% | spread |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026.04.01–07.30 | OHLC | 79 | no | 1510 | 57.62 | **1.397** | +8391.22 | +0.371 | 3.75 | 4.3 |
| 2 | 2026.04.01–07.30 | OHLC | ~79 | no | 1508 | 57.43 | **1.395** | +8341.82 | +0.369 | 3.73 | 4.3 |
| 3 | 2026.04.01–07.30 | OHLC | 51 | 06-16 | 1062 | 59.04 | **1.548** | +6842.79 | +0.794 | 2.59 | 4.0 |
| 4 | 2026.01.01–04.01 | OHLC | 9 | 01-15 | 166 | 43.37 | **1.126** | +289.90 | +0.182 | 3.53 | 4.4 |
| 5 | 2026.01.01–04.01 | OHLC | 9 | 01-15 | 176 | 44.32 | **1.176** | +428.89 | +0.241 | 3.59 | 4.4 |
| 6 | 2025.01.02–02.01 | OHLC | 1 | 01-03 | 28 | 28.57 | 0.516 | −231.04 | −0.367 | 2.79 | 12.1 |
| 7 | 2026.01.01–09.02 | REAL | 9 | 01-15 | 124 | 41.94 | 0.853 | −25.10 | −0.013 | 3.25 | 13.7 |
| 8 | 2025.07.01–08.01 | REAL | ? | ? | 2 | 0.00 | 0.000 | −53.90 | −1.109 | 0.54 | 16.0 |
| 9 | 2026.05.01–07.31 | REAL | ? | ? | 10 | 70.00 | 0.280 | −53.80 | +0.009 | ? | 9.5 |
| 10 | 2026.07.01–07.31 | REAL | ? | ? | 45 | 37.78 | 0.616 | −270.64 | −0.283 | 3.26 | 12.7 |
| 11 | 2026.09.01–09.02 | REAL | 1 | no | 15 | 26.67 | 0.287 | −102.24 | −0.581 | 2.24 | 33.5 |

Every run modelled at ≤4.4 points of spread made money. Every run
modelled at ≥9.5 points lost. Eleven runs, perfect separation; the
probability of that ordering arising by chance if spread were irrelevant
is 1/C(11,5) = 1/462 = **0.0022**.

**Run 6 is the control that rules out the obvious objection.** It is an
OHLC run — but it happened to fall in a period the simulator modelled at a
realistic 12.1-point spread, and it lost, with a profit factor of 0.516.
So the discriminating variable is the modelled cost and path realism, not
the label "OHLC".

### 3.3 The real-tick evidence, stated at its true strength

Pooling all five real-tick runs: **196 trades, all five runs negative,
approximately −25.2 R in total, −0.128 R per trade.** With a per-trade
standard deviation near 1.0 R that is t ≈ −1.80, two-sided p ≈ 0.07.

That is **directionally unanimous but not individually significant**, and
I will not overstate it. The evidentiary weight comes from combining
three independent things: the unanimity across runs (sign test, 5 of 5,
p = 0.031), the perfect spread separation across all eleven runs
(p = 0.0022), and the controlled A/B where the only changed variable was
the tick model. Any one of those alone would be suggestive. Together they
are the reason for the verdict.

### 3.4 Why the spread matters this much: the arithmetic of a 20-second scalp

For a SELL, entry is at the bid but both the stop and the target trigger
on the ask. The adverse barrier is therefore `stop − spread` away and the
favourable barrier is `target + spread` away. For a driftless walk between
two barriers, P(reach favourable first) = adverse/(adverse+favourable).

| spread | stop | target | random-walk WR | cash payoff | break-even WR | gap |
|---|---|---|---|---|---|---|
| 13.0 | 200 | 297 | 37.63% | 1.485 | 40.24% | **−2.62 pp** |
| 33.5 | 200 | 297 | 33.50% | 1.485 | 40.24% | **−6.74 pp** |
| 33.5 | 200 | 200 | 41.63% | 1.000 | 50.00% | **−8.38 pp** |
| 33.5 | 400 | 594 | 36.87% | 1.485 | 40.24% | **−3.37 pp** |
| 13.0 | 400 | 594 | 38.93% | 1.485 | 40.24% | **−1.31 pp** |
| 13.0 | 600 | 891 | 39.37% | 1.485 | 40.24% | **−0.87 pp** |

The gap is the directional accuracy the strategy must supply *before it
earns anything at all*. At a realistic 13-point spread on a 200-point stop
it must beat a coin flip by 2.6 percentage points to break even; at the
33.5 points actually observed on 2026-09-01 it must beat it by 6.7. The
last three rows show the only structural lever that helps: widening both
barriers proportionally dilutes the fixed spread cost, and the handicap
falls by roughly half each time the barriers double. A scalper working
a 95-point stop at 33.5 points of spread is paying **35.3% of its risk
budget to the broker on entry**, and no signal quality recovers that.

The EA cannot currently choose the bottom row of that table, and this is
the point at which the two failures compound. Barrier width is not a
setting an operator selects; it is derived from a spread sample taken once
at initialisation (section 5.5). A calm open produces narrow barriers that
are then carried into whatever spread regime the rest of the session
brings — which is precisely the top-left-to-middle movement in this table,
from a −2.62 pp handicap to a −6.74 pp one, arrived at automatically and
without anything in the code registering that it happened.

### 3.5 The permanent-halt bug: no backtest in this project ever finished a losing period

This is a genuine, serious code defect, and its main effect is on the
*evidence*, not on the P&L.

`InpFlattenOnTrip` defaults to `true` at `ScalpRobotPro.mq5:179`, is
copied to the snapshot at `:559`, and defaults to `true` again in both
`CRuntimeConfig.mqh:339` and `CConfigurationBuilder.mqh:888`. I verified
by grep that neither `Profiles\CProfileApplier.mqh` nor
`Profiles\CMarketProfile.mqh` contains the string "flatten" — the GOLD
profile never overrides it. So `true` is what runs in every backtest.

That single flag is handed to both guards at `CProductionEngine.mqh:585-590`,
and the daily branch of `CRiskLimitGuard` passes it through as the
`flatten_required` verdict at `:463-483`. Then
`CProductionEngine.mqh:2206-2208` routes any `flatten_required` verdict to
`EmergencyFlatten`, which at `:2628-2643` fires **two permanent latches**:

1. `CRiskLimitGuard::TriggerEmergencyShutdown` sets `m_emergency_tripped`
   and persists it. `ClearEmergency` at `:563-578` requires a human
   acknowledgement; its only caller in the tree is
   `Scripts\ScalpRobotPro\Phase2CompileCheck.mq5:231`. The code comment is
   candid: *"No automation path calls this: an emergency stop that clears
   itself is not a stop."*
2. `Halt()` sets `m_running = false`. `Resume()`'s only caller is the
   operator keypress at `CProductionEngine.mqh:2569-2570`, which cannot
   occur in the Strategy Tester.

The daily latch's own midnight rearm at `CRiskLimitGuard.mqh:284-299` does
run — `UpdateAccountState` is on the tick path — but it is irrelevant,
because the other two latches never clear. The result is that **a routine
2% daily loss permanently ends the backtest.**

Observed, verbatim from the journals:

| Run | Requested | Actually traded | Halt message |
|---|---|---|---|
| 3 | 4 months | 51 days | `daily loss 2.05% reached limit 2.00%` |
| 4 | 3 months | 9 days | `2.20%` |
| 5 | 3 months | 9 days | `2.21%` |
| 6 | 1 month | 1 day | `2.31%` |
| 7 | 8 months | 9 days | `EMERGENCY FLATTEN: risk guard: daily loss 2.11% reached limit 2.00%, closed 0` |

The bias this introduces is asymmetric and it flatters the EA. A losing
configuration gets cut off early and looks like it merely had a small
sample; a winning configuration runs until its first bad day and then
stops. **Run 3 reported the highest profit factor of all eleven runs
(1.548) precisely because it halted on 2026-06-16, just as it began to
break down.** Every "good" result in this project's history is a result
that stopped before it could be falsified.

---

## 4. LOSING-TRADE PATTERN ANALYSIS

### 4.1 The January-2025 population, and why it cannot be used the way it looks usable

The largest trade dataset in the project is 50,967 closed trades parsed
from the 1,078-pass optimisation over January 2025. Before using it I ran
three contamination checks. All three failed, and the failures are more
informative than the dataset would have been.

**Check 1 — is any single "strategy" a real sample?** The `OrderBlock`
strategy has exactly **1,078 rows** — one per optimisation pass. All 1,078
have the same R (**−1.0**), the same holding time (**100 seconds**), zero
wins, and total **−$66,382.16**, spread 97–99 rows per agent across all
eleven agents. This is *one deterministic losing trade replayed once per
pass*, not 1,078 trades. Any per-strategy statistic from this pool is
measuring how many parameter sets were tested, not how often a setup won.

**Check 2 — the holding-time lattice.** Across all 50,967 rows there are
only **48 distinct holding times**, minimum 40 s, maximum 1600 s,
**92.18% of them exact multiples of 20 seconds**, and **0.00% under 20
seconds**. Real ticks in run 7 produced a 1-second exit. Twenty seconds is
the OHLC interpolation grid. This is a simulator fingerprint, not market
behaviour.

**Check 3 — the loss distribution.** **12,774 of 12,774 losing trades are
exactly −1.000 R. 100.000%.** Not one is worse than −1.05 R. The worst R
in 50,967 trades is −1.000. Under real ticks the mean loss was −1.124 R
and the worst was −1.800 R.

That third result is the one to keep. In OHLC generation the stop is
filled *at* the stop price, always. Slippage past the stop — the single
most important cost in fast gold — is structurally impossible. A strategy
tuned in that environment is tuned in a world where its worst case is
capped, and it will size and place stops accordingly.

### 4.2 How trades actually die under real ticks

From the controlled experiment, the exit-reason distribution inverts
completely:

| Exit reason | OHLC | Real ticks |
|---|---|---|
| take profit | 65 (39.2%) | 8 (6.5%) |
| stop loss | 91 (54.8%) | 71 (57.3%) |
| early exit (stall) | 4 (2.4%) | **42 (33.9%)** |
| timeout | 6 (3.6%) | 3 (2.4%) |

The stop-loss rate barely moves. What collapses is the take-profit rate,
and what replaces it is the early-exit rule firing on stalls. So the
dominant real-tick failure mode is **not** "wrong direction" — it is
**"right-ish direction, never travels far enough to pay for the spread
before the manager gives up."** That is the signature of a target that is
too far away for the holding horizon, a stop that is too tight for the
noise, or both at once.

### 4.3 The direction-was-right-and-it-still-lost case

The clearest single-day evidence is run 11, 2026-09-01. Gold fell $56.76
that day. **All 15 trades were SELL — the correct side — and 11 of them
lost.** Profit factor 0.287, average R −0.581. A strategy that is on the
right side of a $56 move and still loses two thirds of its trades is not
suffering from a signal problem. It is being taken out by cost and noise
inside the entry-to-exit window.

Two mechanisms, both quantified from the EA's own logs:

**Stop-size dispersion.** The 15 sizing decisions that day used stops of
200, 236, 185, 186, 174, 159, 159, 162, **95**, 148, 154, 179, 188, 196
and 198 points. Minimum 95, median 179, maximum 236 — a **2.48× range
within a single session.** At the 33.5-point spread observed that day, the
95-point stop handed 35.3% of its risk budget to the spread before the
trade had a chance.

**A fixed break-even offset against a variable stop.**
`Interface\Manager\CTradeManager.mqh:612-639` (`EvalBreakEven`) moves the
stop to entry plus a **fixed point offset** once profit exceeds a **fixed
point trigger**. Neither is expressed in R, so both mean different things
on different trades. In this run the offset was **156.0 points** (logged 8
times). Against that day's 236-point stop that is +0.66 R; against its
95-point stop it is **+1.64 R** — beyond the trade's own take-profit, so on
the tightest and most cost-burdened positions the rule can never fire at
all, while on the widest ones it truncates. Same code, opposite effects,
entirely because a constant point offset is compared against a variable
denominator.

Worse, the offset is not even consistent between runs. It is 156.0 points
here because the GOLD profile derives it from `sl_min_points` at
`Profiles\CMarketProfile.mqh:893`, but in the January-2025 sweep the
input default applied instead and it was **20.0 points** — logged 9,241
times. That is 0.08–0.21 R against the observed stop range, and barely more
than the 13.7–33.5 points of spread being paid. The same rule is worth
0.08 R in one configuration and 1.64 R in another, and nothing in the code
records that choice as having been made.

**Signal duplication.** 13 of those 15 trades came from one break-of-
structure event resampled across six consecutive M1 bars (section 2.1). So
the day's loss is largely one bad idea, sized three times over and repeated.

### 4.4 What the optimisation sweep says about the search itself

Two properties of the 1,078-pass sweep are worth recording because they
tell you the optimiser was not finding an edge.

`corr(win_rate, payoff_ratio) = −0.982`. Across the whole parameter space,
win rate and payoff move in near-perfect opposition. That is the signature
of parameters that only trade one off against the other — pulling the
target closer raises the win rate and lowers the payoff by the same
arithmetic amount. It is what you see when there is no directional edge to
find, only a barrier geometry to slide along.

`max_con_losses` is exactly **3.0 in all 1,078 passes, standard deviation
0.0**. A genuine sample of 30+ trades at a 40–55% win rate would produce a
distribution of streak lengths, not a constant. This is another
determinism artifact and it means the "largest consecutive-loss streak"
figure in every report from that sweep is meaningless.

### 4.5 The developer's own headline sample, and a correction to it

`Profiles\CAccuracyFilter.mqh:14-16` and `ScalpRobotPro.mq5:349-352`
both record a measured result of **1,221 trades, 43.90% win rate, 0.948
payoff ratio, over "31 months of XAUUSD real ticks."**
`Profiles\CMarketProfile.mqh:916` cites the same dataset for the claim that
"1268 of 1313 actionable decisions — 96.6% — died exactly here."

Taken at face value, those numbers describe a losing system:

| | value |
|---|---|
| break-even win rate at 0.948 payoff | 51.34% |
| actual win rate | 43.90% |
| **shortfall** | **−7.44 pp** |
| expectancy | **−0.145 R per trade** |
| per-trade SD | 0.967 R |
| standard error | 0.0277 R |
| t statistic | **−5.23** |
| two-sided p | ≈ 1.7 × 10⁻⁷ |
| 95% CI on expectancy | **[−0.199, −0.091] R** |
| cumulative over 1,221 trades | **−176.8 R** |

The entire confidence interval lies below zero. By the project's own
recorded measurement, this strategy loses about a seventh of a unit of
risk on every trade, with overwhelming statistical confidence.

**But the dataset behind those numbers cannot exist on this terminal.**
Real tick history here covers **2025-05-27 → 2026-09-01 — 15.2 months**,
not 31. Bar history covers 2020-01-17 → 2026-09-02 (79.5 months). A
31-month real-tick XAUUSD backtest is not reproducible in this
environment, and given everything in sections 3 and 4.1, the most likely
explanation is that it was an OHLC-modelled run labelled as real ticks.

This is a correction to an earlier view I held during the audit. I had
treated the 1,221-trade sample as the decisive evidence. It is not
decisive, because I cannot reproduce it. Its *direction* is corroborated
independently by the five real-tick runs, so it is not discarded — but its
specific figures must be labelled unverifiable, and, more importantly,
**every calibration constant in the GOLD profile and the accuracy filter
was fitted to that dataset.** If the path was synthetic, the constants
were fitted to a simulator.

---

## 5. CODE BUG AND LOGIC AUDIT

### 5.1 Severity table

| # | Severity | Location | Defect | Effect |
|---|---|---|---|---|
| 1 | **Critical** | `CProductionEngine.mqh:2206-2208` + `:2628-2643`, `CRiskLimitGuard.mqh:463-483`, `ScalpRobotPro.mq5:179` | routine daily-loss latch routed to `EmergencyFlatten`, firing two non-clearing latches | every backtest permanently stops at its first −2% day; all historical evidence truncated and biased favourably |
| 2 | **Critical** | `Intelligence\Structure\CMarketStructure.mqh:244-245`, `:281` | break detection is a **level state test**, true while price stays beyond the level, not an event test; `last_event_time` re-stamped on every such evaluation | staleness gate, de-dup fingerprint and freshness bonus all defeated; one event traded once per bar (13 of 15 trades on 2026-09-01) |
| 3 | **Critical** | `Profiles\CMarketProfile.mqh:828-899` | **every** protective and structural distance in the EA descends from a **single spread sample taken at init** (section 5.5) | the whole trade geometry is a function of one tick; a session that opens calm and turns volatile keeps calm-market stops, targets and break-detection buffers all day |
| 4 | **High** | `Interface\Manager\CTradeManager.mqh:612-639`; offset source `Profiles\CMarketProfile.mqh:893` vs input default at `.mq5:145` | break-even trigger and offset are **fixed point constants** against an ATR-variable stop, and the offset differs by 8× between configurations (156.0 pts in run 11, logged 8×; 20.0 pts in the Jan-2025 sweep, logged 9,241×) | at 156 pts: +0.66 R on a 236-pt stop but +1.64 R on a 95-pt stop, so it can never fire on the tightest trades and truncates the widest. At 20 pts: only 0.08–0.21 R, barely above the spread paid |
| 5 | **High** | `CProductionEngine.mqh:2180-2187` | forces the ATR stop model and passes `scalp_target_min_points` — a **target** constant — into the `fixed_points` **stop** argument | stop geometry is set by a number that means something else |
| 6 | **High** | `Intelligence\Risk\CProtectionManager.mqh:409-426` + `SetStopBounds` (no caller) + broker `stops=0`; floor source `CMarketProfile.mqh:858-864` never copied by `CProfileApplier.mqh` | the design's only stop floor is `sl_min_points`, which is **never transmitted to the engine** — it survives only as a seed for other numbers. `m_stop_min_points` is permanently 0 and the stops-level clamp at `:474-476` never binds | **nothing anywhere prevents an arbitrarily tight stop**; observed minimum 95 pts at 33.5 pts spread |
| 7 | **High** | `COrderManager` `ClampProtectiveLevels` | stop is widened **after** position size has been computed | realised risk exceeds the 0.25% budget by the widening ratio |
| 8 | **High** | `CPositionSizers.mqh:87-98` | uses `SYMBOL_TRADE_TICK_VALUE` where tick size ≠ point | on this symbol tick size = point so it is currently harmless; a broker quoting XAUUSD in 3 digits makes it a **10× sizing error** |
| 9 | **High** | `CExecutionEngine.mqh:491-501` | slippage measured only on orders the EA sends | slippage on server-side SL/TP fills — the dominant slippage in gold — is invisible to every report |
| 10 | **High** | tester journal, every run | `news filter DISABLED (tester has no news CSV)` | no backtest has ever applied a news blackout; all traded through every release |
| 11 | **Medium** | `CScalpController.mqh:785-806`, `:483` | cost model frozen at init and `m_commission_points` defaults to 0.0 (`InpScalpCommissionPoints = 0.0` at `.mq5:329`) | target-viability and early-exit thresholds computed against a zero-commission, opening-spread world |
| 12 | **Medium** | `CScalpController.mqh` uses ATR at shift **1**, `CProtectionManager.mqh` at shift **0** | two subsystems disagree on which bar defines volatility | the shift-0 read samples the *forming* bar, so its value differs systematically between tick models — sizing is coupled to the simulator |
| 13 | **Medium** | `CTradeManager.mqh` `RecordExit:1315-1321` | trailing-stop hits recorded as take-profit | inflates reported TP rate; the 39.2% figure in section 3.1 is an upper bound |
| 14 | **High** | `Profiles\CProfileApplier.mqh` (no `sl_min` reference anywhere) vs `CMarketProfile.mqh:864, 884, 893, 899` | `sl_min_points` is not a field on the runtime snapshot at all, yet four other distances are derived from it | the profile computes a stop floor, uses it to set the fixed stop, the break-even offset and the trail step, and then never passes the floor itself — so the one value intended as a safety limit acts only as a multiplier for others |
| 15 | **Medium** | `CProductionEngine.mqh:2224-2247` | scalp target override always binding | configured `tp=468pts` never reaches an order (0 occurrences of "468" in trade logs) |
| 16 | **Medium** | HTF gate | minimum achievable BOS composite score 0.756 vs 0.55 floor | the higher-timeframe filter is mathematically incapable of rejecting the dominant setup |
| 17 | **Low** | `CProtectionManager.mqh:658-825` | protection engine's only caller is `Phase2CompileCheck.mq5:196-203` | dead code presenting as a feature |
| 18 | **Low** | `Filters\CSessionFilter.mqh` | declaration-only scaffold, never instantiated | dead; the live session logic is `CSessionManager` (see 5.3) |
| 19 | **Informational** | whole tree | 128 of 209 `.mqh` files unreachable from the production EA; 90 reachable from no `.mq5` at all | 61.2% of the header corpus is inert in production, 43.1% is inert everywhere — and the orphans concentrate in `Risk\`, `Filters\`, `Trade\` and `News\` |
| 20 | **High** | `CMarketProfile.mqh:589-590` (60 / 240 min) vs `.mq5:324` (`InpScalpMaxHoldSeconds = 300`) vs the early-exit rule | three layers each shorten the holding horizon and none agree | the profile author designed for a 1–4 hour gold trade; the realised median hold is **22 seconds** |

### 5.2 Repainting, lookahead and data leakage — what I found and did not find

I looked specifically for the classic MQL5 offences and, to the
developer's credit, **found no lookahead bias**: no negative shifts, no
buffer copies that reach past the current bar, no use of a future bar's
close. Entry evaluation is gated on `is_new_bar` and reads closed bars.

There is **repainting-adjacent behaviour** in the shift-0 ATR read at
`CProtectionManager.mqh` (item 12). Reading the forming bar is legitimate
in live trading, but it makes the value tick-model-dependent, so stop
distances are not comparable between an OHLC backtest and a real-tick one.
That is a measurement defect rather than a cheat.

The one genuine state-management leak is item 2, the `last_event_time`
re-stamp. It is not lookahead — it is a stale-state bug that converts one
signal into many.

**On the prohibited recovery patterns, the code is clean, and deliberately
so.** I searched the whole tree for martingale, grid and averaging-down
constructs. Every one of the six `martingale` hits is either a prohibition
or an *anti*-martingale: `CPositionSizers.mqh:445`, `:449` and `:521`
shrink size after consecutive losses, `CScalpController.mqh:32` states "NO
MARTINGALE, STRUCTURALLY. This class never returns a volume", and
`CPercentRiskSizer.mqh:23` reduces size in drawdown. There are zero hits
for `lot_multiplier`, `recovery_lot`, `grid_step` or `GridStep`, and every
`average`-family identifier in the tree is a moving average or a
statistic. `max_con_losses` is 3 with standard deviation 0.0 across all
1,078 optimisation passes, which is what a hard consecutive-loss cap looks
like rather than a recovery mechanism.

The one construct worth naming explicitly is the scale-in facility
(`InpScaleInEnabled`, `.mq5:154-157`). It is **pyramiding, not averaging
down**: `CTradeManager::EvalScaleIn:698-712` requires
`position.profit_points >= m_scale_in_trigger_points` before it will add,
so it can only add to a position already in profit. It is also `false` by
default at `:230`, no profile enables it (grep for `scale_in` across
`Profiles\` returns nothing), and it is `false` in all eight preserved run
cores. It has never been active in any result in this project.

Two things follow from the above. Reported drawdown is not being hidden by
position management, so the losses in section 3 are the real losses. And
the risk framework was written by someone who understood which patterns to
avoid — which is part of why the failure is upstream of the code rather
than in it.

### 5.3 Corrections to findings made earlier in this audit

Three earlier conclusions were wrong and are corrected here so they are
not repeated:

`CSessionManager` **is live.** It is wired in via
`m_decision.SetCollaborators(m_sessions, m_news, m_context)` at
`CProductionEngine.mqh:935` and does gate entries inside
`CDecisionEngine::Evaluate`. The dead class is the separate
`Filters\CSessionFilter.mqh` scaffold.

The **news gate is live in code**, not absent. It is inert in backtests
only because the tester has no news CSV.

**Commission is not ignored at close.** `DEAL_COMMISSION` is read at
`CProductionEngine.mqh:2468` and added into `net_profit`. What is missing
is commission in the *decision-time* cost model, which defaults to zero
(item 11). On this demo account commission was in fact zero, so reported
net equals gross — but a real XAUUSD account charging $7 per lot
round-trip costs 7 points, which is 3–7% of the observed stop range.

### 5.4 Why the configured stop and target never reach an order

The configuration says `sl=312pts tp=468pts`. No order ever used them.
Three layers overwrite them in sequence:

`CProductionEngine.mqh:2180-2187` forces the stop model to ATR regardless
of configuration, and passes `scalp_target_min_points` into the argument
that the protection manager treats as a *fixed stop distance*.
`CProductionEngine.mqh:2224-2247` then applies a scalp target override
that is always binding. Finally `CMarketProfile.mqh:828-899` has already
derived the ATR multipliers and point floors from the spread sampled at
init.

The net effect is that stop and target are set by a chain of derived
values with no single owner, which is why they varied 2.48× within one
session while the user-visible configuration claimed two constants.
Grepping the trade logs for "312" or "468" returns zero occurrences.

This matters beyond the bug itself: **the parameters exposed for
optimisation are not the parameters that control the trade.** Every
optimisation run in this project was searching a space partly disconnected
from the behaviour it was scoring.

### 5.5 Every distance in the EA descends from one tick

This is the finding I did not expect, and it is fully traceable. The GOLD
profile ships with `max_spread_points = 0.0`, meaning "resolve from the
broker" (`CMarketProfile.mqh:241`). At `:828-835` that resolution happens
**once, at initialisation**, from a single spread sample:

```
observed = (symbol.spread_current > 0 ? symbol.spread_current : 10.0)  // ONE sample, at init
multiple = (symbol.spread_float ? 4.0 : 2.0)
max_spread_points = max(observed*multiple, observed+10.0)
```

The EA's own config dump reports `maxSpread=52pts`. Working backwards
through a floating-spread multiple of 4.0, the sampled spread was
**13.0 points**. Every subsequent distance follows from that one number:

| Derived value | Formula (`CMarketProfile.mqh`) | Result | Confirmed by |
|---|---|---|---|
| `max_spread_points` | `13.0 × 4.0` | **52** | config dump `maxSpread=52pts` |
| `max_slippage_points` | `52 × 0.5` | 26 | `:839` |
| `sl_min_points` | `max(max(0×1.5, 0+10), 52×3)` | **156** | `:858-864`; broker `stops=0` |
| `sl_fixed_points` | `156 × 2.0` | **312** | config dump `sl=312pts` |
| `tp_fixed_points` | `312 × 1.5` | **468** | config dump `tp=468pts` |
| `breakeven_trigger_points` | `312 × 0.6` | 187.2 | `:891` |
| `breakeven_offset_points` | `= sl_min_points` | **156** | logged `break-even at +156.0 pts`, run 11 |
| `trail_start_points` | `312 × 0.8` | 249.6 | `:895` |
| `trail_distance_points` | `312 × 0.6` | 187.2 | `:897` |
| `trail_step_points` | `max(156 × 0.2, 1)` | 31.2 | `:899` |
| `smc_min_gap_points` | `max(52, 20)` | **52** | `:871-872` |
| `smc_structure_break_buffer` | `max(52 × 0.25, 5)` | **13** | `:876-878` |

Three of those — 52, 312, 468 — appear verbatim in the EA's own config
dump, and a fourth, 156, appears verbatim in the trade log. The chain is
not an inference.

Two things follow. First, **the entire trade geometry of this EA is a
function of the spread on one tick at startup.** Not a measured
distribution, not a rolling average — one sample. Run the same EA at a
different minute and every stop, target, trailing distance and
structure-break threshold changes.

Second, and more subtly, `max_spread_points` is a *ceiling* — the largest
spread the EA will tolerate — and it has been made the unit of measure for
everything else. So the structure-break buffer ends up at 13 points, which
is exactly the sampled spread and well below the 33.5 points observed on
2026-09-01. A parameter whose job was to reject bad conditions is being
used to define what counts as a structural event.

This also explains why `sl=312pts` and `tp=468pts` never reach an order:
they are the *fixed-model fallbacks*, computed and then discarded by the
ATR override at `CProductionEngine.mqh:2180-2187`, while 156 — the seed
they were built from — survives as the break-even offset. Nobody chose
that; it is what the derivation chain produced.

---

## 6. AVAILABLE DATA AUDIT

Everything in this section was verified on this machine. Nothing is
estimated.

### 6.1 Local MT5 history

| Data | Coverage | Storage | Size |
|---|---|---|---|
| XAUUSD **real ticks** | **2025-05-27 → 2026-09-01 (15.2 months)** | `.tkc`, one file per month | 594 MB |
| XAUUSD **bars** | 2020-01-17 → 2026-09-02 (79.5 months) | `.hcc`, one file per year | 163 MB |

This is the hard constraint on everything that follows. Tick-accurate
validation is possible over **15.2 months only**. Bar data reaches back
6.6 years but, as sections 3 and 4 established, bar-derived tick
generation is not a valid environment for a 22-second-hold strategy. So
the usable, trustworthy sample is 15.2 months — enough for perhaps two or
three genuinely independent regime segments, not enough for a
heavily-parameterised model.

If longer real-tick history is wanted it must be downloaded from the
broker (Tools → Options → Charts → unlimited bars, then a full symbol
refresh) or bought from a tick vendor, and its provenance recorded. I
would not proceed on the assumption that more is available until it has
been verified on disk.

### 6.2 Spread and cost reality

| Model | Average spread at entry |
|---|---|
| 1-minute OHLC generation | **4.0 – 4.4 points** |
| Real ticks | **9.5 – 33.5 points** |

The OHLC model understates spread by roughly a factor of three because it
takes the spread from the M1 bar record rather than from the tick tape.
This is the proximate cause of every false-positive result in the project.

Commission and swap are 0.00 in every report on this demo account.
Commission on a live XAUUSD account is typically $3–$7 per lot per round
trip, which on a 100-oz contract is 3–7 points. **Treat commission as
unknown-but-nonzero, not as zero.** Slippage cannot currently be measured
at all on the exits that matter (item 9).

### 6.3 Volume: what this feed does and does not provide

The EA reads **broker tick volume** exclusively — a count of price
updates, not traded contracts. Verified: every construction site of the
volume indicator and of the OBV/MFI wrappers takes the default
`VOLUME_TICK`; no caller anywhere requests `VOLUME_REAL`. The code's own
validation warning is accurate: *"real volume requested; many FX/metals
feeds report zero."*

There is **no order book on this stack.** `MarketBookAdd`,
`MarketBookGet`, `MarketBookRelease`, `MqlBookInfo` and `BOOK_TYPE` each
return zero hits across all 235 source files. No DOM, no
Level 2, no bid/ask executed-volume split, therefore no genuine footprint,
no real CVD, no absorption measurement. Tick volume correlates with
activity and is a legitimate proxy for *participation intensity*; it is
not order flow and must never be labelled as such.

---

## 7. ADVANCED DATA OPPORTUNITIES

### 7.1 The timescale test, applied first

Before assessing any external feed I applied one filter: **does it update
faster than the holding period it is meant to inform?** The strategy's
median hold under real ticks is 22 seconds. A daily or weekly dataset
cannot inform a 22-second decision except as a slow-moving regime label,
and a regime label is only worth its integration cost if it changes the
trade/no-trade decision often enough to matter.

That test eliminates most of the impressive-sounding list immediately, and
I would rather say so than build an elaborate data pipeline that cannot
possibly pay for itself.

| Source | Real update frequency | Useful to a 22-second scalp? |
|---|---|---|
| CFTC Commitments of Traders | weekly, published Friday for Tuesday | No. Three-day publication lag; a positioning snapshot cannot time an M1 entry |
| Options positioning / gamma exposure (GEX) | daily, and for *futures* options not spot | No, for this strategy. Dealer gamma levels are price magnets on a multi-day horizon |
| COMEX GC futures volume & open interest | tick-level during CME hours, but a **different instrument** | Possibly — see 7.3 |
| DXY | continuous | Marginally. Correlation is real but the beta is unstable intraday |
| US Treasury yields (2y/10y real) | continuous during cash hours | No at this timescale; a macro-regime input at best |
| Economic calendar | scheduled, known in advance | **Yes — and it is free.** See 7.2 |
| Broker spread and tick-arrival rate | continuous, already on this machine | **Yes, highest value per unit of effort.** See 7.2 |

### 7.2 The two data improvements I would actually make, both local and free

**Liquidity state from the tick tape.** Spread and tick-arrival rate are
already streaming into the terminal and are already stored in the `.tkc`
files, so this is historically testable over the full 15.2 months with no
external dependency. The evidence in section 3 says the single largest
determinant of this system's outcome is the spread it pays. A strategy
that measures the current spread against its own recent distribution and
refuses to trade in the worst decile is acting directly on the strongest
relationship in the data. This is not a sophisticated feature; it is the
one the evidence demands.

**A real economic calendar.** MT5 exposes the broker's calendar natively
through `CalendarValueHistory` / `CalendarEventById`, which works in the
Strategy Tester on builds that support it, and the events carry proper
timestamps and importance levels. The current news gate is well-built and
never runs. Populating it costs little and removes a category of loss the
EA is presently fully exposed to.

### 7.3 COMEX GC futures — the one external feed with a real case, and its real cost

The honest case for GC futures is that they are the price-discovery venue
for gold and they publish **genuine centralised traded volume**, which
spot XAUUSD does not have. Aggressive volume at the futures bid/ask is the
closest thing to true order flow available for this asset.

The honest costs: it is a different instrument with a basis that moves; it
trades CME hours with a daily maintenance break that does not align with
the spot session; consolidated tick data with bid/ask volume split is a
paid subscription (CME DataMine, or a vendor such as Databento or Rithmic
— pricing needs to be checked at the time of purchase, I have no network
access from this environment to verify current figures); historical
depth-of-book is expensive; and timestamp alignment between a vendor feed
and this broker's clock has to be established and re-verified, because a
few hundred milliseconds of misalignment on a 22-second trade is not a
detail.

**My recommendation is to not integrate it yet.** It is the right feed to
reach for *if and when* a validated harness shows that a locally-available
strategy has an edge that is being limited by an inability to see
aggressive volume. Buying it before that point risks spending real money
to add a variable to a system whose measurement apparatus is not yet
trustworthy — which is precisely the mistake this project has already made
once with tick volume.

### 7.4 What I am explicitly not proposing

No footprint charts, no absorption detection, no CVD, no dealer
positioning model, no DOM-based logic. Not because they are without merit
in general, but because **the data required to compute them honestly does
not exist for spot XAUUSD on this stack**, and computing them from tick
volume would produce numbers that look like order flow and are not. Under
the project's data rule that is fabrication, whatever the variable names
say.

---

## 8. PROPOSED NEW STRATEGY ARCHITECTURE

### 8.0 Step zero, before any strategy work: a trustworthy measurement harness

This is the most important recommendation in the document. Every piece of
evidence this project has produced was generated by an apparatus that
cannot measure what it claims to measure. Building a better strategy on top
of it would mean repeating the last cycle with more effort.

The harness has to establish five things before a single entry rule is
written:

Real ticks only, for every result that is allowed to influence a decision.
OHLC generation may be used for compile-and-smoke tests and for nothing
else. Any report must carry its tick model in its header so the two can
never be confused again.

The permanent-halt defect fixed, so that a backtest survives its bad days.
A daily loss limit should stand the position down for the rest of the
session and rearm at the next session; only a drawdown breach should latch.
That is a one-line separation of two flags that are currently one.

Slippage measured on server-side stop and target fills, not only on
EA-sent orders. Without it the cost model is blind on the exits that
dominate.

Commission entered as a parameter with a non-zero default, and every
reported result labelled in-sample or out-of-sample at the point of
generation rather than in retrospect.

And the derived-distance chain of section 5.5 made visible and pinnable.
At present the stop, target, break-even offset, trailing distances,
spread ceiling and structure-break buffer are all computed from one
spread sample taken at startup, and none of them is recorded anywhere
except by inference from a config dump. Log the sample and all twelve
derived values, and allow each to be overridden by an explicit input.
This is a reproducibility fix, not a design fix — the design flaw is that
a static geometry is being used at all, and that belongs to 8.2.

Only when the same run, repeated, gives the same numbers, and those numbers
move sensibly when costs are varied deliberately, is the harness worth
trusting.

### 8.1 The structural change the arithmetic requires

Section 3.4 shows the spread cost is a fixed toll and the only way to
dilute it is to widen both barriers. At 13 points of spread, a 200-point
stop needs 2.62 points of edge over a coin flip; a 400-point stop needs
1.31, and a 600-point stop 0.87. Meanwhile the real-tick exit distribution
(4.2) shows the dominant failure is trades that never travel far enough
before the manager gives up.

Both point the same way: **this system is trying to scalp at a horizon
where the cost is too large a fraction of the target.** My proposal is to
keep the entry logic's character — structural, intraday, gold — but move
the holding horizon out from ~22 seconds to the several-minute to
one-hour range, with barriers scaled to measured volatility rather than to
a spread sampled at init.

I want to be careful about what I am and am not claiming. I am **not**
claiming a longer hold is profitable — that has to be tested. I am
claiming that the 22-second horizon is arithmetically the hardest place to
find an edge on this instrument at this cost, and that there is no
evidence in this project that an edge exists there.

### 8.2 The layered design

**Layer 1 — Higher-timeframe context.** H1 and H4 swing structure: the
last confirmed higher-high/higher-low or lower-high/lower-low sequence,
plus the previous day's high, low and close, and the current day's opening
range. *Reason for existing:* the present HTF layer is a two-bar EMA slope
that cannot reject the setup it is meant to filter. A trade taken into the
opposing side of a confirmed H1 structure is a materially different bet
from one taken with it, and that distinction is currently unrepresented.

**Layer 2 — Market regime, and the authority to stand down.** Three
measurements, each with a defined refusal: realised volatility over the
last N minutes against its own distribution for this time of day (refuse
the bottom decile — dead tape); spread against its own recent distribution
(refuse the worst decile — this is the section 6.2 finding acted upon);
and a trend/chop discriminator such as efficiency ratio or ADX (route to
different setups rather than refusing). *Reason for existing:* this is the
layer that lets the system stay out, which the brief explicitly requires
and which the current EA has no mechanism for beyond a fixed 52-point
spread cap.

**Layer 3 — Liquidity and structure.** Prior-session highs and lows,
equal highs/lows as resting-liquidity pools, and sweep detection: a
penetration of such a level followed by rejection back through it within a
bounded number of bars. *Reason for existing:* a sweep gives a
*specifically located* invalidation point, which is what makes a tight
stop defensible instead of arbitrary. The current EA's stops are derived
from an ATR chain with no reference to where price would prove the idea
wrong.

**Layer 4 — Setup.** Two, at most, and each must be independently testable
and independently reportable. A continuation entry on a displacement leg
in the direction of H1 structure, and a reversal entry on a liquidity
sweep of a prior-session extreme against an overextended move. *Reason for
existing:* the current engine votes across four-plus correlated detectors
reading the same M1 bars, which manufactures false confirmation. Two
uncorrelated setups, each with its own statistics, is more information than
five correlated ones blended into a single number.

**Layer 5 — Confirmation, with a hard rule.** One confirmation per setup,
and it must be uncorrelated with the trigger. A structural trigger may not
be confirmed by another structural read of the same bars. Tick-volume
expansion relative to the same minute-of-day in recent history is
acceptable because it measures participation rather than geometry.
*Reason for existing:* `minConfirmations = 2` is currently satisfiable by
two views of one event, which is exactly how one break-of-structure became
thirteen trades.

**Layer 6 — Execution.** One position per setup instance, enforced by a
fingerprint on the *originating event* rather than on the evaluation time —
this is the direct fix for defect 2. A single owner for stop and target
geometry, so that no downstream layer may silently override it. Both
expressed as ATR multiples with an absolute floor that is actually wired
in, since the broker supplies no minimum. Explicit refusal to enter when
`spread / stop_distance` exceeds a configured ceiling — on the evidence, a
95-point stop at 33.5 points of spread should never have been permitted to
trade.

**Layer 7 — Dynamic risk management.** Break-even and trailing expressed
in **R, never in points**, which fixes defect 4 by construction. Risk per
trade fixed and modest; the 0.25% currently configured is sensible and I
would not change it. Position sizing computed *after* all clamping, so
realised risk matches intended risk. Daily stand-down that rearms; a
latching drawdown limit that does not. Correlation-aware position limits,
so three concurrent positions cannot all be the same idea.

---

## 9. TESTING PLAN

### 9.1 The data split, fixed now and not revisited

Real ticks cover 2025-05-27 → 2026-09-01. I propose splitting it once, in
writing, before any development:

| Segment | Period | Use |
|---|---|---|
| **Development** | 2025-05-27 → 2026-02-28 (9.1 months) | all exploration, all parameter selection, all failed ideas |
| **Validation** | 2026-03-01 → 2026-09-01 (6.0 months) | locked; touched only for final confirmation of a frozen candidate |

The validation segment gets **one look per candidate strategy.** If a
candidate fails there, it is not adjusted and re-run — that converts the
validation set into a second development set, which is the most common way
an honest process becomes a dishonest one. It goes back to development
with the failure recorded in the changelog.

Six months of M1 gold at a several-minute horizon should produce a few
hundred trades, which is a workable but not luxurious out-of-sample
sample. That constraint argues strongly for a *small* number of parameters,
and it is the reason section 8.2 caps the design at two setups with one
confirmation each.

Bar history back to 2020 may be used for one purpose only: sanity-checking
that a rule is not obviously specific to 2025–2026 conditions. Any result
from it must be labelled bar-generated and may not be used to select
parameters.

### 9.2 The hypothesis format every change must satisfy

No component enters the system without this filled in first, in the
changelog, before the test is run:

| Field | Requirement |
|---|---|
| Setup | the exact observable condition |
| Entry trigger | the exact event and the bar/tick it is evaluated on |
| Invalidation | what would prove the idea wrong, expressed as a price level |
| Stop | derived from the invalidation, not chosen for its R |
| Target | with the reasoning for its distance |
| Required confirmation | and why it is uncorrelated with the trigger |
| Regime where it should work | and, explicitly, where it should not |
| Minimum sample | before the result is allowed to influence anything |
| Metric that decides | chosen in advance |
| Predicted failure mode | what should show up if the hypothesis is wrong |

The last row is the one that keeps this honest. A hypothesis that does not
say in advance how it could fail cannot be falsified by a backtest.

### 9.3 Acceptance thresholds, set in advance

A component is kept only if, on development data, it improves expectancy
per trade by an amount larger than its standard error, and does not achieve
that improvement solely by reducing trade count below the minimum sample.
A component that improves profit factor while lowering expectancy per trade
is rejected — that is usually just a tighter target.

A candidate strategy is promoted to validation only when, on development
data, it shows positive expectancy after a **deliberately pessimistic cost
model**: real ticks, plus a commission of 7 points round trip, plus a
spread stress test at 1.5× the observed distribution. If an edge does not
survive being charged more than it will really pay, it is a cost artifact,
not an edge. The current EA fails this test in the opposite direction —
it only survives being charged *less* than it will really pay.

### 9.4 What every report must contain

Number of trades, win rate, profit factor, net profit, gross profit, gross
loss, maximum drawdown in percent and currency, average win, average loss,
expectancy per trade in R, average R, largest win, largest loss, maximum
consecutive wins, maximum consecutive losses, monthly breakdown, trade
frequency, long/short split, performance by session, performance by
volatility regime, testing period, tick model, spread and commission
assumptions, and in-sample or out-of-sample status.

Two of those deserve emphasis given what this audit found. **Tick model**
must appear in every report header, because its omission is how this
project spent its development cycle optimising a simulator. And **maximum
consecutive losses** must come from a run that was not permanently halted,
or the figure is meaningless — as it was in all 1,078 passes of the
January-2025 sweep, where it was exactly 3.0 with zero variance.

### 9.5 Baseline for comparison

The baseline the new work must beat is not the current EA's best
backtest — that number is an artifact. It is the current EA measured
honestly: **real ticks, halt bug fixed, pessimistic costs.** On present
evidence that baseline is somewhere around −0.13 R per trade. Establishing
it properly is the first test to run after the harness is fixed, and it
should be run and recorded before any new strategy code exists, so that
every later comparison has a real reference point.

---

## 10. RISKS AND LIMITATIONS OF THIS AUDIT

I did not run a single new backtest. Everything numeric here is derived
from artifacts the previous development cycle left behind — journals, CSV
trade logs, reports, tick and bar files — plus direct reading of the
source. New statistics were computed from those artifacts; no new runs were
generated. That is the largest limitation and it shapes the others.

**The real-tick sample is small.** 196 trades across five runs, t ≈ −1.80,
p ≈ 0.07. On its own this would not support a strong conclusion. Its role
in the argument is unanimity of direction, not magnitude.

**The "31 months of real ticks" claim is unverified, not disproven.** What
I established is that it cannot be reproduced on this terminal, because
only 15.2 months of tick data exist here. There are innocent explanations —
history downloaded and later purged, or a run performed on a different
machine. My inference that it was OHLC-modelled rests on the fact that
every reproducible characteristic of the project's trade data carries OHLC
fingerprints, which is strong circumstantial evidence and not proof. If
that dataset can be produced and re-run, it should be, because it is the
foundation of every calibration constant in the GOLD profile.

**The controlled A/B had unequal deposits** (10,000 vs 1,000), so cash
figures are not comparable and I compared only R and profit factor. The
coarser lot step at the smaller deposit adds up to about 8% sizing
quantisation to the real-tick side.

**Three of the eleven runs have incomplete metadata.** For runs 8, 9 and 10
I could not establish days traded or halt status from the journals. Their
headline metrics are recorded, but they contribute only their sign to the
argument.

**The reachability count is an upper bound.** The 81-of-209 figure comes
from include-graph traversal, so a class reached only through a branch that
never executes — or included but never instantiated — still counts as
reachable. The amount of genuinely live code is smaller than 81 files, not
larger. The traversal resolved every `#include` in the tree, so the
denominator is exact; it is the numerator that is generous.

**The random-walk barrier model in section 3.4 assumes zero drift and no
autocorrelation.** It is a benchmark for what a directionless strategy
would achieve at a given cost, not a prediction of what this strategy will
do. Its purpose is to show the size of the toll, and that part is robust.

**Statistical tests used normal approximations** via `math.erf` and
Monte Carlo with `numpy`; `scipy` could not be installed in this
environment. At these sample sizes the approximations are adequate, but
exact tests would be preferable and should be used when the samples get
larger.

**Whether this broker reports real volume for XAUUSD was not tested** — the
code path exists but is never selected, so the question is currently moot.
Commission on a live account is unknown and must be measured, not assumed.

### 10.1 What would change the verdict

A real-tick backtest, over the full 15.2 months, with the halt defect
fixed and pessimistic costs applied, producing positive expectancy on the
locked validation segment with a few hundred trades. That result does not
exist today. If it can be produced, the verdict moves from C to B.

Conversely, nothing in this audit shows that M1 or short-horizon gold
trading is impossible, and I want that stated plainly. What it shows is
that **this implementation, measured on this data, has no demonstrated
edge, and the development process that produced it was optimising against a
simulator artifact.** Those are different claims, and only the second one
is settled.

---

## 11. EXACT NEXT STEPS

In order. Each step produces an artifact that makes the next one
verifiable.

**1. Confirm the baseline is preserved.** `_baseline_original_20260903\`
holds 265 files. Nothing under `MQL5\` has been modified during this audit.
Create the versioned working copy for changes rather than editing in place,
and start `CHANGELOG.md` with this audit as entry zero.

**2. Fix the measurement harness, and nothing else.** Five changes, no
strategy logic: separate the daily stand-down flag from the drawdown latch
so a −2% day no longer ends the run; measure slippage on server-side stop
and target fills; add commission as a parameter with a non-zero default;
stamp tick model, cost assumptions and in-sample/out-of-sample status into
every report header; and make the derived-distance chain in section 5.5
reproducible — log the sampled spread and all twelve values derived from
it at initialisation, and allow them to be pinned to explicit inputs.
Each of these is independently verifiable and none of them changes a
trading decision.

That last one is a prerequisite for step 3 rather than an improvement to
it. While every stop, target and structure buffer descends from one
startup tick, two runs over the same period are not the same experiment,
and no baseline drawn from them is reproducible in the sense section 9
requires. Note that pinning the values is not the same as fixing the
underlying design flaw — a static geometry chosen once is still a static
geometry. Making it responsive to conditions is a strategy change and
belongs in step 6, not here.

**3. Establish the honest baseline.** Run the unmodified strategy on real
ticks over the full 15.2 months with the harness fixed, the distance chain
pinned and recorded, and pessimistic costs. Record every metric in
section 9.4. This number — not any existing backtest — becomes the
reference for all future comparison. My expectation is that it lands near
−0.13 R per trade; if it lands materially above zero, stop and re-read
section 10.1, because that would be the single most important finding
available and it would change the plan.

**4. Fix defect 2 and re-measure.** The `last_event_time` re-stamp is the
one bug with a plausible direct P&L cost, since it turns single events into
multiple correlated positions. Fix it in isolation, re-run step 3, and
record the delta. This is also the cleanest test of whether *any* code fix
can move this system, and its result should inform how much further repair
is worth attempting.

**5. Decide, on that evidence, between repair and redesign.** If steps 3
and 4 leave expectancy clearly negative — which is what I expect — proceed
to the layered architecture in section 8 as new code, keeping the old EA
intact and runnable for comparison. If they leave it near zero, a narrower
repair path becomes defensible and should be taken instead.

**6. Build the new system one layer at a time, in the order given in 8.2,
with a written hypothesis per layer.** Regime and liquidity filtering
first, because they are the layers the evidence most directly supports and
because they can be tested against the existing entry logic before any new
entry logic exists.

**7. Do not touch the validation segment** until a candidate is frozen.

**8. Reduce the codebase.** 128 headers unreachable from the production EA
actively obstruct understanding and were a contributing cause of the
failures in this audit — several of the dead classes are exactly the
safeguards one would assume were protecting the system. Start with the 90
that no `.mq5` reaches at all, since removing those cannot break a build.
Archive them out of the build tree rather than deleting them.

---

## 12. VERDICT

**C — the system should be fundamentally redesigned.**

Not because the code is badly written. Much of it is careful, and in
several places — the order-flow header's refusal to overclaim, the comment
explaining why an emergency stop must not clear itself, the note about
metals feeds reporting no real volume — the author was more honest with
himself than the results ended up being. The problem is upstream of the
code.

The reasoning, in order of weight:

**The only profitable results came from a simulator that cannot represent
the strategy.** With 209 byte-identical trading inputs over identical days,
1-minute OHLC generation gives profit factor 1.126 and real ticks give
0.853. The share of trades reaching target falls from 39.2% to 6.5%. OHLC
generation on this feed models the spread at 4.0–4.4 points where reality
is 9.5–33.5, fills every stop exactly at its price — 12,774 of 12,774
losers at precisely −1.000 R — and cannot produce any price movement
shorter than 20 seconds, for a strategy whose median hold is 22 seconds.

**Profitability across the project's entire history tracks modelled spread
and nothing else.** Eleven runs, perfect separation at the 4.4/9.5-point
boundary, p = 0.0022. Including one OHLC run that happened to be modelled
at a realistic spread, and lost.

**Every real-tick run lost.** Five runs, 196 trades, −0.128 R per trade.
Unanimous in direction, p ≈ 0.07 on its own — corroborative rather than
conclusive, and treated as such.

**The calibration constants rest on a dataset that cannot exist here.** The
GOLD profile and the accuracy filter are fitted to "31 months of real
ticks"; this terminal holds 15.2. And by the developer's own recorded
figures that dataset was itself losing 0.145 R per trade with t = −5.23.

**The trade geometry is not designed, it is inherited from one tick.** The
stop, the target, the break-even trigger and offset, the trailing distance
and step, the maximum spread gate, the slippage allowance and the
structure-break buffer are all arithmetic descendants of a single spread
measurement taken once at initialisation. Three of them appear in the EA's
own config dump exactly as that chain predicts. Nothing re-derives them
when conditions change, and the one value the design intended as a safety
floor is never transmitted to the engine at all — it survives only as a
multiplier for the others.

**No backtest in this project has ever survived a bad day.** A routine 2%
daily loss fires an emergency latch that cannot clear, so every run ended
at its first drawdown. The best-looking result in the entire history — the
1.548 profit factor — earned that number by stopping on 2026-06-16, just as
it started to break.

**And the arithmetic of the chosen horizon is hostile.** At a realistic 13
points of spread on a 200-point stop, the strategy must beat a coin flip by
2.6 percentage points before it earns anything; at the 33.5 points actually
observed, by 6.7. A 95-point stop at that spread — which this EA placed —
pays 35.3% of its risk budget to the broker on entry. There is no signal
quality that recovers that, and there is no evidence anywhere in this
project that the entry logic supplies even the smaller number.

What follows from all of that is not "the parameters need work." It is that
the development loop was closed around an instrument that lied, and the
strategy grew to fit the lie. Repairing all nineteen defects in section 5
would produce a correctly-implemented version of a strategy with no
demonstrated edge.

So the redesign starts with the measurement apparatus, not with the
strategy — and the first honest number this project produces will be a
negative one. That is the point. Until a backtest can be trusted to tell
you that you are losing, it cannot be trusted to tell you that you are
winning.

---

*Audit performed 2026-09-03 against `C:\scalp robot\MQL5` as of that date.
No file under `MQL5\` was modified. Baseline preserved at
`_baseline_original_20260903\`. Supporting evidence in
`outputs\evidence\`.*
