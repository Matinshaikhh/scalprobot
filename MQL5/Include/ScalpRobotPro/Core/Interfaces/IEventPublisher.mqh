//+------------------------------------------------------------------+
//|                                              IEventPublisher.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : publish side of the event bus.               |
//|                                                                  |
//|   Split from the subscribe side on purpose: producers receive    |
//|   only IEventPublisher and physically cannot tamper with the     |
//|   subscription table. Interface Segregation Principle.           |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_IEVENTPUBLISHER_MQH
#define SRP_CORE_INTERFACES_IEVENTPUBLISHER_MQH

#include "../Types/Structs.mqh"

interface IEventPublisher
  {
   //--- Full payload dispatch.
   void              Publish(const SEventPayload &payload);

   //--- Shorthand for the common "id + text" case; the implementation
   //--- fills timestamps and source itself.
   void              PublishSimple(const ENUM_SRP_EVENT event_id,
                                   const string source_module,
                                   const string message);

   //--- True when at least one listener is registered for the topic,
   //--- letting hot-path callers skip payload construction.
   bool              HasListeners(const ENUM_SRP_EVENT event_id);
  };

#endif // SRP_CORE_INTERFACES_IEVENTPUBLISHER_MQH
//+------------------------------------------------------------------+
