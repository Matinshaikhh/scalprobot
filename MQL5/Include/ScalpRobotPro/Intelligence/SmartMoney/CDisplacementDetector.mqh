//+------------------------------------------------------------------+
//|                                     CDisplacementDetector.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): identify displacement - an impulsive,      |
//|   one-sided move that is large relative to recent volatility.          |
//|                                                                  |
//|   WHY DISPLACEMENT IS THE KEYSTONE OF THIS SUBSYSTEM                  |
//|   Every zone concept depends on it. An order block formed by an        |
//|   ordinary candle is just a candle; an order block followed by         |
//|   displacement is evidence that a large participant moved price away   |
//|   from that level. Without a displacement test, "order block"          |
//|   degenerates into "any recent candle", which is why so many SMC       |
//|   implementations mark up dozens of meaningless boxes.                 |
//|                                                                  |
//|   Three conditions, all required:                                     |
//|     1. RANGE     bar range >= N x ATR (materially larger than normal)  |
//|     2. BODY      body / range >= threshold (directional, not a wick)   |
//|     3. CLOSE     closes in the top/bottom fraction of its own range    |
//|                                                                  |
//|   Requiring all three rejects wide indecision bars, which have the     |
//|   range of displacement but none of the conviction.                    |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_SMARTMONEY_CDISPLACEMENTDETECTOR_MQH
#define SRP_INTELLIGENCE_SMARTMONEY_CDISPLACEMENTDETECTOR_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../Types/IntelligenceStructs.mqh"
#include "../Indicators/CStandardIndicators.mqh"

class CDisplacementDetector
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   ILogger          *m_logger;            // borrowed
   CAtrIntel        *m_atr;               // borrowed - volatility reference

   //--- Thresholds.
   double            m_min_atr_multiple;
   double            m_min_body_ratio;
   double            m_close_position;    // fraction of range for the close
   int               m_lookback_bars;

   SDisplacement     m_last;
   long              m_detection_count;

public:
                     CDisplacementDetector(const string symbol,
                                           const ENUM_TIMEFRAMES tf,
                                           CAtrIntel *atr,
                                           ILogger *logger);
                    ~CDisplacementDetector(void) { }

   void              SetThresholds(const double min_atr_multiple,
                                   const double min_body_ratio,
                                   const double close_position);
   void              SetLookback(const int bars);

   bool              Validate(SValidationResult &result) const;

   //--- Tests one specific bar.
   bool              TestBar(const int shift,SDisplacement &out) const;
   //--- Scans the recent window and returns the most recent displacement.
   bool              FindRecent(SDisplacement &out);
   //--- True when the given bar displaced in the given direction.
   bool              IsDisplacement(const int shift,
                                    const ENUM_SRP_BIAS direction) const;

   void              GetLast(SDisplacement &out) const { out=m_last; }
   long              DetectionCount(void) const { return(m_detection_count); }
   double            MinAtrMultiple(void) const { return(m_min_atr_multiple); }
  };

//+------------------------------------------------------------------+
CDisplacementDetector::CDisplacementDetector(const string symbol,
                                             const ENUM_TIMEFRAMES tf,
                                             CAtrIntel *atr,
                                             ILogger *logger)
  : m_symbol(symbol),
    m_timeframe(tf),
    m_logger(logger),
    m_atr(atr),
    m_min_atr_multiple(1.5),
    m_min_body_ratio(0.6),
    m_close_position(0.7),
    m_lookback_bars(20),
    m_detection_count(0)
  {
  }
//+------------------------------------------------------------------+
void CDisplacementDetector::SetThresholds(const double min_atr_multiple,
                                          const double min_body_ratio,
                                          const double close_position)
  {
   if(min_atr_multiple>0.0)
      m_min_atr_multiple=min_atr_multiple;
   if(min_body_ratio>0.0 && min_body_ratio<=1.0)
      m_min_body_ratio=min_body_ratio;
   if(close_position>0.5 && close_position<=1.0)
      m_close_position=close_position;
  }
//+------------------------------------------------------------------+
void CDisplacementDetector::SetLookback(const int bars)
  {
   if(bars>=1)
      m_lookback_bars=bars;
  }
//+------------------------------------------------------------------+
bool CDisplacementDetector::Validate(SValidationResult &result) const
  {
   if(m_atr==NULL)
     {
      result.AddError("CDisplacementDetector: ATR indicator not injected");
      return(false);
     }
   if(m_min_atr_multiple<1.0)
      result.AddWarning("CDisplacementDetector: ATR multiple below 1.0 will "
                        "flag ordinary bars as displacement");
   return(true);
  }
//+------------------------------------------------------------------+
bool CDisplacementDetector::TestBar(const int shift,SDisplacement &out) const
  {
   out.Reset();
   if(shift<0 || m_atr==NULL)
      return(false);

   //--- ATR is read at the SAME shift as the bar under test, so an old
   //--- bar is judged against the volatility that prevailed then rather
   //--- than against today's.
   double atr_value=0.0;
   if(!m_atr.ValueAt(0,shift,atr_value) || atr_value<=0.0)
      return(false);

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(m_symbol,m_timeframe,shift,1,rates)!=1)
      return(false);

   const double high=rates[0].high;
   const double low=rates[0].low;
   const double open=rates[0].open;
   const double close=rates[0].close;
   const double range=high-low;
   if(range<=0.0)
      return(false);

   const double body=MathAbs(close-open);
   const double body_ratio=body/range;
   const double atr_multiple=range/atr_value;

   out.bar_shift    = shift;
   out.occurred_at  = rates[0].time;
   out.range_points = range/(SymbolInfoDouble(m_symbol,SYMBOL_POINT)>0.0
                             ? SymbolInfoDouble(m_symbol,SYMBOL_POINT) : 1.0);
   out.body_ratio   = body_ratio;
   out.atr_multiple = atr_multiple;

   //--- CONDITION 1: materially larger than normal volatility.
   if(atr_multiple<m_min_atr_multiple)
      return(false);
   //--- CONDITION 2: directional body, not a wide indecision bar.
   if(body_ratio<m_min_body_ratio)
      return(false);

   //--- CONDITION 3: closes near its own extreme, confirming the move
   //--- was held into the close rather than rejected.
   const bool bullish=(close>open);
   const double close_fraction=(bullish ? (close-low)/range : (high-close)/range);
   if(close_fraction<m_close_position)
      return(false);

   out.detected  = true;
   out.direction = (bullish ? SRP_BIAS_BULLISH : SRP_BIAS_BEARISH);
   return(true);
  }
//+------------------------------------------------------------------+
bool CDisplacementDetector::FindRecent(SDisplacement &out)
  {
   out.Reset();
   //--- Start at shift 1: the forming bar can still change entirely, so
   //--- judging it would produce a signal that repaints.
   for(int shift=1;shift<=m_lookback_bars;shift++)
     {
      SDisplacement candidate;
      if(!TestBar(shift,candidate))
         continue;
      out=candidate;
      m_last=candidate;
      m_detection_count++;
      return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
bool CDisplacementDetector::IsDisplacement(const int shift,
                                           const ENUM_SRP_BIAS direction) const
  {
   SDisplacement candidate;
   if(!TestBar(shift,candidate))
      return(false);
   if(direction==SRP_BIAS_NEUTRAL)
      return(true);
   return(candidate.direction==direction);
  }

#endif // SRP_INTELLIGENCE_SMARTMONEY_CDISPLACEMENTDETECTOR_MQH
//+------------------------------------------------------------------+
