//+------------------------------------------------------------------+
//|                                          CVolatilityFilter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Filters : rejects entries outside a usable volatility band.            |
//|                                                                  |
//|   Two-sided by design. Too little volatility means the target cannot be  |
//|   reached before the spread eats the edge; too much means stops are      |
//|   random. Most EAs filter only the upper bound and then wonder why they  |
//|   bleed during dead sessions.                                           |
//+------------------------------------------------------------------+
#ifndef SRP_FILTERS_CVOLATILITYFILTER_MQH
#define SRP_FILTERS_CVOLATILITYFILTER_MQH

#include "../Core/Base/CFilterBase.mqh"
#include "../Indicators/CIndicatorManager.mqh"
#include "../Indicators/CAtrIndicator.mqh"

class CVolatilityFilter : public CFilterBase
  {
private:
   CIndicatorManager *m_indicators;        // borrowed
   CAtrIndicator     *m_atr;               // borrowed, cached
   double            m_min_atr_points;
   double            m_max_atr_points;
   bool              m_reject_extreme_regime;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const ENUM_SRP_SIGNAL_DIRECTION direction,
                                SFilterVerdict &verdict) override;

public:
                     CVolatilityFilter(CIndicatorManager *indicators,
                                       ILogger *logger);
                    ~CVolatilityFilter(void) { }

   void              SetAtrBounds(const double min_points,const double max_points);
   void              SetRejectExtremeRegime(const bool value);
  };

#endif // SRP_FILTERS_CVOLATILITYFILTER_MQH
//+------------------------------------------------------------------+
