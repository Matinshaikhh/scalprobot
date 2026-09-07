//+------------------------------------------------------------------+
//|                                           CRiskGuardChain.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : Composite over IRiskGuard.                                     |
//|                                                                  |
//|   RESPONSIBILITY (one only): run every guard and combine the answers.    |
//|   Chain of Responsibility for entry permission, plus a fan-out sweep     |
//|   for flatten demands.                                                  |
//|                                                                  |
//|   IMPORTANT ASYMMETRY                                                   |
//|   Entry permission SHORT-CIRCUITS on the first refusal - one veto is     |
//|   enough. Flatten demands do NOT short-circuit: every guard is asked,    |
//|   because the reason matters for the journal and because several guards  |
//|   may want to flatten for different reasons simultaneously.             |
//|                                                                  |
//|   OWNERSHIP: owns its guards and deletes them.                          |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CRISKGUARDCHAIN_MQH
#define SRP_RISK_CRISKGUARDCHAIN_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IRiskGuard.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CRiskGuardChain : public IModule
  {
private:
   CModuleIdentity   m_id;
   IRiskGuard       *m_guards[];           // OWNED

   //--- Last-pass results, surfaced on the dashboard so the user can see
   //--- exactly which guard is blocking and why.
   ENUM_SRP_VETO_REASON m_last_veto_reason;
   string            m_last_veto_guard;
   string            m_last_veto_detail;
   int               m_tripped_count;

public:
                     CRiskGuardChain(ILogger *logger);
                    ~CRiskGuardChain(void);

   //--- Composition. Takes ownership.
   bool              Add(IRiskGuard *guard);
   int               Count(void) const { return(ArraySize(m_guards)); }
   IRiskGuard       *At(const int index) const;
   IRiskGuard       *FindByName(const string name) const;

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override;

   //--- Pipeline stage 7. Short-circuits on the first refusal.
   bool              AllowsNewEntry(const SDecisionContext &context,
                                    ENUM_SRP_VETO_REASON &reason,
                                    string &detail);

   //--- Asks every guard. Returns true when at least one demands a
   //--- flatten, reporting the most severe reason.
   bool              AnyDemandsFlatten(const SDecisionContext &context,
                                       ENUM_SRP_EXIT_REASON &reason,
                                       string &detail);

   //--- Called by the engine at the day boundary to rearm latched guards.
   void              RearmAll(void);
   int               TrippedCount(void) const { return(m_tripped_count); }

   //--- Diagnostics for the dashboard -------------------------------
   ENUM_SRP_VETO_REASON LastVetoReason(void) const { return(m_last_veto_reason); }
   string            LastVetoGuard(void)     const { return(m_last_veto_guard); }
   string            LastVetoDetail(void)    const { return(m_last_veto_detail); }
  };

#endif // SRP_RISK_CRISKGUARDCHAIN_MQH
//+------------------------------------------------------------------+
