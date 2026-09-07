//+------------------------------------------------------------------+
//|                                     CCalendarNewsProvider.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   News : INewsProvider backed by the terminal economic calendar.          |
//|                                                                  |
//|   Uses CalendarValueHistory / CalendarEventById. Two constraints drive    |
//|   the design:                                                           |
//|     * the calendar is unavailable in the strategy tester, so             |
//|       IsAvailable() reports false there and the caller applies its        |
//|       fail-safe policy instead of silently trading through news;         |
//|     * calendar queries are relatively expensive, so results are cached    |
//|       and refreshed on an interval rather than per tick.                 |
//+------------------------------------------------------------------+
#ifndef SRP_NEWS_CCALENDARNEWSPROVIDER_MQH
#define SRP_NEWS_CCALENDARNEWSPROVIDER_MQH

#include "../Core/Interfaces/INewsProvider.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CCalendarNewsProvider : public INewsProvider
  {
private:
   CModuleIdentity   m_id;
   IClock           *m_clock;              // borrowed
   SNewsEvent        m_events[];
   datetime          m_last_refresh;
   int               m_refresh_interval_seconds;
   bool              m_available;
   //--- Only events for these currencies are retained.
   string            m_currencies[];
   ENUM_SRP_NEWS_IMPACT m_minimum_impact;

   bool              IsCurrencyRelevant(const string currency) const;
   ENUM_SRP_NEWS_IMPACT MapImportance(const ENUM_CALENDAR_EVENT_IMPORTANCE importance) const;

public:
                     CCalendarNewsProvider(IClock *clock,ILogger *logger);
                    ~CCalendarNewsProvider(void);

   //--- Accepts "USD,XAU,EUR". Empty means accept all.
   void              SetCurrencyFilter(const string csv_currencies);
   void              SetMinimumImpact(const ENUM_SRP_NEWS_IMPACT impact);
   void              SetRefreshInterval(const int seconds);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- INewsProvider ------------------------------------------------
   virtual ENUM_SRP_NEWS_SOURCE SourceKind(void) override
     { return(SRP_NEWS_SOURCE_TERMINAL_CALENDAR); }
   virtual string    ProviderName(void) override { return(m_id.Name()); }
   virtual bool      IsAvailable(void) override { return(m_available); }
   virtual bool      Refresh(const datetime from,const datetime to) override;
   virtual int       EventCount(void) override { return(ArraySize(m_events)); }
   virtual bool      GetEvent(const int index,SNewsEvent &event) override;
   virtual datetime  LastRefreshTime(void) override { return(m_last_refresh); }
  };

#endif // SRP_NEWS_CCALENDARNEWSPROVIDER_MQH
//+------------------------------------------------------------------+
