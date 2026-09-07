//+------------------------------------------------------------------+
//|                                            CRegimeEngine.mqh |
//|            Scalping Robot Pro - Regime & Volatility Engine (P6) |
//|                                                                  |
//|   RESPONSIBILITY (one only): classify the market into a regime and a   |
//|   volatility class, using THIS asset's thresholds, and report which    |
//|   strategies that combination permits.                               |
//|                                                                  |
//|   WHY IT EXISTS                                                      |
//|   Before Phase 6, every enabled strategy was polled on every pass and  |
//|   the results were voted on. That means a mean-reversion strategy got  |
//|   a vote during a violent trend, and a breakout strategy got one in a  |
//|   dead range. The vote can outweigh the fact that a strategy's premise |
//|   is absent. Gating by regime removes those opinions before they are   |
//|   counted rather than hoping the vote dilutes them.                   |
//|                                                                  |
//|   THRESHOLDS ARE PER-ASSET, NOT GLOBAL. Gold whipsaws, so it demands   |
//|   a higher ADX before "trend" is believed; an index at 20,000 has a    |
//|   much smaller ATR as a share of price than gold does, so the          |
//|   volatility bands differ by an order of magnitude. Both come from     |
//|   SMarketProfile, so neither asset can silently inherit the other's.   |
//|                                                                  |
//|   IT CLASSIFIES AND NOTHING ELSE. No sizing, no orders, no drawing.    |
//|   A caller asks "what regime is this and may strategy X run", and      |
//|   acts on the answer itself.                                         |
//|                                                                  |
//|   MULTI-TIMEFRAME BY CONSTRUCTION. Regime is read from the CONTEXT     |
//|   timeframe (M15 by default), never from the execution timeframe: an   |
//|   M1 reading of "trend" is noise. All bar access starts at shift 1 -   |
//|   the last CLOSED bar - so a forming candle can never repaint a        |
//|   decision. See the ReadClosed* helpers.                             |
//+------------------------------------------------------------------+
#ifndef SRP_PROFILES_CREGIMEENGINE_MQH
#define SRP_PROFILES_CREGIMEENGINE_MQH

#include "CMarketProfile.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Intelligence/Indicators/CStandardIndicators.mqh"
#include "../Intelligence/Structure/CMarketStructure.mqh"
#include "../Utilities/CMathUtils.mqh"

//+------------------------------------------------------------------+
//| The seven regimes Part 7 requires.                                 |
//+------------------------------------------------------------------+
enum ENUM_SRP_REGIME
  {
   SRP_REGIME_UNDEFINED,        // not enough data yet
   SRP_REGIME_TREND,            // directional and sustained
   SRP_REGIME_RANGE,            // contained, no directional edge
   SRP_REGIME_BREAKOUT,         // range being left with expansion
   SRP_REGIME_HIGH_VOLATILITY,  // moving, but too wildly to trust
   SRP_REGIME_LOW_VOLATILITY,   // too quiet to pay the spread
   SRP_REGIME_REVERSAL,         // character change against the trend
   SRP_REGIME_TRANSITION        // between states; nothing is reliable
  };

//+------------------------------------------------------------------+
//| Volatility class, per Part 13.                                     |
//+------------------------------------------------------------------+
enum ENUM_SRP_VOL_CLASS
  {
   SRP_VOL_UNDEFINED,
   SRP_VOL_LOW,
   SRP_VOL_NORMAL,
   SRP_VOL_HIGH,
   SRP_VOL_EXTREME
  };

//+------------------------------------------------------------------+
//| Which strategy is being asked about. Mirrors the plugin set so the  |
//| permission table can be explicit rather than string-matched.        |
//+------------------------------------------------------------------+
enum ENUM_SRP_STRAT_SLOT
  {
   SRP_SLOT_EMA_CROSS,
   SRP_SLOT_TREND_CONTINUATION,
   SRP_SLOT_MOMENTUM,
   SRP_SLOT_LIQUIDITY_SWEEP,
   SRP_SLOT_ORDER_BLOCK,
   SRP_SLOT_FVG,
   SRP_SLOT_VWAP_PULLBACK,
   SRP_SLOT_OPENING_RANGE,
   SRP_SLOT_MEAN_REVERSION,
   SRP_SLOT_BREAKOUT,
   SRP_SLOT_BOS,
   SRP_SLOT_VOLATILITY_BREAKOUT,
   SRP_SLOT_ORDER_FLOW,
   SRP_SLOT_COUNT
  };

//+------------------------------------------------------------------+
//| The complete classification for one pass.                          |
//+------------------------------------------------------------------+
struct SRegimeState
  {
   bool                  valid;
   ENUM_SRP_REGIME       regime;
   ENUM_SRP_VOL_CLASS    volatility;
   //--- Raw measurements, kept so a decision can be explained rather
   //--- than merely reported.
   double                adx;
   double                plus_di;
   double                minus_di;
   double                atr;
   double                atr_percent;      // ATR as % of price
   double                expansion_ratio;  // current ATR vs its average
   double                range_position;   // 0..1 within the recent range
   bool                  bullish_bias;
   bool                  bearish_bias;
   //--- Trading permission derived from the classification.
   bool                  trading_allowed;
   string                block_reason;
   //--- Risk adaptation, per Part 13.
   double                risk_multiplier;  // scales position size
   double                stop_multiplier;  // scales stop distance
   double                confidence_bonus; // added to the required floor
   string                detail;
   datetime              evaluated_at;

                     SRegimeState(void) { Reset(); }
   void              Reset(void)
     {
      valid=false;
      regime=SRP_REGIME_UNDEFINED;
      volatility=SRP_VOL_UNDEFINED;
      adx=0.0; plus_di=0.0; minus_di=0.0;
      atr=0.0; atr_percent=0.0; expansion_ratio=0.0; range_position=0.5;
      bullish_bias=false; bearish_bias=false;
      trading_allowed=false; block_reason="not evaluated";
      risk_multiplier=1.0; stop_multiplier=1.0; confidence_bonus=0.0;
      detail=""; evaluated_at=0;
     }
  };

//+------------------------------------------------------------------+
class CRegimeEngine
  {
private:
   ILogger              *m_logger;          // borrowed
   string                m_symbol;
   SMarketProfile        m_profile;         // this asset's thresholds

   //--- Borrowed analysis inputs. The engine reads them, never owns them.
   CAdxIntel            *m_adx_context;     // on the CONTEXT timeframe
   CAtrIntel            *m_atr_context;
   CMarketStructure     *m_structure;

   ENUM_TIMEFRAMES       m_context_tf;
   SRegimeState          m_state;
   datetime              m_cached_bar;      // recompute once per context bar
   long                  m_evaluations;
   long                  m_blocks;
   //--- How many context bars were spent in each regime and volatility
   //--- class. Without this, a run that traded rarely cannot be explained:
   //--- "the gate was closed" and "the gate was open but no setup formed"
   //--- look identical from the outside.
   long                  m_regime_bars[8];
   long                  m_vol_bars[5];

   //--- Bar reads, ALWAYS from the last closed bar. See the class note.
   bool              ReadClosedRange(const int bars,double &high,double &low) const;
   bool              ReadAtrAverage(const int bars,double &average) const;

   ENUM_SRP_VOL_CLASS ClassifyVolatility(const double atr_percent) const;
   ENUM_SRP_REGIME   ClassifyRegime(SRegimeState &state) const;
   void              ApplyAdaptation(SRegimeState &state) const;

public:
                     CRegimeEngine(const string symbol,ILogger *logger);
                    ~CRegimeEngine(void) { }

   void              SetProfile(const SMarketProfile &profile);
   //--- Both indicators MUST be built on the context timeframe. Passing
   //--- execution-timeframe indicators would classify noise as regime.
   void              SetContextIndicators(CAdxIntel *adx,CAtrIntel *atr);
   void              SetStructure(CMarketStructure *structure);

   bool              Initialize(void);
   void              Validate(SValidationResult &result) const;

   //--- Recomputes at most once per context bar: regime does not change
   //--- within an M15 candle, so calling this every tick is nearly free.
   bool              Evaluate(const datetime now,const bool force=false);

   void              GetState(SRegimeState &out) const { out=m_state; }
   ENUM_SRP_REGIME   Regime(void) const     { return(m_state.regime); }
   ENUM_SRP_VOL_CLASS Volatility(void) const{ return(m_state.volatility); }
   bool              TradingAllowed(void) const { return(m_state.trading_allowed); }

   //--- THE GATE. Answers "may this strategy run in this regime".
   bool              Permits(const ENUM_SRP_STRAT_SLOT slot) const;
   //--- Names every strategy the current regime permits, for diagnostics.
   string            DescribePermissions(void) const;
   //--- Share of context bars spent in each regime and volatility class.
   //--- The answer to "why did it trade so rarely".
   string            DescribeDistribution(void) const;

   long              EvaluationCount(void) const { return(m_evaluations); }
   long              BlockCount(void) const { return(m_blocks); }
   string            Describe(void) const;

   static string     RegimeToString(const ENUM_SRP_REGIME regime);
   static string     VolatilityToString(const ENUM_SRP_VOL_CLASS vol);
   static string     SlotToString(const ENUM_SRP_STRAT_SLOT slot);
   //--- Static so the permission table can be asserted by a harness
   //--- without constructing indicators.
   static bool       RegimePermits(const ENUM_SRP_REGIME regime,
                                   const ENUM_SRP_STRAT_SLOT slot);
  };

//+------------------------------------------------------------------+
CRegimeEngine::CRegimeEngine(const string symbol,ILogger *logger)
  : m_logger(logger),
    m_symbol(symbol),
    m_adx_context(NULL),
    m_atr_context(NULL),
    m_structure(NULL),
    m_context_tf(PERIOD_M15),
    m_cached_bar(0),
    m_evaluations(0),
    m_blocks(0)
  {
   m_profile.Reset();
   ArrayInitialize(m_regime_bars,0);
   ArrayInitialize(m_vol_bars,0);
  }
//+------------------------------------------------------------------+
void CRegimeEngine::SetProfile(const SMarketProfile &profile)
  {
   m_profile=profile;
   m_context_tf=profile.context_timeframe;
  }
//+------------------------------------------------------------------+
void CRegimeEngine::SetContextIndicators(CAdxIntel *adx,CAtrIntel *atr)
  {
   m_adx_context=adx;
   m_atr_context=atr;
  }
//+------------------------------------------------------------------+
void CRegimeEngine::SetStructure(CMarketStructure *structure)
  {
   m_structure=structure;
  }
//+------------------------------------------------------------------+
bool CRegimeEngine::Initialize(void)
  {
   m_state.Reset();
   m_cached_bar=0;
   //--- The engine is usable with only ADX and ATR; structure adds the
   //--- reversal and breakout refinement but is not required.
   return(m_adx_context!=NULL && m_atr_context!=NULL);
  }
//+------------------------------------------------------------------+
void CRegimeEngine::Validate(SValidationResult &result) const
  {
   if(m_adx_context==NULL)
      result.AddError("CRegimeEngine: no context ADX, regime cannot be classified");
   if(m_atr_context==NULL)
      result.AddError("CRegimeEngine: no context ATR, volatility cannot be classified");
   if(m_structure==NULL)
      result.AddWarning("CRegimeEngine: no market structure, reversal and "
                        "breakout detection will be less precise");
   if(m_profile.atr_low_percent>=m_profile.atr_high_percent)
      result.AddError("CRegimeEngine: volatility bands are inverted");
   if(m_profile.range_adx_threshold>=m_profile.trend_adx_threshold)
      result.AddError("CRegimeEngine: range ADX threshold is not below the "
                      "trend threshold");
  }
//+------------------------------------------------------------------+
//| CLOSED-BAR RANGE. Starts at shift 1 so the forming bar is excluded.  |
//|                                                                  |
//| Using shift 0 here would be a repainting bug: the current bar's high  |
//| and low grow as it forms, so a range position computed from it would  |
//| change value for the same historical moment.                         |
//+------------------------------------------------------------------+
bool CRegimeEngine::ReadClosedRange(const int bars,double &high,double &low) const
  {
   high=0.0; low=0.0;
   if(bars<2)
      return(false);

   double highs[],lows[];
   //--- start_pos 1 == last CLOSED bar.
   if(CopyHigh(m_symbol,m_context_tf,1,bars,highs)!=bars)
      return(false);
   if(CopyLow(m_symbol,m_context_tf,1,bars,lows)!=bars)
      return(false);

   high=highs[0];
   low=lows[0];
   for(int i=1;i<bars;i++)
     {
      if(highs[i]>high) high=highs[i];
      if(lows[i]<low)   low=lows[i];
     }
   return(high>low);
  }
//+------------------------------------------------------------------+
//| Average ATR over recent CLOSED bars, for the expansion ratio.        |
//+------------------------------------------------------------------+
bool CRegimeEngine::ReadAtrAverage(const int bars,double &average) const
  {
   average=0.0;
   if(m_atr_context==NULL || bars<2)
      return(false);

   double sum=0.0;
   int counted=0;
   //--- shift 1 upward: never the forming bar.
   for(int shift=1;shift<=bars;shift++)
     {
      double value=0.0;
      if(!m_atr_context.ValueAt(0,shift,value) || value<=0.0)
         continue;
      sum+=value;
      counted++;
     }
   if(counted<2)
      return(false);
   average=sum/(double)counted;
   return(average>0.0);
  }
//+------------------------------------------------------------------+
ENUM_SRP_VOL_CLASS CRegimeEngine::ClassifyVolatility(const double atr_percent) const
  {
   if(atr_percent<=0.0)
      return(SRP_VOL_UNDEFINED);
   if(atr_percent<m_profile.atr_low_percent)
      return(SRP_VOL_LOW);
   if(atr_percent>=m_profile.atr_extreme_percent)
      return(SRP_VOL_EXTREME);
   if(atr_percent>=m_profile.atr_high_percent)
      return(SRP_VOL_HIGH);
   return(SRP_VOL_NORMAL);
  }
//+------------------------------------------------------------------+
//| REGIME CLASSIFICATION.                                             |
//|                                                                  |
//| Order is deliberate and is the design. Volatility extremes are        |
//| decided FIRST because they override everything: a "trend" in extreme  |
//| volatility is not a tradeable trend, it is a market in dislocation,   |
//| and treating it as a trend is how a scalper gets run over.            |
//+------------------------------------------------------------------+
ENUM_SRP_REGIME CRegimeEngine::ClassifyRegime(SRegimeState &state) const
  {
   //--- 1. Extremes first: they invalidate any structural read.
   if(state.volatility==SRP_VOL_EXTREME)
      return(SRP_REGIME_HIGH_VOLATILITY);
   if(state.volatility==SRP_VOL_LOW)
      return(SRP_REGIME_LOW_VOLATILITY);

   //--- 2. Expansion out of contraction is a breakout, and it outranks
   //--- the ADX read because ADX lags a fresh expansion badly.
   const bool expanding=(state.expansion_ratio>=
                         m_profile.breakout_expansion_ratio);
   //--- Near a range extreme, expanding: price is leaving the range.
   const bool at_edge=(state.range_position>0.80 ||
                       state.range_position<0.20);
   if(expanding && at_edge)
      return(SRP_REGIME_BREAKOUT);

   //--- 3. Structural character change against the prevailing direction.
   if(m_structure!=NULL)
     {
      const ENUM_SRP_STRUCTURE_EVENT event=m_structure.LastEvent();
      if(event==SRP_STRUCT_CHOCH_BULLISH || event==SRP_STRUCT_CHOCH_BEARISH)
         return(SRP_REGIME_REVERSAL);
     }

   //--- 4. Directional strength.
   if(state.adx>=m_profile.trend_adx_threshold)
     {
      //--- High volatility with direction is still a trend, but the
      //--- adaptation step will shrink risk for it.
      return(SRP_REGIME_TREND);
     }

   //--- 5. Contained and directionless.
   if(state.adx<m_profile.range_adx_threshold)
      return(SRP_REGIME_RANGE);

   //--- 6. Between range and trend: nothing is reliable here, and
   //--- pretending otherwise is where marginal trades come from.
   return(SRP_REGIME_TRANSITION);
  }
//+------------------------------------------------------------------+
//| RISK ADAPTATION, per Part 13.                                      |
//|                                                                  |
//| Volatility changes how much a given stop distance costs and how          |
//| likely it is to be touched by noise. Rather than re-tuning parameters   |
//| per session, the engine reports multipliers the risk layer applies.     |
//|                                                                  |
//| Extreme volatility REDUCES risk or blocks entirely - it never          |
//| increases size. That direction is not negotiable.                     |
//+------------------------------------------------------------------+
void CRegimeEngine::ApplyAdaptation(SRegimeState &state) const
  {
   state.risk_multiplier=1.0;
   state.stop_multiplier=1.0;
   state.confidence_bonus=0.0;
   state.trading_allowed=true;
   state.block_reason="";

   switch(state.volatility)
     {
      case SRP_VOL_EXTREME:
         //--- Dislocation. Spreads widen, slippage becomes unpredictable
         //--- and stops are hit on noise. Stand aside.
         state.trading_allowed=false;
         state.block_reason=StringFormat(
            "extreme volatility: ATR %.3f%% of price exceeds the %.3f%% "
            "ceiling for this asset",
            state.atr_percent,m_profile.atr_extreme_percent);
         state.risk_multiplier=0.0;
         break;

      case SRP_VOL_HIGH:
         //--- Tradeable, but on a smaller footprint with a wider stop and
         //--- a higher bar for entry.
         state.risk_multiplier=0.60;
         state.stop_multiplier=1.30;
         state.confidence_bonus=0.05;
         break;

      case SRP_VOL_LOW:
         //--- The move is unlikely to cover the spread and the target.
         state.trading_allowed=false;
         state.block_reason=StringFormat(
            "volatility too low: ATR %.3f%% of price is below the %.3f%% "
            "floor, a scalp would not clear costs",
            state.atr_percent,m_profile.atr_low_percent);
         state.risk_multiplier=0.0;
         break;

      case SRP_VOL_NORMAL:
         break;

      default:
         state.trading_allowed=false;
         state.block_reason="volatility could not be classified";
         state.risk_multiplier=0.0;
         break;
     }

   //--- Regime-level adjustment on top of the volatility class.
   if(state.trading_allowed)
      switch(state.regime)
        {
         case SRP_REGIME_TRANSITION:
            //--- Not blocked outright: a genuine setup can still appear.
            //--- But it must clear a higher bar on a smaller size.
            state.risk_multiplier*=0.70;
            state.confidence_bonus+=0.05;
            break;
         case SRP_REGIME_REVERSAL:
            //--- Reversals are real but the highest-variance entries.
            state.risk_multiplier*=0.80;
            state.confidence_bonus+=0.03;
            break;
         case SRP_REGIME_UNDEFINED:
            state.trading_allowed=false;
            state.block_reason="regime undefined, insufficient data";
            state.risk_multiplier=0.0;
            break;
         default:
            break;
        }
  }
//+------------------------------------------------------------------+
bool CRegimeEngine::Evaluate(const datetime now,const bool force)
  {
   if(m_adx_context==NULL || m_atr_context==NULL)
     {
      m_state.Reset();
      m_state.block_reason="regime engine not wired";
      return(false);
     }

   //--- Cache per context bar. Regime does not change inside an M15
   //--- candle, and this sits on the hot path.
   const datetime bar=iTime(m_symbol,m_context_tf,0);
   if(!force && bar==m_cached_bar && m_state.valid)
      return(true);

   m_evaluations++;
   SRegimeState state;
   state.evaluated_at=now;

   //--- ADX from the last CLOSED context bar. Shift 1, never 0.
   if(!m_adx_context.Main(1,state.adx))
     {
      m_state=state;
      m_state.block_reason="context ADX unavailable";
      return(false);
     }
   m_adx_context.PlusDi(1,state.plus_di);
   m_adx_context.MinusDi(1,state.minus_di);
   state.bullish_bias=(state.plus_di>state.minus_di);
   state.bearish_bias=(state.minus_di>state.plus_di);

   //--- ATR from the last closed bar, and as a share of price so the
   //--- figure is comparable across instruments.
   if(!m_atr_context.ValueAt(0,1,state.atr) || state.atr<=0.0)
     {
      m_state=state;
      m_state.block_reason="context ATR unavailable";
      return(false);
     }
   const double price=SymbolInfoDouble(m_symbol,SYMBOL_BID);
   if(price>0.0)
      state.atr_percent=state.atr/price*100.0;

   //--- Expansion: current ATR against its own recent average. This is
   //--- what distinguishes a breakout from a drift.
   double atr_average=0.0;
   if(ReadAtrAverage(20,atr_average) && atr_average>0.0)
      state.expansion_ratio=state.atr/atr_average;
   else
      state.expansion_ratio=1.0;

   //--- Where price sits inside the recent closed range.
   double high=0.0,low=0.0;
   if(ReadClosedRange(20,high,low) && high>low && price>0.0)
      state.range_position=CMathUtils::Clamp((price-low)/(high-low),0.0,1.0);

   //--- Classify, then adapt.
   state.volatility=ClassifyVolatility(state.atr_percent);
   state.regime=ClassifyRegime(state);
   ApplyAdaptation(state);
   state.valid=true;

   state.detail=StringFormat("%s / %s | ADX %.1f (%s) ATR %.3f%% exp %.2fx "
                             "pos %.2f",
                             RegimeToString(state.regime),
                             VolatilityToString(state.volatility),
                             state.adx,
                             (state.bullish_bias ? "bull"
                              : (state.bearish_bias ? "bear" : "flat")),
                             state.atr_percent,state.expansion_ratio,
                             state.range_position);

   if(!state.trading_allowed)
      m_blocks++;

   //--- Histogram, counted once per context bar because the cache above
   //--- means this line is reached once per bar rather than once per tick.
   const int rslot=(int)state.regime;
   if(rslot>=0 && rslot<ArraySize(m_regime_bars))
      m_regime_bars[rslot]++;
   const int vslot=(int)state.volatility;
   if(vslot>=0 && vslot<ArraySize(m_vol_bars))
      m_vol_bars[vslot]++;

   m_state=state;
   m_cached_bar=bar;
   return(true);
  }
//+------------------------------------------------------------------+
//| REGIME DISTRIBUTION over the run.                                  |
//|                                                                  |
//| This is what makes a low trade count explainable. A run that spent    |
//| 80% of its bars in LOW_VOLATILITY was never going to trade much, and  |
//| that is a fact about the market and the thresholds rather than a bug.  |
//+------------------------------------------------------------------+
string CRegimeEngine::DescribeDistribution(void) const
  {
   long total=0;
   for(int i=0;i<ArraySize(m_regime_bars);i++)
      total+=m_regime_bars[i];
   if(total<=0)
      return("regime distribution: no context bars classified");

   string text=StringFormat("regime distribution over %I64d context bars:",
                            total);
   for(int i=0;i<ArraySize(m_regime_bars);i++)
      if(m_regime_bars[i]>0)
         text+=StringFormat(" %s=%.1f%%",
                            RegimeToString((ENUM_SRP_REGIME)i),
                            (double)m_regime_bars[i]/(double)total*100.0);

   text+="\n  volatility:";
   for(int i=0;i<ArraySize(m_vol_bars);i++)
      if(m_vol_bars[i]>0)
         text+=StringFormat(" %s=%.1f%%",
                            VolatilityToString((ENUM_SRP_VOL_CLASS)i),
                            (double)m_vol_bars[i]/(double)total*100.0);
   return(text);
  }
//+------------------------------------------------------------------+
//| THE PERMISSION TABLE.                                              |
//|                                                                  |
//| Static and pure, so a harness can assert every cell without building  |
//| indicators. This is the table Part 7 asks for, made explicit rather   |
//| than emerging from scattered conditionals.                            |
//|                                                                  |
//| The principle: a strategy runs only where its PREMISE exists. Mean     |
//| reversion assumes a level will hold, which is false in a breakout.    |
//| Breakout logic assumes range containment is ending, which is false     |
//| mid-range. Running them anyway and letting a vote sort it out means    |
//| counting opinions that were never valid.                              |
//+------------------------------------------------------------------+
bool CRegimeEngine::RegimePermits(const ENUM_SRP_REGIME regime,
                                  const ENUM_SRP_STRAT_SLOT slot)
  {
   switch(regime)
     {
      //--- Directional and sustained: continuation and momentum.
      case SRP_REGIME_TREND:
         return(slot==SRP_SLOT_TREND_CONTINUATION ||
                slot==SRP_SLOT_MOMENTUM           ||
                slot==SRP_SLOT_EMA_CROSS          ||
                slot==SRP_SLOT_ORDER_BLOCK        ||
                slot==SRP_SLOT_FVG                ||
                slot==SRP_SLOT_VWAP_PULLBACK      ||
                slot==SRP_SLOT_BOS                ||
                slot==SRP_SLOT_ORDER_FLOW);

      //--- Contained: fade the edges, hunt stops at the extremes.
      case SRP_REGIME_RANGE:
         return(slot==SRP_SLOT_MEAN_REVERSION ||
                slot==SRP_SLOT_LIQUIDITY_SWEEP||
                slot==SRP_SLOT_ORDER_BLOCK    ||
                slot==SRP_SLOT_VWAP_PULLBACK);

      //--- Leaving the range with expansion.
      case SRP_REGIME_BREAKOUT:
         return(slot==SRP_SLOT_BREAKOUT            ||
                slot==SRP_SLOT_VOLATILITY_BREAKOUT ||
                slot==SRP_SLOT_OPENING_RANGE       ||
                slot==SRP_SLOT_MOMENTUM            ||
                slot==SRP_SLOT_BOS                 ||
                slot==SRP_SLOT_ORDER_FLOW);

      //--- Character change: sweeps and structure breaks lead. Order flow
      //--- belongs here too - a volume-backed divergence (price making a
      //--- new extreme while cumulative flow does not confirm it) is one
      //--- of the earliest tells that a reversal is starting.
      case SRP_REGIME_REVERSAL:
         return(slot==SRP_SLOT_LIQUIDITY_SWEEP ||
                slot==SRP_SLOT_BOS             ||
                slot==SRP_SLOT_ORDER_BLOCK     ||
                slot==SRP_SLOT_FVG             ||
                slot==SRP_SLOT_ORDER_FLOW);

      //--- Moving too wildly to trust structure, but a strong sweep or
      //--- an expansion break can still be valid on reduced size. Order
      //--- flow is participation-gated by its own relative-volume floor,
      //--- so it does not need the structural premise the excluded
      //--- strategies rely on.
      case SRP_REGIME_HIGH_VOLATILITY:
         return(slot==SRP_SLOT_LIQUIDITY_SWEEP ||
                slot==SRP_SLOT_VOLATILITY_BREAKOUT ||
                slot==SRP_SLOT_ORDER_FLOW);

      //--- Too quiet to pay the spread. Nothing runs.
      case SRP_REGIME_LOW_VOLATILITY:
         return(false);

      //--- Between states. Only the highest-conviction structural
      //--- setups, and the adaptation step already shrank their size.
      case SRP_REGIME_TRANSITION:
         return(slot==SRP_SLOT_ORDER_BLOCK ||
                slot==SRP_SLOT_LIQUIDITY_SWEEP);

      default:
         return(false);
     }
  }
//+------------------------------------------------------------------+
bool CRegimeEngine::Permits(const ENUM_SRP_STRAT_SLOT slot) const
  {
   //--- An unevaluated or blocked market permits nothing. Failing closed
   //--- is the only safe default for a gate.
   if(!m_state.valid || !m_state.trading_allowed)
      return(false);
   return(RegimePermits(m_state.regime,slot));
  }
//+------------------------------------------------------------------+
string CRegimeEngine::DescribePermissions(void) const
  {
   if(!m_state.valid)
      return("regime not evaluated: nothing permitted");
   if(!m_state.trading_allowed)
      return("blocked ("+m_state.block_reason+"): nothing permitted");

   string text="permitted:";
   bool any=false;
   for(int i=0;i<(int)SRP_SLOT_COUNT;i++)
      if(RegimePermits(m_state.regime,(ENUM_SRP_STRAT_SLOT)i))
        {
         text+=" "+SlotToString((ENUM_SRP_STRAT_SLOT)i);
         any=true;
        }
   if(!any)
      text+=" none";
   return(text);
  }
//+------------------------------------------------------------------+
string CRegimeEngine::RegimeToString(const ENUM_SRP_REGIME regime)
  {
   switch(regime)
     {
      case SRP_REGIME_TREND:           return("TREND");
      case SRP_REGIME_RANGE:           return("RANGE");
      case SRP_REGIME_BREAKOUT:        return("BREAKOUT");
      case SRP_REGIME_HIGH_VOLATILITY: return("HIGH_VOLATILITY");
      case SRP_REGIME_LOW_VOLATILITY:  return("LOW_VOLATILITY");
      case SRP_REGIME_REVERSAL:        return("REVERSAL");
      case SRP_REGIME_TRANSITION:      return("TRANSITION");
     }
   return("UNDEFINED");
  }
//+------------------------------------------------------------------+
string CRegimeEngine::VolatilityToString(const ENUM_SRP_VOL_CLASS vol)
  {
   switch(vol)
     {
      case SRP_VOL_LOW:     return("LOW");
      case SRP_VOL_NORMAL:  return("NORMAL");
      case SRP_VOL_HIGH:    return("HIGH");
      case SRP_VOL_EXTREME: return("EXTREME");
     }
   return("UNDEFINED");
  }
//+------------------------------------------------------------------+
string CRegimeEngine::SlotToString(const ENUM_SRP_STRAT_SLOT slot)
  {
   switch(slot)
     {
      case SRP_SLOT_EMA_CROSS:           return("EmaCross");
      case SRP_SLOT_TREND_CONTINUATION:  return("TrendContinuation");
      case SRP_SLOT_MOMENTUM:            return("Momentum");
      case SRP_SLOT_LIQUIDITY_SWEEP:     return("LiquiditySweep");
      case SRP_SLOT_ORDER_BLOCK:         return("OrderBlock");
      case SRP_SLOT_FVG:                 return("FairValueGap");
      case SRP_SLOT_VWAP_PULLBACK:       return("VwapPullback");
      case SRP_SLOT_OPENING_RANGE:       return("OpeningRange");
      case SRP_SLOT_MEAN_REVERSION:      return("MeanReversion");
      case SRP_SLOT_BREAKOUT:            return("Breakout");
      case SRP_SLOT_BOS:                 return("BreakOfStructure");
      case SRP_SLOT_VOLATILITY_BREAKOUT: return("VolatilityBreakout");
      case SRP_SLOT_ORDER_FLOW:          return("OrderFlow");
     }
   return("Unknown");
  }
//+------------------------------------------------------------------+
string CRegimeEngine::Describe(void) const
  {
   string text=StringFormat("regime engine [%s %s]: %s",
                            m_profile.name,EnumToString(m_context_tf),
                            (m_state.valid ? m_state.detail : "not evaluated"));
   text+=StringFormat(" | eval=%I64d blocks=%I64d",m_evaluations,m_blocks);
   if(!m_state.trading_allowed && m_state.block_reason!="")
      text+=" | BLOCKED: "+m_state.block_reason;
   else
      if(m_state.risk_multiplier!=1.0 || m_state.stop_multiplier!=1.0)
         text+=StringFormat(" | risk x%.2f stop x%.2f conf +%.2f",
                            m_state.risk_multiplier,m_state.stop_multiplier,
                            m_state.confidence_bonus);
   return(text);
  }

#endif // SRP_PROFILES_CREGIMEENGINE_MQH
//+------------------------------------------------------------------+
