//+------------------------------------------------------------------+
//|                                   CParameterSetValidator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Optimization : rejects incoherent parameter combinations early.           |
//|                                                                  |
//|   RESPONSIBILITY (one only): decide whether a parameter set is worth        |
//|   testing at all.                                                        |
//|                                                                  |
//|   THE POINT                                                              |
//|   An optimiser will happily spend an hour testing combinations that make    |
//|   no sense - a fast MA period above the slow one, a take profit inside      |
//|   the spread, a trailing step wider than its distance. Rejecting those in   |
//|   OnInit costs microseconds and can cut a large optimisation by a           |
//|   substantial fraction of its passes.                                     |
//|                                                                  |
//|   Distinct from CConfigValidator: that one asks "is this configuration      |
//|   SAFE to trade?", this one asks "is this combination WORTH testing?"       |
//+------------------------------------------------------------------+
#ifndef SRP_OPTIMIZATION_CPARAMETERSETVALIDATOR_MQH
#define SRP_OPTIMIZATION_CPARAMETERSETVALIDATOR_MQH

#include "../Core/Interfaces/IConfigProvider.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Types/Structs.mqh"

class CParameterSetValidator
  {
private:
   ILogger          *m_logger;             // borrowed
   bool              m_strict_mode;        // reject on warnings too
   //--- Pass counters. MQL5 has no 'mutable', so IsWorthTesting is
   //--- non-const rather than losing the tally a tester run needs.
   long              m_rejected;
   long              m_accepted;

   //--- Rule groups, each rejecting a family of pointless combinations.
   bool              CheckIndicatorOrdering(IConfigProvider *config,
                                            SValidationResult &result) const;
   bool              CheckStopTargetRelationship(IConfigProvider *config,
                                                 SValidationResult &result) const;
   bool              CheckTrailingCoherence(IConfigProvider *config,
                                            SValidationResult &result) const;
   bool              CheckRiskCoherence(IConfigProvider *config,
                                        SValidationResult &result) const;
   bool              CheckScheduleCoherence(IConfigProvider *config,
                                            SValidationResult &result) const;
   bool              CheckStrategySelection(IConfigProvider *config,
                                            SValidationResult &result) const;

public:
                     CParameterSetValidator(ILogger *logger);
                    ~CParameterSetValidator(void) { }

   void              SetStrictMode(const bool value);

   //--- Returns false when the pass should be abandoned immediately.
   //--- Non-const: it maintains the accepted/rejected tally.
   bool              IsWorthTesting(IConfigProvider *config,
                                    SValidationResult &result);

   //--- Diagnostics for a tester run: how many passes were skipped.
   long              RejectedCount(void) const { return(m_rejected); }
   long              AcceptedCount(void) const { return(m_accepted); }
  };

#include "../Configuration/CConfigKeys.mqh"

//+------------------------------------------------------------------+
CParameterSetValidator::CParameterSetValidator(ILogger *logger)
  : m_logger(logger),
    m_strict_mode(false),
    m_rejected(0),
    m_accepted(0)
  {
  }
//+------------------------------------------------------------------+
void CParameterSetValidator::SetStrictMode(const bool value)
  {
   m_strict_mode=value;
  }
//+------------------------------------------------------------------+
bool CParameterSetValidator::IsWorthTesting(IConfigProvider *config,
                                            SValidationResult &result)
  {
   if(config==NULL)
     {
      result.AddError("no configuration provider supplied");
      return(false);
     }

   //--- Every rule runs even after the first failure, so the tester log
   //--- shows all reasons rather than one at a time across many passes.
   CheckIndicatorOrdering(config,result);
   CheckStopTargetRelationship(config,result);
   CheckTrailingCoherence(config,result);
   CheckRiskCoherence(config,result);
   CheckScheduleCoherence(config,result);
   CheckStrategySelection(config,result);

   const bool worth=(result.is_valid &&
                     (!m_strict_mode || result.warning_count==0));
   if(worth)
      m_accepted++;
   else
     {
      m_rejected++;
      //--- Debug level: during a 50,000-pass optimisation an info-level
      //--- line per rejection would itself become the bottleneck.
      if(m_logger!=NULL && m_logger.IsEnabled(SRP_LOG_DEBUG))
         m_logger.Debug("ParamValidator","pass skipped: "+result.first_error);
     }
   return(worth);
  }
//+------------------------------------------------------------------+
bool CParameterSetValidator::CheckIndicatorOrdering(IConfigProvider *config,
                                                    SValidationResult &result) const
  {
   const int fast=config.GetInt(CConfigKeys::INDICATOR_FAST_MA_PERIOD,0);
   const int slow=config.GetInt(CConfigKeys::INDICATOR_SLOW_MA_PERIOD,0);
   const int trend=config.GetInt(CConfigKeys::INDICATOR_TREND_MA_PERIOD,0);

   //--- The single most common wasted optimisation: the genetic algorithm
   //--- freely generates fast >= slow, which inverts every crossover.
   //--- Roughly half of a naive two-MA grid is this case.
   if(fast>0 && slow>0 && fast>=slow)
     {
      result.AddError("fast MA period ("+IntegerToString(fast)+
                      ") is not below the slow period ("+
                      IntegerToString(slow)+")");
      return(false);
     }
   if(slow>0 && trend>0 && slow>=trend)
     {
      result.AddWarning("slow MA period is not below the trend period, so the "
                        "trend filter is nearly redundant");
     }
   //--- Periods so close together that the pass duplicates its neighbour.
   if(fast>0 && slow>0 && (slow-fast)<2)
      result.AddWarning("fast and slow MA periods are within 1 bar of each "
                        "other, the pass adds little information");
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
bool CParameterSetValidator::CheckStopTargetRelationship(IConfigProvider *config,
                                                          SValidationResult &result) const
  {
   const double sl=config.GetDouble(CConfigKeys::SL_FIXED_POINTS,0.0);
   const double tp=config.GetDouble(CConfigKeys::TP_FIXED_POINTS,0.0);
   const double spread=config.GetDouble(CConfigKeys::RISK_MAX_SPREAD_POINTS,0.0);

   //--- A target inside the spread cannot be reached at all, so the pass
   //--- is guaranteed to produce a loss for reasons unrelated to the edge.
   if(tp>0.0 && spread>0.0 && tp<=spread)
     {
      result.AddError("take profit ("+DoubleToString(tp,0)+
                      ") is inside the permitted spread ("+
                      DoubleToString(spread,0)+"), it can never be reached");
      return(false);
     }
   if(sl>0.0 && spread>0.0 && sl<=spread)
     {
      result.AddError("stop loss is inside the permitted spread, it would "
                      "trigger on the spread alone");
      return(false);
     }
   //--- A target smaller than the stop needs a very high win rate. Not
   //--- invalid, but worth flagging in strict mode.
   if(sl>0.0 && tp>0.0 && tp<sl*0.3)
      result.AddWarning("take profit is under a third of the stop, requiring "
                        "an implausible win rate to be profitable");
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
bool CParameterSetValidator::CheckTrailingCoherence(IConfigProvider *config,
                                                     SValidationResult &result) const
  {
   if(config.GetInt(CConfigKeys::TRAIL_MODE,0)==(int)SRP_TRAIL_DISABLED)
      return(true);

   const double distance=config.GetDouble(CConfigKeys::TRAIL_DISTANCE_POINTS,0.0);
   const double step=config.GetDouble(CConfigKeys::TRAIL_STEP_POINTS,0.0);
   const double start=config.GetDouble(CConfigKeys::TRAIL_START_POINTS,0.0);

   if(distance<=0.0)
     {
      result.AddError("trailing is enabled with a non-positive distance");
      return(false);
     }
   if(step>distance)
     {
      result.AddError("trailing step ("+DoubleToString(step,0)+
                      ") exceeds its distance ("+DoubleToString(distance,0)+
                      "), the stop would never settle");
      return(false);
     }
   //--- Starting the trail closer than its own distance means the first
   //--- move would place the stop behind the entry and be refused by the
   //--- one-way rule, so the trail silently never engages.
   if(start>0.0 && start<distance)
      result.AddWarning("trailing starts closer than its distance, so the "
                        "first trail move would be rejected");
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
bool CParameterSetValidator::CheckRiskCoherence(IConfigProvider *config,
                                                 SValidationResult &result) const
  {
   const double risk=config.GetDouble(CConfigKeys::RISK_PERCENT,0.0);
   const double daily=config.GetDouble(CConfigKeys::GUARD_DAILY_LOSS_PERCENT,0.0);

   //--- If one loss trips the daily guard, every pass ends after the first
   //--- losing trade and the whole run measures nothing.
   if(risk>0.0 && daily>0.0 && risk>=daily)
     {
      result.AddError("per-trade risk ("+DoubleToString(risk,2)+
                      "%) is at or above the daily loss limit ("+
                      DoubleToString(daily,2)+"%), one loss ends each day");
      return(false);
     }
   const double max_lot=config.GetDouble(CConfigKeys::RISK_MAX_LOT,0.0);
   const double fixed_lot=config.GetDouble(CConfigKeys::RISK_FIXED_LOT,0.0);
   if(max_lot>0.0 && fixed_lot>max_lot)
     {
      result.AddError("fixed lot exceeds the maximum lot, the cap makes the "
                      "sizing parameter inert");
      return(false);
     }
   //--- Scale-out that cannot leave a remainder.
   if(config.GetBool(CConfigKeys::TM_SCALE_OUT_ENABLED,false))
     {
      const double fraction=config.GetDouble(CConfigKeys::TM_SCALE_OUT_FRACTION,0.0);
      if(fraction<=0.0 || fraction>=1.0)
        {
         result.AddError("scale-out fraction outside 0..1 exclusive");
         return(false);
        }
     }
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
bool CParameterSetValidator::CheckScheduleCoherence(IConfigProvider *config,
                                                     SValidationResult &result) const
  {
   if(config.GetBool(CConfigKeys::SESSION_FILTER_ENABLED,false))
     {
      const bool any=config.GetBool(CConfigKeys::SESSION_ALLOW_SYDNEY,false) ||
                     config.GetBool(CConfigKeys::SESSION_ALLOW_TOKYO,false) ||
                     config.GetBool(CConfigKeys::SESSION_ALLOW_LONDON,false) ||
                     config.GetBool(CConfigKeys::SESSION_ALLOW_NEWYORK,false);
      //--- Zero trades guaranteed. The optimiser would otherwise spend a
      //--- full pass discovering that.
      if(!any)
        {
         result.AddError("every session is disabled with the session filter "
                         "on, the pass cannot take a trade");
         return(false);
        }
     }
   //--- A blackout wide enough to cover the whole session.
   if(config.GetBool(CConfigKeys::NEWS_FILTER_ENABLED,false))
     {
      const int before=config.GetInt(CConfigKeys::NEWS_MINUTES_BEFORE,0);
      const int after=config.GetInt(CConfigKeys::NEWS_MINUTES_AFTER,0);
      if(before+after>720)
         result.AddWarning("the news blackout exceeds 12 hours per event and "
                           "will suppress most trading");
     }
   //--- A frequency cap of zero blocks everything.
   if(config.GetBool(CConfigKeys::FILTER_FREQUENCY_ENABLED,false) &&
      config.GetInt(CConfigKeys::FILTER_MAX_TRADES_PER_DAY,-1)==0)
     {
      result.AddError("the daily trade cap is 0 with the frequency filter on");
      return(false);
     }
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
bool CParameterSetValidator::CheckStrategySelection(IConfigProvider *config,
                                                     SValidationResult &result) const
  {
   const bool any=
      config.GetBool(CConfigKeys::STRATEGY_MOMENTUM_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_MEAN_REVERSION_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_BREAKOUT_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_EMA_CROSS_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_VWAP_PULLBACK_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_LIQUIDITY_SWEEP_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_ORDER_BLOCK_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_FVG_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_OPENING_RANGE_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_TREND_CONTINUATION_ENABLED,false);
   if(!any)
     {
      result.AddError("no strategy is enabled, the pass cannot generate a "
                      "signal");
      return(false);
     }

   //--- A confirmation requirement no configuration can satisfy.
   const int required=config.GetInt(CConfigKeys::DECISION_MIN_CONFIRMATIONS,0);
   if(required>13)
     {
      result.AddError("more confirmations required than the 13 available");
      return(false);
     }
   const double min_confidence=
      config.GetDouble(CConfigKeys::DECISION_MIN_CONFIDENCE,0.0);
   if(min_confidence>=1.0)
     {
      result.AddError("minimum confidence of 1.0 or above can never be met");
      return(false);
     }
   if(min_confidence>=0.95)
      result.AddWarning("minimum confidence at 0.95 or above will reject "
                        "nearly every signal");
   //--- Unanimous voting across many strategies is effectively a block.
   return(result.is_valid);
  }

#endif // SRP_OPTIMIZATION_CPARAMETERSETVALIDATOR_MQH
//+------------------------------------------------------------------+
