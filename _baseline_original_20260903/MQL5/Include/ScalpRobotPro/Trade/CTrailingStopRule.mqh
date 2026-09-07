//+------------------------------------------------------------------+
//|                                          CTrailingStopRule.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Trade : advances the stop as profit grows.                             |
//|                                                                  |
//|   Supports fixed-step, ATR-scaled and profit-percentage models, chosen   |
//|   by configuration. Only ever moves the stop in the profitable           |
//|   direction: a trailing stop that can retreat is not a trailing stop.    |
//|                                                                  |
//|   The step threshold prevents server spam. Without it, a tick-by-tick    |
//|   trail issues thousands of modifications an hour, which brokers          |
//|   throttle and which shows up as mysterious latency.                     |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_CTRAILINGSTOPRULE_MQH
#define SRP_TRADE_CTRAILINGSTOPRULE_MQH

#include "../Core/Base/CPositionRuleBase.mqh"
#include "../Indicators/CIndicatorManager.mqh"

class CTrailingStopRule : public CPositionRuleBase
  {
private:
   ENUM_SRP_TRAIL_MODE m_mode;
   double            m_start_points;       // profit needed before trailing
   double            m_distance_points;    // gap between price and stop
   double            m_step_points;        // minimum advance per update
   double            m_atr_multiplier;
   CIndicatorManager *m_indicators;        // borrowed, for ATR mode

   //--- One resolver per mode; keeps OnEvaluate free of branching noise.
   bool              ResolveDistance(const SDecisionContext &context,
                                     const SSymbolSpec &spec,
                                     double &distance_points) const;
   //--- True only when the new stop is a genuine improvement beyond the
   //--- step threshold.
   bool              IsImprovement(const SSymbolSpec &spec,
                                   const SPositionSnapshot &position,
                                   const double candidate_stop) const;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const SSymbolSpec &spec,
                                const SPositionSnapshot &position,
                                SPositionAction &action) override;

public:
                     CTrailingStopRule(const ENUM_SRP_TRAIL_MODE mode,
                                       CIndicatorManager *indicators,
                                       ILogger *logger);
                    ~CTrailingStopRule(void) { }

   void              SetFixedParameters(const double start_points,
                                        const double distance_points,
                                        const double step_points);
   void              SetAtrMultiplier(const double multiplier);
   void              SetMode(const ENUM_SRP_TRAIL_MODE mode);
  };

#endif // SRP_TRADE_CTRAILINGSTOPRULE_MQH
//+------------------------------------------------------------------+
