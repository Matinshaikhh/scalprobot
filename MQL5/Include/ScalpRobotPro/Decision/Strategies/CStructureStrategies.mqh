//+------------------------------------------------------------------+
//|                                      CStructureStrategies.mqh |
//|                Scalping Robot Pro - Phase 6 strategy plugins |
//|                                                                  |
//|   The two strategies Part 8 requires that Phases 1-5 never built:      |
//|                                                                  |
//|     CBreakOfStructureStrategy - trades the CONFIRMED break of a swing  |
//|                                 that changes market structure         |
//|     CVolatilityBreakoutStrategy - trades expansion out of a measured   |
//|                                 contraction (squeeze release)         |
//|                                                                  |
//|   WHY THESE ARE GENUINELY NEW, not renames.                           |
//|                                                                  |
//|   The audit found `CBreakoutStrategyPlugin` already existed, and it     |
//|   trades a swing-level break with an ATR margin. That is a PRICE-LEVEL  |
//|   breakout. It is not the same premise as either strategy here:        |
//|                                                                  |
//|     * Break of Structure asks whether the market's STRUCTURAL          |
//|       character has changed - a higher high in a downtrend sequence,   |
//|       confirmed by a close beyond it. The level matters less than what |
//|       breaking it implies about who is in control.                     |
//|                                                                  |
//|     * Volatility Breakout asks whether RANGE is expanding out of       |
//|       compression, independent of any particular level. A squeeze can  |
//|       release without touching a swing high at all.                    |
//|                                                                  |
//|   Both read the shared snapshot and the borrowed context. Neither      |
//|   sizes a position, sends an order, or touches the terminal for prices |
//|   - doing so would read a different instant than every other module in |
//|   the same pass.                                                     |
//|                                                                  |
//|   LOOK-AHEAD DISCIPLINE (Part 10). Every bar read below starts at      |
//|   shift 1, the last CLOSED bar. The base class already refuses to      |
//|   evaluate mid-bar unless a plugin opts out, and neither of these does.|
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_STRATEGIES_CSTRUCTURESTRATEGIES_MQH
#define SRP_DECISION_STRATEGIES_CSTRUCTURESTRATEGIES_MQH

#include "CStrategyPlugin.mqh"

//+------------------------------------------------------------------+
//| BREAK OF STRUCTURE.                                                |
//|                                                                  |
//| Premise: a swing point breaking in the direction of the prevailing    |
//| structure CONTINUES it (BOS); one breaking against it CHANGES it       |
//| (CHoCH). Both are tradeable, and they are not the same trade.          |
//|                                                                  |
//| WHAT MAKES THIS DIFFERENT FROM A PRICE BREAKOUT: the entry requires    |
//| the structure engine to have registered the event, which means the      |
//| swing sequence itself was re-labelled. A wick through a level that      |
//| does not change the sequence is not a break of structure, and this      |
//| plugin will not trade it.                                            |
//|                                                                  |
//| CONFIRMATION REQUIRED: a CLOSE beyond the level, not a touch. Wicks    |
//| through swing highs are how liquidity is taken before a reversal, so   |
//| trading the touch is trading the trap.                               |
//+------------------------------------------------------------------+
class CBreakOfStructureStrategy : public CStrategyPlugin
  {
private:
   //--- Minimum bars since the event, so a stale break is not re-traded.
   int               m_max_event_age_bars;
   //--- A break must clear the level by this multiple of ATR, otherwise
   //--- ordinary noise around a level reads as a break.
   double            m_confirm_atr_multiple;
   //--- CHoCH is a reversal and carries more risk than a continuation
   //--- BOS. Both are permitted; they are scored differently.
   bool              m_trade_choch;
   bool              m_trade_bos;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;

public:
                     CBreakOfStructureStrategy(CStrategyContext *context,
                                               ILogger *logger)
     : CStrategyPlugin("BreakOfStructure",SRP_STRAT_BREAK_OF_STRUCTURE,
                       context,logger),
       m_max_event_age_bars(3),
       m_confirm_atr_multiple(0.25),
       m_trade_choch(true),
       m_trade_bos(true) { }

   void              SetMaxEventAge(const int bars)
     { if(bars>=1) m_max_event_age_bars=bars; }
   void              SetConfirmMultiple(const double multiple)
     { if(multiple>=0.0) m_confirm_atr_multiple=multiple; }
   void              SetEventTypes(const bool trade_bos,const bool trade_choch)
     { m_trade_bos=trade_bos; m_trade_choch=trade_choch; }
  };

//+------------------------------------------------------------------+
bool CBreakOfStructureStrategy::OnEvaluate(const SDecisionInput &snapshot,
                                          SStrategySignal &signal)
  {
   //--- Structure is the entire premise. Without it there is no opinion
   //--- to offer, and guessing would be worse than abstaining.
   if(!snapshot.structure_valid)
     {
      Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
           "market structure unavailable",SRP_RISK_RATING_NONE);
      return(false);
     }

   const ENUM_SRP_STRUCTURE_EVENT event=snapshot.structure.last_event;
   if(event==SRP_STRUCT_NONE)
     {
      Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
           "no structural break registered",SRP_RISK_RATING_NONE);
      return(false);
     }

   const bool is_choch=(event==SRP_STRUCT_CHOCH_BULLISH ||
                        event==SRP_STRUCT_CHOCH_BEARISH);
   const bool is_bos  =(event==SRP_STRUCT_BOS_BULLISH ||
                        event==SRP_STRUCT_BOS_BEARISH);

   if(is_choch && !m_trade_choch)
     {
      Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
           "CHoCH trading disabled",SRP_RISK_RATING_NONE);
      return(false);
     }
   if(is_bos && !m_trade_bos)
     {
      Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
           "BOS trading disabled",SRP_RISK_RATING_NONE);
      return(false);
     }

   const bool bullish=(event==SRP_STRUCT_BOS_BULLISH ||
                       event==SRP_STRUCT_CHOCH_BULLISH);

   //--- STALENESS. An event from twenty bars ago has already been priced
   //--- in; entering now is chasing.
   //---
   //--- Age is derived from last_event_time rather than a bar counter,
   //--- because the structure state records WHEN the event happened, not
   //--- how long ago. Converting through the timeframe's period keeps the
   //--- comparison in bars, which is what the threshold means.
   const int seconds_per_bar=PeriodSeconds(snapshot.timeframe);
   int age=0;
   if(snapshot.structure.last_event_time>0 && seconds_per_bar>0)
      age=(int)((snapshot.server_time-snapshot.structure.last_event_time)/
                seconds_per_bar);
   if(age<0)
      age=0;
   if(age>m_max_event_age_bars)
     {
      Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
           StringFormat("structural break is %d bars old, beyond the %d-bar "
                        "window",age,m_max_event_age_bars),
           SRP_RISK_RATING_NONE);
      return(false);
     }

   //--- CONFIRMATION: the last CLOSED bar must have closed BEYOND the
   //--- broken level by a margin scaled to volatility. A wick through is
   //--- how stops are taken before a move the other way.
   double atr=0.0;
   if(m_context.Atr()!=NULL)
      m_context.Atr().ValueAt(0,1,atr);
   const double margin=(atr>0.0 ? atr*m_confirm_atr_multiple : 0.0);

   //--- THE BROKEN LEVEL. A bullish break clears the prior HIGH; a
   //--- bearish one clears the prior LOW. Those are the swing points the
   //--- structure engine itself re-labelled, so using them keeps this
   //--- strategy consistent with the engine's own definition of a break
   //--- rather than inventing a second one.
   double level=0.0;
   if(bullish)
     {
      if(snapshot.structure.prior_high.valid)
         level=snapshot.structure.prior_high.price;
      else
         if(snapshot.structure.last_high.valid)
            level=snapshot.structure.last_high.price;
     }
   else
     {
      if(snapshot.structure.prior_low.valid)
         level=snapshot.structure.prior_low.price;
      else
         if(snapshot.structure.last_low.valid)
            level=snapshot.structure.last_low.price;
     }

   if(level>0.0)
     {
      //--- prev_close is the last closed bar's close.
      if(bullish && snapshot.prev_close<=level+margin)
        {
         Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
              StringFormat("bullish break unconfirmed: close %.*f has not "
                           "cleared %.*f by %.*f",
                           snapshot.digits,snapshot.prev_close,
                           snapshot.digits,level,snapshot.digits,margin),
              SRP_RISK_RATING_NONE);
         return(false);
        }
      if(!bullish && snapshot.prev_close>=level-margin)
        {
         Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
              StringFormat("bearish break unconfirmed: close %.*f has not "
                           "cleared %.*f by %.*f",
                           snapshot.digits,snapshot.prev_close,
                           snapshot.digits,level,snapshot.digits,margin),
              SRP_RISK_RATING_NONE);
         return(false);
        }
     }

   //--- CONFIDENCE. Built from independent evidence rather than a
   //--- constant, so a marginal break scores below a decisive one.
   double confidence=0.50;
   string why="";

   //--- 1. A continuation break in an already-graded trend is the
   //--- highest-quality version of this setup.
   if(is_bos)
     {
      confidence+=0.10;
      why="BOS";
      if(snapshot.structure.grade==SRP_TREND_GRADE_STRONG)
        {
         confidence+=0.10;
         why+=" in a strong trend";
        }
      else
         if(snapshot.structure.grade==SRP_TREND_GRADE_EXHAUSTED)
           {
            //--- A break in an exhausted trend is where continuation
            //--- setups fail, so it is penalised rather than rewarded.
            confidence-=0.15;
            why+=" but the trend is exhausted";
           }
     }
   else
     {
      why="CHoCH";
      //--- A character change is higher variance by nature. It earns its
      //--- confidence from the freshness and decisiveness of the break.
      confidence+=0.05;
     }

   //--- 2. Direction must agree with the structure's own read.
   const bool structure_agrees=
      (bullish  && snapshot.structure.direction==SRP_TREND_DIR_BULLISH) ||
      (!bullish && snapshot.structure.direction==SRP_TREND_DIR_BEARISH);
   if(structure_agrees)
     {
      confidence+=0.10;
      why+=", structure agrees";
     }

   //--- 3. Freshness. The bar of the break is the best entry.
   if(age<=1)
     {
      confidence+=0.10;
      why+=", fresh";
     }

   //--- 4. Decisiveness: how far beyond the level price actually closed,
   //--- measured in ATR so it is comparable across instruments.
   if(atr>0.0 && level>0.0)
     {
      const double clearance=MathAbs(snapshot.prev_close-level)/atr;
      if(clearance>=0.5)
        {
         confidence+=0.08;
         why+=StringFormat(", closed %.2f ATR beyond",clearance);
        }
     }

   //--- 5. Structural strength score, already computed by Phase 2.
   if(snapshot.structure.strength_score>=0.6)
     {
      confidence+=0.05;
      why+=", strong structure";
     }

   confidence=CMathUtils::Clamp(confidence,0.0,1.0);

   const string reason=StringFormat(
      "%s %s break of %.*f (%s), %d bar(s) ago",
      (bullish ? "bullish" : "bearish"),
      (is_choch ? "character-change" : "continuation"),
      snapshot.digits,level,why,age);

   Emit(signal,snapshot,
        (bullish ? SRP_DECISION_BUY : SRP_DECISION_SELL),
        confidence,reason,RatingFromConfidence(confidence));

   //--- Stop hint: beyond the broken level, which is where the premise
   //--- is invalidated. The risk layer may widen it but not ignore it.
   if(level>0.0 && atr>0.0)
      signal.suggested_stop=(bullish ? level-atr*0.5 : level+atr*0.5);
   return(true);
  }

//+------------------------------------------------------------------+
//| VOLATILITY BREAKOUT (squeeze release).                             |
//|                                                                  |
//| Premise: range CONTRACTION precedes range EXPANSION. When realised     |
//| range has been compressing and then expands decisively, the move       |
//| tends to continue in the direction of the expansion.                  |
//|                                                                  |
//| WHAT MAKES THIS DIFFERENT FROM A PRICE BREAKOUT: no level is           |
//| involved. The signal is the CHANGE IN RANGE itself. A squeeze can      |
//| release in the middle of a range, nowhere near a swing high, and this  |
//| plugin will trade that while a level-based breakout sees nothing.      |
//|                                                                  |
//| THE MEASUREMENT, and why it is done this way:                          |
//|   compression = average true range over the recent window, divided by  |
//|                 the average over a longer baseline window             |
//|   expansion   = the last closed bar's range divided by the recent      |
//|                 average                                              |
//| Compression BELOW 1 means the market has been quieter than its own     |
//| baseline. Expansion ABOVE the threshold means that has just ended.     |
//| Requiring both is what distinguishes a release from ordinary noise in  |
//| an already-volatile market.                                          |
//|                                                                  |
//| ALL BARS READ FROM SHIFT 1. Using the forming bar would make the       |
//| expansion ratio grow within the bar and repaint the signal.            |
//+------------------------------------------------------------------+
class CVolatilityBreakoutStrategy : public CStrategyPlugin
  {
private:
   int               m_squeeze_bars;        // recent window
   int               m_baseline_bars;       // longer comparison window
   double            m_max_compression;     // must be quieter than this
   double            m_min_expansion;       // release threshold
   //--- The breakout bar must close in the top/bottom fraction of its own
   //--- range, or the expansion had no directional conviction.
   double            m_min_close_position;

   bool              MeasureRanges(const SDecisionInput &snapshot,
                                   double &recent_average,
                                   double &baseline_average,
                                   double &last_range) const;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;

public:
                     CVolatilityBreakoutStrategy(CStrategyContext *context,
                                                 ILogger *logger)
     : CStrategyPlugin("VolatilityBreakout",SRP_STRAT_VOLATILITY_BREAKOUT,
                       context,logger),
       m_squeeze_bars(6),
       m_baseline_bars(24),
       m_max_compression(0.85),
       m_min_expansion(1.60),
       m_min_close_position(0.65) { }

   void              SetWindows(const int squeeze_bars,const int baseline_bars)
     {
      if(squeeze_bars>=2) m_squeeze_bars=squeeze_bars;
      if(baseline_bars>squeeze_bars) m_baseline_bars=baseline_bars;
     }
   void              SetCompression(const double max_compression)
     { if(max_compression>0.0) m_max_compression=max_compression; }
   void              SetExpansion(const double min_expansion)
     { if(min_expansion>1.0) m_min_expansion=min_expansion; }
   void              SetMinClosePosition(const double fraction)
     { if(fraction>0.5 && fraction<=1.0) m_min_close_position=fraction; }
  };

//+------------------------------------------------------------------+
//| Reads true ranges from CLOSED bars only.                            |
//|                                                                  |
//| True range, not high-low: a gap between bars is real range and         |
//| ignoring it understates volatility exactly when it matters most.       |
//+------------------------------------------------------------------+
bool CVolatilityBreakoutStrategy::MeasureRanges(const SDecisionInput &snapshot,
                                               double &recent_average,
                                               double &baseline_average,
                                               double &last_range) const
  {
   recent_average=0.0; baseline_average=0.0; last_range=0.0;

   const int need=m_baseline_bars+2;
   double highs[],lows[],closes[];
   //--- start_pos 1 == last CLOSED bar. Never 0.
   if(CopyHigh(snapshot.symbol,snapshot.timeframe,1,need,highs)!=need)
      return(false);
   if(CopyLow(snapshot.symbol,snapshot.timeframe,1,need,lows)!=need)
      return(false);
   if(CopyClose(snapshot.symbol,snapshot.timeframe,1,need,closes)!=need)
      return(false);

   //--- CopyHigh returns oldest-first, so the newest closed bar is last.
   const int newest=need-1;

   double recent_sum=0.0,baseline_sum=0.0;
   int recent_count=0,baseline_count=0;

   for(int back=0;back<m_baseline_bars;back++)
     {
      const int i=newest-back;
      if(i<1)
         break;
      //--- True range includes the gap from the previous close.
      const double prev_close=closes[i-1];
      const double tr=MathMax(highs[i]-lows[i],
                              MathMax(MathAbs(highs[i]-prev_close),
                                      MathAbs(lows[i]-prev_close)));
      if(tr<=0.0)
         continue;
      baseline_sum+=tr;
      baseline_count++;
      //--- The most recent bars, excluding the breakout bar itself: the
      //--- squeeze must be measured BEFORE the release, or the release
      //--- inflates the very average it is being compared against.
      if(back>=1 && back<=m_squeeze_bars)
        {
         recent_sum+=tr;
         recent_count++;
        }
      if(back==0)
         last_range=tr;
     }

   if(recent_count<2 || baseline_count<m_squeeze_bars+2 || last_range<=0.0)
      return(false);

   recent_average=recent_sum/(double)recent_count;
   baseline_average=baseline_sum/(double)baseline_count;
   return(recent_average>0.0 && baseline_average>0.0);
  }
//+------------------------------------------------------------------+
bool CVolatilityBreakoutStrategy::OnEvaluate(const SDecisionInput &snapshot,
                                            SStrategySignal &signal)
  {
   double recent=0.0,baseline=0.0,last_range=0.0;
   if(!MeasureRanges(snapshot,recent,baseline,last_range))
     {
      Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
           "insufficient closed-bar history to measure range expansion",
           SRP_RISK_RATING_NONE);
      return(false);
     }

   //--- 1. WAS there a squeeze? Recent range below its own baseline.
   const double compression=recent/baseline;
   if(compression>m_max_compression)
     {
      Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
           StringFormat("no squeeze: recent range is %.2f of baseline, "
                        "needs <= %.2f",compression,m_max_compression),
           SRP_RISK_RATING_NONE);
      return(false);
     }

   //--- 2. Has it RELEASED? The breakout bar's range against the squeeze.
   const double expansion=last_range/recent;
   if(expansion<m_min_expansion)
     {
      Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
           StringFormat("squeeze intact but no release: expansion %.2fx, "
                        "needs >= %.2fx",expansion,m_min_expansion),
           SRP_RISK_RATING_NONE);
      return(false);
     }

   //--- 3. DIRECTION. Where the breakout bar closed inside its own range.
   //--- An expansion bar closing mid-range is indecision, not a breakout.
   const double bar_range=snapshot.prev_high-snapshot.prev_low;
   if(bar_range<=0.0)
     {
      Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
           "breakout bar has no range",SRP_RISK_RATING_NONE);
      return(false);
     }
   const double close_position=(snapshot.prev_close-snapshot.prev_low)/bar_range;

   const bool bullish=(close_position>=m_min_close_position);
   const bool bearish=(close_position<=(1.0-m_min_close_position));
   if(!bullish && !bearish)
     {
      Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
           StringFormat("expansion %.2fx but the bar closed mid-range "
                        "(%.2f), no directional conviction",
                        expansion,close_position),
           SRP_RISK_RATING_NONE);
      return(false);
     }

   //--- CONFIDENCE from the strength of each independent condition.
   double confidence=0.50;
   string why=StringFormat("squeeze %.2f, release %.2fx",
                           compression,expansion);

   //--- Tighter squeezes release harder.
   if(compression<=0.70)
     {
      confidence+=0.08;
      why+=", tight squeeze";
     }
   //--- A larger release is more convincing, to a point.
   if(expansion>=2.20)
     {
      confidence+=0.10;
      why+=", strong release";
     }
   else
      if(expansion>=1.90)
         confidence+=0.05;

   //--- A decisive close near the extreme.
   const double conviction=(bullish ? close_position : 1.0-close_position);
   if(conviction>=0.85)
     {
      confidence+=0.08;
      why+=", decisive close";
     }

   //--- Agreement with structural direction, when structure is available.
   if(snapshot.structure_valid)
     {
      const bool agrees=
         (bullish  && snapshot.structure.direction==SRP_TREND_DIR_BULLISH) ||
         (bearish  && snapshot.structure.direction==SRP_TREND_DIR_BEARISH);
      if(agrees)
        {
         confidence+=0.10;
         why+=", with structure";
        }
      else
         if(snapshot.structure.direction==SRP_TREND_DIR_RANGING)
           {
            //--- A squeeze release out of a range is the textbook case.
            confidence+=0.06;
            why+=", out of a range";
           }
     }

   //--- The release must be worth more than the cost of entering it.
   if(snapshot.spread_points>0.0 && snapshot.point>0.0)
     {
      const double range_points=last_range/snapshot.point;
      if(range_points<snapshot.spread_points*3.0)
        {
         Emit(signal,snapshot,SRP_DECISION_NO_TRADE,0.0,
              StringFormat("release of %.0f points is too small against a "
                           "%.0f point spread",
                           range_points,snapshot.spread_points),
              SRP_RISK_RATING_NONE);
         return(false);
        }
     }

   confidence=CMathUtils::Clamp(confidence,0.0,1.0);

   const string reason=StringFormat("%s volatility breakout: %s",
                                    (bullish ? "bullish" : "bearish"),why);

   Emit(signal,snapshot,
        (bullish ? SRP_DECISION_BUY : SRP_DECISION_SELL),
        confidence,reason,RatingFromConfidence(confidence));

   //--- Stop hint: the far side of the breakout bar. If price returns
   //--- through it, the release failed and the premise is gone.
   signal.suggested_stop=(bullish ? snapshot.prev_low : snapshot.prev_high);
   return(true);
  }

#endif // SRP_DECISION_STRATEGIES_CSTRUCTURESTRATEGIES_MQH
//+------------------------------------------------------------------+
