//+------------------------------------------------------------------+
//|                                                    IStrategy.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : entry-logic contract.                        |
//|                                                                  |
//|   A strategy is a PURE OPINION PROVIDER. It reads an immutable    |
//|   SDecisionContext and returns an SSignal. It may not size a      |
//|   position, may not touch the trade API, and may not veto - those |
//|   are the Risk, Trade and Filters layers respectively. This is    |
//|   the strictest single-responsibility boundary in the system.     |
//|                                                                  |
//|   Inherits IModule (single parent - MQL5 forbids more) so the    |
//|   kernel can manage a strategy's lifecycle like any other module. |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_ISTRATEGY_MQH
#define SRP_CORE_INTERFACES_ISTRATEGY_MQH

#include "IModule.mqh"

interface IStrategy : public IModule
  {
   //--- Stable identity for weighting, journalling and statistics.
   ENUM_SRP_STRATEGY_ID StrategyId(void);
   string            StrategyName(void);

   //--- Runtime enable/disable without destroying the instance.
   bool              IsEnabled(void);
   void              SetEnabled(const bool enabled);

   //--- Aggregation weight when several strategies vote.
   double            Weight(void);
   void              SetWeight(const double weight);

   //--- The core question. MUST NOT mutate 'context'.
   //--- Returns false when the strategy has no opinion this pass.
   bool              Evaluate(const SDecisionContext &context,SSignal &signal);

   //--- Optional strategy-owned exit opinion, consulted by the
   //--- position manager. Lets a strategy close what it opened
   //--- without ever calling the trade API itself.
   bool              ShouldExit(const SDecisionContext &context,
                                const SPositionSnapshot &position,
                                ENUM_SRP_EXIT_REASON &reason);

   //--- Timeframes/history the strategy needs; the market data
   //--- service uses this to guarantee data availability at init.
   int               RequiredBars(void);
  };

#endif // SRP_CORE_INTERFACES_ISTRATEGY_MQH
//+------------------------------------------------------------------+
