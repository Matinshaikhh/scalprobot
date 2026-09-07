//+------------------------------------------------------------------+
//|                                      IntelligenceStructs.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   Passive data-transfer objects for Phase 2. No business logic -    |
//|   only data plus trivial reset/validity helpers, so no consumer      |
//|   can read an uninitialised field.                                  |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_TYPES_STRUCTS_MQH
#define SRP_INTELLIGENCE_TYPES_STRUCTS_MQH

#include "../../Core/Types/Constants.mqh"
//--- Phase 1 structs supply SValidationResult, which the Phase 2
//--- Validate() methods report through. Reusing it keeps validation
//--- reporting uniform across both phases instead of inventing a
//--- parallel result type.
#include "../../Core/Types/Structs.mqh"
#include "IntelligenceEnums.mqh"

//=== RISK ==========================================================
//+------------------------------------------------------------------+
//| Output of the sizing layer.                                       |
//+------------------------------------------------------------------+
struct SSizingResult
  {
   bool              approved;
   double            volume;             // normalised, broker-legal
   double            raw_volume;         // before normalisation
   double            risk_amount;        // account currency at risk
   double            risk_percent;
   double            stop_distance_points;
   ENUM_SRP_SIZING_MODEL model_used;
   string            explanation;
   string            rejection_reason;

                     SSizingResult(void) { Reset(); }
   void              Reset(void)
     {
      approved=false; volume=0.0; raw_volume=0.0;
      risk_amount=0.0; risk_percent=0.0; stop_distance_points=0.0;
      model_used=SRP_SIZING_FIXED_LOT;
      explanation=""; rejection_reason="";
     }
  };

//+------------------------------------------------------------------+
//| Rolling profit-and-loss ledger across all time windows.            |
//| One struct so every limit reads the same numbers.                  |
//+------------------------------------------------------------------+
struct SRiskLedger
  {
   //--- Window boundaries, in server time.
   datetime          day_start;
   datetime          week_start;
   datetime          month_start;
   //--- Opening capital per window, captured at each boundary.
   double            day_open_equity;
   double            week_open_equity;
   double            month_open_equity;
   //--- Realised results per window.
   double            day_realized;
   double            week_realized;
   double            month_realized;
   //--- Floating result, shared by all windows.
   double            floating;
   //--- High-water mark, persisted so a restart cannot reset drawdown.
   double            peak_equity;
   double            trough_equity;
   //--- Trade counters.
   int               day_trades;
   int               week_trades;
   int               month_trades;
   int               consecutive_losses;
   int               consecutive_wins;

                     SRiskLedger(void) { Reset(); }
   void              Reset(void)
     {
      day_start=0; week_start=0; month_start=0;
      day_open_equity=0.0; week_open_equity=0.0; month_open_equity=0.0;
      day_realized=0.0; week_realized=0.0; month_realized=0.0;
      floating=0.0; peak_equity=0.0; trough_equity=0.0;
      day_trades=0; week_trades=0; month_trades=0;
      consecutive_losses=0; consecutive_wins=0;
     }
   //--- Totals include floating: an open loss is a real loss for the
   //--- purpose of a daily limit, which is the conservative reading.
   double            DayTotal(void)   const { return(day_realized+floating); }
   double            WeekTotal(void)  const { return(week_realized+floating); }
   double            MonthTotal(void) const { return(month_realized+floating); }
  };

//+------------------------------------------------------------------+
//| Verdict from the limit guard set.                                  |
//+------------------------------------------------------------------+
struct SRiskVerdict
  {
   bool                  entries_allowed;
   bool                  flatten_required;
   ENUM_SRP_LIMIT_BREACH breach;
   string                detail;
   double                measured;
   double                limit;

                     SRiskVerdict(void) { Reset(); }
   void              Reset(void)
     {
      entries_allowed=true; flatten_required=false;
      breach=SRP_BREACH_NONE; detail="";
      measured=0.0; limit=0.0;
     }
   void              Deny(const ENUM_SRP_LIMIT_BREACH kind,
                          const string text,
                          const double measured_value,
                          const double limit_value,
                          const bool require_flatten)
     {
      entries_allowed=false;
      flatten_required=require_flatten;
      breach=kind; detail=text;
      measured=measured_value; limit=limit_value;
     }
  };

//+------------------------------------------------------------------+
//| Protective levels resolved for one prospective or open trade.      |
//+------------------------------------------------------------------+
struct SProtectionPlan
  {
   bool              has_stop;
   bool              has_target;
   double            stop_price;
   double            target_price;
   double            stop_distance_points;
   double            target_distance_points;
   double            reward_risk_ratio;
   ENUM_SRP_STOP_MODEL   stop_model;
   ENUM_SRP_TARGET_MODEL target_model;
   string            explanation;

                     SProtectionPlan(void) { Reset(); }
   void              Reset(void)
     {
      has_stop=false; has_target=false;
      stop_price=0.0; target_price=0.0;
      stop_distance_points=0.0; target_distance_points=0.0;
      reward_risk_ratio=0.0;
      stop_model=SRP_STOP_NONE; target_model=SRP_TARGET_NONE;
      explanation="";
     }
  };

//+------------------------------------------------------------------+
//| Requested adjustment to an open position's stop.                   |
//+------------------------------------------------------------------+
struct SStopAdjustment
  {
   bool                      adjust;
   double                    new_stop_price;
   ENUM_SRP_PROTECTION_STAGE stage;
   string                    reason;

                     SStopAdjustment(void) { Reset(); }
   void              Reset(void)
     {
      adjust=false; new_stop_price=0.0;
      stage=SRP_PROTECTION_NONE; reason="";
     }
  };

//=== INDICATORS ====================================================
//+------------------------------------------------------------------+
//| One indicator read. 'valid' is checked before 'value' is used, so   |
//| EMPTY_VALUE can never leak into a calculation.                     |
//+------------------------------------------------------------------+
struct SIndicatorReading
  {
   bool              valid;
   double            value;
   datetime          bar_time;
   int               shift;

                     SIndicatorReading(void) { Reset(); }
   void              Reset(void)
     {
      valid=false; value=0.0; bar_time=0; shift=0;
     }
  };

//=== SMART MONEY CONCEPTS ==========================================
//+------------------------------------------------------------------+
//| A price zone: order block, FVG, breaker, mitigation or pool.        |
//+------------------------------------------------------------------+
struct SPriceZone
  {
   ENUM_SRP_ZONE_KIND  kind;
   ENUM_SRP_ZONE_STATE state;
   ENUM_SRP_BIAS       bias;
   double              upper;
   double              lower;
   double              midpoint;          // 50% - the usual entry trigger
   datetime            formed_at;
   int                 formed_bar;        // shift when detected
   int                 touch_count;
   double              strength;          // 0..1 composite quality
   double              volume_at_form;
   bool                has_displacement;  // formed with an impulsive move
   string              note;

                     SPriceZone(void) { Reset(); }
   void              Reset(void)
     {
      kind=SRP_ZONE_ORDER_BLOCK; state=SRP_ZONE_FRESH; bias=SRP_BIAS_NEUTRAL;
      upper=0.0; lower=0.0; midpoint=0.0;
      formed_at=0; formed_bar=0; touch_count=0;
      strength=0.0; volume_at_form=0.0;
      has_displacement=false; note="";
     }
   double            Height(void) const { return(upper-lower); }
   bool              Contains(const double price) const
     {
      return(price<=upper && price>=lower);
     }
   bool              IsActionable(void) const
     {
      return(state==SRP_ZONE_FRESH || state==SRP_ZONE_TESTED);
     }
  };

//+------------------------------------------------------------------+
//| Detected liquidity sweep (stop run).                              |
//+------------------------------------------------------------------+
struct SLiquiditySweep
  {
   ENUM_SRP_SWEEP_KIND kind;
   double              swept_level;
   double              extreme_reached;
   datetime            occurred_at;
   int                 bar_shift;
   double              penetration_points;
   bool                reversed;          // closed back inside: a true sweep
   double              strength;

                     SLiquiditySweep(void) { Reset(); }
   void              Reset(void)
     {
      kind=SRP_SWEEP_NONE; swept_level=0.0; extreme_reached=0.0;
      occurred_at=0; bar_shift=0; penetration_points=0.0;
      reversed=false; strength=0.0;
     }
  };

//+------------------------------------------------------------------+
//| Equal highs / equal lows cluster - resting liquidity.              |
//+------------------------------------------------------------------+
struct SEqualLevels
  {
   bool              found;
   ENUM_SRP_SWING_KIND kind;
   double            level;
   int               touch_count;
   double            tolerance_points;
   datetime          first_touch;
   datetime          last_touch;

                     SEqualLevels(void) { Reset(); }
   void              Reset(void)
     {
      found=false; kind=SRP_SWING_KIND_HIGH; level=0.0;
      touch_count=0; tolerance_points=0.0;
      first_touch=0; last_touch=0;
     }
  };

//+------------------------------------------------------------------+
//| Displacement: an impulsive, one-sided move. The footprint of        |
//| institutional participation and what validates a zone.             |
//+------------------------------------------------------------------+
struct SDisplacement
  {
   bool              detected;
   ENUM_SRP_BIAS     direction;
   double            range_points;
   double            body_ratio;         // body / total range
   double            atr_multiple;
   int               bar_shift;
   datetime          occurred_at;

                     SDisplacement(void) { Reset(); }
   void              Reset(void)
     {
      detected=false; direction=SRP_BIAS_NEUTRAL;
      range_points=0.0; body_ratio=0.0; atr_multiple=0.0;
      bar_shift=0; occurred_at=0;
     }
  };

//+------------------------------------------------------------------+
//| The dealing range and where price sits inside it.                  |
//+------------------------------------------------------------------+
struct SDealingRange
  {
   bool                 valid;
   double               range_high;
   double               range_low;
   double               equilibrium;      // 50%
   double               current_position; // 0..1 within the range
   ENUM_SRP_RANGE_ZONE  zone;

                     SDealingRange(void) { Reset(); }
   void              Reset(void)
     {
      valid=false; range_high=0.0; range_low=0.0; equilibrium=0.0;
      current_position=0.0; zone=SRP_RANGE_UNDEFINED;
     }
   double            Height(void) const { return(range_high-range_low); }
  };

//=== MARKET STRUCTURE =============================================
//+------------------------------------------------------------------+
//| One confirmed swing point.                                        |
//+------------------------------------------------------------------+
struct SSwingPoint
  {
   bool                 valid;
   ENUM_SRP_SWING_KIND  kind;
   ENUM_SRP_SWING_LABEL label;
   double               price;
   datetime             time;
   int                  bar_shift;        // at detection time
   int                  strength;         // confirming bars each side
   bool                 swept;            // liquidity above/below taken

                     SSwingPoint(void) { Reset(); }
   void              Reset(void)
     {
      valid=false; kind=SRP_SWING_KIND_HIGH; label=SRP_SWING_UNCLASSIFIED;
      price=0.0; time=0; bar_shift=0; strength=0; swept=false;
     }
  };

//+------------------------------------------------------------------+
//| Complete structural picture. The primary Phase 2 output.            |
//+------------------------------------------------------------------+
struct SStructureState
  {
   ENUM_SRP_TREND_DIRECTION direction;
   ENUM_SRP_TREND_GRADE     grade;
   ENUM_SRP_PRICE_PHASE     phase;
   ENUM_SRP_STRUCTURE_EVENT last_event;
   datetime                 last_event_time;
   //--- The four reference points that define current structure.
   SSwingPoint              last_high;
   SSwingPoint              prior_high;
   SSwingPoint              last_low;
   SSwingPoint              prior_low;
   //--- Quantified strength, 0..1.
   double                   strength_score;
   int                      consecutive_hh;
   int                      consecutive_ll;
   int                      swing_count;
   SDealingRange            range;

                     SStructureState(void) { Reset(); }
   void              Reset(void)
     {
      direction=SRP_TREND_DIR_NONE;
      grade=SRP_TREND_GRADE_NONE;
      phase=SRP_PHASE_UNDEFINED;
      last_event=SRP_STRUCT_NONE;
      last_event_time=0;
      last_high.Reset(); prior_high.Reset();
      last_low.Reset();  prior_low.Reset();
      strength_score=0.0;
      consecutive_hh=0; consecutive_ll=0; swing_count=0;
      range.Reset();
     }
   bool              IsBullish(void) const { return(direction==SRP_TREND_DIR_BULLISH); }
   bool              IsBearish(void) const { return(direction==SRP_TREND_DIR_BEARISH); }
   bool              IsTrending(void) const
     {
      return(direction==SRP_TREND_DIR_BULLISH || direction==SRP_TREND_DIR_BEARISH);
     }
  };

#endif // SRP_INTELLIGENCE_TYPES_STRUCTS_MQH
//+------------------------------------------------------------------+
