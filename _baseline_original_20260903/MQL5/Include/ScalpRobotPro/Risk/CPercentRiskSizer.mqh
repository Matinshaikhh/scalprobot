//+------------------------------------------------------------------+
//|                                          CPercentRiskSizer.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : volume derived from a percentage of balance or equity.         |
//|                                                                  |
//|   The core sizing model for disciplined risk: choose the volume that   |
//|   loses exactly N percent if the stop is hit. It therefore REQUIRES a  |
//|   stop distance and returns 0 without one rather than guessing - a     |
//|   silent fallback to a fixed lot here would break the user's stated    |
//|   risk contract, which is exactly the kind of quiet betrayal this      |
//|   architecture is designed to prevent.                                 |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CPERCENTRISKSIZER_MQH
#define SRP_RISK_CPERCENTRISKSIZER_MQH

#include "../Core/Interfaces/IPositionSizer.mqh"

class CPercentRiskSizer : public IPositionSizer
  {
private:
   double            m_risk_percent;
   bool              m_use_equity;         // false => balance
   //--- Optional: shrink size while in drawdown, an anti-martingale.
   bool              m_reduce_in_drawdown;
   double            m_drawdown_trigger_percent;
   double            m_drawdown_size_factor;

   double            ReferenceCapital(const SAccountSnapshot &account) const;
   double            ApplyDrawdownAdjustment(const double volume,
                                             const SDecisionContext &context,
                                             string &explanation) const;

public:
                     CPercentRiskSizer(const double risk_percent,
                                       const bool use_equity=true);
                    ~CPercentRiskSizer(void) { }

   void              SetRiskPercent(const double percent);
   void              SetUseEquity(const bool value);
   void              SetDrawdownReduction(const bool enabled,
                                          const double trigger_percent,
                                          const double size_factor);

   virtual ENUM_SRP_RISK_MODE Mode(void) override
     {
      return(m_use_equity ? SRP_RISK_PERCENT_EQUITY : SRP_RISK_PERCENT_BALANCE);
     }
   virtual string    SizerName(void) override { return("PercentRiskSizer"); }

   virtual double    CalculateVolume(const SDecisionContext &context,
                                     const SSymbolSpec &spec,
                                     const double stop_distance_points,
                                     string &explanation) override;
  };

#endif // SRP_RISK_CPERCENTRISKSIZER_MQH
//+------------------------------------------------------------------+
