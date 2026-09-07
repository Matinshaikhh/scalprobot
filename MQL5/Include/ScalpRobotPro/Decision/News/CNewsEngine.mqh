//+------------------------------------------------------------------+
//|                                               CNewsEngine.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   RESPONSIBILITY (one only): know when a high-impact release is due,   |
//|   pause trading around it, and report the countdown.                  |
//|                                                                  |
//|   NAMED EVENT RECOGNITION                                            |
//|   The terminal calendar reports a generic importance flag, but NFP,    |
//|   CPI, FOMC, GDP, PMI and rate decisions move gold and FX far more     |
//|   than that flag suggests. This engine classifies events by NAME and   |
//|   assigns its own severity, so a "moderate" CPI print is still         |
//|   treated as critical.                                              |
//|                                                                  |
//|   THE FAIL-SAFE DECISION IS EXPLICIT                                 |
//|   When the calendar is unavailable - which is always true in the       |
//|   strategy tester - this engine must choose between trading blind and  |
//|   refusing to trade. That choice is configuration, stated plainly and  |
//|   logged. A news filter that silently degrades to "allow everything"   |
//|   is worse than having none, because the user believes they are        |
//|   protected.                                                        |
//|                                                                  |
//|   A CSV fallback exists precisely so backtests can be honest about    |
//|   news rather than ignoring it.                                      |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_NEWS_CNEWSENGINE_MQH
#define SRP_DECISION_NEWS_CNEWSENGINE_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CStringUtils.mqh"
//--- CTimeUtils is used by CountdownText. It was previously absent, so this
//--- header only compiled where an earlier include in the same translation
//--- unit happened to provide it - which is why including it first in a new
//--- harness produced 30 errors inside a file that had not been touched.
#include "../../Utilities/CTimeUtils.mqh"
#include "../Types/DecisionStructs.mqh"

#define SRP_MAX_NEWS_EVENTS 128

class CNewsEngine
  {
private:
   ILogger          *m_logger;            // borrowed
   string            m_symbol;
   //--- Currencies relevant to the traded symbol, resolved at init.
   string            m_currencies[];

   //--- Cached event window.
   SNewsItem         m_events[];
   datetime          m_last_refresh;
   int               m_refresh_interval_seconds;
   bool              m_source_available;
   bool              m_use_calendar;
   //--- CSV fallback for the tester.
   bool              m_use_csv;
   string            m_csv_file;
   int               m_malformed_lines;

   //--- Pause windows per severity. Higher severity, wider blackout.
   int               m_pause_before_critical;
   int               m_pause_after_critical;
   int               m_pause_before_high;
   int               m_pause_after_high;
   int               m_pause_before_medium;
   int               m_pause_after_medium;
   //--- Policy.
   ENUM_SRP_NEWS_SEVERITY m_minimum_severity;
   bool              m_fail_safe_block;
   bool              m_flatten_on_critical;
   bool              m_enabled;

   SNewsState        m_state;
   long              m_pauses;
   long              m_evaluations;

   //--- Classifies an event by NAME. This is the core value the engine
   //--- adds over a raw importance flag.
   ENUM_SRP_NEWS_KIND ClassifyByTitle(const string title) const;
   ENUM_SRP_NEWS_SEVERITY SeverityFor(const ENUM_SRP_NEWS_KIND kind,
                                      const int calendar_importance) const;
   void              PauseWindowFor(const ENUM_SRP_NEWS_SEVERITY severity,
                                    int &before_minutes,
                                    int &after_minutes) const;
   bool              IsCurrencyRelevant(const string currency) const;
   void              ResolveSymbolCurrencies(void);
   bool              LoadFromCalendar(const datetime from,const datetime to);
   bool              LoadFromCsv(void);
   bool              ParseCsvLine(const string line,SNewsItem &item) const;
   bool              PushEvent(const SNewsItem &item);
   void              SortByTime(void);

public:
                     CNewsEngine(const string symbol,ILogger *logger);
                    ~CNewsEngine(void);

   //--- Configuration ------------------------------------------------
   void              SetEnabled(const bool enabled) { m_enabled=enabled; }
   void              SetSource(const bool use_calendar,const bool use_csv,
                               const string csv_file);
   void              SetMinimumSeverity(const ENUM_SRP_NEWS_SEVERITY severity);
   void              SetCriticalWindow(const int before,const int after);
   void              SetHighWindow(const int before,const int after);
   void              SetMediumWindow(const int before,const int after);
   void              SetFailSafeBlock(const bool block);
   void              SetFlattenOnCritical(const bool flatten);
   void              SetRefreshInterval(const int seconds);
   //--- Overrides the auto-resolved currency list.
   void              SetCurrencyFilter(const string csv_currencies);

   bool              Initialize(void);
   void              Shutdown(void);
   bool              Validate(SValidationResult &result) const;

   //--- Refreshes the event cache. Throttled internally, so calling it
   //--- on the timer is cheap.
   bool              Refresh(const datetime now,const bool force=false);
   //--- Recomputes the blackout state and countdown.
   bool              Evaluate(const datetime now);

   //--- Access -------------------------------------------------------
   void              GetState(SNewsState &out) const { out=m_state; }
   bool              IsTradingPermitted(void) const { return(m_state.trading_permitted); }
   bool              IsFlattenRecommended(void) const { return(m_state.flatten_recommended); }
   ENUM_SRP_NEWS_PHASE Phase(void) const { return(m_state.phase); }
   int               SecondsUntilNext(void) const { return(m_state.seconds_until_next); }
   int               SecondsUntilResume(void) const { return(m_state.seconds_until_resume); }
   bool              SourceAvailable(void) const { return(m_source_available); }
   int               EventCount(void) const { return(ArraySize(m_events)); }
   bool              GetEvent(const int index,SNewsItem &out) const;
   //--- Human-readable countdown, for logs and journals.
   string            CountdownText(void) const;

   long              PauseCount(void) const { return(m_pauses); }
   int               MalformedLineCount(void) const { return(m_malformed_lines); }
   string            Describe(void) const;
   static string     KindToString(const ENUM_SRP_NEWS_KIND kind);
   static string     SeverityToString(const ENUM_SRP_NEWS_SEVERITY severity);
   static string     PhaseToString(const ENUM_SRP_NEWS_PHASE phase);
  };

//+------------------------------------------------------------------+
CNewsEngine::CNewsEngine(const string symbol,ILogger *logger)
  : m_logger(logger),
    m_symbol(symbol),
    m_last_refresh(0),
    m_refresh_interval_seconds(900),
    m_source_available(false),
    m_use_calendar(true),
    m_use_csv(false),
    m_csv_file("srp_news.csv"),
    m_malformed_lines(0),
    m_pause_before_critical(60),
    m_pause_after_critical(60),
    m_pause_before_high(30),
    m_pause_after_high(30),
    m_pause_before_medium(15),
    m_pause_after_medium(15),
    m_minimum_severity(SRP_NEWS_SEV_HIGH),
    m_fail_safe_block(false),
    m_flatten_on_critical(false),
    m_enabled(true),
    m_pauses(0),
    m_evaluations(0)
  {
   ArrayResize(m_events,0);
   ArrayResize(m_currencies,0);
  }
//+------------------------------------------------------------------+
CNewsEngine::~CNewsEngine(void)
  {
   ArrayFree(m_events);
   ArrayFree(m_currencies);
  }
//+------------------------------------------------------------------+
void CNewsEngine::SetSource(const bool use_calendar,const bool use_csv,
                            const string csv_file)
  {
   m_use_calendar=use_calendar;
   m_use_csv=use_csv;
   if(StringLen(csv_file)>0)
      m_csv_file=csv_file;
  }
//+------------------------------------------------------------------+
void CNewsEngine::SetMinimumSeverity(const ENUM_SRP_NEWS_SEVERITY severity)
  {
   m_minimum_severity=severity;
  }
//+------------------------------------------------------------------+
void CNewsEngine::SetCriticalWindow(const int before,const int after)
  {
   if(before>=0) m_pause_before_critical=before;
   if(after>=0)  m_pause_after_critical=after;
  }
//+------------------------------------------------------------------+
void CNewsEngine::SetHighWindow(const int before,const int after)
  {
   if(before>=0) m_pause_before_high=before;
   if(after>=0)  m_pause_after_high=after;
  }
//+------------------------------------------------------------------+
void CNewsEngine::SetMediumWindow(const int before,const int after)
  {
   if(before>=0) m_pause_before_medium=before;
   if(after>=0)  m_pause_after_medium=after;
  }
//+------------------------------------------------------------------+
void CNewsEngine::SetFailSafeBlock(const bool block)
  {
   m_fail_safe_block=block;
  }
//+------------------------------------------------------------------+
void CNewsEngine::SetFlattenOnCritical(const bool flatten)
  {
   m_flatten_on_critical=flatten;
  }
//+------------------------------------------------------------------+
void CNewsEngine::SetRefreshInterval(const int seconds)
  {
   if(seconds>=60)
      m_refresh_interval_seconds=seconds;
  }
//+------------------------------------------------------------------+
void CNewsEngine::SetCurrencyFilter(const string csv_currencies)
  {
   ArrayResize(m_currencies,0);
   if(StringLen(csv_currencies)==0)
      return;
   string parts[];
   const int count=StringSplit(csv_currencies,',',parts);
   for(int i=0;i<count;i++)
     {
      string code=parts[i];
      StringTrimLeft(code);
      StringTrimRight(code);
      StringToUpper(code);
      if(StringLen(code)==0)
         continue;
      const int size=ArraySize(m_currencies);
      if(ArrayResize(m_currencies,size+1)!=size+1)
         break;
      m_currencies[size]=code;
     }
  }
//+------------------------------------------------------------------+
void CNewsEngine::ResolveSymbolCurrencies(void)
  {
   if(ArraySize(m_currencies)>0)
      return;                             // explicitly configured

   //--- Derive from the symbol's base and profit currencies. For XAUUSD
   //--- that yields XAU and USD, so US releases are correctly flagged.
   const string base=SymbolInfoString(m_symbol,SYMBOL_CURRENCY_BASE);
   const string profit=SymbolInfoString(m_symbol,SYMBOL_CURRENCY_PROFIT);
   const string margin=SymbolInfoString(m_symbol,SYMBOL_CURRENCY_MARGIN);

   if(StringLen(base)>0)
     {
      ArrayResize(m_currencies,1);
      m_currencies[0]=base;
     }
   if(StringLen(profit)>0 && profit!=base)
     {
      const int size=ArraySize(m_currencies);
      if(ArrayResize(m_currencies,size+1)==size+1)
         m_currencies[size]=profit;
     }
   if(StringLen(margin)>0 && margin!=base && margin!=profit)
     {
      const int size=ArraySize(m_currencies);
      if(ArrayResize(m_currencies,size+1)==size+1)
         m_currencies[size]=margin;
     }

   //--- Metals are priced in USD and driven by US data even when the
   //--- symbol's base currency is XAU, so USD is always relevant.
   bool has_usd=false;
   const int total=ArraySize(m_currencies);
   for(int i=0;i<total;i++)
      if(m_currencies[i]=="USD")
         has_usd=true;
   if(!has_usd)
     {
      const int size=ArraySize(m_currencies);
      if(ArrayResize(m_currencies,size+1)==size+1)
         m_currencies[size]="USD";
     }
  }
//+------------------------------------------------------------------+
bool CNewsEngine::IsCurrencyRelevant(const string currency) const
  {
   const int total=ArraySize(m_currencies);
   if(total==0)
      return(true);                       // no filter: accept all
   string upper=currency;
   StringToUpper(upper);
   for(int i=0;i<total;i++)
      if(m_currencies[i]==upper)
         return(true);
   return(false);
  }
//+------------------------------------------------------------------+
ENUM_SRP_NEWS_KIND CNewsEngine::ClassifyByTitle(const string title) const
  {
   //--- Name matching against the releases that actually move price.
   //--- Case-insensitive and substring-based, because calendar wording
   //--- varies between providers and over time.
   string text=title;
   StringToUpper(text);

   //--- FOMC / Fed: the single most disruptive scheduled event.
   if(StringFind(text,"FOMC")>=0 ||
      StringFind(text,"FEDERAL FUNDS")>=0 ||
      StringFind(text,"FED INTEREST RATE")>=0 ||
      StringFind(text,"FED CHAIR")>=0)
      return(SRP_NEWS_FOMC);

   //--- Non-farm payrolls.
   if(StringFind(text,"NONFARM")>=0 ||
      StringFind(text,"NON-FARM")>=0 ||
      StringFind(text,"NFP")>=0 ||
      StringFind(text,"PAYROLL")>=0)
      return(SRP_NEWS_NFP);

   //--- CPI and inflation.
   if(StringFind(text,"CPI")>=0 ||
      StringFind(text,"CONSUMER PRICE")>=0 ||
      StringFind(text,"INFLATION RATE")>=0)
      return(SRP_NEWS_CPI);

   //--- Other central bank rate decisions.
   if(StringFind(text,"INTEREST RATE DECISION")>=0 ||
      StringFind(text,"RATE DECISION")>=0 ||
      StringFind(text,"BANK RATE")>=0 ||
      StringFind(text,"CASH RATE")>=0)
      return(SRP_NEWS_INTEREST_RATE);

   //--- GDP.
   if(StringFind(text,"GDP")>=0 ||
      StringFind(text,"GROSS DOMESTIC")>=0)
      return(SRP_NEWS_GDP);

   //--- PMI.
   if(StringFind(text,"PMI")>=0 ||
      StringFind(text,"PURCHASING MANAGER")>=0)
      return(SRP_NEWS_PMI);

   //--- Unemployment.
   if(StringFind(text,"UNEMPLOYMENT")>=0 ||
      StringFind(text,"JOBLESS")>=0)
      return(SRP_NEWS_UNEMPLOYMENT);

   //--- Retail sales.
   if(StringFind(text,"RETAIL SALES")>=0)
      return(SRP_NEWS_RETAIL_SALES);

   return(SRP_NEWS_OTHER);
  }
//+------------------------------------------------------------------+
ENUM_SRP_NEWS_SEVERITY CNewsEngine::SeverityFor(const ENUM_SRP_NEWS_KIND kind,
                                                const int calendar_importance) const
  {
   //--- NAMED EVENTS OVERRIDE the calendar flag. FOMC and NFP are
   //--- reliably account-threatening for a scalper regardless of how a
   //--- provider has tagged them.
   switch(kind)
     {
      case SRP_NEWS_FOMC:
      case SRP_NEWS_NFP:
         return(SRP_NEWS_SEV_CRITICAL);
      case SRP_NEWS_CPI:
      case SRP_NEWS_INTEREST_RATE:
         return(SRP_NEWS_SEV_CRITICAL);
      case SRP_NEWS_GDP:
      case SRP_NEWS_UNEMPLOYMENT:
         return(SRP_NEWS_SEV_HIGH);
      case SRP_NEWS_PMI:
      case SRP_NEWS_RETAIL_SALES:
         return(SRP_NEWS_SEV_MEDIUM);
     }

   //--- Unrecognised event: fall back to the calendar's own importance.
   //--- CALENDAR_IMPORTANCE_HIGH == 3 in MQL5.
   if(calendar_importance>=3)
      return(SRP_NEWS_SEV_HIGH);
   if(calendar_importance==2)
      return(SRP_NEWS_SEV_MEDIUM);
   if(calendar_importance==1)
      return(SRP_NEWS_SEV_LOW);
   return(SRP_NEWS_SEV_NONE);
  }
//+------------------------------------------------------------------+
void CNewsEngine::PauseWindowFor(const ENUM_SRP_NEWS_SEVERITY severity,
                                 int &before_minutes,
                                 int &after_minutes) const
  {
   switch(severity)
     {
      case SRP_NEWS_SEV_CRITICAL:
         before_minutes=m_pause_before_critical;
         after_minutes=m_pause_after_critical;
         return;
      case SRP_NEWS_SEV_HIGH:
         before_minutes=m_pause_before_high;
         after_minutes=m_pause_after_high;
         return;
      case SRP_NEWS_SEV_MEDIUM:
         before_minutes=m_pause_before_medium;
         after_minutes=m_pause_after_medium;
         return;
     }
   before_minutes=0;
   after_minutes=0;
  }
//+------------------------------------------------------------------+
bool CNewsEngine::PushEvent(const SNewsItem &item)
  {
   const int size=ArraySize(m_events);
   if(size>=SRP_MAX_NEWS_EVENTS)
      return(false);
   if(ArrayResize(m_events,size+1)!=size+1)
      return(false);
   m_events[size]=item;
   return(true);
  }
//+------------------------------------------------------------------+
void CNewsEngine::SortByTime(void)
  {
   //--- Simple insertion sort: the event count is small (tens), and this
   //--- keeps the class free of a sorting dependency.
   const int total=ArraySize(m_events);
   for(int i=1;i<total;i++)
     {
      SNewsItem key=m_events[i];
      int j=i-1;
      while(j>=0 && m_events[j].event_time>key.event_time)
        {
         m_events[j+1]=m_events[j];
         j--;
        }
      m_events[j+1]=key;
     }
  }
//+------------------------------------------------------------------+
bool CNewsEngine::LoadFromCalendar(const datetime from,const datetime to)
  {
   //--- The terminal calendar is unavailable in the strategy tester. That
   //--- is a fact to report, not an error to hide.
   MqlCalendarValue values[];
   const int count=CalendarValueHistory(values,from,to,NULL,NULL);
   //--- THE SOURCE IS THE CALENDAR, NOT THE EVENT LIST.
   //---
   //--- Only a failed QUERY means the source is unavailable. A successful
   //--- query returning nothing relevant means the source works and there
   //--- is nothing to avoid, which is the opposite conclusion.
   //---
   //--- MEASURED: this function used to end with `return(ArraySize(m_events)>0)`,
   //--- so a working calendar with no high-impact USD events in the window
   //--- reported "unavailable", the live fail-safe blocked on it, and 100%
   //--- of evaluations were declined as NEWS_BLOCKED. A quiet calendar day
   //--- was indistinguishable from a broken feed - and the quiet day is
   //--- precisely when trading should be allowed.
   //--- CalendarValueHistory returns -1 on query failure and 0 for a
   //--- successful query with no matching events. A quiet calendar is the
   //--- safest time to trade, not a reason to trip the live fail-safe.
   if(count<0)
      return(false);

   for(int i=0;i<count;i++)
     {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id,event))
         continue;
      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id,country))
         continue;

      if(!IsCurrencyRelevant(country.currency))
         continue;

      SNewsItem item;
      item.valid          = true;
      item.title          = event.name;
      item.currency       = country.currency;
      item.event_time     = values[i].time;
      item.kind           = ClassifyByTitle(event.name);
      item.severity       = SeverityFor(item.kind,(int)event.importance);
      item.affects_symbol = true;
      PauseWindowFor(item.severity,item.pause_before_minutes,
                     item.pause_after_minutes);

      //--- Discard anything below the configured threshold now, so the
      //--- evaluation loop stays small and fast.
      if(item.severity<m_minimum_severity)
         continue;
      if(!PushEvent(item))
         break;
     }
   //--- TRUE because the calendar answered. An empty relevant-event list is
   //--- a valid answer meaning "nothing to avoid right now", and reporting
   //--- it as unavailability inverted the filter's purpose.
   return(true);
  }
//+------------------------------------------------------------------+
bool CNewsEngine::ParseCsvLine(const string line,SNewsItem &item) const
  {
   item.Reset();
   //--- Expected: YYYY.MM.DD HH:MM;CURRENCY;IMPORTANCE;TITLE
   string parts[];
   if(StringSplit(line,';',parts)<4)
      return(false);

   const datetime when=StringToTime(parts[0]);
   if(when<=0)
      return(false);

   string currency=parts[1];
   StringTrimLeft(currency);
   StringTrimRight(currency);
   StringToUpper(currency);

   const int importance=(int)StringToInteger(parts[2]);
   const string title=parts[3];

   item.valid          = true;
   item.event_time     = when;
   item.currency       = currency;
   item.title          = title;
   item.kind           = ClassifyByTitle(title);
   item.severity       = SeverityFor(item.kind,importance);
   item.affects_symbol = true;
   PauseWindowFor(item.severity,item.pause_before_minutes,
                  item.pause_after_minutes);
   return(true);
  }
//+------------------------------------------------------------------+
bool CNewsEngine::LoadFromCsv(void)
  {
   if(!FileIsExist(m_csv_file))
      return(false);

   const int handle=FileOpen(m_csv_file,FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle==INVALID_HANDLE)
      return(false);

   m_malformed_lines=0;
   while(!FileIsEnding(handle))
     {
      const string line=FileReadString(handle);
      if(StringLen(line)==0)
         continue;
      //--- Allow comment lines so a user can annotate the file.
      if(StringGetCharacter(line,0)=='#')
         continue;

      SNewsItem item;
      if(!ParseCsvLine(line,item))
        {
         m_malformed_lines++;
         continue;
        }
      if(!IsCurrencyRelevant(item.currency))
         continue;
      if(item.severity<m_minimum_severity)
         continue;
      if(!PushEvent(item))
         break;
     }
   FileClose(handle);

   //--- Malformed lines are counted and reported rather than skipped
   //--- silently: a typo'd file that loads nothing looks exactly like a
   //--- clear calendar otherwise.
   if(m_malformed_lines>0 && m_logger!=NULL)
      m_logger.Warn("CNewsEngine",
                    StringFormat("%d malformed CSV line(s) ignored",
                                 m_malformed_lines));
   //--- The FILE opened and parsed, so the source is available. Same
   //--- correction as the calendar path: a file listing no events relevant
   //--- to this symbol is a valid statement that nothing is pending, not
   //--- evidence that news data is missing.
   return(true);
  }
//+------------------------------------------------------------------+
bool CNewsEngine::Initialize(void)
  {
   ResolveSymbolCurrencies();
   if(m_logger!=NULL)
     {
      string list="";
      const int total=ArraySize(m_currencies);
      for(int i=0;i<total;i++)
         list+=(i>0 ? "," : "")+m_currencies[i];
      m_logger.Info("CNewsEngine","monitoring currencies: "+list);
     }
   return(true);
  }
//+------------------------------------------------------------------+
void CNewsEngine::Shutdown(void)
  {
   ArrayResize(m_events,0);
   m_state.Reset();
   m_last_refresh=0;
  }
//+------------------------------------------------------------------+
bool CNewsEngine::Refresh(const datetime now,const bool force)
  {
   if(!m_enabled)
     {
      m_source_available=true;            // disabled is not "unavailable"
      return(true);
     }

   //--- Throttle: calendar queries are relatively expensive and the
   //--- schedule changes rarely.
   if(!force && m_last_refresh>0 &&
      (long)(now-m_last_refresh)<(long)m_refresh_interval_seconds)
      return(true);

   ArrayResize(m_events,0);

   //--- Window: a day back for cooldowns still in effect, two days
   //--- forward so approaching events are known well in advance.
   const datetime from=(datetime)((long)now-86400);
   const datetime to=(datetime)((long)now+172800);

   bool loaded=false;
   if(m_use_calendar)
      loaded=LoadFromCalendar(from,to);
   //--- CSV is the tester fallback, and also a manual override when a
   //--- broker's calendar feed is unreliable.
   if(!loaded && m_use_csv)
      loaded=LoadFromCsv();

   m_source_available=loaded;
   m_last_refresh=now;

   if(!loaded && m_logger!=NULL)
      m_logger.Warn("CNewsEngine",
                    StringFormat("no news source available; fail-safe=%s",
                                 (m_fail_safe_block ? "BLOCK" : "ALLOW")));
   else
      SortByTime();
   return(loaded);
  }
//+------------------------------------------------------------------+
bool CNewsEngine::Evaluate(const datetime now)
  {
   m_state.Reset();
   m_state.source_available=m_source_available;
   m_evaluations++;

   if(!m_enabled)
     {
      m_state.trading_permitted=true;
      m_state.detail="news filter disabled";
      return(true);
     }

   //--- THE FAIL-SAFE DECISION, made explicit and logged.
   if(!m_source_available)
     {
      m_state.trading_permitted=!m_fail_safe_block;
      m_state.detail=(m_fail_safe_block
                      ? "news source unavailable: blocking (fail-safe)"
                      : "news source unavailable: allowing (configured)");
      if(m_fail_safe_block)
         m_pauses++;
      return(true);
     }

   const int total=ArraySize(m_events);
   bool in_blackout=false;
   int worst_resume_seconds=0;
   int nearest_future_seconds=0;
   bool has_future=false;

   for(int i=0;i<total;i++)
     {
      if(!m_events[i].valid)
         continue;

      const long delta=(long)m_events[i].event_time-(long)now;
      m_events[i].minutes_until=(int)(delta/60);

      const long before_seconds=(long)m_events[i].pause_before_minutes*60;
      const long after_seconds=(long)m_events[i].pause_after_minutes*60;

      //--- Inside the blackout window: from 'before' ahead of the release
      //--- through 'after' following it.
      if(delta<=before_seconds && delta>=-after_seconds)
        {
         in_blackout=true;
         const int resume=(int)(after_seconds+delta);
         if(resume>worst_resume_seconds)
           {
            worst_resume_seconds=resume;
            m_state.active_event=m_events[i];
           }
         //--- Critical events may warrant flattening rather than merely
         //--- pausing: a position through FOMC is a coin flip with a
         //--- widened spread.
         if(m_flatten_on_critical &&
            m_events[i].severity>=SRP_NEWS_SEV_CRITICAL)
            m_state.flatten_recommended=true;
        }

      //--- Track the nearest upcoming event for the countdown.
      if(delta>0 && (!has_future || delta<(long)nearest_future_seconds))
        {
         nearest_future_seconds=(int)delta;
         m_state.next_event=m_events[i];
         has_future=true;
        }
     }

   m_state.seconds_until_next=(has_future ? nearest_future_seconds : 0);
   m_state.seconds_until_resume=worst_resume_seconds;

   if(in_blackout)
     {
      m_state.trading_permitted=false;
      m_pauses++;
      //--- Distinguish the three blackout phases so a caller can react
      //--- differently: approaching is a reason to stop opening,
      //--- cooldown is a reason to wait for spreads to normalise.
      const long delta=(long)m_state.active_event.event_time-(long)now;
      if(delta>60)
         m_state.phase=SRP_NEWS_PHASE_APPROACHING;
      else if(delta>=-60)
         m_state.phase=SRP_NEWS_PHASE_ACTIVE;
      else
         m_state.phase=SRP_NEWS_PHASE_COOLDOWN;
      m_state.detail=StringFormat("%s [%s] %s, resume in %s",
                                  m_state.active_event.title,
                                  SeverityToString(m_state.active_event.severity),
                                  PhaseToString(m_state.phase),
                                  CTimeUtils::FormatDuration(worst_resume_seconds));
      return(true);
     }

   m_state.trading_permitted=true;
   m_state.phase=SRP_NEWS_PHASE_CLEAR;
   m_state.detail=(has_future
                   ? StringFormat("clear; next: %s in %s",
                                  m_state.next_event.title,
                                  CTimeUtils::FormatDuration(nearest_future_seconds))
                   : "clear; no upcoming events in range");
   return(true);
  }
//+------------------------------------------------------------------+
bool CNewsEngine::GetEvent(const int index,SNewsItem &out) const
  {
   out.Reset();
   if(index<0 || index>=ArraySize(m_events))
      return(false);
   out=m_events[index];
   return(true);
  }
//+------------------------------------------------------------------+
string CNewsEngine::CountdownText(void) const
  {
   if(!m_state.trading_permitted && m_state.seconds_until_resume>0)
      return("PAUSED - resume in "+
             CTimeUtils::FormatDuration(m_state.seconds_until_resume));
   if(m_state.seconds_until_next>0)
      return("next event in "+
             CTimeUtils::FormatDuration(m_state.seconds_until_next)+
             " ("+m_state.next_event.title+")");
   return("no scheduled events");
  }
//+------------------------------------------------------------------+
bool CNewsEngine::Validate(SValidationResult &result) const
  {
   if(!m_enabled)
     {
      result.AddWarning("CNewsEngine: news filter disabled; high-impact "
                        "releases will not pause trading");
      return(true);
     }
   if(!m_use_calendar && !m_use_csv)
     {
      result.AddError("CNewsEngine: no source enabled (calendar or CSV)");
      return(false);
     }
   if(!m_source_available && !m_fail_safe_block)
      result.AddWarning("CNewsEngine: source unavailable and fail-safe is "
                        "ALLOW; trading will proceed through news");
   if(m_pause_before_critical<15)
      result.AddWarning("CNewsEngine: critical pre-event window under 15 "
                        "minutes is unusually tight for FOMC/NFP");
   if(ArraySize(m_currencies)==0)
      result.AddWarning("CNewsEngine: no currency filter; all events will match");
   return(true);
  }
//+------------------------------------------------------------------+
string CNewsEngine::KindToString(const ENUM_SRP_NEWS_KIND kind)
  {
   switch(kind)
     {
      case SRP_NEWS_NFP:           return("NFP");
      case SRP_NEWS_CPI:           return("CPI");
      case SRP_NEWS_FOMC:          return("FOMC");
      case SRP_NEWS_GDP:           return("GDP");
      case SRP_NEWS_PMI:           return("PMI");
      case SRP_NEWS_INTEREST_RATE: return("RATE_DECISION");
      case SRP_NEWS_UNEMPLOYMENT:  return("UNEMPLOYMENT");
      case SRP_NEWS_RETAIL_SALES:  return("RETAIL_SALES");
     }
   return("OTHER");
  }
//+------------------------------------------------------------------+
string CNewsEngine::SeverityToString(const ENUM_SRP_NEWS_SEVERITY severity)
  {
   switch(severity)
     {
      case SRP_NEWS_SEV_LOW:      return("LOW");
      case SRP_NEWS_SEV_MEDIUM:   return("MEDIUM");
      case SRP_NEWS_SEV_HIGH:     return("HIGH");
      case SRP_NEWS_SEV_CRITICAL: return("CRITICAL");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CNewsEngine::PhaseToString(const ENUM_SRP_NEWS_PHASE phase)
  {
   switch(phase)
     {
      case SRP_NEWS_PHASE_APPROACHING: return("APPROACHING");
      case SRP_NEWS_PHASE_ACTIVE:      return("ACTIVE");
      case SRP_NEWS_PHASE_COOLDOWN:    return("COOLDOWN");
     }
   return("CLEAR");
  }
//+------------------------------------------------------------------+
string CNewsEngine::Describe(void) const
  {
   return(StringFormat("news: %s | events=%d source=%s | %s | pauses=%I64d",
                       (m_state.trading_permitted ? "clear" : "PAUSED"),
                       ArraySize(m_events),
                       (m_source_available ? "ok" : "unavailable"),
                       CountdownText(),
                       m_pauses));
  }

#endif // SRP_DECISION_NEWS_CNEWSENGINE_MQH
//+------------------------------------------------------------------+
