//+------------------------------------------------------------------+
//|                                               CTrendFilter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Filters : rejects entries against the higher-timeframe trend.          |
//|                                                                  |
//|   A DIRECTIONAL filter - it needs the proposed direction, which is why   |
//|   IFilter::Evaluate carries one. Buy signals are vetoed in a downtrend    |
//|   and vice versa, while a ranging market can be configured to permit     |
//|   both or neither.                                                      |
//+------------------------------------------------------------------+
#ifndef SRP_FILTERS_CTRENDFILTER_MQH
#define SRP_FILTERS_CTRENDFILTER_MQH

#include "../Core/Base/CFilterBase.mqh"
#include "../Indicators/CIndicatorManager.mqh"
#include "../Indicators/CMovingAverageIndicator.mqh"
#include "../Indicators/CAdxIndicator.mqh"

class CTrendFilter : public CFilterBase
  {
private:
   CIndicatorManager       *m_indicators;  // borrowed
   CMovingAverageIndicator *m_trend_ma;    // borrowed, cached
   CAdxIndicator           *m_adx;         // borrowed, cached
   double            m_min_adx;
   bool              m_allow_in_range;
   bool              m_use_regime_state;   // trust the regime analyzer
   double            m_min_distance_points; // ignore price hugging the MA

   ENUM_SRP_TREND_STATE ResolveTrend(const SDecisionContext &context) const;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const ENUM_SRP_SIGNAL_DIRECTION direction,
                                SFilterVerdict &verdict) override;

public:
                     CTrendFilter(CIndicatorManager *indicators,ILogger *logger);
                    ~CTrendFilter(void) { }

   void              SetMinAdx(const double value);
   void              SetAllowInRange(const bool value);
   void              SetUseRegimeState(const bool value);
   void              SetMinDistancePoints(const double points);
  };

#endif // SRP_FILTERS_CTRENDFILTER_MQH
//+------------------------------------------------------------------+
