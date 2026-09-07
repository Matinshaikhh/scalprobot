//+------------------------------------------------------------------+
//|                                             ScalpRobotPro.mq5 |
//|                                            Copyright 2026 |
//|                          Scalping Robot Pro - Expert Advisor entry |
//+------------------------------------------------------------------+
//|                                                                  |
//|   THIS FILE IS A THIN ADAPTER. NOTHING ELSE.                      |
//|                                                                  |
//|   It has exactly four jobs:                                       |
//|     1. declare the `input` block (the only place inputs may live); |
//|     2. copy those inputs into an SInputSnapshot;                   |
//|     3. build and seal the configuration provider;                  |
//|     4. forward every terminal callback to CProductionEngine.       |
//|                                                                  |
//|   It contains NO trading logic, NO calculations, NO OrderSend, NO   |
//|   chart drawing and NO state beyond two pointers. Every terminal    |
//|   event handler below is a single delegation.                      |
//|                                                                  |
//|   WHY THE FILE IS DELIBERATELY BORING                              |
//|   MQL5 `input` variables are file-scoped globals, and an .mq5 file  |
//|   cannot be unit-tested or reused. Any logic placed here is         |
//|   permanently untestable and permanently coupled to the terminal.   |
//|   By confining this file to adaptation, 100% of the product's       |
//|   behaviour lives in classes that can be instantiated, injected     |
//|   with fakes and verified in isolation.                            |
//|                                                                  |
//|   WHICH ENGINE THIS DRIVES                                         |
//|   CProductionEngine (Runtime\), which is the composition root over  |
//|   the fully implemented stack: CRiskEngine, CDecisionEngine,        |
//|   CTradeEngine and CTraderInterface. The Phase 1 CTradingEngine     |
//|   scaffold under Core\ is the architectural reference it grew from  |
//|   and is deliberately not on the executable path.                  |
//|                                                                  |
//|   Read CProductionEngine::Build to see what the product is made of, |
//|   and CProductionEngine::OnTickEvent to see how a tick becomes a    |
//|   trade.                                                           |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026"
#property link        ""
//--- Kept in step with SRP_PRODUCT_VERSION by hand: MQL5 will not accept a
//--- macro here, and a terminal showing 1.10 beside a report header saying
//--- 1.11 is worse than either number alone.
#property version     "1.11"
#property description "Scalping Robot Pro - modular, SOLID MQL5 scalping robot"
#property description "NASDAQ-tuned defaults, instrument-agnostic engine"
#property strict

#include <ScalpRobotPro/Configuration/CConfigurationBuilder.mqh>
#include <ScalpRobotPro/Configuration/CConfigValidator.mqh>
#include <ScalpRobotPro/Optimization/CParameterSetValidator.mqh>
#include <ScalpRobotPro/Profiles/CProfileApplier.mqh>
#include <ScalpRobotPro/Runtime/CProductionEngine.mqh>

//+------------------------------------------------------------------+
//| INPUT BLOCK                                                       |
//| The single permitted location for `input` declarations in the       |
//| entire product. Everything downstream reads IConfigProvider.        |
//|                                                                  |
//| Defaults mirror CConfigurationBuilder::ApplyNasdaqDefaults so the   |
//| shipped preset and the code cannot drift apart.                     |
//+------------------------------------------------------------------+

//--- Market profile ------------------------------------------------
input group                     "=== Market Profile ==="
//--- AUTO detects the asset class from the broker symbol and loads the
//--- matching preset. The named modes force a preset regardless of the
//--- symbol, which is what you want when a broker uses an unusual name
//--- the classifier does not recognise.
input ENUM_SRP_PROFILE_MODE InpProfileMode = SRP_PROFILE_AUTO; // Profile selection
//--- When true, the profile supplies every parameter below and the
//--- inputs are ignored except where a profile leaves a field at zero.
//--- When false, the inputs win and the profile is advisory only.
input bool     InpProfileOverridesInputs   = true;       // Profile wins over inputs

//--- General -------------------------------------------------------
input group                     "=== General ==="
input long     InpMagicNumber              = 20260808;   // Magic number
input string   InpOrderComment             = "SRP";      // Order comment
input ENUM_SRP_DIRECTION_MODE InpDirectionMode = SRP_DIRECTION_BOTH; // Trade direction
input int      InpTickThrottleMs           = 250;        // Tick throttle (ms, 0=every tick)
//--- MULTI-TIMEFRAME. Context drives regime classification, setup drives
//--- structure; execution is always the chart timeframe.
//---
//--- These EXIST AS INPUTS because the snapshot has no other source for
//--- them. They were previously supplied only by the market profile, so
//--- running with InpProfileOverridesInputs=false left both at zero, an
//--- invalid timeframe reached iADX, the handle was refused with error
//--- 4805 and the EA declined to start. The tester reported that only as
//--- an aborted pass, which is indistinguishable from a run that took no
//--- trades.
input ENUM_TIMEFRAMES InpContextTimeframe  = PERIOD_M15;  // Context timeframe (regime)
input ENUM_TIMEFRAMES InpSetupTimeframe    = PERIOD_M5;   // Setup timeframe (structure)

//--- Logging -------------------------------------------------------
input group                     "=== Logging ==="
input ENUM_SRP_LOG_LEVEL InpLogLevel       = SRP_LOG_INFO; // Log level
input bool     InpLogToFile                = true;       // Log to file
input bool     InpLogToTerminal            = true;       // Log to Experts tab
input bool     InpLogToAlert               = false;      // Alert on errors
input bool     InpLogToPush                = false;      // Push on errors
input string   InpLogFolder                = "ScalpRobotPro\\Logs"; // Log folder
input bool     InpLogDailyRotation         = true;       // Rotate log daily
input bool     InpLogChannelErrors         = true;       // Channel: errors
input bool     InpLogChannelTrades         = true;       // Channel: trades
input bool     InpLogChannelIndicators     = false;      // Channel: indicators (noisy)
input bool     InpLogChannelRisk           = true;       // Channel: risk events
input bool     InpLogChannelPerformance    = true;       // Channel: performance
input bool     InpLogChannelExecution      = true;       // Channel: execution time
input bool     InpLogMirrorErrors          = true;       // Mirror errors to journal
input int      InpLogFlushEvery            = 8;          // Flush every N records

//--- Risk ----------------------------------------------------------
input group                     "=== Risk ==="
input ENUM_SRP_SIZING_MODEL InpSizingModel = SRP_SIZING_RISK_PERCENT; // Sizing model
input ENUM_SRP_CAPITAL_BASE InpCapitalBase = SRP_CAPITAL_EQUITY; // Capital reference
input double   InpFixedLot                 = 0.10;       // Fixed lot
input double   InpRiskPercent              = 0.5;        // Risk per trade (%)
input double   InpMaxLot                   = 5.00;       // Maximum lot
input double   InpMinLot                   = 0.0;        // Minimum lot (0=broker min)
input int      InpMaxPositions             = 2;          // Max concurrent positions
input double   InpKellyFraction            = 0.25;       // Kelly fraction
input int      InpKellyMinTrades           = 30;         // Kelly minimum sample
input double   InpAutoLotCapitalPerStep    = 1000.0;     // Auto lot: capital per step
input double   InpAutoLotPerStep           = 0.10;       // Auto lot: lot per step
input double   InpAtrRiskMultiple          = 1.5;        // ATR sizing multiple
input double   InpMaxSpreadPoints          = 60.0;       // Max spread (points)
input int      InpMaxSlippagePoints        = 30;         // Max deviation (points)
input double   InpMinFreeMarginPercent     = 30.0;       // Min free margin (%)

//--- Stop loss / take profit ---------------------------------------
input group                     "=== Stop Loss / Take Profit ==="
input ENUM_SRP_STOP_MODEL InpStopModel     = SRP_STOP_ATR_MULTIPLE; // Stop loss model
input double   InpSlFixedPoints            = 250.0;      // Stop loss (points)
input double   InpSlAtrMultiplier          = 1.5;        // Stop loss (ATR multiple)
input ENUM_SRP_TARGET_MODEL InpTargetModel = SRP_TARGET_RISK_REWARD; // Take profit model
input double   InpTpFixedPoints            = 400.0;      // Take profit (points)
input double   InpTpAtrMultiplier          = 2.5;        // Take profit (ATR multiple)
input double   InpTpRiskReward             = 1.6;        // Take profit (risk:reward)

//--- Trade management ----------------------------------------------
input group                     "=== Trade Management ==="
input ENUM_SRP_TRAIL_MODE InpTrailMode     = SRP_TRAIL_FIXED_STEP; // Trailing model
input double   InpTrailStartPoints         = 200.0;      // Trailing start (points)
input double   InpTrailDistancePoints      = 150.0;      // Trailing distance (points)
input double   InpTrailStepPoints          = 20.0;       // Trailing step (points)
input bool     InpBreakEvenEnabled         = true;       // Enable break-even
input double   InpBreakEvenTriggerPoints   = 150.0;      // Break-even trigger (points)
input double   InpBreakEvenOffsetPoints    = 20.0;       // Break-even offset (points)
input bool     InpAtrTrailEnabled          = false;      // Enable ATR trailing
input double   InpAtrTrailMultiple         = 2.0;        // ATR trailing multiple
input bool     InpAtrExitEnabled           = true;       // Enable ATR exit
input double   InpAtrExitMultiple          = 3.0;        // ATR exit multiple
input bool     InpScaleOutEnabled          = true;       // Enable scale out
input double   InpScaleOutTriggerPoints    = 180.0;      // Scale out trigger (points)
input double   InpScaleOutFraction         = 0.5;        // Scale out fraction
input int      InpScaleOutMax              = 1;          // Scale out max times
input bool     InpScaleInEnabled           = false;      // Enable scale in
input double   InpScaleInTriggerPoints     = 250.0;      // Scale in trigger (points)
input double   InpScaleInFraction          = 0.5;        // Scale in fraction
input int      InpScaleInMax               = 1;          // Scale in max times
input bool     InpReverseEnabled           = false;      // Enable reversal
input bool     InpTimeStopEnabled          = true;       // Enable time stop
input int      InpTimeStopMinutes          = 45;         // Max position age (minutes)
input bool     InpMaxHoldEnabled           = true;       // Enable max hold
input int      InpMaxHoldMinutes           = 120;        // Max hold (minutes)
input bool     InpProfitLockEnabled        = true;       // Enable profit lock
input double   InpProfitLockTriggerPercent = 2.0;        // Profit lock trigger (%)
input double   InpProfitLockKeepPercent    = 50.0;       // Profit lock keep (%)

//--- Account protection --------------------------------------------
input group                     "=== Account Protection ==="
input bool     InpDailyProfitEnabled       = true;       // Enable daily profit target
input double   InpDailyProfitPercent       = 3.0;        // Daily profit target (%)
input bool     InpDailyLossEnabled         = true;       // Enable daily loss limit
input double   InpDailyLossPercent         = 3.0;        // Daily loss limit (%)
input double   InpWeeklyLossPercent        = 6.0;        // Weekly loss limit (%)
input double   InpMonthlyLossPercent       = 12.0;       // Monthly loss limit (%)
input bool     InpMaxDrawdownEnabled       = true;       // Enable max drawdown limit
input double   InpMaxDrawdownPercent       = 10.0;       // Max drawdown (%)
input double   InpMaxExposurePercent       = 5.0;        // Max total exposure (%)
input int      InpConsecutiveLossLimit     = 4;          // Consecutive loss limit (0=off)
input bool     InpFlattenOnTrip            = true;       // Close positions when tripped
input bool     InpDailyLimitTerminal       = false;      // Daily loss limit ends the run (false=stand down, rearm next session)
input bool     InpKillSwitchEnabled        = true;       // Enable kill switch

//--- Sessions and schedule -----------------------------------------
input group                     "=== Sessions & Schedule ==="
input bool     InpSessionFilterEnabled     = true;       // Enable session filter
input bool     InpAllowSydney              = false;      // Allow Sydney session
input bool     InpAllowTokyo               = false;      // Allow Tokyo session
input bool     InpAllowLondon              = true;       // Allow London session
input bool     InpAllowNewYork             = true;       // Allow New York session
input bool     InpKillZonesOnly            = false;      // Trade kill zones only
input bool     InpRequireOverlap           = false;      // Require session overlap
input bool     InpScheduleEnabled          = true;       // Enable weekday schedule
input bool     InpWeekendFilter            = true;       // Block the weekend
input int      InpFridayCloseMinutes       = 60;         // Flatten before Friday close (min)
input bool     InpHolidayFilterEnabled     = true;       // Enable holiday filter
input string   InpHolidayList              = "";         // Holidays (YYYY.MM.DD;...)
input int      InpBrokerGmtOffset          = 0;          // Broker GMT offset (hours)
input bool     InpDstAdjust                = true;       // Adjust for DST
//--- SESSION WINDOWS, in minutes past midnight GMT.
//---
//--- Same reason as the timeframes above: the snapshot had no source for
//--- these other than the market profile, so running with
//--- InpProfileOverridesInputs=false left every window at 00:00-00:00 and
//--- the session filter blocked 100% of ticks. The run completed and
//--- reported zero trades, which looks exactly like a strategy that found
//--- no setups.
input int      InpLondonOpenGmt            = 8*60;       // London open (min past GMT midnight)
input int      InpLondonCloseGmt           = 16*60+30;   // London close
input int      InpNewYorkOpenGmt           = 13*60;      // New York open
input int      InpNewYorkCloseGmt          = 21*60;      // New York close
input int      InpPrimaryKzOpenGmt         = 13*60+30;   // Primary kill zone open
input int      InpPrimaryKzCloseGmt        = 16*60;      // Primary kill zone close
input int      InpSkipAfterOpenMinutes     = 2;          // Skip after session open (min)
input int      InpSkipBeforeCloseMinutes   = 10;         // Skip before session close (min)

//--- News ----------------------------------------------------------
input group                     "=== News Filter ==="
input bool     InpNewsFilterEnabled        = true;       // Enable news filter
input ENUM_SRP_NEWS_SOURCE InpNewsSource   = SRP_NEWS_SOURCE_TERMINAL_CALENDAR; // News source
input ENUM_SRP_NEWS_IMPACT InpNewsMinImpact= SRP_NEWS_IMPACT_HIGH; // Minimum impact
input int      InpNewsMinutesBefore        = 15;         // Blackout before (minutes)
input int      InpNewsMinutesAfter         = 15;         // Blackout after (minutes)
input bool     InpNewsClosePositions       = false;      // Close positions on blackout
input string   InpNewsCsvFile              = "";         // CSV file (tester)
input string   InpNewsCurrencyFilter       = "USD";      // Currencies (blank=all)
input bool     InpNewsFailSafeBlock        = true;       // Block when source unavailable

//--- Market filters ------------------------------------------------
input group                     "=== Market Filters ==="
input bool     InpSpreadFilterEnabled      = true;       // Enable spread filter
input bool     InpVolatilityFilterEnabled  = true;       // Enable volatility filter
input double   InpVolatilityMinAtr         = 0.0;        // Min ATR (points, 0=off)
input double   InpVolatilityMaxAtr         = 0.0;        // Max ATR (points, 0=off)
input bool     InpTrendFilterEnabled       = true;       // Enable trend filter
input ENUM_TIMEFRAMES InpTrendTimeframe    = PERIOD_M15; // Trend timeframe
input bool     InpFrequencyFilterEnabled   = true;       // Enable frequency filter
input int      InpMinSecondsBetweenTrades  = 60;         // Min seconds between trades
input int      InpMaxTradesPerDay          = 20;         // Max trades per day
input int      InpMaxTradesPerHour         = 6;          // Max trades per hour

//--- Strategies ----------------------------------------------------
input group                     "=== Strategies ==="
input ENUM_SRP_AGGREGATION_MODE InpAggregationMode = SRP_AGGREGATION_WEIGHTED_SCORE; // Aggregation
input int      InpVoteMode                 = 0;          // Vote mode
input int      InpMinConfirmations         = 3;          // Minimum confirmations
input double   InpMinConfidence            = 0.55;       // Minimum confidence (0-1)
input int      InpMaxRiskRating            = 3;          // Max accepted risk rating
input bool     InpRequireConfirmation      = true;       // Require confirmation
input bool     InpEmaCrossEnabled          = true;       // Strategy: EMA cross
input bool     InpVwapPullbackEnabled      = true;       // Strategy: VWAP pullback
input bool     InpLiquiditySweepEnabled    = true;       // Strategy: liquidity sweep
input bool     InpOrderBlockEnabled        = true;       // Strategy: order block
input bool     InpFvgEnabled               = true;       // Strategy: fair value gap
input bool     InpOpeningRangeEnabled      = true;       // Strategy: opening range
input bool     InpTrendContinuationEnabled = true;       // Strategy: trend continuation
input bool     InpMomentumEnabled          = true;       // Strategy: momentum scalp
input double   InpMomentumWeight           = 1.0;        // Momentum weight
input bool     InpMeanReversionEnabled     = false;      // Strategy: mean reversion
input double   InpMeanReversionWeight      = 0.5;        // Mean reversion weight
input bool     InpBreakoutEnabled          = true;       // Strategy: breakout
input double   InpBreakoutWeight           = 1.0;        // Breakout weight
// Break of structure is DISABLED as an entry source. July 2026 evidence: 135 of 144
// entries were BoS, and they resolved their own barriers 35.4% of the time where a
// driftless walk on the same barriers predicts 44.8% (SE 4.1pp, ~2.3 sigma worse).
// CMarketStructure still supplies structure context to the other plugins.
input bool     InpBosEnabled               = false;      // Strategy: break of structure
input double   InpBosWeight                = 1.0;        // Break of structure weight
input bool     InpVolBreakoutEnabled       = true;       // Strategy: volatility breakout
input double   InpVolBreakoutWeight        = 1.0;        // Volatility breakout weight
input bool     InpOrderFlowEnabled         = true;       // Strategy: order flow (OBV+MFI)
input double   InpOrderFlowWeight          = 1.0;        // Order flow weight
input double   InpOrderFlowMinVolume       = 0.90;       // Order flow min relative volume

//--- Indicators ----------------------------------------------------
input group                     "=== Indicators ==="
input int      InpFastMaPeriod             = 9;          // Fast MA period
input int      InpSlowMaPeriod             = 21;         // Slow MA period
input int      InpTrendMaPeriod            = 100;        // Trend MA period
input int      InpRsiPeriod                = 14;         // RSI period
input int      InpAtrPeriod                = 14;         // ATR period
input int      InpAdxPeriod                = 14;         // ADX period
input int      InpBollingerPeriod          = 20;         // Bollinger period
input double   InpBollingerDeviation       = 2.0;        // Bollinger deviation

//--- Smart money concepts ------------------------------------------
input group                     "=== Smart Money Concepts ==="
input bool     InpSmcEnabled               = true;       // Enable SMC analysis
input int      InpSmcSwingStrength         = 3;          // Swing strength (bars)
input int      InpSmcSwingLookback         = 300;        // Swing lookback (bars)
input int      InpSmcZoneCapacity          = 64;         // Zone capacity
input int      InpSmcZoneMaxAgeBars        = 500;        // Zone max age (bars)
input double   InpSmcDisplacementAtr       = 1.5;        // Displacement (ATR multiple)
input double   InpSmcMinGapPoints          = 50.0;       // Min gap (points)
input bool     InpSmcRequireDisplacement   = true;       // Require displacement
input double   InpSmcEqualToleranceAtr     = 0.15;       // Equal level tolerance (ATR)
input int      InpSmcSweepLookbackBars     = 10;         // Sweep lookback (bars)
input double   InpSmcStructureBreakBuffer  = 10.0;       // Structure break buffer (points)

//--- Dashboard -----------------------------------------------------
input group                     "=== Dashboard ==="
input bool     InpDashboardEnabled         = true;       // Show dashboard
input ENUM_SRP_UI_THEME InpDashboardTheme  = SRP_UI_THEME_DARK; // Theme
input int      InpDashboardCorner          = 0;          // Corner (0-3)
input int      InpDashboardXOffset         = 12;         // X offset (px)
input int      InpDashboardYOffset         = 22;         // Y offset (px)
input int      InpDashboardRefreshMs       = 500;        // Refresh interval (ms)
input bool     InpDashboardShowInTester    = false;      // Show in visual tester
input bool     InpDrawOverlayEnabled       = true;       // Draw chart overlay
input bool     InpDrawEntries              = true;       // Draw entries
input bool     InpDrawStops                = true;       // Draw stops and targets
input bool     InpDrawZones                = true;       // Draw zones
input bool     InpDrawLiquidity            = true;       // Draw liquidity
input bool     InpDrawStructure            = true;       // Draw structure
input bool     InpDrawSessionBoxes         = true;       // Draw session boxes
input bool     InpDrawTradeLabels          = true;       // Draw trade labels
input bool     InpDrawStatistics           = true;       // Draw statistics
input int      InpDrawMaxZones             = 12;         // Max zones drawn
input int      InpDrawZoneExtendBars       = 20;         // Zone extension (bars)

//--- Ultra-scalp mode ----------------------------------------------
input group                     "=== Ultra-Scalp Mode (XAUUSD) ==="
//--- Every setting below can only REDUCE trading. None creates an entry.
//--- Enabled automatically by the GOLD profile; this input lets you force
//--- it on or off regardless.
input bool     InpScalpModeEnabled         = true;       // Enable ultra-scalp mode
//--- Anti-double-fire window ONLY. Not a trade interval: a new trade
//--- always requires a genuinely new signal fingerprint.
input int      InpScalpCooldownSeconds     = 15;         // Duplicate-signal cooldown (s)
input int      InpScalpMaxHoldSeconds      = 300;        // Max holding time (s)
input double   InpScalpTargetAtrMultiple   = 0.55;       // Target (ATR multiple)
input double   InpScalpTargetMinPoints     = 0.0;        // Target floor (pts, 0=auto from costs)
input double   InpScalpTargetMaxPoints     = 0.0;        // Target ceiling (pts, 0=none)
input double   InpScalpStopAtrMultiple     = 0.90;       // Stop (ATR multiple)
//--- HARNESS v2, FIX 3. Was 0.0, i.e. every historical run modelled a
//--- broker that charges nothing to trade. On this XAUUSD spec 1 lot is
//--- 100 oz and one point is 0.01, so ONE POINT IS EXACTLY $1.00 PER LOT
//--- and this figure reads directly as USD per lot per round turn.
//---
//--- 6.0 is a MODELLED COST, not a measurement of this account. Evidence
//--- from the tester logs is that the demo feed charged zero commission:
//--- 12,798 of 12,873 losing closes came back at R = exactly -1.00, which
//--- is only possible when nothing is deducted beyond the price move.
//--- $6/lot round turn is the low end of a real raw-spread gold account.
//--- REPLACE IT with the broker's own schedule before quoting any result;
//--- leaving it at 0.0 is now flagged by the validator rather than passing
//--- silently. This value feeds target viability, the early-exit floor and
//--- the cost block in CScalpController, so it does change which trades
//--- are taken - deliberately, because the old answer was wrong.
input double   InpScalpCommissionPoints    = 6.0;        // Commission (points per round trip, 1pt=$1/lot)
input double   InpScalpExecCostPoints      = 0.0;        // Execution cost (pts, 0=auto)
input double   InpScalpMinRewardCostRatio  = 2.0;        // Min target/cost ratio
input double   InpScalpMaxSpreadTargetRatio= 0.35;       // Max spread as share of target
input bool     InpScalpEarlyExitEnabled    = true;       // Enable early profit exit
input double   InpScalpEarlyExitMinPoints  = 0.0;        // Early exit floor (pts, 0=auto)
// 0.85 matches the gold profile, which overrides this input at runtime. The old
// 0.55 default made the printed input block disagree with what actually ran, and
// the break-even gate now prices target*share, so the value is load-bearing.
input double   InpScalpEarlyExitTargetShare= 0.85;       // Early exit at share of target
input double   InpScalpAtrMinPoints        = 0.0;        // Min ATR to scalp (pts, 0=off)
input double   InpScalpAtrMaxPoints        = 0.0;        // Max ATR to scalp (pts, 0=off)

//--- Entry quality (accuracy) gate ---------------------------------
input group                     "=== Entry Accuracy (multi-timeframe + volume) ==="
//--- RAISES THE WIN RATE BY SELECTIVITY, NOT BY SHRINKING THE TARGET.
//---
//--- Shrinking a target raises the win rate and lowers the payoff by the
//--- same mechanism, so the break-even win rate rises to meet it and
//--- nothing is gained. These settings change WHICH trades are taken and
//--- leave the geometry alone, which is the only kind of improvement that
//--- survives contact with costs.
//---
//--- Measured basis: over 1221 real-tick XAUUSD trades the payoff was
//--- 0.948 (break-even 51.3%) against a 43.90% win rate, and 1219 of
//--- those trades were M1 signals with no requirement that M5 or M15
//--- agreed.
input bool     InpAccuracyEnabled          = true;       // Enable entry accuracy gate
input bool     InpAccuracyRequireSetup     = true;       // Require setup TF (M5) agreement
input bool     InpAccuracyRequireContext   = true;       // Require context TF (M15) agreement
//--- Tick volume, because this feed reports REAL volume as zero on gold.
input double   InpAccuracyMinRelVolume     = 1.00;       // Min relative volume (x average)
input int      InpAccuracyVolumeLookback   = 20;         // Volume average lookback (bars)
//--- How far through its recent range price may already be. A continuation
//--- entry taken at the extreme is the classic way a good signal becomes a
//--- bad trade.
input double   InpAccuracyMaxExtension     = 0.75;       // Max range extension at entry
input double   InpAccuracyMinScore         = 0.65;       // Min composite agreement score

//--- Scalp tiers ---------------------------------------------------
input group                     "=== Scalp Tiers ==="
//--- THE RELATIONSHIP THESE SETTINGS EXPRESS.
//---
//--- A win rate and a target size are not independent. Break-even payoff
//--- for a win rate W is (1-W)/W, so:
//---
//---     50% needs 1.000     60% needs 0.667
//---     70% needs 0.429     80% needs 0.250
//---
//--- A HIGH win rate therefore permits a SMALL target, and a small target
//--- is what makes a high win rate reachable. The tier's assumed win rate
//--- is enforced: any geometry that cannot break even at it is refused,
//--- with costs counted on both sides.
//---
//--- The tier is chosen from the regime, not from preference. Range and
//--- reversal go to SUPER (price returns, so a tight target is hit often);
//--- trend and breakout go to SWING (price runs, so a tight target leaves
//--- the move behind); high volatility forces SWING because a tight target
//--- sits inside the noise.
input bool     InpTierSuperEnabled         = true;       // SUPER-SCALP tier enabled
//--- REDESIGN 2026-09-04. WIDENED, BECAUSE COST WAS A THIRD OF THE TARGET.
//---
//--- 0.65/0.45 put a 155 point target against a 39-47 point round-trip cost
//--- on XAUUSD, and the early-profit exit collected only 85% of it. The
//--- geometry the robot actually traded was therefore 132 net of nothing
//--- against a 107 point stop plus cost on both sides: net payoff 0.61,
//--- break-even 61.2%, measured 35.4% over 144 trades in July 2026. No win
//--- rate this system can reach pays for that, so the target was not
//--- slightly wrong, it was the wrong size.
//---
//--- Cost is a FIXED number of points, so payoff improves superlinearly as
//--- the geometry widens. At ATR(14) M1 ~238 pts and cost ~46.5:
//---   stop  0.60xATR = 143 pts
//---   target 1.35xATR = 321 pts, of which the 0.85 share collects 273
//---   net payoff (273-46.5)/(143+46.5) = 1.195  ->  break-even 45.6%
//--- Derived from that arithmetic, not from a parameter search.
input double   InpTierSuperTargetAtr       = 1.35;       // SUPER target (ATR multiple)
input double   InpTierSuperStopAtr         = 0.60;       // SUPER stop (ATR multiple)
//--- A 321 point target cannot be reached in 120 seconds. The July data is
//--- monotonic on this: the 0-10s holding bucket lost 4.30 per trade over 53
//--- trades, the 61-120s bucket was flat over 21. The old window cut trades
//--- before the geometry it was sized for could resolve.
input int      InpTierSuperHoldSeconds     = 600;        // SUPER max hold (s)
//--- Set just ABOVE the 45.6% the geometry needs, never comfortably above.
//--- The 1.4 point margin is deliberate: when spread widens, cost rises, the
//--- requirement crosses this line and the gate refuses the trade by itself.
//--- That makes the figure a live constraint rather than a claim. Measured
//--- performance can only lower it (see CScalpController::GateWinRate).
input double   InpTierSuperWinRate         = 0.47;       // SUPER design win rate
input ENUM_TIMEFRAMES InpTierSuperTimeframe= PERIOD_M1;  // SUPER ATR timeframe

//--- DISABLED BY DEFAULT, ON MEASURED EVIDENCE.
//---
//--- STANDARD only receives HIGH_VOLATILITY and TRANSITION bars - the two
//--- regimes with the weakest premise of the five. Two independent fresh
//--- backtests (2026-01..04 and 2026-04..07, XAUUSD M1) confirm the same
//--- pattern: it ran BELOW its own break-even (51.08% win against a
//--- 62.34% requirement in the 4-month run) while contributing a small
//--- fraction of total entries, and got zero entries at all in the
//--- 3-month run. SUPER, by contrast, cleared break-even with margin in
//--- both. Disabling STANDARD does not stop those bars from trading - the
//--- tier selector falls back to SUPER, which is the tier actually proven
//--- to have an edge in this data. Set true to re-enable it for your own
//--- comparison.
input bool     InpTierStandardEnabled      = false;      // STANDARD tier enabled
//--- REDESIGN 2026-09-04. Left disabled, but made COHERENT: 0.70/0.70 could
//--- not clear cost at any win rate, so enabling it for a comparison would
//--- have measured nothing but the cost model. 1.20/0.60 collects 243 pts of
//--- a 286 pt target against a 143 pt stop - net payoff 1.04, break-even
//--- 49.1% - which the 0.50 design rate just clears.
input double   InpTierStandardTargetAtr    = 1.20;       // STANDARD target (ATR multiple)
input double   InpTierStandardStopAtr      = 0.60;       // STANDARD stop (ATR multiple)
input int      InpTierStandardHoldSeconds  = 300;        // STANDARD max hold (s)
input double   InpTierStandardWinRate      = 0.50;       // STANDARD design win rate
input ENUM_TIMEFRAMES InpTierStandardTimeframe = PERIOD_M1; // STANDARD ATR timeframe

//--- REDESIGN 2026-09-04. REACHABLE FOR THE FIRST TIME.
//---
//--- SelectScalpTier used to route only EXTREME volatility here, and the
//--- regime engine sets trading_allowed=false for exactly that class - so
//--- every run in this project's history reported SWING entries=0 while the
//--- robot ran on one tier. HIGH volatility now routes here, which is where
//--- a wide target is both reachable and cheapest relative to cost.
//---
//--- At ATR(14) M5 ~530 pts and cost ~46.5:
//---   stop  0.75xATR = 398 pts
//---   target 1.60xATR = 848 pts, of which the 0.85 share collects 721
//---   net payoff (721-46.5)/(398+46.5) = 1.517  ->  break-even 39.7%
//--- The old 1.40/0.90 needed 52.3% once the early exit was priced, which is
//--- why it was quoted as safe and was not.
input bool     InpTierSwingEnabled         = true;       // SWING-SCALP tier enabled
input double   InpTierSwingTargetAtr       = 1.60;       // SWING target (ATR multiple)
input double   InpTierSwingStopAtr         = 0.75;       // SWING stop (ATR multiple)
input int      InpTierSwingHoldSeconds     = 1800;       // SWING max hold (s)
input double   InpTierSwingWinRate         = 0.45;       // SWING design win rate
input ENUM_TIMEFRAMES InpTierSwingTimeframe= PERIOD_M5;  // SWING ATR timeframe

//--- Statistics ----------------------------------------------------
input group                     "=== Statistics ==="
input bool     InpJournalEnabled           = true;       // Write trade journal
input bool     InpPersistState             = true;       // Persist state across restarts
input string   InpStateFolder              = "ScalpRobotPro\\State"; // State folder
input int      InpAnalyticsMinSample       = 10;         // Analytics minimum sample
input bool     InpAnalyticsUseRMultiples   = false;      // Use R multiples
input double   InpAnalyticsInitialBalance  = 0.0;        // Initial balance (0=account)

//--- Optimisation --------------------------------------------------
input group                     "=== Optimisation ==="
input ENUM_SRP_OPTIMIZATION_CRITERION InpOptCriterion = SRP_CRITERION_CUSTOM_COMPOSITE; // Criterion
input int      InpOptMinTrades             = 30;         // Minimum trades to score
input double   InpOptDrawdownPenalty       = 1.0;        // Drawdown penalty weight
input double   InpOptConcentrationPenalty  = 1.0;        // Concentration penalty weight
input double   InpOptStreakPenalty         = 1.0;        // Losing streak penalty weight
input bool     InpOptWalkForwardEnabled    = false;      // Enable walk-forward reporting
input int      InpOptWfIsDays              = 90;         // Walk-forward in-sample (days)
input int      InpOptWfOosDays             = 30;         // Walk-forward out-of-sample (days)
input double   InpOptWfMinEfficiency       = 0.5;        // Walk-forward min efficiency
input bool     InpOptMonteCarloEnabled     = false;      // Run Monte Carlo on backtest
input int      InpOptMonteCarloRuns        = 1000;       // Monte Carlo runs
input int      InpOptMonteCarloSeed        = 0;          // Monte Carlo seed (0=random)
input double   InpOptMonteCarloRuinPercent = 30.0;       // Ruin threshold (%)
input bool     InpOptExportCsv             = true;       // Export pass CSV
input string   InpOptExportFolder          = "ScalpRobotPro\\Optimization"; // Export folder
input bool     InpOptForwardTestMode       = false;      // Forward test mode
input bool     InpOptRejectIncoherent      = true;       // Skip incoherent parameter sets

//--- Measurement harness -------------------------------------------
input group                     "=== Measurement Harness (reporting only) ==="
//--- HARNESS v2, FIX 4. THIS INPUT CHANGES NO TRADING DECISION.
//---
//--- It declares which half of the data the run is entitled to speak for,
//--- and it exists because nothing in fifteen months of this project's
//--- results recorded that. Every figure therefore read as a validation,
//--- including the ones produced by tuning on the same days they were
//--- measured over.
//---
//--- The terminal cannot supply this. MQL_FORWARD tells us whether the
//--- tester is in its forward window and nothing more, so a deliberate
//--- hold-out run over a date range the operator has never optimised on is
//--- indistinguishable from a development pass. Only the operator knows,
//--- so the operator states it - and the report header prints UNDECLARED
//--- and QUOTABLE=NO when they do not.
//---
//--- Leaving it UNDECLARED is allowed and produces a warning, not a
//--- refusal to start. What it does not produce is a quotable number.
input ENUM_SRP_DATA_SEGMENT InpRunDataSegment = SRP_SEGMENT_UNDECLARED; // Data segment this run speaks for

//--- HARNESS v2, FIX 5. AT THE DEFAULT OF 0.0 THIS CHANGES NO TRADING
//--- DECISION. AT ANY OTHER VALUE IT CHANGES ALL OF THEM, ON PURPOSE.
//---
//--- Audit 5.5: twelve trading distances - the stop floor, the fixed stop
//--- and target, the break-even trigger and offset, the trailing start,
//--- distance and step, the spread ceiling, the slippage allowance, the
//--- order deviation, the fair-value-gap threshold and the structure-break
//--- buffer - are all computed once at initialisation from ONE reading of
//--- SYMBOL_SPREAD, and nothing re-derives them afterwards.
//---
//--- The consequence is not a bad geometry, it is an unrepeatable one. Two
//--- backtests over the same dates start at different clock times, sample
//--- different ticks, and trade measurably different distances. Comparing
//--- them measures the arrival time of one tick.
//---
//--- 0.0 keeps the live sample, which is the shipping behaviour and what
//--- live trading needs - the geometry should fit the broker it runs on.
//--- Any positive value substitutes that number for the sample, so a
//--- measurement run can be repeated and an A/B can be believed.
//---
//--- What this is NOT: it does not make the geometry adaptive. A static
//--- geometry recomputed from a fixed root is still a static geometry, and
//--- whether one belongs here at all is a strategy question the audit puts
//--- in step 6. This fix makes the existing behaviour reproducible; it does
//--- not defend it.
input double   InpPinSpreadSample          = 0.0;       // Pin spread sample, points (0 = live tick)

//+------------------------------------------------------------------+
//| MODULE-LEVEL STATE                                                |
//| Two pointers, nothing more. Both are owned here and released in    |
//| reverse order.                                                    |
//+------------------------------------------------------------------+
CInputConfiguration *g_config = NULL;
CProductionEngine   *g_engine = NULL;

//+------------------------------------------------------------------+
//| Copies the input block into the transport struct.                  |
//| The ONLY function in the product that reads `input` variables.      |
//+------------------------------------------------------------------+
void CollectInputs(SInputSnapshot &snapshot)
  {
   //--- General
   snapshot.magic                    = InpMagicNumber;
   snapshot.order_comment            = InpOrderComment;
   snapshot.direction_mode           = InpDirectionMode;
   snapshot.tick_throttle_ms         = InpTickThrottleMs;
   snapshot.context_timeframe        = (int)InpContextTimeframe;
   snapshot.setup_timeframe          = (int)InpSetupTimeframe;
   //--- Logging
   snapshot.log_level                = InpLogLevel;
   snapshot.log_to_file              = InpLogToFile;
   snapshot.log_to_terminal          = InpLogToTerminal;
   snapshot.log_to_alert             = InpLogToAlert;
   snapshot.log_to_push              = InpLogToPush;
   snapshot.log_folder               = InpLogFolder;
   snapshot.log_daily_rotation       = InpLogDailyRotation;
   snapshot.log_channel_errors       = InpLogChannelErrors;
   snapshot.log_channel_trades       = InpLogChannelTrades;
   snapshot.log_channel_indicators   = InpLogChannelIndicators;
   snapshot.log_channel_risk         = InpLogChannelRisk;
   snapshot.log_channel_performance  = InpLogChannelPerformance;
   snapshot.log_channel_execution    = InpLogChannelExecution;
   snapshot.log_format_default       = 0;
   snapshot.log_mirror_errors_to_journal = InpLogMirrorErrors;
   snapshot.log_flush_every          = InpLogFlushEvery;
   //--- Risk. The input IS the sizing vocabulary the engine consumes, so
   //--- no translation happens here and none can go wrong.
   snapshot.sizing_model             = InpSizingModel;
   snapshot.risk_capital_base        = (int)InpCapitalBase;
   snapshot.fixed_lot                = InpFixedLot;
   snapshot.risk_percent             = InpRiskPercent;
   snapshot.max_lot                  = InpMaxLot;
   snapshot.max_positions            = InpMaxPositions;
   snapshot.kelly_fraction           = InpKellyFraction;
   snapshot.kelly_min_trades         = InpKellyMinTrades;
   snapshot.auto_lot_capital_per_step= InpAutoLotCapitalPerStep;
   snapshot.auto_lot_per_step        = InpAutoLotPerStep;
   snapshot.atr_risk_multiple        = InpAtrRiskMultiple;
   snapshot.max_spread_points        = InpMaxSpreadPoints;
   snapshot.max_slippage_points      = InpMaxSlippagePoints;
   snapshot.min_free_margin_percent  = InpMinFreeMarginPercent;
   //--- Protective levels
   snapshot.sl_mode                  = (ENUM_SRP_SL_MODE)InpStopModel;
   snapshot.sl_fixed_points          = InpSlFixedPoints;
   snapshot.sl_atr_multiplier        = InpSlAtrMultiplier;
   snapshot.tp_mode                  = (ENUM_SRP_TP_MODE)InpTargetModel;
   snapshot.tp_fixed_points          = InpTpFixedPoints;
   snapshot.tp_atr_multiplier        = InpTpAtrMultiplier;
   snapshot.tp_risk_reward           = InpTpRiskReward;
   //--- Trade management
   snapshot.trail_mode               = InpTrailMode;
   snapshot.trail_start_points       = InpTrailStartPoints;
   snapshot.trail_distance_points    = InpTrailDistancePoints;
   snapshot.trail_step_points        = InpTrailStepPoints;
   snapshot.breakeven_enabled        = InpBreakEvenEnabled;
   snapshot.breakeven_trigger_points = InpBreakEvenTriggerPoints;
   snapshot.breakeven_offset_points  = InpBreakEvenOffsetPoints;
   snapshot.tm_atr_trail_enabled     = InpAtrTrailEnabled;
   snapshot.tm_atr_trail_multiple    = InpAtrTrailMultiple;
   snapshot.tm_atr_exit_enabled      = InpAtrExitEnabled;
   snapshot.tm_atr_exit_multiple     = InpAtrExitMultiple;
   snapshot.tm_scale_out_enabled     = InpScaleOutEnabled;
   snapshot.tm_scale_out_trigger_points = InpScaleOutTriggerPoints;
   snapshot.tm_scale_out_fraction    = InpScaleOutFraction;
   snapshot.tm_scale_out_max         = InpScaleOutMax;
   snapshot.tm_scale_in_enabled      = InpScaleInEnabled;
   snapshot.tm_scale_in_trigger_points = InpScaleInTriggerPoints;
   snapshot.tm_scale_in_fraction     = InpScaleInFraction;
   snapshot.tm_scale_in_max          = InpScaleInMax;
   snapshot.tm_reverse_enabled       = InpReverseEnabled;
   snapshot.time_stop_enabled        = InpTimeStopEnabled;
   snapshot.time_stop_minutes        = InpTimeStopMinutes;
   snapshot.tm_max_hold_enabled      = InpMaxHoldEnabled;
   snapshot.tm_max_hold_minutes      = InpMaxHoldMinutes;
   //--- Partial close is expressed through scale-out in the production
   //--- trade manager; both are kept in step so either vocabulary works.
   snapshot.partial_close_enabled    = InpScaleOutEnabled;
   snapshot.partial_close_trigger_points = InpScaleOutTriggerPoints;
   snapshot.partial_close_percent    = InpScaleOutFraction*100.0;
   snapshot.profit_lock_enabled      = InpProfitLockEnabled;
   snapshot.profit_lock_trigger_percent = InpProfitLockTriggerPercent;
   snapshot.profit_lock_keep_percent = InpProfitLockKeepPercent;
   //--- Guards
   snapshot.daily_profit_enabled     = InpDailyProfitEnabled;
   snapshot.daily_profit_percent     = InpDailyProfitPercent;
   snapshot.daily_loss_enabled       = InpDailyLossEnabled;
   snapshot.daily_loss_percent       = InpDailyLossPercent;
   snapshot.weekly_loss_percent      = InpWeeklyLossPercent;
   snapshot.monthly_loss_percent     = InpMonthlyLossPercent;
   snapshot.max_drawdown_enabled     = InpMaxDrawdownEnabled;
   snapshot.max_drawdown_percent     = InpMaxDrawdownPercent;
   snapshot.consecutive_loss_limit   = InpConsecutiveLossLimit;
   snapshot.flatten_on_trip          = InpFlattenOnTrip;
   snapshot.daily_limit_terminal     = InpDailyLimitTerminal;
   snapshot.kill_switch_enabled      = InpKillSwitchEnabled;
   //--- Sessions and schedule
   snapshot.session_filter_enabled   = InpSessionFilterEnabled;
   snapshot.allow_sydney             = InpAllowSydney;
   snapshot.allow_tokyo              = InpAllowTokyo;
   snapshot.allow_london             = InpAllowLondon;
   snapshot.allow_newyork            = InpAllowNewYork;
   snapshot.kill_zones_only          = InpKillZonesOnly;
   snapshot.require_overlap          = InpRequireOverlap;
   snapshot.schedule_enabled         = InpScheduleEnabled;
   snapshot.weekend_filter           = InpWeekendFilter;
   snapshot.friday_close_minutes     = InpFridayCloseMinutes;
   snapshot.holiday_filter_enabled   = InpHolidayFilterEnabled;
   snapshot.holiday_list             = InpHolidayList;
   snapshot.broker_gmt_offset        = InpBrokerGmtOffset;
   snapshot.dst_adjust               = InpDstAdjust;
   snapshot.london_open_gmt          = InpLondonOpenGmt;
   snapshot.london_close_gmt         = InpLondonCloseGmt;
   snapshot.newyork_open_gmt         = InpNewYorkOpenGmt;
   snapshot.newyork_close_gmt        = InpNewYorkCloseGmt;
   snapshot.primary_kz_open_gmt      = InpPrimaryKzOpenGmt;
   snapshot.primary_kz_close_gmt     = InpPrimaryKzCloseGmt;
   snapshot.skip_after_open_minutes  = InpSkipAfterOpenMinutes;
   snapshot.skip_before_close_minutes= InpSkipBeforeCloseMinutes;
   //--- News
   snapshot.news_filter_enabled      = InpNewsFilterEnabled;
   snapshot.news_source              = InpNewsSource;
   snapshot.news_min_impact          = InpNewsMinImpact;
   snapshot.news_minutes_before      = InpNewsMinutesBefore;
   snapshot.news_minutes_after       = InpNewsMinutesAfter;
   snapshot.news_close_positions     = InpNewsClosePositions;
   snapshot.news_csv_file            = InpNewsCsvFile;
   snapshot.news_currency_filter     = InpNewsCurrencyFilter;
   snapshot.news_fail_safe_block     = InpNewsFailSafeBlock;
   //--- Filters
   snapshot.spread_filter_enabled    = InpSpreadFilterEnabled;
   snapshot.volatility_filter_enabled= InpVolatilityFilterEnabled;
   snapshot.volatility_min_atr       = InpVolatilityMinAtr;
   snapshot.volatility_max_atr       = InpVolatilityMaxAtr;
   snapshot.trend_filter_enabled     = InpTrendFilterEnabled;
   snapshot.trend_timeframe          = InpTrendTimeframe;
   snapshot.frequency_filter_enabled = InpFrequencyFilterEnabled;
   snapshot.min_seconds_between_trades = InpMinSecondsBetweenTrades;
   snapshot.max_trades_per_day       = InpMaxTradesPerDay;
   snapshot.max_trades_per_hour      = InpMaxTradesPerHour;
   //--- Strategies and decision engine
   snapshot.aggregation_mode         = InpAggregationMode;
   snapshot.min_confidence           = InpMinConfidence;
   snapshot.decision_vote_mode       = InpVoteMode;
   snapshot.decision_min_confirmations = InpMinConfirmations;
   snapshot.decision_min_confidence  = InpMinConfidence;
   snapshot.decision_max_risk_rating = InpMaxRiskRating;
   snapshot.require_confirmation     = InpRequireConfirmation;
   snapshot.ema_cross_enabled        = InpEmaCrossEnabled;
   snapshot.vwap_pullback_enabled    = InpVwapPullbackEnabled;
   snapshot.liquidity_sweep_enabled  = InpLiquiditySweepEnabled;
   snapshot.order_block_enabled      = InpOrderBlockEnabled;
   snapshot.fvg_enabled              = InpFvgEnabled;
   snapshot.opening_range_enabled    = InpOpeningRangeEnabled;
   snapshot.trend_continuation_enabled = InpTrendContinuationEnabled;
   snapshot.momentum_enabled         = InpMomentumEnabled;
   snapshot.momentum_weight          = InpMomentumWeight;
   snapshot.mean_reversion_enabled   = InpMeanReversionEnabled;
   snapshot.mean_reversion_weight    = InpMeanReversionWeight;
   snapshot.breakout_enabled         = InpBreakoutEnabled;
   snapshot.breakout_weight          = InpBreakoutWeight;
   snapshot.bos_enabled              = InpBosEnabled;
   snapshot.bos_weight               = InpBosWeight;
   snapshot.volatility_breakout_enabled = InpVolBreakoutEnabled;
   snapshot.volatility_breakout_weight  = InpVolBreakoutWeight;
   snapshot.order_flow_enabled       = InpOrderFlowEnabled;
   snapshot.order_flow_weight        = InpOrderFlowWeight;
   snapshot.order_flow_min_volume    = InpOrderFlowMinVolume;
   //--- Indicators
   snapshot.fast_ma_period           = InpFastMaPeriod;
   snapshot.slow_ma_period           = InpSlowMaPeriod;
   snapshot.trend_ma_period          = InpTrendMaPeriod;
   snapshot.rsi_period               = InpRsiPeriod;
   snapshot.atr_period               = InpAtrPeriod;
   snapshot.adx_period               = InpAdxPeriod;
   snapshot.bollinger_period         = InpBollingerPeriod;
   snapshot.bollinger_deviation      = InpBollingerDeviation;
   //--- Smart money concepts
   snapshot.smc_enabled              = InpSmcEnabled;
   snapshot.smc_swing_strength       = InpSmcSwingStrength;
   snapshot.smc_swing_lookback       = InpSmcSwingLookback;
   snapshot.smc_zone_capacity        = InpSmcZoneCapacity;
   snapshot.smc_zone_max_age_bars    = InpSmcZoneMaxAgeBars;
   snapshot.smc_displacement_atr_multiple = InpSmcDisplacementAtr;
   snapshot.smc_min_gap_points       = InpSmcMinGapPoints;
   snapshot.smc_require_displacement = InpSmcRequireDisplacement;
   snapshot.smc_equal_tolerance_atr  = InpSmcEqualToleranceAtr;
   snapshot.smc_sweep_lookback_bars  = InpSmcSweepLookbackBars;
   snapshot.smc_structure_break_buffer = InpSmcStructureBreakBuffer;
   //--- Dashboard
   snapshot.dashboard_enabled        = InpDashboardEnabled;
   snapshot.dashboard_theme          = (ENUM_SRP_THEME)InpDashboardTheme;
   snapshot.dashboard_corner         = InpDashboardCorner;
   snapshot.dashboard_x_offset       = InpDashboardXOffset;
   snapshot.dashboard_y_offset       = InpDashboardYOffset;
   snapshot.dashboard_refresh_ms     = InpDashboardRefreshMs;
   snapshot.dashboard_show_in_tester = InpDashboardShowInTester;
   snapshot.draw_overlay_enabled     = InpDrawOverlayEnabled;
   snapshot.draw_entries             = InpDrawEntries;
   snapshot.draw_stops               = InpDrawStops;
   snapshot.draw_zones               = InpDrawZones;
   snapshot.draw_liquidity           = InpDrawLiquidity;
   snapshot.draw_structure           = InpDrawStructure;
   snapshot.draw_session_boxes       = InpDrawSessionBoxes;
   snapshot.draw_trade_labels        = InpDrawTradeLabels;
   snapshot.draw_statistics          = InpDrawStatistics;
   snapshot.draw_max_zones           = InpDrawMaxZones;
   snapshot.draw_zone_extend_bars    = InpDrawZoneExtendBars;
   //--- Ultra-scalp mode
   snapshot.scalp_mode_enabled       = InpScalpModeEnabled;
   snapshot.scalp_cooldown_seconds   = InpScalpCooldownSeconds;
   snapshot.scalp_max_hold_seconds   = InpScalpMaxHoldSeconds;
   snapshot.scalp_target_atr_multiple= InpScalpTargetAtrMultiple;
   snapshot.scalp_target_min_points  = InpScalpTargetMinPoints;
   snapshot.scalp_target_max_points  = InpScalpTargetMaxPoints;
   snapshot.scalp_stop_atr_multiple  = InpScalpStopAtrMultiple;
   snapshot.scalp_commission_points  = InpScalpCommissionPoints;
   snapshot.scalp_execution_cost_points = InpScalpExecCostPoints;
   snapshot.scalp_min_reward_cost_ratio = InpScalpMinRewardCostRatio;
   snapshot.scalp_max_spread_target_ratio = InpScalpMaxSpreadTargetRatio;
   snapshot.scalp_early_exit_enabled = InpScalpEarlyExitEnabled;
   snapshot.scalp_early_exit_min_points = InpScalpEarlyExitMinPoints;
   snapshot.scalp_early_exit_target_share = InpScalpEarlyExitTargetShare;
   snapshot.scalp_atr_min_points     = InpScalpAtrMinPoints;
   snapshot.scalp_atr_max_points     = InpScalpAtrMaxPoints;
   //--- Entry accuracy gate
   snapshot.accuracy_filter_enabled      = InpAccuracyEnabled;
   snapshot.accuracy_require_setup       = InpAccuracyRequireSetup;
   snapshot.accuracy_require_context     = InpAccuracyRequireContext;
   snapshot.accuracy_min_relative_volume = InpAccuracyMinRelVolume;
   snapshot.accuracy_volume_lookback     = InpAccuracyVolumeLookback;
   snapshot.accuracy_max_extension       = InpAccuracyMaxExtension;
   snapshot.accuracy_min_score           = InpAccuracyMinScore;
   //--- Scalp tiers: 0=SUPER, 1=STANDARD, 2=SWING.
   snapshot.tier_enabled[0]          = InpTierSuperEnabled;
   snapshot.tier_target_atr[0]       = InpTierSuperTargetAtr;
   snapshot.tier_stop_atr[0]         = InpTierSuperStopAtr;
   snapshot.tier_hold_seconds[0]     = InpTierSuperHoldSeconds;
   snapshot.tier_win_rate[0]         = InpTierSuperWinRate;
   snapshot.tier_timeframe[0]        = (int)InpTierSuperTimeframe;
   snapshot.tier_enabled[1]          = InpTierStandardEnabled;
   snapshot.tier_target_atr[1]       = InpTierStandardTargetAtr;
   snapshot.tier_stop_atr[1]         = InpTierStandardStopAtr;
   snapshot.tier_hold_seconds[1]     = InpTierStandardHoldSeconds;
   snapshot.tier_win_rate[1]         = InpTierStandardWinRate;
   snapshot.tier_timeframe[1]        = (int)InpTierStandardTimeframe;
   snapshot.tier_enabled[2]          = InpTierSwingEnabled;
   snapshot.tier_target_atr[2]       = InpTierSwingTargetAtr;
   snapshot.tier_stop_atr[2]         = InpTierSwingStopAtr;
   snapshot.tier_hold_seconds[2]     = InpTierSwingHoldSeconds;
   snapshot.tier_win_rate[2]         = InpTierSwingWinRate;
   snapshot.tier_timeframe[2]        = (int)InpTierSwingTimeframe;

   //--- Statistics
   snapshot.journal_enabled          = InpJournalEnabled;
   snapshot.persist_state            = InpPersistState;
   snapshot.state_folder             = InpStateFolder;
   snapshot.analytics_min_sample     = InpAnalyticsMinSample;
   snapshot.analytics_use_r_multiples= InpAnalyticsUseRMultiples;
   snapshot.analytics_initial_balance= InpAnalyticsInitialBalance;
   //--- Optimisation
   snapshot.opt_criterion            = InpOptCriterion;
   snapshot.opt_min_trades           = InpOptMinTrades;
   snapshot.opt_drawdown_penalty     = InpOptDrawdownPenalty;
   snapshot.opt_concentration_penalty= InpOptConcentrationPenalty;
   snapshot.opt_streak_penalty       = InpOptStreakPenalty;
   snapshot.opt_walk_forward_enabled = InpOptWalkForwardEnabled;
   snapshot.opt_wf_is_days           = InpOptWfIsDays;
   snapshot.opt_wf_oos_days          = InpOptWfOosDays;
   snapshot.opt_wf_min_efficiency    = InpOptWfMinEfficiency;
   snapshot.opt_monte_carlo_enabled  = InpOptMonteCarloEnabled;
   snapshot.opt_monte_carlo_runs     = InpOptMonteCarloRuns;
   snapshot.opt_monte_carlo_seed     = InpOptMonteCarloSeed;
   snapshot.opt_monte_carlo_ruin_percent = InpOptMonteCarloRuinPercent;
   snapshot.opt_export_csv           = InpOptExportCsv;
   snapshot.opt_export_folder        = InpOptExportFolder;
   snapshot.opt_forward_test_mode    = InpOptForwardTestMode;
   snapshot.opt_reject_incoherent    = InpOptRejectIncoherent;
   //--- Exposure ceiling, shared by the limit guard.
   snapshot.max_exposure_percent     = InpMaxExposurePercent;
   //--- HARNESS v2, FIX 4. Reporting only; see the input's comment.
   snapshot.data_segment             = InpRunDataSegment;
   //--- HARNESS v2, FIX 5. Inert at 0.0; the root of the geometry chain
   //--- at anything else. See the input's comment.
   snapshot.pin_spread_sample        = InpPinSpreadSample;
  }

//+------------------------------------------------------------------+
//| Reads the broker's description of the instrument once, at init.     |
//|                                                                  |
//| This is the ONE place the entry point calls SymbolInfo*, and it does |
//| so purely to hand the validator real broker limits. Every other      |
//| module receives the resolved struct rather than querying the         |
//| terminal, which is what keeps 2-digit indices and 5-digit majors on  |
//| identical code paths.                                               |
//+------------------------------------------------------------------+
bool ResolveSymbolSpec(const string symbol,SSymbolSpec &spec)
  {
   spec.Reset();
   //--- A symbol absent from Market Watch returns zeroes rather than
   //--- failing, so selection is verified before anything is trusted.
   if(!SymbolSelect(symbol,true))
      return(false);

   spec.symbol              = symbol;
   spec.digits              = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   spec.point               = SymbolInfoDouble(symbol,SYMBOL_POINT);
   spec.tick_size           = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   spec.tick_value          = SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   spec.contract_size       = SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   spec.volume_min          = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   spec.volume_max          = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   spec.volume_step         = SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   spec.stops_level_points  = (int)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
   spec.freeze_level_points = (int)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   spec.margin_initial      = SymbolInfoDouble(symbol,SYMBOL_MARGIN_INITIAL);
   spec.swap_long           = SymbolInfoDouble(symbol,SYMBOL_SWAP_LONG);
   spec.swap_short          = SymbolInfoDouble(symbol,SYMBOL_SWAP_SHORT);
   spec.trade_mode          = (ENUM_SYMBOL_TRADE_MODE)
                              SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
   spec.calc_mode           = (ENUM_SYMBOL_CALC_MODE)
                              SymbolInfoInteger(symbol,SYMBOL_TRADE_CALC_MODE);

   //--- Point and volume step are the two values every downstream
   //--- calculation divides by. Zero means the symbol is not really
   //--- available, whatever the other fields say.
   spec.is_resolved=(spec.point>0.0 && spec.volume_step>0.0 &&
                     spec.digits>0);
   return(spec.is_resolved);
  }

//+------------------------------------------------------------------+
//| Releases the object graph. Safe to call more than once.            |
//+------------------------------------------------------------------+
void ReleaseGraph(void)
  {
   //--- Reverse construction order: engine first, then the configuration
   //--- it borrowed. Deleting config first would leave the engine reading
   //--- freed memory during its own teardown.
   if(g_engine!=NULL)
     {
      delete g_engine;
      g_engine=NULL;
     }
   if(g_config!=NULL)
     {
      delete g_config;
      g_config=NULL;
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization                                              |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   //--- 1. RESOLVE THE INSTRUMENT FIRST.
   //--- Everything downstream depends on the broker's own contract
   //--- specification, and a symbol that cannot be resolved must abort
   //--- startup rather than run on zeroes.
   SSymbolProfile symbol_spec;
   if(!CSymbolClassifier::Resolve(_Symbol,symbol_spec))
     {
      Print(SRP_PRODUCT_NAME,": cannot trade ",_Symbol," - ",
            symbol_spec.resolve_error);
      return(INIT_FAILED);
     }

   //--- 1b. HARNESS v2, FIX 5. PIN THE ROOT OF THE TRADE GEOMETRY.
   //---
   //--- Resolve() has just read SYMBOL_SPREAD, and step 2 below turns that
   //--- one number into twelve trading distances that never change again
   //--- (audit 5.5). The substitution has to happen here, between the read
   //--- and the derivation, because after BuildForMode the arithmetic is
   //--- already done.
   //---
   //--- InpPinSpreadSample is read directly rather than through the snapshot
   //--- for the same reason InpProfileMode is below: the geometry is built
   //--- before the configuration exists to hold it. CollectInputs still
   //--- carries it, so the sealed config, the validator and the report
   //--- header all see the same value the profile was built from.
   if(CSymbolClassifier::PinSpreadSample(symbol_spec,InpPinSpreadSample))
      Print(SRP_PRODUCT_NAME,": spread sample PINNED at ",
            DoubleToString(InpPinSpreadSample,2),
            " pts - the trade geometry is reproducible for this run");

   Print(CSymbolClassifier::Describe(symbol_spec));

   //--- Refuse to start on an instrument the broker will not fully trade.
   if(!symbol_spec.IsTradable())
     {
      Print(SRP_PRODUCT_NAME,": ",_Symbol,
            " is not fully tradable on this account",
            (symbol_spec.IsCloseOnly() ? " (close-only)" : ""));
      return(INIT_FAILED);
     }

   //--- 2. SELECT AND APPLY THE MARKET PROFILE.
   //--- The profile supplies asset-specific defaults so NASDAQ and gold
   //--- cannot silently share a parameter. Inputs are collected after it
   //--- when the trader wants the final say.
   SMarketProfile market_profile;
   CMarketProfileFactory::BuildForMode(symbol_spec,InpProfileMode,
                                       market_profile);
   Print(CProfileApplier::DescribeApplication(market_profile,symbol_spec));
   Print(CMarketProfileFactory::Describe(market_profile));
   //--- HARNESS v2, FIX 5. The derivation itself, not just its results.
   //--- Printed immediately after the profile dump so the twelve distances
   //--- above and the one number they came from are in the same log block.
   Print(CMarketProfileFactory::DescribeDerivation(market_profile));

   //--- 3. Collect inputs at the boundary.
   SInputSnapshot inputs;
   CollectInputs(inputs);

   //--- PRECEDENCE. When the profile wins, its asset-specific values
   //--- overwrite the input block; otherwise the inputs stand and the
   //--- profile was advisory. Either way the choice is explicit and
   //--- logged, never implicit.
   if(InpProfileOverridesInputs)
     {
      CProfileApplier::Apply(market_profile,inputs);
      Print(SRP_PRODUCT_NAME,": profile values override the input block "
            "(InpProfileOverridesInputs=true)");
     }
   else
      Print(SRP_PRODUCT_NAME,": input block overrides the profile "
            "(InpProfileOverridesInputs=false)");

   //--- 4. Populate and SEAL the configuration. After this line no
   //--- setting can change for the rest of the run.
   g_config=new CInputConfiguration(NULL);
   if(g_config==NULL)
     {
      Print(SRP_PRODUCT_NAME,": failed to allocate configuration");
      return(INIT_FAILED);
     }
   if(!CConfigurationBuilder::Populate(g_config,inputs))
     {
      Print(SRP_PRODUCT_NAME,": configuration could not be populated");
      ReleaseGraph();
      return(INIT_FAILED);
     }

   //--- 5. Validate before building anything. A contradictory setting
   //--- must abort OnInit, not surface as odd behaviour on tick 10,000.
   //---
   //--- The broker spec is supplied so the BROKER-RELATIVE rules actually
   //--- run. Without it the validator reports them as skipped, which
   //--- means a stop closer than the broker's minimum, a volume below the
   //--- minimum lot, or a symbol that is close-only would all pass
   //--- validation and fail later at OrderSend instead.
   CConfigValidator validator(NULL);
   SSymbolSpec spec;
   if(ResolveSymbolSpec(_Symbol,spec))
      validator.SetSymbolSpec(spec);
   else
      Print(SRP_PRODUCT_NAME,": ",_Symbol," specification unavailable, "
            "broker-relative validation will be reported as skipped");

   SValidationResult validation;
   if(!validator.ValidateAll(g_config,validation))
     {
      Print(SRP_PRODUCT_NAME," configuration is invalid:");
      Print(validation.report);
      ReleaseGraph();
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(validation.warning_count>0)
      Print(SRP_PRODUCT_NAME," configuration warnings:\n",validation.report);

   //--- 6. During an optimisation, skip parameter sets that cannot
   //--- produce a meaningful result. Returning INIT_PARAMETERS_INCORRECT
   //--- makes the tester discard the pass instead of spending minutes on
   //--- a combination that was incoherent from the start.
   if(InpOptRejectIncoherent && (bool)MQLInfoInteger(MQL_OPTIMIZATION))
     {
      CParameterSetValidator screen(NULL);
      SValidationResult worth;
      if(!screen.IsWorthTesting(g_config,worth))
        {
         Print(SRP_PRODUCT_NAME," pass skipped: ",worth.first_error);
         ReleaseGraph();
         return(INIT_PARAMETERS_INCORRECT);
        }
     }

   //--- 7. Build the engine over the sealed configuration.
   g_engine=new CProductionEngine();
   if(g_engine==NULL)
     {
      Print(SRP_PRODUCT_NAME,": failed to allocate engine");
      ReleaseGraph();
      return(INIT_FAILED);
     }
   if(!g_engine.Build(g_config,_Symbol,_Period))
     {
      //--- The validation report explains exactly what was wrong, so a
      //--- user (or support) never has to guess why startup failed.
      Print(SRP_PRODUCT_NAME," initialisation failed:");
      Print(g_engine.ValidationReport());
      ReleaseGraph();
      return(INIT_FAILED);
     }

   const int start_code=g_engine.Start();
   if(start_code!=INIT_SUCCEEDED)
     {
      ReleaseGraph();
      return(start_code);
     }

   //--- The engine drives its own housekeeping from the timer, keeping
   //--- slow work (news refresh, limit windows, log flushing) off the
   //--- tick path entirely. The tester has no timer, so it is not armed
   //--- there - OnTimer would never fire anyway.
   if(!(bool)MQLInfoInteger(MQL_TESTER))
      EventSetMillisecondTimer(SRP_TIMER_INTERVAL_MS);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_engine!=NULL)
      g_engine.Stop(reason);
   ReleaseGraph();
  }

//+------------------------------------------------------------------+
//| Tick                                                               |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   if(g_engine==NULL)
      return;
   g_engine.OnTickEvent();
  }

//+------------------------------------------------------------------+
//| Timer                                                              |
//+------------------------------------------------------------------+
void OnTimer(void)
  {
   if(g_engine==NULL)
      return;
   g_engine.OnTimerEvent();
  }

//+------------------------------------------------------------------+
//| Trade transaction                                                  |
//| The authoritative notification of stop-loss and take-profit hits.  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(g_engine==NULL)
      return;
   g_engine.OnTradeTransactionEvent(transaction,request,result);
  }

//+------------------------------------------------------------------+
//| Chart event                                                        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(g_engine==NULL)
      return;
   g_engine.OnChartEventReceived(id,lparam,dparam,sparam);
  }

//+------------------------------------------------------------------+
//| Tester fitness value                                               |
//| Called after the last tick and before OnDeinit, so the graph is     |
//| still alive and the pass statistics are readable.                   |
//+------------------------------------------------------------------+
double OnTester(void)
  {
   if(g_engine==NULL)
      return(0.0);
   return(g_engine.OnTesterEvent());
  }
//+------------------------------------------------------------------+
