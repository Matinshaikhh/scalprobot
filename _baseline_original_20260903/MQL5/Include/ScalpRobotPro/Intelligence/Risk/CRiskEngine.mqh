//+------------------------------------------------------------------+
//|                                               CRiskEngine.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): coordinate the risk subsystem and expose   |
//|   one coherent API. It owns the sizers, the limit guard and the         |
//|   protection manager, and it normalises raw volume to broker rules.     |
//|                                                                  |
//|   IT COORDINATES, IT DOES NOT CALCULATE. Sizing belongs to the sizer   |
//|   models, limits to CRiskLimitGuard, levels to CProtectionManager.     |
//|                                                                  |
//|   THE ORDER OF OPERATIONS IS THE WHOLE POINT                          |
//|     1  check limits          (no sizing at all if trading is barred)   |
//|     2  resolve the stop      (size depends on it)                     |
//|     3  size the position     (needs the stop distance)                 |
//|     4  normalise the volume  (step, bounds - always rounds DOWN)       |
//|     5  RE-VERIFY actual risk after normalisation                       |
//|                                                                  |
//|   Step 5 is the one almost every implementation omits. Flooring the     |
//|   volume to a broker step changes the money at risk, and a stop widened |
//|   to the broker minimum changes it again. Without re-verification a     |
//|   position sized for 1% can quietly risk materially more, which defeats |
//|   the entire purpose of the risk layer.                                |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_RISK_CRISKENGINE_MQH
#define SRP_INTELLIGENCE_RISK_CRISKENGINE_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Core/Interfaces/IStateStore.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "CPositionSizers.mqh"
#include "CRiskLimitGuard.mqh"
#include "CProtectionManager.mqh"

class CRiskEngine
  {
private:
   string              m_symbol;
   ILogger            *m_logger;          // borrowed
   //--- OWNED components.
   CSizerBase         *m_sizer;
   CRiskLimitGuard    *m_guard;
   CProtectionManager *m_protection;
   //--- BORROWED.
   CAtrIntel          *m_atr;
   CSwingDetector     *m_swings;

   //--- Absolute ceiling on a single trade's risk, independent of the
   //--- selected model. A misconfigured sizer cannot exceed this.
   double              m_max_risk_percent_per_trade;
   double              m_max_volume;
   bool                m_initialized;

   SSizingResult       m_last_result;
   long                m_approvals;
   long                m_rejections;

   //--- Instrument facts.
   double              m_point;
   double              m_tick_size;
   double              m_tick_value;
   double              m_volume_min;
   double              m_volume_max;
   double              m_volume_step;

   bool                RefreshSpec(void);
   //--- Always floors: rounding up would exceed the approved risk.
   double              NormalizeVolume(const double volume) const;
   void                BuildContext(const double stop_distance_points,
                                    SSizingContext &context) const;
   //--- Step 5: recompute real risk and shrink if normalisation pushed it
   //--- over the ceiling.
   bool                EnforceRiskCeiling(SSizingResult &result,
                                          const SSizingContext &context);

public:
                     CRiskEngine(const string symbol,
                                 CAtrIntel *atr,
                                 ILogger *logger);
                    ~CRiskEngine(void);

   //--- Wiring. Each setter takes OWNERSHIP of its argument.
   void              SetSizer(CSizerBase *sizer);
   void              SetLimitGuard(CRiskLimitGuard *guard);
   void              SetProtectionManager(CProtectionManager *protection);
   void              SetSwingDetector(CSwingDetector *swings);
   void              SetMaxRiskPercentPerTrade(const double percent);
   void              SetMaxVolume(const double volume);

   bool              Initialize(const double equity,const datetime now);
   void              Shutdown(void);
   bool              Validate(SValidationResult &result);

   //--- Called once per pass, before any evaluation.
   void              UpdateAccountState(const double equity,
                                        const double floating,
                                        const datetime now);
   void              RecordClosedTrade(const double net_profit,const datetime now);

   //=== THE PRIMARY OPERATION =======================================
   //--- Resolves limits, protection and size for a prospective trade.
   bool              EvaluateEntry(const bool is_buy,
                                   const double entry_price,
                                   const double total_open_lots,
                                   const double exposure_risk_percent,
                                   SSizingResult &sizing,
                                   SProtectionPlan &plan,
                                   SRiskVerdict &verdict);

   //--- In-trade stop management, delegated to the protection manager.
   bool              EvaluateStopAdjustment(const bool is_buy,
                                            const double entry_price,
                                            const double current_price,
                                            const double peak_price,
                                            const double current_stop,
                                            SStopAdjustment &adjustment);

   //--- Emergency control.
   void              TriggerEmergencyShutdown(const string reason,const datetime now);
   bool              ClearEmergencyShutdown(const string acknowledgement);
   bool              IsEmergencyActive(void) const;

   //--- What one lot loses if the stop is hit, according to the terminal.
   //--- Public so a harness can assert it against OrderCalcProfit and so
   //--- the value can be shown to a user who questions a position size.
   double            BrokerMoneyPerLot(const double stop_distance_points) const;

   //--- Component access. BORROWED pointers - the engine deletes them.
   CRiskLimitGuard    *Guard(void)      const { return(m_guard); }
   CProtectionManager *Protection(void) const { return(m_protection); }
   CSizerBase         *Sizer(void)      const { return(m_sizer); }

   //--- Diagnostics.
   void              GetLastResult(SSizingResult &out) const { out=m_last_result; }
   long              ApprovalCount(void)  const { return(m_approvals); }
   long              RejectionCount(void) const { return(m_rejections); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CRiskEngine::CRiskEngine(const string symbol,CAtrIntel *atr,ILogger *logger)
  : m_symbol(symbol),
    m_logger(logger),
    m_sizer(NULL),
    m_guard(NULL),
    m_protection(NULL),
    m_atr(atr),
    m_swings(NULL),
    m_max_risk_percent_per_trade(2.0),
    m_max_volume(0.0),
    m_initialized(false),
    m_approvals(0),
    m_rejections(0),
    m_point(0.0),
    m_tick_size(0.0),
    m_tick_value(0.0),
    m_volume_min(0.0),
    m_volume_max(0.0),
    m_volume_step(0.0)
  {
   RefreshSpec();
  }
//+------------------------------------------------------------------+
CRiskEngine::~CRiskEngine(void)
  {
   //--- Reverse of assignment order; all three are owned.
   if(m_protection!=NULL) { delete m_protection; m_protection=NULL; }
   if(m_guard!=NULL)      { delete m_guard;      m_guard=NULL;      }
   if(m_sizer!=NULL)      { delete m_sizer;      m_sizer=NULL;      }
  }
//+------------------------------------------------------------------+
bool CRiskEngine::RefreshSpec(void)
  {
   m_point       = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   m_tick_size   = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
   m_tick_value  = SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
   m_volume_min  = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
   m_volume_max  = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
   m_volume_step = SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
   if(m_tick_size<=0.0)
      m_tick_size=m_point;
   return(m_point>0.0 && m_volume_step>0.0);
  }
//+------------------------------------------------------------------+
void CRiskEngine::SetSizer(CSizerBase *sizer)
  {
   if(m_sizer!=NULL)
      delete m_sizer;
   m_sizer=sizer;
  }
//+------------------------------------------------------------------+
void CRiskEngine::SetLimitGuard(CRiskLimitGuard *guard)
  {
   if(m_guard!=NULL)
      delete m_guard;
   m_guard=guard;
  }
//+------------------------------------------------------------------+
void CRiskEngine::SetProtectionManager(CProtectionManager *protection)
  {
   if(m_protection!=NULL)
      delete m_protection;
   m_protection=protection;
  }
//+------------------------------------------------------------------+
void CRiskEngine::SetSwingDetector(CSwingDetector *swings)
  {
   m_swings=swings;
   if(m_protection!=NULL)
      m_protection.SetSwingDetector(swings);
  }
//+------------------------------------------------------------------+
void CRiskEngine::SetMaxRiskPercentPerTrade(const double percent)
  {
   if(percent>0.0)
      m_max_risk_percent_per_trade=percent;
  }
//+------------------------------------------------------------------+
void CRiskEngine::SetMaxVolume(const double volume)
  {
   m_max_volume=(volume<0.0 ? 0.0 : volume);
  }
//+------------------------------------------------------------------+
bool CRiskEngine::Initialize(const double equity,const datetime now)
  {
   if(!RefreshSpec())
     {
      if(m_logger!=NULL)
         m_logger.Error("CRiskEngine","invalid instrument specification");
      return(false);
     }
   if(m_sizer==NULL)
     {
      if(m_logger!=NULL)
         m_logger.Error("CRiskEngine","no sizing model configured");
      return(false);
     }
   if(m_guard!=NULL && !m_guard.Initialize(equity,now))
      return(false);
   m_initialized=true;
   return(true);
  }
//+------------------------------------------------------------------+
void CRiskEngine::Shutdown(void)
  {
   if(m_guard!=NULL)
      m_guard.Shutdown();
   m_initialized=false;
  }
//+------------------------------------------------------------------+
double CRiskEngine::NormalizeVolume(const double volume) const
  {
   if(volume<=0.0 || m_volume_step<=0.0)
      return(0.0);
   //--- FLOOR, never round. Rounding up silently exceeds the approved
   //--- risk, and at the minimum lot that is a doubling of exposure.
   double stepped=CMathUtils::FloorToStep(volume,m_volume_step);

   //--- Below the broker minimum there is no legal volume. Returning 0
   //--- makes the caller abort rather than send a doomed order.
   if(stepped<m_volume_min)
      return(0.0);
   if(stepped>m_volume_max)
      stepped=m_volume_max;
   if(m_max_volume>0.0 && stepped>m_max_volume)
      stepped=CMathUtils::FloorToStep(m_max_volume,m_volume_step);

   //--- Derive precision from the step itself: some brokers use finer
   //--- than two decimals.
   int digits=0;
   double step=m_volume_step;
   while(step<1.0 && digits<8)
     {
      step*=10.0;
      digits++;
     }
   return(NormalizeDouble(stepped,digits));
  }
//+------------------------------------------------------------------+
//| THE AUTHORITATIVE RISK CONVERSION.                                   |
//|                                                                  |
//| Returns the money one lot loses if the stop is hit, as the terminal   |
//| itself computes it. Returns 0.0 when unavailable, which tells the     |
//| sizing context to fall back to tick arithmetic.                      |
//|                                                                  |
//| WHY NOT COMPUTE IT FROM tick_value: on this broker XAUUSD reports     |
//| tick_size 0.01 and tick_value 0.10 against a 100 oz contract, which   |
//| understates the real loss by a factor of ten. Sizing on that figure   |
//| risked 5.01% on a trade configured for 0.5%. OrderCalcProfit uses the |
//| broker's own contract specification, so it stays correct across       |
//| metals, indices, crypto and FX without special cases.                |
//|                                                                  |
//| The magnitude is returned: a loss is reported negative, and risk is   |
//| naturally expressed as a positive quantity.                          |
//+------------------------------------------------------------------+
double CRiskEngine::BrokerMoneyPerLot(const double stop_distance_points) const
  {
   if(stop_distance_points<=0.0 || m_point<=0.0)
      return(0.0);

   const double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
   if(ask<=0.0)
      return(0.0);
   const double stop_price=ask-stop_distance_points*m_point;
   if(stop_price<=0.0)
      return(0.0);

   //--- One lot, priced over exactly the stop distance being sized. BUY is
   //--- used for both directions: the distance is what determines the
   //--- loss, and using one side consistently avoids a spread asymmetry
   //--- leaking into position size.
   double loss=0.0;
   if(!OrderCalcProfit(ORDER_TYPE_BUY,m_symbol,1.0,ask,stop_price,loss))
      return(0.0);
   return(MathAbs(loss));
  }
//+------------------------------------------------------------------+
void CRiskEngine::BuildContext(const double stop_distance_points,
                               SSizingContext &context) const
  {
   context.Reset();
   context.balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   context.equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   context.free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   context.point       = m_point;
   context.tick_size   = m_tick_size;
   context.tick_value  = m_tick_value;
   context.volume_min  = m_volume_min;
   context.volume_max  = m_volume_max;
   context.volume_step = m_volume_step;
   context.stop_distance_points=stop_distance_points;
   //--- Ask the terminal what one lot actually loses over this stop. It
   //--- prices the fill with the same code the broker will, so it cannot
   //--- disagree with the account the way tick_value arithmetic can.
   context.broker_money_per_lot=BrokerMoneyPerLot(stop_distance_points);

   if(m_atr!=NULL)
     {
      double atr_value=0.0;
      if(m_atr.ValueAt(0,0,atr_value))
         context.atr_value=atr_value;
     }

   //--- Performance figures come from the ledger, so Kelly and dynamic
   //--- sizing read the same numbers the limits are measured against.
   if(m_guard!=NULL)
     {
      SRiskLedger ledger;
      m_guard.GetLedger(ledger);
      context.peak_equity              = ledger.peak_equity;
      context.consecutive_losses       = ledger.consecutive_losses;
      context.current_drawdown_percent = m_guard.DrawdownPercent();
     }
  }
//+------------------------------------------------------------------+
bool CRiskEngine::EnforceRiskCeiling(SSizingResult &result,
                                     const SSizingContext &context)
  {
   //--- STEP 5. Recompute the ACTUAL money at risk using the normalised
   //--- volume and the final stop distance, then shrink if it exceeds
   //--- the per-trade ceiling.
   const double money_per_lot=context.MoneyPerLotAtStop();
   if(money_per_lot<=0.0 || context.equity<=0.0)
     {
      //--- Without a stop there is no measurable risk to verify. The
      //--- volume stands, but the caller is told the check was skipped.
      result.explanation+=" | risk ceiling not verified (no stop)";
      return(true);
     }

   const double risk_money=result.volume*money_per_lot;
   const double risk_percent=risk_money/context.equity*100.0;
   result.risk_amount  = risk_money;
   result.risk_percent = risk_percent;

   if(risk_percent<=m_max_risk_percent_per_trade)
      return(true);

   //--- Over the ceiling. Compute the largest volume that fits and floor
   //--- it to a legal step.
   const double allowed_money=context.equity*m_max_risk_percent_per_trade/100.0;
   const double capped=NormalizeVolume(allowed_money/money_per_lot);
   if(capped<=0.0)
     {
      result.approved=false;
      result.volume=0.0;
      result.rejection_reason=StringFormat(
         "risk %.2f%% exceeds ceiling %.2f%% and no smaller legal volume exists",
         risk_percent,m_max_risk_percent_per_trade);
      return(false);
     }

   if(m_logger!=NULL)
      m_logger.Warn("CRiskEngine",
                    StringFormat("volume reduced %.2f -> %.2f: risk %.2f%% "
                                 "exceeded ceiling %.2f%%",
                                 result.volume,capped,risk_percent,
                                 m_max_risk_percent_per_trade));

   result.volume       = capped;
   result.risk_amount  = capped*money_per_lot;
   result.risk_percent = result.risk_amount/context.equity*100.0;
   result.explanation += StringFormat(" | capped to %.2f%% risk ceiling",
                                      m_max_risk_percent_per_trade);
   return(true);
  }
//+------------------------------------------------------------------+
void CRiskEngine::UpdateAccountState(const double equity,
                                     const double floating,
                                     const datetime now)
  {
   if(m_guard==NULL)
      return;
   //--- Windows first, so a boundary crossing reseeds the opening equity
   //--- before the new equity is folded in.
   m_guard.UpdateWindows(equity,now);
   m_guard.UpdateEquity(equity,floating);
  }
//+------------------------------------------------------------------+
void CRiskEngine::RecordClosedTrade(const double net_profit,const datetime now)
  {
   if(m_guard!=NULL)
      m_guard.RecordClosedTrade(net_profit,now);
  }
//+------------------------------------------------------------------+
bool CRiskEngine::EvaluateEntry(const bool is_buy,
                                const double entry_price,
                                const double total_open_lots,
                                const double exposure_risk_percent,
                                SSizingResult &sizing,
                                SProtectionPlan &plan,
                                SRiskVerdict &verdict)
  {
   sizing.Reset();
   plan.Reset();
   verdict.Reset();

   if(!m_initialized)
     {
      sizing.rejection_reason="risk engine not initialised";
      m_rejections++;
      return(false);
     }
   RefreshSpec();

   //--- STEP 1: LIMITS FIRST. There is no point sizing a trade that is
   //--- barred, and evaluating limits first also means a tripped guard
   //--- costs almost nothing on the hot path.
   if(m_guard!=NULL)
     {
      const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(!m_guard.Evaluate(equity,total_open_lots,exposure_risk_percent,verdict))
        {
         sizing.rejection_reason=verdict.detail;
         m_last_result=sizing;
         m_rejections++;
         return(false);
        }
     }

   //--- STEP 2: THE STOP. Sizing depends on it, so it is resolved first.
   if(m_protection!=NULL)
      m_protection.BuildPlan(is_buy,entry_price,plan);

   const double stop_distance=(plan.has_stop ? plan.stop_distance_points : 0.0);
   sizing.stop_distance_points=stop_distance;

   //--- STEP 3: SIZE, using the resolved stop distance.
   SSizingContext context;
   BuildContext(stop_distance,context);

   string explanation="";
   const double raw=m_sizer.Calculate(context,explanation);
   sizing.raw_volume  = raw;
   sizing.model_used  = m_sizer.Model();
   sizing.explanation = explanation;

   if(raw<=0.0)
     {
      sizing.rejection_reason="sizing model returned zero: "+explanation;
      m_last_result=sizing;
      m_rejections++;
      return(false);
     }

   //--- STEP 4: NORMALISE to broker rules. Always downward.
   const double normalized=NormalizeVolume(raw);
   if(normalized<=0.0)
     {
      sizing.rejection_reason=StringFormat(
         "volume %.4f normalises below broker minimum %.4f",raw,m_volume_min);
      m_last_result=sizing;
      m_rejections++;
      return(false);
     }
   sizing.volume=normalized;

   //--- STEP 5: RE-VERIFY the real risk after normalisation.
   if(!EnforceRiskCeiling(sizing,context))
     {
      m_last_result=sizing;
      m_rejections++;
      return(false);
     }

   sizing.approved=true;
   m_last_result=sizing;
   m_approvals++;
   return(true);
  }
//+------------------------------------------------------------------+
bool CRiskEngine::EvaluateStopAdjustment(const bool is_buy,
                                         const double entry_price,
                                         const double current_price,
                                         const double peak_price,
                                         const double current_stop,
                                         SStopAdjustment &adjustment)
  {
   adjustment.Reset();
   if(m_protection==NULL)
      return(false);
   return(m_protection.EvaluateAll(is_buy,entry_price,current_price,
                                   peak_price,current_stop,adjustment));
  }
//+------------------------------------------------------------------+
void CRiskEngine::TriggerEmergencyShutdown(const string reason,const datetime now)
  {
   if(m_guard!=NULL)
      m_guard.TriggerEmergency(reason,now);
  }
//+------------------------------------------------------------------+
bool CRiskEngine::ClearEmergencyShutdown(const string acknowledgement)
  {
   if(m_guard==NULL)
      return(false);
   return(m_guard.ClearEmergency(acknowledgement));
  }
//+------------------------------------------------------------------+
bool CRiskEngine::IsEmergencyActive(void) const
  {
   return(m_guard!=NULL && m_guard.IsEmergencyTripped());
  }
//+------------------------------------------------------------------+
bool CRiskEngine::Validate(SValidationResult &result)
  {
   if(m_sizer==NULL)
      result.AddError("CRiskEngine: no sizing model configured");
   if(m_point<=0.0 || m_volume_step<=0.0)
      result.AddError("CRiskEngine: invalid instrument specification");
   if(m_tick_value<=0.0)
      result.AddWarning("CRiskEngine: tick value is zero; risk-based sizing "
                        "will not work");
   if(m_max_risk_percent_per_trade>10.0)
      result.AddWarning("CRiskEngine: per-trade risk ceiling above 10% is "
                        "unusually aggressive");
   if(m_guard!=NULL)
      m_guard.Validate(result);
   if(m_protection!=NULL)
      m_protection.Validate(result);
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
string CRiskEngine::Describe(void) const
  {
   return(StringFormat("risk engine: model=%s ceiling=%.2f%% approvals=%I64d "
                       "rejections=%I64d | %s",
                       (m_sizer!=NULL ? m_sizer.Name() : "none"),
                       m_max_risk_percent_per_trade,
                       m_approvals,m_rejections,
                       (m_guard!=NULL ? m_guard.Describe() : "no guard")));
  }

#endif // SRP_INTELLIGENCE_RISK_CRISKENGINE_MQH
//+------------------------------------------------------------------+
