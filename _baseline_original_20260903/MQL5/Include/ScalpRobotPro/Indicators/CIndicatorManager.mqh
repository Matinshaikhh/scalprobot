//+------------------------------------------------------------------+
//|                                           CIndicatorManager.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Indicators : registry and single refresh point for indicators.      |
//|                                                                  |
//|   RESPONSIBILITY (one only): own the indicator collection, refresh    |
//|   it exactly once per pass, and hand out borrowed pointers by id.     |
//|                                                                  |
//|   WHY IT EARNS ITS PLACE                                             |
//|   Without it, three strategies each create their own ATR handle:      |
//|   three terminal calculations, three chances to leak a handle, and    |
//|   three values that can differ mid-tick. With it: one handle, one     |
//|   refresh, one value, released deterministically.                     |
//|                                                                  |
//|   OWNERSHIP: owns its IIndicator instances and deletes them.          |
//+------------------------------------------------------------------+
#ifndef SRP_INDICATORS_CINDICATORMANAGER_MQH
#define SRP_INDICATORS_CINDICATORMANAGER_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IIndicator.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CIndicatorManager : public IModule
  {
private:
   CModuleIdentity   m_id;
   IIndicator       *m_indicators[];      // OWNED
   int               m_ready_count;
   int               m_failed_count;
   ulong             m_last_refresh_sequence;

public:
                     CIndicatorManager(ILogger *logger);
                    ~CIndicatorManager(void);

   //--- Composition. Takes ownership; returns false if refused, in
   //--- which case the caller must delete the indicator.
   bool              Add(IIndicator *indicator);

   //--- Lookup by stable id. Returns a BORROWED pointer - callers must
   //--- never delete it. Strategies cache these at Initialize().
   IIndicator       *Find(const ENUM_SRP_INDICATOR_ID id) const;
   bool              Has(const ENUM_SRP_INDICATOR_ID id) const;
   int               Count(void) const { return(ArraySize(m_indicators)); }

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   //--- Creates every handle. Fails if ANY indicator fails, because a
   //--- strategy silently running without its indicator is worse than
   //--- refusing to start.
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Pipeline stage 2. Refreshes all buffers once. Returns false
   //--- when any indicator is not ready, which aborts the pass rather
   //--- than letting a strategy read a stale buffer.
   bool              RefreshAll(const ulong snapshot_sequence);

   bool              AllReady(void) const;
   int               ReadyCount(void) const { return(m_ready_count); }
  };

#endif // SRP_INDICATORS_CINDICATORMANAGER_MQH
//+------------------------------------------------------------------+
