//+------------------------------------------------------------------+
//|                                                    INotifier.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : outbound operator alerting.                  |
//|                                                                  |
//|   Separate from ILogSink: a sink records history, a notifier       |
//|   interrupts a human. Keeping them apart stops the log from        |
//|   spamming push messages.                                         |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_INOTIFIER_MQH
#define SRP_CORE_INTERFACES_INOTIFIER_MQH

#include "IModule.mqh"

interface INotifier : public IModule
  {
   string            ChannelName(void);
   bool              IsEnabled(void);
   void              SetEnabled(const bool enabled);

   //--- Rate-limited by the implementation; callers need not throttle.
   bool              Notify(const ENUM_SRP_LOG_LEVEL severity,
                            const string subject,
                            const string body);
  };

#endif // SRP_CORE_INTERFACES_INOTIFIER_MQH
//+------------------------------------------------------------------+
