# Decision Engine — Phase 3

11 classes, 5,841 lines, four subsystems. **Compiles clean: 0 errors, 0 warnings.**

No dashboard. No optimization. No order placement — this layer decides; acting is the caller's job.

Location: `MQL5/Include/ScalpRobotPro/Decision/`

---

## Build verification

| Harness | Result |
|---|---|
| `P3SessionNewsCheck.mq5` — session + news | **0 errors, 0 warnings** |
| `P3StrategyCheck.mq5` — all 10 plugins | **0 errors, 0 warnings** |
| `Phase3CompileCheck.mq5` — full pipeline | **0 errors, 0 warnings** |
| `EngineCompileCheck.mq5` — Phase 1 | **0 errors, 0 warnings** |
| `IntelCompileCheck.mq5` — Phase 2 indicators | **0 errors, 0 warnings** |
| `SmcCompileCheck.mq5` — Phase 2 structure/SMC | **0 errors, 0 warnings** |
| `Phase2CompileCheck.mq5` — Phase 2 full | **0 errors, 0 warnings** |

Phases 1 and 2 still compile, confirming Phase 3 broke nothing. No completed code was rewritten.

Two pre-existing files continue to fail, unchanged from Phase 1 and not authored here:
`EngineCompileTest.mq5` (100 errors, targets the parallel `CTradeEngine` API) and
`ScalpRobotPro.mq5` (1 error, `CTradingEngine::Start` has no body by design).

---

## Pipeline

```
1  SESSION    may we trade at this moment at all?      ─┐ checked FIRST,
2  NEWS       is a high-impact release too close?      ─┘ before any indicator
3  SNAPSHOT   assemble the immutable SDecisionInput
4  POLL       collect an opinion from every enabled plugin
5  VOTE       collapse opinions into one direction
6  CONFIRM    score that direction against 13 checks
7  BLEND      strategy conviction x confirmation confidence
```

On a weekend or inside an FOMC blackout the whole pipeline costs two comparisons — no indicator is
read and no plugin polled.

---

## 1. Strategy Engine — 10 independent plugins

Every plugin returns exactly the required contract: **BUY / SELL / NO TRADE**, **confidence score**,
**trade reason**, **risk rating**.

| Plugin | Basis |
|---|---|
| `CEmaCrossStrategy` | fast/slow cross, ATR-scaled separation, trend filter |
| `CVwapPullbackStrategy` | return to session VWAP inside a trend |
| `CLiquiditySweepStrategy` | fades a confirmed stop run |
| `COrderBlockStrategy` | entry at a fresh order/breaker block |
| `CFairValueGapStrategy` | entry at an unfilled FVG |
| `CMomentumScalpPlugin` | RSI thrust + MACD agreement + volume |
| `COpeningRangeBreakout` | session opening range break |
| `CTrendContinuationStrategy` | pullback inside an established trend |
| `CMeanReversionPlugin` | band-extreme reversion with trend veto |
| `CBreakoutStrategyPlugin` | swing break with volume expansion |

`CStrategyPlugin` is a Template Method base: `Evaluate()` enforces the universal guards — enabled,
data valid, **session permitted, news permitted**, bar-close discipline, confidence floor — then
delegates to `OnEvaluate()`. A plugin author therefore *cannot* forget a guard or accidentally trade
through a news blackout.

`CStrategyContext` holds borrowed pointers to all 21 Phase 2 modules. Ten plugins each needing five
indicators would otherwise mean fifty constructor arguments and a signature change per new data
source. Every convenience reader is null-safe, so a plugin whose indicator was not wired abstains
cleanly instead of crashing.

**Confidence is blended from independent evidence in every plugin** — typically ATR-normalised
magnitude, structural agreement, volume and session liquidity — each normalised 0..1 before
averaging. That is what makes scores comparable *between* plugins and therefore votable.

Two decisions worth noting:

- **`CMomentumScalpPlugin` does not fade RSI extremes.** In a genuine momentum move RSI stays
  extended; fading it is how momentum systems bleed. It uses RSI as a directional bias check.
- **`CMeanReversionPlugin` vetoes on strong trend** rather than merely lowering confidence. Fading a
  strong trend produces mean-reversion's worst losses, so ADX and structure grade are hard vetoes.

Plugins that know their own invalidation point supply a `suggested_stop` hint — the broken level, the
sweep extreme, the far zone edge. Sizing and final stop placement still belong to the Phase 2 risk
engine.

---

## 2. Signal Confirmation — 13 checks

Trend · Volume · ATR · VWAP · ADX · RSI · MACD · Bollinger · Market Structure · SMC · News ·
Session · Spread

**Four-valued results, not boolean:** `PASS` / `FAIL` / `NEUTRAL` / `UNAVAILABLE`.

The last two are distinct on purpose. `NEUTRAL` means the indicator has an opinion and it is "no
strong view"; `UNAVAILABLE` means there is no data at all. Collapsing them into `false` would let a
missing indicator masquerade as active disagreement and quietly suppress every trade. **Unavailable
checks are excluded from the denominator** rather than scored zero, so wiring fewer indicators
lowers precision without biasing the score toward zero.

**Blocking vs advisory.** News, session and spread veto outright; the indicator checks move the
score. That mirrors reality — a wide spread makes a scalp unprofitable regardless of how good the
setup looks, whereas a flat RSI merely weakens it.

A minimum decisive-check count prevents a "confirmed" verdict resting on one available indicator.

Notable interpretations:

- **ADX below threshold is `NEUTRAL`, not `FAIL`** — plenty of valid setups occur in quiet
  conditions. ADX measures strength; the DI pair supplies direction. Reading ADX alone as
  directional is a common error.
- **Bollinger penalises entering at an extreme.** Buying at the upper band means chasing, and for a
  scalper the remaining room to target determines whether the trade can pay.
- **ATR is two-sided.** Too little volatility means the target cannot be reached before the spread
  eats the edge; too much means stops are random.

---

## 3. Session Manager

Tokyo · London · New York · Sydney · Kill Zones · Overlaps · Weekend · Holiday · Broker Offset · DST

Session windows are facts about **GMT**, but a broker's server clock is not GMT and usually shifts
twice a year. An EA hard-coding "London opens at 08:00 server time" is correct for one broker in one
half of the year. This class resolves the offset from the terminal, converts GMT windows into server
time on every pass, and handles windows that wrap midnight (Sydney, Asian kill zone) — which naive
comparisons get wrong.

**Kill zones are narrower than sessions.** A session says the market is open; a kill zone says
institutional flow is concentrated. For a scalper that distinction is the difference between an edge
and noise, so both are reported separately.

`liquidity_score` (0..1) quantifies session quality — London/NY overlap scores 1.0, off-hours 0.10 —
because downstream confirmations need a number to weight against rather than an implicit assumption.

Blocking checks run cheapest-first: weekend → holiday → year-end → Friday close → Monday open →
no session → session edge → kill zone. Session edges are skipped because the widest spreads of the
day sit there.

**On DST:** the terminal exposes no DST flag, so detection is a documented northern-hemisphere
approximation (late March to late October) reported as an informational flag. The broker offset
itself already shifts with DST on most servers, so it is not used as a correction factor. Stating
that plainly is better than implying precision that isn't there.

---

## 4. News Engine

NFP · CPI · FOMC · GDP · PMI · Interest Rate Decisions · Pause · Resume · Countdown

**Named event recognition is the core value.** The terminal calendar reports a generic importance
flag, but NFP, CPI and FOMC move gold and FX far more than that flag suggests. `ClassifyByTitle()`
matches on name (case-insensitive substring, because provider wording varies) and assigns its own
severity — so a "moderate"-tagged CPI print is still treated as critical.

Pause windows scale with severity: critical 60/60 minutes, high 30/30, medium 15/15.

**The fail-safe decision is explicit.** When the calendar is unavailable — always true in the
strategy tester — the engine must choose between trading blind and refusing to trade. That choice is
configuration (`SetFailSafeBlock`), stated plainly and logged. A news filter that silently degrades
to "allow everything" is worse than having none, because the user believes they are protected. A CSV
fallback exists so backtests can be honest about news rather than ignoring it.

Malformed CSV lines are counted and reported: a typo'd file that loads zero events otherwise looks
identical to a clear calendar.

Currencies are auto-resolved from the symbol, with USD always included — metals are priced in USD
and driven by US data even when the base currency is XAU.

---

## Voting

Five modes: `FIRST_MATCH` · `HIGHEST_CONFIDENCE` · `MAJORITY` · `WEIGHTED` (default) · `UNANIMOUS`.

Weighted multiplies confidence by plugin weight per side, because it respects both *how many*
plugins agree and *how strongly*. A **margin test** rejects near-even splits: genuine disagreement
between plugins is not a signal, and trading a coin flip while paying a spread is negative
expectancy.

**Final confidence multiplies rather than averages:**

```
final = signal_confidence x confirmation_confidence
```

Deliberate. A strong signal with weak confirmation should *not* score the same as a moderate signal
with strong confirmation — both factors must be present. The risk rating derives from the blended
figure, not the strategy's own optimism.

---

## Compatibility with Phases 1 and 2

No completed code was modified. Two collisions were resolved by renaming **Phase 3** symbols:

**1. `SRP_SESSION_*` collision.** Phase 1's `Core/Types/Enums.mqh` already defines `ENUM_SRP_SESSION`
with members `SRP_SESSION_SYDNEY`, `_TOKYO`, `_LONDON`, `_NEWYORK`. MQL5 places enum members in the
**global** namespace, so reusing those names is a redefinition error. Phase 3 uses the `SRP_TS_`
prefix instead.

**2. `input` is a reserved MQL5 keyword.** I initially used it as a parameter name across the
strategy files, which produced 101 errors. Renamed to `snapshot` with a case-sensitive
word-boundary replace so `SDecisionInput` was untouched. Worth flagging for anyone extending the
plugin contract.

---

## Orphaned file to resolve

`Decision/Types/DecisionTypes.mqh` (362 lines) exists but was not authored here. It declares
`SStrategySignal`, `SConfirmationReport`, `SSessionState`, `SNewsItem`, `SNewsState` and
`SDecisionInput` — **the same struct names as my `DecisionStructs.mqh`**. Its own enums are
`SRP_D_`-prefixed and do not collide, but the struct names would be a hard redefinition error if both
files were ever included in one translation unit.

Nothing references it, so the current build is unaffected. It was left in place rather than deleting
a file I did not create.

**Recommendation:** delete `DecisionTypes.mqh`, or if its design is preferred, delete
`DecisionStructs.mqh` and migrate `CDecisionEngine`, the plugins and the confirmation engine onto
its `SRP_D_`-prefixed vocabulary. The two cannot coexist.

This is the third such orphan (after `SRPVersion.mqh` in Phase 1's architecture and the parallel
`CTradeEngine` stack). A cleanup pass across all three would be worth doing before Phase 4.

---

## Not included, by design

No dashboard, no optimization, no order placement. The engine outputs one `STradeDecision` carrying
the verdict, blended confidence, risk rating, the winning signal, the full confirmation report, vote
accounting, and session/news context snapshots — everything a caller needs to act, or to explain why
it did not.
