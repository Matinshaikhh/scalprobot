//+------------------------------------------------------------------+
//|                                           CSessionCalendar.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Filters : resolves which trading session a moment belongs to.          |
//|                                                                  |
//|   RESPONSIBILITY (one only): time-to-session mapping, including the      |
//|   broker's GMT offset and windows that wrap midnight.                   |
//|                                                                  |
//|   Shared by CSessionFilter, CMarketRegimeAnalyzer and the dashboard.     |
//|   Because it takes its time from IClock rather than TimeCurrent(), the   |
//|   session logic can be verified against any historical timestamp.        |
//+------------------------------------------------------------------+
#ifndef SRP_FILTERS_CSESSIONCALENDAR_MQH
#define SRP_FILTERS_CSESSIONCALENDAR_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CSessionCalendar : public IModule
  {
private:
   CModuleIdentity   m_id;
   IClock           *m_clock;              // borrowed

   //--- Session windows in GMT minutes-since-midnight, converted to
   //--- server time using the resolved offset.
   int               m_sydney_open_gmt;
   int               m_sydney_close_gmt;
   int               m_tokyo_open_gmt;
   int               m_tokyo_close_gmt;
   int               m_london_open_gmt;
   int               m_london_close_gmt;
   int               m_newyork_open_gmt;
   int               m_newyork_close_gmt;
   int               m_server_offset_minutes;
   bool              m_offset_resolved;

   int               ToServerMinutes(const int gmt_minutes) const;
   bool              IsInWindow(const datetime moment,
                                const int open_gmt,
                                const int close_gmt) const;

public:
                     CSessionCalendar(IClock *clock,ILogger *logger);
                    ~CSessionCalendar(void) { }

   //--- Windows are configurable because brokers differ and because
   //--- daylight saving shifts them twice a year.
   void              SetSydneyWindow(const int open_gmt_minutes,
                                     const int close_gmt_minutes);
   void              SetTokyoWindow(const int open_gmt_minutes,
                                    const int close_gmt_minutes);
   void              SetLondonWindow(const int open_gmt_minutes,
                                     const int close_gmt_minutes);
   void              SetNewYorkWindow(const int open_gmt_minutes,
                                      const int close_gmt_minutes);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Queries -------------------------------------------------------
   //--- The overlap is reported in preference to a single session,
   //--- because London/NY overlap behaves unlike either alone.
   ENUM_SRP_SESSION  ResolveSession(const datetime moment) const;
   bool              IsSessionActive(const ENUM_SRP_SESSION session,
                                     const datetime moment) const;
   bool              IsOverlapActive(const datetime moment) const;

   //--- Minutes since the active session opened / until it closes.
   int               MinutesSinceOpen(const ENUM_SRP_SESSION session,
                                      const datetime moment) const;
   int               MinutesUntilClose(const ENUM_SRP_SESSION session,
                                       const datetime moment) const;

   static string     SessionToString(const ENUM_SRP_SESSION session);
  };

#endif // SRP_FILTERS_CSESSIONCALENDAR_MQH
//+------------------------------------------------------------------+
