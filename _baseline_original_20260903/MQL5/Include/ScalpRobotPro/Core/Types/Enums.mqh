//+------------------------------------------------------------------+
//|                                                        Enums.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Types : the shared vocabulary of the entire system.       |
//|   Every enumerator is SRP_-prefixed because MQL5 places enum     |
//|   members in the global namespace.                               |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_TYPES_ENUMS_MQH
#define SRP_CORE_TYPES_ENUMS_MQH

//--- Directional intent produced by strategies ----------------------
enum ENUM_SRP_SIGNAL_DIRECTION
  {
   SRP_SIGNAL_NONE  =  0,
   SRP_SIGNAL_BUY   =  1,
   SRP_SIGNAL_SELL  = -1
  };

//--- User-selectable trade direction permission ---------------------
enum ENUM_SRP_DIRECTION_MODE
  {
   SRP_DIRECTION_BOTH,
   SRP_DIRECTION_BUY_ONLY,
   SRP_DIRECTION_SELL_ONLY,
   SRP_DIRECTION_DISABLED
  };

//--- Engine lifecycle state machine ---------------------------------
enum ENUM_SRP_ENGINE_STATE
  {
   SRP_STATE_CREATED,          // constructed, not initialised
   SRP_STATE_INITIALIZING,     // bootstrapper wiring the graph
   SRP_STATE_READY,            // initialised, awaiting first tick
   SRP_STATE_TRADING,          // full pipeline active
   SRP_STATE_MANAGING_ONLY,    // no new entries, manage open trades
   SRP_STATE_PAUSED,           // temporarily suspended by a guard
   SRP_STATE_HALTED,           // terminal stop (kill switch)
   SRP_STATE_SHUTDOWN          // deinitialised
  };

//--- Logging ---------------------------------------------------------
enum ENUM_SRP_LOG_LEVEL
  {
   SRP_LOG_TRACE,
   SRP_LOG_DEBUG,
   SRP_LOG_INFO,
   SRP_LOG_WARN,
   SRP_LOG_ERROR,
   SRP_LOG_FATAL,
   SRP_LOG_OFF
  };

enum ENUM_SRP_LOG_SINK_KIND
  {
   SRP_SINK_TERMINAL,
   SRP_SINK_FILE,
   SRP_SINK_ALERT,
   SRP_SINK_PUSH,
   SRP_SINK_CHART_COMMENT
  };

//--- Position sizing model ------------------------------------------
enum ENUM_SRP_RISK_MODE
  {
   SRP_RISK_FIXED_LOT,
   SRP_RISK_FIXED_MONEY,
   SRP_RISK_PERCENT_BALANCE,
   SRP_RISK_PERCENT_EQUITY,
   SRP_RISK_VOLATILITY_SCALED,
   SRP_RISK_RECOVERY_SEQUENCE
  };

//--- Protective price level models ----------------------------------
enum ENUM_SRP_SL_MODE
  {
   SRP_SL_NONE,
   SRP_SL_FIXED_POINTS,
   SRP_SL_ATR_MULTIPLE,
   SRP_SL_MARKET_STRUCTURE
  };

enum ENUM_SRP_TP_MODE
  {
   SRP_TP_NONE,
   SRP_TP_FIXED_POINTS,
   SRP_TP_ATR_MULTIPLE,
   SRP_TP_RISK_REWARD
  };

enum ENUM_SRP_TRAIL_MODE
  {
   SRP_TRAIL_DISABLED,
   SRP_TRAIL_FIXED_STEP,
   SRP_TRAIL_ATR_STEP,
   SRP_TRAIL_PROFIT_PERCENT
  };

//--- Why a candidate trade was refused ------------------------------
enum ENUM_SRP_VETO_REASON
  {
   SRP_VETO_NONE,
   SRP_VETO_SPREAD,
   SRP_VETO_SESSION,
   SRP_VETO_SCHEDULE,
   SRP_VETO_HOLIDAY,
   SRP_VETO_NEWS,
   SRP_VETO_VOLATILITY,
   SRP_VETO_TREND,
   SRP_VETO_LIQUIDITY,
   SRP_VETO_FREQUENCY,
   SRP_VETO_DIRECTION,
   SRP_VETO_EXPOSURE,
   SRP_VETO_DRAWDOWN,
   SRP_VETO_DAILY_TARGET,
   SRP_VETO_MARGIN,
   SRP_VETO_SLIPPAGE,
   SRP_VETO_CIRCUIT_BREAKER,
   SRP_VETO_KILL_SWITCH,
   SRP_VETO_NO_SIGNAL,
   SRP_VETO_CONFIGURATION,
   SRP_VETO_MARKET_CLOSED
  };

//--- Filter taxonomy (used for dashboard grouping and diagnostics) --
enum ENUM_SRP_FILTER_CATEGORY
  {
   SRP_FILTER_CATEGORY_MARKET,
   SRP_FILTER_CATEGORY_TIME,
   SRP_FILTER_CATEGORY_NEWS,
   SRP_FILTER_CATEGORY_RISK,
   SRP_FILTER_CATEGORY_TECHNICAL,
   SRP_FILTER_CATEGORY_ACCOUNT
  };

//--- News -----------------------------------------------------------
enum ENUM_SRP_NEWS_IMPACT
  {
   SRP_NEWS_IMPACT_NONE,
   SRP_NEWS_IMPACT_LOW,
   SRP_NEWS_IMPACT_MEDIUM,
   SRP_NEWS_IMPACT_HIGH
  };

enum ENUM_SRP_NEWS_SOURCE
  {
   SRP_NEWS_SOURCE_DISABLED,
   SRP_NEWS_SOURCE_TERMINAL_CALENDAR,
   SRP_NEWS_SOURCE_CSV_FILE
  };

//--- Trading sessions ------------------------------------------------
enum ENUM_SRP_SESSION
  {
   SRP_SESSION_OFF_HOURS,
   SRP_SESSION_SYDNEY,
   SRP_SESSION_TOKYO,
   SRP_SESSION_LONDON,
   SRP_SESSION_NEWYORK,
   SRP_SESSION_LONDON_NY_OVERLAP
  };

//--- Market regime classification -----------------------------------
enum ENUM_SRP_TREND_STATE
  {
   SRP_TREND_UNDEFINED,
   SRP_TREND_UP,
   SRP_TREND_DOWN,
   SRP_TREND_RANGING
  };

enum ENUM_SRP_VOLATILITY_STATE
  {
   SRP_VOLATILITY_UNDEFINED,
   SRP_VOLATILITY_LOW,
   SRP_VOLATILITY_NORMAL,
   SRP_VOLATILITY_HIGH,
   SRP_VOLATILITY_EXTREME
  };

//--- How multiple strategy opinions collapse into one decision ------
enum ENUM_SRP_AGGREGATION_MODE
  {
   SRP_AGGREGATION_FIRST_MATCH,
   SRP_AGGREGATION_MAJORITY_VOTE,
   SRP_AGGREGATION_WEIGHTED_SCORE,
   SRP_AGGREGATION_UNANIMOUS
  };

//--- Strategy identity ----------------------------------------------
enum ENUM_SRP_STRATEGY_ID
  {
   SRP_STRATEGY_MOMENTUM,
   SRP_STRATEGY_MEAN_REVERSION,
   SRP_STRATEGY_BREAKOUT,
   SRP_STRATEGY_VOLATILITY_EXPANSION,
   SRP_STRATEGY_GRID_RECOVERY
  };

//--- Indicator identity (registry keys for the indicator manager) ---
enum ENUM_SRP_INDICATOR_ID
  {
   SRP_INDICATOR_FAST_MA,
   SRP_INDICATOR_SLOW_MA,
   SRP_INDICATOR_TREND_MA,
   SRP_INDICATOR_RSI,
   SRP_INDICATOR_ATR,
   SRP_INDICATOR_BOLLINGER,
   SRP_INDICATOR_MACD,
   SRP_INDICATOR_STOCHASTIC,
   SRP_INDICATOR_ADX,
   SRP_INDICATOR_VWAP
  };

//--- Position close attribution -------------------------------------
enum ENUM_SRP_EXIT_REASON
  {
   SRP_EXIT_UNKNOWN,
   SRP_EXIT_TAKE_PROFIT,
   SRP_EXIT_STOP_LOSS,
   SRP_EXIT_TRAILING_STOP,
   SRP_EXIT_BREAK_EVEN,
   SRP_EXIT_PARTIAL_CLOSE,
   SRP_EXIT_STRATEGY_SIGNAL,
   SRP_EXIT_TIME_STOP,
   SRP_EXIT_NEWS_BLACKOUT,
   SRP_EXIT_RISK_GUARD,
   SRP_EXIT_KILL_SWITCH,
   SRP_EXIT_MANUAL
  };

//--- Event bus topics -----------------------------------------------
enum ENUM_SRP_EVENT
  {
   SRP_EVENT_ENGINE_INITIALIZED,
   SRP_EVENT_ENGINE_STATE_CHANGED,
   SRP_EVENT_ENGINE_SHUTDOWN,
   SRP_EVENT_CONFIG_VALIDATED,
   SRP_EVENT_NEW_BAR,
   SRP_EVENT_MARKET_SNAPSHOT_READY,
   SRP_EVENT_SIGNAL_GENERATED,
   SRP_EVENT_SIGNAL_VETOED,
   SRP_EVENT_RISK_REJECTED,
   SRP_EVENT_ORDER_SUBMITTED,
   SRP_EVENT_ORDER_REJECTED,
   SRP_EVENT_POSITION_OPENED,
   SRP_EVENT_POSITION_MODIFIED,
   SRP_EVENT_POSITION_PARTIALLY_CLOSED,
   SRP_EVENT_POSITION_CLOSED,
   SRP_EVENT_STOP_LEVEL_UPDATED,
   SRP_EVENT_DRAWDOWN_LIMIT_REACHED,
   SRP_EVENT_DAILY_TARGET_REACHED,
   SRP_EVENT_NEWS_BLACKOUT_STARTED,
   SRP_EVENT_NEWS_BLACKOUT_ENDED,
   SRP_EVENT_CIRCUIT_BREAKER_TRIPPED,
   SRP_EVENT_KILL_SWITCH_ACTIVATED,
   SRP_EVENT_STATISTICS_UPDATED,
   SRP_EVENT_HEALTH_DEGRADED,
   SRP_EVENT_ERROR_RAISED,
   SRP_EVENT_HEARTBEAT
  };

//--- Health -----------------------------------------------------------
enum ENUM_SRP_HEALTH_STATUS
  {
   SRP_HEALTH_OK,
   SRP_HEALTH_DEGRADED,
   SRP_HEALTH_CRITICAL
  };

//--- Dashboard ------------------------------------------------------
enum ENUM_SRP_THEME
  {
   SRP_THEME_DARK,
   SRP_THEME_LIGHT,
   SRP_THEME_HIGH_CONTRAST
  };

enum ENUM_SRP_WIDGET_ID
  {
   SRP_WIDGET_HEADER,
   SRP_WIDGET_ACCOUNT,
   SRP_WIDGET_SIGNAL,
   SRP_WIDGET_POSITIONS,
   SRP_WIDGET_RISK,
   SRP_WIDGET_FILTERS,
   SRP_WIDGET_NEWS,
   SRP_WIDGET_STATISTICS,
   SRP_WIDGET_EQUITY_CURVE,
   SRP_WIDGET_FOOTER
  };

//--- Optimisation ----------------------------------------------------
enum ENUM_SRP_OPTIMIZATION_CRITERION
  {
   SRP_CRITERION_NET_PROFIT,
   SRP_CRITERION_PROFIT_FACTOR,
   SRP_CRITERION_EXPECTANCY,
   SRP_CRITERION_SHARPE_RATIO,
   SRP_CRITERION_RECOVERY_FACTOR,
   SRP_CRITERION_CUSTOM_COMPOSITE
  };

//--- Error handling policy ------------------------------------------
enum ENUM_SRP_ERROR_ACTION
  {
   SRP_ERROR_ACTION_IGNORE,
   SRP_ERROR_ACTION_RETRY,
   SRP_ERROR_ACTION_SKIP_TICK,
   SRP_ERROR_ACTION_PAUSE,
   SRP_ERROR_ACTION_HALT
  };

#endif // SRP_CORE_TYPES_ENUMS_MQH
//+------------------------------------------------------------------+
