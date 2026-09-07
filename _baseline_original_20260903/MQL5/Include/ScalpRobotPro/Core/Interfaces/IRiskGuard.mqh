//+------------------------------------------------------------------+
//|                                                   IRiskGuard.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : capital-protection contract.                 |
//|                                                                  |
//|   A guard is distinct from a filter. A filter asks "is this a     |
//|   good moment to trade?"; a guard asks "is the ACCOUNT still      |
//|   allowed to trade at all?" Guards may therefore demand that      |
//|   open positions be liquidated, which filters may never do.       |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_IRISKGUARD_MQH
#define SRP_CORE_INTERFACES_IRISKGUARD_MQH

#include "IModule.mqh"

interface IRiskGuard : public IModule
  {
   string            GuardName(void);
   bool              IsEnabled(void);
   void              SetEnabled(const bool enabled);

   //--- May a NEW position be opened?
   bool              AllowsNewEntry(const SDecisionContext &context,
                                    ENUM_SRP_VETO_REASON &reason,
                                    string &detail);

   //--- Must existing exposure be closed right now? This is the only
   //--- place in the system, other than the position manager's own
   //--- rules, that can force liquidation.
   bool              DemandsFlatten(const SDecisionContext &context,
                                    ENUM_SRP_EXIT_REASON &reason,
                                    string &detail);

   //--- True once a guard has latched (e.g. daily loss limit hit).
   //--- Latched guards stay tripped until Rearm() is called by the
   //--- session-boundary logic.
   bool              IsTripped(void);
   void              Rearm(void);
  };

#endif // SRP_CORE_INTERFACES_IRISKGUARD_MQH
//+------------------------------------------------------------------+
