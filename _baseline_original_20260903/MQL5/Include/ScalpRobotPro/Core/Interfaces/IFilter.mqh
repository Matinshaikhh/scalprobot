//+------------------------------------------------------------------+
//|                                                      IFilter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : veto contract.                               |
//|                                                                  |
//|   A filter answers exactly one question: "may a trade happen      |
//|   right now?" It never sizes, never executes, never generates a   |
//|   direction. Filters are deliberately dumb and independent so     |
//|   CFilterChain can run them in any order, and so a new filter is  |
//|   a new file rather than an edit to existing logic (Open/Closed). |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_IFILTER_MQH
#define SRP_CORE_INTERFACES_IFILTER_MQH

#include "IModule.mqh"

interface IFilter : public IModule
  {
   string                   FilterName(void);
   ENUM_SRP_FILTER_CATEGORY Category(void);

   bool                     IsEnabled(void);
   void                     SetEnabled(const bool enabled);

   //--- A blocking filter aborts the pass; a non-blocking one only
   //--- records an advisory verdict for the dashboard.
   bool                     IsBlocking(void);

   //--- Evaluation order within the chain. Cheap, high-rejection
   //--- filters get a low value so the chain short-circuits early.
   int                      Priority(void);

   //--- The verdict. 'direction' is supplied because some filters are
   //--- directional (e.g. trend alignment). MUST NOT mutate context.
   void                     Evaluate(const SDecisionContext &context,
                                     const ENUM_SRP_SIGNAL_DIRECTION direction,
                                     SFilterVerdict &verdict);
  };

#endif // SRP_CORE_INTERFACES_IFILTER_MQH
//+------------------------------------------------------------------+
