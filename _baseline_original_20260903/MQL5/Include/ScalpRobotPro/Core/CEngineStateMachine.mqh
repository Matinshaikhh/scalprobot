//+------------------------------------------------------------------+
//|                                          CEngineStateMachine.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : legal-transition enforcement for the engine lifecycle.    |
//|                                                                  |
//|   Extracted from CTradingEngine deliberately. Without this class   |
//|   the engine accumulates scattered boolean flags (m_paused,        |
//|   m_halted, m_ready) whose combinations become unreasonable -      |
//|   the classic path to spaghetti. Here, state is ONE value and     |
//|   every change is validated against an explicit transition table.  |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CENGINESTATEMACHINE_MQH
#define SRP_CORE_CENGINESTATEMACHINE_MQH

#include "Interfaces/IEventPublisher.mqh"
#include "Interfaces/ILogger.mqh"

class CEngineStateMachine
  {
private:
   ENUM_SRP_ENGINE_STATE m_state;
   ENUM_SRP_ENGINE_STATE m_previous_state;
   datetime              m_changed_at;
   string                m_reason;
   ILogger              *m_logger;         // borrowed
   IEventPublisher      *m_publisher;      // borrowed

   //--- The explicit transition table. Any pair absent here is
   //--- rejected and logged, so an illegal state can never occur.
   bool              IsTransitionLegal(const ENUM_SRP_ENGINE_STATE from,
                                       const ENUM_SRP_ENGINE_STATE to) const;

public:
                     CEngineStateMachine(void);
                    ~CEngineStateMachine(void) { }

   void              SetCollaborators(ILogger *logger,IEventPublisher *publisher)
     {
      m_logger=logger;
      m_publisher=publisher;
     }

   //--- Attempt a transition. Returns false when illegal.
   bool              TransitionTo(const ENUM_SRP_ENGINE_STATE target,
                                  const string reason,
                                  const datetime now);

   ENUM_SRP_ENGINE_STATE State(void)         const { return(m_state); }
   ENUM_SRP_ENGINE_STATE PreviousState(void) const { return(m_previous_state); }
   datetime          ChangedAt(void)         const { return(m_changed_at); }
   string            Reason(void)            const { return(m_reason); }

   //--- Intent-revealing queries used across the codebase instead of
   //--- raw state comparisons.
   bool              CanOpenNewPositions(void) const { return(m_state==SRP_STATE_TRADING); }
   bool              CanManagePositions(void)  const
     {
      return(m_state==SRP_STATE_TRADING ||
             m_state==SRP_STATE_MANAGING_ONLY ||
             m_state==SRP_STATE_HALTED);
     }
   bool              IsOperational(void) const
     {
      return(m_state==SRP_STATE_TRADING ||
             m_state==SRP_STATE_MANAGING_ONLY ||
             m_state==SRP_STATE_PAUSED);
     }
   bool              IsTerminal(void) const
     {
      return(m_state==SRP_STATE_HALTED || m_state==SRP_STATE_SHUTDOWN);
     }

   string            StateToString(const ENUM_SRP_ENGINE_STATE state) const;
  };

//+------------------------------------------------------------------+
CEngineStateMachine::CEngineStateMachine(void)
  : m_state(SRP_STATE_CREATED),
    m_previous_state(SRP_STATE_CREATED),
    m_changed_at(0),
    m_reason("constructed"),
    m_logger(NULL),
    m_publisher(NULL)
  {
  }
//+------------------------------------------------------------------+
bool CEngineStateMachine::IsTransitionLegal(const ENUM_SRP_ENGINE_STATE from,
                                            const ENUM_SRP_ENGINE_STATE to) const
  {
   if(from==to)
      return(true);                        // idempotent, harmless
   //--- Shutdown is reachable from anywhere: OnDeinit must always work.
   if(to==SRP_STATE_SHUTDOWN)
      return(true);
   //--- Halt is reachable from any live state: the kill switch is
   //--- unconditional by design.
   if(to==SRP_STATE_HALTED && from!=SRP_STATE_SHUTDOWN)
      return(true);

   switch(from)
     {
      case SRP_STATE_CREATED:
         return(to==SRP_STATE_INITIALIZING);

      case SRP_STATE_INITIALIZING:
         return(to==SRP_STATE_READY);

      case SRP_STATE_READY:
         return(to==SRP_STATE_TRADING || to==SRP_STATE_MANAGING_ONLY);

      case SRP_STATE_TRADING:
         return(to==SRP_STATE_MANAGING_ONLY || to==SRP_STATE_PAUSED);

      case SRP_STATE_MANAGING_ONLY:
         return(to==SRP_STATE_TRADING || to==SRP_STATE_PAUSED);

      case SRP_STATE_PAUSED:
         return(to==SRP_STATE_TRADING || to==SRP_STATE_MANAGING_ONLY);

      case SRP_STATE_HALTED:
         //--- Only a full restart leaves HALTED; nothing else.
         return(false);

      case SRP_STATE_SHUTDOWN:
         return(false);
     }
   return(false);
  }
//+------------------------------------------------------------------+
bool CEngineStateMachine::TransitionTo(const ENUM_SRP_ENGINE_STATE target,
                                       const string reason,
                                       const datetime now)
  {
   if(!IsTransitionLegal(m_state,target))
     {
      if(m_logger!=NULL)
         m_logger.Error("CEngineStateMachine",
                        "illegal transition "+StateToString(m_state)+
                        " -> "+StateToString(target)+" ("+reason+")");
      return(false);
     }
   if(m_state==target)
      return(true);

   m_previous_state = m_state;
   m_state          = target;
   m_changed_at     = now;
   m_reason         = reason;

   if(m_logger!=NULL)
      m_logger.Info("CEngineStateMachine",
                    StateToString(m_previous_state)+" -> "+
                    StateToString(m_state)+" ("+reason+")");

   if(m_publisher!=NULL)
     {
      SEventPayload payload;
      payload.event_id      = SRP_EVENT_ENGINE_STATE_CHANGED;
      payload.timestamp     = now;
      payload.source_module = "CEngineStateMachine";
      payload.message       = reason;
      payload.integer_value = (long)m_state;
      m_publisher.Publish(payload);
     }
   return(true);
  }
//+------------------------------------------------------------------+
string CEngineStateMachine::StateToString(const ENUM_SRP_ENGINE_STATE state) const
  {
   switch(state)
     {
      case SRP_STATE_CREATED:        return("CREATED");
      case SRP_STATE_INITIALIZING:   return("INITIALIZING");
      case SRP_STATE_READY:          return("READY");
      case SRP_STATE_TRADING:        return("TRADING");
      case SRP_STATE_MANAGING_ONLY:  return("MANAGING_ONLY");
      case SRP_STATE_PAUSED:         return("PAUSED");
      case SRP_STATE_HALTED:         return("HALTED");
      case SRP_STATE_SHUTDOWN:       return("SHUTDOWN");
     }
   return("UNKNOWN");
  }

#endif // SRP_CORE_CENGINESTATEMACHINE_MQH
//+------------------------------------------------------------------+
