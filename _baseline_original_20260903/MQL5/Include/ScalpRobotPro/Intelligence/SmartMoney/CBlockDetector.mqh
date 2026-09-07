//+------------------------------------------------------------------+
//|                                            CBlockDetector.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): detect the three block types and fair      |
//|   value gaps, and hand them to the registry.                          |
//|                                                                  |
//|   THE FOUR CONCEPTS, PRECISELY DEFINED                                |
//|                                                                  |
//|   ORDER BLOCK      The last opposing candle before displacement.       |
//|                    A bullish OB is the last DOWN candle before an up   |
//|                    displacement - where buyers absorbed supply.        |
//|                                                                  |
//|   BREAKER BLOCK    An order block that FAILED, after price broke       |
//|                    structure through it. Its polarity inverts: a       |
//|                    failed bullish OB becomes bearish resistance.       |
//|                                                                  |
//|   MITIGATION BLOCK The origin candle of a move that returned to        |
//|                    mitigate an earlier position. Distinguished from    |
//|                    an OB by requiring a prior failed leg.             |
//|                                                                  |
//|   FAIR VALUE GAP   A three-bar pattern where bar 1's wick and bar 3's  |
//|                    wick do not overlap, leaving an unfilled void.      |
//|                                                                  |
//|   Every block requires displacement confirmation. Without that test    |
//|   "order block" means "any candle", which is worthless.                |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_SMARTMONEY_CBLOCKDETECTOR_MQH
#define SRP_INTELLIGENCE_SMARTMONEY_CBLOCKDETECTOR_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "../Types/IntelligenceStructs.mqh"
//--- CVolumeIndicator supplies the optional volume confirmation used in
//--- zone scoring.
#include "../Indicators/CComputedIndicators.mqh"
#include "CDisplacementDetector.mqh"
#include "CZoneRegistry.mqh"

class CBlockDetector
  {
private:
   string                 m_symbol;
   ENUM_TIMEFRAMES        m_timeframe;
   ILogger               *m_logger;        // borrowed
   CDisplacementDetector *m_displacement;  // borrowed
   CZoneRegistry         *m_registry;      // borrowed
   CVolumeIndicator      *m_volume;        // borrowed, optional

   int                    m_scan_bars;
   int                    m_max_lookback_for_origin;
   double                 m_min_gap_points;
   bool                   m_require_displacement;
   datetime               m_cached_bar;

   long                   m_order_blocks;
   long                   m_breaker_blocks;
   long                   m_mitigation_blocks;
   long                   m_fair_value_gaps;

   double            PointValue(void) const;
   //--- Scores a zone 0..1 from displacement size, volume and freshness.
   double            ScoreZone(const double atr_multiple,
                               const double relative_volume,
                               const bool has_displacement) const;
   //--- Walks back from a displacement bar to find the last opposing
   //--- candle, which is the order block itself.
   bool              FindOrderBlockOrigin(const MqlRates &rates[],
                                          const int count,
                                          const int displacement_index,
                                          const ENUM_SRP_BIAS direction,
                                          int &out_index) const;

public:
                     CBlockDetector(const string symbol,const ENUM_TIMEFRAMES tf,
                                    CDisplacementDetector *displacement,
                                    CZoneRegistry *registry,
                                    ILogger *logger);
                    ~CBlockDetector(void) { }

   void              SetVolumeIndicator(CVolumeIndicator *volume);
   void              SetScanBars(const int bars);
   void              SetMinGapPoints(const double points);
   void              SetRequireDisplacement(const bool value);

   bool              Validate(SValidationResult &result) const;

   //--- Full scan. Detects everything and populates the registry.
   bool              Scan(const bool force=false);

   //--- Individual detectors, exposed for targeted use and testing.
   int               DetectOrderBlocks(const MqlRates &rates[],const int count);
   int               DetectFairValueGaps(const MqlRates &rates[],const int count);
   int               DetectBreakerBlocks(const MqlRates &rates[],const int count);
   int               DetectMitigationBlocks(const MqlRates &rates[],const int count);

   //--- Diagnostics.
   long              OrderBlockCount(void)      const { return(m_order_blocks); }
   long              BreakerBlockCount(void)    const { return(m_breaker_blocks); }
   long              MitigationBlockCount(void) const { return(m_mitigation_blocks); }
   long              FairValueGapCount(void)    const { return(m_fair_value_gaps); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CBlockDetector::CBlockDetector(const string symbol,const ENUM_TIMEFRAMES tf,
                               CDisplacementDetector *displacement,
                               CZoneRegistry *registry,
                               ILogger *logger)
  : m_symbol(symbol),
    m_timeframe(tf),
    m_logger(logger),
    m_displacement(displacement),
    m_registry(registry),
    m_volume(NULL),
    m_scan_bars(120),
    m_max_lookback_for_origin(10),
    m_min_gap_points(0.0),
    m_require_displacement(true),
    m_cached_bar(0),
    m_order_blocks(0),
    m_breaker_blocks(0),
    m_mitigation_blocks(0),
    m_fair_value_gaps(0)
  {
  }
//+------------------------------------------------------------------+
void CBlockDetector::SetVolumeIndicator(CVolumeIndicator *volume)
  {
   m_volume=volume;
  }
//+------------------------------------------------------------------+
void CBlockDetector::SetScanBars(const int bars)
  {
   if(bars>=20)
      m_scan_bars=bars;
  }
//+------------------------------------------------------------------+
void CBlockDetector::SetMinGapPoints(const double points)
  {
   if(points>=0.0)
      m_min_gap_points=points;
  }
//+------------------------------------------------------------------+
void CBlockDetector::SetRequireDisplacement(const bool value)
  {
   m_require_displacement=value;
  }
//+------------------------------------------------------------------+
double CBlockDetector::PointValue(void) const
  {
   const double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   return(point>0.0 ? point : 0.00001);
  }
//+------------------------------------------------------------------+
bool CBlockDetector::Validate(SValidationResult &result) const
  {
   if(m_displacement==NULL)
     {
      result.AddError("CBlockDetector: displacement detector not injected");
      return(false);
     }
   if(m_registry==NULL)
     {
      result.AddError("CBlockDetector: zone registry not injected");
      return(false);
     }
   if(!m_require_displacement)
      result.AddWarning("CBlockDetector: displacement requirement disabled; "
                        "zone quality will be low");
   return(true);
  }
//+------------------------------------------------------------------+
double CBlockDetector::ScoreZone(const double atr_multiple,
                                 const double relative_volume,
                                 const bool has_displacement) const
  {
   //--- Composite 0..1 quality. Displacement dominates because it is the
   //--- strongest available evidence of institutional participation.
   double score=0.0;
   int components=0;

   //--- Displacement magnitude, saturating at 3x ATR.
   score+=CMathUtils::Clamp(atr_multiple/3.0,0.0,1.0);
   components++;

   //--- Volume confirmation when available.
   if(relative_volume>0.0)
     {
      score+=CMathUtils::Clamp(relative_volume/2.5,0.0,1.0);
      components++;
     }

   //--- Binary displacement flag.
   score+=(has_displacement ? 1.0 : 0.3);
   components++;

   return(components>0 ? score/(double)components : 0.0);
  }
//+------------------------------------------------------------------+
bool CBlockDetector::FindOrderBlockOrigin(const MqlRates &rates[],
                                          const int count,
                                          const int displacement_index,
                                          const ENUM_SRP_BIAS direction,
                                          int &out_index) const
  {
   out_index=-1;
   //--- Walk BACKWARDS in time (higher shift) from the displacement bar,
   //--- looking for the last candle of opposing colour. That candle is
   //--- where the opposing orders sat before being absorbed.
   const int limit=MathMin(displacement_index+m_max_lookback_for_origin,count-1);
   for(int i=displacement_index+1;i<=limit;i++)
     {
      const bool is_bullish_candle=(rates[i].close>rates[i].open);
      //--- Bullish displacement -> look for the last DOWN candle.
      if(direction==SRP_BIAS_BULLISH && !is_bullish_candle)
        {
         out_index=i;
         return(true);
        }
      //--- Bearish displacement -> look for the last UP candle.
      if(direction==SRP_BIAS_BEARISH && is_bullish_candle)
        {
         out_index=i;
         return(true);
        }
     }
   return(false);
  }
//+------------------------------------------------------------------+
int CBlockDetector::DetectOrderBlocks(const MqlRates &rates[],const int count)
  {
   int detected=0;
   //--- Start at 1: the forming bar cannot yet be assessed.
   for(int i=1;i<count-m_max_lookback_for_origin-1;i++)
     {
      SDisplacement displacement;
      if(!m_displacement.TestBar(i,displacement))
         continue;

      int origin=-1;
      if(!FindOrderBlockOrigin(rates,count,i,displacement.direction,origin))
         continue;

      SPriceZone zone;
      zone.kind             = SRP_ZONE_ORDER_BLOCK;
      zone.state            = SRP_ZONE_FRESH;
      zone.bias             = displacement.direction;
      //--- The zone is the origin candle's full range. Using the body
      //--- only is a common variant, but the wick is where the orders
      //--- actually filled, so the full range is the safer definition.
      zone.upper            = rates[origin].high;
      zone.lower            = rates[origin].low;
      zone.formed_at        = rates[origin].time;
      zone.formed_bar       = origin;
      zone.has_displacement = true;
      zone.volume_at_form   = (double)rates[origin].tick_volume;

      double relative_volume=0.0;
      if(m_volume!=NULL)
         m_volume.RelativeVolume(20,relative_volume);
      zone.strength=ScoreZone(displacement.atr_multiple,relative_volume,true);
      zone.note="OB from displacement at shift "+IntegerToString(i);

      if(m_registry.Add(zone))
        {
         detected++;
         m_order_blocks++;
        }
     }
   return(detected);
  }
//+------------------------------------------------------------------+
int CBlockDetector::DetectFairValueGaps(const MqlRates &rates[],const int count)
  {
   int detected=0;
   const double min_gap=m_min_gap_points*PointValue();

   //--- Three-bar pattern. Index i is the MIDDLE bar; i+1 is older,
   //--- i-1 is newer. A gap exists when the outer two bars' wicks do
   //--- not overlap, leaving a price band that was never traded through.
   for(int i=1;i<count-2;i++)
     {
      const int older=i+1;
      const int newer=i-1;
      if(newer<0)
         continue;

      //--- BULLISH FVG: the older bar's high sits below the newer bar's
      //--- low, so price gapped upward leaving a void beneath.
      if(rates[newer].low>rates[older].high)
        {
         const double gap=rates[newer].low-rates[older].high;
         if(gap>min_gap)
           {
            //--- Optional displacement confirmation on the middle bar.
            bool displaced=true;
            double atr_multiple=1.0;
            if(m_require_displacement)
              {
               SDisplacement displacement;
               displaced=m_displacement.TestBar(i,displacement) &&
                         displacement.direction==SRP_BIAS_BULLISH;
               if(displaced)
                  atr_multiple=displacement.atr_multiple;
              }
            if(displaced)
              {
               SPriceZone zone;
               zone.kind             = SRP_ZONE_FAIR_VALUE_GAP;
               zone.state            = SRP_ZONE_FRESH;
               zone.bias             = SRP_BIAS_BULLISH;
               zone.upper            = rates[newer].low;
               zone.lower            = rates[older].high;
               zone.formed_at        = rates[i].time;
               zone.formed_bar       = i;
               zone.has_displacement = m_require_displacement;
               zone.volume_at_form   = (double)rates[i].tick_volume;
               double relative_volume=0.0;
               if(m_volume!=NULL)
                  m_volume.RelativeVolume(20,relative_volume);
               zone.strength=ScoreZone(atr_multiple,relative_volume,displaced);
               zone.note="bullish FVG";
               if(m_registry.Add(zone))
                 {
                  detected++;
                  m_fair_value_gaps++;
                 }
              }
           }
        }

      //--- BEARISH FVG: the older bar's low sits above the newer bar's
      //--- high, so price gapped downward leaving a void above.
      if(rates[newer].high<rates[older].low)
        {
         const double gap=rates[older].low-rates[newer].high;
         if(gap>min_gap)
           {
            bool displaced=true;
            double atr_multiple=1.0;
            if(m_require_displacement)
              {
               SDisplacement displacement;
               displaced=m_displacement.TestBar(i,displacement) &&
                         displacement.direction==SRP_BIAS_BEARISH;
               if(displaced)
                  atr_multiple=displacement.atr_multiple;
              }
            if(displaced)
              {
               SPriceZone zone;
               zone.kind             = SRP_ZONE_FAIR_VALUE_GAP;
               zone.state            = SRP_ZONE_FRESH;
               zone.bias             = SRP_BIAS_BEARISH;
               zone.upper            = rates[older].low;
               zone.lower            = rates[newer].high;
               zone.formed_at        = rates[i].time;
               zone.formed_bar       = i;
               zone.has_displacement = m_require_displacement;
               zone.volume_at_form   = (double)rates[i].tick_volume;
               double relative_volume=0.0;
               if(m_volume!=NULL)
                  m_volume.RelativeVolume(20,relative_volume);
               zone.strength=ScoreZone(atr_multiple,relative_volume,displaced);
               zone.note="bearish FVG";
               if(m_registry.Add(zone))
                 {
                  detected++;
                  m_fair_value_gaps++;
                 }
              }
           }
        }
     }
   return(detected);
  }
//+------------------------------------------------------------------+
int CBlockDetector::DetectBreakerBlocks(const MqlRates &rates[],const int count)
  {
   int detected=0;
   //--- A BREAKER is a FAILED order block. The registry already tracks
   //--- invalidation, so this promotes invalidated order blocks into
   //--- breakers with INVERTED polarity: a bullish block that failed
   //--- becomes bearish resistance, because the trapped buyers above
   //--- become sellers on any retest.
   const int total=m_registry.Count();
   for(int i=0;i<total;i++)
     {
      SPriceZone zone;
      if(!m_registry.At(i,zone))
         continue;
      if(zone.kind!=SRP_ZONE_ORDER_BLOCK)
         continue;
      if(zone.state!=SRP_ZONE_INVALIDATED)
         continue;

      SPriceZone breaker;
      breaker.kind             = SRP_ZONE_BREAKER_BLOCK;
      breaker.state            = SRP_ZONE_FRESH;
      //--- POLARITY INVERSION - the defining property of a breaker.
      breaker.bias             = (zone.bias==SRP_BIAS_BULLISH
                                  ? SRP_BIAS_BEARISH : SRP_BIAS_BULLISH);
      breaker.upper            = zone.upper;
      breaker.lower            = zone.lower;
      breaker.formed_at        = zone.formed_at;
      breaker.formed_bar       = zone.formed_bar;
      breaker.has_displacement = zone.has_displacement;
      breaker.volume_at_form   = zone.volume_at_form;
      //--- Slightly discounted: a level that already failed once is
      //--- less reliable than a fresh one.
      breaker.strength         = zone.strength*0.8;
      breaker.note             = "breaker from failed OB";

      if(m_registry.Add(breaker))
        {
         detected++;
         m_breaker_blocks++;
        }
     }
   return(detected);
  }
//+------------------------------------------------------------------+
int CBlockDetector::DetectMitigationBlocks(const MqlRates &rates[],const int count)
  {
   int detected=0;
   //--- A MITIGATION BLOCK is the origin of a move that failed to make a
   //--- new extreme, then reversed. The distinguishing test versus an
   //--- order block: the leg following the origin did NOT exceed the
   //--- prior extreme before reversing, meaning positions opened there
   //--- were mitigated rather than driven to profit.
   for(int i=3;i<count-m_max_lookback_for_origin-1;i++)
     {
      SDisplacement displacement;
      if(!m_displacement.TestBar(i,displacement))
         continue;

      int origin=-1;
      if(!FindOrderBlockOrigin(rates,count,i,displacement.direction,origin))
         continue;

      //--- Look at the bars BEFORE the origin for a failed attempt in the
      //--- same direction as the displacement.
      const int window_end=MathMin(origin+m_max_lookback_for_origin,count-1);
      bool failed_leg=false;

      if(displacement.direction==SRP_BIAS_BULLISH)
        {
         //--- Find a prior high that the pre-origin move failed to clear.
         double prior_high=rates[origin].high;
         for(int j=origin+1;j<=window_end;j++)
            if(rates[j].high>prior_high)
               prior_high=rates[j].high;
         //--- If the origin candle's own high stayed below that prior
         //--- high, the earlier attempt failed - a mitigation setup.
         failed_leg=(rates[origin].high<prior_high);
        }
      else
        {
         double prior_low=rates[origin].low;
         for(int j=origin+1;j<=window_end;j++)
            if(rates[j].low<prior_low)
               prior_low=rates[j].low;
         failed_leg=(rates[origin].low>prior_low);
        }

      if(!failed_leg)
         continue;

      SPriceZone zone;
      zone.kind             = SRP_ZONE_MITIGATION_BLOCK;
      zone.state            = SRP_ZONE_FRESH;
      zone.bias             = displacement.direction;
      zone.upper            = rates[origin].high;
      zone.lower            = rates[origin].low;
      zone.formed_at        = rates[origin].time;
      zone.formed_bar       = origin;
      zone.has_displacement = true;
      zone.volume_at_form   = (double)rates[origin].tick_volume;
      double relative_volume=0.0;
      if(m_volume!=NULL)
         m_volume.RelativeVolume(20,relative_volume);
      //--- Mitigation blocks are inherently weaker than clean order
      //--- blocks, so the score is discounted.
      zone.strength=ScoreZone(displacement.atr_multiple,relative_volume,true)*0.85;
      zone.note="mitigation block";

      if(m_registry.Add(zone))
        {
         detected++;
         m_mitigation_blocks++;
        }
     }
   return(detected);
  }
//+------------------------------------------------------------------+
bool CBlockDetector::Scan(const bool force)
  {
   if(m_displacement==NULL || m_registry==NULL)
      return(false);

   const datetime current_bar=
      (datetime)SeriesInfoInteger(m_symbol,m_timeframe,SERIES_LASTBAR_DATE);
   if(!force && m_cached_bar==current_bar)
      return(true);

   const int available=Bars(m_symbol,m_timeframe);
   if(available<32)
      return(false);
   const int count=(available<m_scan_bars ? available : m_scan_bars);

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(m_symbol,m_timeframe,0,count,rates)!=count)
      return(false);

   //--- ORDER MATTERS. Zone states are advanced first so that breaker
   //--- promotion sees fresh invalidations from the current bar.
   m_registry.UpdateStates(rates[0].high,rates[0].low,rates[0].close,0);

   DetectOrderBlocks(rates,count);
   DetectFairValueGaps(rates,count);
   DetectMitigationBlocks(rates,count);
   //--- Breakers LAST: they depend on order blocks already being present
   //--- and already marked invalidated.
   DetectBreakerBlocks(rates,count);

   m_cached_bar=current_bar;
   return(true);
  }
//+------------------------------------------------------------------+
string CBlockDetector::Describe(void) const
  {
   return(StringFormat("blocks detected: OB=%I64d BB=%I64d MB=%I64d FVG=%I64d",
                       m_order_blocks,m_breaker_blocks,
                       m_mitigation_blocks,m_fair_value_gaps));
  }

#endif // SRP_INTELLIGENCE_SMARTMONEY_CBLOCKDETECTOR_MQH
//+------------------------------------------------------------------+
