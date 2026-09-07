//+------------------------------------------------------------------+
//|                                               IEventListener.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : observer contract for the event bus.         |
//|                                                                  |
//|   Cross-cutting reactions (statistics, journal, dashboard,       |
//|   notifications) subscribe instead of being called directly by   |
//|   the pipeline. The pipeline therefore has zero knowledge of its |
//|   observers, which keeps the trading path free of reporting      |
//|   concerns.                                                      |
//|                                                                  |
//|   MQL5 allows only ONE parent per class, so a module that        |
//|   already inherits a role interface (IStrategy, IFilter, ...)    |
//|   cannot additionally inherit IEventListener. Such modules       |
//|   COMPOSE a CEventListenerAdapter (Core/Events), which is the    |
//|   only listener registered with the bus and which forwards to    |
//|   the module through CModuleBase::HandleEvent(). Composition     |
//|   over inheritance, enforced by the language.                    |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_IEVENTLISTENER_MQH
#define SRP_CORE_INTERFACES_IEVENTLISTENER_MQH

#include "../Types/Structs.mqh"

interface IEventListener
  {
   string            ListenerName(void);

   //--- Declares interest. The bus consults this before dispatching,
   //--- so a listener never receives traffic it does not need.
   bool              IsInterestedIn(const ENUM_SRP_EVENT event_id);

   //--- Handler. Implementations must be non-blocking and must not
   //--- publish synchronously in a way that re-enters the bus.
   void              OnEvent(const SEventPayload &payload);
  };

#endif // SRP_CORE_INTERFACES_IEVENTLISTENER_MQH
//+------------------------------------------------------------------+
