//+------------------------------------------------------------------+
//|                                                IPositionRule.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : one in-trade management behaviour.           |
//|                                                                  |
//|   Break-even, trailing, partial close and time-stop are each a     |
//|   separate rule rather than branches inside one god-method. The    |
//|   position manager simply iterates the rules it was given, which   |
//|   is why new management behaviour never destabilises existing      |
//|   behaviour.                                                      |
//|                                                                  |
//|   A rule DECIDES; it never executes. It returns an intent that     |
//|   the position manager forwards to ITradeExecutor.                |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_IPOSITIONRULE_MQH
#define SRP_CORE_INTERFACES_IPOSITIONRULE_MQH

#include "IModule.mqh"

//--- What a rule wants done to a position.
enum ENUM_SRP_RULE_ACTION
  {
   SRP_RULE_ACTION_NONE,
   SRP_RULE_ACTION_MODIFY_STOPS,
   SRP_RULE_ACTION_CLOSE_PARTIAL,
   SRP_RULE_ACTION_CLOSE_FULL
  };

//--- The intent produced by a rule.
struct SPositionAction
  {
   ENUM_SRP_RULE_ACTION action;
   double            new_stop_loss;
   double            new_take_profit;
   double            close_volume;
   ENUM_SRP_EXIT_REASON reason;
   string            rule_name;
   string            explanation;

                     SPositionAction(void) { Reset(); }
   void              Reset(void)
     {
      action=SRP_RULE_ACTION_NONE;
      new_stop_loss=SRP_INVALID_PRICE;
      new_take_profit=SRP_INVALID_PRICE;
      close_volume=0.0;
      reason=SRP_EXIT_UNKNOWN;
      rule_name=""; explanation="";
     }
  };

interface IPositionRule : public IModule
  {
   string            RuleName(void);
   bool              IsEnabled(void);
   void              SetEnabled(const bool enabled);

   //--- Lower value == evaluated earlier. Protective rules run before
   //--- profit-taking rules so capital preservation always wins.
   int               Priority(void);

   //--- Decide. MUST NOT call the trade API and MUST NOT mutate the
   //--- position snapshot.
   void              Evaluate(const SDecisionContext &context,
                              const SSymbolSpec &spec,
                              const SPositionSnapshot &position,
                              SPositionAction &action);
  };

#endif // SRP_CORE_INTERFACES_IPOSITIONRULE_MQH
//+------------------------------------------------------------------+
