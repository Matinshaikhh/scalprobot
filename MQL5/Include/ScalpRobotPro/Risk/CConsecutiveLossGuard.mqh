//+------------------------------------------------------------------+
//|                                      CConsecutiveLossGuard.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : pauses after a run of losing trades.                           |
//|                                                                  |
//|   A losing streak is the earliest available evidence that market         |
//|   conditions no longer match the strategy's assumptions. Pausing on it   |
//|   is cheaper than waiting for the drawdown guard to fire.               |
//|                                                                  |
//|   It learns the streak from SRP_EVENT_POSITION_CLOSED via the event      |
//|   bus, so it never polls history and never touches the trade API.       |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CCONSECUTIVELOSSGUARD_MQH
#define SRP_RISK_CCONSECUTIVELOSSGUARD_MQH

#include "../Core/Base/CRiskGuardBase.mqh"
#include "../Core/Interfaces/IStateStore.mqh"

class CConsecutiveLossGuard : public CRiskGuardBase
  {
private:
   int               m_loss_limit;
   int               m_current_streak;
   int               m_cooldown_minutes;
   datetime          m_cooldown_until;
   IStateStore      *m_state;              // borrowed

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnRearm(void) override;
   virtual bool      OnAllowsNewEntry(const SDecisionContext &context,
                                      ENUM_SRP_VETO_REASON &reason,
                                      string &detail) override;

public:
                     CConsecutiveLossGuard(const int loss_limit,
                                           IStateStore *state,
                                           ILogger *logger);
                    ~CConsecutiveLossGuard(void) { }

   void              SetLossLimit(const int limit);
   //--- After the cooldown expires the guard rearms itself, so a streak
   //--- causes a pause rather than a permanent stop.
   void              SetCooldownMinutes(const int minutes);

   //--- Bus entry point: updates the streak from closed-trade events.
   virtual void      HandleEvent(const SEventPayload &payload) override;

   int               CurrentStreak(void) const { return(m_current_streak); }
  };

#endif // SRP_RISK_CCONSECUTIVELOSSGUARD_MQH
//+------------------------------------------------------------------+
