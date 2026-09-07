//+------------------------------------------------------------------+
//|                                               ITradeExecutor.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : the ONLY door to the broker.                 |
//|                                                                  |
//|   Nothing outside an ITradeExecutor implementation may call       |
//|   OrderSend. That single rule makes the whole system testable:    |
//|   inject a simulating executor and the entire pipeline runs with  |
//|   zero broker contact.                                            |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_ITRADEEXECUTOR_MQH
#define SRP_CORE_INTERFACES_ITRADEEXECUTOR_MQH

#include "IModule.mqh"

interface ITradeExecutor : public IModule
  {
   //--- Open a new position from a fully-validated request.
   bool              OpenPosition(const STradeRequest &request,STradeResult &result);

   //--- Close an entire position.
   bool              ClosePosition(const ulong ticket,
                                   const ENUM_SRP_EXIT_REASON reason,
                                   STradeResult &result);

   //--- Reduce a position. 'volume' is the amount to remove.
   bool              ClosePartial(const ulong ticket,
                                  const double volume,
                                  const ENUM_SRP_EXIT_REASON reason,
                                  STradeResult &result);

   //--- Change protective levels. Implementations must skip no-op
   //--- modifications so the server is never spammed.
   bool              ModifyStops(const ulong ticket,
                                 const double stop_loss,
                                 const double take_profit,
                                 STradeResult &result);

   bool              DeletePendingOrder(const ulong ticket,STradeResult &result);

   //--- Execution telemetry, surfaced on the dashboard.
   double            AverageSlippagePoints(void);
   double            AverageLatencyMs(void);
   int               RejectionCount(void);
  };

#endif // SRP_CORE_INTERFACES_ITRADEEXECUTOR_MQH
//+------------------------------------------------------------------+
