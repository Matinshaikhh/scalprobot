//+------------------------------------------------------------------+
//|                                                      ILogger.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : logging abstraction.                         |
//|                                                                  |
//|   Every module receives an ILogME* by constructor injection and  |
//|   never calls Print() directly. That keeps output routable       |
//|   (file / terminal / push / alert) and silenceable during        |
//|   optimisation passes without touching module code.              |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_ILOGGER_MQH
#define SRP_CORE_INTERFACES_ILOGGER_MQH

#include "../Types/Enums.mqh"

interface ILogger
  {
   //--- Primary entry point. 'context' names the emitting module.
   void              Log(const ENUM_SRP_LOG_LEVEL level,
                         const string context,
                         const string message);

   //--- Convenience levels (implementations delegate to Log).
   void              Trace(const string context,const string message);
   void              Debug(const string context,const string message);
   void              Info(const string context,const string message);
   void              Warn(const string context,const string message);
   void              Error(const string context,const string message);
   void              Fatal(const string context,const string message);

   //--- Terminal error codes are logged through a dedicated path so
   //--- the formatter can decorate them with human-readable text.
   void              LogRetcode(const string context,
                                const string operation,
                                const uint retcode);

   //--- Guard for expensive message construction at call sites.
   bool              IsEnabled(const ENUM_SRP_LOG_LEVEL level);

   //--- Runtime verbosity control (used by the optimisation guard).
   void              SetMinimumLevel(const ENUM_SRP_LOG_LEVEL level);
   ENUM_SRP_LOG_LEVEL MinimumLevel(void);

   //--- Force buffered sinks to persist.
   void              Flush(void);
  };

#endif // SRP_CORE_INTERFACES_ILOGGER_MQH
//+------------------------------------------------------------------+
