//+------------------------------------------------------------------+
//|                                              CBrokerManager.mqh |
//|                          Scalping Robot Pro - Core Trading Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): know what the broker and account will  |
//|   permit, and answer pre-trade legality questions about it.         |
//|                                                                  |
//|   This class owns every environment fact the execution path needs:  |
//|     * netting vs hedging  (changes the MEANING of a close/reverse)  |
//|     * supported filling modes (FOK / IOC / RETURN)                  |
//|     * stop and freeze levels                                       |
//|     * volume step, min, max                                        |
//|     * spread, margin and market-open state                         |
//|                                                                  |
//|   WHY IT MATTERS THAT THIS IS ONE CLASS                            |
//|   Assuming ORDER_FILLING_FOK is the classic cause of "unsupported   |
//|   filling mode" rejections on ECN accounts. Assuming hedging is why  |
//|   a "close position" silently becomes a reverse on a netting         |
//|   account. Both are environment questions, so both are answered      |
//|   here once rather than guessed at each call site.                  |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_ENGINE_CBROKERMANAGER_MQH
#define SRP_TRADE_ENGINE_CBROKERMANAGER_MQH

#include "../../Core/Interfaces/IModule.mqh"
#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Core/Base/CModuleIdentity.mqh"
#include "../../Utilities/CMathUtils.mqh"

//+------------------------------------------------------------------+
//| Outcome of a pre-trade legality check. Carries the reason so the   |
//| caller can log, veto and report without re-deriving anything.      |
//+------------------------------------------------------------------+
struct SBrokerCheckResult
  {
   bool                 allowed;
   ENUM_SRP_VETO_REASON reason;
   string               detail;
   double               measured_value;   // spread, margin level, etc.
   double               limit_value;

                     SBrokerCheckResult(void) { Reset(); }
   void              Reset(void)
     {
      allowed=true;
      reason=SRP_VETO_NONE;
      detail="";
      measured_value=0.0;
      limit_value=0.0;
     }
   void              Deny(const ENUM_SRP_VETO_REASON veto,
                          const string text,
                          const double measured=0.0,
                          const double limit=0.0)
     {
      allowed=false;
      reason=veto;
      detail=text;
      measured_value=measured;
      limit_value=limit;
     }
  };

class CBrokerManager : public IModule
  {
private:
   CModuleIdentity   m_id;
   string            m_symbol;

   //--- Symbol facts, resolved at init and refreshed on demand.
   int               m_digits;
   double            m_point;
   double            m_tick_size;
   double            m_tick_value;
   double            m_contract_size;
   double            m_volume_min;
   double            m_volume_max;
   double            m_volume_step;
   double            m_volume_limit;      // 0 == no aggregate cap
   int               m_stops_level;
   int               m_freeze_level;
   ENUM_SYMBOL_TRADE_MODE      m_trade_mode;
   ENUM_SYMBOL_TRADE_EXECUTION m_execution_mode;
   ENUM_SYMBOL_CALC_MODE       m_calc_mode;
   uint              m_filling_flags;
   ENUM_ORDER_TYPE_FILLING m_preferred_filling;
   bool              m_symbol_resolved;

   //--- Account facts.
   ENUM_ACCOUNT_MARGIN_MODE m_margin_mode;
   bool              m_is_hedging;
   long              m_leverage;
   string            m_currency;
   int               m_limit_orders;

   //--- Configured guard limits.
   double            m_max_spread_points;
   double            m_min_free_margin_percent;
   double            m_min_margin_level_percent;
   double            m_margin_safety_factor;   // require this much headroom

   //--- Internal resolution steps.
   bool              ResolveSymbolFacts(void);
   bool              ResolveAccountFacts(void);
   ENUM_ORDER_TYPE_FILLING PickFillingMode(void) const;

public:
                     CBrokerManager(const string symbol,ILogger *logger);
                    ~CBrokerManager(void) { }

   //--- Configuration ------------------------------------------------
   void              SetMaxSpreadPoints(const double points);
   void              SetMarginRequirements(const double min_free_margin_percent,
                                           const double min_margin_level_percent);
   void              SetMarginSafetyFactor(const double factor);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Refresh values that legitimately change intraday.
   bool              RefreshVolatile(void);

   //--- Account mode -------------------------------------------------
   bool              IsHedging(void) const { return(m_is_hedging); }
   bool              IsNetting(void) const { return(!m_is_hedging); }
   ENUM_ACCOUNT_MARGIN_MODE MarginMode(void) const { return(m_margin_mode); }
   string            AccountCurrency(void) const { return(m_currency); }

   //--- Symbol facts -------------------------------------------------
   string            Symbol(void)        const { return(m_symbol); }
   int               Digits(void)        const { return(m_digits); }
   double            Point(void)         const { return(m_point); }
   double            TickSize(void)      const { return(m_tick_size); }
   double            TickValue(void)     const { return(m_tick_value); }
   double            VolumeMin(void)     const { return(m_volume_min); }
   double            VolumeMax(void)     const { return(m_volume_max); }
   double            VolumeStep(void)    const { return(m_volume_step); }
   int               StopsLevel(void)    const { return(m_stops_level); }
   int               FreezeLevel(void)   const { return(m_freeze_level); }
   ENUM_ORDER_TYPE_FILLING FillingMode(void) const { return(m_preferred_filling); }
   bool              IsMarketExecution(void) const
     { return(m_execution_mode==SYMBOL_TRADE_EXECUTION_MARKET); }

   //--- Live market data ---------------------------------------------
   double            Bid(void) const;
   double            Ask(void) const;
   double            SpreadPoints(void) const;
   bool              GetTick(MqlTick &tick) const;

   //--- Normalisation ------------------------------------------------
   double            NormalizePrice(const double price) const;
   //--- Always floors: rounding volume up would exceed the risk budget
   //--- that was already approved upstream.
   double            NormalizeVolume(const double volume) const;
   double            PointsToPrice(const double points) const;
   double            PriceToPoints(const double price_delta) const;

   //--- PRE-TRADE CHECKS ---------------------------------------------
   //--- Global permissions: terminal, EA, account and symbol.
   bool              CheckTradingAllowed(SBrokerCheckResult &result) const;
   //--- Spread protection.
   bool              CheckSpread(SBrokerCheckResult &result) const;
   //--- Symbol session state; prevents sending into a closed market.
   bool              CheckMarketOpen(SBrokerCheckResult &result) const;
   //--- Volume legality against step, bounds and aggregate cap.
   bool              CheckVolume(const double volume,
                                 SBrokerCheckResult &result) const;
   //--- Margin sufficiency using OrderCalcMargin, plus the configured
   //--- free-margin floor and margin-level floor.
   bool              CheckMargin(const ENUM_ORDER_TYPE order_type,
                                 const double volume,
                                 const double price,
                                 SBrokerCheckResult &result) const;
   //--- Stop-level legality for SL/TP relative to a reference price.
   bool              CheckStopDistance(const double reference_price,
                                       const double level_price,
                                       SBrokerCheckResult &result) const;
   //--- Freeze-level check: inside it, modification is refused by the
   //--- server, so the caller must skip rather than retry forever.
   bool              IsInsideFreezeLevel(const double reference_price,
                                         const double level_price) const;

   //--- Composite gate used by the execution engine before every entry.
   bool              CheckCanOpen(const ENUM_ORDER_TYPE order_type,
                                  const double volume,
                                  const double price,
                                  SBrokerCheckResult &result) const;

   //--- Largest volume the account can currently afford for this side.
   double            MaxAffordableVolume(const ENUM_ORDER_TYPE order_type,
                                         const double price) const;

   //--- Diagnostics --------------------------------------------------
   string            Describe(void) const;
   static string     FillingModeToString(const ENUM_ORDER_TYPE_FILLING mode);
  };

//+------------------------------------------------------------------+
CBrokerManager::CBrokerManager(const string symbol,ILogger *logger)
  : m_symbol(symbol),
    m_digits(0),
    m_point(0.0),
    m_tick_size(0.0),
    m_tick_value(0.0),
    m_contract_size(0.0),
    m_volume_min(0.0),
    m_volume_max(0.0),
    m_volume_step(0.0),
    m_volume_limit(0.0),
    m_stops_level(0),
    m_freeze_level(0),
    m_trade_mode(SYMBOL_TRADE_MODE_DISABLED),
    m_execution_mode(SYMBOL_TRADE_EXECUTION_REQUEST),
    m_calc_mode(SYMBOL_CALC_MODE_FOREX),
    m_filling_flags(0),
    m_preferred_filling(ORDER_FILLING_RETURN),
    m_symbol_resolved(false),
    m_margin_mode(ACCOUNT_MARGIN_MODE_RETAIL_NETTING),
    m_is_hedging(false),
    m_leverage(0),
    m_currency(""),
    m_limit_orders(0),
    m_max_spread_points(0.0),
    m_min_free_margin_percent(0.0),
    m_min_margin_level_percent(0.0),
    m_margin_safety_factor(1.1)
  {
   m_id.Configure("CBrokerManager",logger);
  }
//+------------------------------------------------------------------+
void CBrokerManager::SetMaxSpreadPoints(const double points)
  {
   m_max_spread_points=(points<0.0 ? 0.0 : points);
  }
//+------------------------------------------------------------------+
void CBrokerManager::SetMarginRequirements(const double min_free_margin_percent,
                                          const double min_margin_level_percent)
  {
   m_min_free_margin_percent =(min_free_margin_percent<0.0 ? 0.0 : min_free_margin_percent);
   m_min_margin_level_percent=(min_margin_level_percent<0.0 ? 0.0 : min_margin_level_percent);
  }
//+------------------------------------------------------------------+
void CBrokerManager::SetMarginSafetyFactor(const double factor)
  {
   //--- Below 1.0 would permit using more margin than exists.
   if(factor>=1.0)
      m_margin_safety_factor=factor;
  }
//+------------------------------------------------------------------+
bool CBrokerManager::Initialize(void)
  {
   if(m_id.IsInitialized())
      return(true);

   //--- The symbol must be in Market Watch before its properties are
   //--- reliable; a symbol absent from the watchlist returns zeros.
   if(!SymbolSelect(m_symbol,true))
     {
      m_id.Error("cannot select symbol "+m_symbol+" in Market Watch");
      m_id.SetHealth(SRP_HEALTH_CRITICAL,"symbol unavailable");
      return(false);
     }

   if(!ResolveSymbolFacts())
     {
      m_id.SetHealth(SRP_HEALTH_CRITICAL,"symbol specification unresolved");
      return(false);
     }
   if(!ResolveAccountFacts())
     {
      m_id.SetHealth(SRP_HEALTH_CRITICAL,"account facts unresolved");
      return(false);
     }

   m_id.Info(Describe());
   m_id.SetInitialized(true);
   m_id.SetHealth(SRP_HEALTH_OK,"");
   return(true);
  }
//+------------------------------------------------------------------+
bool CBrokerManager::ResolveSymbolFacts(void)
  {
   m_digits        =(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
   m_point         =SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   m_tick_size     =SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
   m_tick_value    =SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
   m_contract_size =SymbolInfoDouble(m_symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   m_volume_min    =SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
   m_volume_max    =SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
   m_volume_step   =SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
   m_volume_limit  =SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_LIMIT);
   m_stops_level   =(int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
   m_freeze_level  =(int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   m_trade_mode    =(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_MODE);
   m_execution_mode=(ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_EXEMODE);
   m_calc_mode     =(ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_CALC_MODE);
   m_filling_flags =(uint)SymbolInfoInteger(m_symbol,SYMBOL_FILLING_MODE);

   //--- A zero point or tick size makes all price arithmetic invalid,
   //--- so this is a hard failure rather than a warning.
   if(m_point<=0.0 || m_digits<0)
     {
      m_id.Error("invalid point/digits for "+m_symbol);
      return(false);
     }
   //--- Some brokers report tick size 0; fall back to point.
   if(m_tick_size<=0.0)
      m_tick_size=m_point;
   if(m_volume_step<=0.0)
     {
      m_id.Error("invalid volume step for "+m_symbol);
      return(false);
     }

   m_preferred_filling=PickFillingMode();
   m_symbol_resolved=true;
   return(true);
  }
//+------------------------------------------------------------------+
bool CBrokerManager::ResolveAccountFacts(void)
  {
   m_margin_mode =(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   m_is_hedging  =(m_margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   m_leverage    =AccountInfoInteger(ACCOUNT_LEVERAGE);
   m_currency    =AccountInfoString(ACCOUNT_CURRENCY);
   m_limit_orders=(int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
   return(StringLen(m_currency)>0);
  }
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING CBrokerManager::PickFillingMode(void) const
  {
   //--- SYMBOL_FILLING_MODE is a bit mask of what the server accepts.
   //--- Choosing from it rather than assuming FOK is what prevents
   //--- retcode 10030 (unsupported filling mode) on ECN accounts.
   const bool allows_fok=((m_filling_flags & SYMBOL_FILLING_FOK)!=0);
   const bool allows_ioc=((m_filling_flags & SYMBOL_FILLING_IOC)!=0);

   //--- On market execution, prefer IOC: a partial fill is better than
   //--- an outright rejection when liquidity is thin, which is common
   //--- on metals during session rollover.
   if(IsMarketExecution())
     {
      if(allows_ioc) return(ORDER_FILLING_IOC);
      if(allows_fok) return(ORDER_FILLING_FOK);
      return(ORDER_FILLING_RETURN);
     }
   if(allows_fok) return(ORDER_FILLING_FOK);
   if(allows_ioc) return(ORDER_FILLING_IOC);
   //--- RETURN is the documented fallback and is valid for exchange
   //--- execution where neither flag is advertised.
   return(ORDER_FILLING_RETURN);
  }
//+------------------------------------------------------------------+
bool CBrokerManager::RefreshVolatile(void)
  {
   if(!m_symbol_resolved)
      return(false);
   //--- Variable-spread brokers widen these intraday; a stale stops
   //--- level produces "invalid stops" on an otherwise correct order.
   m_stops_level =(int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
   m_freeze_level=(int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   m_tick_value  =SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
   m_volume_limit=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_LIMIT);
   return(true);
  }
//+------------------------------------------------------------------+
void CBrokerManager::Validate(SValidationResult &result)
  {
   if(!m_symbol_resolved)
     {
      result.AddError("CBrokerManager: symbol specification unresolved");
      return;
     }
   if(m_trade_mode==SYMBOL_TRADE_MODE_DISABLED)
      result.AddError("CBrokerManager: trading disabled for "+m_symbol);
   if(m_trade_mode==SYMBOL_TRADE_MODE_CLOSEONLY)
      result.AddWarning("CBrokerManager: "+m_symbol+" is close-only; no new entries possible");
   if(m_trade_mode==SYMBOL_TRADE_MODE_LONGONLY)
      result.AddWarning("CBrokerManager: "+m_symbol+" permits long positions only");
   if(m_trade_mode==SYMBOL_TRADE_MODE_SHORTONLY)
      result.AddWarning("CBrokerManager: "+m_symbol+" permits short positions only");
   if(m_filling_flags==0)
      result.AddWarning("CBrokerManager: broker advertises no filling mode; using RETURN");
   if(m_tick_value<=0.0)
      result.AddWarning("CBrokerManager: tick value is zero; money calculations will be wrong");
   if(!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      result.AddWarning("CBrokerManager: algo trading disabled in terminal");
   if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      result.AddWarning("CBrokerManager: expert trading disabled on account");
  }
//+------------------------------------------------------------------+
void CBrokerManager::Shutdown(void)
  {
   m_id.SetInitialized(false);
  }
//+------------------------------------------------------------------+
void CBrokerManager::ReportHealth(SHealthReport &report)
  {
   if(!m_symbol_resolved)
      m_id.SetHealth(SRP_HEALTH_CRITICAL,"symbol unresolved");
   else if(!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      m_id.SetHealth(SRP_HEALTH_DEGRADED,"terminal trading disabled");
   else if(m_trade_mode==SYMBOL_TRADE_MODE_DISABLED)
      m_id.SetHealth(SRP_HEALTH_CRITICAL,"symbol trading disabled");
   else
      m_id.SetHealth(SRP_HEALTH_OK,"");
   m_id.FillReport(report,TimeCurrent());
  }
//+------------------------------------------------------------------+
bool CBrokerManager::GetTick(MqlTick &tick) const
  {
   return(SymbolInfoTick(m_symbol,tick));
  }
//+------------------------------------------------------------------+
double CBrokerManager::Bid(void) const
  {
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol,tick))
      return(0.0);
   return(tick.bid);
  }
//+------------------------------------------------------------------+
double CBrokerManager::Ask(void) const
  {
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol,tick))
      return(0.0);
   return(tick.ask);
  }
//+------------------------------------------------------------------+
double CBrokerManager::SpreadPoints(void) const
  {
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol,tick))
      return(0.0);
   if(tick.ask<=0.0 || tick.bid<=0.0)
      return(0.0);
   return(PriceToPoints(tick.ask-tick.bid));
  }
//+------------------------------------------------------------------+
double CBrokerManager::PointsToPrice(const double points) const
  {
   return(points*m_point);
  }
//+------------------------------------------------------------------+
double CBrokerManager::PriceToPoints(const double price_delta) const
  {
   return(CMathUtils::SafeDivide(price_delta,m_point,0.0));
  }
//+------------------------------------------------------------------+
double CBrokerManager::NormalizePrice(const double price) const
  {
   if(price<=0.0)
      return(0.0);
   //--- Round to tick size first, then to digits. Brokers on metals
   //--- often use a tick size that is a multiple of point, and skipping
   //--- this step yields prices the server rejects as invalid.
   const double ticked=CMathUtils::RoundToStep(price,m_tick_size);
   return(NormalizeDouble(ticked,m_digits));
  }
//+------------------------------------------------------------------+
double CBrokerManager::NormalizeVolume(const double volume) const
  {
   if(volume<=0.0)
      return(0.0);
   //--- FLOOR, never round: rounding up silently exceeds the approved
   //--- risk, and at the minimum lot that is a doubling of exposure.
   double stepped=CMathUtils::FloorToStep(volume,m_volume_step);
   if(stepped<m_volume_min)
     {
      //--- Below the broker minimum there is no legal volume at all.
      //--- Returning 0 makes the caller abort rather than send an
      //--- order that will certainly be rejected.
      return(0.0);
     }
   if(stepped>m_volume_max)
      stepped=m_volume_max;
   //--- Volume step can be finer than 2 decimals on some brokers, so
   //--- derive the precision from the step itself.
   int volume_digits=0;
   double step=m_volume_step;
   while(step<1.0 && volume_digits<8)
     {
      step*=10.0;
      volume_digits++;
     }
   return(NormalizeDouble(stepped,volume_digits));
  }
//+------------------------------------------------------------------+
bool CBrokerManager::CheckTradingAllowed(SBrokerCheckResult &result) const
  {
   result.Reset();
   if(!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      result.Deny(SRP_VETO_CONFIGURATION,"algo trading disabled in terminal");
      return(false);
     }
   if(!(bool)MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      result.Deny(SRP_VETO_CONFIGURATION,"trading not permitted for this EA");
      return(false);
     }
   if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     {
      result.Deny(SRP_VETO_CONFIGURATION,"trading disabled on account");
      return(false);
     }
   if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      result.Deny(SRP_VETO_CONFIGURATION,"expert trading disabled on account");
      return(false);
     }
   if(m_trade_mode==SYMBOL_TRADE_MODE_DISABLED)
     {
      result.Deny(SRP_VETO_MARKET_CLOSED,"symbol trading disabled: "+m_symbol);
      return(false);
     }
   if(m_trade_mode==SYMBOL_TRADE_MODE_CLOSEONLY)
     {
      result.Deny(SRP_VETO_MARKET_CLOSED,"symbol is close-only: "+m_symbol);
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CBrokerManager::CheckMarketOpen(SBrokerCheckResult &result) const
  {
   result.Reset();
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol,tick))
     {
      result.Deny(SRP_VETO_MARKET_CLOSED,"no tick data for "+m_symbol);
      return(false);
     }
   if(tick.bid<=0.0 || tick.ask<=0.0)
     {
      result.Deny(SRP_VETO_MARKET_CLOSED,"invalid quotes (bid/ask zero)");
      return(false);
     }
   //--- A quote older than a couple of minutes means the session is
   //--- effectively closed even if the terminal still reports a price.
   const long age_seconds=(long)TimeCurrent()-(long)tick.time;
   if(age_seconds>120)
     {
      result.Deny(SRP_VETO_MARKET_CLOSED,
                  StringFormat("stale quote, %I64d seconds old",age_seconds),
                  (double)age_seconds,120.0);
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CBrokerManager::CheckSpread(SBrokerCheckResult &result) const
  {
   result.Reset();
   if(m_max_spread_points<=0.0)
      return(true);                       // protection disabled
   const double spread=SpreadPoints();
   if(spread<=0.0)
     {
      result.Deny(SRP_VETO_SPREAD,"spread unavailable");
      return(false);
     }
   if(spread>m_max_spread_points)
     {
      result.Deny(SRP_VETO_SPREAD,
                  StringFormat("spread %.1f exceeds limit %.1f points",
                               spread,m_max_spread_points),
                  spread,m_max_spread_points);
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CBrokerManager::CheckVolume(const double volume,
                                 SBrokerCheckResult &result) const
  {
   result.Reset();
   if(volume<=0.0)
     {
      result.Deny(SRP_VETO_CONFIGURATION,"volume is zero");
      return(false);
     }
   if(volume<m_volume_min-SRP_EPSILON)
     {
      result.Deny(SRP_VETO_CONFIGURATION,
                  StringFormat("volume %.4f below broker minimum %.4f",
                               volume,m_volume_min),
                  volume,m_volume_min);
      return(false);
     }
   if(volume>m_volume_max+SRP_EPSILON)
     {
      result.Deny(SRP_VETO_CONFIGURATION,
                  StringFormat("volume %.4f above broker maximum %.4f",
                               volume,m_volume_max),
                  volume,m_volume_max);
      return(false);
     }
   //--- Confirm the volume sits exactly on a step boundary. A value
   //--- that merely looks close is rejected by the server.
   const double steps=CMathUtils::SafeDivide(volume,m_volume_step,0.0);
   if(MathAbs(steps-MathRound(steps))>0.001)
     {
      result.Deny(SRP_VETO_CONFIGURATION,
                  StringFormat("volume %.4f is not a multiple of step %.4f",
                               volume,m_volume_step),
                  volume,m_volume_step);
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CBrokerManager::CheckMargin(const ENUM_ORDER_TYPE order_type,
                                 const double volume,
                                 const double price,
                                 SBrokerCheckResult &result) const
  {
   result.Reset();

   double required=0.0;
   //--- OrderCalcMargin is authoritative: it accounts for the symbol's
   //--- calculation mode, leverage and any broker-specific margin rate.
   //--- Deriving margin manually is how EAs end up wrong on metals.
   if(!OrderCalcMargin(order_type,m_symbol,volume,price,required))
     {
      result.Deny(SRP_VETO_MARGIN,
                  "OrderCalcMargin failed, error "+IntegerToString(GetLastError()));
      return(false);
     }

   const double equity      =AccountInfoDouble(ACCOUNT_EQUITY);
   const double free_margin =AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   const double needed      =required*m_margin_safety_factor;

   if(needed>free_margin)
     {
      result.Deny(SRP_VETO_MARGIN,
                  StringFormat("insufficient margin: need %.2f, free %.2f",
                               needed,free_margin),
                  free_margin,needed);
      return(false);
     }

   //--- Free-margin floor: keep a configured buffer so one trade cannot
   //--- consume the headroom that open positions need to survive noise.
   if(m_min_free_margin_percent>0.0 && equity>0.0)
     {
      const double remaining_percent=(free_margin-needed)/equity*100.0;
      if(remaining_percent<m_min_free_margin_percent)
        {
         result.Deny(SRP_VETO_MARGIN,
                     StringFormat("free margin after trade %.2f%% below floor %.2f%%",
                                  remaining_percent,m_min_free_margin_percent),
                     remaining_percent,m_min_free_margin_percent);
         return(false);
        }
     }

   //--- Margin-level floor, evaluated only when positions already exist
   //--- (margin level is meaningless at zero used margin).
   if(m_min_margin_level_percent>0.0)
     {
      const double used_margin=AccountInfoDouble(ACCOUNT_MARGIN);
      if(used_margin>0.0)
        {
         const double projected_level=equity/(used_margin+needed)*100.0;
         if(projected_level<m_min_margin_level_percent)
           {
            result.Deny(SRP_VETO_MARGIN,
                        StringFormat("projected margin level %.1f%% below floor %.1f%%",
                                     projected_level,m_min_margin_level_percent),
                        projected_level,m_min_margin_level_percent);
            return(false);
           }
        }
     }

   result.measured_value=required;
   return(true);
  }
//+------------------------------------------------------------------+
double CBrokerManager::MaxAffordableVolume(const ENUM_ORDER_TYPE order_type,
                                          const double price) const
  {
   double margin_per_min_lot=0.0;
   if(!OrderCalcMargin(order_type,m_symbol,m_volume_min,price,margin_per_min_lot))
      return(0.0);
   if(margin_per_min_lot<=0.0)
      return(m_volume_max);

   const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double budget=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   //--- Honour the free-margin floor when computing affordability.
   if(m_min_free_margin_percent>0.0 && equity>0.0)
      budget-=equity*m_min_free_margin_percent/100.0;
   if(budget<=0.0)
      return(0.0);

   budget/=m_margin_safety_factor;
   const double lots=m_volume_min*(budget/margin_per_min_lot);
   return(NormalizeVolume(lots));
  }
//+------------------------------------------------------------------+
bool CBrokerManager::CheckStopDistance(const double reference_price,
                                       const double level_price,
                                       SBrokerCheckResult &result) const
  {
   result.Reset();
   if(level_price<=0.0)
      return(true);                       // no level is always legal
   if(m_stops_level<=0)
      return(true);                       // broker imposes no minimum
   const double distance=MathAbs(PriceToPoints(reference_price-level_price));
   if(distance<(double)m_stops_level)
     {
      result.Deny(SRP_VETO_CONFIGURATION,
                  StringFormat("level %.1f points from price, minimum %d",
                               distance,m_stops_level),
                  distance,(double)m_stops_level);
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CBrokerManager::IsInsideFreezeLevel(const double reference_price,
                                         const double level_price) const
  {
   if(m_freeze_level<=0 || level_price<=0.0)
      return(false);
   const double distance=MathAbs(PriceToPoints(reference_price-level_price));
   return(distance<(double)m_freeze_level);
  }
//+------------------------------------------------------------------+
bool CBrokerManager::CheckCanOpen(const ENUM_ORDER_TYPE order_type,
                                  const double volume,
                                  const double price,
                                  SBrokerCheckResult &result) const
  {
   //--- Ordered cheapest-first so the common rejection costs least.
   if(!CheckTradingAllowed(result)) return(false);
   if(!CheckMarketOpen(result))     return(false);
   if(!CheckSpread(result))         return(false);
   if(!CheckVolume(volume,result))  return(false);

   //--- Directional permission, for symbols restricted to one side.
   const bool is_buy=(order_type==ORDER_TYPE_BUY ||
                      order_type==ORDER_TYPE_BUY_LIMIT ||
                      order_type==ORDER_TYPE_BUY_STOP ||
                      order_type==ORDER_TYPE_BUY_STOP_LIMIT);
   if(m_trade_mode==SYMBOL_TRADE_MODE_LONGONLY && !is_buy)
     {
      result.Deny(SRP_VETO_DIRECTION,"symbol permits long positions only");
      return(false);
     }
   if(m_trade_mode==SYMBOL_TRADE_MODE_SHORTONLY && is_buy)
     {
      result.Deny(SRP_VETO_DIRECTION,"symbol permits short positions only");
      return(false);
     }

   if(!CheckMargin(order_type,volume,price,result)) return(false);
   return(true);
  }
//+------------------------------------------------------------------+
string CBrokerManager::FillingModeToString(const ENUM_ORDER_TYPE_FILLING mode)
  {
   switch(mode)
     {
      case ORDER_FILLING_FOK:    return("FOK");
      case ORDER_FILLING_IOC:    return("IOC");
      case ORDER_FILLING_RETURN: return("RETURN");
     }
   return("UNKNOWN");
  }
//+------------------------------------------------------------------+
string CBrokerManager::Describe(void) const
  {
   return(StringFormat("%s | %s | digits=%d point=%.*f tickSize=%.*f | "
                       "vol %.4f..%.4f step %.4f | stops=%d freeze=%d | "
                       "filling=%s | leverage=1:%I64d %s",
                       m_symbol,
                       (m_is_hedging ? "HEDGING" : "NETTING"),
                       m_digits,m_digits,m_point,m_digits,m_tick_size,
                       m_volume_min,m_volume_max,m_volume_step,
                       m_stops_level,m_freeze_level,
                       FillingModeToString(m_preferred_filling),
                       m_leverage,m_currency));
  }

#endif // SRP_TRADE_ENGINE_CBROKERMANAGER_MQH
//+------------------------------------------------------------------+
