//+------------------------------------------------------------------+
//|                                            CPositionRuleBase.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Base : abstract base for in-trade management rules.       |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_BASE_CPOSITIONRULEBASE_MQH
#define SRP_CORE_BASE_CPOSITIONRULEBASE_MQH

#include "../Interfaces/IPositionRule.mqh"
#include "CModuleIdentity.mqh"

class CPositionRuleBase : public IPositionRule
  {
protected:
   CModuleIdentity   m_id;
   int               m_priority;
   long              m_action_count;

   virtual void      OnEvaluate(const SDecisionContext &context,
                                const SSymbolSpec &spec,
                                const SPositionSnapshot &position,
                                SPositionAction &action)=0;

   virtual bool      OnInitialize(void)                   { return(true); }
   virtual void      OnShutdown(void)                     { }
   virtual void      OnValidate(SValidationResult &result) { }

   //--- Intent helpers; keep subclasses declarative.
   void              RequestStops(SPositionAction &action,
                                  const double stop_loss,
                                  const double take_profit,
                                  const ENUM_SRP_EXIT_REASON reason,
                                  const string explanation)
     {
      action.action          = SRP_RULE_ACTION_MODIFY_STOPS;
      action.new_stop_loss   = stop_loss;
      action.new_take_profit = take_profit;
      action.reason          = reason;
      action.explanation     = explanation;
     }

   void              RequestPartialClose(SPositionAction &action,
                                         const double volume,
                                         const ENUM_SRP_EXIT_REASON reason,
                                         const string explanation)
     {
      action.action       = SRP_RULE_ACTION_CLOSE_PARTIAL;
      action.close_volume = volume;
      action.reason       = reason;
      action.explanation  = explanation;
     }

   void              RequestFullClose(SPositionAction &action,
                                      const ENUM_SRP_EXIT_REASON reason,
                                      const string explanation)
     {
      action.action      = SRP_RULE_ACTION_CLOSE_FULL;
      action.reason      = reason;
      action.explanation = explanation;
     }

public:
                     CPositionRuleBase(const string name,
                                       ILogger *logger,
                                       const int priority=100)
     : m_priority(priority),
       m_action_count(0)
     {
      m_id.Configure(name,logger);
     }
   virtual          ~CPositionRuleBase(void) { }

   //--- IModule -----------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }

   virtual bool      Initialize(void) override
     {
      if(m_id.IsInitialized())
         return(true);
      if(!OnInitialize())
        {
         m_id.SetHealth(SRP_HEALTH_CRITICAL,"rule initialisation failed");
         return(false);
        }
      m_id.SetInitialized(true);
      return(true);
     }

   virtual void      Validate(SValidationResult &result) override { OnValidate(result); }

   virtual void      Shutdown(void) override
     {
      OnShutdown();
      m_id.SetInitialized(false);
     }

   virtual void      ReportHealth(SHealthReport &report) override
     {
      m_id.FillReport(report,0);
     }

   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- IPositionRule -----------------------------------------------
   virtual string    RuleName(void) override { return(m_id.Name()); }
   virtual bool      IsEnabled(void) override { return(m_id.IsEnabled()); }
   virtual void      SetEnabled(const bool enabled) override { m_id.SetEnabled(enabled); }
   virtual int       Priority(void) override { return(m_priority); }

   virtual void      Evaluate(const SDecisionContext &context,
                              const SSymbolSpec &spec,
                              const SPositionSnapshot &position,
                              SPositionAction &action) override
     {
      action.Reset();
      action.rule_name=m_id.Name();
      if(!m_id.IsEnabled() || !m_id.IsInitialized())
         return;
      OnEvaluate(context,spec,position,action);
      if(action.action!=SRP_RULE_ACTION_NONE)
         m_action_count++;
     }

   long              ActionCount(void) const { return(m_action_count); }
  };

#endif // SRP_CORE_BASE_CPOSITIONRULEBASE_MQH
//+------------------------------------------------------------------+
