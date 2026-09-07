//+------------------------------------------------------------------+
//|                                          CTrendStrategies.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   Five trend- and momentum-based plugins:                             |
//|     CEmaCrossStrategy          fast/slow EMA cross with trend filter   |
//|     CMomentumScalpPlugin       RSI thrust + MACD agreement             |
//|     CTrendContinuationStrategy pullback entry inside an established     |
//|                               trend                                  |
//|     CBreakoutStrategyPlugin    swing-level break with volume            |
//|     COpeningRangeBreakout      session opening range break              |
//|                                                                  |
//|   Each implements ONLY OnEvaluate. Guards, confidence flooring and     |
//|   signal stamping live in CStrategyPlugin.                            |
//|                                                                  |
//|   CONFIDENCE IS BLENDED FROM INDEPENDENT EVIDENCE in every plugin, so  |
//|   a single strong snapshot cannot manufacture certainty on its own. Each  |
//|   component is normalised 0..1 before averaging, which is what makes   |
//|   scores comparable between plugins and therefore votable.            |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_STRATEGIES_CTRENDSTRATEGIES_MQH
#define SRP_DECISION_STRATEGIES_CTRENDSTRATEGIES_MQH

#include "CStrategyPlugin.mqh"
//--- CSessionManager supplies SessionToString for the trade reason text.
#include "../Session/CSessionManager.mqh"

//+------------------------------------------------------------------+
//| EMA CROSS                                                         |
//|                                                                  |
//| Enters when the fast EMA crosses the slow EMA, filtered by a longer   |
//| trend EMA. The trend filter matters: an unfiltered MA cross is one of |
//| the worst-performing signals in existence because it fires constantly |
//| in range-bound conditions.                                           |
//+------------------------------------------------------------------+
class CEmaCrossStrategy : public CStrategyPlugin
  {
private:
   bool              m_require_trend_agreement;
   double            m_min_separation_atr;   // cross must be decisive

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     CEmaCrossStrategy(CStrategyContext *context,ILogger *logger)
     : CStrategyPlugin("EmaCross",SRP_STRAT_EMA_CROSS,context,logger),
       m_require_trend_agreement(true),
       m_min_separation_atr(0.10) { }

   void              SetRequireTrendAgreement(const bool require_agreement)
     { m_require_trend_agreement=require_agreement; }
   void              SetMinSeparation(const double atr_fraction)
     { if(atr_fraction>=0.0) m_min_separation_atr=atr_fraction; }
  };
//+------------------------------------------------------------------+
bool CEmaCrossStrategy::OnValidate(SValidationResult &result)
  {
   if(m_context.EmaFast()==NULL || m_context.EmaSlow()==NULL)
     {
      result.AddError(m_name+": requires fast and slow EMA");
      return(false);
     }
   if(m_require_trend_agreement && m_context.EmaTrend()==NULL)
      result.AddWarning(m_name+": trend agreement requested but no trend EMA "
                        "wired; filter will be skipped");
   return(true);
  }
//+------------------------------------------------------------------+
bool CEmaCrossStrategy::OnEvaluate(const SDecisionInput &snapshot,
                                   SStrategySignal &signal)
  {
   CEmaIndicator *fast=m_context.EmaFast();
   CEmaIndicator *slow=m_context.EmaSlow();
   if(fast==NULL || slow==NULL || !fast.IsReady() || !slow.IsReady())
      return(false);

   //--- Read current and previous values: a cross is a two-bar event.
   double fast_now=0.0,fast_prev=0.0,slow_now=0.0,slow_prev=0.0;
   if(!fast.ValueAt(0,0,fast_now) || !fast.ValueAt(0,1,fast_prev))
      return(false);
   if(!slow.ValueAt(0,0,slow_now) || !slow.ValueAt(0,1,slow_prev))
      return(false);

   const bool crossed_up=(fast_prev<=slow_prev && fast_now>slow_now);
   const bool crossed_down=(fast_prev>=slow_prev && fast_now<slow_now);
   if(!crossed_up && !crossed_down)
      return(false);

   //--- SEPARATION TEST. A cross where the averages are effectively
   //--- touching is noise; requiring ATR-scaled separation filters the
   //--- chop that destroys MA-cross systems.
   double atr=0.0;
   const bool has_atr=m_context.AtrValue(atr);
   const double separation=MathAbs(fast_now-slow_now);
   if(has_atr && atr>0.0)
     {
      if(separation<atr*m_min_separation_atr)
         return(false);
     }

   const ENUM_SRP_DECISION decision=(crossed_up ? SRP_DECISION_BUY
                                                : SRP_DECISION_SELL);

   //--- TREND FILTER. Rejects counter-trend crosses outright.
   double trend_value=0.0;
   bool trend_agrees=true;
   if(m_require_trend_agreement && m_context.EmaTrendValue(trend_value))
     {
      trend_agrees=(decision==SRP_DECISION_BUY ? snapshot.close>trend_value
                                               : snapshot.close<trend_value);
      if(!trend_agrees)
         return(false);
     }

   //--- CONFIDENCE from three independent components.
   double score=0.0;
   int components=0;

   //--- 1. Separation relative to ATR: a decisive cross scores higher.
   if(has_atr && atr>0.0)
     {
      score+=CMathUtils::Clamp(separation/(atr*0.5),0.0,1.0);
      components++;
     }
   //--- 2. Structural agreement.
   if(snapshot.structure_valid)
     {
      const bool structure_agrees=
         (decision==SRP_DECISION_BUY ? snapshot.structure.IsBullish()
                                     : snapshot.structure.IsBearish());
      score+=(structure_agrees ? 1.0 : 0.25);
      components++;
     }
   //--- 3. Session liquidity: the same cross is worth more in London.
   score+=snapshot.session.liquidity_score;
   components++;

   const double confidence=(components>0 ? score/(double)components : 0.0);
   const string reason=StringFormat(
      "EMA %s cross, separation %.1f pts%s",
      (crossed_up ? "bullish" : "bearish"),
      (snapshot.point>0.0 ? separation/snapshot.point : 0.0),
      (m_require_trend_agreement ? " with trend agreement" : ""));

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));
   return(true);
  }

//+------------------------------------------------------------------+
//| MOMENTUM SCALPING                                                 |
//|                                                                  |
//| RSI thrust confirmed by MACD histogram direction. Deliberately does  |
//| NOT use RSI overbought/oversold as a reversal trigger: in a genuine  |
//| momentum move RSI stays extended, and fading it is how momentum      |
//| systems bleed.                                                     |
//+------------------------------------------------------------------+
class CMomentumScalpPlugin : public CStrategyPlugin
  {
private:
   double            m_rsi_buy_threshold;
   double            m_rsi_sell_threshold;
   bool              m_require_macd_agreement;
   double            m_min_volume_ratio;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     CMomentumScalpPlugin(CStrategyContext *context,ILogger *logger)
     : CStrategyPlugin("MomentumScalp",SRP_STRAT_MOMENTUM_SCALP,context,logger),
       m_rsi_buy_threshold(55.0),
       m_rsi_sell_threshold(45.0),
       m_require_macd_agreement(true),
       m_min_volume_ratio(1.0) { }

   void              SetRsiThresholds(const double buy,const double sell)
     {
      if(buy>50.0)  m_rsi_buy_threshold=buy;
      if(sell<50.0) m_rsi_sell_threshold=sell;
     }
   void              SetRequireMacd(const bool require_macd)
     { m_require_macd_agreement=require_macd; }
   void              SetMinVolumeRatio(const double ratio)
     { if(ratio>=0.0) m_min_volume_ratio=ratio; }
  };
//+------------------------------------------------------------------+
bool CMomentumScalpPlugin::OnValidate(SValidationResult &result)
  {
   if(m_context.Rsi()==NULL)
     {
      result.AddError(m_name+": requires RSI");
      return(false);
     }
   if(m_require_macd_agreement && m_context.Macd()==NULL)
      result.AddWarning(m_name+": MACD agreement requested but none wired");
   return(true);
  }
//+------------------------------------------------------------------+
bool CMomentumScalpPlugin::OnEvaluate(const SDecisionInput &snapshot,
                                      SStrategySignal &signal)
  {
   double rsi=0.0;
   if(!m_context.RsiValue(rsi))
      return(false);

   //--- RSI must be extended in the direction of the intended trade, and
   //--- rising/falling with it.
   double rsi_prev=0.0;
   CRsiIntel *rsi_ind=m_context.Rsi();
   if(rsi_ind==NULL || !rsi_ind.ValueAt(0,1,rsi_prev))
      return(false);

   ENUM_SRP_DECISION decision=SRP_DECISION_NO_TRADE;
   if(rsi>=m_rsi_buy_threshold && rsi>rsi_prev)
      decision=SRP_DECISION_BUY;
   else if(rsi<=m_rsi_sell_threshold && rsi<rsi_prev)
      decision=SRP_DECISION_SELL;
   if(decision==SRP_DECISION_NO_TRADE)
      return(false);

   //--- MACD AGREEMENT. Two independent momentum measures agreeing is
   //--- materially stronger evidence than either alone.
   double histogram=0.0;
   const bool has_macd=m_context.MacdHistogram(histogram);
   if(m_require_macd_agreement)
     {
      if(!has_macd)
         return(false);
      const bool agrees=(decision==SRP_DECISION_BUY ? histogram>0.0
                                                    : histogram<0.0);
      if(!agrees)
         return(false);
     }

   //--- VOLUME GATE. Momentum without participation is a trap.
   double relative_volume=0.0;
   const bool has_volume=m_context.RelativeVolume(20,relative_volume);
   if(has_volume && m_min_volume_ratio>0.0 &&
      relative_volume<m_min_volume_ratio)
      return(false);

   //--- CONFIDENCE: RSI extension, MACD magnitude, volume, liquidity.
   double score=0.0;
   int components=0;

   //--- RSI distance beyond its threshold, saturating at 20 points past.
   const double rsi_extension=(decision==SRP_DECISION_BUY
                               ? rsi-m_rsi_buy_threshold
                               : m_rsi_sell_threshold-rsi);
   score+=CMathUtils::Clamp(rsi_extension/20.0,0.0,1.0);
   components++;

   if(has_macd)
     {
      //--- Normalise the histogram against ATR so the scale is
      //--- instrument-independent.
      double atr=0.0;
      if(m_context.AtrValue(atr) && atr>0.0)
        {
         score+=CMathUtils::Clamp(MathAbs(histogram)/(atr*0.3),0.0,1.0);
         components++;
        }
     }
   if(has_volume)
     {
      score+=CMathUtils::Clamp(relative_volume/2.0,0.0,1.0);
      components++;
     }
   score+=snapshot.session.liquidity_score;
   components++;

   const double confidence=(components>0 ? score/(double)components : 0.0);
   const string reason=StringFormat("momentum: RSI %.1f (%s)%s%s",
                                    rsi,
                                    (decision==SRP_DECISION_BUY ? "rising" : "falling"),
                                    (has_macd ? ", MACD agrees" : ""),
                                    (has_volume ? StringFormat(", vol x%.2f",
                                                               relative_volume) : ""));

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));
   return(true);
  }

//+------------------------------------------------------------------+
//| TREND CONTINUATION                                                |
//|                                                                  |
//| Enters on a pullback WITHIN an established trend, which is a very     |
//| different proposition from entering on a breakout. It requires the    |
//| structure engine to report a trend AND the pullback phase, so it      |
//| cannot fire in a range.                                              |
//+------------------------------------------------------------------+
class CTrendContinuationStrategy : public CStrategyPlugin
  {
private:
   double            m_min_adx;
   double            m_min_structure_score;
   bool              m_require_pullback_phase;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     CTrendContinuationStrategy(CStrategyContext *context,
                                                ILogger *logger)
     : CStrategyPlugin("TrendContinuation",SRP_STRAT_TREND_CONTINUATION,
                       context,logger),
       m_min_adx(22.0),
       m_min_structure_score(0.45),
       m_require_pullback_phase(true) { }

   void              SetMinAdx(const double value)
     { if(value>=0.0) m_min_adx=value; }
   void              SetMinStructureScore(const double score)
     { if(score>=0.0 && score<=1.0) m_min_structure_score=score; }
   void              SetRequirePullback(const bool require_pullback)
     { m_require_pullback_phase=require_pullback; }
  };
//+------------------------------------------------------------------+
bool CTrendContinuationStrategy::OnValidate(SValidationResult &result)
  {
   if(m_context.Structure()==NULL)
     {
      result.AddError(m_name+": requires the market structure engine");
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CTrendContinuationStrategy::OnEvaluate(const SDecisionInput &snapshot,
                                            SStrategySignal &signal)
  {
   if(!snapshot.structure_valid)
      return(false);
   //--- A trend must actually exist. This is the whole premise.
   if(!snapshot.structure.IsTrending())
      return(false);
   if(snapshot.structure.strength_score<m_min_structure_score)
      return(false);

   //--- PULLBACK PHASE. Entering mid-impulse is chasing; entering on the
   //--- retracement is the edge this plugin targets.
   if(m_require_pullback_phase &&
      snapshot.structure.phase!=SRP_PHASE_PULLBACK)
      return(false);

   //--- ADX confirms the trend has strength rather than merely direction.
   double adx=0.0;
   const bool has_adx=m_context.AdxValue(adx);
   if(has_adx && m_min_adx>0.0 && adx<m_min_adx)
      return(false);

   const ENUM_SRP_DECISION decision=(snapshot.structure.IsBullish()
                                     ? SRP_DECISION_BUY : SRP_DECISION_SELL);

   //--- DISCOUNT/PREMIUM AGREEMENT. Buying a pullback in the discount half
   //--- of the range is materially better value than buying in premium.
   double location_score=0.5;
   if(snapshot.structure.range.valid)
     {
      const double position=snapshot.structure.range.current_position;
      location_score=(decision==SRP_DECISION_BUY ? (1.0-position) : position);
     }

   //--- CONFIDENCE: structure score, ADX, location, liquidity.
   double score=snapshot.structure.strength_score;
   int components=1;
   if(has_adx)
     {
      score+=CMathUtils::Clamp(adx/50.0,0.0,1.0);
      components++;
     }
   score+=location_score;
   components++;
   score+=snapshot.session.liquidity_score;
   components++;

   const double confidence=score/(double)components;
   const string reason=StringFormat(
      "trend continuation: %s %s pullback, score %.2f%s",
      CMarketStructure::DirectionToString(snapshot.structure.direction),
      CMarketStructure::GradeToString(snapshot.structure.grade),
      snapshot.structure.strength_score,
      (has_adx ? StringFormat(", ADX %.1f",adx) : ""));

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));

   //--- Structure supplies a natural invalidation point, so the plugin
   //--- offers it as a hint rather than leaving the stop to a generic
   //--- calculator that cannot see the swing.
   if(decision==SRP_DECISION_BUY && snapshot.structure.last_low.valid)
      signal.suggested_stop=snapshot.structure.last_low.price;
   else if(decision==SRP_DECISION_SELL && snapshot.structure.last_high.valid)
      signal.suggested_stop=snapshot.structure.last_high.price;
   return(true);
  }

//+------------------------------------------------------------------+
//| BREAKOUT                                                          |
//|                                                                  |
//| Trades a decisive break of the most recent confirmed swing level,     |
//| requiring an ATR-scaled margin and volume expansion. The margin       |
//| scales with volatility because a fixed point buffer is either noise   |
//| in a fast market or unreachable in a quiet one.                       |
//+------------------------------------------------------------------+
class CBreakoutStrategyPlugin : public CStrategyPlugin
  {
private:
   double            m_margin_atr;
   double            m_min_volume_ratio;
   bool              m_require_displacement;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     CBreakoutStrategyPlugin(CStrategyContext *context,
                                             ILogger *logger)
     : CStrategyPlugin("Breakout",SRP_STRAT_BREAKOUT,context,logger),
       m_margin_atr(0.25),
       m_min_volume_ratio(1.2),
       m_require_displacement(false) { }

   void              SetMarginAtr(const double atr_fraction)
     { if(atr_fraction>=0.0) m_margin_atr=atr_fraction; }
   void              SetMinVolumeRatio(const double ratio)
     { if(ratio>=0.0) m_min_volume_ratio=ratio; }
   void              SetRequireDisplacement(const bool require_displacement)
     { m_require_displacement=require_displacement; }
  };
//+------------------------------------------------------------------+
bool CBreakoutStrategyPlugin::OnValidate(SValidationResult &result)
  {
   if(m_context.Swings()==NULL)
     {
      result.AddError(m_name+": requires the swing detector");
      return(false);
     }
   if(m_context.Atr()==NULL)
      result.AddWarning(m_name+": no ATR wired; break margin will be zero");
   return(true);
  }
//+------------------------------------------------------------------+
bool CBreakoutStrategyPlugin::OnEvaluate(const SDecisionInput &snapshot,
                                         SStrategySignal &signal)
  {
   CSwingDetector *swings=m_context.Swings();
   if(swings==NULL || !swings.IsValid())
      return(false);

   SSwingPoint last_high,last_low;
   const bool has_high=swings.LastHigh(last_high);
   const bool has_low=swings.LastLow(last_low);
   if(!has_high && !has_low)
      return(false);

   double atr=0.0;
   const bool has_atr=m_context.AtrValue(atr);
   const double margin=(has_atr ? atr*m_margin_atr : 0.0);

   ENUM_SRP_DECISION decision=SRP_DECISION_NO_TRADE;
   double broken_level=0.0;
   double breach=0.0;

   //--- Break must exceed the level by the volatility-scaled margin.
   if(has_high && last_high.valid && snapshot.close>last_high.price+margin)
     {
      decision=SRP_DECISION_BUY;
      broken_level=last_high.price;
      breach=snapshot.close-last_high.price;
     }
   else if(has_low && last_low.valid && snapshot.close<last_low.price-margin)
     {
      decision=SRP_DECISION_SELL;
      broken_level=last_low.price;
      breach=last_low.price-snapshot.close;
     }
   if(decision==SRP_DECISION_NO_TRADE)
      return(false);

   //--- VOLUME EXPANSION. A break on thin volume is the classic false
   //--- break, so this gate is on by default.
   double relative_volume=0.0;
   const bool has_volume=m_context.RelativeVolume(20,relative_volume);
   if(has_volume && m_min_volume_ratio>0.0 &&
      relative_volume<m_min_volume_ratio)
      return(false);

   //--- Optional displacement confirmation.
   if(m_require_displacement)
     {
      CDisplacementDetector *displacement=m_context.Displacement();
      if(displacement==NULL)
         return(false);
      const ENUM_SRP_BIAS wanted=(decision==SRP_DECISION_BUY
                                  ? SRP_BIAS_BULLISH : SRP_BIAS_BEARISH);
      if(!displacement.IsDisplacement(1,wanted))
         return(false);
     }

   //--- CONFIDENCE: breach size, volume, structural agreement, liquidity.
   double score=0.0;
   int components=0;
   if(has_atr && atr>0.0)
     {
      score+=CMathUtils::Clamp(breach/atr,0.0,1.0);
      components++;
     }
   if(has_volume)
     {
      score+=CMathUtils::Clamp(relative_volume/2.0,0.0,1.0);
      components++;
     }
   if(snapshot.structure_valid)
     {
      //--- A break agreeing with structure, or a fresh BOS, is stronger.
      const bool agrees=
         (decision==SRP_DECISION_BUY
          ? (snapshot.structure.IsBullish() ||
             snapshot.structure.last_event==SRP_STRUCT_BOS_BULLISH)
          : (snapshot.structure.IsBearish() ||
             snapshot.structure.last_event==SRP_STRUCT_BOS_BEARISH));
      score+=(agrees ? 1.0 : 0.3);
      components++;
     }
   score+=snapshot.session.liquidity_score;
   components++;

   const double confidence=(components>0 ? score/(double)components : 0.0);
   const string reason=StringFormat(
      "breakout: %s through %.*f by %.1f pts%s",
      (decision==SRP_DECISION_BUY ? "up" : "down"),
      snapshot.digits,broken_level,
      (snapshot.point>0.0 ? breach/snapshot.point : 0.0),
      (has_volume ? StringFormat(", vol x%.2f",relative_volume) : ""));

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));
   //--- The broken level is the natural invalidation point.
   signal.suggested_stop=broken_level;
   return(true);
  }

//+------------------------------------------------------------------+
//| OPENING RANGE BREAKOUT                                            |
//|                                                                  |
//| Builds a high/low range over the first N minutes of a session, then   |
//| trades a break of it. Only active for a limited window after the      |
//| range completes: an "opening range" break six hours later is not an   |
//| opening range break, and treating it as one is a common error.        |
//+------------------------------------------------------------------+
class COpeningRangeBreakout : public CStrategyPlugin
  {
private:
   int               m_range_minutes;
   int               m_valid_for_minutes;
   double            m_margin_atr;
   double            m_min_range_atr;      // reject a meaninglessly tight range
   //--- Cached range, rebuilt once per session.
   bool              m_range_built;
   double            m_range_high;
   double            m_range_low;
   datetime          m_range_session_start;
   ENUM_SRP_TRADING_SESSION m_range_session;

   bool              BuildRange(const SDecisionInput &snapshot);

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     COpeningRangeBreakout(CStrategyContext *context,
                                           ILogger *logger)
     : CStrategyPlugin("OpeningRangeBreakout",
                       SRP_STRAT_OPENING_RANGE_BREAKOUT,context,logger),
       m_range_minutes(30),
       m_valid_for_minutes(180),
       m_margin_atr(0.15),
       m_min_range_atr(0.5),
       m_range_built(false),
       m_range_high(0.0),
       m_range_low(0.0),
       m_range_session_start(0),
       m_range_session(SRP_TS_NONE) { }

   void              SetRangeMinutes(const int minutes)
     { if(minutes>=5) m_range_minutes=minutes; }
   void              SetValidForMinutes(const int minutes)
     { if(minutes>=10) m_valid_for_minutes=minutes; }
   void              SetMarginAtr(const double atr_fraction)
     { if(atr_fraction>=0.0) m_margin_atr=atr_fraction; }
   void              SetMinRangeAtr(const double atr_multiple)
     { if(atr_multiple>=0.0) m_min_range_atr=atr_multiple; }

   void              GetRange(double &high,double &low,bool &built) const
     { high=m_range_high; low=m_range_low; built=m_range_built; }
  };
//+------------------------------------------------------------------+
bool COpeningRangeBreakout::OnValidate(SValidationResult &result)
  {
   if(m_valid_for_minutes<=m_range_minutes)
     {
      result.AddError(m_name+": validity window must exceed the range window");
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool COpeningRangeBreakout::BuildRange(const SDecisionInput &snapshot)
  {
   //--- The range spans the first m_range_minutes of the current session.
   //--- Rebuilt only when the session changes, so this is cheap.
   const int bars_needed=m_range_minutes;
   if(bars_needed<1)
      return(false);

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   //--- Offset back to where the session began, then take the range bars.
   const int offset=snapshot.session.minutes_into_session-m_range_minutes;
   if(offset<0)
      return(false);                      // range still forming

   if(CopyRates(snapshot.symbol,PERIOD_M1,offset,bars_needed,rates)!=bars_needed)
      return(false);

   double high=rates[0].high;
   double low=rates[0].low;
   for(int i=1;i<bars_needed;i++)
     {
      if(rates[i].high>high) high=rates[i].high;
      if(rates[i].low<low)   low=rates[i].low;
     }
   if(high<=low)
      return(false);

   m_range_high=high;
   m_range_low=low;
   m_range_built=true;
   m_range_session=snapshot.session.active_session;
   m_range_session_start=snapshot.server_time;
   return(true);
  }
//+------------------------------------------------------------------+
bool COpeningRangeBreakout::OnEvaluate(const SDecisionInput &snapshot,
                                       SStrategySignal &signal)
  {
   if(snapshot.session.active_session==SRP_TS_NONE)
      return(false);

   //--- Rebuild when the session changes.
   if(!m_range_built || m_range_session!=snapshot.session.active_session)
     {
      m_range_built=false;
      if(!BuildRange(snapshot))
         return(false);
     }

   //--- VALIDITY WINDOW. The premise expires; a break hours later is a
   //--- different setup entirely.
   if(snapshot.session.minutes_into_session>m_valid_for_minutes)
      return(false);
   //--- And the range must be complete.
   if(snapshot.session.minutes_into_session<m_range_minutes)
      return(false);

   double atr=0.0;
   const bool has_atr=m_context.AtrValue(atr);

   //--- MINIMUM RANGE SIZE. A range narrower than ATR is noise, and
   //--- breaking it means nothing.
   const double range_height=m_range_high-m_range_low;
   if(has_atr && atr>0.0 && m_min_range_atr>0.0)
     {
      if(range_height<atr*m_min_range_atr)
         return(false);
     }

   const double margin=(has_atr ? atr*m_margin_atr : 0.0);

   ENUM_SRP_DECISION decision=SRP_DECISION_NO_TRADE;
   double level=0.0;
   double breach=0.0;
   if(snapshot.close>m_range_high+margin)
     {
      decision=SRP_DECISION_BUY;
      level=m_range_high;
      breach=snapshot.close-m_range_high;
     }
   else if(snapshot.close<m_range_low-margin)
     {
      decision=SRP_DECISION_SELL;
      level=m_range_low;
      breach=m_range_low-snapshot.close;
     }
   if(decision==SRP_DECISION_NO_TRADE)
      return(false);

   //--- CONFIDENCE: breach size, range quality, volume, liquidity.
   double score=0.0;
   int components=0;
   if(has_atr && atr>0.0)
     {
      score+=CMathUtils::Clamp(breach/atr,0.0,1.0);
      components++;
      //--- A well-formed range (1-3 ATR) is a better base than an
      //--- extremely wide or narrow one.
      const double range_atr=range_height/atr;
      score+=CMathUtils::Clamp(range_atr/3.0,0.0,1.0);
      components++;
     }
   double relative_volume=0.0;
   if(m_context.RelativeVolume(20,relative_volume))
     {
      score+=CMathUtils::Clamp(relative_volume/2.0,0.0,1.0);
      components++;
     }
   score+=snapshot.session.liquidity_score;
   components++;

   const double confidence=(components>0 ? score/(double)components : 0.0);
   const string reason=StringFormat(
      "opening range %s break: %s session range %.*f-%.*f, breach %.1f pts",
      (decision==SRP_DECISION_BUY ? "high" : "low"),
      CSessionManager::SessionToString(snapshot.session.active_session),
      snapshot.digits,m_range_low,snapshot.digits,m_range_high,
      (snapshot.point>0.0 ? breach/snapshot.point : 0.0));

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));
   //--- The opposite side of the range is the natural invalidation.
   signal.suggested_stop=(decision==SRP_DECISION_BUY ? m_range_low
                                                     : m_range_high);
   return(true);
  }

#endif // SRP_DECISION_STRATEGIES_CTRENDSTRATEGIES_MQH
//+------------------------------------------------------------------+
