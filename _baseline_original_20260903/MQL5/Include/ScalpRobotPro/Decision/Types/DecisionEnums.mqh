//+------------------------------------------------------------------+
//|                                             DecisionEnums.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   Shared vocabulary for Phase 3. Separate from Phase 1 and Phase 2    |
//|   enums so neither is modified. All enumerators are SRP_-prefixed:    |
//|   MQL5 places enum members in the global namespace.                   |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_TYPES_ENUMS_MQH
#define SRP_DECISION_TYPES_ENUMS_MQH

//=== STRATEGY ======================================================
//--- The ten strategy plugins. Stable ids so statistics and journals
//--- can attribute a trade to its origin long after the fact.
enum ENUM_SRP_STRATEGY_KIND
  {
   SRP_STRAT_EMA_CROSS,
   SRP_STRAT_VWAP_PULLBACK,
   SRP_STRAT_LIQUIDITY_SWEEP,
   SRP_STRAT_ORDER_BLOCK,
   SRP_STRAT_FAIR_VALUE_GAP,
   SRP_STRAT_MOMENTUM_SCALP,
   SRP_STRAT_OPENING_RANGE_BREAKOUT,
   SRP_STRAT_TREND_CONTINUATION,
   SRP_STRAT_MEAN_REVERSION,
   SRP_STRAT_BREAKOUT,
   //--- APPENDED IN PHASE 6, never inserted. These ids are written into
   //--- trade journals and statistics, so renumbering an existing member
   //--- would silently re-attribute every historical trade.
   SRP_STRAT_BREAK_OF_STRUCTURE,
   SRP_STRAT_VOLATILITY_BREAKOUT,
   //--- APPENDED for the order-flow plugin. Same rule: append only.
   SRP_STRAT_ORDER_FLOW
  };

//--- A strategy's verdict. Deliberately three-valued: NO_TRADE is a
//--- real answer, not an absence of one.
enum ENUM_SRP_DECISION
  {
   SRP_DECISION_NO_TRADE,
   SRP_DECISION_BUY,
   SRP_DECISION_SELL
  };

//--- Risk rating a strategy assigns to its own signal. Lets the caller
//--- size differently for a high-conviction setup versus a marginal one.
enum ENUM_SRP_RISK_RATING
  {
   SRP_RISK_RATING_NONE,
   SRP_RISK_RATING_LOW,
   SRP_RISK_RATING_MEDIUM,
   SRP_RISK_RATING_HIGH,
   SRP_RISK_RATING_EXTREME
  };

//=== CONFIRMATION ==================================================
//--- The thirteen confirmation checks. Each is an independent filter
//--- contributing to the composite confidence score.
enum ENUM_SRP_CONFIRM_KIND
  {
   SRP_CONFIRM_TREND,
   SRP_CONFIRM_VOLUME,
   SRP_CONFIRM_ATR,
   SRP_CONFIRM_VWAP,
   SRP_CONFIRM_ADX,
   SRP_CONFIRM_RSI,
   SRP_CONFIRM_MACD,
   SRP_CONFIRM_BOLLINGER,
   SRP_CONFIRM_STRUCTURE,
   SRP_CONFIRM_SMC,
   SRP_CONFIRM_NEWS,
   SRP_CONFIRM_SESSION,
   SRP_CONFIRM_SPREAD
  };

//--- Outcome of one confirmation check.
enum ENUM_SRP_CONFIRM_RESULT
  {
   SRP_CONFIRM_PASS,          // agrees with the proposed direction
   SRP_CONFIRM_FAIL,          // disagrees
   SRP_CONFIRM_NEUTRAL,       // no opinion; neither helps nor hinders
   SRP_CONFIRM_UNAVAILABLE    // data missing - distinct from neutral
  };

//=== SESSION =======================================================
//--- NAME COLLISION NOTE: Phase 1's Core/Types/Enums.mqh already defines
//--- ENUM_SRP_SESSION with members SRP_SESSION_SYDNEY, _TOKYO, _LONDON,
//--- _NEWYORK. MQL5 places enum members in the GLOBAL namespace, so
//--- reusing those names is a redefinition error. Phase 3 therefore uses
//--- the SRP_TS_ prefix ("trading session") rather than modifying Phase 1.
enum ENUM_SRP_TRADING_SESSION
  {
   SRP_TS_NONE,
   SRP_TS_SYDNEY,
   SRP_TS_TOKYO,
   SRP_TS_LONDON,
   SRP_TS_NEWYORK
  };

//--- Kill zones: the high-probability windows within sessions where
//--- institutional activity concentrates.
enum ENUM_SRP_KILL_ZONE
  {
   SRP_KILLZONE_NONE,
   SRP_KILLZONE_ASIAN,
   SRP_KILLZONE_LONDON_OPEN,
   SRP_KILLZONE_NEWYORK_OPEN,
   SRP_KILLZONE_LONDON_CLOSE
  };

enum ENUM_SRP_SESSION_OVERLAP
  {
   SRP_OVERLAP_NONE,
   SRP_OVERLAP_SYDNEY_TOKYO,
   SRP_OVERLAP_TOKYO_LONDON,
   SRP_OVERLAP_LONDON_NEWYORK   // the highest-liquidity window of the day
  };

//--- Why the session manager refused to trade.
enum ENUM_SRP_TIME_BLOCK
  {
   SRP_TIME_BLOCK_NONE,
   SRP_TIME_BLOCK_WEEKEND,
   SRP_TIME_BLOCK_HOLIDAY,
   SRP_TIME_BLOCK_NO_SESSION,
   SRP_TIME_BLOCK_OUTSIDE_KILLZONE,
   SRP_TIME_BLOCK_FRIDAY_CLOSE,
   SRP_TIME_BLOCK_SESSION_EDGE     // first/last minutes: widest spreads
  };

//=== NEWS ==========================================================
//--- The specific high-impact releases the engine recognises by name.
//--- Named separately from generic impact because these move gold and
//--- FX far more than their nominal importance flag suggests.
enum ENUM_SRP_NEWS_KIND
  {
   SRP_NEWS_OTHER,
   SRP_NEWS_NFP,                  // non-farm payrolls
   SRP_NEWS_CPI,                  // consumer price index
   SRP_NEWS_FOMC,                 // Fed rate decision / statement
   SRP_NEWS_GDP,
   SRP_NEWS_PMI,
   SRP_NEWS_INTEREST_RATE,        // non-Fed central bank decisions
   SRP_NEWS_UNEMPLOYMENT,
   SRP_NEWS_RETAIL_SALES
  };

enum ENUM_SRP_NEWS_SEVERITY
  {
   SRP_NEWS_SEV_NONE,
   SRP_NEWS_SEV_LOW,
   SRP_NEWS_SEV_MEDIUM,
   SRP_NEWS_SEV_HIGH,
   SRP_NEWS_SEV_CRITICAL          // FOMC, NFP: flatten-worthy
  };

enum ENUM_SRP_NEWS_PHASE
  {
   SRP_NEWS_PHASE_CLEAR,          // no event in range
   SRP_NEWS_PHASE_APPROACHING,    // inside the pre-event window
   SRP_NEWS_PHASE_ACTIVE,         // at the release
   SRP_NEWS_PHASE_COOLDOWN        // inside the post-event window
  };

//=== AGGREGATION ===================================================
//--- How several strategy opinions collapse into one decision.
enum ENUM_SRP_VOTE_MODE
  {
   SRP_VOTE_FIRST_MATCH,          // fastest; first actionable wins
   SRP_VOTE_HIGHEST_CONFIDENCE,   // best single opinion
   SRP_VOTE_MAJORITY,             // count votes per direction
   SRP_VOTE_WEIGHTED,             // confidence x weight per direction
   SRP_VOTE_UNANIMOUS             // strictest; all agree or no trade
  };

//--- Why the decision engine declined to act.
enum ENUM_SRP_DECLINE_REASON
  {
   SRP_DECLINE_NONE,
   SRP_DECLINE_NO_SIGNAL,
   SRP_DECLINE_LOW_CONFIDENCE,
   SRP_DECLINE_CONFIRMATION_FAILED,
   SRP_DECLINE_CONFLICTING_SIGNALS,
   SRP_DECLINE_SESSION_BLOCKED,
   SRP_DECLINE_NEWS_BLOCKED,
   SRP_DECLINE_DATA_UNAVAILABLE,
   SRP_DECLINE_DISABLED,
   //--- Added in Phase 6. Kept distinct from NO_SIGNAL because "no setup
   //--- existed" and "the regime excluded every strategy that could have
   //--- found one" send a user looking in completely different places.
   SRP_DECLINE_REGIME_BLOCKED
  };

#endif // SRP_DECISION_TYPES_ENUMS_MQH
//+------------------------------------------------------------------+
