//+------------------------------------------------------------------+
//|                                               IPositionSizer.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : volume calculation strategy (GoF Strategy).  |
//|                                                                  |
//|   Deliberately PARENTLESS: a sizer is a stateless calculator with |
//|   nothing to initialise or release, so forcing IModule on it      |
//|   would be interface pollution. Interface Segregation Principle.  |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_IPOSITIONSIZER_MQH
#define SRP_CORE_INTERFACES_IPOSITIONSIZER_MQH

#include "../Types/Structs.mqh"

interface IPositionSizer
  {
   ENUM_SRP_RISK_MODE Mode(void);
   string            SizerName(void);

   //--- Raw, unnormalised volume. Broker normalisation (step, min,
   //--- max, margin) is the separate responsibility of CLotNormalizer,
   //--- so this method stays pure arithmetic and easily verifiable.
   //--- 'stop_distance_points' is 0 when no stop is used, and the
   //--- implementation must handle that without dividing by zero.
   double            CalculateVolume(const SDecisionContext &context,
                                     const SSymbolSpec &spec,
                                     const double stop_distance_points,
                                     string &explanation);
  };

#endif // SRP_CORE_INTERFACES_IPOSITIONSIZER_MQH
//+------------------------------------------------------------------+
