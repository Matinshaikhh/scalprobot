//+------------------------------------------------------------------+
//|                                      CConfirmationEngine.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   RESPONSIBILITY (one only): score a proposed direction against         |
//|   thirteen independent checks and produce a composite confidence.      |
//|                                                                  |
//|   THE THIRTEEN CHECKS                                                |
//|     Trend · Volume · ATR · VWAP · ADX · RSI · MACD · Bollinger ·       |
//|     Market Structure · SMC · News · Session · Spread                  |
//|                                                                  |
//|   FOUR-VALUED RESULTS, NOT BOOLEAN                                   |
//|   PASS / FAIL / NEUTRAL / UNAVAILABLE. The distinction between the      |
//|   last two matters enormously: NEUTRAL means the indicator has an       |
//|   opinion and it is "no strong view"; UNAVAILABLE means there is no     |
//|   data at all. Collapsing them into false would let a missing           |
//|   indicator masquerade as a genuine disagreement and quietly suppress   |
//|   every trade.                                                        |
//|                                                                  |
//|   Unavailable checks are EXCLUDED from the denominator rather than      |
//|   scored zero, so wiring fewer indicators lowers precision but does    |
//|   not systematically bias the score toward zero.                       |
//|                                                                  |
//|   BLOCKING vs ADVISORY                                               |
//|   News, session and spread are blocking: they veto outright. The        |
//|   indicator checks are advisory - they move the score. That mirrors     |
//|   reality: a wide spread makes a scalp unprofitable regardless of how   |
//|   good the setup looks, whereas a flat RSI merely weakens it.           |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_CONFIRMATION_CCONFIRMATIONENGINE_MQH
#define SRP_DECISION_CONFIRMATION_CCONFIRMATIONENGINE_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "../Strategies/CStrategyContext.mqh"
#include "../Types/DecisionStructs.mqh"

#define SRP_CONFIRM_COUNT 13

class CConfirmationEngine
  {
private:
   ILogger          *m_logger;            // borrowed
   CStrategyContext *m_context;           // borrowed

   //--- Per-check configuration.
   bool              m_enabled[SRP_CONFIRM_COUNT];
   double            m_weight[SRP_CONFIRM_COUNT];
   bool              m_blocking[SRP_CONFIRM_COUNT];

   //--- Thresholds.
   double            m_min_confidence;
   double            m_adx_trending;
   double            m_rsi_bull_floor;
   double            m_rsi_bear_ceiling;
   double            m_min_volume_ratio;
   double            m_min_atr_points;
   double            m_max_atr_points;
   double            m_max_spread_points;
   double            m_min_session_liquidity;
   //--- Requiring a minimum number of decisive checks prevents a
   //--- "confirmed" verdict resting on one available indicator.
   int               m_min_decisive_checks;

   SConfirmation     m_results[SRP_CONFIRM_COUNT];
   SConfirmationReport m_last_report;
   long              m_evaluations;
   long              m_confirmations;
   long              m_rejections;

   //--- One method per check. Each sets result, score and detail.
   void              CheckTrend(const SDecisionInput &snapshot,
                                const ENUM_SRP_DECISION direction,
                                SConfirmation &out) const;
   void              CheckVolume(const SDecisionInput &snapshot,
                                 SConfirmation &out) const;
   void              CheckAtr(const SDecisionInput &snapshot,
                              SConfirmation &out) const;
   void              CheckVwap(const SDecisionInput &snapshot,
                               const ENUM_SRP_DECISION direction,
                               SConfirmation &out) const;
   void              CheckAdx(const SDecisionInput &snapshot,
                              const ENUM_SRP_DECISION direction,
                              SConfirmation &out) const;
   void              CheckRsi(const SDecisionInput &snapshot,
                              const ENUM_SRP_DECISION direction,
                              SConfirmation &out) const;
   void              CheckMacd(const SDecisionInput &snapshot,
                               const ENUM_SRP_DECISION direction,
                               SConfirmation &out) const;
   void              CheckBollinger(const SDecisionInput &snapshot,
                                    const ENUM_SRP_DECISION direction,
                                    SConfirmation &out) const;
   void              CheckStructure(const SDecisionInput &snapshot,
                                    const ENUM_SRP_DECISION direction,
                                    SConfirmation &out) const;
   void              CheckSmc(const SDecisionInput &snapshot,
                              const ENUM_SRP_DECISION direction,
                              SConfirmation &out) const;
   void              CheckNews(const SDecisionInput &snapshot,
                               SConfirmation &out) const;
   void              CheckSession(const SDecisionInput &snapshot,
                                  SConfirmation &out) const;
   void              CheckSpread(const SDecisionInput &snapshot,
                                 SConfirmation &out) const;

   void              Stamp(SConfirmation &out,
                           const ENUM_SRP_CONFIRM_KIND kind,
                           const string name,
                           const int index) const;
   static void       SetResult(SConfirmation &out,
                               const ENUM_SRP_CONFIRM_RESULT result,
                               const double score,
                               const string detail);

public:
                     CConfirmationEngine(CStrategyContext *context,ILogger *logger);
                    ~CConfirmationEngine(void) { }

   //--- Configuration ------------------------------------------------
   void              SetCheckEnabled(const ENUM_SRP_CONFIRM_KIND kind,
                                     const bool enabled);
   void              SetCheckWeight(const ENUM_SRP_CONFIRM_KIND kind,
                                    const double weight);
   void              SetCheckBlocking(const ENUM_SRP_CONFIRM_KIND kind,
                                      const bool blocking);
   void              SetMinConfidence(const double minimum);
   void              SetAdxThreshold(const double trending);
   void              SetRsiBands(const double bull_floor,const double bear_ceiling);
   void              SetMinVolumeRatio(const double ratio);
   void              SetAtrBounds(const double min_points,const double max_points);
   void              SetMaxSpread(const double points);
   void              SetMinSessionLiquidity(const double score);
   void              SetMinDecisiveChecks(const int count);

   bool              Validate(SValidationResult &result) const;

   //--- THE primary operation. Returns false when the trade is rejected.
   bool              Confirm(const SDecisionInput &snapshot,
                             const ENUM_SRP_DECISION direction,
                             SConfirmationReport &report);

   //--- Access -------------------------------------------------------
   void              GetLastReport(SConfirmationReport &out) const
     { out=m_last_report; }
   int               ResultCount(void) const { return(SRP_CONFIRM_COUNT); }
   bool              GetResult(const int index,SConfirmation &out) const;
   long              EvaluationCount(void)   const { return(m_evaluations); }
   long              ConfirmationCount(void) const { return(m_confirmations); }
   long              RejectionCount(void)    const { return(m_rejections); }
   string            Describe(void) const;
   static string     KindToString(const ENUM_SRP_CONFIRM_KIND kind);
   static string     ResultToString(const ENUM_SRP_CONFIRM_RESULT result);
  };

//+------------------------------------------------------------------+
CConfirmationEngine::CConfirmationEngine(CStrategyContext *context,
                                         ILogger *logger)
  : m_logger(logger),
    m_context(context),
    m_min_confidence(0.55),
    m_adx_trending(22.0),
    m_rsi_bull_floor(48.0),
    m_rsi_bear_ceiling(52.0),
    m_min_volume_ratio(0.8),
    m_min_atr_points(0.0),
    m_max_atr_points(0.0),
    m_max_spread_points(0.0),
    m_min_session_liquidity(0.0),
    m_min_decisive_checks(3),
    m_evaluations(0),
    m_confirmations(0),
    m_rejections(0)
  {
   //--- All checks enabled and equally weighted by default.
   for(int i=0;i<SRP_CONFIRM_COUNT;i++)
     {
      m_enabled[i]=true;
      m_weight[i]=1.0;
      m_blocking[i]=false;
     }
   //--- BLOCKING by default: these three make a trade unviable rather
   //--- than merely less attractive.
   m_blocking[(int)SRP_CONFIRM_NEWS]=true;
   m_blocking[(int)SRP_CONFIRM_SESSION]=true;
   m_blocking[(int)SRP_CONFIRM_SPREAD]=true;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetCheckEnabled(const ENUM_SRP_CONFIRM_KIND kind,
                                          const bool enabled)
  {
   const int index=(int)kind;
   if(index>=0 && index<SRP_CONFIRM_COUNT)
      m_enabled[index]=enabled;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetCheckWeight(const ENUM_SRP_CONFIRM_KIND kind,
                                         const double weight)
  {
   const int index=(int)kind;
   if(index>=0 && index<SRP_CONFIRM_COUNT && weight>=0.0)
      m_weight[index]=weight;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetCheckBlocking(const ENUM_SRP_CONFIRM_KIND kind,
                                           const bool blocking)
  {
   const int index=(int)kind;
   if(index>=0 && index<SRP_CONFIRM_COUNT)
      m_blocking[index]=blocking;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetMinConfidence(const double minimum)
  {
   if(minimum>=0.0 && minimum<=1.0)
      m_min_confidence=minimum;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetAdxThreshold(const double trending)
  {
   if(trending>0.0)
      m_adx_trending=trending;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetRsiBands(const double bull_floor,
                                      const double bear_ceiling)
  {
   if(bull_floor>0.0 && bull_floor<100.0)   m_rsi_bull_floor=bull_floor;
   if(bear_ceiling>0.0 && bear_ceiling<100.0) m_rsi_bear_ceiling=bear_ceiling;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetMinVolumeRatio(const double ratio)
  {
   if(ratio>=0.0)
      m_min_volume_ratio=ratio;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetAtrBounds(const double min_points,
                                       const double max_points)
  {
   m_min_atr_points=(min_points<0.0 ? 0.0 : min_points);
   m_max_atr_points=(max_points<0.0 ? 0.0 : max_points);
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetMaxSpread(const double points)
  {
   m_max_spread_points=(points<0.0 ? 0.0 : points);
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetMinSessionLiquidity(const double score)
  {
   if(score>=0.0 && score<=1.0)
      m_min_session_liquidity=score;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetMinDecisiveChecks(const int count)
  {
   if(count>=0)
      m_min_decisive_checks=count;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::Stamp(SConfirmation &out,
                                const ENUM_SRP_CONFIRM_KIND kind,
                                const string name,
                                const int index) const
  {
   out.Reset();
   out.kind=kind;
   out.name=name;
   out.weight=m_weight[index];
   out.is_blocking=m_blocking[index];
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::SetResult(SConfirmation &out,
                                    const ENUM_SRP_CONFIRM_RESULT result,
                                    const double score,
                                    const string detail)
  {
   out.result=result;
   out.score=CMathUtils::Clamp(score,0.0,1.0);
   out.detail=detail;
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckTrend(const SDecisionInput &snapshot,
                                     const ENUM_SRP_DECISION direction,
                                     SConfirmation &out) const
  {
   //--- Trend agreement via the trend EMA. Distinct from the structure
   //--- check, which uses swing sequence rather than a moving average.
   double trend_value=0.0;
   if(!m_context.EmaTrendValue(trend_value))
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"no trend EMA");
      return;
     }
   const bool above=(snapshot.close>trend_value);
   const bool agrees=(direction==SRP_DECISION_BUY ? above : !above);

   //--- Distance from the average scales the conviction: price hugging
   //--- the MA is a weak read either way.
   double atr=0.0;
   double normalised=0.5;
   if(m_context.AtrValue(atr) && atr>0.0)
      normalised=CMathUtils::Clamp(MathAbs(snapshot.close-trend_value)/atr,0.0,1.0);

   if(agrees)
      SetResult(out,SRP_CONFIRM_PASS,0.5+normalised*0.5,
                StringFormat("price %s trend EMA",(above ? "above" : "below")));
   else
      SetResult(out,SRP_CONFIRM_FAIL,0.5-normalised*0.5,
                StringFormat("price %s trend EMA, against direction",
                             (above ? "above" : "below")));
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckVolume(const SDecisionInput &snapshot,
                                      SConfirmation &out) const
  {
   //--- Volume is DIRECTIONLESS: it confirms participation, not a side.
   //--- Scoring it as a pass/fail on direction would be meaningless.
   double relative=0.0;
   if(!m_context.RelativeVolume(20,relative))
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"no volume data");
      return;
     }
   if(relative>=m_min_volume_ratio)
      SetResult(out,SRP_CONFIRM_PASS,
                CMathUtils::Clamp(relative/2.0,0.0,1.0),
                StringFormat("volume x%.2f of average",relative));
   else
      SetResult(out,SRP_CONFIRM_FAIL,
                CMathUtils::Clamp(relative/2.0,0.0,1.0),
                StringFormat("volume x%.2f below floor x%.2f",
                             relative,m_min_volume_ratio));
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckAtr(const SDecisionInput &snapshot,
                                   SConfirmation &out) const
  {
   //--- TWO-SIDED. Too little volatility means the target cannot be
   //--- reached before the spread eats the edge; too much means stops are
   //--- random. Most implementations filter only the upper bound.
   double atr_points=0.0;
   if(!m_context.AtrPoints(snapshot.point,atr_points))
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"no ATR");
      return;
     }
   if(m_min_atr_points>0.0 && atr_points<m_min_atr_points)
     {
      SetResult(out,SRP_CONFIRM_FAIL,0.2,
                StringFormat("ATR %.1f below floor %.1f pts",
                             atr_points,m_min_atr_points));
      return;
     }
   if(m_max_atr_points>0.0 && atr_points>m_max_atr_points)
     {
      SetResult(out,SRP_CONFIRM_FAIL,0.2,
                StringFormat("ATR %.1f above ceiling %.1f pts",
                             atr_points,m_max_atr_points));
      return;
     }
   //--- Inside the usable band. Score by expansion: an expanding market
   //--- offers more room, which suits a scalper.
   double ratio=1.0;
   CAtrIntel *atr=m_context.Atr();
   if(atr!=NULL)
      atr.ExpansionRatio(20,ratio);
   SetResult(out,SRP_CONFIRM_PASS,
             CMathUtils::Clamp(ratio/1.5,0.3,1.0),
             StringFormat("ATR %.1f pts, expansion x%.2f",atr_points,ratio));
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckVwap(const SDecisionInput &snapshot,
                                    const ENUM_SRP_DECISION direction,
                                    SConfirmation &out) const
  {
   double vwap=0.0;
   if(!m_context.VwapValue(vwap))
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"no VWAP");
      return;
     }
   //--- Above VWAP is intraday bullish control, below is bearish.
   const bool above=(snapshot.close>vwap);
   const bool agrees=(direction==SRP_DECISION_BUY ? above : !above);

   double atr=0.0;
   double normalised=0.5;
   if(m_context.AtrValue(atr) && atr>0.0)
      normalised=CMathUtils::Clamp(MathAbs(snapshot.close-vwap)/atr,0.0,1.0);

   if(agrees)
      SetResult(out,SRP_CONFIRM_PASS,0.5+normalised*0.5,
                StringFormat("price %s VWAP",(above ? "above" : "below")));
   else
      SetResult(out,SRP_CONFIRM_FAIL,0.5-normalised*0.5,
                "price on the wrong side of VWAP");
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckAdx(const SDecisionInput &snapshot,
                                   const ENUM_SRP_DECISION direction,
                                   SConfirmation &out) const
  {
   double adx=0.0;
   if(!m_context.AdxValue(adx))
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"no ADX");
      return;
     }
   //--- ADX measures STRENGTH; the DI pair supplies DIRECTION. Reading
   //--- ADX alone as directional is a common misinterpretation.
   double plus=0.0,minus=0.0;
   const bool has_di=m_context.AdxDi(plus,minus);

   if(adx<m_adx_trending)
     {
      //--- Weak trend is genuinely NEUTRAL, not a failure: plenty of
      //--- valid setups occur in quiet conditions.
      SetResult(out,SRP_CONFIRM_NEUTRAL,0.4,
                StringFormat("ADX %.1f below trending threshold %.1f",
                             adx,m_adx_trending));
      return;
     }
   if(!has_di)
     {
      SetResult(out,SRP_CONFIRM_NEUTRAL,0.5,
                StringFormat("ADX %.1f but DI unavailable",adx));
      return;
     }

   const bool bullish_bias=(plus>minus);
   const bool agrees=(direction==SRP_DECISION_BUY ? bullish_bias : !bullish_bias);
   if(agrees)
      SetResult(out,SRP_CONFIRM_PASS,CMathUtils::Clamp(adx/50.0,0.0,1.0),
                StringFormat("ADX %.1f with %s DI bias",
                             adx,(bullish_bias ? "+" : "-")));
   else
      SetResult(out,SRP_CONFIRM_FAIL,0.2,
                StringFormat("ADX %.1f but DI bias opposes",adx));
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckRsi(const SDecisionInput &snapshot,
                                   const ENUM_SRP_DECISION direction,
                                   SConfirmation &out) const
  {
   double rsi=0.0;
   if(!m_context.RsiValue(rsi))
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"no RSI");
      return;
     }
   //--- Used as a MOMENTUM BIAS check, not an overbought/oversold veto.
   //--- Vetoing a long because RSI is high would reject exactly the
   //--- strong-momentum entries a scalper wants.
   if(direction==SRP_DECISION_BUY)
     {
      if(rsi>=m_rsi_bull_floor)
         SetResult(out,SRP_CONFIRM_PASS,
                   CMathUtils::Clamp((rsi-50.0)/30.0+0.5,0.0,1.0),
                   StringFormat("RSI %.1f supports long",rsi));
      else
         SetResult(out,SRP_CONFIRM_FAIL,
                   CMathUtils::Clamp(rsi/100.0,0.0,1.0),
                   StringFormat("RSI %.1f below long floor %.1f",
                                rsi,m_rsi_bull_floor));
      return;
     }
   if(rsi<=m_rsi_bear_ceiling)
      SetResult(out,SRP_CONFIRM_PASS,
                CMathUtils::Clamp((50.0-rsi)/30.0+0.5,0.0,1.0),
                StringFormat("RSI %.1f supports short",rsi));
   else
      SetResult(out,SRP_CONFIRM_FAIL,
                CMathUtils::Clamp((100.0-rsi)/100.0,0.0,1.0),
                StringFormat("RSI %.1f above short ceiling %.1f",
                             rsi,m_rsi_bear_ceiling));
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckMacd(const SDecisionInput &snapshot,
                                    const ENUM_SRP_DECISION direction,
                                    SConfirmation &out) const
  {
   double histogram=0.0;
   if(!m_context.MacdHistogram(histogram))
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"no MACD");
      return;
     }
   const bool bullish=(histogram>0.0);
   const bool agrees=(direction==SRP_DECISION_BUY ? bullish : !bullish);

   //--- Normalise magnitude against ATR so the score is
   //--- instrument-independent.
   double atr=0.0;
   double magnitude=0.5;
   if(m_context.AtrValue(atr) && atr>0.0)
      magnitude=CMathUtils::Clamp(MathAbs(histogram)/(atr*0.3),0.0,1.0);

   if(agrees)
      SetResult(out,SRP_CONFIRM_PASS,0.4+magnitude*0.6,
                StringFormat("MACD histogram %s",(bullish ? "positive" : "negative")));
   else
      SetResult(out,SRP_CONFIRM_FAIL,0.3,"MACD histogram opposes direction");
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckBollinger(const SDecisionInput &snapshot,
                                         const ENUM_SRP_DECISION direction,
                                         SConfirmation &out) const
  {
   double upper=0.0,middle=0.0,lower=0.0;
   if(!m_context.BollingerBands(upper,middle,lower))
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"no Bollinger Bands");
      return;
     }
   const double width=upper-lower;
   if(width<=0.0)
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"degenerate bands");
      return;
     }

   //--- %B: 0 at the lower band, 1 at the upper.
   const double percent_b=CMathUtils::Clamp((snapshot.close-lower)/width,0.0,1.0);

   //--- ENTERING AT AN EXTREME IS PENALISED. Buying at the upper band
   //--- means chasing, and for a scalper the remaining room to the target
   //--- is what determines whether the trade can pay.
   if(direction==SRP_DECISION_BUY)
     {
      if(percent_b>0.9)
         SetResult(out,SRP_CONFIRM_FAIL,0.2,
                   StringFormat("%%B %.2f: buying at the upper extreme",percent_b));
      else
         SetResult(out,SRP_CONFIRM_PASS,1.0-percent_b,
                   StringFormat("%%B %.2f leaves room upward",percent_b));
      return;
     }
   if(percent_b<0.1)
      SetResult(out,SRP_CONFIRM_FAIL,0.2,
                StringFormat("%%B %.2f: selling at the lower extreme",percent_b));
   else
      SetResult(out,SRP_CONFIRM_PASS,percent_b,
                StringFormat("%%B %.2f leaves room downward",percent_b));
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckStructure(const SDecisionInput &snapshot,
                                         const ENUM_SRP_DECISION direction,
                                         SConfirmation &out) const
  {
   if(!snapshot.structure_valid)
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"structure not resolved");
      return;
     }
   //--- Ranging is NEUTRAL, not a failure: many valid setups are
   //--- range-bound by nature.
   if(!snapshot.structure.IsTrending())
     {
      SetResult(out,SRP_CONFIRM_NEUTRAL,0.45,
                "structure ranging, no directional bias");
      return;
     }
   const bool agrees=(direction==SRP_DECISION_BUY
                      ? snapshot.structure.IsBullish()
                      : snapshot.structure.IsBearish());
   if(agrees)
      SetResult(out,SRP_CONFIRM_PASS,
                CMathUtils::Clamp(snapshot.structure.strength_score,0.0,1.0),
                StringFormat("%s %s structure",
                             CMarketStructure::DirectionToString(snapshot.structure.direction),
                             CMarketStructure::GradeToString(snapshot.structure.grade)));
   else
      SetResult(out,SRP_CONFIRM_FAIL,0.15,
                StringFormat("structure is %s, opposing",
                             CMarketStructure::DirectionToString(snapshot.structure.direction)));
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckSmc(const SDecisionInput &snapshot,
                                   const ENUM_SRP_DECISION direction,
                                   SConfirmation &out) const
  {
   CZoneRegistry *zones=m_context.Zones();
   if(zones==NULL)
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"no zone registry");
      return;
     }

   //--- PREMIUM/DISCOUNT is the primary SMC confirmation: buying in
   //--- discount and selling in premium is the core value principle.
   double location_score=0.5;
   string location="";
   if(snapshot.structure_valid && snapshot.structure.range.valid)
     {
      const double position=snapshot.structure.range.current_position;
      location_score=(direction==SRP_DECISION_BUY ? 1.0-position : position);
      location=StringFormat(", %s zone",
                            (snapshot.structure.range.zone==SRP_RANGE_PREMIUM ? "premium"
                             : snapshot.structure.range.zone==SRP_RANGE_DISCOUNT ? "discount"
                             : "equilibrium"));
     }

   //--- An opposing zone directly ahead is a genuine obstacle: price must
   //--- pass through resting orders to reach the target.
   SPriceZone blocking_zone;
   const ENUM_SRP_BIAS opposing=(direction==SRP_DECISION_BUY
                                 ? SRP_BIAS_BEARISH : SRP_BIAS_BULLISH);
   bool obstacle=false;
   if(direction==SRP_DECISION_BUY)
      obstacle=zones.NearestAbove(snapshot.close,blocking_zone) &&
               blocking_zone.bias==opposing;
   else
      obstacle=zones.NearestBelow(snapshot.close,blocking_zone) &&
               blocking_zone.bias==opposing;

   if(obstacle)
     {
      SetResult(out,SRP_CONFIRM_FAIL,location_score*0.5,
                StringFormat("opposing zone ahead at %.*f%s",
                             snapshot.digits,blocking_zone.midpoint,location));
      return;
     }

   if(location_score>=0.5)
      SetResult(out,SRP_CONFIRM_PASS,location_score,
                StringFormat("SMC location favourable%s",location));
   else
      SetResult(out,SRP_CONFIRM_NEUTRAL,location_score,
                StringFormat("SMC location marginal%s",location));
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckNews(const SDecisionInput &snapshot,
                                    SConfirmation &out) const
  {
   //--- BLOCKING. A news blackout makes the setup irrelevant.
   if(!snapshot.news.trading_permitted)
     {
      SetResult(out,SRP_CONFIRM_FAIL,0.0,
                StringLen(snapshot.news.detail)>0 ? snapshot.news.detail
                                                  : "news blackout active");
      return;
     }
   if(!snapshot.news.source_available)
     {
      //--- Permitted but blind. Reported as neutral so the score reflects
      //--- reduced certainty rather than false confidence.
      SetResult(out,SRP_CONFIRM_NEUTRAL,0.5,
                "news source unavailable; proceeding as configured");
      return;
     }
   SetResult(out,SRP_CONFIRM_PASS,1.0,
             StringLen(snapshot.news.detail)>0 ? snapshot.news.detail : "news clear");
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckSession(const SDecisionInput &snapshot,
                                       SConfirmation &out) const
  {
   //--- BLOCKING.
   if(!snapshot.session.trading_permitted)
     {
      SetResult(out,SRP_CONFIRM_FAIL,0.0,
                StringLen(snapshot.session.block_detail)>0
                ? snapshot.session.block_detail : "session closed");
      return;
     }
   if(m_min_session_liquidity>0.0 &&
      snapshot.session.liquidity_score<m_min_session_liquidity)
     {
      SetResult(out,SRP_CONFIRM_FAIL,snapshot.session.liquidity_score,
                StringFormat("liquidity %.2f below floor %.2f",
                             snapshot.session.liquidity_score,
                             m_min_session_liquidity));
      return;
     }
   SetResult(out,SRP_CONFIRM_PASS,snapshot.session.liquidity_score,
             StringFormat("%s%s liquidity %.2f",
                          CSessionManager::SessionToString(snapshot.session.active_session),
                          (snapshot.session.in_kill_zone ? " kill zone" : ""),
                          snapshot.session.liquidity_score));
  }
//+------------------------------------------------------------------+
void CConfirmationEngine::CheckSpread(const SDecisionInput &snapshot,
                                      SConfirmation &out) const
  {
   //--- BLOCKING and, for a scalper, decisive. A strategy targeting 100
   //--- points cannot survive a 60-point spread no matter how good the
   //--- setup is.
   if(m_max_spread_points<=0.0)
     {
      SetResult(out,SRP_CONFIRM_NEUTRAL,0.5,"spread check disabled");
      return;
     }
   if(snapshot.spread_points<=0.0)
     {
      SetResult(out,SRP_CONFIRM_UNAVAILABLE,0.0,"spread unavailable");
      return;
     }
   if(snapshot.spread_points>m_max_spread_points)
     {
      SetResult(out,SRP_CONFIRM_FAIL,0.0,
                StringFormat("spread %.1f exceeds limit %.1f pts",
                             snapshot.spread_points,m_max_spread_points));
      return;
     }
   //--- Tighter is better, scored linearly against the limit.
   SetResult(out,SRP_CONFIRM_PASS,
             CMathUtils::Clamp(1.0-(snapshot.spread_points/m_max_spread_points),
                               0.0,1.0),
             StringFormat("spread %.1f of %.1f pts",
                          snapshot.spread_points,m_max_spread_points));
  }
//+------------------------------------------------------------------+
bool CConfirmationEngine::Confirm(const SDecisionInput &snapshot,
                                  const ENUM_SRP_DECISION direction,
                                  SConfirmationReport &report)
  {
   report.Reset();
   m_evaluations++;

   if(m_context==NULL || direction==SRP_DECISION_NO_TRADE)
     {
      report.summary="no context or no direction";
      m_last_report=report;
      m_rejections++;
      return(false);
     }

   //--- Run every enabled check.
   Stamp(m_results[0],SRP_CONFIRM_TREND,"Trend",0);
   if(m_enabled[0]) CheckTrend(snapshot,direction,m_results[0]);
   Stamp(m_results[1],SRP_CONFIRM_VOLUME,"Volume",1);
   if(m_enabled[1]) CheckVolume(snapshot,m_results[1]);
   Stamp(m_results[2],SRP_CONFIRM_ATR,"ATR",2);
   if(m_enabled[2]) CheckAtr(snapshot,m_results[2]);
   Stamp(m_results[3],SRP_CONFIRM_VWAP,"VWAP",3);
   if(m_enabled[3]) CheckVwap(snapshot,direction,m_results[3]);
   Stamp(m_results[4],SRP_CONFIRM_ADX,"ADX",4);
   if(m_enabled[4]) CheckAdx(snapshot,direction,m_results[4]);
   Stamp(m_results[5],SRP_CONFIRM_RSI,"RSI",5);
   if(m_enabled[5]) CheckRsi(snapshot,direction,m_results[5]);
   Stamp(m_results[6],SRP_CONFIRM_MACD,"MACD",6);
   if(m_enabled[6]) CheckMacd(snapshot,direction,m_results[6]);
   Stamp(m_results[7],SRP_CONFIRM_BOLLINGER,"Bollinger",7);
   if(m_enabled[7]) CheckBollinger(snapshot,direction,m_results[7]);
   Stamp(m_results[8],SRP_CONFIRM_STRUCTURE,"Structure",8);
   if(m_enabled[8]) CheckStructure(snapshot,direction,m_results[8]);
   Stamp(m_results[9],SRP_CONFIRM_SMC,"SMC",9);
   if(m_enabled[9]) CheckSmc(snapshot,direction,m_results[9]);
   Stamp(m_results[10],SRP_CONFIRM_NEWS,"News",10);
   if(m_enabled[10]) CheckNews(snapshot,m_results[10]);
   Stamp(m_results[11],SRP_CONFIRM_SESSION,"Session",11);
   if(m_enabled[11]) CheckSession(snapshot,m_results[11]);
   Stamp(m_results[12],SRP_CONFIRM_SPREAD,"Spread",12);
   if(m_enabled[12]) CheckSpread(snapshot,m_results[12]);

   //--- AGGREGATE.
   double weighted_score=0.0;
   double weight_total=0.0;
   bool blocked=false;

   for(int i=0;i<SRP_CONFIRM_COUNT;i++)
     {
      if(!m_enabled[i])
         continue;
      report.evaluated++;

      switch(m_results[i].result)
        {
         case SRP_CONFIRM_PASS:
            report.passed++;
            weighted_score+=m_results[i].score*m_results[i].weight;
            weight_total+=m_results[i].weight;
            break;

         case SRP_CONFIRM_FAIL:
            report.failed++;
            weighted_score+=m_results[i].score*m_results[i].weight;
            weight_total+=m_results[i].weight;
            //--- A BLOCKING failure vetoes outright, regardless of score.
            if(m_results[i].is_blocking && !blocked)
              {
               blocked=true;
               report.blocking_failure=m_results[i].kind;
               report.blocking_detail=m_results[i].name+": "+m_results[i].detail;
              }
            break;

         case SRP_CONFIRM_NEUTRAL:
            report.neutral++;
            weighted_score+=m_results[i].score*m_results[i].weight;
            weight_total+=m_results[i].weight;
            break;

         case SRP_CONFIRM_UNAVAILABLE:
            //--- EXCLUDED from the denominator. Scoring it zero would let
            //--- a missing indicator drag the score down as if it had
            //--- actively disagreed.
            report.unavailable++;
            break;
        }
     }

   report.confidence=(weight_total>0.0 ? weighted_score/weight_total : 0.0);

   //--- Blocking veto takes precedence over any score.
   if(blocked)
     {
      report.confirmed=false;
      report.summary="blocked by "+report.blocking_detail;
      m_last_report=report;
      m_rejections++;
      return(false);
     }

   //--- MINIMUM EVIDENCE. Without this a single available check could
   //--- "confirm" a trade on its own.
   const int decisive=report.passed+report.failed;
   if(decisive<m_min_decisive_checks)
     {
      report.confirmed=false;
      report.summary=StringFormat("only %d decisive check(s), need %d",
                                  decisive,m_min_decisive_checks);
      m_last_report=report;
      m_rejections++;
      return(false);
     }

   report.confirmed=(report.confidence>=m_min_confidence);
   report.summary=StringFormat("%d pass, %d fail, %d neutral, %d unavailable; "
                               "confidence %.2f vs floor %.2f",
                               report.passed,report.failed,report.neutral,
                               report.unavailable,report.confidence,
                               m_min_confidence);
   m_last_report=report;
   if(report.confirmed)
      m_confirmations++;
   else
      m_rejections++;
   return(report.confirmed);
  }
//+------------------------------------------------------------------+
bool CConfirmationEngine::GetResult(const int index,SConfirmation &out) const
  {
   out.Reset();
   if(index<0 || index>=SRP_CONFIRM_COUNT)
      return(false);
   out=m_results[index];
   return(true);
  }
//+------------------------------------------------------------------+
bool CConfirmationEngine::Validate(SValidationResult &result) const
  {
   if(m_context==NULL)
     {
      result.AddError("CConfirmationEngine: no strategy context injected");
      return(false);
     }
   int enabled_count=0;
   for(int i=0;i<SRP_CONFIRM_COUNT;i++)
      if(m_enabled[i])
         enabled_count++;
   if(enabled_count==0)
     {
      result.AddError("CConfirmationEngine: all checks disabled");
      return(false);
     }
   if(m_min_decisive_checks>enabled_count)
      result.AddError("CConfirmationEngine: minimum decisive checks exceeds "
                      "the number of enabled checks; nothing can ever confirm");
   if(m_max_spread_points<=0.0)
      result.AddWarning("CConfirmationEngine: spread check disabled; a scalper "
                        "should normally cap spread");
   if(m_min_confidence<0.3)
      result.AddWarning("CConfirmationEngine: confidence floor below 0.30 will "
                        "admit weak setups");
   return(true);
  }
//+------------------------------------------------------------------+
string CConfirmationEngine::KindToString(const ENUM_SRP_CONFIRM_KIND kind)
  {
   switch(kind)
     {
      case SRP_CONFIRM_TREND:     return("Trend");
      case SRP_CONFIRM_VOLUME:    return("Volume");
      case SRP_CONFIRM_ATR:       return("ATR");
      case SRP_CONFIRM_VWAP:      return("VWAP");
      case SRP_CONFIRM_ADX:       return("ADX");
      case SRP_CONFIRM_RSI:       return("RSI");
      case SRP_CONFIRM_MACD:      return("MACD");
      case SRP_CONFIRM_BOLLINGER: return("Bollinger");
      case SRP_CONFIRM_STRUCTURE: return("Structure");
      case SRP_CONFIRM_SMC:       return("SMC");
      case SRP_CONFIRM_NEWS:      return("News");
      case SRP_CONFIRM_SESSION:   return("Session");
      case SRP_CONFIRM_SPREAD:    return("Spread");
     }
   return("Unknown");
  }
//+------------------------------------------------------------------+
string CConfirmationEngine::ResultToString(const ENUM_SRP_CONFIRM_RESULT result)
  {
   switch(result)
     {
      case SRP_CONFIRM_PASS:        return("PASS");
      case SRP_CONFIRM_FAIL:        return("FAIL");
      case SRP_CONFIRM_NEUTRAL:     return("NEUTRAL");
      case SRP_CONFIRM_UNAVAILABLE: return("UNAVAIL");
     }
   return("?");
  }
//+------------------------------------------------------------------+
string CConfirmationEngine::Describe(void) const
  {
   return(StringFormat("confirmation: %s conf=%.2f | %s | eval=%I64d "
                       "confirmed=%I64d rejected=%I64d",
                       (m_last_report.confirmed ? "CONFIRMED" : "rejected"),
                       m_last_report.confidence,
                       m_last_report.summary,
                       m_evaluations,m_confirmations,m_rejections));
  }

#endif // SRP_DECISION_CONFIRMATION_CCONFIRMATIONENGINE_MQH
//+------------------------------------------------------------------+
