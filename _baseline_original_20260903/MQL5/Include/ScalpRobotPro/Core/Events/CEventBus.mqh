//+------------------------------------------------------------------+
//|                                                    CEventBus.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Events : the single decoupling point of the system.        |
//|                                                                  |
//|   RESPONSIBILITY (one only): deliver an SEventPayload from a      |
//|   producer to every interested listener. It knows nothing about   |
//|   trading, risk or UI.                                            |
//|                                                                  |
//|   Producers hold IEventPublisher; the kernel holds the concrete    |
//|   bus and is the only thing allowed to subscribe/unsubscribe.      |
//|                                                                  |
//|   Re-entrancy: a listener may publish while being dispatched.      |
//|   Such publications are queued and drained after the current      |
//|   dispatch completes, which makes recursion impossible.           |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_EVENTS_CEVENTBUS_MQH
#define SRP_CORE_EVENTS_CEVENTBUS_MQH

#include "../Interfaces/IEventPublisher.mqh"
#include "../Interfaces/IEventListener.mqh"
#include "../Interfaces/ILogger.mqh"

class CEventBus : public IEventPublisher
  {
private:
   IEventListener   *m_listeners[];        // borrowed pointers
   SEventPayload     m_deferred[];         // re-entrancy queue
   ILogger          *m_logger;
   bool              m_dispatching;
   long              m_published_count;
   long              m_dropped_count;

   //--- Deliver to every interested listener. Never called re-entrantly.
   void              Dispatch(const SEventPayload &payload);
   //--- Drain publications made from inside a dispatch.
   void              DrainDeferred(void);

public:
                     CEventBus(void);
                    ~CEventBus(void);

   //--- Wiring (kernel only) ---------------------------------------
   void              SetLogger(ILogger *logger) { m_logger=logger; }
   bool              Subscribe(IEventListener *listener);
   bool              Unsubscribe(IEventListener *listener);
   void              UnsubscribeAll(void);
   int               ListenerCount(void) const { return(ArraySize(m_listeners)); }

   //--- IEventPublisher --------------------------------------------
   virtual void      Publish(const SEventPayload &payload) override;
   virtual void      PublishSimple(const ENUM_SRP_EVENT event_id,
                                   const string source_module,
                                   const string message) override;
   virtual bool      HasListeners(const ENUM_SRP_EVENT event_id) override;

   //--- Diagnostics ------------------------------------------------
   long              PublishedCount(void) const { return(m_published_count); }
   long              DroppedCount(void)   const { return(m_dropped_count); }
  };

//+------------------------------------------------------------------+
CEventBus::CEventBus(void)
  : m_logger(NULL),
    m_dispatching(false),
    m_published_count(0),
    m_dropped_count(0)
  {
   ArrayResize(m_listeners,0);
   ArrayResize(m_deferred,0);
  }
//+------------------------------------------------------------------+
CEventBus::~CEventBus(void)
  {
   //--- Listeners are borrowed, so only the tables are released.
   ArrayFree(m_listeners);
   ArrayFree(m_deferred);
  }
//+------------------------------------------------------------------+
bool CEventBus::Subscribe(IEventListener *listener)
  {
   if(listener==NULL)
      return(false);
   const int total=ArraySize(m_listeners);
   for(int i=0;i<total;i++)
      if(m_listeners[i]==listener)
         return(true);                    // idempotent
   if(total>=SRP_MAX_EVENT_LISTENERS)
     {
      if(m_logger!=NULL)
         m_logger.Error("CEventBus","listener table full, subscription refused");
      return(false);
     }
   if(ArrayResize(m_listeners,total+1)!=total+1)
      return(false);
   m_listeners[total]=listener;
   return(true);
  }
//+------------------------------------------------------------------+
bool CEventBus::Unsubscribe(IEventListener *listener)
  {
   const int total=ArraySize(m_listeners);
   for(int i=0;i<total;i++)
     {
      if(m_listeners[i]!=listener)
         continue;
      for(int j=i;j<total-1;j++)
         m_listeners[j]=m_listeners[j+1];
      ArrayResize(m_listeners,total-1);
      return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
void CEventBus::UnsubscribeAll(void)
  {
   ArrayResize(m_listeners,0);
  }
//+------------------------------------------------------------------+
bool CEventBus::HasListeners(const ENUM_SRP_EVENT event_id)
  {
   const int total=ArraySize(m_listeners);
   for(int i=0;i<total;i++)
      if(m_listeners[i]!=NULL && m_listeners[i].IsInterestedIn(event_id))
         return(true);
   return(false);
  }
//+------------------------------------------------------------------+
void CEventBus::Publish(const SEventPayload &payload)
  {
   m_published_count++;
   //--- Defer instead of recursing.
   if(m_dispatching)
     {
      const int size=ArraySize(m_deferred);
      if(size>=SRP_MAX_EVENT_LISTENERS)
        {
         m_dropped_count++;
         return;
        }
      if(ArrayResize(m_deferred,size+1)!=size+1)
        {
         m_dropped_count++;
         return;
        }
      m_deferred[size]=payload;
      return;
     }
   m_dispatching=true;
   Dispatch(payload);
   DrainDeferred();
   m_dispatching=false;
  }
//+------------------------------------------------------------------+
void CEventBus::PublishSimple(const ENUM_SRP_EVENT event_id,
                              const string source_module,
                              const string message)
  {
   SEventPayload payload;
   payload.event_id       = event_id;
   payload.timestamp      = TimeCurrent();
   payload.timestamp_msc  = GetTickCount64();
   payload.source_module  = source_module;
   payload.message        = message;
   Publish(payload);
  }
//+------------------------------------------------------------------+
void CEventBus::Dispatch(const SEventPayload &payload)
  {
   const int total=ArraySize(m_listeners);
   for(int i=0;i<total;i++)
     {
      IEventListener *listener=m_listeners[i];
      if(listener==NULL)
         continue;
      if(!listener.IsInterestedIn(payload.event_id))
         continue;
      listener.OnEvent(payload);
     }
  }
//+------------------------------------------------------------------+
void CEventBus::DrainDeferred(void)
  {
   //--- Index-based loop: the queue may grow while draining.
   for(int i=0;i<ArraySize(m_deferred);i++)
      Dispatch(m_deferred[i]);
   ArrayResize(m_deferred,0);
  }

#endif // SRP_CORE_EVENTS_CEVENTBUS_MQH
//+------------------------------------------------------------------+
