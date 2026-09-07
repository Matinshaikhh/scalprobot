//+------------------------------------------------------------------+
//|                                              CModuleIdentity.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Base : the shared state every module owns.                |
//|                                                                  |
//|   WHY THIS CLASS EXISTS                                          |
//|   MQL5 allows a single parent. Because IStrategy, IFilter,        |
//|   IRiskGuard and friends each already inherit IModule, their      |
//|   abstract bases cannot ALSO inherit a common CModuleBase to      |
//|   share boilerplate. Rather than duplicating that boilerplate     |
//|   in six base classes, every base COMPOSES one CModuleIdentity    |
//|   and delegates to it. Composition solves what inheritance        |
//|   cannot express here.                                           |
//|                                                                  |
//|   Single responsibility: hold a module's name, injected logger,   |
//|   enabled flag and health state. It makes no decisions.           |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_BASE_CMODULEIDENTITY_MQH
#define SRP_CORE_BASE_CMODULEIDENTITY_MQH

#include "../Interfaces/ILogger.mqh"
#include "../Types/Structs.mqh"

class CModuleIdentity
  {
private:
   string            m_name;
   ILogger          *m_logger;          // borrowed, never owned
   bool              m_enabled;
   bool              m_initialized;
   ENUM_SRP_HEALTH_STATUS m_health;
   string            m_health_detail;

public:
                     CModuleIdentity(void)
     : m_name("unnamed"),
       m_logger(NULL),
       m_enabled(true),
       m_initialized(false),
       m_health(SRP_HEALTH_OK),
       m_health_detail("")
     {
     }

   //--- Configured once by the owning base class constructor.
   void              Configure(const string name,ILogger *logger)
     {
      m_name=name;
      m_logger=logger;
     }

   string            Name(void)        const { return(m_name); }
   ILogger          *Logger(void)      const { return(m_logger); }
   bool              HasLogger(void)   const { return(m_logger!=NULL); }

   bool              IsEnabled(void)   const { return(m_enabled); }
   void              SetEnabled(const bool v)     { m_enabled=v; }

   bool              IsInitialized(void) const { return(m_initialized); }
   void              SetInitialized(const bool v) { m_initialized=v; }

   //--- Health bookkeeping. Modules set it; CHealthMonitor reads it.
   void              SetHealth(const ENUM_SRP_HEALTH_STATUS status,
                               const string detail)
     {
      m_health=status;
      m_health_detail=detail;
     }
   ENUM_SRP_HEALTH_STATUS Health(void) const { return(m_health); }
   string            HealthDetail(void) const { return(m_health_detail); }

   //--- Fills a report using the state above, so no base class has to
   //--- reimplement ReportHealth().
   void              FillReport(SHealthReport &report,const datetime now) const
     {
      report.module_name = m_name;
      report.status      = m_health;
      report.detail      = m_health_detail;
      report.checked_at  = now;
     }

   //--- Null-safe logging helpers. A module with no logger stays
   //--- silent instead of crashing, which matters during teardown.
   void              Log(const ENUM_SRP_LOG_LEVEL level,const string message) const
     {
      if(m_logger!=NULL)
         m_logger.Log(level,m_name,message);
     }
   void              Info(const string message)  const { Log(SRP_LOG_INFO,message);  }
   void              Warn(const string message)  const { Log(SRP_LOG_WARN,message);  }
   void              Error(const string message) const { Log(SRP_LOG_ERROR,message); }
   void              Debug(const string message) const { Log(SRP_LOG_DEBUG,message); }
  };

#endif // SRP_CORE_BASE_CMODULEIDENTITY_MQH
//+------------------------------------------------------------------+
