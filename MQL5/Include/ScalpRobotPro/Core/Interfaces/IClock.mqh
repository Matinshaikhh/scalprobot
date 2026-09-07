//+------------------------------------------------------------------+
//|                                                       IClock.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : time abstraction.                            |
//|                                                                  |
//|   Every module asks the clock instead of calling TimeCurrent()    |
//|   directly. This is what makes session, schedule, holiday and     |
//|   news logic deterministically testable - inject a fake clock and |
//|   any moment in history can be replayed.                          |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_ICLOCK_MQH
#define SRP_CORE_INTERFACES_ICLOCK_MQH

#include "../Types/Structs.mqh"

interface IClock
  {
   //--- Broker server time.
   datetime          ServerTime(void);
   //--- Millisecond resolution, for latency measurement.
   ulong             TickCountMs(void);
   //--- Local terminal time and GMT, for calendar conversions.
   datetime          LocalTime(void);
   datetime          GmtTime(void);
   //--- Server-to-GMT offset in seconds, resolved once at startup.
   int               ServerGmtOffsetSeconds(void);

   //--- Decomposed server time, so callers avoid repeated TimeToStruct.
   void              ServerTimeStruct(MqlDateTime &out);

   //--- True while running inside the strategy tester.
   bool              IsTesting(void);
   bool              IsOptimization(void);
   bool              IsVisualMode(void);
  };

#endif // SRP_CORE_INTERFACES_ICLOCK_MQH
//+------------------------------------------------------------------+
