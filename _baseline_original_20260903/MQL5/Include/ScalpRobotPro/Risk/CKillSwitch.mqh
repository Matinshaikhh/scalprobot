//+------------------------------------------------------------------+
//|                                                CKillSwitch.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : the unconditional last line of defence.                        |
//|                                                                  |
//|   RESPONSIBILITY (one only): permanently stop all trading when an        |
//|   unrecoverable condition is detected, and stay stopped across           |
//|   restarts until a human clears it.                                     |
//|                                                                  |
//|   DISTINCT FROM A GUARD                                                 |
//|   A guard measures one metric and can rearm at a session boundary. The   |
//|   kill switch does not rearm - it requires deliberate human action.      |
//|   Triggers include an equity floor breach, an error storm, a terminal    |
//|   trading-disabled condition, and an explicit operator command.          |
//|                                                                  |
//|   It publishes SRP_EVENT_KILL_SWITCH_ACTIVATED; the engine listens and   |
//|   transitions to HALTED. The switch itself never closes a position -     |
//|   detection and reaction stay separated even here.                      |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CKILLSWITCH_MQH
#define SRP_RISK_CKILLSWITCH_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IStateStore.mqh"
#include "../Core/Interfaces/IEventPublisher.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CKillSwitch : public IModule
  {
private:
   CModuleIdentity   m_id;
   IStateStore      *m_state;              // borrowed
   IEventPublisher  *m_publisher;          // borrowed

   bool              m_activated;
   string            m_activation_reason;
   datetime          m_activated_at;

   //--- Trigger thresholds.
   bool              m_equity_floor_enabled;
   double            m_equity_floor_value;
   bool              m_error_storm_enabled;
   int               m_error_storm_threshold;
   bool              m_flatten_on_activation;

   void              Persist(void);
   void              Restore(void);

public:
                     CKillSwitch(IStateStore *state,
                                 IEventPublisher *publisher,
                                 ILogger *logger);
                    ~CKillSwitch(void) { }

   void              SetEquityFloor(const bool enabled,const double floor_value);
   void              SetErrorStormTrigger(const bool enabled,const int threshold);
   void              SetFlattenOnActivation(const bool value);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   //--- Restores a previously latched activation, so a restart cannot
   //--- silently resume trading after a kill.
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override;

   //--- Evaluated every pass by the engine.
   bool              Evaluate(const SDecisionContext &context,
                              const int consecutive_errors);

   //--- Explicit activation, available to the operator and to modules
   //--- that detect an unrecoverable state.
   void              Activate(const string reason,const datetime now);

   //--- Deliberately requires a human. Not called from any automation.
   bool              ClearByOperator(const string acknowledgement);

   bool              IsActivated(void)      const { return(m_activated); }
   string            Reason(void)           const { return(m_activation_reason); }
   bool              ShouldFlatten(void)    const { return(m_flatten_on_activation); }
  };

#endif // SRP_RISK_CKILLSWITCH_MQH
//+------------------------------------------------------------------+
