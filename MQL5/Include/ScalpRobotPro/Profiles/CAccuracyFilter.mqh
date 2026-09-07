//+------------------------------------------------------------------+
//|                                          CAccuracyFilter.mqh |
//|         Scalping Robot Pro - entry quality gate (P7, XAUUSD M1) |
//|                                                                  |
//|   RESPONSIBILITY (one only): score how much AGREEMENT exists behind a  |
//|   proposed entry across three timeframes and the volume series, and    |
//|   refuse entries that lack it.                                       |
//|                                                                  |
//|   IT ONLY EVER REFUSES. It returns no size, no stop, no target and     |
//|   cannot create an entry. Every path through it either passes a        |
//|   decision through unchanged or declines it with a named reason.       |
//|                                                                  |
//|   WHY IT EXISTS - THE MEASURED PROBLEM                               |
//|   Over 1221 real-tick XAUUSD trades the payoff ratio was 0.948, which  |
//|   requires a 51.3% win rate to break even. The measured rate was       |
//|   43.90%. Attribution showed 1219 of those 1221 trades came from a     |
//|   SINGLE strategy firing on M1 alone, with no requirement that the     |
//|   higher timeframes agreed with it.                                   |
//|                                                                  |
//|   That is the gap this class addresses: it does not invent a new       |
//|   signal, it requires the existing one to be corroborated before it    |
//|   is traded.                                                          |
//|                                                                  |
//|   WHY AGREEMENT AND NOT A TIGHTER TARGET                              |
//|   A win rate can always be raised by shrinking the target, but that    |
//|   lowers the payoff by the same mechanism and the break-even rate      |
//|   rises to meet it. Nothing is gained. Raising the win rate through    |
//|   SELECTIVITY leaves the geometry alone, so the break-even rate stays  |
//|   where it is. Only the second kind of improvement is real, and this   |
//|   class is deliberately the second kind.                              |
//|                                                                  |
//|   TICK VOLUME, MEASURED NOT ASSUMED                                   |
//|   This broker reports real volume as ZERO on XAUUSD across M1/M5/M15   |
//|   and tick volume as healthy (means 35.7 / 313.2 / 875.4 per bar).    |
//|   So every volume test here uses TICK volume as a participation        |
//|   proxy, which is what is actually available rather than what would    |
//|   be preferable.                                                      |
//+------------------------------------------------------------------+
#ifndef SRP_PROFILES_CACCURACYFILTER_MQH
#define SRP_PROFILES_CACCURACYFILTER_MQH

#include "../Core/Interfaces/ILogger.mqh"
#include "../Intelligence/Indicators/CStandardIndicators.mqh"
#include "../Intelligence/Indicators/CComputedIndicators.mqh"
#include "../Utilities/CMathUtils.mqh"
#include "../Core/Types/Structs.mqh"

//+------------------------------------------------------------------+
//| Why an entry was refused. One primary reason, so the funnel reads   |
//| as a cause rather than a list of symptoms.                          |
//+------------------------------------------------------------------+
enum ENUM_SRP_ACCURACY_BLOCK
  {
   SRP_ACCURACY_OK,
   SRP_ACCURACY_BLOCK_MTF_CONFLICT,   // higher timeframe disagrees
   SRP_ACCURACY_BLOCK_VOLUME_THIN,    // no participation behind the move
   SRP_ACCURACY_BLOCK_EXHAUSTED,      // most of the move already happened
   SRP_ACCURACY_BLOCK_SCORE,          // agreement score below the floor
   SRP_ACCURACY_BLOCK_UNAVAILABLE,    // data missing: fail CLOSED
   SRP_ACCURACY_BLOCK_DISABLED
  };

//+------------------------------------------------------------------+
//| The verdict, with every component visible.                          |
//|                                                                  |
//| The components are reported individually and not just as a total,     |
//| because "score 0.55 below floor 0.65" tells an operator nothing about |
//| WHICH corroboration was missing.                                     |
//+------------------------------------------------------------------+
struct SAccuracyVerdict
  {
   bool                    allowed;
   ENUM_SRP_ACCURACY_BLOCK block;
   string                  detail;

   //--- Per-component agreement, each in [0,1].
   double                  mtf_score;       // M1 vs M5 vs M15 alignment
   double                  volume_score;    // participation behind the move
   double                  room_score;      // how much move is left
   double                  total_score;

   //--- Diagnostics worth seeing in a log.
   bool                    m5_agrees;
   bool                    m15_agrees;
   double                  relative_volume;
   double                  bar_position;    // where in its range price sits

                     SAccuracyVerdict(void) { Reset(); }
   void              Reset(void)
     {
      allowed=false; block=SRP_ACCURACY_OK; detail="";
      mtf_score=0.0; volume_score=0.0; room_score=0.0; total_score=0.0;
      m5_agrees=false; m15_agrees=false;
      relative_volume=0.0; bar_position=0.5;
     }
  };

//+------------------------------------------------------------------+
//| Running tally, so the contribution of each gate is measurable.      |
//+------------------------------------------------------------------+
struct SAccuracyMetrics
  {
   long              evaluated;
   long              passed;
   long              blocked_mtf;
   long              blocked_volume;
   long              blocked_exhausted;
   long              blocked_score;
   long              blocked_unavailable;
   //--- Mean score of what passed versus what did not. If these are the
   //--- same the filter is not discriminating and should be said so.
   double            score_sum_passed;
   double            score_sum_blocked;

                     SAccuracyMetrics(void) { Reset(); }
   void              Reset(void)
     {
      evaluated=0; passed=0;
      blocked_mtf=0; blocked_volume=0; blocked_exhausted=0;
      blocked_score=0; blocked_unavailable=0;
      score_sum_passed=0.0; score_sum_blocked=0.0;
     }
  };

//+------------------------------------------------------------------+
class CAccuracyFilter
  {
private:
   string            m_symbol;
   ILogger          *m_logger;          // borrowed

   //--- BORROWED, all of them. This class owns no indicator and deletes
   //--- nothing: the engine already builds these series and building a
   //--- second copy would double the handle count for no gain.
   CEmaIndicator    *m_ema_fast_exec;   // execution timeframe
   CEmaIndicator    *m_ema_slow_exec;
   CEmaIndicator    *m_ema_setup;       // M5 by default
   CEmaIndicator    *m_ema_context;     // M15 by default
   CVolumeIndicator *m_volume;
   CAtrIntel        *m_atr;

   ENUM_TIMEFRAMES   m_tf_exec;
   ENUM_TIMEFRAMES   m_tf_setup;
   ENUM_TIMEFRAMES   m_tf_context;

   bool              m_enabled;

   //=== CONFIGURATION =================================================
   //--- Require the setup/context timeframes to agree with the signal.
   bool              m_require_setup_agreement;
   bool              m_require_context_agreement;
   //--- Participation floor, as a multiple of the recent average.
   double            m_min_relative_volume;
   int               m_volume_lookback;

   //--- Relative volume of the LAST CLOSED BAR.
   //---
   //--- CVolumeIndicator::RelativeVolume divides the FORMING bar by the
   //--- preceding average, which is the right measure for "is this bar
   //--- busy right now" and the wrong one here. A signal arriving 20%
   //--- into a bar sees roughly 20% of that bar's eventual volume, so an
   //--- x1.0 floor rejects nearly everything for a reason that has
   //--- nothing to do with participation.
   //---
   //--- MEASURED: with the forming bar, 1165 of 1313 signals were refused
   //--- as VOLUME_THIN - which read as "gold never has volume behind its
   //--- breaks" and was actually an artefact of when the bar was sampled.
   //---
   //--- Closed bars only, so the reading is also reproducible: the same
   //--- signal scores the same whenever it is evaluated within the bar.
   bool              ClosedBarRelativeVolume(double &out) const;
   //--- How far into its own recent range price may already have travelled
   //--- before a continuation entry is treated as late.
   double            m_max_entry_extension;
   //--- Composite floor.
   double            m_min_total_score;
   //--- Component weights.
   double            m_weight_mtf;
   double            m_weight_volume;
   double            m_weight_room;

   SAccuracyMetrics  m_metrics;
   SAccuracyVerdict  m_last;

   //--- True when an EMA pair on the given timeframe leans the way the
   //--- signal does. Reads shift 1: the CLOSED bar.
   bool              TimeframeAgrees(CEmaIndicator *ema,const bool is_buy,
                                     bool &resolved) const;
   //--- Where price sits inside the recent range, 0 = low, 1 = high.
   bool              BarPosition(const bool is_buy,double &out) const;

public:
                     CAccuracyFilter(const string symbol,ILogger *logger);
                    ~CAccuracyFilter(void) { }

   void              SetIndicators(CEmaIndicator *fast_exec,
                                   CEmaIndicator *slow_exec,
                                   CEmaIndicator *setup,
                                   CEmaIndicator *context,
                                   CVolumeIndicator *volume,
                                   CAtrIntel *atr);
   void              SetTimeframes(const ENUM_TIMEFRAMES exec,
                                   const ENUM_TIMEFRAMES setup,
                                   const ENUM_TIMEFRAMES context);
   void              SetEnabled(const bool enabled) { m_enabled=enabled; }
   bool              IsEnabled(void) const { return(m_enabled); }

   void              ConfigureAgreement(const bool require_setup,
                                        const bool require_context);
   void              ConfigureVolume(const double min_relative,
                                     const int lookback);
   void              ConfigureExtension(const double max_extension);
   void              ConfigureScore(const double min_total,
                                    const double weight_mtf,
                                    const double weight_volume,
                                    const double weight_room);

   bool              Initialize(void);
   void              Validate(SValidationResult &result) const;

   //=== THE GATE ======================================================
   //--- Refuse-only. Never returns a size, a stop or a target.
   //---
   //--- `strategy_kind` is ENUM_SRP_STRATEGY_KIND, passed as int so this
   //--- class keeps no dependency on the decision layer. It exists because
   //--- the extension test is only meaningful for CONTINUATION setups; see
   //--- IsBreakoutPremise. Defaulted to -1 ("unknown"), which is treated as
   //--- a continuation setup so the stricter behaviour is the default.
   bool              Evaluate(const bool is_buy,SAccuracyVerdict &verdict,
                              const int strategy_kind=-1);

   //--- Does this strategy's premise REQUIRE price to be at an extreme?
   //---
   //--- THE MEASURED DEFECT THIS ANSWERS. Over one month the extension gate
   //--- refused 45 of 61 accuracy rejections - by far the largest single
   //--- cause of "no trades". It measures how far price has travelled
   //--- through the last 20 M1 bars and refuses entries near the top of
   //--- that range as "late".
   //---
   //--- For a pullback or mean-reversion entry that is exactly right. For a
   //--- BREAK OF STRUCTURE it is a contradiction: the signal fires BECAUSE
   //--- price just made a new extreme, so bar_position is ~1.0 by
   //--- construction and the gate refused essentially every one of them.
   //--- Since Break-of-Structure produced 1219 of 1221 trades in the
   //--- 31-month sample, that single interaction was enough to stop trading
   //--- altogether.
   //---
   //--- The gate is NOT removed - being late still matters for the setups
   //--- where lateness is a real risk. It is made premise-aware.
   static bool       IsBreakoutPremise(const int strategy_kind);

   void              GetMetrics(SAccuracyMetrics &out) const { out=m_metrics; }
   string            DescribeFunnel(void) const;
   static string     BlockToString(const ENUM_SRP_ACCURACY_BLOCK block);
  };

//+------------------------------------------------------------------+
CAccuracyFilter::CAccuracyFilter(const string symbol,ILogger *logger)
  : m_symbol(symbol),
    m_logger(logger),
    m_ema_fast_exec(NULL),
    m_ema_slow_exec(NULL),
    m_ema_setup(NULL),
    m_ema_context(NULL),
    m_volume(NULL),
    m_atr(NULL),
    m_tf_exec(PERIOD_M1),
    m_tf_setup(PERIOD_M5),
    m_tf_context(PERIOD_M15),
    m_enabled(false),
    m_require_setup_agreement(true),
    m_require_context_agreement(true),
    m_min_relative_volume(1.0),
    m_volume_lookback(20),
    m_max_entry_extension(0.75),
    m_min_total_score(0.65),
    m_weight_mtf(0.5),
    m_weight_volume(0.3),
    m_weight_room(0.2)
  {
   m_metrics.Reset();
   m_last.Reset();
  }
//+------------------------------------------------------------------+
void CAccuracyFilter::SetIndicators(CEmaIndicator *fast_exec,
                                    CEmaIndicator *slow_exec,
                                    CEmaIndicator *setup,
                                    CEmaIndicator *context,
                                    CVolumeIndicator *volume,
                                    CAtrIntel *atr)
  {
   m_ema_fast_exec=fast_exec;
   m_ema_slow_exec=slow_exec;
   m_ema_setup=setup;
   m_ema_context=context;
   m_volume=volume;
   m_atr=atr;
  }
//+------------------------------------------------------------------+
void CAccuracyFilter::SetTimeframes(const ENUM_TIMEFRAMES exec,
                                    const ENUM_TIMEFRAMES setup,
                                    const ENUM_TIMEFRAMES context)
  {
   if((int)exec>0)    m_tf_exec=exec;
   if((int)setup>0)   m_tf_setup=setup;
   if((int)context>0) m_tf_context=context;
  }
//+------------------------------------------------------------------+
void CAccuracyFilter::ConfigureAgreement(const bool require_setup,
                                         const bool require_context)
  {
   m_require_setup_agreement=require_setup;
   m_require_context_agreement=require_context;
  }
//+------------------------------------------------------------------+
void CAccuracyFilter::ConfigureVolume(const double min_relative,
                                      const int lookback)
  {
   if(min_relative>=0.0) m_min_relative_volume=min_relative;
   if(lookback>1)        m_volume_lookback=lookback;
  }
//+------------------------------------------------------------------+
void CAccuracyFilter::ConfigureExtension(const double max_extension)
  {
   //--- Below 0.5 a continuation entry would be refused in the very
   //--- conditions it exists for, so the usable band is bounded.
   if(max_extension>=0.5 && max_extension<=1.0)
      m_max_entry_extension=max_extension;
  }
//+------------------------------------------------------------------+
void CAccuracyFilter::ConfigureScore(const double min_total,
                                     const double weight_mtf,
                                     const double weight_volume,
                                     const double weight_room)
  {
   if(min_total>=0.0 && min_total<=1.0)
      m_min_total_score=min_total;
   //--- Weights are normalised on use, so only their ratio matters and a
   //--- caller cannot accidentally change the scale of the score.
   if(weight_mtf>=0.0)    m_weight_mtf=weight_mtf;
   if(weight_volume>=0.0) m_weight_volume=weight_volume;
   if(weight_room>=0.0)   m_weight_room=weight_room;
  }
//+------------------------------------------------------------------+
bool CAccuracyFilter::Initialize(void)
  {
   m_metrics.Reset();
   m_last.Reset();
   return(true);
  }
//+------------------------------------------------------------------+
void CAccuracyFilter::Validate(SValidationResult &result) const
  {
   if(!m_enabled)
      return;
   if(m_ema_fast_exec==NULL || m_ema_slow_exec==NULL)
      result.AddError("CAccuracyFilter: execution EMAs missing, alignment "
                      "cannot be assessed");
   if(m_require_setup_agreement && m_ema_setup==NULL)
      result.AddError("CAccuracyFilter: setup-timeframe agreement required "
                      "but no setup EMA is wired");
   if(m_require_context_agreement && m_ema_context==NULL)
      result.AddError("CAccuracyFilter: context-timeframe agreement required "
                      "but no context EMA is wired");
   if(m_volume==NULL && m_min_relative_volume>0.0)
      result.AddError("CAccuracyFilter: a volume floor is set but no volume "
                      "series is wired; the filter would be inert");
   if(m_tf_setup==m_tf_exec || m_tf_context==m_tf_exec)
      result.AddWarning("CAccuracyFilter: setup or context timeframe equals "
                        "the execution timeframe, so 'agreement' is a "
                        "comparison of a series with itself");
   const double weight_total=m_weight_mtf+m_weight_volume+m_weight_room;
   if(weight_total<=0.0)
      result.AddError("CAccuracyFilter: all component weights are zero, the "
                      "score would always be zero");
  }
//+------------------------------------------------------------------+
//| Does this timeframe's EMA pair lean the way the signal does?         |
//|                                                                  |
//| SHIFT 1 THROUGHOUT. The forming bar's EMA changes on every tick, so   |
//| reading shift 0 would let the same setup pass and fail within one     |
//| bar and would make any measurement irreproducible.                    |
//|                                                                  |
//| `resolved` distinguishes "disagrees" from "could not be read". They   |
//| are different facts and the caller fails CLOSED on the second.       |
//+------------------------------------------------------------------+
bool CAccuracyFilter::TimeframeAgrees(CEmaIndicator *ema,const bool is_buy,
                                      bool &resolved) const
  {
   resolved=false;
   if(ema==NULL || !ema.IsReady())
      return(false);

   double now=0.0,prior=0.0;
   if(!ema.ValueAt(0,1,now) || !ema.ValueAt(0,3,prior))
      return(false);
   if(now<=0.0 || prior<=0.0)
      return(false);

   resolved=true;
   //--- Slope of the average over two closed bars. Deliberately simple:
   //--- the question is only which way this timeframe leans, and a more
   //--- elaborate measure would add parameters without adding information.
   return(is_buy ? (now>prior) : (now<prior));
  }
//+------------------------------------------------------------------+
//| Where does price sit inside its recent range?                       |
//|                                                                  |
//| 0 means at the low, 1 at the high. For a BUY, a value near 1 means    |
//| the move has already happened and the entry is late - which is one of |
//| the few things that reliably converts a good signal into a bad trade. |
//+------------------------------------------------------------------+
bool CAccuracyFilter::ClosedBarRelativeVolume(double &out) const
  {
   out=0.0;
   const int lookback=(m_volume_lookback>1 ? m_volume_lookback : 20);
   //--- One extra bar: index 0 is the forming bar and is discarded, so the
   //--- numerator is bar 1 and the average spans bars 2..lookback+1.
   long v[];
   const int want=lookback+2;
   if(CopyTickVolume(m_symbol,m_tf_exec,0,want,v)!=want)
      return(false);

   const double current=(double)v[1];
   double sum=0.0;
   int    n=0;
   for(int i=2;i<want;i++)
     {
      if(v[i]<=0)
         continue;
      sum+=(double)v[i];
      n++;
     }
   if(n<=0 || current<=0.0)
      return(false);
   const double mean=sum/(double)n;
   if(mean<=0.0)
      return(false);
   out=current/mean;
   return(true);
  }
//+------------------------------------------------------------------+
bool CAccuracyFilter::BarPosition(const bool is_buy,double &out) const
  {
   out=0.5;
   const int lookback=20;
   double high[],low[];
   if(CopyHigh(m_symbol,m_tf_exec,1,lookback,high)!=lookback)
      return(false);
   if(CopyLow(m_symbol,m_tf_exec,1,lookback,low)!=lookback)
      return(false);

   double hi=high[0],lo=low[0];
   for(int i=1;i<lookback;i++)
     {
      if(high[i]>hi) hi=high[i];
      if(low[i]<lo)  lo=low[i];
     }
   const double span=hi-lo;
   if(span<=0.0)
      return(false);

   const double price=(is_buy
                       ? SymbolInfoDouble(m_symbol,SYMBOL_ASK)
                       : SymbolInfoDouble(m_symbol,SYMBOL_BID));
   if(price<=0.0)
      return(false);

   //--- Expressed in the DIRECTION OF THE TRADE, so 1.0 always means
   //--- "extended" whether the trade is long or short. Reporting a raw
   //--- range position would invert the meaning for sells.
   const double raw=(price-lo)/span;
   out=CMathUtils::Clamp((is_buy ? raw : 1.0-raw),0.0,1.0);
   return(true);
  }
//+------------------------------------------------------------------+
//| THE GATE.                                                          |
//|                                                                  |
//| Order: cheapest and most decisive first, and the reported reason is   |
//| the PRIMARY one rather than whichever check ran last.                 |
//+------------------------------------------------------------------+
bool CAccuracyFilter::IsBreakoutPremise(const int strategy_kind)
  {
   //--- Written against the enumerator VALUES rather than the names, since
   //--- this class deliberately does not include the decision layer:
   //---   2  LIQUIDITY_SWEEP        - fires on a sweep of an extreme
   //---   6  OPENING_RANGE_BREAKOUT - fires on leaving the range
   //---   9  BREAKOUT               - fires on leaving the range
   //---   10 BREAK_OF_STRUCTURE     - fires on a new structural extreme
   //---   11 VOLATILITY_BREAKOUT    - fires on an expansion move
   //--- Every one of these REQUIRES price to be at an extreme, so judging
   //--- them "extended" refuses their own entry condition.
   return(strategy_kind==2  || strategy_kind==6 || strategy_kind==9 ||
          strategy_kind==10 || strategy_kind==11);
  }
//+------------------------------------------------------------------+
bool CAccuracyFilter::Evaluate(const bool is_buy,SAccuracyVerdict &verdict,
                               const int strategy_kind)
  {
   verdict.Reset();

   if(!m_enabled)
     {
      //--- Disabled means TRANSPARENT, not blocking. A filter that is
      //--- switched off must not change behaviour.
      verdict.allowed=true;
      verdict.block=SRP_ACCURACY_BLOCK_DISABLED;
      verdict.detail="accuracy filter disabled";
      verdict.total_score=1.0;
      m_last=verdict;
      return(true);
     }

   m_metrics.evaluated++;

   //--- 1. MULTI-TIMEFRAME AGREEMENT.
   //---
   //--- The measured defect this addresses: 1219 of 1221 trades were taken
   //--- on an M1 signal with no requirement that M5 or M15 agreed.
   bool setup_resolved=false, context_resolved=false;
   const bool setup_ok  = TimeframeAgrees(m_ema_setup,is_buy,setup_resolved);
   const bool context_ok= TimeframeAgrees(m_ema_context,is_buy,context_resolved);
   verdict.m5_agrees  = setup_ok;
   verdict.m15_agrees = context_ok;

   //--- FAIL CLOSED on unreadable data. Treating "unknown" as "agrees"
   //--- would quietly disable the filter during warm-up, which is exactly
   //--- when it is least safe to trade.
   if((m_require_setup_agreement && !setup_resolved) ||
      (m_require_context_agreement && !context_resolved))
     {
      verdict.block=SRP_ACCURACY_BLOCK_UNAVAILABLE;
      verdict.detail="higher-timeframe trend unreadable; refusing rather "
                     "than assuming agreement";
      m_metrics.blocked_unavailable++;
      m_last=verdict;
      return(false);
     }

   //--- Score before the hard requirement, so the score is reported even
   //--- on a refusal and the operator can see how close it was.
   int agree_count=0, agree_total=0;
   if(setup_resolved)   { agree_total++; if(setup_ok)   agree_count++; }
   if(context_resolved) { agree_total++; if(context_ok) agree_count++; }
   verdict.mtf_score=(agree_total>0
                      ? (double)agree_count/(double)agree_total : 0.0);

   if((m_require_setup_agreement && !setup_ok) ||
      (m_require_context_agreement && !context_ok))
     {
      verdict.block=SRP_ACCURACY_BLOCK_MTF_CONFLICT;
      verdict.detail=StringFormat("%s signal but %s%s disagrees",
                                  (is_buy ? "BUY" : "SELL"),
                                  (!setup_ok   ? EnumToString(m_tf_setup) : ""),
                                  (!context_ok ? " "+EnumToString(m_tf_context) : ""));
      m_metrics.blocked_mtf++;
      m_metrics.score_sum_blocked+=verdict.mtf_score;
      m_last=verdict;
      return(false);
     }

   //--- 2. PARTICIPATION.
   //---
   //--- Tick volume, because this feed reports real volume as zero on
   //--- XAUUSD. A break with no increase in activity behind it is the
   //--- classic false break.
   if(m_min_relative_volume>0.0)
     {
      double relative=0.0;
      //--- Closed bars only. See ClosedBarRelativeVolume: sampling the
      //--- forming bar made this gate reject 1165 of 1313 signals for a
      //--- reason unrelated to participation.
      if(!ClosedBarRelativeVolume(relative))
        {
         verdict.block=SRP_ACCURACY_BLOCK_UNAVAILABLE;
         verdict.detail="volume series unavailable; refusing rather than "
                        "assuming participation";
         m_metrics.blocked_unavailable++;
         m_last=verdict;
         return(false);
        }
      verdict.relative_volume=relative;
      //--- Scored on a curve rather than pass/fail, so a marginally thin
      //--- bar with strong agreement elsewhere is not discarded outright.
      verdict.volume_score=CMathUtils::Clamp(relative/2.0,0.0,1.0);

      if(m_min_relative_volume>0.0 && relative<m_min_relative_volume)
        {
         verdict.block=SRP_ACCURACY_BLOCK_VOLUME_THIN;
         verdict.detail=StringFormat("participation x%.2f below the x%.2f "
                                     "floor: move is not supported",
                                     relative,m_min_relative_volume);
         m_metrics.blocked_volume++;
         m_metrics.score_sum_blocked+=verdict.mtf_score;
         m_last=verdict;
         return(false);
        }
     }
   else
      verdict.volume_score=0.5;   // unknown, scored neutrally

   //--- 3. ROOM LEFT.
   //---
   //--- Scored for every strategy, but ENFORCED only where lateness is a
   //--- real risk. A breakout premise puts price at an extreme by
   //--- definition, so refusing it for being at an extreme refuses the
   //--- setup itself. The score still contributes to the composite, so a
   //--- fully extended breakout is rated lower than a fresh one - it is
   //--- simply not vetoed outright.
   const bool breakout_premise=IsBreakoutPremise(strategy_kind);
   double position=0.5;
   if(BarPosition(is_buy,position))
     {
      verdict.bar_position=position;
      verdict.room_score=CMathUtils::Clamp(1.0-position,0.0,1.0);
      if(!breakout_premise && position>m_max_entry_extension)
        {
         verdict.block=SRP_ACCURACY_BLOCK_EXHAUSTED;
         verdict.detail=StringFormat("entry is %.0f%% through the recent "
                                     "range, past the %.0f%% ceiling: most "
                                     "of the move has happened",
                                     position*100.0,
                                     m_max_entry_extension*100.0);
         m_metrics.blocked_exhausted++;
         m_metrics.score_sum_blocked+=verdict.mtf_score;
         m_last=verdict;
         return(false);
        }
     }
   else
      verdict.room_score=0.5;     // unknown, scored neutrally

   //--- 4. COMPOSITE. Normalised by the weights actually in use.
   //---
   //--- For a breakout premise the ROOM component is EXCLUDED from both
   //--- numerator and denominator rather than scored low. Including it would
   //--- reintroduce the same veto through the composite floor: a break of
   //--- structure sits near 1.0 by construction, so its room score is near
   //--- zero, and with a 0.2 weight that alone can drag an otherwise
   //--- perfectly corroborated setup under the floor. Dropping the term is
   //--- the same treatment already given to an unreadable indicator - a
   //--- component that cannot be meaningful is not counted, rather than
   //--- counted as a failure.
   const bool score_room=!breakout_premise;
   const double weight_total=m_weight_mtf+m_weight_volume+
                             (score_room ? m_weight_room : 0.0);
   verdict.total_score=(weight_total>0.0
      ? (verdict.mtf_score*m_weight_mtf +
         verdict.volume_score*m_weight_volume +
         (score_room ? verdict.room_score*m_weight_room : 0.0)) / weight_total
      : 0.0);

   if(verdict.total_score<m_min_total_score)
     {
      verdict.block=SRP_ACCURACY_BLOCK_SCORE;
      verdict.detail=StringFormat("agreement %.2f below floor %.2f "
                                  "(mtf %.2f vol %.2f room %.2f)",
                                  verdict.total_score,m_min_total_score,
                                  verdict.mtf_score,verdict.volume_score,
                                  verdict.room_score);
      m_metrics.blocked_score++;
      m_metrics.score_sum_blocked+=verdict.mtf_score;
      m_last=verdict;
      return(false);
     }

   verdict.allowed=true;
   verdict.block=SRP_ACCURACY_OK;
   verdict.detail=StringFormat("agreement %.2f (mtf %.2f vol x%.2f room "
                               "%.2f, %.0f%% through range)",
                               verdict.total_score,verdict.mtf_score,
                               verdict.relative_volume,verdict.room_score,
                               verdict.bar_position*100.0);
   m_metrics.passed++;
   m_metrics.score_sum_passed+=verdict.mtf_score;
   m_last=verdict;
   return(true);
  }
//+------------------------------------------------------------------+
string CAccuracyFilter::DescribeFunnel(void) const
  {
   if(!m_enabled)
      return("ACCURACY FILTER: disabled");
   if(m_metrics.evaluated<=0)
      return("ACCURACY FILTER: never evaluated");

   const long blocked=m_metrics.evaluated-m_metrics.passed;
   string text=StringFormat("ACCURACY FILTER: %I64d evaluated -> %I64d "
                            "passed (%.1f%%), %I64d refused",
                            m_metrics.evaluated,m_metrics.passed,
                            100.0*m_metrics.passed/m_metrics.evaluated,
                            blocked);
   text+=StringFormat("\n    refused by: MTF_CONFLICT=%I64d VOLUME_THIN=%I64d "
                      "EXHAUSTED=%I64d SCORE=%I64d UNAVAILABLE=%I64d",
                      m_metrics.blocked_mtf,m_metrics.blocked_volume,
                      m_metrics.blocked_exhausted,m_metrics.blocked_score,
                      m_metrics.blocked_unavailable);
   //--- Whether the filter is actually discriminating. If passed and
   //--- blocked populations score the same, it is not, and that should be
   //--- visible rather than inferred from the trade count.
   if(m_metrics.passed>0 && blocked>0)
      text+=StringFormat("\n    mean MTF score: passed %.3f vs refused %.3f",
                         m_metrics.score_sum_passed/m_metrics.passed,
                         m_metrics.score_sum_blocked/blocked);
   return(text);
  }
//+------------------------------------------------------------------+
string CAccuracyFilter::BlockToString(const ENUM_SRP_ACCURACY_BLOCK block)
  {
   switch(block)
     {
      case SRP_ACCURACY_OK:                    return("OK");
      case SRP_ACCURACY_BLOCK_MTF_CONFLICT:    return("MTF_CONFLICT");
      case SRP_ACCURACY_BLOCK_VOLUME_THIN:     return("VOLUME_THIN");
      case SRP_ACCURACY_BLOCK_EXHAUSTED:       return("EXHAUSTED");
      case SRP_ACCURACY_BLOCK_SCORE:           return("LOW_AGREEMENT");
      case SRP_ACCURACY_BLOCK_UNAVAILABLE:     return("DATA_UNAVAILABLE");
      case SRP_ACCURACY_BLOCK_DISABLED:        return("DISABLED");
     }
   return("UNKNOWN");
  }

#endif // SRP_PROFILES_CACCURACYFILTER_MQH
//+------------------------------------------------------------------+
