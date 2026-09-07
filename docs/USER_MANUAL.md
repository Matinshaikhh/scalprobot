# User Manual

Every setting Scalping Robot Pro exposes, what it does, and when to change it.

Inputs are grouped exactly as they appear in the terminal dialog. Defaults are tuned for
NASDAQ (US100/NAS100) scalping on M1–M5, but the engine is instrument-agnostic: every
distance is expressed in **points**, never pips or price, so switching instrument is a
preset change rather than a code change.

Inputs stop at the boundary. They are copied once into a sealed configuration object at
startup; nothing can change a setting mid-run.

---

## How a tick becomes a trade

Worth reading once, because most settings are a gate somewhere in this sequence.

```
OnTick
 ├─ 1 throttle              cheapest possible exit
 ├─ 2 refresh state         indicators, structure, account
 ├─ 3 manage open positions runs even while halted
 ├─ 4 risk gate             guards may forbid or demand flatten
 ├─ 5 decide                strategies → confirmation → session → news
 ├─ 6 size and protect      volume, stop, target
 ├─ 7 execute               the only OrderSend in the product
 └─ 8 render                dashboard and overlay, last
```

Management before entry is deliberate. An engine that hunts for a new signal before
trailing an open winner will, on a fast tick, add risk while existing risk sits
unprotected.

Any stage may abort, and when one does the reason is recorded and reported.

---

## General

| Input | Default | Notes |
|---|---|---|
| `InpMagicNumber` | 20260808 | Identifies this instance's positions. **Must be unique per instance.** |
| `InpOrderComment` | SRP | Appears in the order comment. |
| `InpDirectionMode` | Both | Both / buy only / sell only / disabled. |
| `InpTickThrottleMs` | 250 | Minimum real milliseconds between pipeline runs. 0 = every tick. |

`InpTickThrottleMs` is a CPU control for fast-ticking instruments. It measures real
elapsed time and is **automatically disabled in the Strategy Tester** — a backtest replays
a month in seconds, so a real-time gate there would discard nearly every simulated tick
and silently change what the strategy sees.

## Logging

| Input | Default |
|---|---|
| `InpLogLevel` | INFO |
| `InpLogToFile` / `InpLogToTerminal` | true / true |
| `InpLogToAlert` / `InpLogToPush` | false / false |
| `InpLogFolder` | ScalpRobotPro\Logs |
| `InpLogDailyRotation` | true |
| `InpLogFlushEvery` | 8 records |

Channels can be toggled independently: errors, trades, indicators, risk, performance,
execution time. `InpLogChannelIndicators` is **off** by default — it is the highest-volume
channel and a diagnostic tool, not a production need.

During an optimisation, logging is forced off regardless of these settings. Even `Print`
costs measurable time across thousands of passes.

## Risk

The most consequential group. Read it before changing anything.

| Input | Default | Notes |
|---|---|---|
| `InpSizingModel` | Risk percent | Fixed lot / risk percent / auto lot / Kelly / ATR / dynamic |
| `InpCapitalBase` | Equity | Balance / equity / free margin / high-water mark |
| `InpFixedLot` | 0.10 | Used by fixed-lot sizing only |
| `InpRiskPercent` | 0.5 | Percent of capital risked per trade |
| `InpMaxLot` | 5.00 | Hard ceiling on volume |
| `InpMaxPositions` | 2 | Concurrent positions |
| `InpKellyFraction` | 0.25 | Quarter-Kelly. Full Kelly over-bets on a small sample. |
| `InpKellyMinTrades` | 30 | Kelly refuses to size below this sample |
| `InpAtrRiskMultiple` | 1.5 | ATR sizing multiple |
| `InpMaxSpreadPoints` | 60 | Reject entries above this spread |
| `InpMaxSlippagePoints` | 30 | Maximum accepted deviation |
| `InpMinFreeMarginPercent` | 30 | Refuse entry below this free margin |

**Capital base.** Equity includes floating profit and loss, so size shrinks while the
account is under water rather than after the fact. High-water mark is the most
conservative: it sizes against peak equity, so a drawdown reduces size immediately.

**How risk is measured.** Volume comes from "money lost per lot if the stop is hit",
obtained from the terminal's own `OrderCalcProfit`. Deriving it from tick value is the
textbook approach and is wrong on some instruments — this broker reports gold with
`tick_size` 0.01 and `tick_value` 0.10 against a 100 oz contract, understating real loss
tenfold. A trade configured for 0.5% risk lost 5.01% before this was corrected.

Volume always rounds **down** to a legal step, and risk is re-verified *after* broker
stop-level clamping. That second check is the step most EAs omit, and the reason a
position sized for 1% can quietly risk more.

## Stop Loss / Take Profit

| Input | Default |
|---|---|
| `InpStopModel` | ATR multiple |
| `InpSlFixedPoints` | 250 |
| `InpSlAtrMultiplier` | 1.5 |
| `InpTargetModel` | Risk:reward |
| `InpTpFixedPoints` | 400 |
| `InpTpAtrMultiplier` | 2.5 |
| `InpTpRiskReward` | 1.6 |

Stop models: none, fixed points, ATR multiple, market structure, dynamic.
Target models: none, fixed points, ATR multiple, risk:reward, structure, dynamic.

ATR-based is the default because a fixed stop that suits a quiet afternoon is
noise-tight at the cash open.

A target inside the spread is unreachable; the validator rejects that combination rather
than letting it fail silently at `OrderSend`.

## Trade Management

| Input | Default | Notes |
|---|---|---|
| `InpTrailMode` | Fixed step | Disabled / fixed / ATR / profit percent |
| `InpTrailStartPoints` | 200 | Profit before trailing begins |
| `InpTrailDistancePoints` | 150 | Distance maintained |
| `InpTrailStepPoints` | 20 | Minimum move per adjustment |
| `InpBreakEvenEnabled` | true | |
| `InpBreakEvenTriggerPoints` | 150 | |
| `InpBreakEvenOffsetPoints` | 20 | Locks a small profit, not exactly break-even |
| `InpAtrTrailEnabled` | false | ATR-scaled trailing |
| `InpAtrExitEnabled` | true | Exit on adverse ATR excursion |
| `InpScaleOutEnabled` | true | Partial close at a profit trigger |
| `InpScaleOutFraction` | 0.5 | Fraction closed |
| `InpScaleInEnabled` | false | Add to a winner |
| `InpReverseEnabled` | false | Close and reverse on an opposing signal |
| `InpTimeStopEnabled` | true | |
| `InpTimeStopMinutes` | 45 | A scalp that has not worked in 45 minutes is not working |
| `InpMaxHoldEnabled` | true | |
| `InpMaxHoldMinutes` | 120 | Absolute ceiling |
| `InpProfitLockEnabled` | true | Lock a share of open profit |

`InpTrailStepPoints` exists to avoid modifying the stop on every tick, which some brokers
throttle or reject.

## Account Protection

Latched guards. Once tripped they stay tripped, and they survive a terminal restart —
otherwise restarting would hand the robot a fresh budget to lose.

| Input | Default |
|---|---|
| `InpDailyProfitEnabled` / `Percent` | true / 3.0 |
| `InpDailyLossEnabled` / `Percent` | true / 3.0 |
| `InpWeeklyLossPercent` | 6.0 |
| `InpMonthlyLossPercent` | 12.0 |
| `InpMaxDrawdownEnabled` / `Percent` | true / 10.0 |
| `InpMaxExposurePercent` | 5.0 |
| `InpConsecutiveLossLimit` | 4 (0 = off) |
| `InpFlattenOnTrip` | true |
| `InpKillSwitchEnabled` | true |

Drawdown is measured from a **persisted all-time equity peak**, not from the session start.

`InpFlattenOnTrip` decides whether a tripped guard closes open positions or leaves them to
their stops. Flatten when unsupervised; leave when watching. Neither is universally right.

The kill switch clears only by human action.

`InpRiskPercent` must be below `InpDailyLossPercent`, or one loss ends every day. The
validator enforces this.

## Sessions & Schedule

| Input | Default |
|---|---|
| `InpSessionFilterEnabled` | true |
| `InpAllowSydney` / `Tokyo` | false / false |
| `InpAllowLondon` / `NewYork` | true / true |
| `InpKillZonesOnly` | false |
| `InpRequireOverlap` | false |
| `InpScheduleEnabled` | true |
| `InpWeekendFilter` | true |
| `InpFridayCloseMinutes` | 60 |
| `InpHolidayFilterEnabled` | true |
| `InpHolidayList` | (empty) `YYYY.MM.DD;...` |
| `InpBrokerGmtOffset` | 0 |
| `InpDstAdjust` | true |

Asia is disabled by default because NASDAQ is a US instrument: the London/NY overlap and
the cash open carry the volume, while Asian hours are thin and mean-reverting.

**`InpBrokerGmtOffset` matters more than it looks.** Session windows are computed in GMT
and converted to server time. If your broker's server time is not GMT and this is wrong,
every session boundary shifts and the robot trades the wrong hours. A dominant
`SESSION_BLOCKED` decline tally with sessions apparently enabled points here first.

`InpFridayCloseMinutes` flattens before the weekend gap.

## News Filter

| Input | Default |
|---|---|
| `InpNewsFilterEnabled` | true |
| `InpNewsSource` | Terminal calendar |
| `InpNewsMinImpact` | High |
| `InpNewsMinutesBefore` / `After` | 15 / 15 |
| `InpNewsClosePositions` | false |
| `InpNewsCsvFile` | (empty) |
| `InpNewsCurrencyFilter` | USD |
| `InpNewsFailSafeBlock` | true |

`InpNewsFailSafeBlock` is the important one. When the news source cannot be read, this
decides whether to block trading or proceed. A news filter that silently degrades to
"allow everything" is worse than having none, because you believe you are protected.

Behaviour depends on environment, deliberately:

- **Live** — fail closed. Trading blind into an unknown release risks real capital.
- **Tester** — the calendar is unavailable by design (it returns *today's* events
  regardless of the simulated bar, which would be look-ahead bias). If no CSV was
  supplied the source can never become available, so failing closed would block 100% of
  entries and produce a clean-looking backtest with zero trades. Instead the run proceeds
  without news filtering and says so plainly. Supply `InpNewsCsvFile` to model news in a
  backtest; then a load failure does fail closed, because at that point it is real.

## Market Filters

| Input | Default |
|---|---|
| `InpSpreadFilterEnabled` | true |
| `InpVolatilityFilterEnabled` | true |
| `InpVolatilityMinAtr` / `MaxAtr` | 0 / 0 (0 = off) |
| `InpTrendFilterEnabled` | true |
| `InpTrendTimeframe` | M15 |
| `InpFrequencyFilterEnabled` | true |
| `InpMinSecondsBetweenTrades` | 60 |
| `InpMaxTradesPerDay` | 20 |
| `InpMaxTradesPerHour` | 6 |

Frequency limits exist to stop a malfunctioning signal from over-trading an account.

## Strategies

Ten independent plugins. Only enabled ones are constructed, so a disabled strategy costs
nothing at runtime.

| Input | Default |
|---|---|
| `InpAggregationMode` | Weighted score |
| `InpVoteMode` | 0 |
| `InpMinConfirmations` | 3 |
| `InpMinConfidence` | 0.55 |
| `InpMaxRiskRating` | 3 |
| `InpRequireConfirmation` | true |
| `InpEmaCrossEnabled` | true |
| `InpVwapPullbackEnabled` | true |
| `InpLiquiditySweepEnabled` | true |
| `InpOrderBlockEnabled` | true |
| `InpFvgEnabled` | true |
| `InpOpeningRangeEnabled` | true |
| `InpTrendContinuationEnabled` | true |
| `InpMomentumEnabled` | true |
| `InpMeanReversionEnabled` | false |
| `InpBreakoutEnabled` | true |

Every strategy reports a direction, a confidence from 0 to 1, a human-readable reason, and
a risk rating. Because confidence is normalised, weighted voting across strategies is
meaningful.

Mean reversion is off by default: it fights an index that trends hard intraday.

If at least one strategy must be enabled — the engine refuses to start with zero plugins
rather than running a robot that silently never trades.

## Indicators

| Input | Default |
|---|---|
| `InpFastMaPeriod` | 9 |
| `InpSlowMaPeriod` | 21 |
| `InpTrendMaPeriod` | 100 |
| `InpRsiPeriod` | 14 |
| `InpAtrPeriod` | 14 |
| `InpAdxPeriod` | 14 |
| `InpBollingerPeriod` | 20 |
| `InpBollingerDeviation` | 2.0 |

Fast must be below slow. The optimisation screen rejects inverted pairs outright.

## Smart Money Concepts

| Input | Default |
|---|---|
| `InpSmcEnabled` | true |
| `InpSmcSwingStrength` | 3 bars |
| `InpSmcSwingLookback` | 300 bars |
| `InpSmcZoneCapacity` | 64 |
| `InpSmcZoneMaxAgeBars` | 500 |
| `InpSmcDisplacementAtr` | 1.5 |
| `InpSmcMinGapPoints` | 50 |
| `InpSmcRequireDisplacement` | true |
| `InpSmcEqualToleranceAtr` | 0.15 |
| `InpSmcSweepLookbackBars` | 10 |
| `InpSmcStructureBreakBuffer` | 10 |

Zone detection runs on **new bars only**, not per tick. Order blocks and fair value gaps
do not form intrabar, and scanning every tick would be the single most expensive thing the
engine could do.

`InpSmcMinGapPoints` is instrument-scale sensitive: index gaps are large in absolute
points, so a forex-scale threshold would classify ordinary noise as a fair value gap.

## Dashboard

| Input | Default |
|---|---|
| `InpDashboardEnabled` | true |
| `InpDashboardTheme` | Dark |
| `InpDashboardCorner` | 0 |
| `InpDashboardXOffset` / `YOffset` | 12 / 22 |
| `InpDashboardRefreshMs` | 500 |
| `InpDashboardShowInTester` | false |
| `InpDrawOverlayEnabled` | true |
| `InpDrawEntries` … `InpDrawStatistics` | true |
| `InpDrawMaxZones` | 12 |
| `InpDrawZoneExtendBars` | 20 |

The dashboard reads a **copy** of engine state and cannot affect trading. A UI bug can
garble a label; it can never move a stop loss.

Drawing is suppressed automatically during optimisation regardless of these settings.

### Keyboard shortcuts

- **D** — collapse or expand the dashboard
- **H** — halt or resume new entries. Open positions stay managed.

## Statistics

| Input | Default |
|---|---|
| `InpJournalEnabled` | true |
| `InpPersistState` | true |
| `InpStateFolder` | ScalpRobotPro\State |
| `InpAnalyticsMinSample` | 10 |
| `InpAnalyticsUseRMultiples` | false |
| `InpAnalyticsInitialBalance` | 0 (0 = read from account) |

State files are namespaced per symbol and magic, so two instances never overwrite each
other's latched guards. Persistence is suppressed in the tester so state from one pass
cannot bias the next.

## Optimisation

See `OPTIMIZATION.md`. Summary:

| Input | Default |
|---|---|
| `InpOptCriterion` | Custom composite |
| `InpOptMinTrades` | 30 |
| `InpOptDrawdownPenalty` | 1.0 |
| `InpOptConcentrationPenalty` | 1.0 |
| `InpOptStreakPenalty` | 1.0 |
| `InpOptWalkForwardEnabled` | false |
| `InpOptWfIsDays` / `OosDays` | 90 / 30 |
| `InpOptWfMinEfficiency` | 0.5 |
| `InpOptMonteCarloEnabled` | false |
| `InpOptMonteCarloRuns` | 1000 |
| `InpOptMonteCarloSeed` | 0 |
| `InpOptMonteCarloRuinPercent` | 30 |
| `InpOptExportCsv` | true |
| `InpOptExportFolder` | ScalpRobotPro\Optimization |
| `InpOptRejectIncoherent` | true |

---

## When it does not trade

This is always explained. On shutdown, or after any run with no entries, the engine
prints a tally:

```
declines by reason: NO_SIGNAL=98259 SESSION_BLOCKED=6424
                    CONFIRMATION_FAILED=5579 LOW_CONFIDENCE=3948
```

| Reason | Meaning | First thing to check |
|---|---|---|
| `NO_SIGNAL` | No setup found. Normal as the bulk. | Enable more strategies, or loosen thresholds. |
| `SESSION_BLOCKED` | Outside permitted hours. | Session toggles, then `InpBrokerGmtOffset`. |
| `NEWS_BLOCKED` | Blackout, or fail-safe with no source. | See the News section. |
| `LOW_CONFIDENCE` | Below `InpMinConfidence`. | Lower it, or reduce `InpMinConfirmations`. |
| `CONFIRMATION_FAILED` | Signal found, confirmation refused. | Confirmation settings. |
| `CONFLICTING_SIGNALS` | Strategies disagreed. | Aggregation mode. |
| `DATA_UNAVAILABLE` | Indicators not ready. | Insufficient history — usually resolves. |

If the decision engine reports `actionable` above zero but the risk engine shows
`approvals=0`, the decision layer agreed and the **risk** layer refused. Check its
rejection count: usually no legal volume could be produced, or a guard is latched.

## Safety properties

Built in, not configurable:

- Only one class sends orders. Substituting a simulating executor runs the whole pipeline
  offline with zero broker contact.
- Foreign positions are never touched — magic **and** symbol are both filtered.
- Volume always rounds down.
- Risk is re-verified after broker stop-level clamping.
- One market snapshot per pass, so every filter and strategy evaluates identical prices.
- Deal tickets are deduplicated.
- Broker filling mode is resolved, not assumed.
- All price arithmetic is tick-size aware.
- Configuration contradictions abort `OnInit` rather than surfacing on tick 10,000.
- Wiring is verified at startup.

---

Trading involves substantial risk of loss. Validate any configuration on a demo account
before committing real capital.
