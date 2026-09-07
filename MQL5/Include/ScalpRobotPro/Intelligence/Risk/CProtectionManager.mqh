//+------------------------------------------------------------------+
//|                                        CProtectionManager.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): compute protective price levels.          |
//|   Stop loss, take profit, break-even, trailing and profit lock.        |
//|                                                                  |
//|   IT CALCULATES, IT DOES NOT EXECUTE. Every method returns a level or  |
//|   an SStopAdjustment; sending the modification is the trade engine's   |
//|   job. That separation is what lets all of this be verified without a  |
//|   broker connection.                                                 |
//|                                                                  |
//|   THE ONE-WAY RULE                                                   |
//|   Every stop adjustment here only ever moves a stop in the            |
//|   PROFITABLE direction. A "trailing" stop that can retreat is not a   |
//|   trailing stop, and a break-even that can be undone is not           |
//|   protection. IsImprovement() enforces this centrally so no           |
//|   individual method can get it wrong.                                |
//|                                                                  |
//|   STRUCTURE-BASED levels come from the Market Structure engine, which  |
//|   is why swings are injected rather than recomputed here.             |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_RISK_CPROTECTIONMANAGER_MQH
#define SRP_INTELLIGENCE_RISK_CPROTECTIONMANAGER_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "../Types/IntelligenceStructs.mqh"
#include "../Indicators/CStandardIndicators.mqh"
#include "../Structure/CSwingDetector.mqh"

class CProtectionManager
  {
private:
   string            m_symbol;
   ILogger          *m_logger;            // borrowed
   CAtrIntel        *m_atr;               // borrowed
   CSwingDetector   *m_swings;            // borrowed, optional

   //--- Instrument facts, refreshed on demand.
   double            m_point;
   int               m_digits;
   double            m_tick_size;
   int               m_stops_level;

   //--- Stop configuration.
   ENUM_SRP_STOP_MODEL m_stop_model;
   double            m_stop_fixed_points;
   double            m_stop_atr_multiple;
   double            m_stop_structure_buffer_points;
   double            m_stop_min_points;
   double            m_stop_max_points;

   //--- Target configuration.
   ENUM_SRP_TARGET_MODEL m_target_model;
   double            m_target_fixed_points;
   double            m_target_atr_multiple;
   double            m_target_risk_reward;

   //--- Break-even.
   bool              m_breakeven_enabled;
   double            m_breakeven_trigger_points;
   double            m_breakeven_offset_points;

   //--- Trailing.
   bool              m_trailing_enabled;
   bool              m_trailing_use_atr;
   double            m_trailing_start_points;
   double            m_trailing_distance_points;
   double            m_trailing_step_points;
   double            m_trailing_atr_multiple;

   //--- Profit lock: ratchet a fraction of peak profit as it accumulates.
   bool              m_profit_lock_enabled;
   double            m_profit_lock_trigger_points;
   double            m_profit_lock_fraction;

   bool              RefreshSpec(void);
   double            Normalize(const double price) const;
   //--- THE one-way gate. Central so no caller can bypass it.
   bool              IsImprovement(const bool is_buy,
                                   const double current_stop,
                                   const double candidate) const;
   bool              RespectsStopLevel(const double reference,
                                       const double level) const;

public:
                     CProtectionManager(const string symbol,
                                        CAtrIntel *atr,
                                        ILogger *logger);
                    ~CProtectionManager(void) { }

   void              SetSwingDetector(CSwingDetector *swings);

   //--- Configuration ------------------------------------------------
   void              ConfigureStop(const ENUM_SRP_STOP_MODEL model,
                                   const double fixed_points,
                                   const double atr_multiple);
   void              SetStopBounds(const double min_points,const double max_points);
   void              SetStructureBuffer(const double points);
   void              ConfigureTarget(const ENUM_SRP_TARGET_MODEL model,
                                     const double fixed_points,
                                     const double atr_multiple,
                                     const double risk_reward);
   void              ConfigureBreakEven(const bool enabled,
                                        const double trigger_points,
                                        const double offset_points);
   void              ConfigureTrailing(const bool enabled,
                                       const double start_points,
                                       const double distance_points,
                                       const double step_points);
   void              ConfigureAtrTrailing(const bool enabled,
                                          const double atr_multiple,
                                          const double step_points);
   void              ConfigureProfitLock(const bool enabled,
                                         const double trigger_points,
                                         const double lock_fraction);

   bool              Validate(SValidationResult &result) const;

   //=== ENTRY PLANNING ==============================================
   //--- Resolves stop and target for a prospective trade.
   bool              BuildPlan(const bool is_buy,
                               const double entry_price,
                               SProtectionPlan &plan);

   //--- Individual resolvers, exposed for targeted use.
   bool              ResolveStopDistance(const bool is_buy,
                                         const double entry_price,
                                         double &distance_points,
                                         string &explanation);
   bool              ResolveStopPrice(const bool is_buy,
                                      const double entry_price,
                                      double &stop_price,
                                      string &explanation);
   bool              ResolveTargetPrice(const bool is_buy,
                                        const double entry_price,
                                        const double stop_distance_points,
                                        double &target_price,
                                        string &explanation);

   //=== IN-TRADE MANAGEMENT =========================================
   //--- Break-even: move the stop to entry (plus offset) once profit
   //--- clears the trigger. Fires once; the caller tracks that via the
   //--- returned stage.
   bool              EvaluateBreakEven(const bool is_buy,
                                       const double entry_price,
                                       const double current_price,
                                       const double current_stop,
                                       SStopAdjustment &adjustment);

   //--- Trailing stop, fixed or ATR-scaled. The step threshold prevents
   //--- server spam: without it a tick-by-tick trail issues thousands of
   //--- modifications an hour, which brokers throttle.
   bool              EvaluateTrailing(const bool is_buy,
                                      const double entry_price,
                                      const double current_price,
                                      const double current_stop,
                                      SStopAdjustment &adjustment);

   //--- Profit lock: ratchets a FRACTION of peak profit, so a large
   //--- unrealised gain cannot be fully surrendered.
   bool              EvaluateProfitLock(const bool is_buy,
                                        const double entry_price,
                                        const double peak_price,
                                        const double current_stop,
                                        SStopAdjustment &adjustment);

   //--- Runs all three in priority order and returns the winning
   //--- adjustment. Capital preservation outranks profit optimisation,
   //--- so break-even is evaluated before trailing.
   bool              EvaluateAll(const bool is_buy,
                                 const double entry_price,
                                 const double current_price,
                                 const double peak_price,
                                 const double current_stop,
                                 SStopAdjustment &adjustment);

   //--- Dynamic stop: widens in high volatility, tightens in low, so the
   //--- stop adapts to regime rather than to a fixed point count.
   bool              ResolveDynamicStopPoints(double &distance_points,
                                              string &explanation);

   double            StopsLevelPoints(void) const { return((double)m_stops_level); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CProtectionManager::CProtectionManager(const string symbol,
                                       CAtrIntel *atr,
                                       ILogger *logger)
  : m_symbol(symbol),
    m_logger(logger),
    m_atr(atr),
    m_swings(NULL),
    m_point(0.0),
    m_digits(0),
    m_tick_size(0.0),
    m_stops_level(0),
    m_stop_model(SRP_STOP_FIXED_POINTS),
    m_stop_fixed_points(500.0),
    m_stop_atr_multiple(2.0),
    m_stop_structure_buffer_points(50.0),
    m_stop_min_points(0.0),
    m_stop_max_points(0.0),
    m_target_model(SRP_TARGET_RISK_REWARD),
    m_target_fixed_points(1000.0),
    m_target_atr_multiple(3.0),
    m_target_risk_reward(1.5),
    m_breakeven_enabled(false),
    m_breakeven_trigger_points(300.0),
    m_breakeven_offset_points(50.0),
    m_trailing_enabled(false),
    m_trailing_use_atr(false),
    m_trailing_start_points(400.0),
    m_trailing_distance_points(300.0),
    m_trailing_step_points(50.0),
    m_trailing_atr_multiple(1.5),
    m_profit_lock_enabled(false),
    m_profit_lock_trigger_points(600.0),
    m_profit_lock_fraction(0.5)
  {
   RefreshSpec();
  }
//+------------------------------------------------------------------+
void CProtectionManager::SetSwingDetector(CSwingDetector *swings)
  {
   m_swings=swings;
  }
//+------------------------------------------------------------------+
bool CProtectionManager::RefreshSpec(void)
  {
   m_point       = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   m_digits      = (int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
   m_tick_size   = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
   m_stops_level = (int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
   if(m_tick_size<=0.0)
      m_tick_size=m_point;
   return(m_point>0.0);
  }
//+------------------------------------------------------------------+
double CProtectionManager::Normalize(const double price) const
  {
   if(price<=0.0)
      return(0.0);
   //--- Tick size first, then digits: metals brokers often use a tick
   //--- size that is a multiple of point, and skipping this yields
   //--- prices the server rejects.
   const double ticked=CMathUtils::RoundToStep(price,m_tick_size);
   return(NormalizeDouble(ticked,m_digits));
  }
//+------------------------------------------------------------------+
bool CProtectionManager::IsImprovement(const bool is_buy,
                                       const double current_stop,
                                       const double candidate) const
  {
   if(candidate<=0.0)
      return(false);
   //--- No stop yet: any valid level is an improvement.
   if(current_stop<=0.0)
      return(true);
   //--- THE ONE-WAY RULE. A buy's stop may only rise; a sell's may only
   //--- fall. Everything else is rejected regardless of which method
   //--- proposed it.
   if(is_buy)
      return(candidate>current_stop+m_tick_size*0.5);
   return(candidate<current_stop-m_tick_size*0.5);
  }
//+------------------------------------------------------------------+
bool CProtectionManager::RespectsStopLevel(const double reference,
                                           const double level) const
  {
   if(level<=0.0 || m_stops_level<=0)
      return(true);
   const double distance=MathAbs(reference-level)/m_point;
   return(distance>=(double)m_stops_level);
  }
//+------------------------------------------------------------------+
void CProtectionManager::ConfigureStop(const ENUM_SRP_STOP_MODEL model,
                                       const double fixed_points,
                                       const double atr_multiple)
  {
   m_stop_model=model;
   if(fixed_points>0.0) m_stop_fixed_points=fixed_points;
   if(atr_multiple>0.0) m_stop_atr_multiple=atr_multiple;
  }
//+------------------------------------------------------------------+
void CProtectionManager::SetStopBounds(const double min_points,
                                       const double max_points)
  {
   m_stop_min_points=(min_points<0.0 ? 0.0 : min_points);
   m_stop_max_points=(max_points<0.0 ? 0.0 : max_points);
  }
//+------------------------------------------------------------------+
void CProtectionManager::SetStructureBuffer(const double points)
  {
   if(points>=0.0)
      m_stop_structure_buffer_points=points;
  }
//+------------------------------------------------------------------+
void CProtectionManager::ConfigureTarget(const ENUM_SRP_TARGET_MODEL model,
                                         const double fixed_points,
                                         const double atr_multiple,
                                         const double risk_reward)
  {
   m_target_model=model;
   if(fixed_points>0.0) m_target_fixed_points=fixed_points;
   if(atr_multiple>0.0) m_target_atr_multiple=atr_multiple;
   if(risk_reward>0.0)  m_target_risk_reward=risk_reward;
  }
//+------------------------------------------------------------------+
void CProtectionManager::ConfigureBreakEven(const bool enabled,
                                            const double trigger_points,
                                            const double offset_points)
  {
   m_breakeven_enabled=enabled;
   if(trigger_points>0.0) m_breakeven_trigger_points=trigger_points;
   if(offset_points>=0.0) m_breakeven_offset_points=offset_points;
  }
//+------------------------------------------------------------------+
void CProtectionManager::ConfigureTrailing(const bool enabled,
                                           const double start_points,
                                           const double distance_points,
                                           const double step_points)
  {
   m_trailing_enabled=enabled;
   m_trailing_use_atr=false;
   if(start_points>0.0)    m_trailing_start_points=start_points;
   if(distance_points>0.0) m_trailing_distance_points=distance_points;
   if(step_points>0.0)     m_trailing_step_points=step_points;
  }
//+------------------------------------------------------------------+
void CProtectionManager::ConfigureAtrTrailing(const bool enabled,
                                              const double atr_multiple,
                                              const double step_points)
  {
   m_trailing_enabled=enabled;
   m_trailing_use_atr=true;
   if(atr_multiple>0.0) m_trailing_atr_multiple=atr_multiple;
   if(step_points>0.0)  m_trailing_step_points=step_points;
  }
//+------------------------------------------------------------------+
void CProtectionManager::ConfigureProfitLock(const bool enabled,
                                             const double trigger_points,
                                             const double lock_fraction)
  {
   m_profit_lock_enabled=enabled;
   if(trigger_points>0.0) m_profit_lock_trigger_points=trigger_points;
   if(lock_fraction>0.0 && lock_fraction<1.0)
      m_profit_lock_fraction=lock_fraction;
  }
//+------------------------------------------------------------------+
bool CProtectionManager::ResolveDynamicStopPoints(double &distance_points,
                                                  string &explanation)
  {
   distance_points=0.0;
   if(m_atr==NULL)
     {
      explanation="dynamic stop requires ATR";
      return(false);
     }
   double atr_value=0.0;
   if(!m_atr.ValueAt(0,0,atr_value) || atr_value<=0.0)
     {
      explanation="ATR unavailable";
      return(false);
     }
   double average_atr=0.0;
   if(!m_atr.Average(0,1,20,average_atr) || average_atr<=0.0)
     {
      //--- No history for a regime comparison: fall back to a plain ATR
      //--- multiple rather than failing the trade.
      distance_points=atr_value*m_stop_atr_multiple/m_point;
      explanation="dynamic stop (no ATR history, plain multiple)";
      return(true);
     }

   //--- REGIME SCALING. In expanded volatility the stop widens beyond the
   //--- base multiple; in compressed volatility it tightens. Clamped so a
   //--- single ATR spike cannot produce an absurd stop.
   const double ratio=CMathUtils::Clamp(atr_value/average_atr,0.5,2.0);
   const double multiple=m_stop_atr_multiple*ratio;
   distance_points=atr_value*multiple/m_point;
   explanation=StringFormat("dynamic stop: ATR %.5f x %.2f (regime ratio %.2f)",
                            atr_value,multiple,ratio);
   return(true);
  }
//+------------------------------------------------------------------+
bool CProtectionManager::ResolveStopDistance(const bool is_buy,
                                             const double entry_price,
                                             double &distance_points,
                                             string &explanation)
  {
   distance_points=0.0;
   explanation="";
   RefreshSpec();

   switch(m_stop_model)
     {
      case SRP_STOP_NONE:
         explanation="no stop model configured";
         return(false);

      case SRP_STOP_FIXED_POINTS:
         distance_points=m_stop_fixed_points;
         explanation=StringFormat("fixed stop %.1f points",distance_points);
         break;

      case SRP_STOP_ATR_MULTIPLE:
        {
         if(m_atr==NULL)
           {
            explanation="ATR stop requires an ATR indicator";
            return(false);
           }
         double atr_value=0.0;
         if(!m_atr.ValueAt(0,0,atr_value) || atr_value<=0.0)
           {
            explanation="ATR value unavailable";
            return(false);
           }
         distance_points=atr_value*m_stop_atr_multiple/m_point;
         explanation=StringFormat("ATR stop %.5f x %.2f = %.1f points",
                                  atr_value,m_stop_atr_multiple,distance_points);
         break;
        }

      case SRP_STOP_STRUCTURE:
        {
         if(m_swings==NULL)
           {
            explanation="structure stop requires a swing detector";
            return(false);
           }
         //--- Place the stop beyond the swing that would invalidate the
         //--- trade thesis, plus a buffer so ordinary noise at the level
         //--- does not trigger it.
         SSwingPoint swing;
         const bool found=(is_buy ? m_swings.LastLow(swing)
                                  : m_swings.LastHigh(swing));
         if(!found || !swing.valid)
           {
            explanation="no confirmed swing for a structure stop";
            return(false);
           }
         const double buffer=m_stop_structure_buffer_points*m_point;
         const double level=(is_buy ? swing.price-buffer : swing.price+buffer);
         distance_points=MathAbs(entry_price-level)/m_point;
         explanation=StringFormat("structure stop beyond swing %.5f = %.1f points",
                                  swing.price,distance_points);
         break;
        }

      case SRP_STOP_DYNAMIC:
         if(!ResolveDynamicStopPoints(distance_points,explanation))
            return(false);
         break;
     }

   //--- Bounds, then the broker minimum. The broker floor is applied LAST
   //--- so it can never be undercut by the configured bounds.
   if(m_stop_min_points>0.0 && distance_points<m_stop_min_points)
     {
      distance_points=m_stop_min_points;
      explanation+=" [raised to min]";
     }
   if(m_stop_max_points>0.0 && distance_points>m_stop_max_points)
     {
      distance_points=m_stop_max_points;
      explanation+=" [capped at max]";
     }
   if(m_stops_level>0 && distance_points<(double)m_stops_level)
     {
      distance_points=(double)m_stops_level;
      explanation+=" [raised to broker stop level]";
     }

   return(distance_points>0.0);
  }
//+------------------------------------------------------------------+
bool CProtectionManager::ResolveStopPrice(const bool is_buy,
                                          const double entry_price,
                                          double &stop_price,
                                          string &explanation)
  {
   stop_price=0.0;
   double distance=0.0;
   if(!ResolveStopDistance(is_buy,entry_price,distance,explanation))
      return(false);
   const double offset=distance*m_point;
   stop_price=Normalize(is_buy ? entry_price-offset : entry_price+offset);
   return(stop_price>0.0);
  }
//+------------------------------------------------------------------+
bool CProtectionManager::ResolveTargetPrice(const bool is_buy,
                                            const double entry_price,
                                            const double stop_distance_points,
                                            double &target_price,
                                            string &explanation)
  {
   target_price=0.0;
   explanation="";
   RefreshSpec();

   double distance_points=0.0;

   switch(m_target_model)
     {
      case SRP_TARGET_NONE:
         explanation="no target model configured";
         return(false);

      case SRP_TARGET_FIXED_POINTS:
         distance_points=m_target_fixed_points;
         explanation=StringFormat("fixed target %.1f points",distance_points);
         break;

      case SRP_TARGET_ATR_MULTIPLE:
        {
         if(m_atr==NULL)
           {
            explanation="ATR target requires an ATR indicator";
            return(false);
           }
         double atr_value=0.0;
         if(!m_atr.ValueAt(0,0,atr_value) || atr_value<=0.0)
           {
            explanation="ATR value unavailable";
            return(false);
           }
         distance_points=atr_value*m_target_atr_multiple/m_point;
         explanation=StringFormat("ATR target %.5f x %.2f",
                                  atr_value,m_target_atr_multiple);
         break;
        }

      case SRP_TARGET_RISK_REWARD:
         //--- Derived from the STOP, which is why the stop distance is a
         //--- parameter rather than recomputed here. Making the
         //--- dependency explicit avoids a cycle between the two methods.
         if(stop_distance_points<=0.0)
           {
            explanation="risk-reward target requires a stop distance";
            return(false);
           }
         distance_points=stop_distance_points*m_target_risk_reward;
         explanation=StringFormat("target %.1f R:R x %.1f stop points",
                                  m_target_risk_reward,stop_distance_points);
         break;

      case SRP_TARGET_STRUCTURE:
        {
         if(m_swings==NULL)
           {
            explanation="structure target requires a swing detector";
            return(false);
           }
         //--- Target the opposing liquidity: the next swing in the
         //--- direction of the trade.
         SSwingPoint swing;
         const bool found=(is_buy ? m_swings.LastHigh(swing)
                                  : m_swings.LastLow(swing));
         if(!found || !swing.valid)
           {
            explanation="no confirmed swing for a structure target";
            return(false);
           }
         distance_points=MathAbs(swing.price-entry_price)/m_point;
         if(distance_points<=0.0)
           {
            explanation="structure target coincides with entry";
            return(false);
           }
         explanation=StringFormat("structure target at swing %.5f",swing.price);
         break;
        }

      case SRP_TARGET_DYNAMIC:
        {
         if(stop_distance_points<=0.0)
           {
            explanation="dynamic target requires a stop distance";
            return(false);
           }
         //--- Scale the reward ratio with volatility expansion: wider
         //--- ranges justify more ambitious targets.
         double ratio=1.0;
         if(m_atr!=NULL)
           {
            double atr_value=0.0,average=0.0;
            if(m_atr.ValueAt(0,0,atr_value) && atr_value>0.0 &&
               m_atr.Average(0,1,20,average) && average>0.0)
               ratio=CMathUtils::Clamp(atr_value/average,0.7,1.8);
           }
         distance_points=stop_distance_points*m_target_risk_reward*ratio;
         explanation=StringFormat("dynamic target %.1f R:R x %.2f volatility",
                                  m_target_risk_reward,ratio);
         break;
        }
     }

   if(distance_points<=0.0)
      return(false);
   //--- Honour the broker floor for targets too.
   if(m_stops_level>0 && distance_points<(double)m_stops_level)
     {
      distance_points=(double)m_stops_level;
      explanation+=" [raised to broker stop level]";
     }

   const double offset=distance_points*m_point;
   target_price=Normalize(is_buy ? entry_price+offset : entry_price-offset);
   return(target_price>0.0);
  }
//+------------------------------------------------------------------+
bool CProtectionManager::BuildPlan(const bool is_buy,
                                   const double entry_price,
                                   SProtectionPlan &plan)
  {
   plan.Reset();
   if(entry_price<=0.0)
      return(false);
   RefreshSpec();

   //--- STOP FIRST: the risk-reward target depends on it.
   string stop_explanation="";
   double stop_distance=0.0;
   if(ResolveStopDistance(is_buy,entry_price,stop_distance,stop_explanation))
     {
      const double offset=stop_distance*m_point;
      plan.stop_price=Normalize(is_buy ? entry_price-offset : entry_price+offset);
      plan.has_stop=(plan.stop_price>0.0);
      plan.stop_distance_points=stop_distance;
      plan.stop_model=m_stop_model;
     }
   plan.explanation=stop_explanation;

   //--- TARGET SECOND, using the resolved stop distance.
   string target_explanation="";
   double target_price=0.0;
   if(ResolveTargetPrice(is_buy,entry_price,stop_distance,
                         target_price,target_explanation))
     {
      plan.target_price=target_price;
      plan.has_target=(target_price>0.0);
      plan.target_distance_points=MathAbs(target_price-entry_price)/m_point;
      plan.target_model=m_target_model;
     }
   plan.explanation+=" | "+target_explanation;

   //--- Report the achieved ratio so the caller can veto a poor one.
   if(plan.has_stop && plan.has_target && plan.stop_distance_points>0.0)
      plan.reward_risk_ratio=plan.target_distance_points/plan.stop_distance_points;

   return(plan.has_stop || plan.has_target);
  }
//+------------------------------------------------------------------+
bool CProtectionManager::EvaluateBreakEven(const bool is_buy,
                                           const double entry_price,
                                           const double current_price,
                                           const double current_stop,
                                           SStopAdjustment &adjustment)
  {
   adjustment.Reset();
   if(!m_breakeven_enabled || entry_price<=0.0 || current_price<=0.0)
      return(false);
   RefreshSpec();

   const double profit_points=(is_buy ? current_price-entry_price
                                      : entry_price-current_price)/m_point;
   if(profit_points<m_breakeven_trigger_points)
      return(false);

   //--- Lock a few points beyond entry rather than exactly at it, so
   //--- commission and spread do not turn a "break-even" exit into a
   //--- small loss.
   const double offset=m_breakeven_offset_points*m_point;
   const double candidate=Normalize(is_buy ? entry_price+offset
                                           : entry_price-offset);

   if(!IsImprovement(is_buy,current_stop,candidate))
      return(false);
   if(!RespectsStopLevel(current_price,candidate))
      return(false);

   adjustment.adjust         = true;
   adjustment.new_stop_price = candidate;
   adjustment.stage          = SRP_PROTECTION_BREAK_EVEN;
   adjustment.reason         = StringFormat("break-even at +%.1f points (profit %.1f)",
                                            m_breakeven_offset_points,profit_points);
   return(true);
  }
//+------------------------------------------------------------------+
bool CProtectionManager::EvaluateTrailing(const bool is_buy,
                                          const double entry_price,
                                          const double current_price,
                                          const double current_stop,
                                          SStopAdjustment &adjustment)
  {
   adjustment.Reset();
   if(!m_trailing_enabled || current_price<=0.0)
      return(false);
   RefreshSpec();

   const double profit_points=(is_buy ? current_price-entry_price
                                      : entry_price-current_price)/m_point;
   if(profit_points<m_trailing_start_points)
      return(false);

   //--- Resolve the trail distance for the configured mode.
   double distance_points=m_trailing_distance_points;
   string mode="fixed";
   if(m_trailing_use_atr)
     {
      if(m_atr==NULL)
         return(false);
      double atr_value=0.0;
      if(!m_atr.ValueAt(0,0,atr_value) || atr_value<=0.0)
         return(false);
      distance_points=atr_value*m_trailing_atr_multiple/m_point;
      mode="ATR";
     }
   if(distance_points<=0.0)
      return(false);
   if(m_stops_level>0 && distance_points<(double)m_stops_level)
      distance_points=(double)m_stops_level;

   const double offset=distance_points*m_point;
   const double candidate=Normalize(is_buy ? current_price-offset
                                           : current_price+offset);

   //--- STEP THRESHOLD. Without this a busy M1 stream would issue a
   //--- modification on nearly every tick, which brokers throttle and
   //--- which shows up to the user as unexplained latency.
   if(current_stop>0.0)
     {
      const double advance=MathAbs(candidate-current_stop)/m_point;
      if(advance<m_trailing_step_points)
         return(false);
     }

   if(!IsImprovement(is_buy,current_stop,candidate))
      return(false);
   if(!RespectsStopLevel(current_price,candidate))
      return(false);

   adjustment.adjust         = true;
   adjustment.new_stop_price = candidate;
   adjustment.stage          = SRP_PROTECTION_TRAILING;
   adjustment.reason         = StringFormat("%s trail %.1f points behind price",
                                            mode,distance_points);
   return(true);
  }
//+------------------------------------------------------------------+
bool CProtectionManager::EvaluateProfitLock(const bool is_buy,
                                            const double entry_price,
                                            const double peak_price,
                                            const double current_stop,
                                            SStopAdjustment &adjustment)
  {
   adjustment.Reset();
   if(!m_profit_lock_enabled || peak_price<=0.0 || entry_price<=0.0)
      return(false);
   RefreshSpec();

   //--- Measured against the PEAK, not the current price: the purpose is
   //--- to protect the best profit the trade has achieved, which is what
   //--- distinguishes this from a trailing stop.
   const double peak_profit_points=(is_buy ? peak_price-entry_price
                                           : entry_price-peak_price)/m_point;
   if(peak_profit_points<m_profit_lock_trigger_points)
      return(false);

   //--- Lock a fraction of the peak gain.
   const double locked_points=peak_profit_points*m_profit_lock_fraction;
   const double offset=locked_points*m_point;
   const double candidate=Normalize(is_buy ? entry_price+offset
                                           : entry_price-offset);

   if(!IsImprovement(is_buy,current_stop,candidate))
      return(false);

   adjustment.adjust         = true;
   adjustment.new_stop_price = candidate;
   adjustment.stage          = SRP_PROTECTION_LOCKED;
   adjustment.reason         = StringFormat("profit lock: %.0f%% of %.1f peak points",
                                            m_profit_lock_fraction*100.0,
                                            peak_profit_points);
   return(true);
  }
//+------------------------------------------------------------------+
bool CProtectionManager::EvaluateAll(const bool is_buy,
                                     const double entry_price,
                                     const double current_price,
                                     const double peak_price,
                                     const double current_stop,
                                     SStopAdjustment &adjustment)
  {
   adjustment.Reset();

   //--- PRIORITY ORDER, and it is deliberate.
   //--- Profit lock first: it protects the largest achieved gain and
   //--- therefore proposes the most protective stop. Break-even next.
   //--- Trailing last, because it optimises rather than protects.
   //--- Each candidate must still pass IsImprovement, so whichever
   //--- proposes the safest stop effectively wins.
   SStopAdjustment candidate;

   if(EvaluateProfitLock(is_buy,entry_price,peak_price,current_stop,candidate))
     {
      adjustment=candidate;
      return(true);
     }
   if(EvaluateBreakEven(is_buy,entry_price,current_price,current_stop,candidate))
     {
      adjustment=candidate;
      return(true);
     }
   if(EvaluateTrailing(is_buy,entry_price,current_price,current_stop,candidate))
     {
      adjustment=candidate;
      return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
bool CProtectionManager::Validate(SValidationResult &result) const
  {
   if(m_point<=0.0)
     {
      result.AddError("CProtectionManager: invalid symbol point value");
      return(false);
     }
   if((m_stop_model==SRP_STOP_ATR_MULTIPLE ||
       m_stop_model==SRP_STOP_DYNAMIC) && m_atr==NULL)
     {
      result.AddError("CProtectionManager: ATR-based stop configured without an ATR indicator");
      return(false);
     }
   if(m_stop_model==SRP_STOP_STRUCTURE && m_swings==NULL)
     {
      result.AddError("CProtectionManager: structure stop configured without a swing detector");
      return(false);
     }
   //--- Cross-field coherence: a trail step wider than its distance can
   //--- never fire, which is a silent misconfiguration.
   if(m_trailing_enabled && m_trailing_step_points>m_trailing_distance_points)
      result.AddWarning("CProtectionManager: trailing step exceeds trailing distance");
   if(m_breakeven_enabled && m_trailing_enabled &&
      m_breakeven_trigger_points>m_trailing_start_points)
      result.AddWarning("CProtectionManager: trailing starts before break-even triggers");
   if(m_stop_model==SRP_STOP_NONE)
      result.AddWarning("CProtectionManager: no stop model configured");
   if(m_stop_max_points>0.0 && m_stop_min_points>m_stop_max_points)
      result.AddError("CProtectionManager: stop min exceeds stop max");
   return(true);
  }
//+------------------------------------------------------------------+
string CProtectionManager::Describe(void) const
  {
   return(StringFormat("protection: stop=%d target=%d BE=%s trail=%s lock=%s "
                       "stopsLevel=%d",
                       (int)m_stop_model,(int)m_target_model,
                       (m_breakeven_enabled ? "on" : "off"),
                       (m_trailing_enabled ? (m_trailing_use_atr ? "ATR" : "fixed") : "off"),
                       (m_profit_lock_enabled ? "on" : "off"),
                       m_stops_level));
  }

#endif // SRP_INTELLIGENCE_RISK_CPROTECTIONMANAGER_MQH
//+------------------------------------------------------------------+
