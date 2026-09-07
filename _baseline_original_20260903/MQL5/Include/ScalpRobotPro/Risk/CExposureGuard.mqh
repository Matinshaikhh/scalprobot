//+------------------------------------------------------------------+
//|                                             CExposureGuard.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : caps concurrent positions, volume and aggregate risk.          |
//|                                                                  |
//|   NON-LATCHING: unlike the loss and drawdown guards, this one is        |
//|   re-evaluated every pass, because exposure falls as positions close.   |
//|   The base class supports both behaviours through one constructor flag. |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CEXPOSUREGUARD_MQH
#define SRP_RISK_CEXPOSUREGUARD_MQH

#include "../Core/Base/CRiskGuardBase.mqh"

class CExposureGuard : public CRiskGuardBase
  {
private:
   int               m_max_positions;
   int               m_max_positions_per_direction;
   double            m_max_total_volume;
   double            m_max_aggregate_risk_percent;
   double            m_min_free_margin_percent;
   double            m_min_margin_level_percent;

protected:
   virtual void      OnValidate(SValidationResult &result) override;
   virtual bool      OnAllowsNewEntry(const SDecisionContext &context,
                                      ENUM_SRP_VETO_REASON &reason,
                                      string &detail) override;

public:
                     CExposureGuard(ILogger *logger);
                    ~CExposureGuard(void) { }

   void              SetPositionLimits(const int max_total,
                                       const int max_per_direction);
   void              SetVolumeLimit(const double max_total_volume);
   void              SetAggregateRiskLimit(const double max_risk_percent);
   void              SetMarginRequirements(const double min_free_margin_percent,
                                           const double min_margin_level_percent);
  };

#endif // SRP_RISK_CEXPOSUREGUARD_MQH
//+------------------------------------------------------------------+
