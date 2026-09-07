//+------------------------------------------------------------------+
//|                                            CSwingDetector.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): find confirmed swing highs and lows.      |
//|                                                                  |
//|   A swing high is a bar whose high exceeds the highs of N bars on      |
//|   BOTH sides. The right-hand requirement is what makes it confirmed:   |
//|   until N bars have closed after the candidate, it can still be        |
//|   exceeded.                                                         |
//|                                                                  |
//|   THE REPAINTING TRAP                                               |
//|   Detecting swings on unconfirmed bars is why so many structure        |
//|   indicators repaint: a "swing high" appears, then vanishes as price   |
//|   pushes higher. Every swing this class reports has already been       |
//|   confirmed by N closed bars, so its history never changes. The cost   |
//|   is an N-bar detection lag, which is the honest price of a stable     |
//|   signal and is documented rather than hidden.                        |
//|                                                                  |
//|   It stores swings newest-first and labels them HH/HL/LH/LL by         |
//|   comparing each to the previous swing of the same kind.               |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_STRUCTURE_CSWINGDETECTOR_MQH
#define SRP_INTELLIGENCE_STRUCTURE_CSWINGDETECTOR_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../Types/IntelligenceStructs.mqh"

class CSwingDetector
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   ILogger          *m_logger;            // borrowed
   //--- Bars required either side of a candidate. Larger = fewer, more
   //--- significant swings, and more lag.
   int               m_strength;
   int               m_lookback_bars;
   int               m_max_swings;

   //--- Confirmed swings, newest first.
   SSwingPoint       m_highs[];
   SSwingPoint       m_lows[];
   datetime          m_cached_bar;
   bool              m_valid;
   long              m_detection_count;

   bool              IsSwingHigh(const MqlRates &rates[],const int index,
                                 const int count) const;
   bool              IsSwingLow(const MqlRates &rates[],const int index,
                                const int count) const;
   //--- Assigns HH/HL/LH/LL by comparing consecutive same-kind swings.
   void              LabelSwings(void);
   bool              PushHigh(const SSwingPoint &swing);
   bool              PushLow(const SSwingPoint &swing);

public:
                     CSwingDetector(const string symbol,const ENUM_TIMEFRAMES tf,
                                    ILogger *logger,
                                    const int strength=3,
                                    const int lookback_bars=300,
                                    const int max_swings=64);
                    ~CSwingDetector(void);

   void              SetStrength(const int strength);
   void              SetLookback(const int bars);

   bool              Initialize(void);
   void              Shutdown(void);
   //--- Rescans on a new bar only; calling every tick is cheap.
   bool              Refresh(const bool force=false);
   bool              Validate(SValidationResult &result) const;

   //--- Access. Index 0 == most recent confirmed swing.
   int               HighCount(void) const { return(ArraySize(m_highs)); }
   int               LowCount(void)  const { return(ArraySize(m_lows)); }
   bool              GetHigh(const int index,SSwingPoint &out) const;
   bool              GetLow(const int index,SSwingPoint &out) const;
   bool              LastHigh(SSwingPoint &out) const  { return(GetHigh(0,out)); }
   bool              PriorHigh(SSwingPoint &out) const { return(GetHigh(1,out)); }
   bool              LastLow(SSwingPoint &out) const   { return(GetLow(0,out)); }
   bool              PriorLow(SSwingPoint &out) const  { return(GetLow(1,out)); }

   //--- Highest high / lowest low across the confirmed set: the dealing
   //--- range boundaries.
   bool              HighestSwing(const int count,double &out) const;
   bool              LowestSwing(const int count,double &out) const;

   //--- Counts consecutive same-label swings, the raw input to trend
   //--- grading.
   int               ConsecutiveHigherHighs(void) const;
   int               ConsecutiveLowerLows(void) const;

   //--- Marks a swing as swept once its liquidity has been taken.
   bool              MarkHighSwept(const int index);
   bool              MarkLowSwept(const int index);

   bool              IsValid(void) const { return(m_valid); }
   int               Strength(void) const { return(m_strength); }
   long              DetectionCount(void) const { return(m_detection_count); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CSwingDetector::CSwingDetector(const string symbol,const ENUM_TIMEFRAMES tf,
                               ILogger *logger,
                               const int strength,
                               const int lookback_bars,
                               const int max_swings)
  : m_symbol(symbol),
    m_timeframe(tf),
    m_logger(logger),
    m_strength(strength<1 ? 1 : strength),
    m_lookback_bars(lookback_bars<32 ? 32 : lookback_bars),
    m_max_swings(max_swings<4 ? 4 : max_swings),
    m_cached_bar(0),
    m_valid(false),
    m_detection_count(0)
  {
   ArrayResize(m_highs,0);
   ArrayResize(m_lows,0);
  }
//+------------------------------------------------------------------+
CSwingDetector::~CSwingDetector(void)
  {
   ArrayFree(m_highs);
   ArrayFree(m_lows);
  }
//+------------------------------------------------------------------+
void CSwingDetector::SetStrength(const int strength)
  {
   if(strength>=1)
     {
      m_strength=strength;
      m_valid=false;              // force a rescan under the new setting
     }
  }
//+------------------------------------------------------------------+
void CSwingDetector::SetLookback(const int bars)
  {
   if(bars>=32)
     {
      m_lookback_bars=bars;
      m_valid=false;
     }
  }
//+------------------------------------------------------------------+
bool CSwingDetector::Initialize(void)
  {
   ArrayResize(m_highs,0);
   ArrayResize(m_lows,0);
   m_valid=false;
   return(true);
  }
//+------------------------------------------------------------------+
void CSwingDetector::Shutdown(void)
  {
   ArrayResize(m_highs,0);
   ArrayResize(m_lows,0);
   m_valid=false;
   m_cached_bar=0;
  }
//+------------------------------------------------------------------+
bool CSwingDetector::IsSwingHigh(const MqlRates &rates[],const int index,
                                 const int count) const
  {
   //--- Need m_strength bars on BOTH sides. The right-side requirement
   //--- is what makes the swing confirmed and non-repainting.
   if(index-m_strength<0 || index+m_strength>=count)
      return(false);

   const double candidate=rates[index].high;
   for(int offset=1;offset<=m_strength;offset++)
     {
      //--- Strictly greater on the newer side, greater-or-equal on the
      //--- older side. The asymmetry breaks ties deterministically so a
      //--- flat top yields exactly one swing, not several.
      if(rates[index-offset].high>=candidate)
         return(false);
      if(rates[index+offset].high>candidate)
         return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CSwingDetector::IsSwingLow(const MqlRates &rates[],const int index,
                                const int count) const
  {
   if(index-m_strength<0 || index+m_strength>=count)
      return(false);

   const double candidate=rates[index].low;
   for(int offset=1;offset<=m_strength;offset++)
     {
      if(rates[index-offset].low<=candidate)
         return(false);
      if(rates[index+offset].low<candidate)
         return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CSwingDetector::PushHigh(const SSwingPoint &swing)
  {
   const int size=ArraySize(m_highs);
   if(size>=m_max_swings)
      return(true);                       // capacity reached, keep newest
   if(ArrayResize(m_highs,size+1)!=size+1)
      return(false);
   m_highs[size]=swing;
   return(true);
  }
//+------------------------------------------------------------------+
bool CSwingDetector::PushLow(const SSwingPoint &swing)
  {
   const int size=ArraySize(m_lows);
   if(size>=m_max_swings)
      return(true);
   if(ArrayResize(m_lows,size+1)!=size+1)
      return(false);
   m_lows[size]=swing;
   return(true);
  }
//+------------------------------------------------------------------+
void CSwingDetector::LabelSwings(void)
  {
   //--- Highs: compare each to the NEXT one in the array, which is the
   //--- chronologically PRIOR swing (array is newest-first).
   const int high_count=ArraySize(m_highs);
   for(int i=0;i<high_count;i++)
     {
      if(i+1>=high_count)
        {
         m_highs[i].label=SRP_SWING_UNCLASSIFIED;
         continue;
        }
      m_highs[i].label=(m_highs[i].price>m_highs[i+1].price
                        ? SRP_SWING_HH : SRP_SWING_LH);
     }

   const int low_count=ArraySize(m_lows);
   for(int i=0;i<low_count;i++)
     {
      if(i+1>=low_count)
        {
         m_lows[i].label=SRP_SWING_UNCLASSIFIED;
         continue;
        }
      m_lows[i].label=(m_lows[i].price>m_lows[i+1].price
                       ? SRP_SWING_HL : SRP_SWING_LL);
     }
  }
//+------------------------------------------------------------------+
bool CSwingDetector::Refresh(const bool force)
  {
   const datetime current_bar=
      (datetime)SeriesInfoInteger(m_symbol,m_timeframe,SERIES_LASTBAR_DATE);
   if(!force && m_valid && m_cached_bar==current_bar)
      return(true);

   const int available=Bars(m_symbol,m_timeframe);
   const int required=m_strength*2+2;
   if(available<required)
     {
      m_valid=false;
      return(false);
     }
   const int count=(available<m_lookback_bars ? available : m_lookback_bars);

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(m_symbol,m_timeframe,0,count,rates)!=count)
     {
      m_valid=false;
      return(false);
     }

   ArrayResize(m_highs,0);
   ArrayResize(m_lows,0);

   //--- Scan newest to oldest so the arrays end up newest-first
   //--- naturally. Start at m_strength: bars newer than that cannot yet
   //--- be confirmed.
   for(int i=m_strength;i<count-m_strength;i++)
     {
      if(ArraySize(m_highs)>=m_max_swings && ArraySize(m_lows)>=m_max_swings)
         break;

      if(IsSwingHigh(rates,i,count))
        {
         SSwingPoint swing;
         swing.valid     = true;
         swing.kind      = SRP_SWING_KIND_HIGH;
         swing.price     = rates[i].high;
         swing.time      = rates[i].time;
         swing.bar_shift = i;
         swing.strength  = m_strength;
         swing.swept     = false;
         if(!PushHigh(swing))
            break;
         m_detection_count++;
        }

      if(IsSwingLow(rates,i,count))
        {
         SSwingPoint swing;
         swing.valid     = true;
         swing.kind      = SRP_SWING_KIND_LOW;
         swing.price     = rates[i].low;
         swing.time      = rates[i].time;
         swing.bar_shift = i;
         swing.strength  = m_strength;
         swing.swept     = false;
         if(!PushLow(swing))
            break;
         m_detection_count++;
        }
     }

   LabelSwings();
   m_cached_bar=current_bar;
   m_valid=true;
   return(true);
  }
//+------------------------------------------------------------------+
bool CSwingDetector::Validate(SValidationResult &result) const
  {
   if(m_strength<1)
     {
      result.AddError("CSwingDetector: strength must be at least 1");
      return(false);
     }
   if(m_strength>20)
      result.AddWarning("CSwingDetector: strength above 20 yields very few swings");
   const int available=Bars(m_symbol,m_timeframe);
   if(available<m_strength*2+2)
     {
      result.AddError("CSwingDetector: insufficient bars for the configured strength");
      return(false);
     }
   if(!m_valid)
      result.AddWarning("CSwingDetector: no successful scan yet");
   return(true);
  }
//+------------------------------------------------------------------+
bool CSwingDetector::GetHigh(const int index,SSwingPoint &out) const
  {
   out.Reset();
   if(!m_valid || index<0 || index>=ArraySize(m_highs))
      return(false);
   out=m_highs[index];
   return(true);
  }
//+------------------------------------------------------------------+
bool CSwingDetector::GetLow(const int index,SSwingPoint &out) const
  {
   out.Reset();
   if(!m_valid || index<0 || index>=ArraySize(m_lows))
      return(false);
   out=m_lows[index];
   return(true);
  }
//+------------------------------------------------------------------+
bool CSwingDetector::HighestSwing(const int count,double &out) const
  {
   out=0.0;
   const int total=ArraySize(m_highs);
   if(!m_valid || total==0)
      return(false);
   const int limit=(count<1 || count>total ? total : count);
   out=m_highs[0].price;
   for(int i=1;i<limit;i++)
      if(m_highs[i].price>out)
         out=m_highs[i].price;
   return(true);
  }
//+------------------------------------------------------------------+
bool CSwingDetector::LowestSwing(const int count,double &out) const
  {
   out=0.0;
   const int total=ArraySize(m_lows);
   if(!m_valid || total==0)
      return(false);
   const int limit=(count<1 || count>total ? total : count);
   out=m_lows[0].price;
   for(int i=1;i<limit;i++)
      if(m_lows[i].price<out)
         out=m_lows[i].price;
   return(true);
  }
//+------------------------------------------------------------------+
int CSwingDetector::ConsecutiveHigherHighs(void) const
  {
   int streak=0;
   const int total=ArraySize(m_highs);
   for(int i=0;i<total;i++)
     {
      if(m_highs[i].label!=SRP_SWING_HH)
         break;
      streak++;
     }
   return(streak);
  }
//+------------------------------------------------------------------+
int CSwingDetector::ConsecutiveLowerLows(void) const
  {
   int streak=0;
   const int total=ArraySize(m_lows);
   for(int i=0;i<total;i++)
     {
      if(m_lows[i].label!=SRP_SWING_LL)
         break;
      streak++;
     }
   return(streak);
  }
//+------------------------------------------------------------------+
bool CSwingDetector::MarkHighSwept(const int index)
  {
   if(index<0 || index>=ArraySize(m_highs))
      return(false);
   m_highs[index].swept=true;
   return(true);
  }
//+------------------------------------------------------------------+
bool CSwingDetector::MarkLowSwept(const int index)
  {
   if(index<0 || index>=ArraySize(m_lows))
      return(false);
   m_lows[index].swept=true;
   return(true);
  }
//+------------------------------------------------------------------+
string CSwingDetector::Describe(void) const
  {
   return(StringFormat("swings: %d highs, %d lows (strength=%d, lookback=%d) valid=%s",
                       ArraySize(m_highs),ArraySize(m_lows),
                       m_strength,m_lookback_bars,
                       (m_valid ? "yes" : "no")));
  }

#endif // SRP_INTELLIGENCE_STRUCTURE_CSWINGDETECTOR_MQH
//+------------------------------------------------------------------+
