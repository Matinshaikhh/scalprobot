//+------------------------------------------------------------------+
//|                                              CTimeStopRule.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Trade : closes positions that have outlived their thesis.              |
//|                                                                  |
//|   A scalp that has not worked within its expected horizon is no longer   |
//|   a scalp - it is an unplanned swing trade. Closing on time keeps the    |
//|   strategy's actual holding period aligned with the one it was tested    |
//|   on, which is what makes backtest statistics meaningful.               |
//|                                                                  |
//|   Also handles the session-end flatten (e.g. no positions over the       |
//|   weekend), because both are "close due to the clock".                   |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_CTIMESTOPRULE_MQH
#define SRP_TRADE_CTIMESTOPRULE_MQH

#include "../Core/Base/CPositionRuleBase.mqh"
#include "../Core/Interfaces/IClock.mqh"

class CTimeStopRule : public CPositionRuleBase
  {
private:
   int               m_max_age_minutes;
   bool              m_only_if_losing;     // give winners more room
   bool              m_close_before_weekend;
   int               m_weekend_close_minutes; // minutes before Fri close
   IClock           *m_clock;              // borrowed

   bool              IsWeekendCloseDue(const SDecisionContext &context) const;

protected:
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const SSymbolSpec &spec,
                                const SPositionSnapshot &position,
                                SPositionAction &action) override;

public:
                     CTimeStopRule(const int max_age_minutes,
                                   IClock *clock,
                                   ILogger *logger);
                    ~CTimeStopRule(void) { }

   void              SetMaxAgeMinutes(const int minutes);
   void              SetOnlyIfLosing(const bool value);
   void              SetWeekendClose(const bool enabled,const int minutes_before);
  };

#endif // SRP_TRADE_CTIMESTOPRULE_MQH
//+------------------------------------------------------------------+
