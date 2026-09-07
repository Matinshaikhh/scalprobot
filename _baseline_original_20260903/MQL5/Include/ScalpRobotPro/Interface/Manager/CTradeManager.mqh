//+------------------------------------------------------------------+
//|                                              CTradeManager.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   RESPONSIBILITY (one only): decide what should happen to each open     |
//|   position, and return that as an intent.                             |
//|                                                                  |
//|   IT DECIDES; IT DOES NOT EXECUTE. Every method returns an             |
//|   STradeIntent. Sending the order is the Phase 1 trade engine's job.   |
//|   That separation is what lets all of this be verified without a       |
//|   broker connection, and it is why this class has no pointer to any    |
//|   executor.                                                          |
//|                                                                  |
//|   Features: Break Even · Trailing Stop · ATR Exit · Time Exit ·        |
//|   Emergency Exit · Scale In · Scale Out · Reverse · Max Holding Time.  |
//|                                                                  |
//|   THE ONE-WAY RULE for stops is enforced centrally in IsBetterStop(),  |
//|   so no individual rule can propose a stop that moves against the      |
//|   position. A trailing stop that can retreat is not a trailing stop.   |
//|                                                                  |
//|   PRIORITY ORDER is deliberate and fixed:                             |
//|     emergency > max-hold > time exit > ATR exit > scale out >          |
//|     profit protection (break-even / trail) > scale in                 |
//|   Capital preservation outranks profit optimisation, and adding        |
//|   exposure is always considered last.                                 |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_MANAGER_CTRADEMANAGER_MQH
#define SRP_INTERFACE_MANAGER_CTRADEMANAGER_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "../../Intelligence/Indicators/CStandardIndicators.mqh"
#include "../Types/InterfaceStructs.mqh"

#define SRP_TM_MAX_TRACKED 32

class CTradeManager
  {
private:
   string            m_symbol;
   ILogger          *m_logger;            // borrowed
   CAtrIntel        *m_atr;               // borrowed, optional

   double            m_point;
   int               m_digits;
   double            m_tick_size;
   int               m_stops_level;

   //--- Break-even.
   bool              m_be_enabled;
   double            m_be_trigger_points;
   double            m_be_offset_points;
   //--- Trailing.
   bool              m_trail_enabled;
   bool              m_trail_use_atr;
   double            m_trail_start_points;
   double            m_trail_distance_points;
   double            m_trail_step_points;
   double            m_trail_atr_multiple;
   //--- ATR exit: close when price retraces N ATR from the peak.
   bool              m_atr_exit_enabled;
   double            m_atr_exit_multiple;
   //--- Time-based exits.
   bool              m_time_exit_enabled;
   int               m_time_exit_minutes;
   bool              m_time_exit_only_if_losing;
   bool              m_max_hold_enabled;
   int               m_max_hold_minutes;
   //--- Emergency.
   bool              m_emergency_armed;
   string            m_emergency_reason;
   //--- Scale in.
   bool              m_scale_in_enabled;
   double            m_scale_in_trigger_points;
   double            m_scale_in_fraction;
   int               m_scale_in_max;
   //--- Scale out.
   bool              m_scale_out_enabled;
   double            m_scale_out_trigger_points;
   double            m_scale_out_fraction;
   int               m_scale_out_max;
   double            m_broker_volume_min;
   double            m_broker_volume_step;
   //--- Reverse.
   bool              m_reverse_enabled;

   //--- Tracked state, keyed by ticket. The manager must remember peak
   //--- excursion and which stages have fired, because a position object
   //--- from the broker carries none of that.
   SManagedPosition  m_tracked[SRP_TM_MAX_TRACKED];
   int               m_tracked_count;

   long              m_intents_issued;

   bool              RefreshSpec(void);
   double            Normalize(const double price) const;
   //--- THE one-way gate for every stop proposal.
   bool              IsBetterStop(const bool is_buy,const double current_stop,
                                  const double candidate) const;
   bool              RespectsStopLevel(const double reference,
                                       const double level) const;
   int               FindTracked(const ulong ticket) const;

   //--- Individual evaluators, each returning an intent or none.
   bool              EvalEmergency(const SManagedPosition &position,
                                   STradeIntent &intent) const;
   bool              EvalMaxHold(const SManagedPosition &position,
                                 STradeIntent &intent) const;
   bool              EvalTimeExit(const SManagedPosition &position,
                                  STradeIntent &intent) const;
   bool              EvalAtrExit(const SManagedPosition &position,
                                 STradeIntent &intent) const;
   bool              EvalScaleOut(const SManagedPosition &position,
                                  STradeIntent &intent) const;
   bool              EvalBreakEven(const SManagedPosition &position,
                                   STradeIntent &intent) const;
   bool              EvalTrailing(const SManagedPosition &position,
                                  STradeIntent &intent) const;
   bool              EvalScaleIn(const SManagedPosition &position,
                                 STradeIntent &intent) const;

public:
                     CTradeManager(const string symbol,CAtrIntel *atr,
                                   ILogger *logger);
                    ~CTradeManager(void) { }

   //--- Configuration ------------------------------------------------
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
   void              ConfigureAtrExit(const bool enabled,
                                      const double atr_multiple);
   void              ConfigureTimeExit(const bool enabled,const int minutes,
                                       const bool only_if_losing);
   void              ConfigureMaxHold(const bool enabled,const int minutes);
   void              ConfigureScaleIn(const bool enabled,
                                      const double trigger_points,
                                      const double fraction,
                                      const int max_adds);
   void              ConfigureScaleOut(const bool enabled,
                                       const double trigger_points,
                                       const double fraction,
                                       const int max_reductions);
   void              ConfigureReverse(const bool enabled)
     { m_reverse_enabled=enabled; }
   void              SetBrokerVolumeLimits(const double volume_min,
                                           const double volume_step);

   //--- Emergency is armed externally by a risk guard or the operator and
   //--- overrides every other consideration until disarmed.
   void              ArmEmergency(const string reason);
   void              DisarmEmergency(void);
   bool              IsEmergencyArmed(void) const { return(m_emergency_armed); }

   bool              Validate(SValidationResult &result) const;

   //=== TRACKING =====================================================
   //--- Updates peak excursion and stage flags. Must be called once per
   //--- pass per position BEFORE Evaluate, since the ATR exit and profit
   //--- lock both measure from the peak.
   bool              Track(const SManagedPosition &position);
   void              Untrack(const ulong ticket);
   void              UntrackAll(void);
   bool              GetTracked(const ulong ticket,SManagedPosition &out) const;
   int               TrackedCount(void) const { return(m_tracked_count); }

   //=== DECISION =====================================================
   //--- Returns the single highest-priority intent for this position.
   bool              Evaluate(const SManagedPosition &position,
                              STradeIntent &intent);
   //--- Explicit reversal request, used when the decision engine flips
   //--- direction while a position is open.
   bool              RequestReverse(const SManagedPosition &position,
                                    const double new_volume,
                                    const string reason,
                                    STradeIntent &intent) const;
   //--- Flatten-everything intent for a kill switch.
   bool              RequestEmergencyExit(const SManagedPosition &position,
                                          STradeIntent &intent) const;

   //--- Confirmation callbacks. The host calls these after the trade
   //--- engine reports success, so stage flags reflect reality rather
   //--- than intent.
   void              NotifyStopMoved(const ulong ticket,const double new_stop,
                                     const ENUM_SRP_TM_TRIGGER trigger);
   void              NotifyScaledIn(const ulong ticket);
   void              NotifyScaledOut(const ulong ticket);

   long              IntentCount(void) const { return(m_intents_issued); }
   string            Describe(void) const;
   static string     ActionToString(const ENUM_SRP_TM_ACTION action);
   static string     TriggerToString(const ENUM_SRP_TM_TRIGGER trigger);
  };

//+------------------------------------------------------------------+
CTradeManager::CTradeManager(const string symbol,CAtrIntel *atr,
                             ILogger *logger)
  : m_symbol(symbol),
    m_logger(logger),
    m_atr(atr),
    m_point(0.0),
    m_digits(0),
    m_tick_size(0.0),
    m_stops_level(0),
    m_be_enabled(false),
    m_be_trigger_points(300.0),
    m_be_offset_points(50.0),
    m_trail_enabled(false),
    m_trail_use_atr(false),
    m_trail_start_points(400.0),
    m_trail_distance_points(300.0),
    m_trail_step_points(50.0),
    m_trail_atr_multiple(1.5),
    m_atr_exit_enabled(false),
    m_atr_exit_multiple(2.0),
    m_time_exit_enabled(false),
    m_time_exit_minutes(120),
    m_time_exit_only_if_losing(true),
    m_max_hold_enabled(false),
    m_max_hold_minutes(480),
    m_emergency_armed(false),
    m_emergency_reason(""),
    m_scale_in_enabled(false),
    m_scale_in_trigger_points(500.0),
    m_scale_in_fraction(0.5),
    m_scale_in_max(1),
    m_scale_out_enabled(false),
    m_scale_out_trigger_points(400.0),
    m_scale_out_fraction(0.5),
    m_scale_out_max(1),
    m_broker_volume_min(0.01),
    m_broker_volume_step(0.01),
    m_reverse_enabled(false),
    m_tracked_count(0),
    m_intents_issued(0)
  {
   RefreshSpec();
  }
//+------------------------------------------------------------------+
bool CTradeManager::RefreshSpec(void)
  {
   m_point       = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   m_digits      = (int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
   m_tick_size   = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
   m_stops_level = (int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
   const double vmin=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
   const double vstep=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
   if(vmin>0.0)  m_broker_volume_min=vmin;
   if(vstep>0.0) m_broker_volume_step=vstep;
   if(m_tick_size<=0.0)
      m_tick_size=m_point;
   return(m_point>0.0);
  }
//+------------------------------------------------------------------+
double CTradeManager::Normalize(const double price) const
  {
   if(price<=0.0)
      return(0.0);
   //--- Tick size first, then digits: on metals a tick size that is a
   //--- multiple of point makes the naive rounding produce prices the
   //--- server rejects.
   const double ticked=CMathUtils::RoundToStep(price,m_tick_size);
   return(NormalizeDouble(ticked,m_digits));
  }
//+------------------------------------------------------------------+
bool CTradeManager::IsBetterStop(const bool is_buy,const double current_stop,
                                 const double candidate) const
  {
   if(candidate<=0.0)
      return(false);
   if(current_stop<=0.0)
      return(true);                       // no stop yet: any is better
   //--- THE ONE-WAY RULE. A buy's stop may only rise; a sell's only fall.
   //--- Half a tick of tolerance prevents no-op churn from rounding.
   if(is_buy)
      return(candidate>current_stop+m_tick_size*0.5);
   return(candidate<current_stop-m_tick_size*0.5);
  }
//+------------------------------------------------------------------+
bool CTradeManager::RespectsStopLevel(const double reference,
                                      const double level) const
  {
   if(level<=0.0 || m_stops_level<=0 || m_point<=0.0)
      return(true);
   return(MathAbs(reference-level)/m_point>=(double)m_stops_level);
  }
//+------------------------------------------------------------------+
void CTradeManager::ConfigureBreakEven(const bool enabled,
                                       const double trigger_points,
                                       const double offset_points)
  {
   m_be_enabled=enabled;
   if(trigger_points>0.0) m_be_trigger_points=trigger_points;
   if(offset_points>=0.0) m_be_offset_points=offset_points;
  }
//+------------------------------------------------------------------+
void CTradeManager::ConfigureTrailing(const bool enabled,
                                      const double start_points,
                                      const double distance_points,
                                      const double step_points)
  {
   m_trail_enabled=enabled;
   m_trail_use_atr=false;
   if(start_points>0.0)    m_trail_start_points=start_points;
   if(distance_points>0.0) m_trail_distance_points=distance_points;
   if(step_points>0.0)     m_trail_step_points=step_points;
  }
//+------------------------------------------------------------------+
void CTradeManager::ConfigureAtrTrailing(const bool enabled,
                                         const double atr_multiple,
                                         const double step_points)
  {
   m_trail_enabled=enabled;
   m_trail_use_atr=true;
   if(atr_multiple>0.0) m_trail_atr_multiple=atr_multiple;
   if(step_points>0.0)  m_trail_step_points=step_points;
  }
//+------------------------------------------------------------------+
void CTradeManager::ConfigureAtrExit(const bool enabled,
                                     const double atr_multiple)
  {
   m_atr_exit_enabled=enabled;
   if(atr_multiple>0.0) m_atr_exit_multiple=atr_multiple;
  }
//+------------------------------------------------------------------+
void CTradeManager::ConfigureTimeExit(const bool enabled,const int minutes,
                                      const bool only_if_losing)
  {
   m_time_exit_enabled=enabled;
   if(minutes>0) m_time_exit_minutes=minutes;
   m_time_exit_only_if_losing=only_if_losing;
  }
//+------------------------------------------------------------------+
void CTradeManager::ConfigureMaxHold(const bool enabled,const int minutes)
  {
   m_max_hold_enabled=enabled;
   if(minutes>0) m_max_hold_minutes=minutes;
  }
//+------------------------------------------------------------------+
void CTradeManager::ConfigureScaleIn(const bool enabled,
                                     const double trigger_points,
                                     const double fraction,
                                     const int max_adds)
  {
   m_scale_in_enabled=enabled;
   if(trigger_points>0.0)          m_scale_in_trigger_points=trigger_points;
   if(fraction>0.0 && fraction<=2.0) m_scale_in_fraction=fraction;
   if(max_adds>=1)                 m_scale_in_max=max_adds;
  }
//+------------------------------------------------------------------+
void CTradeManager::ConfigureScaleOut(const bool enabled,
                                      const double trigger_points,
                                      const double fraction,
                                      const int max_reductions)
  {
   m_scale_out_enabled=enabled;
   if(trigger_points>0.0)           m_scale_out_trigger_points=trigger_points;
   if(fraction>0.0 && fraction<1.0) m_scale_out_fraction=fraction;
   if(max_reductions>=1)            m_scale_out_max=max_reductions;
  }
//+------------------------------------------------------------------+
void CTradeManager::SetBrokerVolumeLimits(const double volume_min,
                                          const double volume_step)
  {
   if(volume_min>0.0)  m_broker_volume_min=volume_min;
   if(volume_step>0.0) m_broker_volume_step=volume_step;
  }
//+------------------------------------------------------------------+
void CTradeManager::ArmEmergency(const string reason)
  {
   if(m_emergency_armed)
      return;
   m_emergency_armed=true;
   m_emergency_reason=reason;
   if(m_logger!=NULL)
      m_logger.Warn("CTradeManager","emergency armed: "+reason);
  }
//+------------------------------------------------------------------+
void CTradeManager::DisarmEmergency(void)
  {
   if(!m_emergency_armed)
      return;
   m_emergency_armed=false;
   m_emergency_reason="";
   if(m_logger!=NULL)
      m_logger.Info("CTradeManager","emergency disarmed");
  }
//+------------------------------------------------------------------+
int CTradeManager::FindTracked(const ulong ticket) const
  {
   for(int i=0;i<m_tracked_count;i++)
      if(m_tracked[i].ticket==ticket)
         return(i);
   return(-1);
  }
//+------------------------------------------------------------------+
bool CTradeManager::Track(const SManagedPosition &position)
  {
   if(position.ticket==SRP_INVALID_TICKET)
      return(false);

   int index=FindTracked(position.ticket);
   if(index<0)
     {
      if(m_tracked_count>=SRP_TM_MAX_TRACKED)
         return(false);
      index=m_tracked_count;
      m_tracked_count++;
      //--- First sight: seed peak at the current price so a position that
      //--- immediately moves against us has a sane baseline.
      m_tracked[index]=position;
      m_tracked[index].peak_price=position.current_price;
      m_tracked[index].peak_profit_points=position.profit_points;
      m_tracked[index].break_even_done=false;
      m_tracked[index].scaled_in=false;
      m_tracked[index].scale_out_count=0;
      m_tracked[index].trailing_active=false;
      if(m_tracked[index].initial_volume<=0.0)
         m_tracked[index].initial_volume=position.volume;
      return(true);
     }

   //--- Preserve manager-maintained fields; refresh broker-owned ones.
   const double peak_price=m_tracked[index].peak_price;
   const double peak_points=m_tracked[index].peak_profit_points;
   const bool be_done=m_tracked[index].break_even_done;
   const bool scaled_in=m_tracked[index].scaled_in;
   const int scale_outs=m_tracked[index].scale_out_count;
   const bool trailing=m_tracked[index].trailing_active;
   const double initial=m_tracked[index].initial_volume;

   m_tracked[index]=position;
   m_tracked[index].break_even_done=be_done;
   m_tracked[index].scaled_in=scaled_in;
   m_tracked[index].scale_out_count=scale_outs;
   m_tracked[index].trailing_active=trailing;
   m_tracked[index].initial_volume=(initial>0.0 ? initial : position.volume);

   //--- PEAK TRACKING. Monotonic in the favourable direction only; this
   //--- is what the ATR exit and profit protection measure against.
   if(position.is_buy)
      m_tracked[index].peak_price=MathMax(peak_price,position.current_price);
   else
      m_tracked[index].peak_price=(peak_price<=0.0
                                   ? position.current_price
                                   : MathMin(peak_price,position.current_price));
   m_tracked[index].peak_profit_points=MathMax(peak_points,
                                               position.profit_points);
   return(true);
  }
//+------------------------------------------------------------------+
void CTradeManager::Untrack(const ulong ticket)
  {
   const int index=FindTracked(ticket);
   if(index<0)
      return;
   for(int i=index;i<m_tracked_count-1;i++)
      m_tracked[i]=m_tracked[i+1];
   m_tracked_count--;
  }
//+------------------------------------------------------------------+
void CTradeManager::UntrackAll(void)
  {
   m_tracked_count=0;
  }
//+------------------------------------------------------------------+
bool CTradeManager::GetTracked(const ulong ticket,SManagedPosition &out) const
  {
   out.Reset();
   const int index=FindTracked(ticket);
   if(index<0)
      return(false);
   out=m_tracked[index];
   return(true);
  }
//+------------------------------------------------------------------+
bool CTradeManager::EvalEmergency(const SManagedPosition &position,
                                  STradeIntent &intent) const
  {
   if(!m_emergency_armed)
      return(false);
   //--- Unconditional. No profit, time or volatility consideration
   //--- overrides an armed emergency.
   intent.action  = SRP_TM_CLOSE_FULL;
   intent.trigger = SRP_TM_TRIGGER_EMERGENCY;
   intent.ticket  = position.ticket;
   intent.volume  = position.volume;
   intent.reason  = "emergency exit: "+m_emergency_reason;
   intent.urgency = 1.0;
   return(true);
  }
//+------------------------------------------------------------------+
bool CTradeManager::EvalMaxHold(const SManagedPosition &position,
                                STradeIntent &intent) const
  {
   if(!m_max_hold_enabled || m_max_hold_minutes<=0)
      return(false);
   if(position.age_seconds<m_max_hold_minutes*60)
      return(false);
   //--- A hard ceiling regardless of profit. Beyond this the position is
   //--- no longer the trade that was analysed.
   intent.action  = SRP_TM_CLOSE_FULL;
   intent.trigger = SRP_TM_TRIGGER_MAX_HOLD;
   intent.ticket  = position.ticket;
   intent.volume  = position.volume;
   intent.reason  = StringFormat("maximum holding time %d min exceeded (%d min)",
                                 m_max_hold_minutes,position.age_seconds/60);
   intent.urgency = 0.9;
   return(true);
  }
//+------------------------------------------------------------------+
bool CTradeManager::EvalTimeExit(const SManagedPosition &position,
                                 STradeIntent &intent) const
  {
   if(!m_time_exit_enabled || m_time_exit_minutes<=0)
      return(false);
   if(position.age_seconds<m_time_exit_minutes*60)
      return(false);
   //--- Optionally spare winners: a trade working in our favour has not
   //--- invalidated its thesis merely by taking time.
   if(m_time_exit_only_if_losing && position.profit_money>=0.0)
      return(false);

   intent.action  = SRP_TM_CLOSE_FULL;
   intent.trigger = SRP_TM_TRIGGER_TIME_EXIT;
   intent.ticket  = position.ticket;
   intent.volume  = position.volume;
   intent.reason  = StringFormat("time exit after %d min%s",
                                 position.age_seconds/60,
                                 (m_time_exit_only_if_losing ? " (losing)" : ""));
   intent.urgency = 0.7;
   return(true);
  }
//+------------------------------------------------------------------+
bool CTradeManager::EvalAtrExit(const SManagedPosition &position,
                                STradeIntent &intent) const
  {
   if(!m_atr_exit_enabled || m_atr==NULL || m_point<=0.0)
      return(false);
   double atr=0.0;
   if(!m_atr.ValueAt(0,0,atr) || atr<=0.0)
      return(false);
   if(position.peak_price<=0.0)
      return(false);

   //--- Retracement from the PEAK, not from entry. Measuring from entry
   //--- would make this a plain stop; measuring from the peak makes it a
   //--- volatility-scaled giveback limit.
   const double giveback=(position.is_buy
                          ? position.peak_price-position.current_price
                          : position.current_price-position.peak_price);
   if(giveback<=0.0)
      return(false);
   const double threshold=atr*m_atr_exit_multiple;
   if(giveback<threshold)
      return(false);
   //--- Only meaningful once the trade actually had profit to give back.
   if(position.peak_profit_points<=0.0)
      return(false);

   intent.action  = SRP_TM_CLOSE_FULL;
   intent.trigger = SRP_TM_TRIGGER_ATR_EXIT;
   intent.ticket  = position.ticket;
   intent.volume  = position.volume;
   intent.reason  = StringFormat("ATR exit: gave back %.1f pts (%.1f x ATR) "
                                 "from peak",
                                 giveback/m_point,m_atr_exit_multiple);
   intent.urgency = 0.75;
   return(true);
  }
//+------------------------------------------------------------------+
bool CTradeManager::EvalScaleOut(const SManagedPosition &position,
                                 STradeIntent &intent) const
  {
   if(!m_scale_out_enabled)
      return(false);
   if(position.scale_out_count>=m_scale_out_max)
      return(false);
   if(position.profit_points<m_scale_out_trigger_points)
      return(false);

   double close_volume=position.volume*m_scale_out_fraction;
   //--- Floor to a legal step.
   close_volume=CMathUtils::FloorToStep(close_volume,m_broker_volume_step);
   if(close_volume<m_broker_volume_min)
      return(false);

   //--- THE REMAINDER MUST STAY LEGAL. Leaving a stub below the broker
   //--- minimum creates a position that cannot be managed or closed
   //--- normally - far worse than declining the partial.
   const double remainder=position.volume-close_volume;
   if(remainder<m_broker_volume_min)
      return(false);

   intent.action  = SRP_TM_SCALE_OUT;
   intent.trigger = SRP_TM_TRIGGER_SCALE_OUT;
   intent.ticket  = position.ticket;
   intent.volume  = close_volume;
   intent.reason  = StringFormat("scale out %.2f of %.2f at +%.1f pts",
                                 close_volume,position.volume,
                                 position.profit_points);
   intent.urgency = 0.6;
   return(true);
  }
//+------------------------------------------------------------------+
bool CTradeManager::EvalBreakEven(const SManagedPosition &position,
                                  STradeIntent &intent) const
  {
   if(!m_be_enabled || position.break_even_done || m_point<=0.0)
      return(false);
   if(position.profit_points<m_be_trigger_points)
      return(false);

   //--- Offset beyond entry rather than exactly at it, so commission and
   //--- spread do not turn a "break-even" exit into a small loss.
   const double offset=m_be_offset_points*m_point;
   const double candidate=Normalize(position.is_buy
                                    ? position.open_price+offset
                                    : position.open_price-offset);
   if(!IsBetterStop(position.is_buy,position.stop_loss,candidate))
      return(false);
   if(!RespectsStopLevel(position.current_price,candidate))
      return(false);

   intent.action   = SRP_TM_MOVE_STOP;
   intent.trigger  = SRP_TM_TRIGGER_BREAK_EVEN;
   intent.ticket   = position.ticket;
   intent.new_stop = candidate;
   intent.reason   = StringFormat("break-even at +%.1f pts (profit %.1f)",
                                  m_be_offset_points,position.profit_points);
   intent.urgency  = 0.55;
   return(true);
  }
//+------------------------------------------------------------------+
bool CTradeManager::EvalTrailing(const SManagedPosition &position,
                                 STradeIntent &intent) const
  {
   if(!m_trail_enabled || m_point<=0.0)
      return(false);
   if(position.profit_points<m_trail_start_points)
      return(false);

   double distance=m_trail_distance_points;
   string mode="fixed";
   if(m_trail_use_atr)
     {
      if(m_atr==NULL)
         return(false);
      double atr=0.0;
      if(!m_atr.ValueAt(0,0,atr) || atr<=0.0)
         return(false);
      distance=atr*m_trail_atr_multiple/m_point;
      mode="ATR";
     }
   if(distance<=0.0)
      return(false);
   //--- Never tighter than the broker allows.
   if(m_stops_level>0 && distance<(double)m_stops_level)
      distance=(double)m_stops_level;

   const double offset=distance*m_point;
   const double candidate=Normalize(position.is_buy
                                    ? position.current_price-offset
                                    : position.current_price+offset);

   //--- STEP THRESHOLD. Without it a busy M1 stream issues a
   //--- modification on nearly every tick, which brokers throttle and
   //--- which surfaces to the user as unexplained latency.
   if(position.stop_loss>0.0)
     {
      const double advance=MathAbs(candidate-position.stop_loss)/m_point;
      if(advance<m_trail_step_points)
         return(false);
     }
   if(!IsBetterStop(position.is_buy,position.stop_loss,candidate))
      return(false);
   if(!RespectsStopLevel(position.current_price,candidate))
      return(false);

   intent.action   = SRP_TM_MOVE_STOP;
   intent.trigger  = (m_trail_use_atr ? SRP_TM_TRIGGER_ATR_TRAIL
                                      : SRP_TM_TRIGGER_TRAILING);
   intent.ticket   = position.ticket;
   intent.new_stop = candidate;
   intent.reason   = StringFormat("%s trail %.1f pts behind price",
                                  mode,distance);
   intent.urgency  = 0.5;
   return(true);
  }
//+------------------------------------------------------------------+
bool CTradeManager::EvalScaleIn(const SManagedPosition &position,
                                STradeIntent &intent) const
  {
   if(!m_scale_in_enabled || position.scaled_in)
      return(false);
   if(position.profit_points<m_scale_in_trigger_points)
      return(false);

   //--- ONLY ADD TO A WINNER. Scaling into a loser is averaging down, a
   //--- fundamentally different and far more dangerous operation, and
   //--- this class will not do it.
   if(position.profit_money<=0.0)
      return(false);

   double add_volume=position.initial_volume*m_scale_in_fraction;
   add_volume=CMathUtils::FloorToStep(add_volume,m_broker_volume_step);
   if(add_volume<m_broker_volume_min)
      return(false);

   intent.action  = SRP_TM_SCALE_IN;
   intent.trigger = SRP_TM_TRIGGER_SCALE_IN;
   intent.ticket  = position.ticket;
   intent.volume  = add_volume;
   intent.reason  = StringFormat("scale in %.2f at +%.1f pts",
                                 add_volume,position.profit_points);
   //--- Lowest urgency: adding exposure is never the priority.
   intent.urgency = 0.3;
   return(true);
  }
//+------------------------------------------------------------------+
bool CTradeManager::Evaluate(const SManagedPosition &position,
                             STradeIntent &intent)
  {
   intent.Reset();
   if(position.ticket==SRP_INVALID_TICKET)
      return(false);

   //--- Prefer the tracked copy: it carries peak excursion and stage
   //--- flags the caller's snapshot does not.
   SManagedPosition working=position;
   SManagedPosition tracked;
   if(GetTracked(position.ticket,tracked))
     {
      working.peak_price=tracked.peak_price;
      working.peak_profit_points=tracked.peak_profit_points;
      working.break_even_done=tracked.break_even_done;
      working.scaled_in=tracked.scaled_in;
      working.scale_out_count=tracked.scale_out_count;
      working.trailing_active=tracked.trailing_active;
      working.initial_volume=tracked.initial_volume;
     }

   //--- FIXED PRIORITY ORDER. Capital preservation first, exposure
   //--- increase last. The first evaluator to produce an intent wins.
   if(EvalEmergency(working,intent)) { m_intents_issued++; return(true); }
   if(EvalMaxHold(working,intent))   { m_intents_issued++; return(true); }
   if(EvalTimeExit(working,intent))  { m_intents_issued++; return(true); }
   if(EvalAtrExit(working,intent))   { m_intents_issued++; return(true); }
   if(EvalScaleOut(working,intent))  { m_intents_issued++; return(true); }
   if(EvalBreakEven(working,intent)) { m_intents_issued++; return(true); }
   if(EvalTrailing(working,intent))  { m_intents_issued++; return(true); }
   if(EvalScaleIn(working,intent))   { m_intents_issued++; return(true); }
   return(false);
  }
//+------------------------------------------------------------------+
bool CTradeManager::RequestReverse(const SManagedPosition &position,
                                   const double new_volume,
                                   const string reason,
                                   STradeIntent &intent) const
  {
   intent.Reset();
   if(!m_reverse_enabled || position.ticket==SRP_INVALID_TICKET)
      return(false);
   double volume=(new_volume>0.0 ? new_volume : position.volume);
   volume=CMathUtils::FloorToStep(volume,m_broker_volume_step);
   if(volume<m_broker_volume_min)
      return(false);

   intent.action  = SRP_TM_REVERSE;
   intent.trigger = SRP_TM_TRIGGER_REVERSAL;
   intent.ticket  = position.ticket;
   intent.volume  = volume;
   intent.reason  = "reverse: "+reason;
   intent.urgency = 0.8;
   return(true);
  }
//+------------------------------------------------------------------+
bool CTradeManager::RequestEmergencyExit(const SManagedPosition &position,
                                         STradeIntent &intent) const
  {
   intent.Reset();
   if(position.ticket==SRP_INVALID_TICKET)
      return(false);
   intent.action  = SRP_TM_CLOSE_FULL;
   intent.trigger = SRP_TM_TRIGGER_EMERGENCY;
   intent.ticket  = position.ticket;
   intent.volume  = position.volume;
   intent.reason  = "emergency exit requested";
   intent.urgency = 1.0;
   return(true);
  }
//+------------------------------------------------------------------+
void CTradeManager::NotifyStopMoved(const ulong ticket,const double new_stop,
                                    const ENUM_SRP_TM_TRIGGER trigger)
  {
   const int index=FindTracked(ticket);
   if(index<0)
      return;
   m_tracked[index].stop_loss=new_stop;
   //--- Flags are set only on CONFIRMED execution, so a failed
   //--- modification is retried rather than silently skipped forever.
   if(trigger==SRP_TM_TRIGGER_BREAK_EVEN)
      m_tracked[index].break_even_done=true;
   if(trigger==SRP_TM_TRIGGER_TRAILING || trigger==SRP_TM_TRIGGER_ATR_TRAIL)
      m_tracked[index].trailing_active=true;
  }
//+------------------------------------------------------------------+
void CTradeManager::NotifyScaledIn(const ulong ticket)
  {
   const int index=FindTracked(ticket);
   if(index>=0)
      m_tracked[index].scaled_in=true;
  }
//+------------------------------------------------------------------+
void CTradeManager::NotifyScaledOut(const ulong ticket)
  {
   const int index=FindTracked(ticket);
   if(index>=0)
      m_tracked[index].scale_out_count++;
  }
//+------------------------------------------------------------------+
bool CTradeManager::Validate(SValidationResult &result) const
  {
   if(m_point<=0.0)
     {
      result.AddError("CTradeManager: invalid symbol point value");
      return(false);
     }
   if((m_trail_use_atr && m_trail_enabled) && m_atr==NULL)
     {
      result.AddError("CTradeManager: ATR trailing configured without an ATR indicator");
      return(false);
     }
   if(m_atr_exit_enabled && m_atr==NULL)
     {
      result.AddError("CTradeManager: ATR exit configured without an ATR indicator");
      return(false);
     }
   //--- Cross-field coherence: a step wider than the distance can never
   //--- fire, which is a silent misconfiguration.
   if(m_trail_enabled && !m_trail_use_atr &&
      m_trail_step_points>m_trail_distance_points)
      result.AddWarning("CTradeManager: trailing step exceeds trailing distance");
   if(m_be_enabled && m_trail_enabled &&
      m_be_trigger_points>m_trail_start_points)
      result.AddWarning("CTradeManager: trailing starts before break-even triggers");
   if(m_max_hold_enabled && m_time_exit_enabled &&
      m_max_hold_minutes<m_time_exit_minutes)
      result.AddWarning("CTradeManager: max hold is shorter than the time exit; "
                        "the time exit can never fire");
   if(m_scale_in_enabled && m_scale_out_enabled &&
      m_scale_in_trigger_points<=m_scale_out_trigger_points)
      result.AddWarning("CTradeManager: scale-in triggers at or before "
                        "scale-out; the two will fight");
   if(m_emergency_armed)
      result.AddWarning("CTradeManager: emergency is currently ARMED");
   return(true);
  }
//+------------------------------------------------------------------+
string CTradeManager::ActionToString(const ENUM_SRP_TM_ACTION action)
  {
   switch(action)
     {
      case SRP_TM_MOVE_STOP:  return("MOVE_STOP");
      case SRP_TM_SCALE_IN:   return("SCALE_IN");
      case SRP_TM_SCALE_OUT:  return("SCALE_OUT");
      case SRP_TM_CLOSE_FULL: return("CLOSE_FULL");
      case SRP_TM_REVERSE:    return("REVERSE");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CTradeManager::TriggerToString(const ENUM_SRP_TM_TRIGGER trigger)
  {
   switch(trigger)
     {
      case SRP_TM_TRIGGER_BREAK_EVEN: return("BREAK_EVEN");
      case SRP_TM_TRIGGER_TRAILING:   return("TRAILING");
      case SRP_TM_TRIGGER_ATR_TRAIL:  return("ATR_TRAIL");
      case SRP_TM_TRIGGER_ATR_EXIT:   return("ATR_EXIT");
      case SRP_TM_TRIGGER_TIME_EXIT:  return("TIME_EXIT");
      case SRP_TM_TRIGGER_MAX_HOLD:   return("MAX_HOLD");
      case SRP_TM_TRIGGER_EMERGENCY:  return("EMERGENCY");
      case SRP_TM_TRIGGER_SCALE_IN:   return("SCALE_IN");
      case SRP_TM_TRIGGER_SCALE_OUT:  return("SCALE_OUT");
      case SRP_TM_TRIGGER_REVERSAL:   return("REVERSAL");
      case SRP_TM_TRIGGER_EARLY_PROFIT:  return("EARLY_PROFIT");
      case SRP_TM_TRIGGER_SCALP_TIMEOUT: return("SCALP_TIMEOUT");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CTradeManager::Describe(void) const
  {
   return(StringFormat("trade manager: tracking %d, %I64d intents | "
                       "BE=%s trail=%s atrExit=%s timeExit=%s maxHold=%s "
                       "scaleIn=%s scaleOut=%s%s",
                       m_tracked_count,m_intents_issued,
                       (m_be_enabled ? "on" : "off"),
                       (m_trail_enabled ? (m_trail_use_atr ? "ATR" : "fixed") : "off"),
                       (m_atr_exit_enabled ? "on" : "off"),
                       (m_time_exit_enabled ? "on" : "off"),
                       (m_max_hold_enabled ? "on" : "off"),
                       (m_scale_in_enabled ? "on" : "off"),
                       (m_scale_out_enabled ? "on" : "off"),
                       (m_emergency_armed ? " | EMERGENCY ARMED" : "")));
  }

#endif // SRP_INTERFACE_MANAGER_CTRADEMANAGER_MQH
//+------------------------------------------------------------------+
