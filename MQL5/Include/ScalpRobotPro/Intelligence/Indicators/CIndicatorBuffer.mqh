//+------------------------------------------------------------------+
//|                                          CIndicatorBuffer.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): cache one indicator buffer and serve     |
//|   reads from memory.                                                |
//|                                                                  |
//|   WHY CACHING IS NOT AN OPTIMISATION HERE                           |
//|   CopyBuffer is a cross-module call into the terminal. On M1 gold,    |
//|   with a dozen indicators each read by several consumers per tick,    |
//|   uncached reads dominate runtime. Worse, two consumers calling       |
//|   CopyBuffer at different moments in the same tick can observe        |
//|   DIFFERENT values, so filters and structure logic silently disagree. |
//|                                                                  |
//|   This class copies once per bar and serves every subsequent read     |
//|   from memory: fast, and identical for all consumers.                |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_INDICATORS_CINDICATORBUFFER_MQH
#define SRP_INTELLIGENCE_INDICATORS_CINDICATORBUFFER_MQH

#include "../Types/IntelligenceStructs.mqh"

class CIndicatorBuffer
  {
private:
   double            m_data[];            // index 0 == current bar
   int               m_capacity;
   int               m_filled;
   int               m_buffer_index;      // which indicator buffer
   datetime          m_cached_bar;        // bar the cache belongs to
   bool              m_valid;
   long              m_copy_count;        // diagnostics: actual CopyBuffer calls
   long              m_hit_count;         // reads served from memory

public:
                     CIndicatorBuffer(void);
                    ~CIndicatorBuffer(void);

   bool              Configure(const int buffer_index,const int capacity);
   void              Invalidate(void);

   //--- Pulls data only when the current bar differs from the cached
   //--- one, so calling it every tick is nearly free.
   bool              Refresh(const int handle,const datetime current_bar,
                             const bool force=false);

   //--- Reads. 'shift' 0 == current bar. Never returns EMPTY_VALUE as a
   //--- valid number.
   bool              Read(const int shift,SIndicatorReading &reading) const;
   bool              Value(const int shift,double &out) const;
   bool              Series(const int start,const int count,double &out[]) const;

   //--- Aggregates over the cached window, used by derived measures.
   bool              Highest(const int start,const int count,double &out) const;
   bool              Lowest(const int start,const int count,double &out) const;
   bool              Average(const int start,const int count,double &out) const;
   //--- Slope in value-per-bar across the lookback.
   bool              Slope(const int lookback,double &out) const;
   //--- Detects a crossing between this buffer and a level.
   bool              CrossedAbove(const double level) const;
   bool              CrossedBelow(const double level) const;

   bool              IsValid(void)     const { return(m_valid); }
   int               Filled(void)      const { return(m_filled); }
   datetime          CachedBar(void)   const { return(m_cached_bar); }
   long              CopyCount(void)   const { return(m_copy_count); }
   long              HitCount(void)    const { return(m_hit_count); }
   double            HitRatio(void)    const;
  };

//+------------------------------------------------------------------+
CIndicatorBuffer::CIndicatorBuffer(void)
  : m_capacity(0),
    m_filled(0),
    m_buffer_index(0),
    m_cached_bar(0),
    m_valid(false),
    m_copy_count(0),
    m_hit_count(0)
  {
   ArrayResize(m_data,0);
  }
//+------------------------------------------------------------------+
CIndicatorBuffer::~CIndicatorBuffer(void)
  {
   ArrayFree(m_data);
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::Configure(const int buffer_index,const int capacity)
  {
   if(buffer_index<0 || capacity<1)
      return(false);
   if(ArrayResize(m_data,capacity)!=capacity)
      return(false);
   ArrayInitialize(m_data,0.0);
   //--- Series indexing: element 0 is the newest bar, which matches how
   //--- every caller thinks about 'shift'.
   ArraySetAsSeries(m_data,true);
   m_buffer_index=buffer_index;
   m_capacity=capacity;
   m_filled=0;
   m_cached_bar=0;
   m_valid=false;
   return(true);
  }
//+------------------------------------------------------------------+
void CIndicatorBuffer::Invalidate(void)
  {
   m_valid=false;
   m_filled=0;
   m_cached_bar=0;
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::Refresh(const int handle,const datetime current_bar,
                               const bool force)
  {
   if(handle==INVALID_HANDLE || m_capacity<1)
     {
      m_valid=false;
      return(false);
     }

   //--- CACHE HIT: same bar, already populated. This is the common path.
   if(!force && m_valid && m_cached_bar==current_bar)
     {
      m_hit_count++;
      return(true);
     }

   const int copied=CopyBuffer(handle,m_buffer_index,0,m_capacity,m_data);
   m_copy_count++;

   if(copied<=0)
     {
      //--- Keep any previous data but mark invalid, so a transient
      //--- failure degrades to "stale" rather than to garbage.
      m_valid=false;
      return(false);
     }

   m_filled=copied;
   m_cached_bar=current_bar;
   m_valid=true;
   return(true);
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::Read(const int shift,SIndicatorReading &reading) const
  {
   reading.Reset();
   reading.shift=shift;
   if(!m_valid || shift<0 || shift>=m_filled)
      return(false);
   const double value=m_data[shift];
   //--- EMPTY_VALUE means the indicator has no result for that bar.
   //--- Treating it as a number is how NaN-like values poison averages.
   if(value==EMPTY_VALUE || !MathIsValidNumber(value))
      return(false);
   reading.valid=true;
   reading.value=value;
   return(true);
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::Value(const int shift,double &out) const
  {
   out=0.0;
   SIndicatorReading reading;
   if(!Read(shift,reading))
      return(false);
   out=reading.value;
   return(true);
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::Series(const int start,const int count,double &out[]) const
  {
   ArrayFree(out);
   if(!m_valid || start<0 || count<1 || start+count>m_filled)
      return(false);
   if(ArrayResize(out,count)!=count)
      return(false);
   for(int i=0;i<count;i++)
     {
      const double value=m_data[start+i];
      if(value==EMPTY_VALUE || !MathIsValidNumber(value))
        {
         ArrayFree(out);
         return(false);
        }
      out[i]=value;
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::Highest(const int start,const int count,double &out) const
  {
   out=0.0;
   if(!m_valid || start<0 || count<1 || start+count>m_filled)
      return(false);
   bool found=false;
   for(int i=start;i<start+count;i++)
     {
      const double value=m_data[i];
      if(value==EMPTY_VALUE || !MathIsValidNumber(value))
         continue;
      if(!found || value>out)
        {
         out=value;
         found=true;
        }
     }
   return(found);
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::Lowest(const int start,const int count,double &out) const
  {
   out=0.0;
   if(!m_valid || start<0 || count<1 || start+count>m_filled)
      return(false);
   bool found=false;
   for(int i=start;i<start+count;i++)
     {
      const double value=m_data[i];
      if(value==EMPTY_VALUE || !MathIsValidNumber(value))
         continue;
      if(!found || value<out)
        {
         out=value;
         found=true;
        }
     }
   return(found);
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::Average(const int start,const int count,double &out) const
  {
   out=0.0;
   if(!m_valid || start<0 || count<1 || start+count>m_filled)
      return(false);
   double sum=0.0;
   int samples=0;
   for(int i=start;i<start+count;i++)
     {
      const double value=m_data[i];
      if(value==EMPTY_VALUE || !MathIsValidNumber(value))
         continue;
      sum+=value;
      samples++;
     }
   if(samples==0)
      return(false);
   out=sum/(double)samples;
   return(true);
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::Slope(const int lookback,double &out) const
  {
   out=0.0;
   if(lookback<1)
      return(false);
   double newest=0.0;
   double oldest=0.0;
   if(!Value(0,newest) || !Value(lookback,oldest))
      return(false);
   out=(newest-oldest)/(double)lookback;
   return(true);
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::CrossedAbove(const double level) const
  {
   double current=0.0;
   double previous=0.0;
   if(!Value(0,current) || !Value(1,previous))
      return(false);
   return(previous<=level && current>level);
  }
//+------------------------------------------------------------------+
bool CIndicatorBuffer::CrossedBelow(const double level) const
  {
   double current=0.0;
   double previous=0.0;
   if(!Value(0,current) || !Value(1,previous))
      return(false);
   return(previous>=level && current<level);
  }
//+------------------------------------------------------------------+
double CIndicatorBuffer::HitRatio(void) const
  {
   const long total=m_hit_count+m_copy_count;
   if(total<=0)
      return(0.0);
   return((double)m_hit_count/(double)total*100.0);
  }

#endif // SRP_INTELLIGENCE_INDICATORS_CINDICATORBUFFER_MQH
//+------------------------------------------------------------------+
