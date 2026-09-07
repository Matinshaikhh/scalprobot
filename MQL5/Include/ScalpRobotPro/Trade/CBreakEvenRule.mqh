//+------------------------------------------------------------------+
//|                                             CBreakEvenRule.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Trade : moves the stop to entry once a profit threshold is met.        |
//|                                                                  |
//|   Low priority NUMBER (runs early) because eliminating risk on a         |
//|   position outranks optimising its profit.                              |
//|                                                                  |
//|   Applies ONCE per position - the base snapshot carries a               |
//|   break_even_applied flag - so it cannot fight the trailing rule for     |
//|   control of the same stop.                                             |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_CBREAKEVENRULE_MQH
#define SRP_TRADE_CBREAKEVENRULE_MQH

#include "../Core/Base/CPositionRuleBase.mqh"

class CBreakEvenRule : public CPositionRuleBase
  {
private:
   double            m_trigger_points;
   double            m_offset_points;      // lock in a few points, not zero
   bool              m_only_after_partial;

protected:
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const SSymbolSpec &spec,
                                const SPositionSnapshot &position,
                                SPositionAction &action) override;

public:
                     CBreakEvenRule(const double trigger_points,
                                    const double offset_points,
                                    ILogger *logger);
                    ~CBreakEvenRule(void) { }

   void              SetTriggerPoints(const double points);
   void              SetOffsetPoints(const double points);
   void              SetOnlyAfterPartial(const bool value);
  };

#endif // SRP_TRADE_CBREAKEVENRULE_MQH
//+------------------------------------------------------------------+
