//+------------------------------------------------------------------+
//|                                              CSpreadFilter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Filters : rejects entries when the spread is too wide.                 |
//|                                                                  |
//|   The single most important filter for an M1 gold scalper. A strategy    |
//|   targeting 100 points cannot survive a 60-point spread, and spreads on  |
//|   gold widen by an order of magnitude around the session roll.           |
//|                                                                  |
//|   Priority 10: it is the cheapest possible check and rejects the most    |
//|   often, so it runs first and short-circuits the rest of the chain.      |
//|                                                                  |
//|   Supports an absolute cap and a relative one (multiple of the rolling   |
//|   average). The relative test catches broker-specific widening without   |
//|   the user having to know their broker's normal spread.                  |
//+------------------------------------------------------------------+
#ifndef SRP_FILTERS_CSPREADFILTER_MQH
#define SRP_FILTERS_CSPREADFILTER_MQH

#include "../Core/Base/CFilterBase.mqh"

class CSpreadFilter : public CFilterBase
  {
private:
   double            m_max_spread_points;
   bool              m_use_relative_check;
   double            m_max_average_multiple;
   //--- Requires the spread to also be acceptable relative to the
   //--- intended stop distance, so a valid spread on a very tight stop
   //--- is still rejected.
   bool              m_compare_to_stop_distance;
   double            m_max_spread_to_stop_ratio;
   double            m_reference_stop_points;

protected:
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const ENUM_SRP_SIGNAL_DIRECTION direction,
                                SFilterVerdict &verdict) override;

public:
                     CSpreadFilter(const double max_spread_points,
                                   ILogger *logger);
                    ~CSpreadFilter(void) { }

   void              SetMaxSpreadPoints(const double points);
   void              SetRelativeCheck(const bool enabled,const double max_multiple);
   void              SetStopDistanceCheck(const bool enabled,
                                          const double max_ratio,
                                          const double reference_stop_points);
  };

#endif // SRP_FILTERS_CSPREADFILTER_MQH
//+------------------------------------------------------------------+
