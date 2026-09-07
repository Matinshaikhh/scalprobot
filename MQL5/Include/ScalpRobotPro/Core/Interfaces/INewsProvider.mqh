//+------------------------------------------------------------------+
//|                                                INewsProvider.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : economic-calendar data source.               |
//|                                                                  |
//|   Abstracts WHERE events come from (terminal calendar, CSV) away  |
//|   from WHAT is done with them (blackout evaluation). The news     |
//|   filter depends on this interface only, so switching source is   |
//|   a configuration decision. Dependency Inversion Principle.       |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_INEWSPROVIDER_MQH
#define SRP_CORE_INTERFACES_INEWSPROVIDER_MQH

#include "IModule.mqh"

interface INewsProvider : public IModule
  {
   ENUM_SRP_NEWS_SOURCE SourceKind(void);
   string            ProviderName(void);

   //--- True when the source is reachable and populated. A false
   //--- value lets the caller apply its fail-safe policy rather than
   //--- silently trading through unknown news.
   bool              IsAvailable(void);

   //--- Refresh the local cache. Throttled by the implementation so
   //--- calling it every tick is harmless.
   bool              Refresh(const datetime from,const datetime to);

   //--- Cached window access.
   int               EventCount(void);
   bool              GetEvent(const int index,SNewsEvent &event);

   datetime          LastRefreshTime(void);
  };

#endif // SRP_CORE_INTERFACES_INEWSPROVIDER_MQH
//+------------------------------------------------------------------+
