//+------------------------------------------------------------------+
//|                                          CPartialCloseRule.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Trade : banks a fraction of the position at a profit threshold.        |
//|                                                                  |
//|   Fires at most once per position (the snapshot's partial_taken flag),   |
//|   and refuses to leave a remainder below the broker's minimum volume -   |
//|   attempting that produces an invalid-volume rejection and leaves the    |
//|   position unmanaged.                                                   |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_CPARTIALCLOSERULE_MQH
#define SRP_TRADE_CPARTIALCLOSERULE_MQH

#include "../Core/Base/CPositionRuleBase.mqh"

class CPartialCloseRule : public CPositionRuleBase
  {
private:
   double            m_trigger_points;
   double            m_close_percent;      // portion of current volume
   bool              m_move_stop_to_entry; // signals the break-even rule

   //--- Verifies both the closed part and the remainder are legal.
   bool              IsVolumeSplitLegal(const SSymbolSpec &spec,
                                        const double current_volume,
                                        double &close_volume) const;

protected:
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const SSymbolSpec &spec,
                                const SPositionSnapshot &position,
                                SPositionAction &action) override;

public:
                     CPartialCloseRule(const double trigger_points,
                                       const double close_percent,
                                       ILogger *logger);
                    ~CPartialCloseRule(void) { }

   void              SetTriggerPoints(const double points);
   void              SetClosePercent(const double percent);
   void              SetMoveStopToEntry(const bool value);
  };

#endif // SRP_TRADE_CPARTIALCLOSERULE_MQH
//+------------------------------------------------------------------+
