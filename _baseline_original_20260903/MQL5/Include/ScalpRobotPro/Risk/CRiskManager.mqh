//+------------------------------------------------------------------+
//|                                               CRiskManager.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : produces the sanctioned size and protective levels.            |
//|                                                                  |
//|   RESPONSIBILITY (one only): turn an approved SIGNAL into a fully        |
//|   specified SRiskDecision. It coordinates - it does not compute.         |
//|   Sizing belongs to IPositionSizer, levels to the calculators,           |
//|   legality to CStopLevelValidator, affordability to CLotNormalizer.      |
//|                                                                  |
//|   THE ORDER MATTERS AND IS DELIBERATE                                    |
//|     1  resolve the stop distance      (size depends on it)               |
//|     2  size the position              (needs the stop distance)          |
//|     3  resolve the take profit        (may depend on the stop, for RR)   |
//|     4  validate levels against broker (may shift them)                   |
//|     5  normalise volume               (step, bounds, margin)             |
//|     6  re-verify risk after clamping  (clamped stop changes real risk)   |
//|                                                                  |
//|   Step 6 is the one almost every commercial EA omits: if the broker's    |
//|   stop level forced the stop wider, the position that was sized for      |
//|   1% now risks more than 1%. This class re-checks and shrinks.           |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CRISKMANAGER_MQH
#define SRP_RISK_CRISKMANAGER_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IPositionSizer.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"
#include "CStopLossCalculator.mqh"
#include "CTakeProfitCalculator.mqh"
#include "CStopLevelValidator.mqh"
#include "CLotNormalizer.mqh"

class CSymbolInfoProvider;

class CRiskManager : public IModule
  {
private:
   CModuleIdentity        m_id;
   //--- OWNED collaborators.
   IPositionSizer        *m_sizer;
   CStopLossCalculator   *m_stop_loss;
   CTakeProfitCalculator *m_take_profit;
   CStopLevelValidator   *m_validator;
   CLotNormalizer        *m_normalizer;
   //--- BORROWED.
   CSymbolInfoProvider   *m_symbol_info;

   //--- Absolute ceiling on a single trade's risk, independent of the
   //--- sizer. A misconfigured sizer cannot exceed this.
   double                 m_max_risk_percent_per_trade;
   SRiskDecision          m_last_decision;

   //--- Step 6: recompute actual risk and shrink volume if the clamped
   //--- stop pushed it over budget.
   bool                   EnforceRiskCeiling(SRiskDecision &decision,
                                             const SDecisionContext &context,
                                             const SSymbolSpec &spec,
                                             const ENUM_SRP_SIGNAL_DIRECTION direction);

   void                   Reject(SRiskDecision &decision,
                                 const ENUM_SRP_VETO_REASON reason,
                                 const string explanation);

public:
                     CRiskManager(CSymbolInfoProvider *symbol_info,ILogger *logger);
                    ~CRiskManager(void);

   //--- Wiring. Each setter takes ownership.
   void              SetSizer(IPositionSizer *sizer);
   void              SetStopLossCalculator(CStopLossCalculator *calculator);
   void              SetTakeProfitCalculator(CTakeProfitCalculator *calculator);
   void              SetStopLevelValidator(CStopLevelValidator *validator);
   void              SetLotNormalizer(CLotNormalizer *normalizer);
   void              SetMaxRiskPercentPerTrade(const double percent);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Pipeline stage 10. The single public operation.
   bool              Evaluate(const SDecisionContext &context,
                              const SSignal &signal,
                              SRiskDecision &decision);

   //--- Reused by CPositionManager when re-sizing a partial close.
   bool              ResolveLevelsForPosition(const SDecisionContext &context,
                                              const SPositionSnapshot &position,
                                              double &stop_loss,
                                              double &take_profit);

   void              LastDecision(SRiskDecision &out) const { out=m_last_decision; }
  };

#endif // SRP_RISK_CRISKMANAGER_MQH
//+------------------------------------------------------------------+
