//+------------------------------------------------------------------+
//|                                             CDrawdownGuard.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : caps peak-to-valley equity decline.                            |
//|                                                                  |
//|   Measures drawdown from the ALL-TIME equity peak, persisted through    |
//|   IStateStore. Using the session high instead would let the limit       |
//|   silently reset every restart - the failure mode that turns a          |
//|   "20% max drawdown" claim into an eventual blown account.              |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CDRAWDOWNGUARD_MQH
#define SRP_RISK_CDRAWDOWNGUARD_MQH

#include "../Core/Base/CRiskGuardBase.mqh"
#include "../Core/Interfaces/IStateStore.mqh"

class CDrawdownGuard : public CRiskGuardBase
  {
private:
   double            m_max_drawdown_percent;
   double            m_equity_peak;
   bool              m_flatten_on_trip;
   bool              m_include_floating;   // count open P/L in the measure
   IStateStore      *m_state;              // borrowed

   double            CurrentDrawdownPercent(const SDecisionContext &context) const;
   void              UpdatePeak(const SDecisionContext &context);

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual bool      OnAllowsNewEntry(const SDecisionContext &context,
                                      ENUM_SRP_VETO_REASON &reason,
                                      string &detail) override;
   virtual bool      OnDemandsFlatten(const SDecisionContext &context,
                                      ENUM_SRP_EXIT_REASON &reason,
                                      string &detail) override;

public:
                     CDrawdownGuard(const double max_drawdown_percent,
                                    IStateStore *state,
                                    ILogger *logger);
                    ~CDrawdownGuard(void) { }

   void              SetMaxDrawdownPercent(const double percent);
   void              SetIncludeFloating(const bool value);
   void              SetFlattenOnTrip(const bool value);

   double            EquityPeak(void) const { return(m_equity_peak); }
   //--- Persists the peak so a restart cannot reset the measurement.
   void              PersistPeak(void);
  };

#endif // SRP_RISK_CDRAWDOWNGUARD_MQH
//+------------------------------------------------------------------+
