//+------------------------------------------------------------------+
//|                                               CRiskGuardBase.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Base : abstract base for every capital-protection guard.  |
//|                                                                  |
//|   Provides the latch mechanism shared by all guards: once a guard |
//|   trips it STAYS tripped until explicitly rearmed at a session    |
//|   boundary. Subclasses implement only their measurement logic.    |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_BASE_CRISKGUARDBASE_MQH
#define SRP_CORE_BASE_CRISKGUARDBASE_MQH

#include "../Interfaces/IRiskGuard.mqh"
#include "CModuleIdentity.mqh"

class CRiskGuardBase : public IRiskGuard
  {
protected:
   CModuleIdentity   m_id;
   bool              m_tripped;
   bool              m_latching;        // false => re-evaluated each pass
   string            m_trip_detail;
   datetime          m_tripped_at;

   //--- Extension points.
   virtual bool      OnAllowsNewEntry(const SDecisionContext &context,
                                      ENUM_SRP_VETO_REASON &reason,
                                      string &detail)=0;

   //--- Default: a guard blocks new entries but does not liquidate.
   //--- Only guards that genuinely must flatten override this.
   virtual bool      OnDemandsFlatten(const SDecisionContext &context,
                                      ENUM_SRP_EXIT_REASON &reason,
                                      string &detail)
     {
      reason=SRP_EXIT_UNKNOWN;
      return(false);
     }

   virtual bool      OnInitialize(void)                   { return(true); }
   virtual void      OnShutdown(void)                     { }
   virtual void      OnValidate(SValidationResult &result) { }
   virtual void      OnRearm(void)                        { }

   //--- Latch helper used by subclasses.
   void              Trip(const string detail,const datetime now)
     {
      if(m_tripped)
         return;
      m_tripped     = true;
      m_trip_detail = detail;
      m_tripped_at  = now;
      m_id.Warn("guard tripped: "+detail);
     }

public:
                     CRiskGuardBase(const string name,
                                    ILogger *logger,
                                    const bool latching=true)
     : m_tripped(false),
       m_latching(latching),
       m_trip_detail(""),
       m_tripped_at(0)
     {
      m_id.Configure(name,logger);
     }
   virtual          ~CRiskGuardBase(void) { }

   //--- IModule -----------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }

   virtual bool      Initialize(void) override
     {
      if(m_id.IsInitialized())
         return(true);
      if(!OnInitialize())
        {
         m_id.SetHealth(SRP_HEALTH_CRITICAL,"guard initialisation failed");
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
      if(m_tripped)
         m_id.SetHealth(SRP_HEALTH_DEGRADED,"tripped: "+m_trip_detail);
      m_id.FillReport(report,m_tripped_at);
     }

   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- IRiskGuard --------------------------------------------------
   virtual string    GuardName(void) override { return(m_id.Name()); }
   virtual bool      IsEnabled(void) override { return(m_id.IsEnabled()); }
   virtual void      SetEnabled(const bool enabled) override { m_id.SetEnabled(enabled); }

   virtual bool      IsTripped(void) override { return(m_tripped); }

   virtual void      Rearm(void) override
     {
      if(m_tripped)
         m_id.Info("guard rearmed");
      m_tripped=false;
      m_trip_detail="";
      m_tripped_at=0;
      OnRearm();
     }

   virtual bool      AllowsNewEntry(const SDecisionContext &context,
                                    ENUM_SRP_VETO_REASON &reason,
                                    string &detail) override
     {
      reason=SRP_VETO_NONE;
      detail="";
      if(!m_id.IsEnabled())
         return(true);
      //--- A latched guard short-circuits without re-measuring.
      if(m_latching && m_tripped)
        {
         reason=SRP_VETO_CIRCUIT_BREAKER;
         detail=m_trip_detail;
         return(false);
        }
      return(OnAllowsNewEntry(context,reason,detail));
     }

   virtual bool      DemandsFlatten(const SDecisionContext &context,
                                    ENUM_SRP_EXIT_REASON &reason,
                                    string &detail) override
     {
      reason=SRP_EXIT_UNKNOWN;
      detail="";
      if(!m_id.IsEnabled())
         return(false);
      return(OnDemandsFlatten(context,reason,detail));
     }

   //--- Diagnostics ------------------------------------------------
   string            TripDetail(void) const { return(m_trip_detail); }
   datetime          TrippedAt(void)  const { return(m_tripped_at); }
  };

#endif // SRP_CORE_BASE_CRISKGUARDBASE_MQH
//+------------------------------------------------------------------+
