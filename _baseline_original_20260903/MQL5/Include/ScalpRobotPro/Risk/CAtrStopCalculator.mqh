//+------------------------------------------------------------------+
//|                                         CAtrStopCalculator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : ATR-multiple protective level model.                           |
//|                                                                  |
//|   Places the level a configured number of ATRs from entry, so the      |
//|   stop breathes with the market instead of being hit by ordinary       |
//|   noise during a volatile session.                                     |
//|                                                                  |
//|   One class serves both SL and TP: the multiplier and the direction    |
//|   sign are configuration, not behaviour.                               |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CATRSTOPCALCULATOR_MQH
#define SRP_RISK_CATRSTOPCALCULATOR_MQH

#include "../Core/Interfaces/IStopLevelCalculator.mqh"

class CAtrStopCalculator : public IStopLevelCalculator
  {
private:
   double            m_multiplier;
   bool              m_is_stop_loss;       // false => take profit side
   double            m_minimum_points;
   double            m_maximum_points;

public:
                     CAtrStopCalculator(const double multiplier,
                                        const bool is_stop_loss);
                    ~CAtrStopCalculator(void) { }

   void              SetMultiplier(const double multiplier);
   //--- Bounds prevent an ATR spike from producing an absurd stop.
   void              SetBounds(const double minimum_points,
                               const double maximum_points);

   virtual string    CalculatorName(void) override
     {
      return(m_is_stop_loss ? "AtrStopLoss" : "AtrTakeProfit");
     }

   virtual bool      Calculate(const SDecisionContext &context,
                               const SSymbolSpec &spec,
                               const ENUM_SRP_SIGNAL_DIRECTION direction,
                               const double entry_price,
                               double &level_price,
                               string &explanation) override;
  };

#endif // SRP_RISK_CATRSTOPCALCULATOR_MQH
//+------------------------------------------------------------------+
