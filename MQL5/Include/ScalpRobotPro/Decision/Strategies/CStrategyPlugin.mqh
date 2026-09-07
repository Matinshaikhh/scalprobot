//+------------------------------------------------------------------+
//|                                           CStrategyPlugin.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   Abstract base for every strategy plugin. Implements the plumbing so  |
//|   a concrete strategy contains ONLY its entry logic.                  |
//|                                                                  |
//|   THE CONTRACT every plugin fulfils, exactly as specified:            |
//|       BUY / SELL / NO TRADE                                          |
//|       Confidence score  (normalised 0..1, comparable across plugins)  |
//|       Trade reason      (human-readable "why")                        |
//|       Risk rating       (LOW..EXTREME)                                |
//|                                                                  |
//|   Template Method: Evaluate() performs the universal preconditions -   |
//|   enabled, data valid, session and news permitted - then delegates to  |
//|   OnEvaluate(). A plugin author therefore cannot forget a guard, and   |
//|   cannot accidentally trade during a news blackout.                    |
//|                                                                  |
//|   PLUGINS ARE PURE OPINION PROVIDERS. No sizing, no order placement,   |
//|   no stop calculation beyond an optional hint. They read a CONST       |
//|   SDecisionInput and must not mutate it.                              |
//|                                                                  |
//|   BORROWED CONTEXT: the plugin never owns or deletes the context.      |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_STRATEGIES_CSTRATEGYPLUGIN_MQH
#define SRP_DECISION_STRATEGIES_CSTRATEGYPLUGIN_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "CStrategyContext.mqh"

class CStrategyPlugin
  {
protected:
   string                 m_name;
   ENUM_SRP_STRATEGY_KIND m_kind;
   ILogger               *m_logger;       // borrowed
   CStrategyContext      *m_context;      // borrowed
   bool                   m_enabled;
   double                 m_weight;
   //--- A plugin below its minimum confidence returns NO_TRADE rather
   //--- than a weak signal, so marginal setups never reach the voter.
   double                 m_min_confidence;
   //--- Requiring a closed bar is the difference between a stable signal
   //--- and one that flickers intrabar. Default true.
   bool                   m_require_new_bar;

   SStrategySignal        m_last_signal;
   long                   m_evaluations;
   long                   m_signals;
   long                   m_abstentions;

   //--- THE single extension point.
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal)=0;
   //--- Optional hooks with safe defaults.
   virtual bool      OnValidate(SValidationResult &result) { return(true); }

   //--- Fills the boilerplate so no plugin forgets a field. This is why
   //--- every signal in the system is comparably populated.
   void              Emit(SStrategySignal &signal,
                          const SDecisionInput &snapshot,
                          const ENUM_SRP_DECISION decision,
                          const double confidence,
                          const string reason,
                          const ENUM_SRP_RISK_RATING rating) const
     {
      signal.decision      = decision;
      signal.strategy      = m_kind;
      signal.strategy_name = m_name;
      signal.confidence    = CMathUtils::Clamp(confidence,0.0,1.0);
      signal.reason        = reason;
      signal.risk_rating   = rating;
      signal.generated_at  = snapshot.server_time;
      signal.weight        = m_weight;
     }

   //--- Shared helper: converts a 0..1 confidence into a risk rating, so
   //--- ratings mean the same thing across plugins instead of each author
   //--- inventing a scale.
   ENUM_SRP_RISK_RATING RatingFromConfidence(const double confidence) const
     {
      if(confidence>=0.85) return(SRP_RISK_RATING_LOW);
      if(confidence>=0.70) return(SRP_RISK_RATING_MEDIUM);
      if(confidence>=0.55) return(SRP_RISK_RATING_HIGH);
      return(SRP_RISK_RATING_EXTREME);
     }

public:
                     CStrategyPlugin(const string name,
                                     const ENUM_SRP_STRATEGY_KIND kind,
                                     CStrategyContext *context,
                                     ILogger *logger);
   virtual          ~CStrategyPlugin(void) { }

   //--- Configuration ------------------------------------------------
   void              SetEnabled(const bool enabled) { m_enabled=enabled; }
   void              SetWeight(const double weight);
   void              SetMinConfidence(const double minimum);
   void              SetRequireNewBar(const bool require_new_bar)
     { m_require_new_bar=require_new_bar; }

   //--- Template method: universal guards, then delegated logic.
   bool              Evaluate(const SDecisionInput &snapshot,
                              SStrategySignal &signal);
   bool              Validate(SValidationResult &result);

   //--- Identity and diagnostics --------------------------------------
   string                 Name(void)        const { return(m_name); }
   ENUM_SRP_STRATEGY_KIND Kind(void)        const { return(m_kind); }
   bool                   IsEnabled(void)   const { return(m_enabled); }
   double                 Weight(void)      const { return(m_weight); }
   double                 MinConfidence(void) const { return(m_min_confidence); }
   void                   GetLastSignal(SStrategySignal &out) const
     { out=m_last_signal; }
   long                   EvaluationCount(void) const { return(m_evaluations); }
   long                   SignalCount(void)     const { return(m_signals); }
   long                   AbstentionCount(void) const { return(m_abstentions); }
   string                 Describe(void) const;

   static string     DecisionToString(const ENUM_SRP_DECISION decision);
   static string     RatingToString(const ENUM_SRP_RISK_RATING rating);
   static string     KindToString(const ENUM_SRP_STRATEGY_KIND kind);
  };

//+------------------------------------------------------------------+
CStrategyPlugin::CStrategyPlugin(const string name,
                                 const ENUM_SRP_STRATEGY_KIND kind,
                                 CStrategyContext *context,
                                 ILogger *logger)
  : m_name(name),
    m_kind(kind),
    m_logger(logger),
    m_context(context),
    m_enabled(true),
    m_weight(1.0),
    m_min_confidence(0.5),
    m_require_new_bar(true),
    m_evaluations(0),
    m_signals(0),
    m_abstentions(0)
  {
  }
//+------------------------------------------------------------------+
void CStrategyPlugin::SetWeight(const double weight)
  {
   if(weight>=0.0)
      m_weight=weight;
  }
//+------------------------------------------------------------------+
void CStrategyPlugin::SetMinConfidence(const double minimum)
  {
   if(minimum>=0.0 && minimum<=1.0)
      m_min_confidence=minimum;
  }
//+------------------------------------------------------------------+
bool CStrategyPlugin::Evaluate(const SDecisionInput &snapshot,
                               SStrategySignal &signal)
  {
   signal.Reset();
   signal.strategy=m_kind;
   signal.strategy_name=m_name;
   signal.weight=m_weight;
   m_evaluations++;

   //--- UNIVERSAL GUARDS. Centralised here so no plugin can omit one.

   //--- 1. Disabled plugins abstain silently.
   if(!m_enabled)
     {
      m_abstentions++;
      return(false);
     }

   //--- 2. Bad or incomplete market data.
   if(!snapshot.is_valid || m_context==NULL)
     {
      m_abstentions++;
      return(false);
     }

   //--- 3. Session and news. A plugin must never be able to trade through
   //--- a blackout by forgetting to check, so the base enforces it.
   if(!snapshot.session.trading_permitted || !snapshot.news.trading_permitted)
     {
      m_abstentions++;
      return(false);
     }

   //--- 4. Bar-close discipline. Evaluating mid-bar produces signals that
   //--- appear and vanish as the bar forms.
   if(m_require_new_bar && !snapshot.is_new_bar)
     {
      m_abstentions++;
      return(false);
     }

   //--- Delegate to the plugin's own logic.
   if(!OnEvaluate(snapshot,signal))
     {
      m_abstentions++;
      m_last_signal=signal;
      return(false);
     }

   //--- 5. CONFIDENCE FLOOR. A weak signal is worse than none, because it
   //--- still consumes a trade slot and dilutes the vote.
   if(signal.IsActionable() && signal.confidence<m_min_confidence)
     {
      signal.decision=SRP_DECISION_NO_TRADE;
      signal.reason=StringFormat("%s (confidence %.2f below floor %.2f)",
                                 signal.reason,signal.confidence,
                                 m_min_confidence);
      m_abstentions++;
      m_last_signal=signal;
      return(false);
     }

   m_last_signal=signal;
   if(signal.IsActionable())
     {
      m_signals++;
      return(true);
     }
   m_abstentions++;
   return(false);
  }
//+------------------------------------------------------------------+
bool CStrategyPlugin::Validate(SValidationResult &result)
  {
   if(m_context==NULL)
     {
      result.AddError(m_name+": no strategy context injected");
      return(false);
     }
   if(m_weight<0.0)
     {
      result.AddError(m_name+": negative weight");
      return(false);
     }
   if(m_min_confidence>0.95)
      result.AddWarning(m_name+": confidence floor above 0.95 will "
                        "suppress nearly every signal");
   return(OnValidate(result));
  }
//+------------------------------------------------------------------+
string CStrategyPlugin::DecisionToString(const ENUM_SRP_DECISION decision)
  {
   switch(decision)
     {
      case SRP_DECISION_BUY:  return("BUY");
      case SRP_DECISION_SELL: return("SELL");
     }
   return("NO_TRADE");
  }
//+------------------------------------------------------------------+
string CStrategyPlugin::RatingToString(const ENUM_SRP_RISK_RATING rating)
  {
   switch(rating)
     {
      case SRP_RISK_RATING_LOW:     return("LOW");
      case SRP_RISK_RATING_MEDIUM:  return("MEDIUM");
      case SRP_RISK_RATING_HIGH:    return("HIGH");
      case SRP_RISK_RATING_EXTREME: return("EXTREME");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CStrategyPlugin::KindToString(const ENUM_SRP_STRATEGY_KIND kind)
  {
   switch(kind)
     {
      case SRP_STRAT_EMA_CROSS:              return("EmaCross");
      case SRP_STRAT_VWAP_PULLBACK:          return("VwapPullback");
      case SRP_STRAT_LIQUIDITY_SWEEP:        return("LiquiditySweep");
      case SRP_STRAT_ORDER_BLOCK:            return("OrderBlock");
      case SRP_STRAT_FAIR_VALUE_GAP:         return("FairValueGap");
      case SRP_STRAT_MOMENTUM_SCALP:         return("MomentumScalp");
      case SRP_STRAT_OPENING_RANGE_BREAKOUT: return("OpeningRangeBreakout");
      case SRP_STRAT_TREND_CONTINUATION:     return("TrendContinuation");
      case SRP_STRAT_MEAN_REVERSION:         return("MeanReversion");
      case SRP_STRAT_BREAKOUT:               return("Breakout");
      case SRP_STRAT_BREAK_OF_STRUCTURE:     return("BreakOfStructure");
      case SRP_STRAT_VOLATILITY_BREAKOUT:    return("VolatilityBreakout");
      case SRP_STRAT_ORDER_FLOW:             return("OrderFlow");
     }
   return("Unknown");
  }
//+------------------------------------------------------------------+
string CStrategyPlugin::Describe(void) const
  {
   return(StringFormat("%s: %s w=%.2f floor=%.2f | eval=%I64d signals=%I64d "
                       "abstain=%I64d | last=%s(%.2f)",
                       m_name,
                       (m_enabled ? "on" : "off"),
                       m_weight,m_min_confidence,
                       m_evaluations,m_signals,m_abstentions,
                       DecisionToString(m_last_signal.decision),
                       m_last_signal.confidence));
  }

#endif // SRP_DECISION_STRATEGIES_CSTRATEGYPLUGIN_MQH
//+------------------------------------------------------------------+
