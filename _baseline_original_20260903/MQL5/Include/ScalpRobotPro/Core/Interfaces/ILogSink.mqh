//+------------------------------------------------------------------+
//|                                                     ILogSink.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : one output destination for log records.      |
//|                                                                  |
//|   CLogger owns a collection of ILogSink. Adding a new            |
//|   destination (database, socket, webhook) means adding a class -  |
//|   never editing CLogger. Open/Closed Principle.                  |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_ILOGSINK_MQH
#define SRP_CORE_INTERFACES_ILOGSINK_MQH

#include "../Types/Enums.mqh"

interface ILogSink
  {
   string                 SinkName(void);
   ENUM_SRP_LOG_SINK_KIND Kind(void);

   //--- Open the underlying resource. False => sink is skipped.
   bool                   Open(void);
   void                   Close(void);

   //--- Receives an already-formatted record plus its level so the
   //--- sink can apply its own threshold (e.g. push only on ERROR).
   void                   Write(const ENUM_SRP_LOG_LEVEL level,
                                const string formatted_record);

   void                   Flush(void);

   //--- Per-sink threshold, independent of the logger's global one.
   void                   SetThreshold(const ENUM_SRP_LOG_LEVEL level);
   bool                   Accepts(const ENUM_SRP_LOG_LEVEL level);
  };

#endif // SRP_CORE_INTERFACES_ILOGSINK_MQH
//+------------------------------------------------------------------+
