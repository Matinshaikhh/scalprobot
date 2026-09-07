//+------------------------------------------------------------------+
//|                                        IStopLevelCalculator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : protective-level calculation contract.       |
//|                                                                  |
//|   One interface serves SL, TP and trailing calculators. Each      |
//|   concrete class computes exactly ONE level from ONE model, so    |
//|   swapping "ATR stop" for "structure stop" is a registry change,  |
//|   not a code change.                                              |
//|                                                                  |
//|   Parentless by design (stateless calculator, nothing to own).    |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_ISTOPLEVELCALCULATOR_MQH
#define SRP_CORE_INTERFACES_ISTOPLEVELCALCULATOR_MQH

#include "../Types/Structs.mqh"

interface IStopLevelCalculator
  {
   string            CalculatorName(void);

   //--- Absolute price for the protective level, or 0.0 when the
   //--- model yields no level. Broker stop-distance clamping is
   //--- CStopLevelValidator's job, not this method's.
   bool              Calculate(const SDecisionContext &context,
                               const SSymbolSpec &spec,
                               const ENUM_SRP_SIGNAL_DIRECTION direction,
                               const double entry_price,
                               double &level_price,
                               string &explanation);
  };

#endif // SRP_CORE_INTERFACES_ISTOPLEVELCALCULATOR_MQH
//+------------------------------------------------------------------+
