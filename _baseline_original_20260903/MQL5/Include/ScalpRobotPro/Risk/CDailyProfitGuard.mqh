//+------------------------------------------------------------------+
//|                                          CDailyProfitGuard.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : stops trading after the daily profit target is met.            |
//|                                                                  |
//|   Symmetric to CDailyLossGuard and equally important: protecting a      |
//|   good day from being given back is a risk decision, not a preference.  |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CDAILYPROFITGUARD_MQH
#define SRP_RISK_CDAILYPROFITGUARD_MQH

#include "../Core/Base/CRiskGuardBase.mqh"
#include "../Core/Interfaces/IStateStore.mqh"

class CDailyProfitGuard : public CRiskGuardBase
  {
private:
   double            m_profit_target_percent;
   bool              m_close_positions_on_target;
   IStateStore      *m_state;              // borrowed
   datetime          m_armed_day;

   double            CurrentDailyProfitPercent(const SDecisionContext &context) const;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnRearm(void) override;
   virtual bool      OnAllowsNewEntry(const SDecisionContext &context,
                                      ENUM_SRP_VETO_REASON &reason,
                                      string &detail) override;
   virtual bool      OnDemandsFlatten(const SDecisionContext &context,
                                      ENUM_SRP_EXIT_REASON &reason,
                                      string &detail) override;

public:
                     CDailyProfitGuard(const double profit_target_percent,
                                       IStateStore *state,
                                       ILogger *logger);
                    ~CDailyProfitGuard(void) { }

   void              SetProfitTargetPercent(const double percent);
   void              SetClosePositionsOnTarget(const bool value);
   void              OnNewTradingDay(const datetime day_start);
  };

#endif // SRP_RISK_CDAILYPROFITGUARD_MQH
//+------------------------------------------------------------------+
