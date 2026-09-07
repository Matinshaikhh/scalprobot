//+------------------------------------------------------------------+
//|                                               CNewsService.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   News : owns the provider and the refresh schedule.                     |
//|                                                                  |
//|   RESPONSIBILITY (one only): keep a current event set available. It        |
//|   decides WHEN to refresh, never what a blackout means - that is           |
//|   CNewsBlackoutEvaluator's job.                                          |
//|                                                                  |
//|   Selecting the provider by configuration is what makes the calendar/CSV  |
//|   choice a setting rather than a code change. It can also fall back from  |
//|   calendar to CSV automatically inside the tester, where the calendar is  |
//|   unavailable.                                                          |
//|                                                                  |
//|   OWNERSHIP: owns its INewsProvider.                                     |
//+------------------------------------------------------------------+
#ifndef SRP_NEWS_CNEWSSERVICE_MQH
#define SRP_NEWS_CNEWSSERVICE_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/INewsProvider.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CNewsService : public IModule
  {
private:
   CModuleIdentity   m_id;
   INewsProvider    *m_provider;           // OWNED
   IClock           *m_clock;              // borrowed
   int               m_refresh_interval_seconds;
   int               m_lookahead_hours;
   int               m_lookback_hours;
   datetime          m_last_refresh;
   bool              m_refresh_failed;

public:
                     CNewsService(IClock *clock,ILogger *logger);
                    ~CNewsService(void);

   //--- Takes ownership of the provider.
   void              SetProvider(INewsProvider *provider);
   void              SetRefreshInterval(const int seconds);
   void              SetWindow(const int lookback_hours,const int lookahead_hours);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Called on the timer, not on every tick. Internally throttled.
   bool              RefreshIfDue(void);

   //--- Read access for the evaluator and the dashboard.
   bool              IsAvailable(void) const;
   int               EventCount(void) const;
   bool              GetEvent(const int index,SNewsEvent &event) const;
   datetime          LastRefreshTime(void) const { return(m_last_refresh); }
   bool              LastRefreshFailed(void) const { return(m_refresh_failed); }
  };

#endif // SRP_NEWS_CNEWSSERVICE_MQH
//+------------------------------------------------------------------+
