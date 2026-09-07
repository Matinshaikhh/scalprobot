//+------------------------------------------------------------------+
//|                                                 CServerClock.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : the only place the system reads the wall clock.           |
//|                                                                  |
//|   Single responsibility: report time. Nothing else. Because every  |
//|   time-dependent module depends on IClock rather than on           |
//|   TimeCurrent(), the whole session/schedule/news subsystem becomes |
//|   deterministically testable.                                     |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CSERVERCLOCK_MQH
#define SRP_CORE_CSERVERCLOCK_MQH

#include "Interfaces/IClock.mqh"

class CServerClock : public IClock
  {
private:
   int               m_gmt_offset_seconds;
   bool              m_offset_resolved;

public:
                     CServerClock(void);
                    ~CServerClock(void) { }

   //--- Resolve the broker/GMT offset once; called at init.
   void              ResolveOffset(void);

   //--- IClock ------------------------------------------------------
   virtual datetime  ServerTime(void)  override { return(TimeCurrent()); }
   virtual ulong     TickCountMs(void) override { return(GetTickCount64()); }
   virtual datetime  LocalTime(void)   override { return(TimeLocal()); }
   virtual datetime  GmtTime(void)     override { return(TimeGMT()); }

   virtual int       ServerGmtOffsetSeconds(void) override;
   virtual void      ServerTimeStruct(MqlDateTime &out) override;

   virtual bool      IsTesting(void)      override { return((bool)MQLInfoInteger(MQL_TESTER)); }
   virtual bool      IsOptimization(void) override { return((bool)MQLInfoInteger(MQL_OPTIMIZATION)); }
   virtual bool      IsVisualMode(void)   override { return((bool)MQLInfoInteger(MQL_VISUAL_MODE)); }
  };

//+------------------------------------------------------------------+
CServerClock::CServerClock(void)
  : m_gmt_offset_seconds(0),
    m_offset_resolved(false)
  {
  }
//+------------------------------------------------------------------+
void CServerClock::ResolveOffset(void)
  {
   //--- TimeGMT is unreliable inside the tester, so the offset is
   //--- taken from the difference and cached rather than re-measured.
   m_gmt_offset_seconds=(int)(TimeCurrent()-TimeGMT());
   m_offset_resolved=true;
  }
//+------------------------------------------------------------------+
int CServerClock::ServerGmtOffsetSeconds(void)
  {
   if(!m_offset_resolved)
      ResolveOffset();
   return(m_gmt_offset_seconds);
  }
//+------------------------------------------------------------------+
void CServerClock::ServerTimeStruct(MqlDateTime &out)
  {
   TimeToStruct(TimeCurrent(),out);
  }

#endif // SRP_CORE_CSERVERCLOCK_MQH
//+------------------------------------------------------------------+
