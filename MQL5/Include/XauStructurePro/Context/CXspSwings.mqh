//+------------------------------------------------------------------+
//|                                                   CXspSwings.mqh |
//|         XauStructurePro - Context (L1) : non-repainting fractals |
//|                                                                  |
//|   XSP's own, not SRP's CSwingDetector. That class is sound and was      |
//|   read in full, but it has two behaviours that would corrupt this       |
//|   study, and both are properties of its interface rather than bugs:     |
//|                                                                  |
//|     1. bar_shift is recorded at detection time. Two refreshes later     |
//|        the shift points at a different bar. Every identity in XSP is     |
//|        keyed on (price, bar TIME) for exactly this reason - a drifting   |
//|        identity is what let defect 2 count one occurrence twice.        |
//|     2. Refresh() rebuilds both arrays with swept=false, so             |
//|        MarkHighSwept has no effect that survives the next bar. S2       |
//|        depends on remembering which pools have been consumed.           |
//|                                                                  |
//|   Reusing it would mean tracking sweep state and stable identity        |
//|   outside it anyway, i.e. writing most of this file regardless, while   |
//|   also pulling ILogger, IntelligenceStructs, Structs and                |
//|   IntelligenceEnums out of the frozen tree.                            |
//|                                                                  |
//|   NON-REPAINTING BY CONSTRUCTION. A swing needs m_strength CLOSED bars  |
//|   on BOTH sides, and the newest bar considered is index 1, so the        |
//|   forming bar can never participate. History does not change, so a       |
//|   confirmed swing never moves.                                         |
//+------------------------------------------------------------------+
#ifndef XSP_CONTEXT_CXSPSWINGS_MQH
#define XSP_CONTEXT_CXSPSWINGS_MQH

#include "../Core/XspTypes.mqh"

#define XSP_MAX_SWINGS                64

struct SXspSwing
  {
   bool              valid;
   bool              is_high;
   double            price;
   datetime          time;         // the bar the extreme belongs to

   void Reset()
     {
      valid=false;
      is_high=false;
      price=0.0;
      time=0;
     }
  };

class CXspSwings
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_strength;
   int               m_lookback;

   SXspSwing         m_highs[];
   SXspSwing         m_lows[];
   int               m_high_count;
   int               m_low_count;
   datetime          m_built_for;   // bar time the arrays were built on
   long              m_rebuilds;

public:
                     CXspSwings(void)
     {
      m_symbol="";
      m_tf=PERIOD_CURRENT;
      m_strength=3;
      m_lookback=300;
      m_high_count=0;
      m_low_count=0;
      m_built_for=0;
      m_rebuilds=0;
      ArrayResize(m_highs,XSP_MAX_SWINGS);
      ArrayResize(m_lows,XSP_MAX_SWINGS);
     }

   bool              Initialize(const string symbol,const ENUM_TIMEFRAMES tf,
                                const int strength=3,const int lookback=300)
     {
      m_symbol=symbol;
      m_tf=tf;
      m_strength=(strength>0?strength:3);
      //--- The scan needs 2*strength+2 bars before it can confirm anything;
      //--- a lookback smaller than that would return an empty list forever
      //--- rather than reporting a configuration error once.
      const int floor_bars=2*m_strength+8;
      m_lookback=(lookback>floor_bars?lookback:floor_bars);
      return(true);
     }

   ENUM_TIMEFRAMES   Timeframe(void)  const { return(m_tf); }
   int               HighCount(void)   const { return(m_high_count); }
   int               LowCount(void)    const { return(m_low_count); }
   long              Rebuilds(void)    const { return(m_rebuilds); }

   //--- index 0 is the MOST RECENT confirmed swing.
   bool              GetHigh(const int index,SXspSwing &out) const
     {
      if(index<0 || index>=m_high_count) return(false);
      out=m_highs[index];
      return(true);
     }

   bool              GetLow(const int index,SXspSwing &out) const
     {
      if(index<0 || index>=m_low_count) return(false);
      out=m_lows[index];
      return(true);
     }

   //+---------------------------------------------------------------+
   //| Rebuild the swing lists. Idempotent within a bar: a second call  |
   //| on the same bar does nothing, so calling it per tick is safe and |
   //| costs one datetime comparison.                                  |
   //+---------------------------------------------------------------+
   bool              Refresh(const bool force=false)
     {
      const datetime bar=iTime(m_symbol,m_tf,0);
      if(bar==0) return(false);
      if(!force && bar==m_built_for) return(true);

      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      const int got=CopyRates(m_symbol,m_tf,0,m_lookback,rates);
      if(got<(2*m_strength+2)) return(false);

      m_high_count=0;
      m_low_count=0;

      //--- Index 0 is the FORMING bar. The newest bar a swing may occupy is
      //--- index 1+strength, because it needs strength closed bars newer
      //--- than itself and index 0 is not closed. Walking ascending means
      //--- the list comes out most-recent-first with no later sort.
      for(int i=m_strength+1;i<got-m_strength;i++)
        {
         if(m_high_count<XSP_MAX_SWINGS && IsSwingHigh(rates,i,got))
           {
            m_highs[m_high_count].valid=true;
            m_highs[m_high_count].is_high=true;
            m_highs[m_high_count].price=rates[i].high;
            m_highs[m_high_count].time=rates[i].time;
            m_high_count++;
           }
         if(m_low_count<XSP_MAX_SWINGS && IsSwingLow(rates,i,got))
           {
            m_lows[m_low_count].valid=true;
            m_lows[m_low_count].is_high=false;
            m_lows[m_low_count].price=rates[i].low;
            m_lows[m_low_count].time=rates[i].time;
            m_low_count++;
           }
        }

      m_built_for=bar;
      m_rebuilds++;
      return(true);
     }

   //+---------------------------------------------------------------+
   //| H1/H4 structural class from swing labels alone.                  |
   //|                                                                |
   //| No EMA, no ADX, no threshold. Every one of those carries a number |
   //| that would have to be chosen, and choosing it on this data is the |
   //| section-9 violation the rebuild exists to avoid. Higher high AND  |
   //| higher low is an uptrend by definition, not by calibration.       |
   //|                                                                |
   //| Anything that is not both is CHOP - including the one-sided case  |
   //| (higher high, lower low: an expanding range). Calling an          |
   //| expansion a trend is how a range gets traded as a continuation.   |
   //+---------------------------------------------------------------+
   ENUM_XSP_TREND    Classify(void) const
     {
      if(m_high_count<2 || m_low_count<2) return(XSP_TREND_CHOP);
      const bool hh=(m_highs[0].price>m_highs[1].price);
      const bool hl=(m_lows[0].price>m_lows[1].price);
      const bool lh=(m_highs[0].price<m_highs[1].price);
      const bool ll=(m_lows[0].price<m_lows[1].price);
      if(hh && hl) return(XSP_TREND_UP);
      if(lh && ll) return(XSP_TREND_DOWN);
      return(XSP_TREND_CHOP);
     }

   //--- Where a price sits inside the most recent confirmed swing range,
   //--- 0 = at the swing low, 1 = at the swing high. -1 when no range is
   //--- confirmed yet; NOT clamped to 0..1, because a value outside it
   //--- means price has left the range and that is information.
   double            RangePosition(const double price) const
     {
      if(m_high_count<1 || m_low_count<1) return(-1.0);
      const double hi=m_highs[0].price;
      const double lo=m_lows[0].price;
      const double span=hi-lo;
      if(span<=XSP_EPSILON) return(-1.0);
      return((price-lo)/span);
     }

   string            Describe(void) const
     {
      return(StringFormat("swings %s strength=%d highs=%d lows=%d class=%s rebuilds=%I64d",
                          EnumToString(m_tf),m_strength,m_high_count,m_low_count,
                          XspTrendName(Classify()),m_rebuilds));
     }

private:
   //+---------------------------------------------------------------+
   //| Fractal test with an ASYMMETRIC tie-break.                       |
   //|                                                                |
   //| Newer side must be strictly LOWER; older side must be not higher. |
   //| The asymmetry is the whole point: on a flat top of two equal      |
   //| highs, a symmetric test confirms NEITHER (each sees an equal      |
   //| neighbour) or BOTH (if both use >=), and "both" would hand the     |
   //| pool detector two levels at one price that then look like an      |
   //| equal-highs cluster formed by a single bar pair.                  |
   //|                                                                |
   //| With this rule the NEWER of two equal highs is confirmed and the  |
   //| older is not - one level, and the more recent of the two, which    |
   //| is the one resting orders would actually sit at. The rule is       |
   //| SRP CSwingDetector's; it is one of the things that class got       |
   //| right, and it is reproduced here rather than reinvented.          |
   //+---------------------------------------------------------------+
   bool              IsSwingHigh(const MqlRates &rates[],const int index,const int count) const
     {
      if(index-m_strength<1 || index+m_strength>=count) return(false);
      const double candidate=rates[index].high;
      for(int offset=1;offset<=m_strength;offset++)
        {
         if(rates[index-offset].high>=candidate) return(false);
         if(rates[index+offset].high>candidate)  return(false);
        }
      return(true);
     }

   bool              IsSwingLow(const MqlRates &rates[],const int index,const int count) const
     {
      if(index-m_strength<1 || index+m_strength>=count) return(false);
      const double candidate=rates[index].low;
      for(int offset=1;offset<=m_strength;offset++)
        {
         if(rates[index-offset].low<=candidate) return(false);
         if(rates[index+offset].low<candidate)  return(false);
        }
      return(true);
     }
  };

#endif // XSP_CONTEXT_CXSPSWINGS_MQH
//+------------------------------------------------------------------+
