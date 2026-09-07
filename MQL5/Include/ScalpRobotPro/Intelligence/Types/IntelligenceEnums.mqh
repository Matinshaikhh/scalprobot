//+------------------------------------------------------------------+
//|                                        IntelligenceEnums.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   Shared vocabulary for Phase 2. Kept separate from                |
//|   Core/Types/Enums.mqh so Phase 1 is untouched.                    |
//|   All enumerators are SRP_-prefixed: MQL5 places enum members in    |
//|   the global namespace.                                            |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_TYPES_ENUMS_MQH
#define SRP_INTELLIGENCE_TYPES_ENUMS_MQH

//=== RISK ==========================================================
//--- Position sizing models. Extends the Phase 1 ENUM_SRP_RISK_MODE
//--- rather than replacing it, so Phase 1 keeps compiling.
enum ENUM_SRP_SIZING_MODEL
  {
   SRP_SIZING_FIXED_LOT,          // constant volume
   SRP_SIZING_RISK_PERCENT,       // % of balance/equity at risk
   SRP_SIZING_AUTO_LOT,           // lot per N currency of equity
   SRP_SIZING_KELLY,              // Kelly criterion from realised edge
   SRP_SIZING_ATR,                // volatility-normalised
   SRP_SIZING_DYNAMIC             // performance-adaptive
  };

//--- Capital reference for percentage models.
enum ENUM_SRP_CAPITAL_BASE
  {
   SRP_CAPITAL_BALANCE,
   SRP_CAPITAL_EQUITY,
   SRP_CAPITAL_FREE_MARGIN,
   SRP_CAPITAL_HIGH_WATER_MARK    // most conservative: peak equity
  };

//--- Which limit tripped. Ordered by escalating severity.
enum ENUM_SRP_LIMIT_BREACH
  {
   SRP_BREACH_NONE,
   SRP_BREACH_DAILY_LOSS,
   SRP_BREACH_WEEKLY_LOSS,
   SRP_BREACH_MONTHLY_LOSS,
   SRP_BREACH_MAX_DRAWDOWN,
   SRP_BREACH_EXPOSURE,
   SRP_BREACH_EMERGENCY
  };

//--- Stop-loss models.
enum ENUM_SRP_STOP_MODEL
  {
   SRP_STOP_NONE,
   SRP_STOP_FIXED_POINTS,
   SRP_STOP_ATR_MULTIPLE,
   SRP_STOP_STRUCTURE,            // beyond the last swing
   SRP_STOP_DYNAMIC               // regime-adaptive
  };

//--- Take-profit models.
enum ENUM_SRP_TARGET_MODEL
  {
   SRP_TARGET_NONE,
   SRP_TARGET_FIXED_POINTS,
   SRP_TARGET_ATR_MULTIPLE,
   SRP_TARGET_RISK_REWARD,
   SRP_TARGET_STRUCTURE,          // next opposing liquidity
   SRP_TARGET_DYNAMIC
  };

//--- Profit-protection stage a position has reached.
enum ENUM_SRP_PROTECTION_STAGE
  {
   SRP_PROTECTION_NONE,
   SRP_PROTECTION_BREAK_EVEN,
   SRP_PROTECTION_TRAILING,
   SRP_PROTECTION_LOCKED          // profit lock engaged
  };

//=== INDICATORS ====================================================
enum ENUM_SRP_INDICATOR_KIND
  {
   SRP_IND_EMA,
   SRP_IND_SMA,
   SRP_IND_VWAP,
   SRP_IND_ATR,
   SRP_IND_RSI,
   SRP_IND_ADX,
   SRP_IND_MACD,
   SRP_IND_BOLLINGER,
   SRP_IND_CCI,
   SRP_IND_STOCHASTIC,
   SRP_IND_ICHIMOKU,
   SRP_IND_VOLUME,
   SRP_IND_OBV,
   SRP_IND_MFI
  };

//--- Readiness state. Distinguishing "warming up" from "broken" matters:
//--- one resolves itself, the other needs operator attention.
enum ENUM_SRP_IND_STATE
  {
   SRP_IND_STATE_UNINITIALIZED,
   SRP_IND_STATE_WARMING_UP,      // handle valid, not enough bars yet
   SRP_IND_STATE_READY,
   SRP_IND_STATE_STALE,           // last refresh failed
   SRP_IND_STATE_FAILED           // handle invalid
  };

//=== SMART MONEY CONCEPTS ==========================================
enum ENUM_SRP_ZONE_KIND
  {
   SRP_ZONE_ORDER_BLOCK,
   SRP_ZONE_BREAKER_BLOCK,
   SRP_ZONE_MITIGATION_BLOCK,
   SRP_ZONE_FAIR_VALUE_GAP,
   SRP_ZONE_LIQUIDITY_POOL
  };

enum ENUM_SRP_ZONE_STATE
  {
   SRP_ZONE_FRESH,                // untouched since formation
   SRP_ZONE_TESTED,               // touched, still valid
   SRP_ZONE_MITIGATED,            // partially consumed
   SRP_ZONE_INVALIDATED,          // decisively violated
   SRP_ZONE_EXPIRED               // aged out
  };

enum ENUM_SRP_BIAS
  {
   SRP_BIAS_NEUTRAL,
   SRP_BIAS_BULLISH,
   SRP_BIAS_BEARISH
  };

//--- Structural events. BOS continues a trend; CHoCH warns of reversal.
enum ENUM_SRP_STRUCTURE_EVENT
  {
   SRP_STRUCT_NONE,
   SRP_STRUCT_BOS_BULLISH,        // break of structure up
   SRP_STRUCT_BOS_BEARISH,
   SRP_STRUCT_CHOCH_BULLISH,      // change of character up
   SRP_STRUCT_CHOCH_BEARISH
  };

//--- Where price sits within the dealing range.
enum ENUM_SRP_RANGE_ZONE
  {
   SRP_RANGE_UNDEFINED,
   SRP_RANGE_DISCOUNT,            // lower half: value for longs
   SRP_RANGE_EQUILIBRIUM,         // around 50%
   SRP_RANGE_PREMIUM              // upper half: value for shorts
  };

enum ENUM_SRP_SWEEP_KIND
  {
   SRP_SWEEP_NONE,
   SRP_SWEEP_HIGH,                // buy-side liquidity taken
   SRP_SWEEP_LOW                  // sell-side liquidity taken
  };

//=== MARKET STRUCTURE =============================================
//--- Swing point classification. The four labels that define structure.
enum ENUM_SRP_SWING_LABEL
  {
   SRP_SWING_UNCLASSIFIED,
   SRP_SWING_HH,                  // higher high
   SRP_SWING_HL,                  // higher low
   SRP_SWING_LH,                  // lower high
   SRP_SWING_LL                   // lower low
  };

enum ENUM_SRP_SWING_KIND
  {
   SRP_SWING_KIND_HIGH,
   SRP_SWING_KIND_LOW
  };

enum ENUM_SRP_TREND_DIRECTION
  {
   SRP_TREND_DIR_NONE,
   SRP_TREND_DIR_BULLISH,
   SRP_TREND_DIR_BEARISH,
   SRP_TREND_DIR_RANGING
  };

enum ENUM_SRP_TREND_GRADE
  {
   SRP_TREND_GRADE_NONE,
   SRP_TREND_GRADE_WEAK,
   SRP_TREND_GRADE_MODERATE,
   SRP_TREND_GRADE_STRONG,
   SRP_TREND_GRADE_EXHAUSTED      // strong but overextended
  };

enum ENUM_SRP_PRICE_PHASE
  {
   SRP_PHASE_UNDEFINED,
   SRP_PHASE_BREAKOUT,
   SRP_PHASE_PULLBACK,
   SRP_PHASE_REVERSAL,
   SRP_PHASE_CONSOLIDATION
  };

#endif // SRP_INTELLIGENCE_TYPES_ENUMS_MQH
//+------------------------------------------------------------------+
