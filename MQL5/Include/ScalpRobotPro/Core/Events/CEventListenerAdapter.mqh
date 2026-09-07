//+------------------------------------------------------------------+
//|                                        CEventListenerAdapter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Events : Adapter pattern, forced by an MQL5 constraint.     |
//|                                                                  |
//|   PROBLEM                                                        |
//|   MQL5 permits a single parent. CStatisticsEngine already          |
//|   inherits IModule, so it CANNOT also inherit IEventListener -     |
//|   yet it must observe the bus.                                     |
//|                                                                  |
//|   SOLUTION                                                        |
//|   This tiny class IS the listener. It wraps an IModule* plus a     |
//|   topic mask and forwards matching events into the module's        |
//|   IModule::HandleEvent(). The kernel creates one adapter per       |
//|   observing module, so no domain class is contorted by the         |
//|   language limitation.                                            |
//|                                                                  |
//|   Single responsibility: bridge bus -> module. No filtering logic  |
//|   beyond the declared topic mask.                                  |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_EVENTS_CEVENTLISTENERADAPTER_MQH
#define SRP_CORE_EVENTS_CEVENTLISTENERADAPTER_MQH

#include "../Interfaces/IEventListener.mqh"
#include "../Interfaces/IModule.mqh"

class CEventListenerAdapter : public IEventListener
  {
private:
   IModule          *m_target;            // borrowed, never owned
   string            m_name;
   ENUM_SRP_EVENT    m_topics[];          // empty == interested in all
   bool              m_accept_all;

public:
                     CEventListenerAdapter(void);
                    ~CEventListenerAdapter(void);

   //--- Wiring. Called by CEngineBootstrapper.
   bool              Attach(IModule *target);
   //--- Restrict to specific topics. Without this the adapter
   //--- receives everything, which is rarely what you want.
   bool              SubscribeTopic(const ENUM_SRP_EVENT event_id);
   void              SubscribeAllTopics(void) { m_accept_all=true; }
   void              ClearTopics(void);

   //--- IEventListener ---------------------------------------------
   virtual string    ListenerName(void) override { return(m_name); }
   virtual bool      IsInterestedIn(const ENUM_SRP_EVENT event_id) override;
   virtual void      OnEvent(const SEventPayload &payload) override;
  };

//+------------------------------------------------------------------+
CEventListenerAdapter::CEventListenerAdapter(void)
  : m_target(NULL),
    m_name("unattached-adapter"),
    m_accept_all(false)
  {
   ArrayResize(m_topics,0);
  }
//+------------------------------------------------------------------+
CEventListenerAdapter::~CEventListenerAdapter(void)
  {
   ArrayFree(m_topics);
  }
//+------------------------------------------------------------------+
bool CEventListenerAdapter::Attach(IModule *target)
  {
   if(target==NULL)
      return(false);
   m_target=target;
   m_name=target.ModuleName()+"-adapter";
   return(true);
  }
//+------------------------------------------------------------------+
bool CEventListenerAdapter::SubscribeTopic(const ENUM_SRP_EVENT event_id)
  {
   const int total=ArraySize(m_topics);
   for(int i=0;i<total;i++)
      if(m_topics[i]==event_id)
         return(true);
   if(ArrayResize(m_topics,total+1)!=total+1)
      return(false);
   m_topics[total]=event_id;
   return(true);
  }
//+------------------------------------------------------------------+
void CEventListenerAdapter::ClearTopics(void)
  {
   ArrayResize(m_topics,0);
   m_accept_all=false;
  }
//+------------------------------------------------------------------+
bool CEventListenerAdapter::IsInterestedIn(const ENUM_SRP_EVENT event_id)
  {
   if(m_target==NULL)
      return(false);
   if(m_accept_all)
      return(true);
   const int total=ArraySize(m_topics);
   for(int i=0;i<total;i++)
      if(m_topics[i]==event_id)
         return(true);
   return(false);
  }
//+------------------------------------------------------------------+
void CEventListenerAdapter::OnEvent(const SEventPayload &payload)
  {
   if(m_target==NULL)
      return;
   m_target.HandleEvent(payload);
  }

#endif // SRP_CORE_EVENTS_CEVENTLISTENERADAPTER_MQH
//+------------------------------------------------------------------+
