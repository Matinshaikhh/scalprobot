//+------------------------------------------------------------------+
//|                                            CDailyLossGuard.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : stops trading after a daily loss threshold.                    |
//|                                                                  |
//|   LATCHING: once tripped it stays tripped until the next trading day,   |
//|   even across a terminal restart, because the trip is persisted via     |
//|   IStateStore. A guard that forgets it fired after a reboot is not a    |
//|   guard.                                                              |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CDAILYLOSSGUARD_MQH
#define SRP_RISK_CDAILYLOSSGUARD_MQH

#include "../Core/Base/CRiskGuardBase.mqh"
#include "../Core/Interfaces/IStateStore.mqh"

class CDailyLossGuard : public CRiskGuardBase
  {
private:
   double            m_loss_limit_percent;
   bool              m_flatten_on_trip;
   IStateStore      *m_state;              // borrowed
   datetime          m_armed_day;

   double            CurrentDailyLossPercent(const SDecisionContext &context) const;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnRearm(void) override;
   virtual bool      OnAllowsNewEntry(const SDecisionContext &context,
                                      ENUM_SRP_VETO_REASON &reason,
                                      string &detail) override;
   //--- Overridden because a breached loss limit may require immediate
   //--- liquidation, not merely a halt on new entries.
   virtual bool      OnDemandsFlatten(const SDecisionContext &context,
                                      ENUM_SRP_EXIT_REASON &reason,
                                      string &detail) override;

public:
                     CDailyLossGuard(const double loss_limit_percent,
                                     IStateStore *state,
                                     ILogger *logger);
                    ~CDailyLossGuard(void) { }

   void              SetLossLimitPercent(const double percent);
   void              SetFlattenOnTrip(const bool value);

   //--- Called by the engine at the day boundary.
   void              OnNewTradingDay(const datetime day_start);
  };

#endif // SRP_RISK_CDAILYLOSSGUARD_MQH
//+------------------------------------------------------------------+
