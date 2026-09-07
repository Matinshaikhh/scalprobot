//+------------------------------------------------------------------+
//|                                            CSmcStrategies.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   Five plugins built on the Phase 2 Smart Money and VWAP modules:      |
//|     CVwapPullbackStrategy   reversion to session VWAP                  |
//|     CLiquiditySweepStrategy entry after a confirmed stop run            |
//|     COrderBlockStrategy     entry at a fresh order block                |
//|     CFairValueGapStrategy   entry at an unfilled FVG                    |
//|     CMeanReversionPlugin    band-extreme reversion                      |
//|                                                                  |
//|   These consume Phase 2 detection rather than reimplementing it. The   |
//|   zone registry already tracks lifecycle state, so a plugin only has   |
//|   to decide whether an ACTIONABLE zone is worth trading now.           |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_STRATEGIES_CSMCSTRATEGIES_MQH
#define SRP_DECISION_STRATEGIES_CSMCSTRATEGIES_MQH

#include "CStrategyPlugin.mqh"

//+------------------------------------------------------------------+
//| VWAP PULLBACK                                                     |
//|                                                                  |
//| Trades price returning to session VWAP in the direction of the         |
//| prevailing bias. VWAP is the institutional reference price, so a       |
//| pullback to it inside a trend is a value entry rather than a           |
//| reversal - which is why trend agreement is required, not optional.     |
//+------------------------------------------------------------------+
class CVwapPullbackStrategy : public CStrategyPlugin
  {
private:
   double            m_touch_tolerance_atr;
   double            m_max_distance_atr;
   bool              m_require_trend_agreement;
   bool              m_use_bands;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     CVwapPullbackStrategy(CStrategyContext *context,
                                           ILogger *logger)
     : CStrategyPlugin("VwapPullback",SRP_STRAT_VWAP_PULLBACK,context,logger),
       m_touch_tolerance_atr(0.20),
       m_max_distance_atr(0.60),
       m_require_trend_agreement(true),
       m_use_bands(true) { }

   void              SetTouchTolerance(const double atr_fraction)
     { if(atr_fraction>0.0) m_touch_tolerance_atr=atr_fraction; }
   void              SetMaxDistance(const double atr_fraction)
     { if(atr_fraction>0.0) m_max_distance_atr=atr_fraction; }
   void              SetRequireTrendAgreement(const bool require_agreement)
     { m_require_trend_agreement=require_agreement; }
   void              SetUseBands(const bool use_bands) { m_use_bands=use_bands; }
  };
//+------------------------------------------------------------------+
bool CVwapPullbackStrategy::OnValidate(SValidationResult &result)
  {
   if(m_context.Vwap()==NULL)
     {
      result.AddError(m_name+": requires VWAP");
      return(false);
     }
   if(m_context.Atr()==NULL)
     {
      result.AddError(m_name+": requires ATR for tolerance scaling");
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CVwapPullbackStrategy::OnEvaluate(const SDecisionInput &snapshot,
                                       SStrategySignal &signal)
  {
   double vwap=0.0;
   if(!m_context.VwapValue(vwap))
      return(false);
   double atr=0.0;
   if(!m_context.AtrValue(atr) || atr<=0.0)
      return(false);

   const double distance=MathAbs(snapshot.close-vwap);
   const double tolerance=atr*m_touch_tolerance_atr;

   //--- Price must be NEAR vwap: this is a pullback entry, not a
   //--- momentum-away-from-value entry.
   if(distance>tolerance)
      return(false);

   //--- BIAS. Direction comes from structure when available, otherwise
   //--- from which side of VWAP price approached from.
   ENUM_SRP_DECISION decision=SRP_DECISION_NO_TRADE;
   bool trend_confirmed=false;

   if(snapshot.structure_valid && snapshot.structure.IsTrending())
     {
      decision=(snapshot.structure.IsBullish() ? SRP_DECISION_BUY
                                            : SRP_DECISION_SELL);
      trend_confirmed=true;
     }
   else if(!m_require_trend_agreement)
     {
      //--- Fall back to the prior bar's position relative to VWAP.
      decision=(snapshot.prev_close>vwap ? SRP_DECISION_BUY : SRP_DECISION_SELL);
     }
   else
      return(false);

   //--- The pullback must not have become a breakdown: for a long, price
   //--- should be at or above VWAP, not far below it.
   const double signed_distance=snapshot.close-vwap;
   if(decision==SRP_DECISION_BUY && signed_distance<-tolerance)
      return(false);
   if(decision==SRP_DECISION_SELL && signed_distance>tolerance)
      return(false);

   //--- CONFIDENCE: proximity, band position, structure, liquidity.
   double score=0.0;
   int components=0;

   //--- Closer to VWAP is a better entry, so proximity inverts distance.
   score+=CMathUtils::Clamp(1.0-(distance/tolerance),0.0,1.0);
   components++;

   if(m_use_bands)
     {
      CVwapIndicator *vwap_ind=m_context.Vwap();
      double upper=0.0,lower=0.0;
      if(vwap_ind!=NULL && vwap_ind.Upper(0,upper) && vwap_ind.Lower(0,lower) &&
         upper>lower)
        {
         //--- Inside the bands is mean-reversion territory and scores
         //--- higher than an extended move.
         const bool inside=(snapshot.close<=upper && snapshot.close>=lower);
         score+=(inside ? 1.0 : 0.4);
         components++;
        }
     }
   if(trend_confirmed)
     {
      score+=snapshot.structure.strength_score;
      components++;
     }
   score+=snapshot.session.liquidity_score;
   components++;

   const double confidence=score/(double)components;
   const string reason=StringFormat(
      "VWAP pullback: price %.1f pts from VWAP %.*f%s",
      (snapshot.point>0.0 ? distance/snapshot.point : 0.0),
      snapshot.digits,vwap,
      (trend_confirmed
       ? ", "+CMarketStructure::DirectionToString(snapshot.structure.direction)+" trend"
       : ""));

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));
   //--- VWAP itself is the invalidation reference for this thesis.
   signal.suggested_entry=snapshot.close;
   return(true);
  }

//+------------------------------------------------------------------+
//| LIQUIDITY SWEEP                                                   |
//|                                                                  |
//| Enters AGAINST the sweep direction after a confirmed stop run. The     |
//| logic is deliberately counter-intuitive: a sweep of highs is a         |
//| BEARISH signal, because the buy-side liquidity above has been consumed |
//| and price closed back below. Phase 2 already enforces the close-back   |
//| requirement, so a "sweep" reaching this plugin is a genuine one.       |
//+------------------------------------------------------------------+
class CLiquiditySweepStrategy : public CStrategyPlugin
  {
private:
   int               m_max_bars_since_sweep;
   double            m_min_sweep_strength;
   bool              m_require_structure_agreement;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     CLiquiditySweepStrategy(CStrategyContext *context,
                                             ILogger *logger)
     : CStrategyPlugin("LiquiditySweep",SRP_STRAT_LIQUIDITY_SWEEP,
                       context,logger),
       m_max_bars_since_sweep(3),
       m_min_sweep_strength(0.35),
       m_require_structure_agreement(false) { }

   void              SetMaxBarsSinceSweep(const int bars)
     { if(bars>=1) m_max_bars_since_sweep=bars; }
   void              SetMinSweepStrength(const double strength)
     { if(strength>=0.0 && strength<=1.0) m_min_sweep_strength=strength; }
   void              SetRequireStructureAgreement(const bool require_agreement)
     { m_require_structure_agreement=require_agreement; }
  };
//+------------------------------------------------------------------+
bool CLiquiditySweepStrategy::OnValidate(SValidationResult &result)
  {
   if(m_context.Liquidity()==NULL)
     {
      result.AddError(m_name+": requires the liquidity detector");
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CLiquiditySweepStrategy::OnEvaluate(const SDecisionInput &snapshot,
                                         SStrategySignal &signal)
  {
   CLiquidityDetector *liquidity=m_context.Liquidity();
   if(liquidity==NULL)
      return(false);

   SLiquiditySweep sweep;
   liquidity.GetLastSweep(sweep);
   if(sweep.kind==SRP_SWEEP_NONE)
      return(false);

   //--- Phase 2 sets 'reversed' only when price closed back inside. A
   //--- sweep without that is a breakout, and trading it as a reversal
   //--- would be exactly wrong.
   if(!sweep.reversed)
      return(false);
   //--- Freshness: the edge decays quickly after the run.
   if(sweep.bar_shift>m_max_bars_since_sweep)
      return(false);
   if(sweep.strength<m_min_sweep_strength)
      return(false);

   //--- THE INVERSION. Highs swept means buy-side liquidity is gone, so
   //--- the expectation is downward continuation.
   const ENUM_SRP_DECISION decision=(sweep.kind==SRP_SWEEP_HIGH
                                     ? SRP_DECISION_SELL : SRP_DECISION_BUY);

   //--- Optional structure agreement. Off by default because a sweep is
   //--- frequently the event that PRECEDES a structure change, so
   //--- demanding agreement would filter out the best cases.
   if(m_require_structure_agreement && snapshot.structure_valid)
     {
      const bool agrees=(decision==SRP_DECISION_BUY
                         ? !snapshot.structure.IsBearish()
                         : !snapshot.structure.IsBullish());
      if(!agrees)
         return(false);
     }

   //--- CONFIDENCE: sweep strength, penetration, recency, liquidity.
   //---
   //--- REDESIGN 2026-09-04. SCALE, NOT STRENGTH. This was the arithmetic
   //--- MEAN of its four components, while CBreakOfStructureStrategy and the
   //--- rest of the plugin set build confidence as a 0.50 base plus bounded
   //--- increments. A mean of four terms in [0,1] lands around 0.55-0.65
   //--- almost regardless of how good the setup is, and break-of-structure
   //--- saturates at 0.93 almost regardless of the same - so under any
   //--- confidence-ranked vote the sweep lost every contest it entered. In
   //--- July 2026 that produced 135 break-of-structure entries against 3
   //--- sweeps, and the three sweeps were the only positive contributors in
   //--- the month.
   //---
   //--- Nothing about the EVIDENCE changes here. The same four measurements
   //--- are read, in the same order, with the two sweep-specific ones
   //--- carrying more weight than the two context ones. What changes is that
   //--- the result is now on the same scale as every plugin it is compared
   //--- against, which is a precondition for the comparison meaning
   //--- anything at all. The cap keeps it short of certainty.
   double confidence=0.50;
   confidence+=0.15*CMathUtils::Clamp(sweep.strength,0.0,1.0);

   double atr=0.0;
   if(m_context.AtrValue(atr) && atr>0.0 && snapshot.point>0.0)
     {
      const double penetration_price=sweep.penetration_points*snapshot.point;
      //--- A deeper run took more stops and is more significant, but the
      //--- effect saturates.
      confidence+=0.15*CMathUtils::Clamp(penetration_price/atr,0.0,1.0);
     }
   //--- Recency: shift 1 is best, decaying to the limit.
   confidence+=0.10*CMathUtils::Clamp(
      1.0-((double)(sweep.bar_shift-1)/(double)m_max_bars_since_sweep),0.0,1.0);
   confidence+=0.10*CMathUtils::Clamp(snapshot.session.liquidity_score,0.0,1.0);
   confidence=CMathUtils::Clamp(confidence,0.0,0.95);

   const string reason=StringFormat(
      "liquidity sweep of %s at %.*f (%.1f pts, %d bars ago) - fading",
      (sweep.kind==SRP_SWEEP_HIGH ? "highs" : "lows"),
      snapshot.digits,sweep.swept_level,
      sweep.penetration_points,sweep.bar_shift);

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));
   //--- The sweep extreme is the natural invalidation: if price returns
   //--- beyond it, the fade thesis is dead.
   signal.suggested_stop=sweep.extreme_reached;
   return(true);
  }

//+------------------------------------------------------------------+
//| ORDER BLOCK ENTRY                                                 |
//|                                                                  |
//| Enters when price returns into a fresh order block. Phase 2 already   |
//| validated displacement at formation and tracks consumption, so this   |
//| plugin only decides whether an ACTIONABLE block is worth trading.     |
//+------------------------------------------------------------------+
class COrderBlockStrategy : public CStrategyPlugin
  {
private:
   double            m_min_zone_strength;
   bool              m_require_midpoint;    // wait for 50% penetration
   bool              m_require_range_agreement;
   int               m_max_touches;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     COrderBlockStrategy(CStrategyContext *context,ILogger *logger)
     : CStrategyPlugin("OrderBlock",SRP_STRAT_ORDER_BLOCK,context,logger),
       m_min_zone_strength(0.40),
       m_require_midpoint(false),
       m_require_range_agreement(true),
       m_max_touches(2) { }

   void              SetMinZoneStrength(const double strength)
     { if(strength>=0.0 && strength<=1.0) m_min_zone_strength=strength; }
   void              SetRequireMidpoint(const bool require_midpoint)
     { m_require_midpoint=require_midpoint; }
   void              SetRequireRangeAgreement(const bool require_agreement)
     { m_require_range_agreement=require_agreement; }
   void              SetMaxTouches(const int touches)
     { if(touches>=1) m_max_touches=touches; }
  };
//+------------------------------------------------------------------+
bool COrderBlockStrategy::OnValidate(SValidationResult &result)
  {
   if(m_context.Zones()==NULL)
     {
      result.AddError(m_name+": requires the zone registry");
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool COrderBlockStrategy::OnEvaluate(const SDecisionInput &snapshot,
                                     SStrategySignal &signal)
  {
   CZoneRegistry *zones=m_context.Zones();
   if(zones==NULL)
      return(false);

   //--- Find the actionable zone price is currently inside.
   SPriceZone zone;
   if(!zones.ZoneContaining(snapshot.close,zone))
      return(false);
   if(zone.kind!=SRP_ZONE_ORDER_BLOCK && zone.kind!=SRP_ZONE_BREAKER_BLOCK)
      return(false);
   if(zone.bias==SRP_BIAS_NEUTRAL)
      return(false);
   if(zone.strength<m_min_zone_strength)
      return(false);
   //--- A repeatedly tested block has been largely consumed.
   if(zone.touch_count>m_max_touches)
      return(false);

   //--- Optional 50% requirement: waiting for the midpoint gives a better
   //--- entry but misses shallow reactions.
   if(m_require_midpoint)
     {
      if(zone.bias==SRP_BIAS_BULLISH && snapshot.close>zone.midpoint)
         return(false);
      if(zone.bias==SRP_BIAS_BEARISH && snapshot.close<zone.midpoint)
         return(false);
     }

   const ENUM_SRP_DECISION decision=(zone.bias==SRP_BIAS_BULLISH
                                     ? SRP_DECISION_BUY : SRP_DECISION_SELL);

   //--- PREMIUM/DISCOUNT AGREEMENT. A bullish block in the premium half
   //--- of the range is poor value, and this is where most order-block
   //--- entries go wrong.
   if(m_require_range_agreement && snapshot.structure_valid &&
      snapshot.structure.range.valid)
     {
      const ENUM_SRP_RANGE_ZONE range_zone=snapshot.structure.range.zone;
      if(decision==SRP_DECISION_BUY && range_zone==SRP_RANGE_PREMIUM)
         return(false);
      if(decision==SRP_DECISION_SELL && range_zone==SRP_RANGE_DISCOUNT)
         return(false);
     }

   //--- CONFIDENCE: zone strength, freshness, displacement, liquidity.
   double score=zone.strength;
   int components=1;

   //--- Fresh beats tested.
   score+=(zone.state==SRP_ZONE_FRESH ? 1.0 : 0.5);
   components++;
   //--- Displacement at formation is the strongest quality signal.
   score+=(zone.has_displacement ? 1.0 : 0.3);
   components++;
   score+=snapshot.session.liquidity_score;
   components++;

   const double confidence=score/(double)components;
   const string reason=StringFormat(
      "%s %s block %.*f-%.*f, strength %.2f, %d touch(es)",
      (zone.bias==SRP_BIAS_BULLISH ? "bullish" : "bearish"),
      (zone.kind==SRP_ZONE_BREAKER_BLOCK ? "breaker" : "order"),
      snapshot.digits,zone.lower,snapshot.digits,zone.upper,
      zone.strength,zone.touch_count);

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));
   //--- The far edge of the zone is the invalidation point.
   signal.suggested_stop=(decision==SRP_DECISION_BUY ? zone.lower : zone.upper);
   signal.suggested_entry=zone.midpoint;
   return(true);
  }

//+------------------------------------------------------------------+
//| FAIR VALUE GAP ENTRY                                              |
//|                                                                  |
//| Enters when price returns into an unfilled FVG. The thesis is that     |
//| price seeks to rebalance inefficiency, so the gap acts as a magnet     |
//| and then as support or resistance.                                    |
//+------------------------------------------------------------------+
class CFairValueGapStrategy : public CStrategyPlugin
  {
private:
   double            m_min_zone_strength;
   double            m_min_gap_atr;
   bool              m_require_fresh;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     CFairValueGapStrategy(CStrategyContext *context,
                                           ILogger *logger)
     : CStrategyPlugin("FairValueGap",SRP_STRAT_FAIR_VALUE_GAP,context,logger),
       m_min_zone_strength(0.35),
       m_min_gap_atr(0.15),
       m_require_fresh(true) { }

   void              SetMinZoneStrength(const double strength)
     { if(strength>=0.0 && strength<=1.0) m_min_zone_strength=strength; }
   void              SetMinGapAtr(const double atr_fraction)
     { if(atr_fraction>=0.0) m_min_gap_atr=atr_fraction; }
   void              SetRequireFresh(const bool require_fresh)
     { m_require_fresh=require_fresh; }
  };
//+------------------------------------------------------------------+
bool CFairValueGapStrategy::OnValidate(SValidationResult &result)
  {
   if(m_context.Zones()==NULL)
     {
      result.AddError(m_name+": requires the zone registry");
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CFairValueGapStrategy::OnEvaluate(const SDecisionInput &snapshot,
                                       SStrategySignal &signal)
  {
   CZoneRegistry *zones=m_context.Zones();
   if(zones==NULL)
      return(false);

   //--- Look specifically for an FVG containing price. Searching by kind
   //--- avoids picking an overlapping order block instead.
   SPriceZone zone;
   if(!zones.ZoneContaining(snapshot.close,zone))
      return(false);
   if(zone.kind!=SRP_ZONE_FAIR_VALUE_GAP)
      return(false);
   if(zone.bias==SRP_BIAS_NEUTRAL)
      return(false);
   if(zone.strength<m_min_zone_strength)
      return(false);
   if(m_require_fresh && zone.state!=SRP_ZONE_FRESH)
      return(false);

   //--- MINIMUM GAP SIZE. A gap narrower than a fraction of ATR is
   //--- rounding noise, not an inefficiency worth trading.
   double atr=0.0;
   const bool has_atr=m_context.AtrValue(atr);
   const double height=zone.Height();
   if(has_atr && atr>0.0 && m_min_gap_atr>0.0)
     {
      if(height<atr*m_min_gap_atr)
         return(false);
     }

   const ENUM_SRP_DECISION decision=(zone.bias==SRP_BIAS_BULLISH
                                     ? SRP_DECISION_BUY : SRP_DECISION_SELL);

   //--- CONFIDENCE: strength, gap size, structure, liquidity.
   double score=zone.strength;
   int components=1;
   if(has_atr && atr>0.0)
     {
      //--- A larger gap is a stronger imbalance, saturating at 1 ATR.
      score+=CMathUtils::Clamp(height/atr,0.0,1.0);
      components++;
     }
   if(snapshot.structure_valid)
     {
      const bool agrees=(decision==SRP_DECISION_BUY
                         ? !snapshot.structure.IsBearish()
                         : !snapshot.structure.IsBullish());
      score+=(agrees ? 1.0 : 0.3);
      components++;
     }
   score+=snapshot.session.liquidity_score;
   components++;

   const double confidence=score/(double)components;
   const string reason=StringFormat(
      "%s FVG %.*f-%.*f (%.1f pts), strength %.2f",
      (zone.bias==SRP_BIAS_BULLISH ? "bullish" : "bearish"),
      snapshot.digits,zone.lower,snapshot.digits,zone.upper,
      (snapshot.point>0.0 ? height/snapshot.point : 0.0),
      zone.strength);

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));
   signal.suggested_stop=(decision==SRP_DECISION_BUY ? zone.lower : zone.upper);
   signal.suggested_entry=zone.midpoint;
   return(true);
  }

//+------------------------------------------------------------------+
//| MEAN REVERSION                                                    |
//|                                                                  |
//| Fades stretched moves back toward the Bollinger mid-band. Requires    |
//| the market NOT to be strongly trending: fading a strong trend is how  |
//| mean-reversion systems produce their worst losses, so trend strength  |
//| is an explicit veto rather than a confidence penalty.                 |
//+------------------------------------------------------------------+
class CMeanReversionPlugin : public CStrategyPlugin
  {
private:
   double            m_rsi_oversold;
   double            m_rsi_overbought;
   double            m_max_adx;             // veto above this
   double            m_min_band_width_atr;
   bool              m_require_rsi_confirmation;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     CMeanReversionPlugin(CStrategyContext *context,ILogger *logger)
     : CStrategyPlugin("MeanReversion",SRP_STRAT_MEAN_REVERSION,context,logger),
       m_rsi_oversold(30.0),
       m_rsi_overbought(70.0),
       m_max_adx(30.0),
       m_min_band_width_atr(1.0),
       m_require_rsi_confirmation(true) { }

   void              SetRsiThresholds(const double oversold,const double overbought)
     {
      if(oversold<50.0)   m_rsi_oversold=oversold;
      if(overbought>50.0) m_rsi_overbought=overbought;
     }
   void              SetMaxAdx(const double value)
     { if(value>0.0) m_max_adx=value; }
   void              SetMinBandWidth(const double atr_multiple)
     { if(atr_multiple>=0.0) m_min_band_width_atr=atr_multiple; }
   void              SetRequireRsi(const bool require_rsi)
     { m_require_rsi_confirmation=require_rsi; }
  };
//+------------------------------------------------------------------+
bool CMeanReversionPlugin::OnValidate(SValidationResult &result)
  {
   if(m_context.Bollinger()==NULL)
     {
      result.AddError(m_name+": requires Bollinger Bands");
      return(false);
     }
   if(m_require_rsi_confirmation && m_context.Rsi()==NULL)
      result.AddWarning(m_name+": RSI confirmation requested but none wired");
   return(true);
  }
//+------------------------------------------------------------------+
bool CMeanReversionPlugin::OnEvaluate(const SDecisionInput &snapshot,
                                      SStrategySignal &signal)
  {
   double upper=0.0,middle=0.0,lower=0.0;
   if(!m_context.BollingerBands(upper,middle,lower))
      return(false);
   if(upper<=lower)
      return(false);

   //--- TREND VETO. This is the single most important guard for a
   //--- mean-reversion plugin: in a strong trend the bands ride with
   //--- price and every fade loses.
   double adx=0.0;
   if(m_context.AdxValue(adx) && m_max_adx>0.0 && adx>m_max_adx)
      return(false);
   //--- Structure veto: a strongly graded trend is equally disqualifying.
   if(snapshot.structure_valid && snapshot.structure.IsTrending() &&
      (snapshot.structure.grade==SRP_TREND_GRADE_STRONG))
      return(false);

   //--- BAND WIDTH. Reverting inside a compressed range is noise trading.
   double atr=0.0;
   const bool has_atr=m_context.AtrValue(atr);
   const double width=upper-lower;
   if(has_atr && atr>0.0 && m_min_band_width_atr>0.0)
     {
      if(width<atr*m_min_band_width_atr)
         return(false);
     }

   //--- Price must be beyond a band.
   ENUM_SRP_DECISION decision=SRP_DECISION_NO_TRADE;
   double penetration=0.0;
   if(snapshot.close<lower)
     {
      decision=SRP_DECISION_BUY;
      penetration=lower-snapshot.close;
     }
   else if(snapshot.close>upper)
     {
      decision=SRP_DECISION_SELL;
      penetration=snapshot.close-upper;
     }
   if(decision==SRP_DECISION_NO_TRADE)
      return(false);

   //--- RSI CONFIRMATION. Price beyond a band plus an RSI extreme is a
   //--- materially better setup than either alone.
   double rsi=0.0;
   const bool has_rsi=m_context.RsiValue(rsi);
   if(m_require_rsi_confirmation)
     {
      if(!has_rsi)
         return(false);
      const bool confirms=(decision==SRP_DECISION_BUY
                           ? rsi<=m_rsi_oversold : rsi>=m_rsi_overbought);
      if(!confirms)
         return(false);
     }

   //--- CONFIDENCE: penetration, RSI extremity, low ADX, band width.
   double score=0.0;
   int components=0;
   if(has_atr && atr>0.0)
     {
      score+=CMathUtils::Clamp(penetration/(atr*0.5),0.0,1.0);
      components++;
     }
   if(has_rsi)
     {
      //--- Distance past the threshold, saturating 20 points beyond.
      const double extremity=(decision==SRP_DECISION_BUY
                              ? m_rsi_oversold-rsi : rsi-m_rsi_overbought);
      score+=CMathUtils::Clamp(extremity/20.0,0.0,1.0);
      components++;
     }
   if(m_max_adx>0.0)
     {
      //--- Lower ADX is BETTER for this plugin, so the score inverts.
      score+=CMathUtils::Clamp(1.0-(adx/m_max_adx),0.0,1.0);
      components++;
     }
   score+=snapshot.session.liquidity_score;
   components++;

   const double confidence=(components>0 ? score/(double)components : 0.0);
   const string reason=StringFormat(
      "mean reversion: price %.1f pts beyond %s band%s, ADX %.1f",
      (snapshot.point>0.0 ? penetration/snapshot.point : 0.0),
      (decision==SRP_DECISION_BUY ? "lower" : "upper"),
      (has_rsi ? StringFormat(", RSI %.1f",rsi) : ""),
      adx);

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));
   //--- The mid-band is the thesis target; the outer band is invalidation.
   signal.suggested_target=middle;
   signal.suggested_stop=(decision==SRP_DECISION_BUY
                          ? snapshot.close-(has_atr ? atr : penetration)
                          : snapshot.close+(has_atr ? atr : penetration));
   return(true);
  }

#endif // SRP_DECISION_STRATEGIES_CSMCSTRATEGIES_MQH
//+------------------------------------------------------------------+
