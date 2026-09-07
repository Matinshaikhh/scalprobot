//+------------------------------------------------------------------+
//|                                    CNewsBlackoutEvaluator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   News : decides whether NOW is inside a news blackout.                  |
//|                                                                  |
//|   RESPONSIBILITY (one only): turn an event list plus the current time     |
//|   into an SNewsBlackoutState. It does no IO and owns no provider.         |
//|                                                                  |
//|   THE FAIL-SAFE DECISION IS EXPLICIT                                     |
//|   When the news source is unavailable, this class must choose between     |
//|   trading blind and refusing to trade. That choice is configuration       |
//|   (news.fail_safe_block), stated plainly and logged - never an            |
//|   accident of control flow. A news filter that silently degrades to       |
//|   "allow everything" when the calendar fails is worse than having no      |
//|   news filter, because the user believes they are protected.             |
//|                                                                  |
//|   Publishes blackout start/end events so the position manager can close   |
//|   exposure ahead of a release and the dashboard can show a countdown.     |
//+------------------------------------------------------------------+
#ifndef SRP_NEWS_CNEWSBLACKOUTEVALUATOR_MQH
#define SRP_NEWS_CNEWSBLACKOUTEVALUATOR_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/IEventPublisher.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CNewsService;

class CNewsBlackoutEvaluator : public IModule
  {
private:
   CModuleIdentity    m_id;
   CNewsService      *m_news_service;      // borrowed
   IClock            *m_clock;             // borrowed
   IEventPublisher   *m_publisher;         // borrowed

   int                m_minutes_before;
   int                m_minutes_after;
   ENUM_SRP_NEWS_IMPACT m_minimum_impact;
   bool               m_fail_safe_block;   // block when source unavailable
   bool               m_close_positions;

   SNewsBlackoutState m_state;
   bool               m_was_in_blackout;   // for edge-triggered events

   bool              IsEventBlocking(const SNewsEvent &event,
                                     const datetime now) const;
   void              PublishTransition(const bool now_in_blackout);

public:
                     CNewsBlackoutEvaluator(CNewsService *news_service,
                                            IClock *clock,
                                            IEventPublisher *publisher,
                                            ILogger *logger);
                    ~CNewsBlackoutEvaluator(void) { }

   void              SetWindow(const int minutes_before,const int minutes_after);
   void              SetMinimumImpact(const ENUM_SRP_NEWS_IMPACT impact);
   void              SetFailSafeBlock(const bool value);
   void              SetClosePositions(const bool value);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Pipeline stage 6. Recomputes the blackout state.
   bool              Evaluate(void);

   void              GetState(SNewsBlackoutState &out) const { out=m_state; }
   bool              IsInBlackout(void)      const { return(m_state.in_blackout); }
   bool              ShouldClosePositions(void) const
     { return(m_close_positions && m_state.in_blackout); }
  };

#endif // SRP_NEWS_CNEWSBLACKOUTEVALUATOR_MQH
//+------------------------------------------------------------------+
