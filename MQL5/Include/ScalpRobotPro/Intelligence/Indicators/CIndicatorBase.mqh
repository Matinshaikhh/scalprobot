//+------------------------------------------------------------------+
//|                            Intelligence/CIndicatorBase.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   Abstract base for every Phase 2 indicator. Delivers the four        |
//|   required capabilities ONCE so no concrete indicator reimplements    |
//|   them:                                                             |
//|                                                                  |
//|     CACHING         one CIndicatorBuffer per output buffer,          |
//|                     refreshed once per bar                          |
//|     VALIDATION      handle checks, BarsCalculated warm-up gating,    |
//|                     EMPTY_VALUE and NaN rejection                   |
//|     ERROR HANDLING  explicit state machine, failure counters,        |
//|                     one automatic recreate attempt                  |
//|     REUSABLE API    uniform Value/Series/Slope/Cross accessors       |
//|                                                                  |
//|   Subclasses implement exactly ONE method: OnCreateHandle().          |
//|   Template Method, so a new indicator is a handle call and nothing    |
//|   else.                                                            |
//|                                                                  |
//|   NAMING: deliberately NOT the Phase 1 CIndicatorBase                |
//|   (Core/Base/CIndicatorBase.mqh). That one is declaration-only and    |
//|   tied to IIndicator. This is a self-contained implementation, so it  |
//|   lives in its own namespace-by-folder and Phase 1 is untouched.      |
//|   Class name is CIntelIndicator to avoid any collision.              |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_INDICATORS_CINDICATORBASE_MQH
#define SRP_INTELLIGENCE_INDICATORS_CINDICATORBASE_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../Types/IntelligenceStructs.mqh"
#include "CIndicatorBuffer.mqh"

//--- Hard ceiling on cached buffers per indicator. Ichimoku uses 5.
#define SRP_MAX_IND_BUFFERS 8

class CIntelIndicator
  {
protected:
   string                 m_name;
   ENUM_SRP_INDICATOR_KIND m_kind;
   string                 m_symbol;
   ENUM_TIMEFRAMES        m_timeframe;
   ILogger               *m_logger;        // borrowed
   int                    m_handle;
   int                    m_buffer_count;
   int                    m_cache_depth;
   int                    m_minimum_bars;
   ENUM_SRP_IND_STATE     m_state;
   string                 m_state_detail;
   //--- One cache per output buffer.
   CIndicatorBuffer       m_buffers[SRP_MAX_IND_BUFFERS];
   //--- Diagnostics.
   long                   m_refresh_count;
   long                   m_failure_count;
   int                    m_consecutive_failures;
   bool                   m_recreate_attempted;

   //--- THE single extension point. Return a valid terminal handle.
   virtual int       OnCreateHandle(void)=0;
   //--- Optional post-refresh hook for derived values.
   virtual bool      OnAfterRefresh(void) { return(true); }

   void              Log(const ENUM_SRP_LOG_LEVEL level,const string message) const
     {
      if(m_logger!=NULL)
         m_logger.Log(level,m_name,message);
     }
   void              SetState(const ENUM_SRP_IND_STATE state,const string detail)
     {
      m_state=state;
      m_state_detail=detail;
     }
   //--- Current bar time; the cache key.
   datetime          CurrentBar(void) const
     {
      return((datetime)SeriesInfoInteger(m_symbol,m_timeframe,SERIES_LASTBAR_DATE));
     }
   void              ReleaseHandle(void)
     {
      if(m_handle!=INVALID_HANDLE)
        {
         IndicatorRelease(m_handle);
         m_handle=INVALID_HANDLE;
        }
     }

public:
                     CIntelIndicator(const string name,
                                     const ENUM_SRP_INDICATOR_KIND kind,
                                     const string symbol,
                                     const ENUM_TIMEFRAMES timeframe,
                                     ILogger *logger,
                                     const int buffer_count=1,
                                     const int minimum_bars=50,
                                     const int cache_depth=256);
   virtual          ~CIntelIndicator(void);

   //--- Lifecycle -----------------------------------------------------
   virtual bool      Initialize(void);
   virtual void      Shutdown(void);
   //--- Refresh every cached buffer. Cheap when already current.
   virtual bool      Refresh(const bool force=false);

   //--- Validation ----------------------------------------------------
   bool              Validate(SValidationResult &result);
   bool              IsReady(void) const { return(m_state==SRP_IND_STATE_READY); }
   //--- Warming up is NOT an error: a fresh handle needs several ticks
   //--- before BarsCalculated reaches the minimum.
   bool              IsWarmingUp(void) const { return(m_state==SRP_IND_STATE_WARMING_UP); }
   bool              HasFailed(void) const { return(m_state==SRP_IND_STATE_FAILED); }

   //--- Reusable API --------------------------------------------------
   bool              Read(const int buffer,const int shift,
                          SIndicatorReading &reading) const;
   bool              Value(const int shift,double &out) const;
   bool              ValueAt(const int buffer,const int shift,double &out) const;
   bool              Series(const int buffer,const int start,
                            const int count,double &out[]) const;
   bool              Slope(const int buffer,const int lookback,double &out) const;
   bool              Highest(const int buffer,const int start,
                             const int count,double &out) const;
   bool              Lowest(const int buffer,const int start,
                            const int count,double &out) const;
   bool              Average(const int buffer,const int start,
                             const int count,double &out) const;
   bool              CrossedAbove(const int buffer,const double level) const;
   bool              CrossedBelow(const int buffer,const double level) const;
   //--- Cross between two buffers of the same indicator (MACD, Stoch).
   bool              BufferCrossedAbove(const int fast_buffer,
                                        const int slow_buffer) const;
   bool              BufferCrossedBelow(const int fast_buffer,
                                        const int slow_buffer) const;

   //--- Identity and diagnostics ---------------------------------------
   string                  Name(void)        const { return(m_name); }
   ENUM_SRP_INDICATOR_KIND Kind(void)        const { return(m_kind); }
   int                     Handle(void)      const { return(m_handle); }
   int                     BufferCount(void) const { return(m_buffer_count); }
   ENUM_SRP_IND_STATE      State(void)       const { return(m_state); }
   string                  StateDetail(void) const { return(m_state_detail); }
   long                    RefreshCount(void)const { return(m_refresh_count); }
   long                    FailureCount(void)const { return(m_failure_count); }
   double                  CacheHitRatio(void) const;
   string                  Describe(void) const;
   static string           StateToString(const ENUM_SRP_IND_STATE state);
  };

//+------------------------------------------------------------------+
CIntelIndicator::CIntelIndicator(const string name,
                                 const ENUM_SRP_INDICATOR_KIND kind,
                                 const string symbol,
                                 const ENUM_TIMEFRAMES timeframe,
                                 ILogger *logger,
                                 const int buffer_count,
                                 const int minimum_bars,
                                 const int cache_depth)
  : m_name(name),
    m_kind(kind),
    m_symbol(symbol),
    m_timeframe(timeframe),
    m_logger(logger),
    m_handle(INVALID_HANDLE),
    m_buffer_count(buffer_count<1 ? 1 :
                  (buffer_count>SRP_MAX_IND_BUFFERS ? SRP_MAX_IND_BUFFERS : buffer_count)),
    m_cache_depth(cache_depth<8 ? 8 : cache_depth),
    m_minimum_bars(minimum_bars<1 ? 1 : minimum_bars),
    m_state(SRP_IND_STATE_UNINITIALIZED),
    m_state_detail("not initialised"),
    m_refresh_count(0),
    m_failure_count(0),
    m_consecutive_failures(0),
    m_recreate_attempted(false)
  {
  }
//+------------------------------------------------------------------+
CIntelIndicator::~CIntelIndicator(void)
  {
   //--- RAII: the handle is released even if Shutdown was never called.
   ReleaseHandle();
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::Initialize(void)
  {
   if(m_handle!=INVALID_HANDLE)
      return(true);

   //--- Configure caches before creating the handle, so a successful
   //--- handle is never left without somewhere to store its data.
   for(int i=0;i<m_buffer_count;i++)
     {
      if(!m_buffers[i].Configure(i,m_cache_depth))
        {
         SetState(SRP_IND_STATE_FAILED,"buffer allocation failed");
         Log(SRP_LOG_ERROR,"cache allocation failed for buffer "+IntegerToString(i));
         return(false);
        }
     }

   m_handle=OnCreateHandle();
   if(m_handle==INVALID_HANDLE)
     {
      SetState(SRP_IND_STATE_FAILED,
               "handle creation failed, error "+IntegerToString(GetLastError()));
      Log(SRP_LOG_ERROR,m_state_detail);
      return(false);
     }

   //--- A brand-new handle has computed nothing yet, so the honest
   //--- initial state is WARMING_UP rather than READY.
   SetState(SRP_IND_STATE_WARMING_UP,"awaiting first calculation");
   return(true);
  }
//+------------------------------------------------------------------+
void CIntelIndicator::Shutdown(void)
  {
   ReleaseHandle();
   for(int i=0;i<m_buffer_count;i++)
      m_buffers[i].Invalidate();
   SetState(SRP_IND_STATE_UNINITIALIZED,"shut down");
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::Refresh(const bool force)
  {
   if(m_handle==INVALID_HANDLE)
     {
      //--- ONE automatic recovery attempt. A handle can be lost when the
      //--- terminal reloads history. Retrying forever would spin, so the
      //--- attempt is made once and then the indicator stays FAILED.
      if(!m_recreate_attempted)
        {
         m_recreate_attempted=true;
         Log(SRP_LOG_WARN,"handle lost; attempting one recreate");
         if(Initialize())
            Log(SRP_LOG_INFO,"handle recreated");
        }
      if(m_handle==INVALID_HANDLE)
        {
         SetState(SRP_IND_STATE_FAILED,"handle unavailable");
         return(false);
        }
     }

   //--- WARM-UP GATE. BarsCalculated is the authoritative readiness
   //--- signal; it returns -1 or a small number for several ticks after
   //--- creation. Reading buffers before this yields zeros that look
   //--- like real values.
   const int calculated=BarsCalculated(m_handle);
   if(calculated<0)
     {
      m_failure_count++;
      m_consecutive_failures++;
      SetState(SRP_IND_STATE_STALE,"BarsCalculated returned "+IntegerToString(calculated));
      return(false);
     }
   if(calculated<m_minimum_bars)
     {
      SetState(SRP_IND_STATE_WARMING_UP,
               StringFormat("%d of %d bars calculated",calculated,m_minimum_bars));
      return(false);
     }

   const datetime bar=CurrentBar();
   bool all_ok=true;
   for(int i=0;i<m_buffer_count;i++)
      if(!m_buffers[i].Refresh(m_handle,bar,force))
         all_ok=false;

   if(!all_ok)
     {
      m_failure_count++;
      m_consecutive_failures++;
      SetState(SRP_IND_STATE_STALE,"buffer copy failed");
      //--- Escalate only after repeated failure, so one bad tick does not
      //--- mark a healthy indicator as broken.
      if(m_consecutive_failures>=5)
         Log(SRP_LOG_WARN,StringFormat("%d consecutive refresh failures",
                                       m_consecutive_failures));
      return(false);
     }

   if(!OnAfterRefresh())
     {
      SetState(SRP_IND_STATE_STALE,"post-refresh hook failed");
      return(false);
     }

   m_refresh_count++;
   m_consecutive_failures=0;
   m_recreate_attempted=false;
   SetState(SRP_IND_STATE_READY,"");
   return(true);
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::Validate(SValidationResult &result)
  {
   if(m_handle==INVALID_HANDLE)
     {
      result.AddError(m_name+": indicator handle is invalid");
      return(false);
     }
   const int available=Bars(m_symbol,m_timeframe);
   if(available<m_minimum_bars)
      result.AddWarning(StringFormat("%s: only %d bars available, needs %d",
                                     m_name,available,m_minimum_bars));
   if(m_state==SRP_IND_STATE_FAILED)
     {
      result.AddError(m_name+": "+m_state_detail);
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::Read(const int buffer,const int shift,
                           SIndicatorReading &reading) const
  {
   reading.Reset();
   if(buffer<0 || buffer>=m_buffer_count)
      return(false);
   //--- Reads are refused unless the indicator is READY. This is the
   //--- single gate that prevents warm-up zeros reaching a calculation.
   if(m_state!=SRP_IND_STATE_READY)
      return(false);
   return(m_buffers[buffer].Read(shift,reading));
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::Value(const int shift,double &out) const
  {
   return(ValueAt(0,shift,out));
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::ValueAt(const int buffer,const int shift,double &out) const
  {
   out=0.0;
   SIndicatorReading reading;
   if(!Read(buffer,shift,reading))
      return(false);
   out=reading.value;
   return(true);
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::Series(const int buffer,const int start,
                             const int count,double &out[]) const
  {
   ArrayFree(out);
   if(buffer<0 || buffer>=m_buffer_count || m_state!=SRP_IND_STATE_READY)
      return(false);
   return(m_buffers[buffer].Series(start,count,out));
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::Slope(const int buffer,const int lookback,double &out) const
  {
   out=0.0;
   if(buffer<0 || buffer>=m_buffer_count || m_state!=SRP_IND_STATE_READY)
      return(false);
   return(m_buffers[buffer].Slope(lookback,out));
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::Highest(const int buffer,const int start,
                              const int count,double &out) const
  {
   out=0.0;
   if(buffer<0 || buffer>=m_buffer_count || m_state!=SRP_IND_STATE_READY)
      return(false);
   return(m_buffers[buffer].Highest(start,count,out));
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::Lowest(const int buffer,const int start,
                             const int count,double &out) const
  {
   out=0.0;
   if(buffer<0 || buffer>=m_buffer_count || m_state!=SRP_IND_STATE_READY)
      return(false);
   return(m_buffers[buffer].Lowest(start,count,out));
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::Average(const int buffer,const int start,
                              const int count,double &out) const
  {
   out=0.0;
   if(buffer<0 || buffer>=m_buffer_count || m_state!=SRP_IND_STATE_READY)
      return(false);
   return(m_buffers[buffer].Average(start,count,out));
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::CrossedAbove(const int buffer,const double level) const
  {
   if(buffer<0 || buffer>=m_buffer_count || m_state!=SRP_IND_STATE_READY)
      return(false);
   return(m_buffers[buffer].CrossedAbove(level));
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::CrossedBelow(const int buffer,const double level) const
  {
   if(buffer<0 || buffer>=m_buffer_count || m_state!=SRP_IND_STATE_READY)
      return(false);
   return(m_buffers[buffer].CrossedBelow(level));
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::BufferCrossedAbove(const int fast_buffer,
                                         const int slow_buffer) const
  {
   double fast_now=0.0,fast_prev=0.0,slow_now=0.0,slow_prev=0.0;
   if(!ValueAt(fast_buffer,0,fast_now) || !ValueAt(fast_buffer,1,fast_prev))
      return(false);
   if(!ValueAt(slow_buffer,0,slow_now) || !ValueAt(slow_buffer,1,slow_prev))
      return(false);
   return(fast_prev<=slow_prev && fast_now>slow_now);
  }
//+------------------------------------------------------------------+
bool CIntelIndicator::BufferCrossedBelow(const int fast_buffer,
                                         const int slow_buffer) const
  {
   double fast_now=0.0,fast_prev=0.0,slow_now=0.0,slow_prev=0.0;
   if(!ValueAt(fast_buffer,0,fast_now) || !ValueAt(fast_buffer,1,fast_prev))
      return(false);
   if(!ValueAt(slow_buffer,0,slow_now) || !ValueAt(slow_buffer,1,slow_prev))
      return(false);
   return(fast_prev>=slow_prev && fast_now<slow_now);
  }
//+------------------------------------------------------------------+
double CIntelIndicator::CacheHitRatio(void) const
  {
   if(m_buffer_count<1)
      return(0.0);
   return(m_buffers[0].HitRatio());
  }
//+------------------------------------------------------------------+
string CIntelIndicator::StateToString(const ENUM_SRP_IND_STATE state)
  {
   switch(state)
     {
      case SRP_IND_STATE_UNINITIALIZED: return("UNINITIALIZED");
      case SRP_IND_STATE_WARMING_UP:    return("WARMING_UP");
      case SRP_IND_STATE_READY:         return("READY");
      case SRP_IND_STATE_STALE:         return("STALE");
      case SRP_IND_STATE_FAILED:        return("FAILED");
     }
   return("UNKNOWN");
  }
//+------------------------------------------------------------------+
string CIntelIndicator::Describe(void) const
  {
   return(StringFormat("%s [%s] buffers=%d minBars=%d refresh=%I64d fail=%I64d cache=%.0f%% %s",
                       m_name,StateToString(m_state),m_buffer_count,m_minimum_bars,
                       m_refresh_count,m_failure_count,CacheHitRatio(),
                       m_state_detail));
  }

#endif // SRP_INTELLIGENCE_INDICATORS_CINDICATORBASE_MQH
//+------------------------------------------------------------------+
