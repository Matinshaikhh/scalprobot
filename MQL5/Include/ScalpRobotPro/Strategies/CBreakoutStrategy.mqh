//+------------------------------------------------------------------+
//|                                           CBreakoutStrategy.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Strategies : range-break entries.                                    |
//|                                                                  |
//|   Tracks a recent high/low channel and signals when price clears it   |
//|   by a volatility-scaled margin. The margin scales with ATR so the    |
//|   same settings behave consistently across volatility regimes -       |
//|   fixed-point breakout margins are the usual reason a gold EA that    |
//|   backtested well fails in a quiet week.                              |
//+------------------------------------------------------------------+
#ifndef SRP_STRATEGIES_CBREAKOUTSTRATEGY_MQH
#define SRP_STRATEGIES_CBREAKOUTSTRATEGY_MQH

#include "../Core/Base/CStrategyBase.mqh"
#include "../Indicators/CIndicatorManager.mqh"
#include "../Indicators/CAtrIndicator.mqh"
#include "../Indicators/CAdxIndicator.mqh"

class CBreakoutStrategy : public CStrategyBase
  {
private:
   CIndicatorManager *m_indicators;        // borrowed
   CAtrIndicator     *m_atr;               // borrowed, cached
   CAdxIndicator     *m_adx;               // borrowed, cached

   int               m_channel_bars;
   double            m_breakout_atr_multiple;
   double            m_min_adx;
   bool              m_require_bar_close;
   //--- Guards against re-entering the same break repeatedly.
   datetime          m_last_signal_bar;

   //--- Channel computation, isolated so it is independently testable.
   bool              ComputeChannel(const SDecisionContext &context,
                                    double &out_high,
                                    double &out_low) const;
   double            ComputeConfidence(const double breach_points,
                                       const double margin_points,
                                       const double adx_value) const;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual bool      OnEvaluate(const SDecisionContext &context,
                                SSignal &signal) override;

public:
                     CBreakoutStrategy(CIndicatorManager *indicators,
                                       ILogger *logger,
                                       const double weight=1.0);
                    ~CBreakoutStrategy(void) { }

   void              SetChannelBars(const int bars);
   void              SetBreakoutMultiple(const double atr_multiple);
   void              SetMinAdx(const double value);
  };

#endif // SRP_STRATEGIES_CBREAKOUTSTRATEGY_MQH
//+------------------------------------------------------------------+
