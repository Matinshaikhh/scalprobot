//+------------------------------------------------------------------+
//|                                          CAccountInfoProvider.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : samples account state once per pipeline pass.             |
//|                                                                  |
//|   RESPONSIBILITY (one only): fill an SAccountSnapshot. Sampling    |
//|   once per pass rather than per-call guarantees that the risk      |
//|   layer, the guards and the dashboard all reason about the SAME    |
//|   equity value - otherwise a guard can pass on one equity reading  |
//|   while the sizer uses another, producing a position that violates |
//|   the very limit that just approved it.                            |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CACCOUNTINFOPROVIDER_MQH
#define SRP_CORE_CACCOUNTINFOPROVIDER_MQH

#include "Interfaces/IModule.mqh"
#include "Interfaces/ILogger.mqh"
#include "Base/CModuleIdentity.mqh"

class CAccountInfoProvider : public IModule
  {
private:
   CModuleIdentity   m_id;
   SAccountSnapshot  m_snapshot;
   bool              m_static_resolved;   // login/currency/leverage etc.

   void              ResolveStaticFields(void);

public:
                     CAccountInfoProvider(ILogger *logger);
                    ~CAccountInfoProvider(void) { }

   //--- IModule -----------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Sampling ----------------------------------------------------
   bool              Refresh(void);
   void              GetSnapshot(SAccountSnapshot &out) const { out=m_snapshot; }

   //--- Convenience predicates used by guards and the engine.
   bool              IsTradingPermitted(void) const;
   bool              IsHedging(void)          const { return(m_snapshot.is_hedging); }
   string            Currency(void)           const { return(m_snapshot.currency); }
  };

#endif // SRP_CORE_CACCOUNTINFOPROVIDER_MQH
//+------------------------------------------------------------------+
