//+------------------------------------------------------------------+
//|                               CVolatilityExpansionStrategy.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Strategies : squeeze-to-expansion entries.                           |
//|                                                                  |
//|   Waits for compressed volatility to release and trades the first      |
//|   directional impulse. Distinct from CBreakoutStrategy: that one       |
//|   needs a PRICE level to be cleared, this one needs a VOLATILITY       |
//|   state change. Two different theses, therefore two classes.           |
//+------------------------------------------------------------------+
#ifndef SRP_STRATEGIES_CVOLATILITYEXPANSIONSTRATEGY_MQH
#define SRP_STRATEGIES_CVOLATILITYEXPANSIONSTRATEGY_MQH

#include "../Core/Base/CStrategyBase.mqh"
#include "../Indicators/CIndicatorManager.mqh"
#include "../Indicators/CAtrIndicator.mqh"
#include "../Indicators/CBollingerIndicator.mqh"
#include "../Utilities/CCircularBuffer.mqh"

class CVolatilityExpansionStrategy : public CStrategyBase
  {
private:
   CIndicatorManager   *m_indicators;      // borrowed
   CAtrIndicator       *m_atr;             // borrowed, cached
   CBollingerIndicator *m_bands;           // borrowed, cached

   //--- Rolling ATR history, so "expansion" is measured against this
   //--- instrument's own recent behaviour rather than a fixed number.
   CCircularBuffer   m_atr_history;
   int               m_history_bars;
   double            m_expansion_ratio;     // current ATR / average ATR
   double            m_squeeze_ratio;
   int               m_squeeze_min_bars;
   int               m_squeeze_bar_count;
   datetime          m_last_history_bar;

   bool              UpdateHistory(const SDecisionContext &context);
   bool              IsSqueezed(double &out_ratio) const;
   bool              IsExpanding(double &out_ratio) const;
   double            ComputeConfidence(const double expansion_ratio) const;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual bool      OnEvaluate(const SDecisionContext &context,
                                SSignal &signal) override;

public:
                     CVolatilityExpansionStrategy(CIndicatorManager *indicators,
                                                  ILogger *logger,
                                                  const double weight=1.0);
                    ~CVolatilityExpansionStrategy(void) { }

   void              SetHistoryBars(const int bars);
   void              SetRatios(const double squeeze_ratio,
                               const double expansion_ratio);
   void              SetSqueezeMinBars(const int bars);
  };

#endif // SRP_STRATEGIES_CVOLATILITYEXPANSIONSTRATEGY_MQH
//+------------------------------------------------------------------+
