//+------------------------------------------------------------------+
//|                                           DecisionStructs.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   Passive data-transfer objects for Phase 3. No business logic -       |
//|   data plus trivial reset helpers, so no consumer can read an          |
//|   uninitialised field.                                               |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_TYPES_STRUCTS_MQH
#define SRP_DECISION_TYPES_STRUCTS_MQH

#include "../../Core/Types/Constants.mqh"
#include "../../Core/Types/Structs.mqh"          // SValidationResult
#include "../../Intelligence/Types/IntelligenceStructs.mqh"
#include "DecisionEnums.mqh"

//=== SESSION =======================================================
//+------------------------------------------------------------------+
//| Complete time-context picture. Produced once per pass by            |
//| CSessionManager and read by every strategy and confirmation.        |
//+------------------------------------------------------------------+
struct SSessionState
  {
   bool                     trading_permitted;
   ENUM_SRP_TIME_BLOCK      block_reason;
   string                   block_detail;
   //--- Active session context.
   ENUM_SRP_TRADING_SESSION active_session;
   ENUM_SRP_SESSION_OVERLAP overlap;
   ENUM_SRP_KILL_ZONE       kill_zone;
   bool                     in_kill_zone;
   //--- Timing within the session.
   int                      minutes_into_session;
   int                      minutes_until_session_end;
   //--- Resolved clock facts.
   datetime                 server_time;
   datetime                 gmt_time;
   int                      broker_offset_minutes;   // server minus GMT
   bool                     dst_active;
   int                      day_of_week;
   //--- Liquidity quality 0..1, derived from session and overlap. A
   //--- scalper's edge depends on it, so it is quantified rather than
   //--- left implicit.
   double                   liquidity_score;

                     SSessionState(void) { Reset(); }
   void              Reset(void)
     {
      trading_permitted=false;
      block_reason=SRP_TIME_BLOCK_NONE;
      block_detail="";
      active_session=SRP_TS_NONE;
      overlap=SRP_OVERLAP_NONE;
      kill_zone=SRP_KILLZONE_NONE;
      in_kill_zone=false;
      minutes_into_session=0;
      minutes_until_session_end=0;
      server_time=0; gmt_time=0;
      broker_offset_minutes=0;
      dst_active=false;
      day_of_week=0;
      liquidity_score=0.0;
     }
  };

//=== NEWS ==========================================================
//+------------------------------------------------------------------+
//| One recognised economic release.                                  |
//+------------------------------------------------------------------+
struct SNewsItem
  {
   bool                    valid;
   ENUM_SRP_NEWS_KIND      kind;
   ENUM_SRP_NEWS_SEVERITY  severity;
   string                  title;
   string                  currency;
   datetime                event_time;
   int                     minutes_until;      // negative once past
   int                     pause_before_minutes;
   int                     pause_after_minutes;
   bool                    affects_symbol;

                     SNewsItem(void) { Reset(); }
   void              Reset(void)
     {
      valid=false;
      kind=SRP_NEWS_OTHER;
      severity=SRP_NEWS_SEV_NONE;
      title=""; currency="";
      event_time=0; minutes_until=0;
      pause_before_minutes=0; pause_after_minutes=0;
      affects_symbol=false;
     }
  };

//+------------------------------------------------------------------+
//| Current news blackout picture, including the countdown.            |
//+------------------------------------------------------------------+
struct SNewsState
  {
   bool                 trading_permitted;
   ENUM_SRP_NEWS_PHASE  phase;
   SNewsItem            active_event;
   SNewsItem            next_event;
   //--- Countdown surfaces, in seconds for precision.
   int                  seconds_until_next;
   int                  seconds_until_resume;
   bool                 flatten_recommended;   // critical events only
   bool                 source_available;
   string               detail;

                     SNewsState(void) { Reset(); }
   void              Reset(void)
     {
      trading_permitted=true;
      phase=SRP_NEWS_PHASE_CLEAR;
      active_event.Reset();
      next_event.Reset();
      seconds_until_next=0;
      seconds_until_resume=0;
      flatten_recommended=false;
      source_available=false;
      detail="";
     }
  };

//=== STRATEGY ======================================================
//+------------------------------------------------------------------+
//| A single strategy's opinion. The exact contract Phase 3 requires:   |
//| BUY / SELL / NO TRADE, confidence, reason, risk rating.            |
//+------------------------------------------------------------------+
struct SStrategySignal
  {
   ENUM_SRP_DECISION      decision;
   ENUM_SRP_STRATEGY_KIND strategy;
   string                 strategy_name;
   //--- Normalised 0..1. Comparable across strategies, which is what
   //--- makes weighted voting meaningful.
   double                 confidence;
   string                 reason;              // human-readable "why"
   ENUM_SRP_RISK_RATING   risk_rating;
   //--- Optional level hints. Zero means "let the risk layer decide" -
   //--- a strategy may know its invalidation point better than a
   //--- generic calculator does.
   double                 suggested_entry;
   double                 suggested_stop;
   double                 suggested_target;
   //--- Provenance.
   datetime               generated_at;
   double                 weight;              // aggregation weight

                     SStrategySignal(void) { Reset(); }
   void              Reset(void)
     {
      decision=SRP_DECISION_NO_TRADE;
      strategy=SRP_STRAT_EMA_CROSS;
      strategy_name="";
      confidence=0.0;
      reason="";
      risk_rating=SRP_RISK_RATING_NONE;
      suggested_entry=0.0;
      suggested_stop=0.0;
      suggested_target=0.0;
      generated_at=0;
      weight=1.0;
     }
   bool              IsActionable(void) const
     { return(decision!=SRP_DECISION_NO_TRADE); }
   bool              IsBuy(void) const  { return(decision==SRP_DECISION_BUY); }
   bool              IsSell(void) const { return(decision==SRP_DECISION_SELL); }
  };

//=== CONFIRMATION ==================================================
//+------------------------------------------------------------------+
//| Result of one confirmation check.                                  |
//+------------------------------------------------------------------+
struct SConfirmation
  {
   ENUM_SRP_CONFIRM_KIND   kind;
   ENUM_SRP_CONFIRM_RESULT result;
   string                  name;
   string                  detail;
   //--- Contribution to the composite score, 0..1.
   double                  score;
   double                  weight;
   //--- A blocking check that fails vetoes the trade outright; a
   //--- non-blocking one only lowers the score.
   bool                    is_blocking;

                     SConfirmation(void) { Reset(); }
   void              Reset(void)
     {
      kind=SRP_CONFIRM_TREND;
      result=SRP_CONFIRM_NEUTRAL;
      name=""; detail="";
      score=0.0; weight=1.0;
      is_blocking=false;
     }
  };

//+------------------------------------------------------------------+
//| Aggregate confirmation outcome.                                    |
//+------------------------------------------------------------------+
struct SConfirmationReport
  {
   bool              confirmed;
   double            confidence;          // 0..1 composite
   int               evaluated;
   int               passed;
   int               failed;
   int               neutral;
   int               unavailable;
   //--- The blocking failure that killed the trade, when one did.
   ENUM_SRP_CONFIRM_KIND blocking_failure;
   string            blocking_detail;
   string            summary;

                     SConfirmationReport(void) { Reset(); }
   void              Reset(void)
     {
      confirmed=false;
      confidence=0.0;
      evaluated=0; passed=0; failed=0; neutral=0; unavailable=0;
      blocking_failure=SRP_CONFIRM_TREND;
      blocking_detail="";
      summary="";
     }
   double            PassRatio(void) const
     {
      const int decisive=passed+failed;
      return(decisive>0 ? (double)passed/(double)decisive : 0.0);
     }
  };

//=== FINAL DECISION ================================================
//+------------------------------------------------------------------+
//| The Decision Engine's single output. Everything a caller needs to   |
//| act, or to explain why it did not.                                 |
//+------------------------------------------------------------------+
struct STradeDecision
  {
   bool                     actionable;
   ENUM_SRP_DECISION        decision;
   ENUM_SRP_DECLINE_REASON  decline_reason;
   //--- Winning signal and the confirmation that validated it.
   SStrategySignal          signal;
   SConfirmationReport      confirmation;
   //--- Final blended confidence: strategy conviction x confirmation.
   double                   final_confidence;
   ENUM_SRP_RISK_RATING     risk_rating;
   //--- Vote accounting, so a conflicted market is visible rather than
   //--- silently resolved.
   int                      candidates;
   int                      buy_votes;
   int                      sell_votes;
   double                   buy_weight;
   double                   sell_weight;
   //--- Context snapshots at decision time.
   SSessionState            session;
   SNewsState               news;
   string                   explanation;
   datetime                 decided_at;

                     STradeDecision(void) { Reset(); }
   void              Reset(void)
     {
      actionable=false;
      decision=SRP_DECISION_NO_TRADE;
      decline_reason=SRP_DECLINE_NONE;
      signal.Reset();
      confirmation.Reset();
      final_confidence=0.0;
      risk_rating=SRP_RISK_RATING_NONE;
      candidates=0; buy_votes=0; sell_votes=0;
      buy_weight=0.0; sell_weight=0.0;
      session.Reset();
      news.Reset();
      explanation="";
      decided_at=0;
     }
  };

//=== SHARED CONTEXT ================================================
//+------------------------------------------------------------------+
//| Everything a strategy or confirmation needs, gathered once per pass.|
//|                                                                  |
//| Bundling it means adding a new data source never changes a single    |
//| strategy signature - the Open/Closed Principle applied to the        |
//| plugin contract. Strategies receive this as a CONST reference and    |
//| must not mutate it.                                                |
//+------------------------------------------------------------------+
struct SDecisionInput
  {
   //--- Market basics.
   string            symbol;
   ENUM_TIMEFRAMES   timeframe;
   datetime          server_time;
   double            bid;
   double            ask;
   double            mid;
   double            spread_points;
   double            point;
   int               digits;
   bool              is_new_bar;
   datetime          bar_time;
   //--- Current bar and the one before it.
   double            open;
   double            high;
   double            low;
   double            close;
   double            prev_open;
   double            prev_high;
   double            prev_low;
   double            prev_close;
   //--- Phase 2 outputs, already computed.
   SStructureState   structure;
   SSessionState     session;
   SNewsState        news;
   bool              structure_valid;
   //--- Validity flag: strategies check this before reading anything.
   bool              is_valid;

                     SDecisionInput(void) { Reset(); }
   void              Reset(void)
     {
      symbol=""; timeframe=PERIOD_CURRENT; server_time=0;
      bid=0.0; ask=0.0; mid=0.0; spread_points=0.0;
      point=0.0; digits=0;
      is_new_bar=false; bar_time=0;
      open=0.0; high=0.0; low=0.0; close=0.0;
      prev_open=0.0; prev_high=0.0; prev_low=0.0; prev_close=0.0;
      structure.Reset();
      session.Reset();
      news.Reset();
      structure_valid=false;
      is_valid=false;
     }
  };

#endif // SRP_DECISION_TYPES_STRUCTS_MQH
//+------------------------------------------------------------------+
