//+------------------------------------------------------------------+
//|                                                 CConfigKeys.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Configuration : the single vocabulary of setting names.             |
//|                                                                  |
//|   Every configuration lookup uses a constant from this file. String  |
//|   literals scattered across modules are a silent-failure machine:    |
//|   a typo yields the fallback value and the module quietly behaves    |
//|   differently than configured. Named constants make that a compile   |
//|   error instead.                                                     |
//+------------------------------------------------------------------+
#ifndef SRP_CONFIGURATION_CCONFIGKEYS_MQH
#define SRP_CONFIGURATION_CCONFIGKEYS_MQH

class CConfigKeys
  {
public:
   //--- General ------------------------------------------------------
   static const string GENERAL_MAGIC;
   static const string GENERAL_ORDER_COMMENT;
   static const string GENERAL_DIRECTION_MODE;
   static const string GENERAL_TICK_THROTTLE_MS;
   static const string GENERAL_TIMER_INTERVAL_MS;
   //--- HARNESS v2, FIX 4. Which half of the data the run is allowed to
   //--- speak for. Declared by the operator, never inferred: the terminal
   //--- knows about forward passes and nothing else, so a hold-out run and
   //--- a development run are indistinguishable to it. Consumed only by
   //--- the report header - it can move no order and gate no trade.
   static const string GENERAL_DATA_SEGMENT;
   //--- HARNESS v2, FIX 5. Substitutes a declared spread sample for the
   //--- one read from the tick at initialisation. Twelve trading distances
   //--- descend from that single reading (audit 5.5), so unlike the segment
   //--- key above this one DOES move orders whenever it is non-zero. It is
   //--- a general key rather than a scalp key because the classifier, the
   //--- market profile and the scalp controller all sample independently
   //--- and all three have to be given the same root.
   static const string GENERAL_PIN_SPREAD_SAMPLE;

   //--- Logging ------------------------------------------------------
   static const string LOG_LEVEL;
   static const string LOG_TO_FILE;
   static const string LOG_TO_TERMINAL;
   static const string LOG_TO_ALERT;
   static const string LOG_TO_PUSH;
   static const string LOG_DAILY_ROTATION;

   //--- Risk ---------------------------------------------------------
   static const string RISK_MODE;
   static const string RISK_FIXED_LOT;
   static const string RISK_FIXED_MONEY;
   static const string RISK_PERCENT;
   static const string RISK_MAX_LOT;
   static const string RISK_MIN_LOT;
   static const string RISK_MAX_POSITIONS;
   static const string RISK_MAX_POSITIONS_PER_DIRECTION;
   static const string RISK_MAX_TOTAL_VOLUME;
   static const string RISK_MAX_SPREAD_POINTS;
   static const string RISK_MAX_SLIPPAGE_POINTS;
   static const string RISK_MIN_FREE_MARGIN_PERCENT;
   static const string RISK_MAX_RISK_PERCENT_TOTAL;

   //--- Protective levels --------------------------------------------
   static const string SL_MODE;
   static const string SL_FIXED_POINTS;
   static const string SL_ATR_MULTIPLIER;
   static const string TP_MODE;
   static const string TP_FIXED_POINTS;
   static const string TP_ATR_MULTIPLIER;
   static const string TP_RISK_REWARD;
   static const string TRAIL_MODE;
   static const string TRAIL_START_POINTS;
   static const string TRAIL_STEP_POINTS;
   static const string TRAIL_DISTANCE_POINTS;
   static const string BREAKEVEN_ENABLED;
   static const string BREAKEVEN_TRIGGER_POINTS;
   static const string BREAKEVEN_OFFSET_POINTS;
   static const string PARTIAL_CLOSE_ENABLED;
   static const string PARTIAL_CLOSE_TRIGGER_POINTS;
   static const string PARTIAL_CLOSE_PERCENT;
   static const string TIME_STOP_ENABLED;
   static const string TIME_STOP_MINUTES;

   //--- Account protection -------------------------------------------
   static const string GUARD_DAILY_PROFIT_ENABLED;
   static const string GUARD_DAILY_PROFIT_PERCENT;
   static const string GUARD_DAILY_LOSS_ENABLED;
   static const string GUARD_DAILY_LOSS_PERCENT;
   static const string GUARD_MAX_DRAWDOWN_ENABLED;
   static const string GUARD_MAX_DRAWDOWN_PERCENT;
   static const string GUARD_EQUITY_FLOOR_ENABLED;
   static const string GUARD_EQUITY_FLOOR_VALUE;
   static const string GUARD_CONSECUTIVE_LOSS_LIMIT;
   static const string GUARD_FLATTEN_ON_TRIP;
   //--- HARNESS v2. Terminality of the daily loss limit, kept separate from
   //--- the drawdown latch. See CProductionEngine::StandDownForDay.
   static const string GUARD_DAILY_LIMIT_TERMINAL;
   static const string KILL_SWITCH_ENABLED;

   //--- Sessions and schedule ----------------------------------------
   static const string SESSION_FILTER_ENABLED;
   static const string SESSION_ALLOW_SYDNEY;
   static const string SESSION_ALLOW_TOKYO;
   static const string SESSION_ALLOW_LONDON;
   static const string SESSION_ALLOW_NEWYORK;
   static const string SCHEDULE_ENABLED;
   static const string SCHEDULE_MONDAY_START;
   static const string SCHEDULE_MONDAY_END;
   static const string SCHEDULE_FRIDAY_CLOSE_MINUTES;
   static const string HOLIDAY_FILTER_ENABLED;
   static const string HOLIDAY_LIST;

   //--- News ---------------------------------------------------------
   static const string NEWS_FILTER_ENABLED;
   static const string NEWS_SOURCE;
   static const string NEWS_MIN_IMPACT;
   static const string NEWS_MINUTES_BEFORE;
   static const string NEWS_MINUTES_AFTER;
   static const string NEWS_CLOSE_POSITIONS;
   static const string NEWS_CSV_FILE;
   static const string NEWS_CURRENCY_FILTER;
   static const string NEWS_FAIL_SAFE_BLOCK;

   //--- Market filters ------------------------------------------------
   static const string FILTER_SPREAD_ENABLED;
   static const string FILTER_VOLATILITY_ENABLED;
   static const string FILTER_VOLATILITY_MIN_ATR;
   static const string FILTER_VOLATILITY_MAX_ATR;
   static const string FILTER_TREND_ENABLED;
   static const string FILTER_TREND_TIMEFRAME;
   static const string FILTER_FREQUENCY_ENABLED;
   static const string FILTER_MIN_SECONDS_BETWEEN_TRADES;
   static const string FILTER_MAX_TRADES_PER_DAY;
   static const string FILTER_MAX_TRADES_PER_HOUR;

   //--- Strategies ----------------------------------------------------
   static const string STRATEGY_AGGREGATION_MODE;
   static const string STRATEGY_MIN_CONFIDENCE;
   static const string STRATEGY_MOMENTUM_ENABLED;
   static const string STRATEGY_MOMENTUM_WEIGHT;
   static const string STRATEGY_MEAN_REVERSION_ENABLED;
   static const string STRATEGY_MEAN_REVERSION_WEIGHT;
   static const string STRATEGY_BREAKOUT_ENABLED;
   static const string STRATEGY_BREAKOUT_WEIGHT;
   static const string DECISION_REQUIRE_CONFIRMATION;
   //--- Added in Phase 6: the two strategies Part 8 required.
   static const string STRATEGY_BOS_ENABLED;
   static const string STRATEGY_BOS_WEIGHT;
   static const string STRATEGY_VOLATILITY_BREAKOUT_ENABLED;
   static const string STRATEGY_VOLATILITY_BREAKOUT_WEIGHT;
   //--- Order flow / volume delta (OBV + MFI + relative volume).
   static const string STRATEGY_ORDER_FLOW_ENABLED;
   static const string STRATEGY_ORDER_FLOW_WEIGHT;
   static const string STRATEGY_ORDER_FLOW_MIN_VOLUME;
   //--- Ultra-scalp mode.
   static const string SCALP_MODE_ENABLED;
   static const string SCALP_COOLDOWN_SECONDS;
   static const string SCALP_MAX_HOLD_SECONDS;
   static const string SCALP_TARGET_ATR_MULTIPLE;
   static const string SCALP_TARGET_MIN_POINTS;
   static const string SCALP_TARGET_MAX_POINTS;
   static const string SCALP_STOP_ATR_MULTIPLE;
   static const string SCALP_COMMISSION_POINTS;
   static const string SCALP_EXECUTION_COST_POINTS;
   static const string SCALP_MIN_REWARD_COST_RATIO;
   static const string SCALP_MAX_SPREAD_TARGET_RATIO;
   static const string SCALP_EARLY_EXIT_ENABLED;
   static const string SCALP_EARLY_EXIT_MIN_POINTS;
   static const string SCALP_EARLY_EXIT_TARGET_SHARE;
   static const string SCALP_ATR_MIN_POINTS;
   static const string SCALP_ATR_MAX_POINTS;

   //--- Entry quality gate.
   static const string ACCURACY_FILTER_ENABLED;
   static const string ACCURACY_REQUIRE_SETUP;
   static const string ACCURACY_REQUIRE_CONTEXT;
   static const string ACCURACY_MIN_RELATIVE_VOLUME;
   static const string ACCURACY_VOLUME_LOOKBACK;
   static const string ACCURACY_MAX_EXTENSION;
   static const string ACCURACY_MIN_SCORE;
   //--- Scalp tiers. One key set per tier, suffixed by index so the store
   //--- stays a flat namespace rather than growing a nested structure.
   static const string TIER_ENABLED_PREFIX;
   static const string TIER_TARGET_ATR_PREFIX;
   static const string TIER_STOP_ATR_PREFIX;
   static const string TIER_HOLD_SECONDS_PREFIX;
   static const string TIER_WIN_RATE_PREFIX;
   static const string TIER_TIMEFRAME_PREFIX;

   //--- Multi-timeframe. Context carries regime; setup carries structure.
   static const string GENERAL_CONTEXT_TIMEFRAME;
   static const string GENERAL_SETUP_TIMEFRAME;
   //--- Session window times, per asset. Previously the windows were
   //--- hardcoded constants in the session manager's constructor.
   static const string SESSION_LONDON_OPEN_GMT;
   static const string SESSION_LONDON_CLOSE_GMT;
   static const string SESSION_NEWYORK_OPEN_GMT;
   static const string SESSION_NEWYORK_CLOSE_GMT;
   static const string SESSION_PRIMARY_KZ_OPEN_GMT;
   static const string SESSION_PRIMARY_KZ_CLOSE_GMT;
   static const string SESSION_SKIP_AFTER_OPEN;
   static const string SESSION_SKIP_BEFORE_CLOSE;

   //--- Indicators ----------------------------------------------------
   static const string INDICATOR_FAST_MA_PERIOD;
   static const string INDICATOR_SLOW_MA_PERIOD;
   static const string INDICATOR_TREND_MA_PERIOD;
   static const string INDICATOR_RSI_PERIOD;
   static const string INDICATOR_ATR_PERIOD;
   static const string INDICATOR_ADX_PERIOD;
   static const string INDICATOR_BOLLINGER_PERIOD;
   static const string INDICATOR_BOLLINGER_DEVIATION;

   //--- Dashboard -----------------------------------------------------
   static const string DASHBOARD_ENABLED;
   static const string DASHBOARD_THEME;
   static const string DASHBOARD_CORNER;
   static const string DASHBOARD_X_OFFSET;
   static const string DASHBOARD_Y_OFFSET;
   static const string DASHBOARD_REFRESH_MS;
   static const string DASHBOARD_SHOW_IN_TESTER;

   //--- Statistics and journal ----------------------------------------
   static const string STATS_JOURNAL_ENABLED;
   static const string STATS_JOURNAL_FILE;
   static const string STATS_PERSIST_STATE;
   //--- Where latched guard state is written between restarts.
   static const string STATS_STATE_FOLDER;

   //--- Optimisation ---------------------------------------------------
   static const string OPT_CRITERION;
   static const string OPT_MIN_TRADES;
   static const string OPT_MAX_DRAWDOWN_PENALTY;

   //=== ADDED IN THE PRODUCTION PHASE ================================
   //--- Phases 2-4 introduced whole subsystems that the original key
   //--- set predates. They are appended rather than reorganised so no
   //--- existing key name changes and nothing downstream breaks.

   //--- Intelligence: position sizing beyond the basic modes ----------
   static const string RISK_KELLY_FRACTION;
   static const string RISK_KELLY_MIN_TRADES;
   //--- Which capital figure a percentage model measures against.
   static const string RISK_CAPITAL_BASE;
   static const string RISK_AUTO_LOT_CAPITAL_PER_STEP;
   static const string RISK_AUTO_LOT_PER_STEP;
   static const string RISK_ATR_RISK_MULTIPLE;
   static const string RISK_WEEKLY_LOSS_PERCENT;
   static const string RISK_MONTHLY_LOSS_PERCENT;
   static const string RISK_PROFIT_LOCK_ENABLED;
   static const string RISK_PROFIT_LOCK_TRIGGER_PERCENT;
   static const string RISK_PROFIT_LOCK_KEEP_PERCENT;

   //--- Smart money concepts ------------------------------------------
   static const string SMC_ENABLED;
   static const string SMC_SWING_STRENGTH;
   static const string SMC_SWING_LOOKBACK;
   static const string SMC_ZONE_CAPACITY;
   static const string SMC_ZONE_MAX_AGE_BARS;
   static const string SMC_DISPLACEMENT_ATR_MULTIPLE;
   static const string SMC_MIN_GAP_POINTS;
   static const string SMC_REQUIRE_DISPLACEMENT;
   static const string SMC_EQUAL_TOLERANCE_ATR;
   static const string SMC_SWEEP_LOOKBACK_BARS;
   static const string SMC_STRUCTURE_BREAK_BUFFER;

   //--- Decision engine ----------------------------------------------
   static const string DECISION_VOTE_MODE;
   static const string DECISION_MIN_CONFIRMATIONS;
   static const string DECISION_MIN_CONFIDENCE;
   static const string DECISION_MAX_RISK_RATING;
   static const string STRATEGY_EMA_CROSS_ENABLED;
   static const string STRATEGY_VWAP_PULLBACK_ENABLED;
   static const string STRATEGY_LIQUIDITY_SWEEP_ENABLED;
   static const string STRATEGY_ORDER_BLOCK_ENABLED;
   static const string STRATEGY_FVG_ENABLED;
   static const string STRATEGY_OPENING_RANGE_ENABLED;
   static const string STRATEGY_TREND_CONTINUATION_ENABLED;

   //--- Sessions: kill zones and broker time -------------------------
   static const string SESSION_KILL_ZONES_ONLY;
   static const string SESSION_REQUIRE_OVERLAP;
   static const string SESSION_WEEKEND_FILTER;
   static const string SESSION_BROKER_GMT_OFFSET;
   static const string SESSION_DST_ADJUST;

   //--- Trade manager (Phase 4) --------------------------------------
   static const string TM_ATR_TRAIL_ENABLED;
   static const string TM_ATR_TRAIL_MULTIPLE;
   static const string TM_ATR_EXIT_ENABLED;
   static const string TM_ATR_EXIT_MULTIPLE;
   static const string TM_MAX_HOLD_ENABLED;
   static const string TM_MAX_HOLD_MINUTES;
   static const string TM_SCALE_IN_ENABLED;
   static const string TM_SCALE_IN_TRIGGER_POINTS;
   static const string TM_SCALE_IN_FRACTION;
   static const string TM_SCALE_IN_MAX;
   static const string TM_SCALE_OUT_ENABLED;
   static const string TM_SCALE_OUT_TRIGGER_POINTS;
   static const string TM_SCALE_OUT_FRACTION;
   static const string TM_SCALE_OUT_MAX;
   static const string TM_REVERSE_ENABLED;

   //--- Enterprise logging (Phase 4) ---------------------------------
   static const string LOG_FOLDER;
   static const string LOG_CHANNEL_ERRORS;
   static const string LOG_CHANNEL_TRADES;
   static const string LOG_CHANNEL_INDICATORS;
   static const string LOG_CHANNEL_RISK;
   static const string LOG_CHANNEL_PERFORMANCE;
   static const string LOG_CHANNEL_EXECUTION;
   static const string LOG_FORMAT_DEFAULT;
   static const string LOG_MIRROR_ERRORS_TO_JOURNAL;
   static const string LOG_FLUSH_EVERY;

   //--- Chart overlay (Phase 4) --------------------------------------
   static const string DRAW_OVERLAY_ENABLED;
   static const string DRAW_ENTRIES;
   static const string DRAW_STOPS;
   static const string DRAW_ZONES;
   static const string DRAW_LIQUIDITY;
   static const string DRAW_STRUCTURE;
   static const string DRAW_SESSION_BOXES;
   static const string DRAW_TRADE_LABELS;
   static const string DRAW_STATISTICS;
   static const string DRAW_MAX_ZONES;
   static const string DRAW_ZONE_EXTEND_BARS;

   //--- Analytics (Phase 4) ------------------------------------------
   static const string ANALYTICS_MIN_SAMPLE;
   static const string ANALYTICS_USE_R_MULTIPLES;
   static const string ANALYTICS_INITIAL_BALANCE;

   //--- Optimisation: walk-forward, Monte Carlo, export --------------
   static const string OPT_CONCENTRATION_PENALTY;
   static const string OPT_STREAK_PENALTY;
   static const string OPT_WALK_FORWARD_ENABLED;
   static const string OPT_WALK_FORWARD_IS_DAYS;
   static const string OPT_WALK_FORWARD_OOS_DAYS;
   static const string OPT_WALK_FORWARD_MIN_EFFICIENCY;
   static const string OPT_MONTE_CARLO_ENABLED;
   static const string OPT_MONTE_CARLO_RUNS;
   static const string OPT_MONTE_CARLO_SEED;
   static const string OPT_MONTE_CARLO_RUIN_PERCENT;
   static const string OPT_EXPORT_CSV;
   static const string OPT_EXPORT_FOLDER;
   static const string OPT_FORWARD_TEST_MODE;
   static const string OPT_REJECT_INCOHERENT;
  };

//--- Definitions. Namespaced with dots for readability in the log dump.
const string CConfigKeys::GENERAL_MAGIC                  = "general.magic";
const string CConfigKeys::GENERAL_ORDER_COMMENT          = "general.order_comment";
const string CConfigKeys::GENERAL_DIRECTION_MODE         = "general.direction_mode";
const string CConfigKeys::GENERAL_TICK_THROTTLE_MS       = "general.tick_throttle_ms";
const string CConfigKeys::GENERAL_TIMER_INTERVAL_MS      = "general.timer_interval_ms";
const string CConfigKeys::GENERAL_DATA_SEGMENT           = "general.data_segment";
const string CConfigKeys::GENERAL_PIN_SPREAD_SAMPLE      = "general.pin_spread_sample";

const string CConfigKeys::LOG_LEVEL                      = "log.level";
const string CConfigKeys::LOG_TO_FILE                    = "log.to_file";
const string CConfigKeys::LOG_TO_TERMINAL                = "log.to_terminal";
const string CConfigKeys::LOG_TO_ALERT                   = "log.to_alert";
const string CConfigKeys::LOG_TO_PUSH                    = "log.to_push";
const string CConfigKeys::LOG_DAILY_ROTATION             = "log.daily_rotation";

const string CConfigKeys::RISK_MODE                      = "risk.mode";
const string CConfigKeys::RISK_FIXED_LOT                 = "risk.fixed_lot";
const string CConfigKeys::RISK_FIXED_MONEY               = "risk.fixed_money";
const string CConfigKeys::RISK_PERCENT                   = "risk.percent";
const string CConfigKeys::RISK_MAX_LOT                   = "risk.max_lot";
const string CConfigKeys::RISK_MIN_LOT                   = "risk.min_lot";
const string CConfigKeys::RISK_MAX_POSITIONS             = "risk.max_positions";
const string CConfigKeys::RISK_MAX_POSITIONS_PER_DIRECTION = "risk.max_positions_per_direction";
const string CConfigKeys::RISK_MAX_TOTAL_VOLUME          = "risk.max_total_volume";
const string CConfigKeys::RISK_MAX_SPREAD_POINTS         = "risk.max_spread_points";
const string CConfigKeys::RISK_MAX_SLIPPAGE_POINTS       = "risk.max_slippage_points";
const string CConfigKeys::RISK_MIN_FREE_MARGIN_PERCENT   = "risk.min_free_margin_percent";
const string CConfigKeys::RISK_MAX_RISK_PERCENT_TOTAL    = "risk.max_risk_percent_total";

const string CConfigKeys::SL_MODE                        = "sl.mode";
const string CConfigKeys::SL_FIXED_POINTS                = "sl.fixed_points";
const string CConfigKeys::SL_ATR_MULTIPLIER              = "sl.atr_multiplier";
const string CConfigKeys::TP_MODE                        = "tp.mode";
const string CConfigKeys::TP_FIXED_POINTS                = "tp.fixed_points";
const string CConfigKeys::TP_ATR_MULTIPLIER              = "tp.atr_multiplier";
const string CConfigKeys::TP_RISK_REWARD                 = "tp.risk_reward";
const string CConfigKeys::TRAIL_MODE                     = "trail.mode";
const string CConfigKeys::TRAIL_START_POINTS             = "trail.start_points";
const string CConfigKeys::TRAIL_STEP_POINTS              = "trail.step_points";
const string CConfigKeys::TRAIL_DISTANCE_POINTS          = "trail.distance_points";
const string CConfigKeys::BREAKEVEN_ENABLED              = "breakeven.enabled";
const string CConfigKeys::BREAKEVEN_TRIGGER_POINTS       = "breakeven.trigger_points";
const string CConfigKeys::BREAKEVEN_OFFSET_POINTS        = "breakeven.offset_points";
const string CConfigKeys::PARTIAL_CLOSE_ENABLED          = "partial.enabled";
const string CConfigKeys::PARTIAL_CLOSE_TRIGGER_POINTS   = "partial.trigger_points";
const string CConfigKeys::PARTIAL_CLOSE_PERCENT          = "partial.percent";
const string CConfigKeys::TIME_STOP_ENABLED              = "timestop.enabled";
const string CConfigKeys::TIME_STOP_MINUTES              = "timestop.minutes";

const string CConfigKeys::GUARD_DAILY_PROFIT_ENABLED     = "guard.daily_profit_enabled";
const string CConfigKeys::GUARD_DAILY_PROFIT_PERCENT     = "guard.daily_profit_percent";
const string CConfigKeys::GUARD_DAILY_LOSS_ENABLED       = "guard.daily_loss_enabled";
const string CConfigKeys::GUARD_DAILY_LOSS_PERCENT       = "guard.daily_loss_percent";
const string CConfigKeys::GUARD_MAX_DRAWDOWN_ENABLED     = "guard.max_drawdown_enabled";
const string CConfigKeys::GUARD_MAX_DRAWDOWN_PERCENT     = "guard.max_drawdown_percent";
const string CConfigKeys::GUARD_EQUITY_FLOOR_ENABLED     = "guard.equity_floor_enabled";
const string CConfigKeys::GUARD_EQUITY_FLOOR_VALUE       = "guard.equity_floor_value";
const string CConfigKeys::GUARD_CONSECUTIVE_LOSS_LIMIT   = "guard.consecutive_loss_limit";
const string CConfigKeys::GUARD_FLATTEN_ON_TRIP          = "guard.flatten_on_trip";
const string CConfigKeys::GUARD_DAILY_LIMIT_TERMINAL     = "guard.daily_limit_terminal";
const string CConfigKeys::KILL_SWITCH_ENABLED            = "guard.kill_switch_enabled";

const string CConfigKeys::SESSION_FILTER_ENABLED         = "session.enabled";
const string CConfigKeys::SESSION_ALLOW_SYDNEY           = "session.allow_sydney";
const string CConfigKeys::SESSION_ALLOW_TOKYO            = "session.allow_tokyo";
const string CConfigKeys::SESSION_ALLOW_LONDON           = "session.allow_london";
const string CConfigKeys::SESSION_ALLOW_NEWYORK          = "session.allow_newyork";
const string CConfigKeys::SCHEDULE_ENABLED               = "schedule.enabled";
const string CConfigKeys::SCHEDULE_MONDAY_START          = "schedule.monday_start";
const string CConfigKeys::SCHEDULE_MONDAY_END            = "schedule.monday_end";
const string CConfigKeys::SCHEDULE_FRIDAY_CLOSE_MINUTES  = "schedule.friday_close_minutes";
const string CConfigKeys::HOLIDAY_FILTER_ENABLED         = "holiday.enabled";
const string CConfigKeys::HOLIDAY_LIST                   = "holiday.list";

const string CConfigKeys::NEWS_FILTER_ENABLED            = "news.enabled";
const string CConfigKeys::NEWS_SOURCE                    = "news.source";
const string CConfigKeys::NEWS_MIN_IMPACT                = "news.min_impact";
const string CConfigKeys::NEWS_MINUTES_BEFORE            = "news.minutes_before";
const string CConfigKeys::NEWS_MINUTES_AFTER             = "news.minutes_after";
const string CConfigKeys::NEWS_CLOSE_POSITIONS           = "news.close_positions";
const string CConfigKeys::NEWS_CSV_FILE                  = "news.csv_file";
const string CConfigKeys::NEWS_CURRENCY_FILTER           = "news.currency_filter";
const string CConfigKeys::NEWS_FAIL_SAFE_BLOCK           = "news.fail_safe_block";

const string CConfigKeys::FILTER_SPREAD_ENABLED          = "filter.spread_enabled";
const string CConfigKeys::FILTER_VOLATILITY_ENABLED      = "filter.volatility_enabled";
const string CConfigKeys::FILTER_VOLATILITY_MIN_ATR      = "filter.volatility_min_atr";
const string CConfigKeys::FILTER_VOLATILITY_MAX_ATR      = "filter.volatility_max_atr";
const string CConfigKeys::FILTER_TREND_ENABLED           = "filter.trend_enabled";
const string CConfigKeys::FILTER_TREND_TIMEFRAME         = "filter.trend_timeframe";
const string CConfigKeys::FILTER_FREQUENCY_ENABLED       = "filter.frequency_enabled";
const string CConfigKeys::FILTER_MIN_SECONDS_BETWEEN_TRADES = "filter.min_seconds_between_trades";
const string CConfigKeys::FILTER_MAX_TRADES_PER_DAY      = "filter.max_trades_per_day";
const string CConfigKeys::FILTER_MAX_TRADES_PER_HOUR     = "filter.max_trades_per_hour";

const string CConfigKeys::STRATEGY_AGGREGATION_MODE      = "strategy.aggregation_mode";
const string CConfigKeys::STRATEGY_MIN_CONFIDENCE        = "strategy.min_confidence";
const string CConfigKeys::STRATEGY_MOMENTUM_ENABLED      = "strategy.momentum_enabled";
const string CConfigKeys::STRATEGY_MOMENTUM_WEIGHT       = "strategy.momentum_weight";
const string CConfigKeys::STRATEGY_MEAN_REVERSION_ENABLED= "strategy.mean_reversion_enabled";
const string CConfigKeys::STRATEGY_MEAN_REVERSION_WEIGHT = "strategy.mean_reversion_weight";
const string CConfigKeys::STRATEGY_BREAKOUT_ENABLED      = "strategy.breakout_enabled";
const string CConfigKeys::STRATEGY_BREAKOUT_WEIGHT       = "strategy.breakout_weight";
const string CConfigKeys::DECISION_REQUIRE_CONFIRMATION  = "decision.require_confirmation";
const string CConfigKeys::STRATEGY_BOS_ENABLED           = "strategy.bos_enabled";
const string CConfigKeys::STRATEGY_BOS_WEIGHT            = "strategy.bos_weight";
const string CConfigKeys::STRATEGY_VOLATILITY_BREAKOUT_ENABLED = "strategy.volatility_breakout_enabled";
const string CConfigKeys::STRATEGY_VOLATILITY_BREAKOUT_WEIGHT  = "strategy.volatility_breakout_weight";
const string CConfigKeys::STRATEGY_ORDER_FLOW_ENABLED    = "strategy.order_flow_enabled";
const string CConfigKeys::STRATEGY_ORDER_FLOW_WEIGHT     = "strategy.order_flow_weight";
const string CConfigKeys::STRATEGY_ORDER_FLOW_MIN_VOLUME = "strategy.order_flow_min_volume";
const string CConfigKeys::SCALP_MODE_ENABLED             = "scalp.mode_enabled";
const string CConfigKeys::SCALP_COOLDOWN_SECONDS         = "scalp.cooldown_seconds";
const string CConfigKeys::SCALP_MAX_HOLD_SECONDS         = "scalp.max_hold_seconds";
const string CConfigKeys::SCALP_TARGET_ATR_MULTIPLE      = "scalp.target_atr_multiple";
const string CConfigKeys::SCALP_TARGET_MIN_POINTS        = "scalp.target_min_points";
const string CConfigKeys::SCALP_TARGET_MAX_POINTS        = "scalp.target_max_points";
const string CConfigKeys::SCALP_STOP_ATR_MULTIPLE        = "scalp.stop_atr_multiple";
const string CConfigKeys::SCALP_COMMISSION_POINTS        = "scalp.commission_points";
const string CConfigKeys::SCALP_EXECUTION_COST_POINTS    = "scalp.execution_cost_points";
const string CConfigKeys::SCALP_MIN_REWARD_COST_RATIO    = "scalp.min_reward_cost_ratio";
const string CConfigKeys::SCALP_MAX_SPREAD_TARGET_RATIO  = "scalp.max_spread_target_ratio";
const string CConfigKeys::SCALP_EARLY_EXIT_ENABLED       = "scalp.early_exit_enabled";
const string CConfigKeys::SCALP_EARLY_EXIT_MIN_POINTS    = "scalp.early_exit_min_points";
const string CConfigKeys::SCALP_EARLY_EXIT_TARGET_SHARE  = "scalp.early_exit_target_share";
const string CConfigKeys::SCALP_ATR_MIN_POINTS           = "scalp.atr_min_points";
const string CConfigKeys::SCALP_ATR_MAX_POINTS           = "scalp.atr_max_points";

const string CConfigKeys::ACCURACY_FILTER_ENABLED        = "accuracy.filter_enabled";
const string CConfigKeys::ACCURACY_REQUIRE_SETUP         = "accuracy.require_setup";
const string CConfigKeys::ACCURACY_REQUIRE_CONTEXT       = "accuracy.require_context";
const string CConfigKeys::ACCURACY_MIN_RELATIVE_VOLUME   = "accuracy.min_relative_volume";
const string CConfigKeys::ACCURACY_VOLUME_LOOKBACK       = "accuracy.volume_lookback";
const string CConfigKeys::ACCURACY_MAX_EXTENSION         = "accuracy.max_extension";
const string CConfigKeys::ACCURACY_MIN_SCORE             = "accuracy.min_score";
const string CConfigKeys::TIER_ENABLED_PREFIX            = "tier.enabled.";
const string CConfigKeys::TIER_TARGET_ATR_PREFIX         = "tier.target_atr.";
const string CConfigKeys::TIER_STOP_ATR_PREFIX           = "tier.stop_atr.";
const string CConfigKeys::TIER_HOLD_SECONDS_PREFIX       = "tier.hold_seconds.";
const string CConfigKeys::TIER_WIN_RATE_PREFIX           = "tier.win_rate.";
const string CConfigKeys::TIER_TIMEFRAME_PREFIX          = "tier.timeframe.";
const string CConfigKeys::GENERAL_CONTEXT_TIMEFRAME      = "general.context_timeframe";
const string CConfigKeys::GENERAL_SETUP_TIMEFRAME        = "general.setup_timeframe";
const string CConfigKeys::SESSION_LONDON_OPEN_GMT        = "session.london_open_gmt";
const string CConfigKeys::SESSION_LONDON_CLOSE_GMT       = "session.london_close_gmt";
const string CConfigKeys::SESSION_NEWYORK_OPEN_GMT       = "session.newyork_open_gmt";
const string CConfigKeys::SESSION_NEWYORK_CLOSE_GMT      = "session.newyork_close_gmt";
const string CConfigKeys::SESSION_PRIMARY_KZ_OPEN_GMT    = "session.primary_kz_open_gmt";
const string CConfigKeys::SESSION_PRIMARY_KZ_CLOSE_GMT   = "session.primary_kz_close_gmt";
const string CConfigKeys::SESSION_SKIP_AFTER_OPEN        = "session.skip_after_open_minutes";
const string CConfigKeys::SESSION_SKIP_BEFORE_CLOSE      = "session.skip_before_close_minutes";

const string CConfigKeys::INDICATOR_FAST_MA_PERIOD       = "indicator.fast_ma_period";
const string CConfigKeys::INDICATOR_SLOW_MA_PERIOD       = "indicator.slow_ma_period";
const string CConfigKeys::INDICATOR_TREND_MA_PERIOD      = "indicator.trend_ma_period";
const string CConfigKeys::INDICATOR_RSI_PERIOD           = "indicator.rsi_period";
const string CConfigKeys::INDICATOR_ATR_PERIOD           = "indicator.atr_period";
const string CConfigKeys::INDICATOR_ADX_PERIOD           = "indicator.adx_period";
const string CConfigKeys::INDICATOR_BOLLINGER_PERIOD     = "indicator.bollinger_period";
const string CConfigKeys::INDICATOR_BOLLINGER_DEVIATION  = "indicator.bollinger_deviation";

const string CConfigKeys::DASHBOARD_ENABLED              = "dashboard.enabled";
const string CConfigKeys::DASHBOARD_THEME                = "dashboard.theme";
const string CConfigKeys::DASHBOARD_CORNER               = "dashboard.corner";
const string CConfigKeys::DASHBOARD_X_OFFSET             = "dashboard.x_offset";
const string CConfigKeys::DASHBOARD_Y_OFFSET             = "dashboard.y_offset";
const string CConfigKeys::DASHBOARD_REFRESH_MS           = "dashboard.refresh_ms";
const string CConfigKeys::DASHBOARD_SHOW_IN_TESTER       = "dashboard.show_in_tester";

const string CConfigKeys::STATS_JOURNAL_ENABLED          = "stats.journal_enabled";
const string CConfigKeys::STATS_JOURNAL_FILE             = "stats.journal_file";
const string CConfigKeys::STATS_PERSIST_STATE            = "stats.persist_state";
const string CConfigKeys::STATS_STATE_FOLDER             = "stats.state_folder";

const string CConfigKeys::OPT_CRITERION                  = "opt.criterion";
const string CConfigKeys::OPT_MIN_TRADES                 = "opt.min_trades";
const string CConfigKeys::OPT_MAX_DRAWDOWN_PENALTY       = "opt.max_drawdown_penalty";

//=== ADDED IN THE PRODUCTION PHASE ==================================
const string CConfigKeys::RISK_KELLY_FRACTION            = "risk.kelly_fraction";
const string CConfigKeys::RISK_KELLY_MIN_TRADES          = "risk.kelly_min_trades";
const string CConfigKeys::RISK_CAPITAL_BASE              = "risk.capital_base";
const string CConfigKeys::RISK_AUTO_LOT_CAPITAL_PER_STEP = "risk.auto_lot_capital_per_step";
const string CConfigKeys::RISK_AUTO_LOT_PER_STEP         = "risk.auto_lot_per_step";
const string CConfigKeys::RISK_ATR_RISK_MULTIPLE         = "risk.atr_risk_multiple";
const string CConfigKeys::RISK_WEEKLY_LOSS_PERCENT       = "risk.weekly_loss_percent";
const string CConfigKeys::RISK_MONTHLY_LOSS_PERCENT      = "risk.monthly_loss_percent";
const string CConfigKeys::RISK_PROFIT_LOCK_ENABLED       = "risk.profit_lock_enabled";
const string CConfigKeys::RISK_PROFIT_LOCK_TRIGGER_PERCENT = "risk.profit_lock_trigger_percent";
const string CConfigKeys::RISK_PROFIT_LOCK_KEEP_PERCENT  = "risk.profit_lock_keep_percent";

const string CConfigKeys::SMC_ENABLED                    = "smc.enabled";
const string CConfigKeys::SMC_SWING_STRENGTH             = "smc.swing_strength";
const string CConfigKeys::SMC_SWING_LOOKBACK             = "smc.swing_lookback";
const string CConfigKeys::SMC_ZONE_CAPACITY              = "smc.zone_capacity";
const string CConfigKeys::SMC_ZONE_MAX_AGE_BARS          = "smc.zone_max_age_bars";
const string CConfigKeys::SMC_DISPLACEMENT_ATR_MULTIPLE  = "smc.displacement_atr_multiple";
const string CConfigKeys::SMC_MIN_GAP_POINTS             = "smc.min_gap_points";
const string CConfigKeys::SMC_REQUIRE_DISPLACEMENT       = "smc.require_displacement";
const string CConfigKeys::SMC_EQUAL_TOLERANCE_ATR        = "smc.equal_tolerance_atr";
const string CConfigKeys::SMC_SWEEP_LOOKBACK_BARS        = "smc.sweep_lookback_bars";
const string CConfigKeys::SMC_STRUCTURE_BREAK_BUFFER     = "smc.structure_break_buffer";

const string CConfigKeys::DECISION_VOTE_MODE             = "decision.vote_mode";
const string CConfigKeys::DECISION_MIN_CONFIRMATIONS     = "decision.min_confirmations";
const string CConfigKeys::DECISION_MIN_CONFIDENCE        = "decision.min_confidence";
const string CConfigKeys::DECISION_MAX_RISK_RATING       = "decision.max_risk_rating";
const string CConfigKeys::STRATEGY_EMA_CROSS_ENABLED     = "strategy.ema_cross_enabled";
const string CConfigKeys::STRATEGY_VWAP_PULLBACK_ENABLED = "strategy.vwap_pullback_enabled";
const string CConfigKeys::STRATEGY_LIQUIDITY_SWEEP_ENABLED = "strategy.liquidity_sweep_enabled";
const string CConfigKeys::STRATEGY_ORDER_BLOCK_ENABLED   = "strategy.order_block_enabled";
const string CConfigKeys::STRATEGY_FVG_ENABLED           = "strategy.fvg_enabled";
const string CConfigKeys::STRATEGY_OPENING_RANGE_ENABLED = "strategy.opening_range_enabled";
const string CConfigKeys::STRATEGY_TREND_CONTINUATION_ENABLED = "strategy.trend_continuation_enabled";

const string CConfigKeys::SESSION_KILL_ZONES_ONLY        = "session.kill_zones_only";
const string CConfigKeys::SESSION_REQUIRE_OVERLAP        = "session.require_overlap";
const string CConfigKeys::SESSION_WEEKEND_FILTER         = "session.weekend_filter";
const string CConfigKeys::SESSION_BROKER_GMT_OFFSET      = "session.broker_gmt_offset";
const string CConfigKeys::SESSION_DST_ADJUST             = "session.dst_adjust";

const string CConfigKeys::TM_ATR_TRAIL_ENABLED           = "tm.atr_trail_enabled";
const string CConfigKeys::TM_ATR_TRAIL_MULTIPLE          = "tm.atr_trail_multiple";
const string CConfigKeys::TM_ATR_EXIT_ENABLED            = "tm.atr_exit_enabled";
const string CConfigKeys::TM_ATR_EXIT_MULTIPLE           = "tm.atr_exit_multiple";
const string CConfigKeys::TM_MAX_HOLD_ENABLED            = "tm.max_hold_enabled";
const string CConfigKeys::TM_MAX_HOLD_MINUTES            = "tm.max_hold_minutes";
const string CConfigKeys::TM_SCALE_IN_ENABLED            = "tm.scale_in_enabled";
const string CConfigKeys::TM_SCALE_IN_TRIGGER_POINTS     = "tm.scale_in_trigger_points";
const string CConfigKeys::TM_SCALE_IN_FRACTION           = "tm.scale_in_fraction";
const string CConfigKeys::TM_SCALE_IN_MAX                = "tm.scale_in_max";
const string CConfigKeys::TM_SCALE_OUT_ENABLED           = "tm.scale_out_enabled";
const string CConfigKeys::TM_SCALE_OUT_TRIGGER_POINTS    = "tm.scale_out_trigger_points";
const string CConfigKeys::TM_SCALE_OUT_FRACTION          = "tm.scale_out_fraction";
const string CConfigKeys::TM_SCALE_OUT_MAX               = "tm.scale_out_max";
const string CConfigKeys::TM_REVERSE_ENABLED             = "tm.reverse_enabled";

const string CConfigKeys::LOG_FOLDER                     = "log.folder";
const string CConfigKeys::LOG_CHANNEL_ERRORS             = "log.channel_errors";
const string CConfigKeys::LOG_CHANNEL_TRADES             = "log.channel_trades";
const string CConfigKeys::LOG_CHANNEL_INDICATORS         = "log.channel_indicators";
const string CConfigKeys::LOG_CHANNEL_RISK               = "log.channel_risk";
const string CConfigKeys::LOG_CHANNEL_PERFORMANCE        = "log.channel_performance";
const string CConfigKeys::LOG_CHANNEL_EXECUTION          = "log.channel_execution";
const string CConfigKeys::LOG_FORMAT_DEFAULT             = "log.format_default";
const string CConfigKeys::LOG_MIRROR_ERRORS_TO_JOURNAL   = "log.mirror_errors_to_journal";
const string CConfigKeys::LOG_FLUSH_EVERY                = "log.flush_every";

const string CConfigKeys::DRAW_OVERLAY_ENABLED           = "draw.overlay_enabled";
const string CConfigKeys::DRAW_ENTRIES                   = "draw.entries";
const string CConfigKeys::DRAW_STOPS                     = "draw.stops";
const string CConfigKeys::DRAW_ZONES                     = "draw.zones";
const string CConfigKeys::DRAW_LIQUIDITY                 = "draw.liquidity";
const string CConfigKeys::DRAW_STRUCTURE                 = "draw.structure";
const string CConfigKeys::DRAW_SESSION_BOXES             = "draw.session_boxes";
const string CConfigKeys::DRAW_TRADE_LABELS              = "draw.trade_labels";
const string CConfigKeys::DRAW_STATISTICS                = "draw.statistics";
const string CConfigKeys::DRAW_MAX_ZONES                 = "draw.max_zones";
const string CConfigKeys::DRAW_ZONE_EXTEND_BARS          = "draw.zone_extend_bars";

const string CConfigKeys::ANALYTICS_MIN_SAMPLE           = "analytics.min_sample";
const string CConfigKeys::ANALYTICS_USE_R_MULTIPLES      = "analytics.use_r_multiples";
const string CConfigKeys::ANALYTICS_INITIAL_BALANCE      = "analytics.initial_balance";

const string CConfigKeys::OPT_CONCENTRATION_PENALTY      = "opt.concentration_penalty";
const string CConfigKeys::OPT_STREAK_PENALTY             = "opt.streak_penalty";
const string CConfigKeys::OPT_WALK_FORWARD_ENABLED       = "opt.walk_forward_enabled";
const string CConfigKeys::OPT_WALK_FORWARD_IS_DAYS       = "opt.walk_forward_is_days";
const string CConfigKeys::OPT_WALK_FORWARD_OOS_DAYS      = "opt.walk_forward_oos_days";
const string CConfigKeys::OPT_WALK_FORWARD_MIN_EFFICIENCY= "opt.walk_forward_min_efficiency";
const string CConfigKeys::OPT_MONTE_CARLO_ENABLED        = "opt.monte_carlo_enabled";
const string CConfigKeys::OPT_MONTE_CARLO_RUNS           = "opt.monte_carlo_runs";
const string CConfigKeys::OPT_MONTE_CARLO_SEED           = "opt.monte_carlo_seed";
const string CConfigKeys::OPT_MONTE_CARLO_RUIN_PERCENT   = "opt.monte_carlo_ruin_percent";
const string CConfigKeys::OPT_EXPORT_CSV                 = "opt.export_csv";
const string CConfigKeys::OPT_EXPORT_FOLDER              = "opt.export_folder";
const string CConfigKeys::OPT_FORWARD_TEST_MODE          = "opt.forward_test_mode";
const string CConfigKeys::OPT_REJECT_INCOHERENT          = "opt.reject_incoherent";

#endif // SRP_CONFIGURATION_CCONFIGKEYS_MQH
//+------------------------------------------------------------------+
