# Market Intelligence Engine — Phase 2

17 classes, 7,695 lines, four subsystems. **Compiles clean: 0 errors, 0 warnings.**

No strategies. No trade entries. No dashboard. This layer measures and describes the market;
deciding what to do about it belongs to a later phase.

Location: `MQL5/Include/ScalpRobotPro/Intelligence/`

---

## Build verification

| Harness | Result |
|---|---|
| `IntelCompileCheck.mq5` — indicator engine | **0 errors, 0 warnings** |
| `SmcCompileCheck.mq5` — structure + SMC | **0 errors, 0 warnings** |
| `Phase2CompileCheck.mq5` — all four subsystems | **0 errors, 0 warnings** |
| `EngineCompileCheck.mq5` — Phase 1 engine | **0 errors, 0 warnings** |

Phase 1 still compiles, confirming Phase 2 broke nothing.

**The Phase 1 compile blocker is solved.** MetaEditor's CLI produced no output when invoked via
PowerShell `Start-Process`. Using `cmd /c` with a space-free build root captures it correctly, and
`/inc:` must point at the MQL5 root for `<ScalpRobotPro/...>` to resolve. The reusable script is
`_build/build.ps1`; run `-Target all` or a specific `.mq5`.

### Two pre-existing files still fail (not mine)

```
Experts/ScalpRobotPro/EngineCompileTest.mq5   100 errors
Experts/ScalpRobotPro/ScalpRobotPro.mq5         1 error
```

`EngineCompileTest.mq5` targets the parallel `CTradeEngine` API flagged in
`docs/TRADING_ENGINE.md` (`Build(magic)`, `OpenMarket`, `STradeGateResult`). `ScalpRobotPro.mq5`
fails on `CTradingEngine::Start` having no body — expected, since the Phase 1 architecture layer is
declaration-only by design. Both were left untouched.

---

## 1. Indicator Engine — 14 indicators

Every indicator supports the four required capabilities, implemented **once** in the base class:

| Capability | Mechanism |
|---|---|
| **Caching** | `CIndicatorBuffer` per output buffer, one `CopyBuffer` per bar |
| **Validation** | handle checks, `BarsCalculated` warm-up gate, `EMPTY_VALUE`/NaN rejection |
| **Error handling** | 5-state machine, failure counters, one automatic recreate attempt |
| **Reusable API** | uniform `Value`/`Series`/`Slope`/`Highest`/`Lowest`/`Average`/`Cross` |

```
CIntelIndicator (abstract)          subclasses implement ONE method: OnCreateHandle()
├── CEmaIndicator      CSmaIndicator     CAtrIntel       CRsiIntel
├── CAdxIntel          CMacdIntel        CBollingerIntel CCciIntel
└── CStochasticIntel   CIchimokuIntel    CObvIntel       CMfiIntel

CVwapIndicator    self-computed, session-anchored
CVolumeIndicator  self-computed, tick or real volume
```

**Why VWAP and Volume don't inherit the base.** Neither maps onto a terminal handle, so
`BarsCalculated` gating and handle lifecycle are meaningless for them. Forcing the inheritance would
mean overriding most of the base to do nothing — a Liskov violation. They present the same read API
by convention instead.

**Why caching isn't merely an optimisation.** Two consumers calling `CopyBuffer` at different
moments in one tick can observe different values, so filters and structure logic silently disagree.
One copy per bar makes every consumer see identical data.

**State machine:** `UNINITIALIZED → WARMING_UP → READY`, with `STALE` and `FAILED` branches.
Distinguishing *warming up* from *broken* matters — one resolves itself, the other needs attention.
Reads are refused unless `READY`, which is the single gate stopping warm-up zeros from entering a
calculation.

---

## 2. Market Structure Engine

```
CSwingDetector      confirmed swing highs/lows, HH/HL/LH/LL labelling
CMarketStructure    trend, strength, phase, BOS/CHoCH, dealing range
```

**Non-repainting by construction.** A swing requires N confirming bars on *both* sides. Detecting on
unconfirmed bars is why most structure indicators repaint: a swing appears, then vanishes as price
pushes higher. The cost is an N-bar detection lag — documented, not hidden.

**BOS vs CHoCH.** The same break means opposite things depending on trend context:

| Event | Meaning |
|---|---|
| **BOS** | break *with* the trend → continuation |
| **CHoCH** | break *against* the trend → first warning of reversal |

This is why `CMarketStructure` owns both the trend state and the event classification — they cannot
be separated.

**Trend strength** is a composite of four measurable properties (sequence consistency, leg
displacement, range-position agreement, structural clarity), each 0..1. Using several inputs means
one unavailable component degrades the score rather than invalidating it.

`EXHAUSTED` is deliberately distinct from `STRONG`: a long streak at a range extreme is powerful but
late, and consumers must be able to tell those apart.

**Direction requires both conditions to agree** (HH *and* HL for bullish). When they disagree the
answer is `RANGING` — which is honest far more often than most trend filters admit.

---

## 3. Smart Money Concepts

```
CZoneRegistry           zone storage + lifecycle state machine
CDisplacementDetector   impulsive-move detection (the keystone)
CBlockDetector          order / breaker / mitigation blocks + FVGs
CLiquidityDetector      sweeps, pools, equal highs/lows, inducement
```

All 15 requested concepts are covered: Order Blocks · Breaker Blocks · Mitigation Blocks · Fair Value
Gaps · Liquidity Sweeps · Liquidity Pools · BOS · CHoCH · Premium Zone · Discount Zone · Equal Highs
· Equal Lows · Displacement · Inducement · Market Structure.

**Displacement is the keystone.** Every zone concept depends on it. Three conditions, all required:

```
1  RANGE  bar range >= N x ATR        (materially larger than normal)
2  BODY   body / range >= threshold   (directional, not a wide indecision bar)
3  CLOSE  closes in the top/bottom fraction of its own range
```

Without a displacement test, "order block" degenerates into "any recent candle" — which is why so
many SMC implementations mark up dozens of meaningless boxes. ATR is read at the **same shift** as
the bar under test, so an old bar is judged against the volatility that prevailed then.

**Zone lifecycle:** `FRESH → TESTED → MITIGATED → INVALIDATED`, plus `EXPIRED`. Invalidation uses the
**close**, not the wick — a spike that immediately reverses is precisely the behaviour these zones
capture, so invalidating on it would be wrong. Capacity is bounded with weakest-then-oldest eviction,
giving a constant memory profile.

**Breaker blocks invert polarity.** A failed *bullish* order block becomes *bearish* resistance,
because trapped buyers become sellers on retest. That inversion is the defining property.

**A sweep requires close-back.** Price must penetrate the level *and close back inside*. Without that
test the move is a genuine breakout, and treating it as a sweep inverts the expected reaction
entirely. Most implementations omit this.

**Liquidity pools carry `NEUTRAL` bias** — a pool is a magnet, not a directional level. Marking it
bullish or bearish would misrepresent it.

Tolerances are expressed in **ATR fractions**, not fixed points, so settings behave consistently
across volatility regimes.

---

## 4. Risk Management

```
CPositionSizers     6 sizing models (Strategy pattern)
CRiskLimitGuard     daily/weekly/monthly loss, drawdown, exposure, emergency
CProtectionManager  stops, targets, break-even, trailing, profit lock
CRiskStateStore     atomic key/value persistence
CRiskEngine         facade + broker normalisation + risk re-verification
```

### Sizing models

| Model | Basis |
|---|---|
| Fixed Lot | constant volume |
| Risk % | % of balance / equity / free margin / high-water mark |
| Auto Lot | lot step per N currency of capital |
| Kelly | `f* = W − (1−W)/R` from realised edge |
| ATR | volatility-normalised, targets constant risk |
| Dynamic | performance-adaptive, anti-martingale |

**Kelly is fractionally scaled and capped.** Full Kelly maximises growth but assumes the measured
edge is the *true* edge — on a small sample it isn't, so full Kelly routinely over-bets. This
implementation enforces a minimum sample, applies a fraction (default 25%), hard-caps the resulting
risk, and returns 0 on a negative edge rather than betting against the strategy.

**Dynamic sizing is anti-martingale and will not be otherwise.** It shrinks after consecutive losses
and during drawdown. Increasing size after losses is the fastest known route to a blown account.

**Models requiring a stop return 0 without one** rather than falling back to a fixed lot. Silently
abandoning the user's stated risk contract is worse than refusing the trade.

### The order of operations

```
1  check limits          (no sizing at all if trading is barred)
2  resolve the stop      (size depends on it)
3  size the position     (needs the stop distance)
4  normalise volume      (step, bounds — always FLOORS)
5  RE-VERIFY actual risk ← the step almost everyone omits
```

Step 5 matters: flooring volume to a broker step changes the money at risk, and a stop widened to the
broker minimum changes it again. Without re-verification a position sized for 1% can quietly risk
materially more — defeating the entire purpose of the layer.

### Limits

Latching, persisted, and rearmed at the correct window boundary. **Floating P&L counts toward loss
limits** — an open loss is a real loss for a daily cap, and excluding it lets an account bleed past
its stated limit while technically complying.

Drawdown is measured from a **persisted all-time equity peak**. A session high would silently reset
on every restart, turning a "20% max drawdown" promise into fiction.

Emergency shutdown does not auto-rearm; `ClearEmergency()` requires a non-empty human
acknowledgement and no automation path calls it.

### Protection

Break-even · trailing (fixed or ATR) · profit lock · dynamic stops and targets.

**The one-way rule** is enforced centrally in `IsImprovement()`: every adjustment may only move a
stop in the profitable direction. A trailing stop that can retreat is not a trailing stop.

**Step threshold on trailing** prevents server spam — without it a busy M1 stream issues thousands of
modifications an hour, which brokers throttle.

**Profit lock measures against the peak**, not the current price. That is what distinguishes it from
a trailing stop: it protects the best profit the trade actually achieved.

---

## Why `CRiskStateStore` exists

Phase 1's `CJsonStateStore` is declaration-only, and modifying Phase 1 was out of scope. The latching
limits genuinely require working persistence, so this is a complete implementation of the same
`IStateStore` contract. Either can be injected — `CRiskLimitGuard` depends only on the interface.

It writes **atomically** (temp file, then replace) so a crash mid-save cannot corrupt state, and it
can be disabled entirely for the tester, where persisted state from pass N would bias pass N+1 and
invalidate the optimisation.

---

## Compatibility with Phase 1

One change was required, and it was additive:

`Intelligence/Types/IntelligenceStructs.mqh` includes `Core/Types/Structs.mqh` to reuse
`SValidationResult`, so validation reporting stays uniform across both phases rather than inventing a
parallel result type. No Phase 1 file was modified.

Naming collisions were avoided rather than resolved destructively: `CIntelIndicator`, `CAtrIntel`,
`CRsiIntel` and similar coexist with the Phase 1 declarations of similar names.

---

## Fixed during this phase

- **Missing include** — `SValidationResult` was referenced without including `Core/Types/Structs.mqh`.
  One root cause, 33 compile errors.
- **Implicit datetime narrowing** — `datetime` arithmetic promotes to `long`; two week-boundary
  calculations needed explicit casts to compile warning-free.

---

## Not included, by design

No strategies, no signal generation, no trade entries, no dashboard. This layer produces
measurements: `SStructureState`, `SPriceZone`, `SLiquiditySweep`, `SSizingResult`,
`SProtectionPlan`, `SRiskVerdict`. Acting on them is a later phase's responsibility.
