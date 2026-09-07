//+------------------------------------------------------------------+
//|                                           InterfaceEnums.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   Shared vocabulary for Phase 4. Separate from Phases 1-3 so none of   |
//|   them is modified. All enumerators carry an SRP_UI_ / SRP_TM_ /        |
//|   SRP_LOG4_ / SRP_PA_ prefix because MQL5 places enum members in the    |
//|   GLOBAL namespace - three prior phases already claimed the obvious     |
//|   names, and a redefinition is a hard compile error.                   |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_TYPES_ENUMS_MQH
#define SRP_INTERFACE_TYPES_ENUMS_MQH

//=== DASHBOARD =====================================================
//--- Every metric the panel can display. One enum so a row is declared
//--- by identity rather than by index.
enum ENUM_SRP_UI_METRIC
  {
   SRP_UI_BALANCE,
   SRP_UI_EQUITY,
   SRP_UI_MARGIN,
   SRP_UI_FLOATING_PROFIT,
   SRP_UI_TODAY_PROFIT,
   SRP_UI_WEEK_PROFIT,
   SRP_UI_MONTH_PROFIT,
   SRP_UI_WIN_RATE,
   SRP_UI_PROFIT_FACTOR,
   SRP_UI_AVERAGE_RR,
   SRP_UI_SPREAD,
   SRP_UI_LATENCY,
   SRP_UI_SESSION,
   SRP_UI_NEWS_COUNTDOWN,
   SRP_UI_STRATEGY,
   SRP_UI_OPEN_TRADES,
   SRP_UI_RISK_PERCENT,
   SRP_UI_LOT_SIZE
  };

//--- Semantic colour intent. Widgets express MEANING and the theme
//--- decides appearance, so a light variant is a config change.
enum ENUM_SRP_UI_TONE
  {
   SRP_UI_TONE_NEUTRAL,
   SRP_UI_TONE_POSITIVE,
   SRP_UI_TONE_NEGATIVE,
   SRP_UI_TONE_WARNING,
   SRP_UI_TONE_CRITICAL,
   SRP_UI_TONE_ACCENT,
   SRP_UI_TONE_MUTED
  };

enum ENUM_SRP_UI_THEME
  {
   SRP_UI_THEME_DARK,
   SRP_UI_THEME_LIGHT,
   SRP_UI_THEME_CONTRAST
  };

//=== CHART OBJECTS =================================================
//--- Every drawable overlay kind. Grouped so visibility can be toggled
//--- per category rather than per object.
enum ENUM_SRP_DRAW_LAYER
  {
   SRP_DRAW_ENTRIES,
   SRP_DRAW_STOP_LOSS,
   SRP_DRAW_TAKE_PROFIT,
   SRP_DRAW_TRAILING_STOP,
   SRP_DRAW_ORDER_BLOCKS,
   SRP_DRAW_FAIR_VALUE_GAPS,
   SRP_DRAW_LIQUIDITY,
   SRP_DRAW_BOS,
   SRP_DRAW_CHOCH,
   SRP_DRAW_SUPPORT,
   SRP_DRAW_RESISTANCE,
   SRP_DRAW_TREND_LINES,
   SRP_DRAW_SESSION_BOXES,
   SRP_DRAW_TRADE_LABELS,
   SRP_DRAW_STATISTICS
  };

//=== TRADE MANAGER =================================================
//--- What the manager wants done to an open position. Returned as an
//--- intent; execution belongs to the Phase 1 trade engine.
enum ENUM_SRP_TM_ACTION
  {
   SRP_TM_NONE,
   SRP_TM_MOVE_STOP,          // break-even, trailing, ATR trail
   SRP_TM_SCALE_IN,           // add to a winning position
   SRP_TM_SCALE_OUT,          // partial close
   SRP_TM_CLOSE_FULL,
   SRP_TM_REVERSE
  };

//--- Why the manager acted. Recorded on the journal line so a support
//--- ticket can be answered from the log alone.
enum ENUM_SRP_TM_TRIGGER
  {
   SRP_TM_TRIGGER_NONE,
   SRP_TM_TRIGGER_BREAK_EVEN,
   SRP_TM_TRIGGER_TRAILING,
   SRP_TM_TRIGGER_ATR_TRAIL,
   SRP_TM_TRIGGER_ATR_EXIT,
   SRP_TM_TRIGGER_TIME_EXIT,
   SRP_TM_TRIGGER_MAX_HOLD,
   SRP_TM_TRIGGER_EMERGENCY,
   SRP_TM_TRIGGER_SCALE_IN,
   SRP_TM_TRIGGER_SCALE_OUT,
   SRP_TM_TRIGGER_REVERSAL,
   //--- APPENDED in the ultra-scalp phase. Never inserted: these ids
   //--- reach the journal, so renumbering re-attributes history.
   //--- Momentum faded while already in profit above the cost floor.
   SRP_TM_TRIGGER_EARLY_PROFIT,
   //--- Scalp holding window elapsed without the move developing.
   SRP_TM_TRIGGER_SCALP_TIMEOUT
  };

//=== ENTERPRISE LOGGING ============================================
//--- Log channels. Separating them means a risk audit is not buried
//--- under indicator noise, and each can be routed independently.
enum ENUM_SRP_LOG4_CHANNEL
  {
   SRP_LOG4_ERRORS,
   SRP_LOG4_TRADES,
   SRP_LOG4_INDICATORS,
   SRP_LOG4_RISK_EVENTS,
   SRP_LOG4_PERFORMANCE,
   SRP_LOG4_EXECUTION_TIME
  };

enum ENUM_SRP_LOG4_FORMAT
  {
   SRP_LOG4_FORMAT_CSV,       // spreadsheet-ready
   SRP_LOG4_FORMAT_TXT,       // human-readable
   SRP_LOG4_FORMAT_JOURNAL    // narrative trade journal
  };

//=== PERFORMANCE ANALYTICS =========================================
enum ENUM_SRP_PA_PERIOD
  {
   SRP_PA_PERIOD_ALL,
   SRP_PA_PERIOD_DAY,
   SRP_PA_PERIOD_WEEK,
   SRP_PA_PERIOD_MONTH,
   SRP_PA_PERIOD_YEAR
  };

#endif // SRP_INTERFACE_TYPES_ENUMS_MQH
//+------------------------------------------------------------------+
