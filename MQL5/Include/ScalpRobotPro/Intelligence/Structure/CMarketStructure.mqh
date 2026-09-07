//+------------------------------------------------------------------+
//|                                          CMarketStructure.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): interpret confirmed swings as structure.  |
//|   It reads CSwingDetector and produces trend direction, strength,      |
//|   phase, BOS/CHoCH events and the dealing range.                      |
//|                                                                  |
//|   IT DETECTS, IT DOES NOT TRADE. No entries, no signals - only a       |
//|   description of the market's structural state.                       |
//|                                                                  |
//|   BOS vs CHoCH - the distinction that carries the meaning             |
//|     BOS   (Break of Structure)  price breaks a swing IN the direction  |
//|           of the prevailing trend. Continuation.                      |
//|     CHoCH (Change of Character) price breaks a swing AGAINST the       |
//|           prevailing trend. The first warning of a reversal.          |
//|                                                                  |
//|   The same break is one or the other purely by trend context, which is |
//|   why this class must own the trend state as well as the events.      |
//|                                                                  |
//|   Trend strength is a composite of four measurable properties, not a   |
//|   single indicator reading, so it degrades gracefully when one input   |
//|   is unavailable.                                                    |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_STRUCTURE_CMARKETSTRUCTURE_MQH
#define SRP_INTELLIGENCE_STRUCTURE_CMARKETSTRUCTURE_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "../Types/IntelligenceStructs.mqh"
#include "CSwingDetector.mqh"

class CMarketStructure
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   ILogger          *m_logger;            // borrowed
   CSwingDetector   *m_swings;            // borrowed

   SStructureState   m_state;
   datetime          m_cached_bar;
   bool              m_valid;
   //--- Tunables.
   int               m_range_swing_count;      // swings defining the range
   double            m_break_buffer_points;    // noise filter on breaks
   double            m_equilibrium_band;       // half-width of equilibrium
   int               m_pullback_max_bars;
   //--- Event history, so a consumer can see the last transition.
   ENUM_SRP_STRUCTURE_EVENT m_previous_event;
   long              m_bos_count;
   long              m_choch_count;

   //--- Analysis steps, each isolated and independently verifiable.
   void              ResolveReferencePoints(void);
   void              ResolveDirection(void);
   void              ResolveEvent(const double current_price);
   void              ResolveRange(const double current_price);
   void              ResolveStrength(void);
   void              ResolvePhase(const double current_price);

   double            PointValue(void) const;

public:
                     CMarketStructure(const string symbol,const ENUM_TIMEFRAMES tf,
                                      CSwingDetector *swings,
                                      ILogger *logger);
                    ~CMarketStructure(void) { }

   void              SetRangeSwingCount(const int count);
   void              SetBreakBuffer(const double points);
   void              SetEquilibriumBand(const double fraction);
   void              SetPullbackMaxBars(const int bars);

   bool              Initialize(void);
   void              Shutdown(void);
   //--- Recomputes on a new bar. 'current_price' is supplied rather than
   //--- read internally, so the caller controls which price the whole
   //--- analysis is consistent with.
   bool              Refresh(const double current_price,const bool force=false);
   bool              Validate(SValidationResult &result) const;

   //--- Primary output.
   void              GetState(SStructureState &out) const { out=m_state; }

   //--- Convenience queries.
   ENUM_SRP_TREND_DIRECTION Direction(void) const { return(m_state.direction); }
   ENUM_SRP_TREND_GRADE     Grade(void)     const { return(m_state.grade); }
   ENUM_SRP_PRICE_PHASE     Phase(void)     const { return(m_state.phase); }
   ENUM_SRP_STRUCTURE_EVENT LastEvent(void) const { return(m_state.last_event); }
   double            StrengthScore(void) const { return(m_state.strength_score); }
   bool              IsBullish(void) const { return(m_state.IsBullish()); }
   bool              IsBearish(void) const { return(m_state.IsBearish()); }
   bool              IsTrending(void) const { return(m_state.IsTrending()); }
   bool              IsRanging(void) const
     { return(m_state.direction==SRP_TREND_DIR_RANGING); }

   //--- Event predicates.
   bool              HasBullishBos(void) const
     { return(m_state.last_event==SRP_STRUCT_BOS_BULLISH); }
   bool              HasBearishBos(void) const
     { return(m_state.last_event==SRP_STRUCT_BOS_BEARISH); }
   bool              HasBullishChoch(void) const
     { return(m_state.last_event==SRP_STRUCT_CHOCH_BULLISH); }
   bool              HasBearishChoch(void) const
     { return(m_state.last_event==SRP_STRUCT_CHOCH_BEARISH); }

   //--- Phase predicates.
   bool              IsBreakout(void) const  { return(m_state.phase==SRP_PHASE_BREAKOUT); }
   bool              IsPullback(void) const  { return(m_state.phase==SRP_PHASE_PULLBACK); }
   bool              IsReversal(void) const  { return(m_state.phase==SRP_PHASE_REVERSAL); }
   bool              IsConsolidating(void) const
     { return(m_state.phase==SRP_PHASE_CONSOLIDATION); }

   //--- Dealing range.
   void              GetRange(SDealingRange &out) const { out=m_state.range; }
   ENUM_SRP_RANGE_ZONE RangeZone(void) const { return(m_state.range.zone); }
   bool              IsPremium(void) const
     { return(m_state.range.zone==SRP_RANGE_PREMIUM); }
   bool              IsDiscount(void) const
     { return(m_state.range.zone==SRP_RANGE_DISCOUNT); }

   long              BosCount(void)   const { return(m_bos_count); }
   long              ChochCount(void) const { return(m_choch_count); }
   bool              IsValid(void)    const { return(m_valid); }
   string            Describe(void) const;
   static string     DirectionToString(const ENUM_SRP_TREND_DIRECTION direction);
   static string     GradeToString(const ENUM_SRP_TREND_GRADE grade);
   static string     PhaseToString(const ENUM_SRP_PRICE_PHASE phase);
   static string     EventToString(const ENUM_SRP_STRUCTURE_EVENT event);
  };

//+------------------------------------------------------------------+
CMarketStructure::CMarketStructure(const string symbol,const ENUM_TIMEFRAMES tf,
                                   CSwingDetector *swings,
                                   ILogger *logger)
  : m_symbol(symbol),
    m_timeframe(tf),
    m_logger(logger),
    m_swings(swings),
    m_cached_bar(0),
    m_valid(false),
    m_range_swing_count(8),
    m_break_buffer_points(0.0),
    m_equilibrium_band(0.05),
    m_pullback_max_bars(20),
    m_previous_event(SRP_STRUCT_NONE),
    m_bos_count(0),
    m_choch_count(0)
  {
  }
//+------------------------------------------------------------------+
void CMarketStructure::SetRangeSwingCount(const int count)
  {
   if(count>=2)
      m_range_swing_count=count;
  }
//+------------------------------------------------------------------+
void CMarketStructure::SetBreakBuffer(const double points)
  {
   if(points>=0.0)
      m_break_buffer_points=points;
  }
//+------------------------------------------------------------------+
void CMarketStructure::SetEquilibriumBand(const double fraction)
  {
   //--- Fraction of the range treated as equilibrium either side of 50%.
   if(fraction>=0.0 && fraction<0.5)
      m_equilibrium_band=fraction;
  }
//+------------------------------------------------------------------+
void CMarketStructure::SetPullbackMaxBars(const int bars)
  {
   if(bars>=1)
      m_pullback_max_bars=bars;
  }
//+------------------------------------------------------------------+
double CMarketStructure::PointValue(void) const
  {
   const double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   return(point>0.0 ? point : 0.00001);
  }
//+------------------------------------------------------------------+
bool CMarketStructure::Initialize(void)
  {
   m_state.Reset();
   m_valid=false;
   m_previous_event=SRP_STRUCT_NONE;
   return(m_swings!=NULL);
  }
//+------------------------------------------------------------------+
void CMarketStructure::Shutdown(void)
  {
   m_state.Reset();
   m_valid=false;
   m_cached_bar=0;
  }
//+------------------------------------------------------------------+
void CMarketStructure::ResolveReferencePoints(void)
  {
   m_swings.LastHigh(m_state.last_high);
   m_swings.PriorHigh(m_state.prior_high);
   m_swings.LastLow(m_state.last_low);
   m_swings.PriorLow(m_state.prior_low);
   m_state.swing_count=m_swings.HighCount()+m_swings.LowCount();
   m_state.consecutive_hh=m_swings.ConsecutiveHigherHighs();
   m_state.consecutive_ll=m_swings.ConsecutiveLowerLows();
  }
//+------------------------------------------------------------------+
void CMarketStructure::ResolveDirection(void)
  {
   //--- Direction requires two highs and two lows: a single pair cannot
   //--- establish a sequence.
   if(!m_state.last_high.valid || !m_state.prior_high.valid ||
      !m_state.last_low.valid  || !m_state.prior_low.valid)
     {
      m_state.direction=SRP_TREND_DIR_NONE;
      return;
     }

   const bool higher_high=(m_state.last_high.price>m_state.prior_high.price);
   const bool higher_low =(m_state.last_low.price >m_state.prior_low.price);
   const bool lower_high =(m_state.last_high.price<m_state.prior_high.price);
   const bool lower_low  =(m_state.last_low.price <m_state.prior_low.price);

   //--- Textbook definitions. Both conditions must agree, otherwise the
   //--- market is ranging - which is the honest answer far more often
   //--- than most trend filters admit.
   if(higher_high && higher_low)
      m_state.direction=SRP_TREND_DIR_BULLISH;
   else if(lower_high && lower_low)
      m_state.direction=SRP_TREND_DIR_BEARISH;
   else
      m_state.direction=SRP_TREND_DIR_RANGING;
  }
//+------------------------------------------------------------------+
void CMarketStructure::ResolveEvent(const double current_price)
  {
   m_state.last_event=SRP_STRUCT_NONE;
   if(!m_state.last_high.valid || !m_state.last_low.valid)
      return;

   const double buffer=m_break_buffer_points*PointValue();
   const bool broke_high=(current_price>m_state.last_high.price+buffer);
   const bool broke_low =(current_price<m_state.last_low.price-buffer);

   if(!broke_high && !broke_low)
      return;

   //--- THE BOS/CHoCH DECISION. Identical break, different meaning,
   //--- decided entirely by the prevailing trend.
   if(broke_high)
     {
      if(m_state.direction==SRP_TREND_DIR_BEARISH)
        {
         //--- Breaking a high while bearish: character has changed.
         m_state.last_event=SRP_STRUCT_CHOCH_BULLISH;
         m_choch_count++;
        }
      else
        {
         //--- Breaking a high while bullish or ranging: continuation.
         m_state.last_event=SRP_STRUCT_BOS_BULLISH;
         m_bos_count++;
        }
     }
   else
     {
      if(m_state.direction==SRP_TREND_DIR_BULLISH)
        {
         m_state.last_event=SRP_STRUCT_CHOCH_BEARISH;
         m_choch_count++;
        }
      else
        {
         m_state.last_event=SRP_STRUCT_BOS_BEARISH;
         m_bos_count++;
        }
     }

   m_state.last_event_time=TimeCurrent();
   if(m_state.last_event!=m_previous_event && m_logger!=NULL)
      m_logger.Debug("CMarketStructure",
                     "structure event: "+EventToString(m_state.last_event));
   m_previous_event=m_state.last_event;
  }
//+------------------------------------------------------------------+
void CMarketStructure::ResolveRange(const double current_price)
  {
   m_state.range.Reset();

   double highest=0.0;
   double lowest=0.0;
   if(!m_swings.HighestSwing(m_range_swing_count,highest) ||
      !m_swings.LowestSwing(m_range_swing_count,lowest))
      return;
   if(highest<=lowest)
      return;

   m_state.range.valid       = true;
   m_state.range.range_high  = highest;
   m_state.range.range_low   = lowest;
   m_state.range.equilibrium = (highest+lowest)*0.5;

   const double height=highest-lowest;
   //--- Normalised position: 0 at the low, 1 at the high.
   double position=(current_price-lowest)/height;
   position=CMathUtils::Clamp(position,0.0,1.0);
   m_state.range.current_position=position;

   //--- Premium / discount / equilibrium. The band around 50% avoids
   //--- flip-flopping when price hovers at the midpoint.
   if(position>0.5+m_equilibrium_band)
      m_state.range.zone=SRP_RANGE_PREMIUM;
   else if(position<0.5-m_equilibrium_band)
      m_state.range.zone=SRP_RANGE_DISCOUNT;
   else
      m_state.range.zone=SRP_RANGE_EQUILIBRIUM;
  }
//+------------------------------------------------------------------+
void CMarketStructure::ResolveStrength(void)
  {
   //--- COMPOSITE SCORE from four independent properties, each 0..1.
   //--- Using several inputs means one unavailable component degrades
   //--- the score rather than invalidating it.
   double score=0.0;
   int components=0;

   //--- 1. Sequence consistency: how many consecutive same-label swings.
   const int streak=(m_state.direction==SRP_TREND_DIR_BULLISH
                     ? m_state.consecutive_hh
                     : (m_state.direction==SRP_TREND_DIR_BEARISH
                        ? m_state.consecutive_ll : 0));
   if(m_state.IsTrending())
     {
      //--- Four consecutive swings is treated as a fully formed trend.
      score+=CMathUtils::Clamp((double)streak/4.0,0.0,1.0);
      components++;
     }

   //--- 2. Swing displacement: size of the latest leg relative to the
   //--- dealing range. A trend making large legs is stronger.
   if(m_state.range.valid && m_state.range.Height()>0.0)
     {
      double leg=0.0;
      if(m_state.direction==SRP_TREND_DIR_BULLISH &&
         m_state.last_high.valid && m_state.last_low.valid)
         leg=m_state.last_high.price-m_state.last_low.price;
      else if(m_state.direction==SRP_TREND_DIR_BEARISH &&
              m_state.last_high.valid && m_state.last_low.valid)
         leg=m_state.last_high.price-m_state.last_low.price;
      if(leg>0.0)
        {
         score+=CMathUtils::Clamp(leg/m_state.range.Height(),0.0,1.0);
         components++;
        }
     }

   //--- 3. Range position agreement: a bullish trend in the premium
   //--- zone is confirmed; one stuck in discount is not.
   if(m_state.range.valid)
     {
      if(m_state.direction==SRP_TREND_DIR_BULLISH)
        {
         score+=m_state.range.current_position;
         components++;
        }
      else if(m_state.direction==SRP_TREND_DIR_BEARISH)
        {
         score+=(1.0-m_state.range.current_position);
         components++;
        }
     }

   //--- 4. Structural clarity: enough swings to trust the reading.
   if(m_state.swing_count>0)
     {
      score+=CMathUtils::Clamp((double)m_state.swing_count/8.0,0.0,1.0);
      components++;
     }

   m_state.strength_score=(components>0 ? score/(double)components : 0.0);

   //--- Grade the score. EXHAUSTED is deliberately separate from STRONG:
   //--- a long streak at an extreme of the range is powerful but late,
   //--- and consumers must be able to tell those apart.
   if(!m_state.IsTrending())
      m_state.grade=SRP_TREND_GRADE_NONE;
   else if(m_state.strength_score>=0.75)
     {
      const bool overextended=
         (m_state.direction==SRP_TREND_DIR_BULLISH &&
          m_state.range.valid && m_state.range.current_position>0.95 && streak>=4) ||
         (m_state.direction==SRP_TREND_DIR_BEARISH &&
          m_state.range.valid && m_state.range.current_position<0.05 && streak>=4);
      m_state.grade=(overextended ? SRP_TREND_GRADE_EXHAUSTED
                                  : SRP_TREND_GRADE_STRONG);
     }
   else if(m_state.strength_score>=0.45)
      m_state.grade=SRP_TREND_GRADE_MODERATE;
   else
      m_state.grade=SRP_TREND_GRADE_WEAK;
  }
//+------------------------------------------------------------------+
void CMarketStructure::ResolvePhase(const double current_price)
  {
   m_state.phase=SRP_PHASE_UNDEFINED;

   //--- A CHoCH is the defining evidence of a reversal attempt, so it
   //--- takes precedence over every other phase reading.
   if(m_state.last_event==SRP_STRUCT_CHOCH_BULLISH ||
      m_state.last_event==SRP_STRUCT_CHOCH_BEARISH)
     {
      m_state.phase=SRP_PHASE_REVERSAL;
      return;
     }

   //--- A BOS in the trend direction is a breakout.
   if(m_state.last_event==SRP_STRUCT_BOS_BULLISH ||
      m_state.last_event==SRP_STRUCT_BOS_BEARISH)
     {
      m_state.phase=SRP_PHASE_BREAKOUT;
      return;
     }

   //--- Ranging with no break is consolidation.
   if(!m_state.IsTrending())
     {
      m_state.phase=SRP_PHASE_CONSOLIDATION;
      return;
     }

   //--- Trending without a fresh break: decide pullback vs continuation
   //--- by where price sits relative to the latest leg.
   if(m_state.direction==SRP_TREND_DIR_BULLISH &&
      m_state.last_high.valid && m_state.last_low.valid)
     {
      const double leg=m_state.last_high.price-m_state.last_low.price;
      if(leg>0.0)
        {
         const double retrace=(m_state.last_high.price-current_price)/leg;
         //--- Between 20% and 80% back into the leg is a pullback; beyond
         //--- that the leg's premise is questionable.
         m_state.phase=(retrace>=0.2 && retrace<=0.8
                        ? SRP_PHASE_PULLBACK : SRP_PHASE_CONSOLIDATION);
        }
      return;
     }

   if(m_state.direction==SRP_TREND_DIR_BEARISH &&
      m_state.last_high.valid && m_state.last_low.valid)
     {
      const double leg=m_state.last_high.price-m_state.last_low.price;
      if(leg>0.0)
        {
         const double retrace=(current_price-m_state.last_low.price)/leg;
         m_state.phase=(retrace>=0.2 && retrace<=0.8
                        ? SRP_PHASE_PULLBACK : SRP_PHASE_CONSOLIDATION);
        }
     }
  }
//+------------------------------------------------------------------+
bool CMarketStructure::Refresh(const double current_price,const bool force)
  {
   if(m_swings==NULL)
      return(false);

   const datetime current_bar=
      (datetime)SeriesInfoInteger(m_symbol,m_timeframe,SERIES_LASTBAR_DATE);
   //--- Price-dependent parts must recompute intrabar, so only the swing
   //--- rescan is bar-gated. The cache check therefore does not
   //--- short-circuit the whole method.
   const bool new_bar=(m_cached_bar!=current_bar);
   if(new_bar || force)
     {
      if(!m_swings.Refresh(force))
         return(false);
      m_cached_bar=current_bar;
     }

   if(m_swings.HighCount()==0 && m_swings.LowCount()==0)
     {
      m_valid=false;
      return(false);
     }

   //--- Ordered: reference points, then direction, then everything that
   //--- depends on direction.
   ResolveReferencePoints();
   ResolveDirection();
   ResolveRange(current_price);
   ResolveEvent(current_price);
   ResolveStrength();
   ResolvePhase(current_price);

   m_valid=true;
   return(true);
  }
//+------------------------------------------------------------------+
bool CMarketStructure::Validate(SValidationResult &result) const
  {
   if(m_swings==NULL)
     {
      result.AddError("CMarketStructure: swing detector not injected");
      return(false);
     }
   if(m_range_swing_count<2)
     {
      result.AddError("CMarketStructure: range swing count must be at least 2");
      return(false);
     }
   if(!m_valid)
      result.AddWarning("CMarketStructure: no successful analysis yet");
   return(true);
  }
//+------------------------------------------------------------------+
string CMarketStructure::DirectionToString(const ENUM_SRP_TREND_DIRECTION direction)
  {
   switch(direction)
     {
      case SRP_TREND_DIR_BULLISH: return("BULLISH");
      case SRP_TREND_DIR_BEARISH: return("BEARISH");
      case SRP_TREND_DIR_RANGING: return("RANGING");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CMarketStructure::GradeToString(const ENUM_SRP_TREND_GRADE grade)
  {
   switch(grade)
     {
      case SRP_TREND_GRADE_WEAK:      return("WEAK");
      case SRP_TREND_GRADE_MODERATE:  return("MODERATE");
      case SRP_TREND_GRADE_STRONG:    return("STRONG");
      case SRP_TREND_GRADE_EXHAUSTED: return("EXHAUSTED");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CMarketStructure::PhaseToString(const ENUM_SRP_PRICE_PHASE phase)
  {
   switch(phase)
     {
      case SRP_PHASE_BREAKOUT:      return("BREAKOUT");
      case SRP_PHASE_PULLBACK:      return("PULLBACK");
      case SRP_PHASE_REVERSAL:      return("REVERSAL");
      case SRP_PHASE_CONSOLIDATION: return("CONSOLIDATION");
     }
   return("UNDEFINED");
  }
//+------------------------------------------------------------------+
string CMarketStructure::EventToString(const ENUM_SRP_STRUCTURE_EVENT event)
  {
   switch(event)
     {
      case SRP_STRUCT_BOS_BULLISH:   return("BOS_BULLISH");
      case SRP_STRUCT_BOS_BEARISH:   return("BOS_BEARISH");
      case SRP_STRUCT_CHOCH_BULLISH: return("CHOCH_BULLISH");
      case SRP_STRUCT_CHOCH_BEARISH: return("CHOCH_BEARISH");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CMarketStructure::Describe(void) const
  {
   return(StringFormat("%s/%s phase=%s event=%s score=%.2f swings=%d zone=%s",
                       DirectionToString(m_state.direction),
                       GradeToString(m_state.grade),
                       PhaseToString(m_state.phase),
                       EventToString(m_state.last_event),
                       m_state.strength_score,
                       m_state.swing_count,
                       (m_state.range.zone==SRP_RANGE_PREMIUM ? "PREMIUM" :
                        m_state.range.zone==SRP_RANGE_DISCOUNT ? "DISCOUNT" :
                        m_state.range.zone==SRP_RANGE_EQUILIBRIUM ? "EQ" : "N/A")));
  }

#endif // SRP_INTELLIGENCE_STRUCTURE_CMARKETSTRUCTURE_MQH
//+------------------------------------------------------------------+
