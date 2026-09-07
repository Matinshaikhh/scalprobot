//+------------------------------------------------------------------+
//|                                        CLiquidityDetector.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): locate resting liquidity and detect when   |
//|   it is taken.                                                       |
//|                                                                  |
//|   FOUR RELATED CONCEPTS                                              |
//|                                                                  |
//|   EQUAL HIGHS/LOWS  Two or more swings at effectively the same price.  |
//|                     Stop orders cluster just beyond them, which is     |
//|                     exactly why price is drawn there.                 |
//|                                                                  |
//|   LIQUIDITY POOL    The zone just beyond an equal-level cluster where  |
//|                     those stops actually sit.                         |
//|                                                                  |
//|   LIQUIDITY SWEEP   Price penetrates a level, takes the stops, then    |
//|                     CLOSES BACK inside. The close-back is the whole    |
//|                     point: without it this is a genuine breakout, not  |
//|                     a sweep. Most implementations omit that test and   |
//|                     therefore label every breakout a "sweep".         |
//|                                                                  |
//|   INDUCEMENT        A minor swing deliberately left below/above a      |
//|                     bigger level, engineered to attract early entries  |
//|                     whose stops then fuel the real move.              |
//|                                                                  |
//|   Tolerance is expressed in ATR fractions, not fixed points, so the    |
//|   same settings behave consistently across volatility regimes.         |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_SMARTMONEY_CLIQUIDITYDETECTOR_MQH
#define SRP_INTELLIGENCE_SMARTMONEY_CLIQUIDITYDETECTOR_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "../Types/IntelligenceStructs.mqh"
#include "../Structure/CSwingDetector.mqh"
#include "../Indicators/CStandardIndicators.mqh"
#include "CZoneRegistry.mqh"

class CLiquidityDetector
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   ILogger          *m_logger;            // borrowed
   CSwingDetector   *m_swings;            // borrowed
   CAtrIntel        *m_atr;               // borrowed
   CZoneRegistry    *m_registry;          // borrowed

   //--- Tolerance for "equal", as a fraction of ATR.
   double            m_equal_tolerance_atr;
   int               m_min_equal_touches;
   //--- Pool depth beyond the level, also in ATR fractions.
   double            m_pool_depth_atr;
   int               m_sweep_lookback_bars;
   double            m_min_penetration_atr;

   SLiquiditySweep   m_last_sweep;
   SEqualLevels      m_last_equal_highs;
   SEqualLevels      m_last_equal_lows;
   datetime          m_cached_bar;
   long              m_sweep_count;
   long              m_pool_count;

   double            PointValue(void) const;
   bool              CurrentAtr(double &out) const;

public:
                     CLiquidityDetector(const string symbol,
                                        const ENUM_TIMEFRAMES tf,
                                        CSwingDetector *swings,
                                        CAtrIntel *atr,
                                        CZoneRegistry *registry,
                                        ILogger *logger);
                    ~CLiquidityDetector(void) { }

   void              SetEqualTolerance(const double atr_fraction);
   void              SetMinEqualTouches(const int touches);
   void              SetPoolDepth(const double atr_fraction);
   void              SetSweepLookback(const int bars);
   void              SetMinPenetration(const double atr_fraction);

   bool              Validate(SValidationResult &result) const;

   //--- Full scan: equal levels, pools and sweeps.
   bool              Scan(const bool force=false);

   //--- Equal highs / lows across the confirmed swing set.
   bool              FindEqualHighs(SEqualLevels &out) const;
   bool              FindEqualLows(SEqualLevels &out) const;

   //--- Registers pools just beyond equal-level clusters.
   int               RegisterLiquidityPools(void);

   //--- Sweep detection. Requires penetration AND close-back.
   bool              DetectSweep(SLiquiditySweep &out);
   bool              DetectSweepOfLevel(const double level,
                                        const ENUM_SRP_SWEEP_KIND kind,
                                        SLiquiditySweep &out) const;

   //--- Inducement: a minor swing sitting between price and a major
   //--- level, which is likely engineered to be run first.
   bool              FindInducement(const ENUM_SRP_BIAS direction,
                                    double &out_level) const;

   //--- Access.
   void              GetLastSweep(SLiquiditySweep &out) const { out=m_last_sweep; }
   void              GetEqualHighs(SEqualLevels &out) const { out=m_last_equal_highs; }
   void              GetEqualLows(SEqualLevels &out) const { out=m_last_equal_lows; }
   bool              HasRecentSweep(void) const { return(m_last_sweep.kind!=SRP_SWEEP_NONE); }

   long              SweepCount(void) const { return(m_sweep_count); }
   long              PoolCount(void)  const { return(m_pool_count); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CLiquidityDetector::CLiquidityDetector(const string symbol,
                                       const ENUM_TIMEFRAMES tf,
                                       CSwingDetector *swings,
                                       CAtrIntel *atr,
                                       CZoneRegistry *registry,
                                       ILogger *logger)
  : m_symbol(symbol),
    m_timeframe(tf),
    m_logger(logger),
    m_swings(swings),
    m_atr(atr),
    m_registry(registry),
    m_equal_tolerance_atr(0.15),
    m_min_equal_touches(2),
    m_pool_depth_atr(0.3),
    m_sweep_lookback_bars(10),
    m_min_penetration_atr(0.05),
    m_cached_bar(0),
    m_sweep_count(0),
    m_pool_count(0)
  {
  }
//+------------------------------------------------------------------+
void CLiquidityDetector::SetEqualTolerance(const double atr_fraction)
  {
   if(atr_fraction>0.0 && atr_fraction<2.0)
      m_equal_tolerance_atr=atr_fraction;
  }
//+------------------------------------------------------------------+
void CLiquidityDetector::SetMinEqualTouches(const int touches)
  {
   if(touches>=2)
      m_min_equal_touches=touches;
  }
//+------------------------------------------------------------------+
void CLiquidityDetector::SetPoolDepth(const double atr_fraction)
  {
   if(atr_fraction>0.0)
      m_pool_depth_atr=atr_fraction;
  }
//+------------------------------------------------------------------+
void CLiquidityDetector::SetSweepLookback(const int bars)
  {
   if(bars>=2)
      m_sweep_lookback_bars=bars;
  }
//+------------------------------------------------------------------+
void CLiquidityDetector::SetMinPenetration(const double atr_fraction)
  {
   if(atr_fraction>=0.0)
      m_min_penetration_atr=atr_fraction;
  }
//+------------------------------------------------------------------+
double CLiquidityDetector::PointValue(void) const
  {
   const double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   return(point>0.0 ? point : 0.00001);
  }
//+------------------------------------------------------------------+
bool CLiquidityDetector::CurrentAtr(double &out) const
  {
   out=0.0;
   if(m_atr==NULL)
      return(false);
   if(!m_atr.ValueAt(0,0,out) || out<=0.0)
      return(false);
   return(true);
  }
//+------------------------------------------------------------------+
bool CLiquidityDetector::Validate(SValidationResult &result) const
  {
   if(m_swings==NULL)
     {
      result.AddError("CLiquidityDetector: swing detector not injected");
      return(false);
     }
   if(m_atr==NULL)
     {
      result.AddError("CLiquidityDetector: ATR indicator not injected");
      return(false);
     }
   if(m_registry==NULL)
      result.AddWarning("CLiquidityDetector: no registry; pools will not be stored");
   return(true);
  }
//+------------------------------------------------------------------+
bool CLiquidityDetector::FindEqualHighs(SEqualLevels &out) const
  {
   out.Reset();
   out.kind=SRP_SWING_KIND_HIGH;

   double atr=0.0;
   if(!CurrentAtr(atr))
      return(false);
   const double tolerance=atr*m_equal_tolerance_atr;

   const int total=m_swings.HighCount();
   if(total<m_min_equal_touches)
      return(false);

   //--- Anchor on the most recent swing high and count how many older
   //--- highs sit within tolerance. Recent levels matter most because
   //--- their stops are still resting.
   SSwingPoint anchor;
   if(!m_swings.GetHigh(0,anchor))
      return(false);

   int touches=1;
   double sum=anchor.price;
   datetime first=anchor.time;
   datetime last=anchor.time;

   for(int i=1;i<total;i++)
     {
      SSwingPoint candidate;
      if(!m_swings.GetHigh(i,candidate))
         continue;
      if(MathAbs(candidate.price-anchor.price)>tolerance)
         continue;
      touches++;
      sum+=candidate.price;
      //--- Swings are newest-first, so an older swing is the first touch.
      if(candidate.time<first)
         first=candidate.time;
      if(candidate.time>last)
         last=candidate.time;
     }

   if(touches<m_min_equal_touches)
      return(false);

   out.found            = true;
   //--- Average the cluster: stops sit around the level, not exactly on
   //--- any single wick.
   out.level            = sum/(double)touches;
   out.touch_count      = touches;
   out.tolerance_points = tolerance/PointValue();
   out.first_touch      = first;
   out.last_touch       = last;
   return(true);
  }
//+------------------------------------------------------------------+
bool CLiquidityDetector::FindEqualLows(SEqualLevels &out) const
  {
   out.Reset();
   out.kind=SRP_SWING_KIND_LOW;

   double atr=0.0;
   if(!CurrentAtr(atr))
      return(false);
   const double tolerance=atr*m_equal_tolerance_atr;

   const int total=m_swings.LowCount();
   if(total<m_min_equal_touches)
      return(false);

   SSwingPoint anchor;
   if(!m_swings.GetLow(0,anchor))
      return(false);

   int touches=1;
   double sum=anchor.price;
   datetime first=anchor.time;
   datetime last=anchor.time;

   for(int i=1;i<total;i++)
     {
      SSwingPoint candidate;
      if(!m_swings.GetLow(i,candidate))
         continue;
      if(MathAbs(candidate.price-anchor.price)>tolerance)
         continue;
      touches++;
      sum+=candidate.price;
      if(candidate.time<first)
         first=candidate.time;
      if(candidate.time>last)
         last=candidate.time;
     }

   if(touches<m_min_equal_touches)
      return(false);

   out.found            = true;
   out.level            = sum/(double)touches;
   out.touch_count      = touches;
   out.tolerance_points = tolerance/PointValue();
   out.first_touch      = first;
   out.last_touch       = last;
   return(true);
  }
//+------------------------------------------------------------------+
int CLiquidityDetector::RegisterLiquidityPools(void)
  {
   if(m_registry==NULL)
      return(0);

   double atr=0.0;
   if(!CurrentAtr(atr))
      return(0);
   const double depth=atr*m_pool_depth_atr;
   int registered=0;

   //--- Pool ABOVE equal highs: that is where buy-side stops rest.
   SEqualLevels highs;
   if(FindEqualHighs(highs))
     {
      SPriceZone pool;
      pool.kind             = SRP_ZONE_LIQUIDITY_POOL;
      pool.state            = SRP_ZONE_FRESH;
      //--- NEUTRAL bias: a pool is a magnet, not a directional level.
      //--- Marking it bullish or bearish would misrepresent its meaning.
      pool.bias             = SRP_BIAS_NEUTRAL;
      pool.lower            = highs.level;
      pool.upper            = highs.level+depth;
      pool.formed_at        = highs.last_touch;
      pool.formed_bar       = 0;
      pool.has_displacement = false;
      //--- More touches means more accumulated stops.
      pool.strength         = CMathUtils::Clamp((double)highs.touch_count/4.0,0.0,1.0);
      pool.note             = StringFormat("buy-side pool, %d touches",highs.touch_count);
      if(m_registry.Add(pool))
        {
         registered++;
         m_pool_count++;
        }
     }

   //--- Pool BELOW equal lows: sell-side stops.
   SEqualLevels lows;
   if(FindEqualLows(lows))
     {
      SPriceZone pool;
      pool.kind             = SRP_ZONE_LIQUIDITY_POOL;
      pool.state            = SRP_ZONE_FRESH;
      pool.bias             = SRP_BIAS_NEUTRAL;
      pool.upper            = lows.level;
      pool.lower            = lows.level-depth;
      pool.formed_at        = lows.last_touch;
      pool.formed_bar       = 0;
      pool.has_displacement = false;
      pool.strength         = CMathUtils::Clamp((double)lows.touch_count/4.0,0.0,1.0);
      pool.note             = StringFormat("sell-side pool, %d touches",lows.touch_count);
      if(m_registry.Add(pool))
        {
         registered++;
         m_pool_count++;
        }
     }

   return(registered);
  }
//+------------------------------------------------------------------+
bool CLiquidityDetector::DetectSweepOfLevel(const double level,
                                            const ENUM_SRP_SWEEP_KIND kind,
                                            SLiquiditySweep &out) const
  {
   out.Reset();
   if(level<=0.0 || kind==SRP_SWEEP_NONE)
      return(false);

   double atr=0.0;
   if(!CurrentAtr(atr))
      return(false);
   const double min_penetration=atr*m_min_penetration_atr;

   const int available=Bars(m_symbol,m_timeframe);
   if(available<m_sweep_lookback_bars+2)
      return(false);

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   const int count=m_sweep_lookback_bars+1;
   if(CopyRates(m_symbol,m_timeframe,0,count,rates)!=count)
      return(false);

   //--- Scan recent CLOSED bars. Shift 0 is still forming, so judging it
   //--- would produce a signal that can disappear.
   for(int i=1;i<count;i++)
     {
      if(kind==SRP_SWEEP_HIGH)
        {
         //--- Penetration above the level.
         if(rates[i].high<=level+min_penetration)
            continue;
         //--- THE DEFINING TEST: closed back BELOW the level. Without
         //--- this the move is a breakout, and treating it as a sweep
         //--- would invert the expected reaction entirely.
         const bool closed_back=(rates[i].close<level);
         out.kind                = SRP_SWEEP_HIGH;
         out.swept_level         = level;
         out.extreme_reached     = rates[i].high;
         out.occurred_at         = rates[i].time;
         out.bar_shift           = i;
         out.penetration_points  = (rates[i].high-level)/PointValue();
         out.reversed            = closed_back;
         //--- Strength blends penetration depth with rejection quality.
         const double depth_score=CMathUtils::Clamp((rates[i].high-level)/atr,0.0,1.0);
         const double range=rates[i].high-rates[i].low;
         const double rejection=(range>0.0
                                 ? (rates[i].high-rates[i].close)/range : 0.0);
         out.strength=(closed_back ? (depth_score+rejection)*0.5 : depth_score*0.3);
         return(closed_back);
        }

      if(kind==SRP_SWEEP_LOW)
        {
         if(rates[i].low>=level-min_penetration)
            continue;
         const bool closed_back=(rates[i].close>level);
         out.kind                = SRP_SWEEP_LOW;
         out.swept_level         = level;
         out.extreme_reached     = rates[i].low;
         out.occurred_at         = rates[i].time;
         out.bar_shift           = i;
         out.penetration_points  = (level-rates[i].low)/PointValue();
         out.reversed            = closed_back;
         const double depth_score=CMathUtils::Clamp((level-rates[i].low)/atr,0.0,1.0);
         const double range=rates[i].high-rates[i].low;
         const double rejection=(range>0.0
                                 ? (rates[i].close-rates[i].low)/range : 0.0);
         out.strength=(closed_back ? (depth_score+rejection)*0.5 : depth_score*0.3);
         return(closed_back);
        }
     }
   return(false);
  }
//+------------------------------------------------------------------+
bool CLiquidityDetector::DetectSweep(SLiquiditySweep &out)
  {
   out.Reset();

   //--- Prefer equal-level clusters: they hold the most stops and are
   //--- therefore the most likely sweep targets.
   SEqualLevels highs;
   if(FindEqualHighs(highs))
     {
      SLiquiditySweep sweep;
      if(DetectSweepOfLevel(highs.level,SRP_SWEEP_HIGH,sweep))
        {
         out=sweep;
         m_last_sweep=sweep;
         m_sweep_count++;
         return(true);
        }
     }

   SEqualLevels lows;
   if(FindEqualLows(lows))
     {
      SLiquiditySweep sweep;
      if(DetectSweepOfLevel(lows.level,SRP_SWEEP_LOW,sweep))
        {
         out=sweep;
         m_last_sweep=sweep;
         m_sweep_count++;
         return(true);
        }
     }

   //--- Fall back to the latest single swing levels.
   SSwingPoint last_high;
   if(m_swings.LastHigh(last_high))
     {
      SLiquiditySweep sweep;
      if(DetectSweepOfLevel(last_high.price,SRP_SWEEP_HIGH,sweep))
        {
         out=sweep;
         m_last_sweep=sweep;
         m_sweep_count++;
         return(true);
        }
     }

   SSwingPoint last_low;
   if(m_swings.LastLow(last_low))
     {
      SLiquiditySweep sweep;
      if(DetectSweepOfLevel(last_low.price,SRP_SWEEP_LOW,sweep))
        {
         out=sweep;
         m_last_sweep=sweep;
         m_sweep_count++;
         return(true);
        }
     }

   return(false);
  }
//+------------------------------------------------------------------+
bool CLiquidityDetector::FindInducement(const ENUM_SRP_BIAS direction,
                                        double &out_level) const
  {
   out_level=0.0;
   if(direction==SRP_BIAS_NEUTRAL)
      return(false);

   //--- INDUCEMENT: for a bullish setup, the nearest swing low ABOVE the
   //--- deepest low. Early longs place stops under it, and that pocket of
   //--- liquidity is usually taken before the real move begins.
   if(direction==SRP_BIAS_BULLISH)
     {
      const int total=m_swings.LowCount();
      if(total<2)
         return(false);
      SSwingPoint deepest;
      if(!m_swings.GetLow(0,deepest))
         return(false);
      //--- Find the lowest low, then the next-lowest above it.
      int deepest_index=0;
      for(int i=1;i<total;i++)
        {
         SSwingPoint candidate;
         if(!m_swings.GetLow(i,candidate))
            continue;
         if(candidate.price<deepest.price)
           {
            deepest=candidate;
            deepest_index=i;
           }
        }
      bool found=false;
      double best=0.0;
      for(int i=0;i<total;i++)
        {
         if(i==deepest_index)
            continue;
         SSwingPoint candidate;
         if(!m_swings.GetLow(i,candidate))
            continue;
         if(candidate.price<=deepest.price)
            continue;
         if(!found || candidate.price<best)
           {
            best=candidate.price;
            found=true;
           }
        }
      if(found)
         out_level=best;
      return(found);
     }

   //--- Bearish mirror: nearest swing high BELOW the highest high.
   const int total=m_swings.HighCount();
   if(total<2)
      return(false);
   SSwingPoint highest;
   if(!m_swings.GetHigh(0,highest))
      return(false);
   int highest_index=0;
   for(int i=1;i<total;i++)
     {
      SSwingPoint candidate;
      if(!m_swings.GetHigh(i,candidate))
         continue;
      if(candidate.price>highest.price)
        {
         highest=candidate;
         highest_index=i;
        }
     }
   bool found=false;
   double best=0.0;
   for(int i=0;i<total;i++)
     {
      if(i==highest_index)
         continue;
      SSwingPoint candidate;
      if(!m_swings.GetHigh(i,candidate))
         continue;
      if(candidate.price>=highest.price)
         continue;
      if(!found || candidate.price>best)
        {
         best=candidate.price;
         found=true;
        }
     }
   if(found)
      out_level=best;
   return(found);
  }
//+------------------------------------------------------------------+
bool CLiquidityDetector::Scan(const bool force)
  {
   if(m_swings==NULL || m_atr==NULL)
      return(false);

   const datetime current_bar=
      (datetime)SeriesInfoInteger(m_symbol,m_timeframe,SERIES_LASTBAR_DATE);
   if(!force && m_cached_bar==current_bar)
      return(true);

   FindEqualHighs(m_last_equal_highs);
   FindEqualLows(m_last_equal_lows);
   RegisterLiquidityPools();

   SLiquiditySweep sweep;
   if(!DetectSweep(sweep))
      m_last_sweep.Reset();

   m_cached_bar=current_bar;
   return(true);
  }
//+------------------------------------------------------------------+
string CLiquidityDetector::Describe(void) const
  {
   return(StringFormat("liquidity: EQH=%s(%d) EQL=%s(%d) sweeps=%I64d pools=%I64d",
                       (m_last_equal_highs.found ? "yes" : "no"),
                       m_last_equal_highs.touch_count,
                       (m_last_equal_lows.found ? "yes" : "no"),
                       m_last_equal_lows.touch_count,
                       m_sweep_count,m_pool_count));
  }

#endif // SRP_INTELLIGENCE_SMARTMONEY_CLIQUIDITYDETECTOR_MQH
//+------------------------------------------------------------------+
