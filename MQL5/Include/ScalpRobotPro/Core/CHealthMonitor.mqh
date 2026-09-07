//+------------------------------------------------------------------+
//|                                               CHealthMonitor.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : periodic liveness sweep across every registered module.   |
//|                                                                  |
//|   RESPONSIBILITY (one only): poll IModule::ReportHealth on a       |
//|   schedule, aggregate the worst status, and publish a degradation  |
//|   event. It never repairs anything - remediation is the engine's   |
//|   decision. Separating detection from reaction keeps both simple.  |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CHEALTHMONITOR_MQH
#define SRP_CORE_CHEALTHMONITOR_MQH

#include "CModuleRegistry.mqh"
#include "Interfaces/IClock.mqh"
#include "Interfaces/IEventPublisher.mqh"
#include "Interfaces/ILogger.mqh"

class CHealthMonitor
  {
private:
   CModuleRegistry  *m_registry;         // borrowed
   IClock           *m_clock;            // borrowed
   ILogger          *m_logger;           // borrowed
   IEventPublisher  *m_publisher;        // borrowed
   ENUM_SRP_HEALTH_STATUS m_aggregate;
   datetime          m_last_check;
   int               m_interval_seconds;
   SHealthReport     m_reports[];
   string            m_summary;

public:
                     CHealthMonitor(void);
                    ~CHealthMonitor(void);

   void              SetCollaborators(CModuleRegistry *registry,
                                      IClock *clock,
                                      ILogger *logger,
                                      IEventPublisher *publisher);
   void              SetInterval(const int seconds);

   //--- Called every heartbeat; internally throttled, so calling it
   //--- often is free.
   void              Poll(void);

   //--- Force an immediate sweep, used right after initialisation.
   void              CheckNow(void);

   ENUM_SRP_HEALTH_STATUS AggregateStatus(void) const { return(m_aggregate); }
   string            Summary(void)              const { return(m_summary); }
   int               ReportCount(void)          const { return(ArraySize(m_reports)); }
   bool              GetReport(const int index,SHealthReport &out) const;
  };

#endif // SRP_CORE_CHEALTHMONITOR_MQH
//+------------------------------------------------------------------+
