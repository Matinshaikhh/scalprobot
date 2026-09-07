//+------------------------------------------------------------------+
//|                                                CTickThrottle.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : decides whether an incoming tick deserves a full pass.    |
//|                                                                  |
//|   RESPONSIBILITY (one only): rate-limiting. On M1 gold the tick    |
//|   rate can exceed what a full pipeline pass costs, so this class   |
//|   answers "process or skip?" - and nothing else. Extracting it     |
//|   keeps performance tuning out of the engine's control flow.       |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CTICKTHROTTLE_MQH
#define SRP_CORE_CTICKTHROTTLE_MQH

#include "Interfaces/IClock.mqh"

class CTickThrottle
  {
private:
   IClock           *m_clock;            // borrowed
   ulong             m_last_pass_ms;
   int               m_min_interval_ms;
   bool              m_new_bar_always_passes;
   long              m_processed;
   long              m_skipped;

public:
                     CTickThrottle(void);
                    ~CTickThrottle(void) { }

   void              SetClock(IClock *clock)                  { m_clock=clock; }
   void              SetMinIntervalMs(const int ms)           { m_min_interval_ms=(ms<0?0:ms); }
   void              SetNewBarAlwaysPasses(const bool value)  { m_new_bar_always_passes=value; }

   //--- The decision. 'is_new_bar' bypasses the throttle so bar-close
   //--- logic is never starved by a busy tick stream.
   bool              ShouldProcess(const bool is_new_bar);

   //--- Diagnostics ------------------------------------------------
   long              ProcessedCount(void) const { return(m_processed); }
   long              SkippedCount(void)   const { return(m_skipped); }
   void              ResetCounters(void)        { m_processed=0; m_skipped=0; }
  };

//+------------------------------------------------------------------+
CTickThrottle::CTickThrottle(void)
  : m_clock(NULL),
    m_last_pass_ms(0),
    m_min_interval_ms(0),
    m_new_bar_always_passes(true),
    m_processed(0),
    m_skipped(0)
  {
  }
//+------------------------------------------------------------------+
bool CTickThrottle::ShouldProcess(const bool is_new_bar)
  {
   if(m_new_bar_always_passes && is_new_bar)
     {
      m_processed++;
      if(m_clock!=NULL)
         m_last_pass_ms=m_clock.TickCountMs();
      return(true);
     }
   if(m_min_interval_ms<=0 || m_clock==NULL)
     {
      m_processed++;
      return(true);
     }
   const ulong now=m_clock.TickCountMs();
   if(now-m_last_pass_ms<(ulong)m_min_interval_ms)
     {
      m_skipped++;
      return(false);
     }
   m_last_pass_ms=now;
   m_processed++;
   return(true);
  }

#endif // SRP_CORE_CTICKTHROTTLE_MQH
//+------------------------------------------------------------------+
