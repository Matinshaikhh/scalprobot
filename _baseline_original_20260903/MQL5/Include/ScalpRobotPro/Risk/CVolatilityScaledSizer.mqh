//+------------------------------------------------------------------+
//|                                     CVolatilityScaledSizer.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : volume inversely scaled by current volatility.                 |
//|                                                                  |
//|   Targets constant RISK rather than constant SIZE: as ATR expands the  |
//|   volume shrinks, so a quiet-session position and a volatile-session   |
//|   position put the same money at risk. This is what keeps a gold       |
//|   scalper's equity curve from being dominated by a handful of          |
//|   high-volatility days.                                               |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CVOLATILITYSCALEDSIZER_MQH
#define SRP_RISK_CVOLATILITYSCALEDSIZER_MQH

#include "../Core/Interfaces/IPositionSizer.mqh"

class CVolatilityScaledSizer : public IPositionSizer
  {
private:
   double            m_risk_percent;
   double            m_reference_atr_percent; // the "normal" volatility
   double            m_min_scale_factor;
   double            m_max_scale_factor;
   bool              m_use_equity;

   //--- Clamped so an ATR spike or a near-zero ATR cannot produce an
   //--- absurd multiplier.
   double            ComputeScaleFactor(const double current_atr_percent) const;

public:
                     CVolatilityScaledSizer(const double risk_percent,
                                            const double reference_atr_percent);
                    ~CVolatilityScaledSizer(void) { }

   void              SetRiskPercent(const double percent);
   void              SetReferenceAtrPercent(const double percent);
   void              SetScaleBounds(const double minimum,const double maximum);

   virtual ENUM_SRP_RISK_MODE Mode(void) override { return(SRP_RISK_VOLATILITY_SCALED); }
   virtual string    SizerName(void) override { return("VolatilityScaledSizer"); }

   virtual double    CalculateVolume(const SDecisionContext &context,
                                     const SSymbolSpec &spec,
                                     const double stop_distance_points,
                                     string &explanation) override;
  };

#endif // SRP_RISK_CVOLATILITYSCALEDSIZER_MQH
//+------------------------------------------------------------------+
