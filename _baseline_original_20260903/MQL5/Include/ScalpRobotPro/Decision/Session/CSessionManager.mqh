//+------------------------------------------------------------------+
//|                                           CSessionManager.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   RESPONSIBILITY (one only): answer "may we trade at this moment, and  |
//|   what is the time context?" It produces an SSessionState and nothing  |
//|   else.                                                              |
//|                                                                  |
//|   WHY BROKER OFFSET AND DST ARE HANDLED EXPLICITLY                   |
//|   Session windows are facts about GMT, but a broker's server clock is |
//|   not GMT and usually shifts twice a year. An EA that hard-codes      |
//|   "London opens at 08:00 server time" is correct for one broker in    |
//|   one half of the year. This class resolves the offset from the       |
//|   terminal, detects DST, and converts GMT windows into server time    |
//|   every pass - so the same settings behave identically on any broker. |
//|                                                                  |
//|   KILL ZONES are narrower than sessions. A session says the market is |
//|   open; a kill zone says institutional flow is concentrated. For a    |
//|   scalper that distinction is the difference between an edge and      |
//|   noise, so both are reported separately.                            |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_SESSION_CSESSIONMANAGER_MQH
#define SRP_DECISION_SESSION_CSESSIONMANAGER_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CTimeUtils.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "../Types/DecisionStructs.mqh"

//--- Maximum holiday dates the filter can hold.
#define SRP_MAX_HOLIDAYS 64

//+------------------------------------------------------------------+
//| One session's GMT window, in minutes from midnight.                |
//+------------------------------------------------------------------+
struct SSessionWindow
  {
   bool              enabled;
   int               open_gmt_minutes;
   int               close_gmt_minutes;

                     SSessionWindow(void)
     : enabled(true),open_gmt_minutes(0),close_gmt_minutes(0) { }
  };

class CSessionManager
  {
private:
   ILogger          *m_logger;            // borrowed
   string            m_symbol;

   //--- MASTER SWITCH for every session-based gate in this class.
   //---
   //--- THE DEFECT THIS FIXES. `session.enabled` was written by the
   //--- configuration builder, read back into SRuntimeConfig, and checked by
   //--- two validators - but never reached this class, which had no way to
   //--- express "disabled" at all. So InpSessionFilterEnabled=false was
   //--- inert: Evaluate ran its full gate chain regardless, returned
   //--- trading_permitted=false, and the decision engine reported
   //--- SESSION_BLOCKED on every tick. The setting appeared in the startup
   //--- log, which made it look applied.
   //---
   //--- Default TRUE so behaviour is unchanged for every caller that does
   //--- not set it; only an explicit false disables session gating.
   bool              m_enabled;

   //--- Overlap requirement. Also previously stored in config and never
   //--- applied, so a trader asking for London/NY overlap only was silently
   //--- allowed to trade either session alone.
   bool              m_require_overlap;

   //--- Session windows, expressed in GMT.
   SSessionWindow    m_sydney;
   SSessionWindow    m_tokyo;
   SSessionWindow    m_london;
   SSessionWindow    m_newyork;

   //--- Kill zone windows, also GMT.
   SSessionWindow    m_kz_asian;
   SSessionWindow    m_kz_london_open;
   SSessionWindow    m_kz_newyork_open;
   SSessionWindow    m_kz_london_close;
   bool              m_require_kill_zone;

   //--- Weekend and Friday handling.
   bool              m_block_weekend;
   int               m_friday_close_minutes;   // stop N min before midnight
   int               m_monday_open_minutes;    // wait N min after open

   //--- Session edges: the widest spreads of the day sit here.
   int               m_skip_after_open_minutes;
   int               m_skip_before_close_minutes;

   //--- Holidays, stored as day-start timestamps.
   datetime          m_holidays[];
   bool              m_holiday_filter_enabled;
   bool              m_block_year_end;

   //--- Clock resolution.
   int               m_broker_offset_minutes;
   bool              m_offset_resolved;
   bool              m_manual_offset;
   bool              m_dst_enabled;

   SSessionState     m_state;
   datetime          m_cached_minute;
   long              m_evaluations;
   long              m_blocks;

   //--- Converts a GMT minute-of-day into the server's minute-of-day.
   int               GmtToServerMinutes(const int gmt_minutes) const;
   bool              IsInWindow(const SSessionWindow &window,
                                const datetime moment) const;
   void              ResolveOffset(void);
   bool              DetectDst(const datetime moment) const;
   ENUM_SRP_TRADING_SESSION ResolveSession(const datetime moment) const;
   ENUM_SRP_SESSION_OVERLAP ResolveOverlap(const datetime moment) const;
   ENUM_SRP_KILL_ZONE       ResolveKillZone(const datetime moment) const;
   double            ComputeLiquidityScore(const ENUM_SRP_TRADING_SESSION session,
                                           const ENUM_SRP_SESSION_OVERLAP overlap,
                                           const ENUM_SRP_KILL_ZONE zone) const;
   bool              IsHoliday(const datetime moment) const;
   bool              IsYearEnd(const datetime moment) const;
   void              ResolveSessionTiming(const datetime moment,
                                          const ENUM_SRP_TRADING_SESSION session,
                                          int &minutes_into,
                                          int &minutes_remaining) const;
   bool              GetWindowFor(const ENUM_SRP_TRADING_SESSION session,
                                  SSessionWindow &out) const;

public:
                     CSessionManager(const string symbol,ILogger *logger);
                    ~CSessionManager(void);

   //--- Configuration ------------------------------------------------
   //--- Windows default to conventional GMT hours; every one is
   //--- adjustable because brokers and DST differ.
   void              SetSydneyWindow(const int open_gmt,const int close_gmt,
                                     const bool enabled=true);
   void              SetTokyoWindow(const int open_gmt,const int close_gmt,
                                    const bool enabled=true);
   void              SetLondonWindow(const int open_gmt,const int close_gmt,
                                     const bool enabled=true);
   void              SetNewYorkWindow(const int open_gmt,const int close_gmt,
                                      const bool enabled=true);
   //--- MASTER SWITCH. False means no session rule in this class may refuse
   //--- a trade. It deliberately does NOT touch news, spread, regime,
   //--- confidence, accuracy or any risk guard - those are separate gates
   //--- owned by separate classes.
   void              SetEnabled(const bool enabled) { m_enabled=enabled; }
   bool              IsEnabled(void) const { return(m_enabled); }
   //--- Requires London and New York to be simultaneously open.
   void              SetRequireOverlap(const bool require_overlap)
     { m_require_overlap=require_overlap; }
   void              SetKillZones(const bool require_kill_zone);
   void              SetAsianKillZone(const int open_gmt,const int close_gmt);
   void              SetLondonOpenKillZone(const int open_gmt,const int close_gmt);
   void              SetNewYorkOpenKillZone(const int open_gmt,const int close_gmt);
   void              SetLondonCloseKillZone(const int open_gmt,const int close_gmt);
   void              SetWeekendFilter(const bool block_weekend,
                                      const int friday_close_minutes,
                                      const int monday_open_minutes);
   void              SetSessionEdgeSkip(const int after_open,const int before_close);
   void              SetHolidayFilter(const bool enabled,const bool block_year_end);
   //--- Accepts "YYYY.MM.DD;YYYY.MM.DD;..." and reports how many parsed,
   //--- so a malformed list is visible rather than silently inert.
   int               LoadHolidays(const string date_list);
   void              ClearHolidays(void);
   //--- Overrides the auto-detected broker offset, for brokers whose
   //--- reported GMT is unreliable.
   void              SetManualBrokerOffset(const int minutes);
   void              SetDstEnabled(const bool enabled);

   bool              Initialize(void);
   void              Shutdown(void);
   bool              Validate(SValidationResult &result) const;

   //--- Recomputes the state. Cached per minute: sessions do not change
   //--- within a minute, so calling this every tick is nearly free.
   bool              Evaluate(const datetime server_time,const bool force=false);

   //--- Access -------------------------------------------------------
   void              GetState(SSessionState &out) const { out=m_state; }
   bool              IsTradingPermitted(void) const { return(m_state.trading_permitted); }
   ENUM_SRP_TRADING_SESSION ActiveSession(void) const { return(m_state.active_session); }
   ENUM_SRP_KILL_ZONE KillZone(void) const { return(m_state.kill_zone); }
   bool              InKillZone(void) const { return(m_state.in_kill_zone); }
   double            LiquidityScore(void) const { return(m_state.liquidity_score); }
   int               BrokerOffsetMinutes(void) const { return(m_broker_offset_minutes); }
   bool              IsDstActive(void) const { return(m_state.dst_active); }
   int               HolidayCount(void) const { return(ArraySize(m_holidays)); }

   long              EvaluationCount(void) const { return(m_evaluations); }
   long              BlockCount(void) const { return(m_blocks); }
   string            Describe(void) const;
   static string     SessionToString(const ENUM_SRP_TRADING_SESSION session);
   static string     KillZoneToString(const ENUM_SRP_KILL_ZONE zone);
   static string     OverlapToString(const ENUM_SRP_SESSION_OVERLAP overlap);
   static string     BlockToString(const ENUM_SRP_TIME_BLOCK block);
  };

//+------------------------------------------------------------------+
CSessionManager::CSessionManager(const string symbol,ILogger *logger)
  : m_logger(logger),
    m_symbol(symbol),
    //--- Enabled by default: an existing caller that never calls
    //--- SetEnabled must behave exactly as before this change.
    m_enabled(true),
    m_require_overlap(false),
    m_require_kill_zone(false),
    m_block_weekend(true),
    m_friday_close_minutes(60),
    m_monday_open_minutes(0),
    m_skip_after_open_minutes(0),
    m_skip_before_close_minutes(0),
    m_holiday_filter_enabled(false),
    m_block_year_end(false),
    m_broker_offset_minutes(0),
    m_offset_resolved(false),
    m_manual_offset(false),
    m_dst_enabled(true),
    m_cached_minute(0),
    m_evaluations(0),
    m_blocks(0)
  {
   ArrayResize(m_holidays,0);

   //--- CONVENTIONAL GMT SESSION HOURS as defaults.
   m_sydney.open_gmt_minutes   = 21*60;   // 21:00 GMT
   m_sydney.close_gmt_minutes  =  6*60;   // 06:00 GMT (wraps midnight)
   m_tokyo.open_gmt_minutes    =  0;      // 00:00 GMT
   m_tokyo.close_gmt_minutes   =  9*60;   // 09:00 GMT
   m_london.open_gmt_minutes   =  8*60;   // 08:00 GMT
   m_london.close_gmt_minutes  = 16*60+30;// 16:30 GMT
   m_newyork.open_gmt_minutes  = 13*60;   // 13:00 GMT
   m_newyork.close_gmt_minutes = 21*60;   // 21:00 GMT

   //--- KILL ZONES: narrower, higher-probability windows.
   m_kz_asian.open_gmt_minutes        = 23*60;    // 23:00-02:00
   m_kz_asian.close_gmt_minutes       =  2*60;
   m_kz_london_open.open_gmt_minutes  =  7*60;    // 07:00-10:00
   m_kz_london_open.close_gmt_minutes = 10*60;
   m_kz_newyork_open.open_gmt_minutes = 12*60+30; // 12:30-15:00
   m_kz_newyork_open.close_gmt_minutes= 15*60;
   m_kz_london_close.open_gmt_minutes = 15*60;    // 15:00-16:00
   m_kz_london_close.close_gmt_minutes= 16*60;
  }
//+------------------------------------------------------------------+
CSessionManager::~CSessionManager(void)
  {
   ArrayFree(m_holidays);
  }
//+------------------------------------------------------------------+
void CSessionManager::SetSydneyWindow(const int open_gmt,const int close_gmt,
                                      const bool enabled)
  {
   m_sydney.open_gmt_minutes=open_gmt;
   m_sydney.close_gmt_minutes=close_gmt;
   m_sydney.enabled=enabled;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetTokyoWindow(const int open_gmt,const int close_gmt,
                                     const bool enabled)
  {
   m_tokyo.open_gmt_minutes=open_gmt;
   m_tokyo.close_gmt_minutes=close_gmt;
   m_tokyo.enabled=enabled;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetLondonWindow(const int open_gmt,const int close_gmt,
                                      const bool enabled)
  {
   m_london.open_gmt_minutes=open_gmt;
   m_london.close_gmt_minutes=close_gmt;
   m_london.enabled=enabled;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetNewYorkWindow(const int open_gmt,const int close_gmt,
                                       const bool enabled)
  {
   m_newyork.open_gmt_minutes=open_gmt;
   m_newyork.close_gmt_minutes=close_gmt;
   m_newyork.enabled=enabled;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetKillZones(const bool require_kill_zone)
  {
   m_require_kill_zone=require_kill_zone;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetAsianKillZone(const int open_gmt,const int close_gmt)
  {
   m_kz_asian.open_gmt_minutes=open_gmt;
   m_kz_asian.close_gmt_minutes=close_gmt;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetLondonOpenKillZone(const int open_gmt,const int close_gmt)
  {
   m_kz_london_open.open_gmt_minutes=open_gmt;
   m_kz_london_open.close_gmt_minutes=close_gmt;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetNewYorkOpenKillZone(const int open_gmt,const int close_gmt)
  {
   m_kz_newyork_open.open_gmt_minutes=open_gmt;
   m_kz_newyork_open.close_gmt_minutes=close_gmt;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetLondonCloseKillZone(const int open_gmt,const int close_gmt)
  {
   m_kz_london_close.open_gmt_minutes=open_gmt;
   m_kz_london_close.close_gmt_minutes=close_gmt;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetWeekendFilter(const bool block_weekend,
                                       const int friday_close_minutes,
                                       const int monday_open_minutes)
  {
   m_block_weekend=block_weekend;
   if(friday_close_minutes>=0) m_friday_close_minutes=friday_close_minutes;
   if(monday_open_minutes>=0)  m_monday_open_minutes=monday_open_minutes;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetSessionEdgeSkip(const int after_open,const int before_close)
  {
   if(after_open>=0)   m_skip_after_open_minutes=after_open;
   if(before_close>=0) m_skip_before_close_minutes=before_close;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetHolidayFilter(const bool enabled,const bool block_year_end)
  {
   m_holiday_filter_enabled=enabled;
   m_block_year_end=block_year_end;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetManualBrokerOffset(const int minutes)
  {
   m_broker_offset_minutes=minutes;
   m_manual_offset=true;
   m_offset_resolved=true;
  }
//+------------------------------------------------------------------+
void CSessionManager::SetDstEnabled(const bool enabled)
  {
   m_dst_enabled=enabled;
  }
//+------------------------------------------------------------------+
void CSessionManager::ClearHolidays(void)
  {
   ArrayResize(m_holidays,0);
  }
//+------------------------------------------------------------------+
int CSessionManager::LoadHolidays(const string date_list)
  {
   ArrayResize(m_holidays,0);
   if(StringLen(date_list)==0)
      return(0);

   string parts[];
   const int count=StringSplit(date_list,';',parts);
   int loaded=0;
   int malformed=0;

   for(int i=0;i<count;i++)
     {
      string text=parts[i];
      StringTrimLeft(text);
      StringTrimRight(text);
      if(StringLen(text)==0)
         continue;
      const datetime parsed=StringToTime(text);
      if(parsed<=0)
        {
         malformed++;
         continue;
        }
      if(loaded>=SRP_MAX_HOLIDAYS)
         break;
      const int size=ArraySize(m_holidays);
      if(ArrayResize(m_holidays,size+1)!=size+1)
         break;
      //--- Store as day-start so comparison is date-only.
      m_holidays[size]=CTimeUtils::StartOfDay(parsed);
      loaded++;
     }

   //--- Report malformed entries rather than silently ignoring them: a
   //--- typo'd holiday list that loads zero dates looks identical to a
   //--- disabled filter otherwise.
   if(malformed>0 && m_logger!=NULL)
      m_logger.Warn("CSessionManager",
                    StringFormat("%d malformed holiday date(s) ignored",malformed));
   if(loaded>0 && m_logger!=NULL)
      m_logger.Info("CSessionManager",
                    StringFormat("%d holiday date(s) loaded",loaded));
   return(loaded);
  }
//+------------------------------------------------------------------+
void CSessionManager::ResolveOffset(void)
  {
   if(m_manual_offset)
      return;
   //--- TimeGMT is unreliable inside the tester, so the offset is
   //--- measured once and cached rather than recomputed per tick.
   const datetime server=TimeCurrent();
   const datetime gmt=TimeGMT();
   if(server>0 && gmt>0)
     {
      m_broker_offset_minutes=(int)((long)(server-gmt)/60);
      m_offset_resolved=true;
     }
  }
//+------------------------------------------------------------------+
bool CSessionManager::DetectDst(const datetime moment) const
  {
   if(!m_dst_enabled)
      return(false);
   //--- Approximate northern-hemisphere DST: late March to late October.
   //--- Exact transition dates differ by jurisdiction, and the terminal
   //--- exposes no DST flag, so this is a documented approximation
   //--- rather than a false claim of precision. The broker offset itself
   //--- already shifts with DST on most servers, so this flag is
   //--- informational for the caller rather than a correction factor.
   MqlDateTime parts;
   TimeToStruct(moment,parts);
   if(parts.mon>3 && parts.mon<10)
      return(true);
   if(parts.mon==3 && parts.day>=25)
      return(true);
   if(parts.mon==10 && parts.day<25)
      return(true);
   return(false);
  }
//+------------------------------------------------------------------+
int CSessionManager::GmtToServerMinutes(const int gmt_minutes) const
  {
   //--- Wrap into 0..1439 after applying the offset. Without the double
   //--- modulo a negative offset produces a negative minute-of-day,
   //--- which then fails every window comparison.
   int minutes=gmt_minutes+m_broker_offset_minutes;
   minutes=((minutes%1440)+1440)%1440;
   return(minutes);
  }
//+------------------------------------------------------------------+
bool CSessionManager::IsInWindow(const SSessionWindow &window,
                                 const datetime moment) const
  {
   if(!window.enabled)
      return(false);
   const int open=GmtToServerMinutes(window.open_gmt_minutes);
   const int close=GmtToServerMinutes(window.close_gmt_minutes);
   //--- CTimeUtils handles the midnight-wrapping case correctly, which
   //--- matters for Sydney and the Asian kill zone.
   return(CTimeUtils::IsWithinDailyWindow(moment,open,close));
  }
//+------------------------------------------------------------------+
bool CSessionManager::GetWindowFor(const ENUM_SRP_TRADING_SESSION session,
                                   SSessionWindow &out) const
  {
   switch(session)
     {
      case SRP_TS_SYDNEY:  out=m_sydney;  return(true);
      case SRP_TS_TOKYO:   out=m_tokyo;   return(true);
      case SRP_TS_LONDON:  out=m_london;  return(true);
      case SRP_TS_NEWYORK: out=m_newyork; return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
ENUM_SRP_TRADING_SESSION CSessionManager::ResolveSession(const datetime moment) const
  {
   //--- PRIORITY ORDER matters when sessions overlap. London and New York
   //--- dominate liquidity, so they are reported in preference to the
   //--- Asian sessions they overlap.
   if(IsInWindow(m_london,moment) && IsInWindow(m_newyork,moment))
      return(SRP_TS_LONDON);          // overlap reported separately
   if(IsInWindow(m_newyork,moment))
      return(SRP_TS_NEWYORK);
   if(IsInWindow(m_london,moment))
      return(SRP_TS_LONDON);
   if(IsInWindow(m_tokyo,moment))
      return(SRP_TS_TOKYO);
   if(IsInWindow(m_sydney,moment))
      return(SRP_TS_SYDNEY);
   return(SRP_TS_NONE);
  }
//+------------------------------------------------------------------+
ENUM_SRP_SESSION_OVERLAP CSessionManager::ResolveOverlap(const datetime moment) const
  {
   //--- London/New York is the highest-liquidity window of the day and is
   //--- therefore checked first.
   if(IsInWindow(m_london,moment) && IsInWindow(m_newyork,moment))
      return(SRP_OVERLAP_LONDON_NEWYORK);
   if(IsInWindow(m_tokyo,moment) && IsInWindow(m_london,moment))
      return(SRP_OVERLAP_TOKYO_LONDON);
   if(IsInWindow(m_sydney,moment) && IsInWindow(m_tokyo,moment))
      return(SRP_OVERLAP_SYDNEY_TOKYO);
   return(SRP_OVERLAP_NONE);
  }
//+------------------------------------------------------------------+
ENUM_SRP_KILL_ZONE CSessionManager::ResolveKillZone(const datetime moment) const
  {
   //--- Checked in descending order of typical significance.
   if(IsInWindow(m_kz_newyork_open,moment))
      return(SRP_KILLZONE_NEWYORK_OPEN);
   if(IsInWindow(m_kz_london_open,moment))
      return(SRP_KILLZONE_LONDON_OPEN);
   if(IsInWindow(m_kz_london_close,moment))
      return(SRP_KILLZONE_LONDON_CLOSE);
   if(IsInWindow(m_kz_asian,moment))
      return(SRP_KILLZONE_ASIAN);
   return(SRP_KILLZONE_NONE);
  }
//+------------------------------------------------------------------+
double CSessionManager::ComputeLiquidityScore(
                           const ENUM_SRP_TRADING_SESSION session,
                           const ENUM_SRP_SESSION_OVERLAP overlap,
                           const ENUM_SRP_KILL_ZONE zone) const
  {
   //--- Quantified rather than left implicit, because a scalper's edge
   //--- depends directly on it and downstream confirmations need a number
   //--- to weight against.
   double score=0.0;

   switch(session)
     {
      case SRP_TS_LONDON:  score=0.75; break;
      case SRP_TS_NEWYORK: score=0.70; break;
      case SRP_TS_TOKYO:   score=0.45; break;
      case SRP_TS_SYDNEY:  score=0.25; break;
      default:                  score=0.10; break;
     }

   //--- Overlaps add genuine depth.
   if(overlap==SRP_OVERLAP_LONDON_NEWYORK)
      score=1.0;
   else if(overlap==SRP_OVERLAP_TOKYO_LONDON)
      score=MathMax(score,0.70);
   else if(overlap==SRP_OVERLAP_SYDNEY_TOKYO)
      score=MathMax(score,0.40);

   //--- A kill zone concentrates flow further.
   if(zone==SRP_KILLZONE_LONDON_OPEN || zone==SRP_KILLZONE_NEWYORK_OPEN)
      score=MathMin(1.0,score+0.15);
   else if(zone==SRP_KILLZONE_LONDON_CLOSE)
      score=MathMin(1.0,score+0.05);

   return(CMathUtils::Clamp(score,0.0,1.0));
  }
//+------------------------------------------------------------------+
bool CSessionManager::IsHoliday(const datetime moment) const
  {
   if(!m_holiday_filter_enabled)
      return(false);
   const datetime today=CTimeUtils::StartOfDay(moment);
   const int total=ArraySize(m_holidays);
   for(int i=0;i<total;i++)
      if(m_holidays[i]==today)
         return(true);
   return(false);
  }
//+------------------------------------------------------------------+
bool CSessionManager::IsYearEnd(const datetime moment) const
  {
   if(!m_block_year_end)
      return(false);
   //--- The final week of December and the first days of January are
   //--- reliably illiquid; spreads widen and slippage multiplies.
   MqlDateTime parts;
   TimeToStruct(moment,parts);
   if(parts.mon==12 && parts.day>=24)
      return(true);
   if(parts.mon==1 && parts.day<=2)
      return(true);
   return(false);
  }
//+------------------------------------------------------------------+
void CSessionManager::ResolveSessionTiming(const datetime moment,
                                           const ENUM_SRP_TRADING_SESSION session,
                                           int &minutes_into,
                                           int &minutes_remaining) const
  {
   minutes_into=0;
   minutes_remaining=0;
   SSessionWindow window;
   if(!GetWindowFor(session,window))
      return;

   const int now=CTimeUtils::MinutesSinceMidnight(moment);
   const int open=GmtToServerMinutes(window.open_gmt_minutes);
   const int close=GmtToServerMinutes(window.close_gmt_minutes);

   //--- Handle the midnight wrap explicitly: naive subtraction gives
   //--- negative elapsed time for a session that started yesterday.
   if(open<=close)
     {
      minutes_into=now-open;
      minutes_remaining=close-now;
     }
   else
     {
      //--- Window wraps midnight.
      if(now>=open)
        {
         minutes_into=now-open;
         minutes_remaining=(1440-now)+close;
        }
      else
        {
         minutes_into=(1440-open)+now;
         minutes_remaining=close-now;
        }
     }
   if(minutes_into<0)      minutes_into=0;
   if(minutes_remaining<0) minutes_remaining=0;
  }
//+------------------------------------------------------------------+
bool CSessionManager::Initialize(void)
  {
   ResolveOffset();
   if(m_logger!=NULL)
      m_logger.Info("CSessionManager",
                    StringFormat("broker offset %+d minutes from GMT%s",
                                 m_broker_offset_minutes,
                                 (m_manual_offset ? " (manual)" : " (detected)")));
   return(true);
  }
//+------------------------------------------------------------------+
void CSessionManager::Shutdown(void)
  {
   m_state.Reset();
   m_cached_minute=0;
  }
//+------------------------------------------------------------------+
bool CSessionManager::Evaluate(const datetime server_time,const bool force)
  {
   if(server_time<=0)
      return(false);

   //--- Cache per minute. Session membership cannot change within a
   //--- minute, so this keeps the hot path almost free.
   const datetime minute=(datetime)(((long)server_time/60)*60);
   if(!force && m_cached_minute==minute)
      return(true);

   if(!m_offset_resolved)
      ResolveOffset();

   m_state.Reset();
   m_state.server_time=server_time;
   m_state.gmt_time=(datetime)((long)server_time-(long)m_broker_offset_minutes*60);
   m_state.broker_offset_minutes=m_broker_offset_minutes;
   m_state.dst_active=DetectDst(server_time);
   m_state.day_of_week=CTimeUtils::DayOfWeek(server_time);
   m_evaluations++;

   //=== MASTER SWITCH ================================================
   //--- Disabled means NO session rule here may refuse a trade.
   //---
   //--- The context is still resolved and published, because the rest of
   //--- the system legitimately READS it: the confirmation engine scores
   //--- session liquidity, the dashboard displays the active session, and
   //--- kill-zone membership feeds strategy logic. Returning an empty state
   //--- would turn "session filtering off" into "session information
   //--- missing", which is a different and worse behaviour.
   //---
   //--- What is skipped is only the set of REFUSALS: weekend, holiday,
   //--- year-end, Friday close, Monday open, no-active-session, session
   //--- edges, overlap and kill zone. News, spread, regime, confidence,
   //--- accuracy and every risk guard live in other classes and are
   //--- untouched by this flag.
   if(!m_enabled)
     {
      m_state.active_session=ResolveSession(server_time);
      m_state.overlap=ResolveOverlap(server_time);
      m_state.kill_zone=ResolveKillZone(server_time);
      m_state.in_kill_zone=(m_state.kill_zone!=SRP_KILLZONE_NONE);
      m_state.liquidity_score=ComputeLiquidityScore(m_state.active_session,
                                                    m_state.overlap,
                                                    m_state.kill_zone);
      ResolveSessionTiming(server_time,m_state.active_session,
                           m_state.minutes_into_session,
                           m_state.minutes_until_session_end);
      m_state.trading_permitted=true;
      m_state.block_reason=SRP_TIME_BLOCK_NONE;
      m_state.block_detail="session filter disabled";
      m_cached_minute=minute;
      return(true);
     }

   //--- BLOCKING CHECKS, cheapest and most decisive first.

   //--- 1. Weekend.
   if(m_block_weekend && CTimeUtils::IsWeekend(server_time))
     {
      m_state.trading_permitted=false;
      m_state.block_reason=SRP_TIME_BLOCK_WEEKEND;
      m_state.block_detail="weekend";
      m_cached_minute=minute;
      m_blocks++;
      return(true);
     }

   //--- 2. Holiday and year-end illiquidity.
   if(IsHoliday(server_time))
     {
      m_state.trading_permitted=false;
      m_state.block_reason=SRP_TIME_BLOCK_HOLIDAY;
      m_state.block_detail="configured holiday";
      m_cached_minute=minute;
      m_blocks++;
      return(true);
     }
   if(IsYearEnd(server_time))
     {
      m_state.trading_permitted=false;
      m_state.block_reason=SRP_TIME_BLOCK_HOLIDAY;
      m_state.block_detail="year-end illiquidity";
      m_cached_minute=minute;
      m_blocks++;
      return(true);
     }

   //--- 3. Friday close: protects against holding through the weekend gap.
   const int minutes_now=CTimeUtils::MinutesSinceMidnight(server_time);
   if(m_state.day_of_week==5 && m_friday_close_minutes>0 &&
      minutes_now>=1440-m_friday_close_minutes)
     {
      m_state.trading_permitted=false;
      m_state.block_reason=SRP_TIME_BLOCK_FRIDAY_CLOSE;
      m_state.block_detail=StringFormat("within %d minutes of Friday close",
                                        m_friday_close_minutes);
      m_cached_minute=minute;
      m_blocks++;
      return(true);
     }

   //--- 4. Monday open delay: the weekend gap and its first spreads.
   if(m_state.day_of_week==1 && m_monday_open_minutes>0 &&
      minutes_now<m_monday_open_minutes)
     {
      m_state.trading_permitted=false;
      m_state.block_reason=SRP_TIME_BLOCK_SESSION_EDGE;
      m_state.block_detail=StringFormat("first %d minutes of Monday",
                                        m_monday_open_minutes);
      m_cached_minute=minute;
      m_blocks++;
      return(true);
     }

   //--- Resolve context.
   m_state.active_session=ResolveSession(server_time);
   m_state.overlap=ResolveOverlap(server_time);
   m_state.kill_zone=ResolveKillZone(server_time);
   m_state.in_kill_zone=(m_state.kill_zone!=SRP_KILLZONE_NONE);
   m_state.liquidity_score=ComputeLiquidityScore(m_state.active_session,
                                                 m_state.overlap,
                                                 m_state.kill_zone);
   ResolveSessionTiming(server_time,m_state.active_session,
                        m_state.minutes_into_session,
                        m_state.minutes_until_session_end);

   //--- 5. No enabled session active.
   if(m_state.active_session==SRP_TS_NONE)
     {
      m_state.trading_permitted=false;
      m_state.block_reason=SRP_TIME_BLOCK_NO_SESSION;
      m_state.block_detail="no enabled session active";
      m_cached_minute=minute;
      m_blocks++;
      return(true);
     }

   //--- 6. Session edges. The widest spreads of the day sit here, so
   //--- skipping them is usually worth the missed opportunity.
   if(m_skip_after_open_minutes>0 &&
      m_state.minutes_into_session<m_skip_after_open_minutes)
     {
      m_state.trading_permitted=false;
      m_state.block_reason=SRP_TIME_BLOCK_SESSION_EDGE;
      m_state.block_detail=StringFormat("first %d minutes of session",
                                        m_skip_after_open_minutes);
      m_cached_minute=minute;
      m_blocks++;
      return(true);
     }
   if(m_skip_before_close_minutes>0 &&
      m_state.minutes_until_session_end<m_skip_before_close_minutes)
     {
      m_state.trading_permitted=false;
      m_state.block_reason=SRP_TIME_BLOCK_SESSION_EDGE;
      m_state.block_detail=StringFormat("last %d minutes of session",
                                        m_skip_before_close_minutes);
      m_cached_minute=minute;
      m_blocks++;
      return(true);
     }

   //--- 6b. OVERLAP REQUIREMENT, when enabled.
   //---
   //--- Previously stored in configuration and never applied: a trader who
   //--- asked to trade only the London/New York overlap was silently
   //--- permitted to trade either session on its own. Applying it here is
   //--- what makes the setting mean something.
   if(m_require_overlap && m_state.overlap==SRP_OVERLAP_NONE)
     {
      m_state.trading_permitted=false;
      m_state.block_reason=SRP_TIME_BLOCK_NO_SESSION;
      m_state.block_detail="overlap required but no sessions overlap now";
      m_cached_minute=minute;
      m_blocks++;
      return(true);
     }

   //--- 7. Kill zone requirement, when enabled.
   if(m_require_kill_zone && !m_state.in_kill_zone)
     {
      m_state.trading_permitted=false;
      m_state.block_reason=SRP_TIME_BLOCK_OUTSIDE_KILLZONE;
      m_state.block_detail="outside all kill zones";
      m_cached_minute=minute;
      m_blocks++;
      return(true);
     }

   m_state.trading_permitted=true;
   m_cached_minute=minute;
   return(true);
  }
//+------------------------------------------------------------------+
bool CSessionManager::Validate(SValidationResult &result) const
  {
   //--- With the filter OFF, no window configuration can prevent trading, so
   //--- "all sessions disabled" is not an error - it is irrelevant. Raising
   //--- it anyway would refuse startup for a configuration that is
   //--- deliberately session-agnostic.
   if(!m_enabled)
     {
      result.AddWarning("CSessionManager: session filter DISABLED - no "
                        "session, weekend, holiday, edge, overlap or kill "
                        "zone rule will refuse a trade");
      return(true);
     }
   if(!m_sydney.enabled && !m_tokyo.enabled &&
      !m_london.enabled && !m_newyork.enabled)
     {
      result.AddError("CSessionManager: all sessions disabled; no trading possible");
      return(false);
     }
   if(!m_offset_resolved)
      result.AddWarning("CSessionManager: broker GMT offset not yet resolved");
   if(MathAbs(m_broker_offset_minutes)>14*60)
      result.AddWarning("CSessionManager: broker offset exceeds 14 hours; "
                        "verify the manual setting");
   if(m_require_kill_zone)
      result.AddWarning("CSessionManager: kill zones required; trading windows "
                        "will be substantially narrower");
   if(m_holiday_filter_enabled && ArraySize(m_holidays)==0)
      result.AddWarning("CSessionManager: holiday filter enabled but no dates loaded");
   if(m_skip_after_open_minutes+m_skip_before_close_minutes>240)
      result.AddWarning("CSessionManager: session edge skips exceed 4 hours combined");
   return(true);
  }
//+------------------------------------------------------------------+
string CSessionManager::SessionToString(const ENUM_SRP_TRADING_SESSION session)
  {
   switch(session)
     {
      case SRP_TS_SYDNEY:  return("SYDNEY");
      case SRP_TS_TOKYO:   return("TOKYO");
      case SRP_TS_LONDON:  return("LONDON");
      case SRP_TS_NEWYORK: return("NEWYORK");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CSessionManager::KillZoneToString(const ENUM_SRP_KILL_ZONE zone)
  {
   switch(zone)
     {
      case SRP_KILLZONE_ASIAN:         return("ASIAN");
      case SRP_KILLZONE_LONDON_OPEN:   return("LONDON_OPEN");
      case SRP_KILLZONE_NEWYORK_OPEN:  return("NEWYORK_OPEN");
      case SRP_KILLZONE_LONDON_CLOSE:  return("LONDON_CLOSE");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CSessionManager::OverlapToString(const ENUM_SRP_SESSION_OVERLAP overlap)
  {
   switch(overlap)
     {
      case SRP_OVERLAP_SYDNEY_TOKYO:    return("SYDNEY_TOKYO");
      case SRP_OVERLAP_TOKYO_LONDON:    return("TOKYO_LONDON");
      case SRP_OVERLAP_LONDON_NEWYORK:  return("LONDON_NEWYORK");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CSessionManager::BlockToString(const ENUM_SRP_TIME_BLOCK block)
  {
   switch(block)
     {
      case SRP_TIME_BLOCK_WEEKEND:          return("WEEKEND");
      case SRP_TIME_BLOCK_HOLIDAY:          return("HOLIDAY");
      case SRP_TIME_BLOCK_NO_SESSION:       return("NO_SESSION");
      case SRP_TIME_BLOCK_OUTSIDE_KILLZONE: return("OUTSIDE_KILLZONE");
      case SRP_TIME_BLOCK_FRIDAY_CLOSE:     return("FRIDAY_CLOSE");
      case SRP_TIME_BLOCK_SESSION_EDGE:     return("SESSION_EDGE");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CSessionManager::Describe(void) const
  {
   //--- The filter state is reported FIRST. "permitted=no(NO_SESSION)" with
   //--- no indication of whether the filter is even on is what made this
   //--- defect hard to see in a log.
   return(StringFormat("session[%s]: %s%s%s | permitted=%s liquidity=%.2f "
                       "offset=%+dm dst=%s | eval=%I64d blocks=%I64d",
                       (m_enabled ? "FILTER ON" : "FILTER OFF"),
                       SessionToString(m_state.active_session),
                       (m_state.overlap!=SRP_OVERLAP_NONE
                        ? " +"+OverlapToString(m_state.overlap) : ""),
                       (m_state.in_kill_zone
                        ? " KZ:"+KillZoneToString(m_state.kill_zone) : ""),
                       (m_state.trading_permitted ? "yes"
                        : "no("+BlockToString(m_state.block_reason)+")"),
                       m_state.liquidity_score,
                       m_broker_offset_minutes,
                       (m_state.dst_active ? "on" : "off"),
                       m_evaluations,m_blocks));
  }

#endif // SRP_DECISION_SESSION_CSESSIONMANAGER_MQH
//+------------------------------------------------------------------+
