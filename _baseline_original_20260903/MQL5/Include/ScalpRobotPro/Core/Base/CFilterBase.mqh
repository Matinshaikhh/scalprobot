//+------------------------------------------------------------------+
//|                                                  CFilterBase.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Base : abstract base for every filter.                    |
//|                                                                  |
//|   Absorbs identity, category, priority, enable flag and verdict   |
//|   stamping. Concrete filters implement OnEvaluate only, and they  |
//|   cannot forget to fill the verdict metadata because the base     |
//|   does it for them.                                              |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_BASE_CFILTERBASE_MQH
#define SRP_CORE_BASE_CFILTERBASE_MQH

#include "../Interfaces/IFilter.mqh"
#include "CModuleIdentity.mqh"

class CFilterBase : public IFilter
  {
protected:
   CModuleIdentity          m_id;
   ENUM_SRP_FILTER_CATEGORY m_category;
   int                      m_priority;
   bool                     m_blocking;
   SFilterVerdict           m_last_verdict;
   long                     m_pass_count;
   long                     m_veto_count;

   //--- Sole extension point. Implementations set only 'passed',
   //--- 'veto_reason' and 'detail'.
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const ENUM_SRP_SIGNAL_DIRECTION direction,
                                SFilterVerdict &verdict)=0;

   virtual bool      OnInitialize(void)                    { return(true); }
   virtual void      OnShutdown(void)                      { }
   virtual void      OnValidate(SValidationResult &result)  { }

   //--- Uniform veto helper, keeps subclasses terse and consistent.
   void              Veto(SFilterVerdict &verdict,
                          const ENUM_SRP_VETO_REASON reason,
                          const string detail)
     {
      verdict.passed      = false;
      verdict.veto_reason = reason;
      verdict.detail      = detail;
     }

public:
                     CFilterBase(const string name,
                                 const ENUM_SRP_FILTER_CATEGORY category,
                                 ILogger *logger,
                                 const int priority=100,
                                 const bool blocking=true)
     : m_category(category),
       m_priority(priority),
       m_blocking(blocking),
       m_pass_count(0),
       m_veto_count(0)
     {
      m_id.Configure(name,logger);
     }
   virtual          ~CFilterBase(void) { }

   //--- IModule -----------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }

   virtual bool      Initialize(void) override
     {
      if(m_id.IsInitialized())
         return(true);
      if(!OnInitialize())
        {
         m_id.SetHealth(SRP_HEALTH_CRITICAL,"filter initialisation failed");
         return(false);
        }
      m_id.SetInitialized(true);
      return(true);
     }

   virtual void      Validate(SValidationResult &result) override
     {
      if(m_priority<0)
         result.AddError(m_id.Name()+": priority must not be negative");
      OnValidate(result);
     }

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

   //--- IFilter -----------------------------------------------------
   virtual string                   FilterName(void) override { return(m_id.Name()); }
   virtual ENUM_SRP_FILTER_CATEGORY Category(void)   override { return(m_category); }
   virtual bool                     IsBlocking(void) override { return(m_blocking); }
   virtual int                      Priority(void)   override { return(m_priority); }

   virtual bool      IsEnabled(void) override { return(m_id.IsEnabled()); }
   virtual void      SetEnabled(const bool enabled) override { m_id.SetEnabled(enabled); }

   //--- Template method: stamps metadata, delegates the decision.
   virtual void      Evaluate(const SDecisionContext &context,
                              const ENUM_SRP_SIGNAL_DIRECTION direction,
                              SFilterVerdict &verdict) override
     {
      verdict.Reset();
      verdict.filter_name = m_id.Name();
      verdict.category    = m_category;
      verdict.is_blocking = m_blocking;

      //--- A disabled filter is transparent, never a veto.
      if(!m_id.IsEnabled())
        {
         verdict.detail="disabled";
         m_last_verdict=verdict;
         return;
        }

      OnEvaluate(context,direction,verdict);

      if(verdict.passed) m_pass_count++;
      else               m_veto_count++;

      m_last_verdict=verdict;
     }

   //--- Diagnostics ------------------------------------------------
   void              LastVerdict(SFilterVerdict &out) const { out=m_last_verdict; }
   long              PassCount(void) const { return(m_pass_count); }
   long              VetoCount(void) const { return(m_veto_count); }
   void              ResetCounters(void)   { m_pass_count=0; m_veto_count=0; }
  };

#endif // SRP_CORE_BASE_CFILTERBASE_MQH
//+------------------------------------------------------------------+
