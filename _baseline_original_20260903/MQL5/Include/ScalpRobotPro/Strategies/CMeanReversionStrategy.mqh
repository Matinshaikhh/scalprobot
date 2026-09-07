//+------------------------------------------------------------------+
//|                                     CMeanReversionStrategy.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Strategies : band-extreme reversion entries.                         |
//|                                                                  |
//|   Fades stretched moves back toward the Bollinger mid-band. It is     |
//|   the natural counterpart to the momentum strategy, which is why      |
//|   the aggregation mode matters: run both in FIRST_MATCH and they      |
//|   fight; run both in WEIGHTED_SCORE and they net out sensibly.        |
//+------------------------------------------------------------------+
#ifndef SRP_STRATEGIES_CMEANREVERSIONSTRATEGY_MQH
#define SRP_STRATEGIES_CMEANREVERSIONSTRATEGY_MQH

#include "../Core/Base/CStrategyBase.mqh"
#include "../Indicators/CIndicatorManager.mqh"
#include "../Indicators/CBollingerIndicator.mqh"
#include "../Indicators/CRsiIndicator.mqh"

class CMeanReversionStrategy : public CStrategyBase
  {
private:
   CIndicatorManager   *m_indicators;      // borrowed
   CBollingerIndicator *m_bands;           // borrowed, cached
   CRsiIndicator       *m_rsi;             // borrowed, cached

   double            m_rsi_oversold;
   double            m_rsi_overbought;
   double            m_min_band_width_points;
   double            m_penetration_points;  // how far beyond the band
   bool              m_require_rsi_confirmation;

   double            ComputeConfidence(const double penetration_points,
                                       const double band_width_points,
                                       const double rsi_value) const;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual bool      OnEvaluate(const SDecisionContext &context,
                                SSignal &signal) override;

public:
                     CMeanReversionStrategy(CIndicatorManager *indicators,
                                            ILogger *logger,
                                            const double weight=1.0);
                    ~CMeanReversionStrategy(void) { }

   void              SetRsiThresholds(const double oversold,
                                      const double overbought);
   void              SetMinBandWidth(const double points);
   void              SetPenetration(const double points);

   //--- Reversion trades target the mid-band, so this strategy owns an
   //--- exit opinion: the trade thesis is complete once price reverts.
   virtual bool      ShouldExit(const SDecisionContext &context,
                                const SPositionSnapshot &position,
                                ENUM_SRP_EXIT_REASON &reason) override;
  };

#endif // SRP_STRATEGIES_CMEANREVERSIONSTRATEGY_MQH
//+------------------------------------------------------------------+
