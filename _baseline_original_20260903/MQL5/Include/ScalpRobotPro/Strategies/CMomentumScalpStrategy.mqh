//+------------------------------------------------------------------+
//|                                     CMomentumScalpStrategy.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Strategies : momentum continuation entries.                          |
//|                                                                  |
//|   Reads a fast/slow MA relationship plus an RSI thrust confirmation.  |
//|   It caches BORROWED indicator pointers at Initialize() so the hot    |
//|   path performs no lookups.                                           |
//|                                                                  |
//|   Note what this class does NOT contain: no lot size, no stop loss,   |
//|   no OrderSend, no filter. It answers one question - "is there        |
//|   momentum worth trading right now?" - and returns a confidence.      |
//+------------------------------------------------------------------+
#ifndef SRP_STRATEGIES_CMOMENTUMSCALPSTRATEGY_MQH
#define SRP_STRATEGIES_CMOMENTUMSCALPSTRATEGY_MQH

#include "../Core/Base/CStrategyBase.mqh"
#include "../Indicators/CIndicatorManager.mqh"
#include "../Indicators/CMovingAverageIndicator.mqh"
#include "../Indicators/CRsiIndicator.mqh"

class CMomentumScalpStrategy : public CStrategyBase
  {
private:
   CIndicatorManager       *m_indicators;   // borrowed
   CMovingAverageIndicator *m_fast_ma;      // borrowed, cached
   CMovingAverageIndicator *m_slow_ma;      // borrowed, cached
   CRsiIndicator           *m_rsi;          // borrowed, cached

   //--- Tunables, injected from configuration.
   double            m_rsi_buy_threshold;
   double            m_rsi_sell_threshold;
   double            m_min_ma_separation_points;
   bool              m_require_bar_close;

   //--- Confidence is a normalised blend of separation and RSI thrust,
   //--- so the aggregator can compare this strategy against others.
   double            ComputeConfidence(const double ma_separation_points,
                                       const double rsi_value) const;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual bool      OnEvaluate(const SDecisionContext &context,
                                SSignal &signal) override;

public:
                     CMomentumScalpStrategy(CIndicatorManager *indicators,
                                            ILogger *logger,
                                            const double weight=1.0);
                    ~CMomentumScalpStrategy(void) { }

   void              SetRsiThresholds(const double buy_threshold,
                                      const double sell_threshold);
   void              SetMinSeparationPoints(const double points);
   void              SetRequireBarClose(const bool value);
  };

#endif // SRP_STRATEGIES_CMOMENTUMSCALPSTRATEGY_MQH
//+------------------------------------------------------------------+
