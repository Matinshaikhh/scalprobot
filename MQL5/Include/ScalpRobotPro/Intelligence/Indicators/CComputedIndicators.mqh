//+------------------------------------------------------------------+
//|                                       CComputedIndicators.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   VWAP and Volume. Neither maps onto a terminal indicator handle, so   |
//|   both compute their own series and cache it themselves.              |
//|                                                                  |
//|   They deliberately do NOT inherit CIntelIndicator: that base owns a   |
//|   handle lifecycle and BarsCalculated gating, neither of which exists  |
//|   here. Forcing the inheritance would mean overriding most of the      |
//|   base to do nothing - a Liskov violation. They present the same       |
//|   read API by convention instead, so consumers treat them alike.       |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_INDICATORS_CCOMPUTEDINDICATORS_MQH
#define SRP_INTELLIGENCE_INDICATORS_CCOMPUTEDINDICATORS_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../Types/IntelligenceStructs.mqh"

//+------------------------------------------------------------------+
//| VWAP - volume weighted average price, anchored to a session.        |
//|                                                                  |
//| Anchoring matters: a rolling VWAP is just a moving average, whereas  |
//| a session-anchored VWAP is the reference institutional participants  |
//| are measured against. This resets at the configured session hour.    |
//+------------------------------------------------------------------+
class CVwapIndicator
  {
private:
   string             m_symbol;
   ENUM_TIMEFRAMES    m_timeframe;
   ILogger           *m_logger;           // borrowed
   int                m_session_start_hour;
   int                m_max_bars;         // safety cap on session length
   //--- Cached series, index 0 == current bar.
   double             m_vwap[];
   double             m_upper_band[];
   double             m_lower_band[];
   int                m_filled;
   datetime           m_cached_bar;
   bool               m_valid;
   double             m_band_deviations;
   ENUM_SRP_IND_STATE m_state;
   string             m_state_detail;
   long               m_refresh_count;
   long               m_failure_count;

   //--- Finds the bar index where the current session began.
   int               FindSessionStartIndex(const datetime &times[],
                                           const int count) const;

public:
                     CVwapIndicator(const string symbol,const ENUM_TIMEFRAMES tf,
                                    ILogger *logger,
                                    const int session_start_hour=0,
                                    const int max_bars=1440);
                    ~CVwapIndicator(void);

   void              SetBandDeviations(const double deviations);

   bool              Initialize(void);
   void              Shutdown(void);
   bool              Refresh(const bool force=false);
   bool              Validate(SValidationResult &result);

   //--- Same read API shape as CIntelIndicator, by convention.
   bool              Value(const int shift,double &out) const;
   bool              Upper(const int shift,double &out) const;
   bool              Lower(const int shift,double &out) const;
   bool              Read(const int shift,SIndicatorReading &reading) const;

   //--- Above VWAP is commonly read as intraday bullish control.
   bool              IsPriceAbove(const double price,const int shift=0) const;
   //--- Distance in points, for measuring extension from fair value.
   bool              DistancePoints(const double price,const double point,
                                    const int shift,double &out) const;

   bool               IsReady(void)     const { return(m_state==SRP_IND_STATE_READY); }
   ENUM_SRP_IND_STATE State(void)       const { return(m_state); }
   string             StateDetail(void) const { return(m_state_detail); }
   string             Name(void)        const { return("VWAP"); }
   long               RefreshCount(void)const { return(m_refresh_count); }
  };

//+------------------------------------------------------------------+
CVwapIndicator::CVwapIndicator(const string symbol,const ENUM_TIMEFRAMES tf,
                               ILogger *logger,
                               const int session_start_hour,
                               const int max_bars)
  : m_symbol(symbol),
    m_timeframe(tf),
    m_logger(logger),
    m_session_start_hour(session_start_hour<0 || session_start_hour>23
                         ? 0 : session_start_hour),
    m_max_bars(max_bars<32 ? 32 : max_bars),
    m_filled(0),
    m_cached_bar(0),
    m_valid(false),
    m_band_deviations(1.0),
    m_state(SRP_IND_STATE_UNINITIALIZED),
    m_state_detail("not initialised"),
    m_refresh_count(0),
    m_failure_count(0)
  {
  }
//+------------------------------------------------------------------+
CVwapIndicator::~CVwapIndicator(void)
  {
   ArrayFree(m_vwap);
   ArrayFree(m_upper_band);
   ArrayFree(m_lower_band);
  }
//+------------------------------------------------------------------+
void CVwapIndicator::SetBandDeviations(const double deviations)
  {
   if(deviations>0.0)
      m_band_deviations=deviations;
  }
//+------------------------------------------------------------------+
bool CVwapIndicator::Initialize(void)
  {
   if(ArrayResize(m_vwap,m_max_bars)!=m_max_bars ||
      ArrayResize(m_upper_band,m_max_bars)!=m_max_bars ||
      ArrayResize(m_lower_band,m_max_bars)!=m_max_bars)
     {
      m_state=SRP_IND_STATE_FAILED;
      m_state_detail="array allocation failed";
      return(false);
     }
   ArraySetAsSeries(m_vwap,true);
   ArraySetAsSeries(m_upper_band,true);
   ArraySetAsSeries(m_lower_band,true);
   ArrayInitialize(m_vwap,0.0);
   ArrayInitialize(m_upper_band,0.0);
   ArrayInitialize(m_lower_band,0.0);
   m_state=SRP_IND_STATE_WARMING_UP;
   m_state_detail="awaiting first refresh";
   return(true);
  }
//+------------------------------------------------------------------+
void CVwapIndicator::Shutdown(void)
  {
   m_valid=false;
   m_filled=0;
   m_cached_bar=0;
   m_state=SRP_IND_STATE_UNINITIALIZED;
   m_state_detail="shut down";
  }
//+------------------------------------------------------------------+
int CVwapIndicator::FindSessionStartIndex(const datetime &times[],
                                          const int count) const
  {
   //--- Walk back from the newest bar until the session hour boundary is
   //--- crossed. Returns the oldest index still inside this session.
   MqlDateTime parts;
   int last_index=0;
   for(int i=0;i<count;i++)
     {
      TimeToStruct(times[i],parts);
      last_index=i;
      //--- Bar at or before the session start hour ends the walk.
      if(parts.hour==m_session_start_hour && parts.min==0)
         break;
      //--- Day change also ends the session, for a 0-hour anchor.
      if(i>0)
        {
         MqlDateTime previous;
         TimeToStruct(times[i-1],previous);
         if(previous.day!=parts.day && m_session_start_hour==0)
           {
            last_index=i-1;
            break;
           }
        }
     }
   return(last_index);
  }
//+------------------------------------------------------------------+
bool CVwapIndicator::Refresh(const bool force)
  {
   const datetime current_bar=
      (datetime)SeriesInfoInteger(m_symbol,m_timeframe,SERIES_LASTBAR_DATE);

   //--- Cache hit: recompute only once per bar.
   if(!force && m_valid && m_cached_bar==current_bar)
      return(true);

   const int available=Bars(m_symbol,m_timeframe);
   if(available<2)
     {
      m_state=SRP_IND_STATE_WARMING_UP;
      m_state_detail="insufficient bars";
      return(false);
     }
   const int count=(available<m_max_bars ? available : m_max_bars);

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(m_symbol,m_timeframe,0,count,rates)!=count)
     {
      m_failure_count++;
      m_state=SRP_IND_STATE_STALE;
      m_state_detail="CopyRates failed";
      return(false);
     }

   datetime times[];
   ArraySetAsSeries(times,true);
   if(ArrayResize(times,count)!=count)
      return(false);
   for(int i=0;i<count;i++)
      times[i]=rates[i].time;

   const int session_start=FindSessionStartIndex(times,count);

   //--- Accumulate from the session start forward to the current bar.
   //--- Typical price is the standard VWAP input.
   double cumulative_pv=0.0;
   double cumulative_volume=0.0;
   double cumulative_pv2=0.0;      // for the standard-deviation bands

   for(int i=session_start;i>=0;i--)
     {
      const double typical=(rates[i].high+rates[i].low+rates[i].close)/3.0;
      //--- Tick volume is the only volume most FX/metals feeds provide.
      double volume=(double)rates[i].tick_volume;
      if(volume<=0.0)
         volume=1.0;               // never divide by zero

      cumulative_pv     += typical*volume;
      cumulative_volume += volume;
      cumulative_pv2    += typical*typical*volume;

      if(cumulative_volume<=0.0)
        {
         m_vwap[i]=typical;
         m_upper_band[i]=typical;
         m_lower_band[i]=typical;
         continue;
        }

      const double vwap=cumulative_pv/cumulative_volume;
      m_vwap[i]=vwap;

      //--- Volume-weighted variance, floored at zero against rounding.
      double variance=(cumulative_pv2/cumulative_volume)-(vwap*vwap);
      if(variance<0.0)
         variance=0.0;
      const double deviation=MathSqrt(variance)*m_band_deviations;
      m_upper_band[i]=vwap+deviation;
      m_lower_band[i]=vwap-deviation;
     }

   //--- Only the session portion is meaningful.
   m_filled=session_start+1;
   m_cached_bar=current_bar;
   m_valid=true;
   m_refresh_count++;
   m_state=SRP_IND_STATE_READY;
   m_state_detail="";
   return(true);
  }
//+------------------------------------------------------------------+
bool CVwapIndicator::Validate(SValidationResult &result)
  {
   if(m_state==SRP_IND_STATE_FAILED)
     {
      result.AddError("VWAP: "+m_state_detail);
      return(false);
     }
   if(Bars(m_symbol,m_timeframe)<32)
      result.AddWarning("VWAP: fewer than 32 bars available");
   return(true);
  }
//+------------------------------------------------------------------+
bool CVwapIndicator::Read(const int shift,SIndicatorReading &reading) const
  {
   reading.Reset();
   reading.shift=shift;
   if(!m_valid || m_state!=SRP_IND_STATE_READY)
      return(false);
   if(shift<0 || shift>=m_filled)
      return(false);
   const double value=m_vwap[shift];
   if(!MathIsValidNumber(value) || value<=0.0)
      return(false);
   reading.valid=true;
   reading.value=value;
   return(true);
  }
//+------------------------------------------------------------------+
bool CVwapIndicator::Value(const int shift,double &out) const
  {
   out=0.0;
   SIndicatorReading reading;
   if(!Read(shift,reading))
      return(false);
   out=reading.value;
   return(true);
  }
//+------------------------------------------------------------------+
bool CVwapIndicator::Upper(const int shift,double &out) const
  {
   out=0.0;
   if(!m_valid || m_state!=SRP_IND_STATE_READY || shift<0 || shift>=m_filled)
      return(false);
   out=m_upper_band[shift];
   return(MathIsValidNumber(out) && out>0.0);
  }
//+------------------------------------------------------------------+
bool CVwapIndicator::Lower(const int shift,double &out) const
  {
   out=0.0;
   if(!m_valid || m_state!=SRP_IND_STATE_READY || shift<0 || shift>=m_filled)
      return(false);
   out=m_lower_band[shift];
   return(MathIsValidNumber(out) && out>0.0);
  }
//+------------------------------------------------------------------+
bool CVwapIndicator::IsPriceAbove(const double price,const int shift) const
  {
   double vwap=0.0;
   if(!Value(shift,vwap))
      return(false);
   return(price>vwap);
  }
//+------------------------------------------------------------------+
bool CVwapIndicator::DistancePoints(const double price,const double point,
                                    const int shift,double &out) const
  {
   out=0.0;
   double vwap=0.0;
   if(!Value(shift,vwap) || point<=0.0)
      return(false);
   out=(price-vwap)/point;
   return(true);
  }

//+------------------------------------------------------------------+
//| Volume - tick or real volume with derived relative measures.         |
//|                                                                  |
//| Raw volume is nearly useless on its own; what matters is volume      |
//| RELATIVE to its own recent average. A "high volume" threshold that   |
//| works at the London open is meaningless at 03:00, so everything here |
//| is expressed as a ratio.                                           |
//+------------------------------------------------------------------+
class CVolumeIndicator
  {
private:
   string             m_symbol;
   ENUM_TIMEFRAMES    m_timeframe;
   ILogger           *m_logger;           // borrowed
   ENUM_APPLIED_VOLUME m_volume_kind;
   int                m_cache_depth;
   double             m_volume[];
   int                m_filled;
   datetime           m_cached_bar;
   bool               m_valid;
   ENUM_SRP_IND_STATE m_state;
   string             m_state_detail;
   long               m_refresh_count;

public:
                     CVolumeIndicator(const string symbol,const ENUM_TIMEFRAMES tf,
                                      ILogger *logger,
                                      const ENUM_APPLIED_VOLUME kind=VOLUME_TICK,
                                      const int cache_depth=256);
                    ~CVolumeIndicator(void);

   bool              Initialize(void);
   void              Shutdown(void);
   bool              Refresh(const bool force=false);
   bool              Validate(SValidationResult &result);

   bool              Value(const int shift,double &out) const;
   bool              Read(const int shift,SIndicatorReading &reading) const;
   bool              Average(const int start,const int count,double &out) const;
   //--- Current volume divided by its recent average. 1.0 == normal.
   bool              RelativeVolume(const int lookback,double &out) const;
   bool              IsHighVolume(const int lookback,const double ratio=1.5) const;
   bool              IsLowVolume(const int lookback,const double ratio=0.5) const;
   bool              Highest(const int start,const int count,double &out) const;

   bool               IsReady(void)     const { return(m_state==SRP_IND_STATE_READY); }
   ENUM_SRP_IND_STATE State(void)       const { return(m_state); }
   string             StateDetail(void) const { return(m_state_detail); }
   string             Name(void)        const { return("Volume"); }
   long               RefreshCount(void)const { return(m_refresh_count); }
  };

//+------------------------------------------------------------------+
CVolumeIndicator::CVolumeIndicator(const string symbol,const ENUM_TIMEFRAMES tf,
                                   ILogger *logger,
                                   const ENUM_APPLIED_VOLUME kind,
                                   const int cache_depth)
  : m_symbol(symbol),
    m_timeframe(tf),
    m_logger(logger),
    m_volume_kind(kind),
    m_cache_depth(cache_depth<32 ? 32 : cache_depth),
    m_filled(0),
    m_cached_bar(0),
    m_valid(false),
    m_state(SRP_IND_STATE_UNINITIALIZED),
    m_state_detail("not initialised"),
    m_refresh_count(0)
  {
  }
//+------------------------------------------------------------------+
CVolumeIndicator::~CVolumeIndicator(void)
  {
   ArrayFree(m_volume);
  }
//+------------------------------------------------------------------+
bool CVolumeIndicator::Initialize(void)
  {
   if(ArrayResize(m_volume,m_cache_depth)!=m_cache_depth)
     {
      m_state=SRP_IND_STATE_FAILED;
      m_state_detail="array allocation failed";
      return(false);
     }
   ArraySetAsSeries(m_volume,true);
   ArrayInitialize(m_volume,0.0);
   m_state=SRP_IND_STATE_WARMING_UP;
   m_state_detail="awaiting first refresh";
   return(true);
  }
//+------------------------------------------------------------------+
void CVolumeIndicator::Shutdown(void)
  {
   m_valid=false;
   m_filled=0;
   m_cached_bar=0;
   m_state=SRP_IND_STATE_UNINITIALIZED;
   m_state_detail="shut down";
  }
//+------------------------------------------------------------------+
bool CVolumeIndicator::Refresh(const bool force)
  {
   const datetime current_bar=
      (datetime)SeriesInfoInteger(m_symbol,m_timeframe,SERIES_LASTBAR_DATE);
   if(!force && m_valid && m_cached_bar==current_bar)
      return(true);

   const int available=Bars(m_symbol,m_timeframe);
   if(available<2)
     {
      m_state=SRP_IND_STATE_WARMING_UP;
      m_state_detail="insufficient bars";
      return(false);
     }
   const int count=(available<m_cache_depth ? available : m_cache_depth);

   if(m_volume_kind==VOLUME_REAL)
     {
      long real_volume[];
      ArraySetAsSeries(real_volume,true);
      if(CopyRealVolume(m_symbol,m_timeframe,0,count,real_volume)!=count)
        {
         m_state=SRP_IND_STATE_STALE;
         m_state_detail="CopyRealVolume failed";
         return(false);
        }
      for(int i=0;i<count;i++)
         m_volume[i]=(double)real_volume[i];
     }
   else
     {
      long tick_volume[];
      ArraySetAsSeries(tick_volume,true);
      if(CopyTickVolume(m_symbol,m_timeframe,0,count,tick_volume)!=count)
        {
         m_state=SRP_IND_STATE_STALE;
         m_state_detail="CopyTickVolume failed";
         return(false);
        }
      for(int i=0;i<count;i++)
         m_volume[i]=(double)tick_volume[i];
     }

   m_filled=count;
   m_cached_bar=current_bar;
   m_valid=true;
   m_refresh_count++;
   m_state=SRP_IND_STATE_READY;
   m_state_detail="";
   return(true);
  }
//+------------------------------------------------------------------+
bool CVolumeIndicator::Validate(SValidationResult &result)
  {
   if(m_state==SRP_IND_STATE_FAILED)
     {
      result.AddError("Volume: "+m_state_detail);
      return(false);
     }
   //--- Most FX and metals feeds report no real volume; warn rather than
   //--- fail, since tick volume remains a usable proxy.
   if(m_volume_kind==VOLUME_REAL)
      result.AddWarning("Volume: real volume requested; many FX/metals feeds report zero");
   return(true);
  }
//+------------------------------------------------------------------+
bool CVolumeIndicator::Read(const int shift,SIndicatorReading &reading) const
  {
   reading.Reset();
   reading.shift=shift;
   if(!m_valid || m_state!=SRP_IND_STATE_READY || shift<0 || shift>=m_filled)
      return(false);
   reading.valid=true;
   reading.value=m_volume[shift];
   return(true);
  }
//+------------------------------------------------------------------+
bool CVolumeIndicator::Value(const int shift,double &out) const
  {
   out=0.0;
   SIndicatorReading reading;
   if(!Read(shift,reading))
      return(false);
   out=reading.value;
   return(true);
  }
//+------------------------------------------------------------------+
bool CVolumeIndicator::Average(const int start,const int count,double &out) const
  {
   out=0.0;
   if(!m_valid || start<0 || count<1 || start+count>m_filled)
      return(false);
   double sum=0.0;
   for(int i=start;i<start+count;i++)
      sum+=m_volume[i];
   out=sum/(double)count;
   return(true);
  }
//+------------------------------------------------------------------+
bool CVolumeIndicator::Highest(const int start,const int count,double &out) const
  {
   out=0.0;
   if(!m_valid || start<0 || count<1 || start+count>m_filled)
      return(false);
   out=m_volume[start];
   for(int i=start+1;i<start+count;i++)
      if(m_volume[i]>out)
         out=m_volume[i];
   return(true);
  }
//+------------------------------------------------------------------+
bool CVolumeIndicator::RelativeVolume(const int lookback,double &out) const
  {
   out=0.0;
   double current=0.0;
   if(!Value(0,current))
      return(false);
   double mean=0.0;
   //--- Average EXCLUDES the current bar, otherwise the measure is
   //--- diluted by the very value being tested.
   if(!Average(1,lookback,mean) || mean<=0.0)
      return(false);
   out=current/mean;
   return(true);
  }
//+------------------------------------------------------------------+
bool CVolumeIndicator::IsHighVolume(const int lookback,const double ratio) const
  {
   double relative=0.0;
   if(!RelativeVolume(lookback,relative))
      return(false);
   return(relative>=ratio);
  }
//+------------------------------------------------------------------+
bool CVolumeIndicator::IsLowVolume(const int lookback,const double ratio) const
  {
   double relative=0.0;
   if(!RelativeVolume(lookback,relative))
      return(false);
   return(relative<=ratio);
  }

#endif // SRP_INTELLIGENCE_INDICATORS_CCOMPUTEDINDICATORS_MQH
//+------------------------------------------------------------------+
