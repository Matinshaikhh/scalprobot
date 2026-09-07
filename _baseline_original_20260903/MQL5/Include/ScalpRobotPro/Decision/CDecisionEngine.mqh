//+------------------------------------------------------------------+
//|                                           CDecisionEngine.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   RESPONSIBILITY (one only): sequence the decision pipeline and         |
//|   produce ONE STradeDecision. It contains no trading rules - every      |
//|   rule lives in a plugin, a confirmation check, the session manager or  |
//|   the news engine.                                                    |
//|                                                                  |
//|   THE PIPELINE                                                       |
//|     1  session   may we trade at this moment at all?                   |
//|     2  news      is a high-impact release too close?                   |
//|     3  build     assemble the immutable SDecisionInput                 |
//|     4  poll      collect an opinion from every enabled plugin          |
//|     5  vote      collapse the opinions into one direction              |
//|     6  confirm   score that direction against 13 checks               |
//|     7  blend     strategy conviction x confirmation confidence         |
//|                                                                  |
//|   Session and news are checked FIRST, before any indicator is read or   |
//|   plugin polled. On a weekend or inside an FOMC blackout the entire     |
//|   pipeline costs two comparisons.                                     |
//|                                                                  |
//|   OWNERSHIP: owns its plugins and the confirmation engine and deletes   |
//|   them. Session manager, news engine and context are BORROWED.         |
//|                                                                  |
//|   NO ORDER PLACEMENT. It outputs a decision; acting on it is the        |
//|   caller's responsibility.                                            |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_CDECISIONENGINE_MQH
#define SRP_DECISION_CDECISIONENGINE_MQH

#include "../Core/Interfaces/ILogger.mqh"
#include "../Utilities/CMathUtils.mqh"
#include "Strategies/CStrategyPlugin.mqh"
#include "Confirmation/CConfirmationEngine.mqh"
#include "Session/CSessionManager.mqh"
#include "News/CNewsEngine.mqh"
//--- The regime engine is BORROWED and optional; this include provides
//--- its type and the strategy-slot enum used by the gate.
#include "../Profiles/CRegimeEngine.mqh"

#define SRP_MAX_PLUGINS 16

class CDecisionEngine
  {
private:
   string               m_symbol;
   ENUM_TIMEFRAMES      m_timeframe;
   ILogger             *m_logger;         // borrowed
   //--- OWNED.
   CStrategyPlugin     *m_plugins[];
   CConfirmationEngine *m_confirmation;
   //--- BORROWED.
   CSessionManager     *m_sessions;
   CNewsEngine         *m_news;
   CStrategyContext    *m_context;

   //--- Voting policy.
   ENUM_SRP_VOTE_MODE   m_vote_mode;
   double               m_min_final_confidence;
   //--- When both sides vote, a near-tie is genuine disagreement rather
   //--- than a signal. This margin decides how near is too near.
   double               m_min_vote_margin;
   bool                 m_require_confirmation;

   //--- Per-pass working state.
   SDecisionInput       m_snapshot;
   SStrategySignal      m_candidates[SRP_MAX_PLUGINS];
   int                  m_candidate_count;
   STradeDecision       m_last_decision;

   //--- BORROWED regime engine. Optional: when absent the gate is open and
   //--- behaviour matches Phase 5 exactly, which keeps the existing tests
   //--- valid and lets this class be tested without indicators.
   CRegimeEngine       *m_regime;
   int                  m_regime_skipped;
   string               m_regime_skipped_names;
   //--- How many plugins the regime actually LET RUN on the last pass.
   //--- Needed to tell "the regime excluded everything" from "strategies
   //--- ran and found no setup", which the skip count alone cannot do.
   int                  m_regime_polled;

   //=== PER-STAGE FUNNEL ==============================================
   //--- Counts how many passes REACHED each stage, not how many failed it.
   //--- The decline tally answers "why did we stop"; this answers "how far
   //--- did we get", and only the pair identifies a bottleneck: a stage
   //--- with a huge decline count that almost nothing reached is not the
   //--- constraint, whatever its absolute number looks like.
   long                 m_reached_session;
   long                 m_reached_news;
   long                 m_reached_snapshot;
   long                 m_reached_regime;
   long                 m_reached_poll;
   long                 m_reached_vote;
   long                 m_reached_confirm;
   long                 m_reached_confidence;
   //--- Setups that existed at all, regardless of what happened after.
   long                 m_raw_setups;

   ENUM_SRP_STRAT_SLOT  KindToSlot(const ENUM_SRP_STRATEGY_KIND kind) const;

   //--- Per-reason decline tally, indexed by ENUM_SRP_DECLINE_REASON.
   //--- WHY THIS EXISTS: "the robot took no trades" is the single most
   //--- common support question, and without this the only honest answer
   //--- is a guess. One counter per reason turns it into a fact.
   //--- Sized for every enumerator; Decline() bounds-checks the index, so
   //--- an added reason cannot write past the end.
   long                 m_decline_tally[10];

   long                 m_evaluations;
   long                 m_actionable;
   long                 m_declined;

   //--- Pipeline steps.
   bool              BuildSnapshot(const datetime now,const bool is_new_bar);
   int               PollPlugins(void);
   bool              ResolveVote(SStrategySignal &winner,
                                 STradeDecision &decision);
   //--- Vote resolvers, one per mode.
   bool              VoteFirstMatch(SStrategySignal &winner) const;
   bool              VoteHighestConfidence(SStrategySignal &winner) const;
   bool              VoteMajority(SStrategySignal &winner,
                                  STradeDecision &decision) const;
   bool              VoteWeighted(SStrategySignal &winner,
                                  STradeDecision &decision) const;
   bool              VoteUnanimous(SStrategySignal &winner) const;

   void              Decline(STradeDecision &decision,
                             const ENUM_SRP_DECLINE_REASON reason,
                             const string explanation);

public:
                     CDecisionEngine(const string symbol,
                                     const ENUM_TIMEFRAMES timeframe,
                                     ILogger *logger);
                    ~CDecisionEngine(void);

   //--- Wiring -------------------------------------------------------
   void              SetCollaborators(CSessionManager *sessions,
                                      CNewsEngine *news,
                                      CStrategyContext *context);
   //--- BORROWED. Injecting a regime engine turns on strategy gating;
   //--- leaving it NULL keeps the Phase 5 behaviour of polling everything.
   void              SetRegimeEngine(CRegimeEngine *regime) { m_regime=regime; }
   int               RegimeSkippedCount(void) const { return(m_regime_skipped); }
   string            RegimeSkippedNames(void) const { return(m_regime_skipped_names); }
   //--- Takes OWNERSHIP of the plugin.
   bool              AddPlugin(CStrategyPlugin *plugin);
   //--- Takes OWNERSHIP of the confirmation engine.
   void              SetConfirmationEngine(CConfirmationEngine *engine);

   void              SetVoteMode(const ENUM_SRP_VOTE_MODE mode) { m_vote_mode=mode; }
   void              SetMinFinalConfidence(const double minimum);
   void              SetMinVoteMargin(const double margin);
   void              SetRequireConfirmation(const bool require_confirmation)
     { m_require_confirmation=require_confirmation; }

   bool              Initialize(void);
   void              Shutdown(void);
   bool              Validate(SValidationResult &result);

   //--- THE primary operation. Runs the whole pipeline.
   bool              Evaluate(const datetime now,const bool is_new_bar,
                              STradeDecision &decision);

   //--- Access -------------------------------------------------------
   void              GetLastDecision(STradeDecision &out) const
     { out=m_last_decision; }
   void              GetSnapshot(SDecisionInput &out) const { out=m_snapshot; }
   int               PluginCount(void) const { return(ArraySize(m_plugins)); }
   CStrategyPlugin  *PluginAt(const int index) const;
   CConfirmationEngine *Confirmation(void) const { return(m_confirmation); }
   int               CandidateCount(void) const { return(m_candidate_count); }

   //--- Reads back how often each reason blocked a trade. Out-of-range
   //--- indices return zero rather than reading past the array.
   long              DeclineCount(const ENUM_SRP_DECLINE_REASON reason) const;
   //--- One line naming every reason that ever fired, most frequent
   //--- first. This is what a user should be shown when asking why
   //--- nothing was traded.
   string            DescribeDeclines(void) const;

   //--- THE STAGE FUNNEL. Reports, per stage, how many passes reached it,
   //--- how many it removed, and that loss as a share of what reached it.
   //---
   //--- The share is the number that matters. An absolute count only says
   //--- a stage is early in the pipeline; the share says whether the stage
   //--- is actually selective. A stage that removes 99% of what reaches it
   //--- is the bottleneck even if a later stage shows a similar raw count.
   string            DescribeFunnel(void) const;
   long              RawSetupCount(void) const { return(m_raw_setups); }

   long              EvaluationCount(void) const { return(m_evaluations); }
   long              ActionableCount(void) const { return(m_actionable); }
   long              DeclinedCount(void)   const { return(m_declined); }
   string            Describe(void) const;
   static string     DeclineToString(const ENUM_SRP_DECLINE_REASON reason);
   static string     VoteModeToString(const ENUM_SRP_VOTE_MODE mode);
  };

//+------------------------------------------------------------------+
CDecisionEngine::CDecisionEngine(const string symbol,
                                 const ENUM_TIMEFRAMES timeframe,
                                 ILogger *logger)
  : m_symbol(symbol),
    m_timeframe(timeframe),
    m_logger(logger),
    m_confirmation(NULL),
    m_sessions(NULL),
    m_news(NULL),
    m_context(NULL),
    m_vote_mode(SRP_VOTE_WEIGHTED),
    m_min_final_confidence(0.55),
    m_min_vote_margin(0.15),
    m_require_confirmation(true),
    m_candidate_count(0),
    m_regime(NULL),
    m_regime_skipped(0),
    m_regime_skipped_names(""),
    m_regime_polled(0),
    m_reached_session(0),
    m_reached_news(0),
    m_reached_snapshot(0),
    m_reached_regime(0),
    m_reached_poll(0),
    m_reached_vote(0),
    m_reached_confirm(0),
    m_reached_confidence(0),
    m_raw_setups(0),
    m_evaluations(0),
    m_actionable(0),
    m_declined(0)
  {
   ArrayInitialize(m_decline_tally,0);
   ArrayResize(m_plugins,0);
  }
//+------------------------------------------------------------------+
CDecisionEngine::~CDecisionEngine(void)
  {
   //--- Reverse of registration order.
   const int total=ArraySize(m_plugins);
   for(int i=total-1;i>=0;i--)
     {
      if(m_plugins[i]!=NULL)
        {
         delete m_plugins[i];
         m_plugins[i]=NULL;
        }
     }
   ArrayFree(m_plugins);
   if(m_confirmation!=NULL)
     {
      delete m_confirmation;
      m_confirmation=NULL;
     }
  }
//+------------------------------------------------------------------+
void CDecisionEngine::SetCollaborators(CSessionManager *sessions,
                                       CNewsEngine *news,
                                       CStrategyContext *context)
  {
   m_sessions=sessions;
   m_news=news;
   m_context=context;
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::AddPlugin(CStrategyPlugin *plugin)
  {
   if(plugin==NULL)
      return(false);
   const int total=ArraySize(m_plugins);
   if(total>=SRP_MAX_PLUGINS)
     {
      if(m_logger!=NULL)
         m_logger.Error("CDecisionEngine","plugin table full; refused "+
                        plugin.Name());
      return(false);
     }
   if(ArrayResize(m_plugins,total+1)!=total+1)
      return(false);
   m_plugins[total]=plugin;
   return(true);
  }
//+------------------------------------------------------------------+
void CDecisionEngine::SetConfirmationEngine(CConfirmationEngine *engine)
  {
   if(m_confirmation!=NULL)
      delete m_confirmation;
   m_confirmation=engine;
  }
//+------------------------------------------------------------------+
void CDecisionEngine::SetMinFinalConfidence(const double minimum)
  {
   if(minimum>=0.0 && minimum<=1.0)
      m_min_final_confidence=minimum;
  }
//+------------------------------------------------------------------+
void CDecisionEngine::SetMinVoteMargin(const double margin)
  {
   if(margin>=0.0)
      m_min_vote_margin=margin;
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::Initialize(void)
  {
   if(m_context==NULL)
     {
      if(m_logger!=NULL)
         m_logger.Error("CDecisionEngine","no strategy context wired");
      return(false);
     }
   if(ArraySize(m_plugins)==0)
     {
      if(m_logger!=NULL)
         m_logger.Error("CDecisionEngine","no strategy plugins registered");
      return(false);
     }
   if(m_logger!=NULL)
      m_logger.Info("CDecisionEngine",
                    StringFormat("ready: %d plugin(s), vote mode %s",
                                 ArraySize(m_plugins),
                                 VoteModeToString(m_vote_mode)));
   return(true);
  }
//+------------------------------------------------------------------+
void CDecisionEngine::Shutdown(void)
  {
   m_snapshot.Reset();
   m_last_decision.Reset();
   m_candidate_count=0;
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::BuildSnapshot(const datetime now,const bool is_new_bar)
  {
   m_snapshot.Reset();
   m_snapshot.symbol=m_symbol;
   m_snapshot.timeframe=m_timeframe;
   m_snapshot.server_time=now;
   m_snapshot.is_new_bar=is_new_bar;

   //--- Instrument facts.
   m_snapshot.point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   m_snapshot.digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
   if(m_snapshot.point<=0.0)
      return(false);

   //--- One tick read, shared by everything downstream. Reading prices
   //--- per-consumer would let two checks evaluate different markets.
   MqlTick tick;
   if(!SymbolInfoTick(m_symbol,tick))
      return(false);
   if(tick.bid<=0.0 || tick.ask<=0.0)
      return(false);
   m_snapshot.bid=tick.bid;
   m_snapshot.ask=tick.ask;
   m_snapshot.mid=(tick.bid+tick.ask)*0.5;
   m_snapshot.spread_points=(tick.ask-tick.bid)/m_snapshot.point;

   //--- Two bars: current and previous.
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(m_symbol,m_timeframe,0,2,rates)!=2)
      return(false);
   m_snapshot.bar_time   = rates[0].time;
   m_snapshot.open       = rates[0].open;
   m_snapshot.high       = rates[0].high;
   m_snapshot.low        = rates[0].low;
   m_snapshot.close      = rates[0].close;
   m_snapshot.prev_open  = rates[1].open;
   m_snapshot.prev_high  = rates[1].high;
   m_snapshot.prev_low   = rates[1].low;
   m_snapshot.prev_close = rates[1].close;

   //--- Phase 2 structure state.
   if(m_context!=NULL)
     {
      CMarketStructure *structure=m_context.Structure();
      if(structure!=NULL)
        {
         structure.GetState(m_snapshot.structure);
         m_snapshot.structure_valid=structure.IsValid();
        }
     }

   //--- Session and news context, already evaluated by the caller.
   if(m_sessions!=NULL)
      m_sessions.GetState(m_snapshot.session);
   else
      m_snapshot.session.trading_permitted=true;
   if(m_news!=NULL)
      m_news.GetState(m_snapshot.news);
   else
      m_snapshot.news.trading_permitted=true;

   m_snapshot.is_valid=true;
   return(true);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Maps a plugin's strategy kind onto the regime engine's slot enum.    |
//|                                                                  |
//| Two enums exist because the regime engine must be usable without the |
//| decision layer (a harness asserts its table standalone). This is the |
//| single translation point between them.                              |
//+------------------------------------------------------------------+
ENUM_SRP_STRAT_SLOT CDecisionEngine::KindToSlot(
                                 const ENUM_SRP_STRATEGY_KIND kind) const
  {
   switch(kind)
     {
      case SRP_STRAT_EMA_CROSS:              return(SRP_SLOT_EMA_CROSS);
      case SRP_STRAT_VWAP_PULLBACK:          return(SRP_SLOT_VWAP_PULLBACK);
      case SRP_STRAT_LIQUIDITY_SWEEP:        return(SRP_SLOT_LIQUIDITY_SWEEP);
      case SRP_STRAT_ORDER_BLOCK:            return(SRP_SLOT_ORDER_BLOCK);
      case SRP_STRAT_FAIR_VALUE_GAP:         return(SRP_SLOT_FVG);
      case SRP_STRAT_MOMENTUM_SCALP:         return(SRP_SLOT_MOMENTUM);
      case SRP_STRAT_OPENING_RANGE_BREAKOUT: return(SRP_SLOT_OPENING_RANGE);
      case SRP_STRAT_TREND_CONTINUATION:     return(SRP_SLOT_TREND_CONTINUATION);
      case SRP_STRAT_MEAN_REVERSION:         return(SRP_SLOT_MEAN_REVERSION);
      case SRP_STRAT_BREAKOUT:               return(SRP_SLOT_BREAKOUT);
      case SRP_STRAT_BREAK_OF_STRUCTURE:     return(SRP_SLOT_BOS);
      case SRP_STRAT_VOLATILITY_BREAKOUT:    return(SRP_SLOT_VOLATILITY_BREAKOUT);
      case SRP_STRAT_ORDER_FLOW:             return(SRP_SLOT_ORDER_FLOW);
     }
   return(SRP_SLOT_COUNT);
  }
//+------------------------------------------------------------------+
//| POLL, WITH REGIME GATING.                                          |
//|                                                                  |
//| Before Phase 6 every enabled plugin was polled and its opinion voted  |
//| on. That let a mean-reversion signal be counted during a violent      |
//| trend, where its premise does not hold. The vote can outweigh the     |
//| fact that the premise was absent.                                   |
//|                                                                  |
//| Gating removes those opinions BEFORE they are counted rather than     |
//| hoping the vote dilutes them. A skipped plugin is recorded so the     |
//| diagnostic can say which strategies the regime excluded, instead of   |
//| the user seeing an unexplained absence of signals.                   |
//|                                                                  |
//| When no regime engine is injected the gate is open and behaviour is   |
//| identical to Phase 5. That keeps the existing tests valid and makes   |
//| the engine testable without indicators.                              |
//+------------------------------------------------------------------+
int CDecisionEngine::PollPlugins(void)
  {
   m_candidate_count=0;
   m_regime_skipped=0;
   m_regime_skipped_names="";
   m_regime_polled=0;
   const int total=ArraySize(m_plugins);
   for(int i=0;i<total;i++)
     {
      if(m_plugins[i]==NULL)
         continue;

      //--- REGIME GATE. Ask before evaluating: a plugin whose premise is
      //--- absent should not even spend the CPU, and must not be able to
      //--- contribute a vote.
      if(m_regime!=NULL)
        {
         const ENUM_SRP_STRAT_SLOT slot=KindToSlot(m_plugins[i].Kind());
         if(slot>=SRP_SLOT_COUNT || !m_regime.Permits(slot))
           {
            m_regime_skipped++;
            if(m_regime_skipped_names!="")
               m_regime_skipped_names+=",";
            m_regime_skipped_names+=m_plugins[i].Name();
            continue;
           }
        }

      //--- The regime let this one run.
      m_regime_polled++;

      SStrategySignal signal;
      if(!m_plugins[i].Evaluate(m_snapshot,signal))
         continue;
      if(!signal.IsActionable())
         continue;
      if(m_candidate_count>=SRP_MAX_PLUGINS)
         break;
      m_candidates[m_candidate_count]=signal;
      m_candidate_count++;
     }
   return(m_candidate_count);
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::VoteFirstMatch(SStrategySignal &winner) const
  {
   //--- Fastest: registration order decides. Useful when one plugin is
   //--- known to be primary and the rest are fallbacks.
   if(m_candidate_count<1)
      return(false);
   winner=m_candidates[0];
   return(true);
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::VoteHighestConfidence(SStrategySignal &winner) const
  {
   if(m_candidate_count<1)
      return(false);
   int best=0;
   for(int i=1;i<m_candidate_count;i++)
      if(m_candidates[i].confidence>m_candidates[best].confidence)
         best=i;
   winner=m_candidates[best];
   return(true);
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::VoteMajority(SStrategySignal &winner,
                                   STradeDecision &decision) const
  {
   if(m_candidate_count<1)
      return(false);

   int buys=0,sells=0;
   for(int i=0;i<m_candidate_count;i++)
     {
      if(m_candidates[i].IsBuy())  buys++;
      else                         sells++;
     }
   decision.buy_votes=buys;
   decision.sell_votes=sells;

   //--- A tie is genuine disagreement, so no trade.
   if(buys==sells)
      return(false);

   const ENUM_SRP_DECISION winning=(buys>sells ? SRP_DECISION_BUY
                                               : SRP_DECISION_SELL);
   //--- Among the winning side, take the most confident as representative.
   int best=-1;
   for(int i=0;i<m_candidate_count;i++)
     {
      if(m_candidates[i].decision!=winning)
         continue;
      if(best<0 || m_candidates[i].confidence>m_candidates[best].confidence)
         best=i;
     }
   if(best<0)
      return(false);
   winner=m_candidates[best];
   return(true);
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::VoteWeighted(SStrategySignal &winner,
                                   STradeDecision &decision) const
  {
   if(m_candidate_count<1)
      return(false);

   //--- Weight x confidence per side. This is the default because it
   //--- respects both how many plugins agree AND how strongly.
   double buy_weight=0.0;
   double sell_weight=0.0;
   int buys=0,sells=0;
   for(int i=0;i<m_candidate_count;i++)
     {
      const double contribution=m_candidates[i].confidence*m_candidates[i].weight;
      if(m_candidates[i].IsBuy())
        {
         buy_weight+=contribution;
         buys++;
        }
      else
        {
         sell_weight+=contribution;
         sells++;
        }
     }
   decision.buy_votes=buys;
   decision.sell_votes=sells;
   decision.buy_weight=buy_weight;
   decision.sell_weight=sell_weight;

   const double total=buy_weight+sell_weight;
   if(total<=0.0)
      return(false);

   //--- MARGIN TEST. A near-even split means the plugins disagree, and
   //--- trading a coin flip with a spread cost is negative expectancy.
   const double margin=MathAbs(buy_weight-sell_weight)/total;
   if(margin<m_min_vote_margin)
      return(false);

   const ENUM_SRP_DECISION winning=(buy_weight>sell_weight ? SRP_DECISION_BUY
                                                           : SRP_DECISION_SELL);
   int best=-1;
   for(int i=0;i<m_candidate_count;i++)
     {
      if(m_candidates[i].decision!=winning)
         continue;
      if(best<0 || m_candidates[i].confidence>m_candidates[best].confidence)
         best=i;
     }
   if(best<0)
      return(false);
   winner=m_candidates[best];
   return(true);
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::VoteUnanimous(SStrategySignal &winner) const
  {
   if(m_candidate_count<1)
      return(false);
   //--- Strictest mode: any disagreement means no trade.
   const ENUM_SRP_DECISION first=m_candidates[0].decision;
   for(int i=1;i<m_candidate_count;i++)
      if(m_candidates[i].decision!=first)
         return(false);
   //--- Report the most confident of the unanimous set.
   return(VoteHighestConfidence(winner));
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::ResolveVote(SStrategySignal &winner,
                                  STradeDecision &decision)
  {
   switch(m_vote_mode)
     {
      case SRP_VOTE_FIRST_MATCH:        return(VoteFirstMatch(winner));
      case SRP_VOTE_HIGHEST_CONFIDENCE: return(VoteHighestConfidence(winner));
      case SRP_VOTE_MAJORITY:           return(VoteMajority(winner,decision));
      case SRP_VOTE_UNANIMOUS:          return(VoteUnanimous(winner));
     }
   return(VoteWeighted(winner,decision));
  }
//+------------------------------------------------------------------+
void CDecisionEngine::Decline(STradeDecision &decision,
                              const ENUM_SRP_DECLINE_REASON reason,
                              const string explanation)
  {
   decision.actionable=false;
   decision.decision=SRP_DECISION_NO_TRADE;
   decision.decline_reason=reason;
   decision.explanation=explanation;
   m_declined++;
   //--- Every decline in the engine funnels through here, so one counter
   //--- bump is enough to keep the tally complete.
   const int slot=(int)reason;
   if(slot>=0 && slot<ArraySize(m_decline_tally))
      m_decline_tally[slot]++;
  }
//+------------------------------------------------------------------+
long CDecisionEngine::DeclineCount(const ENUM_SRP_DECLINE_REASON reason) const
  {
   const int slot=(int)reason;
   if(slot<0 || slot>=ArraySize(m_decline_tally))
      return(0);
   return(m_decline_tally[slot]);
  }
//+------------------------------------------------------------------+
//| Names every reason that actually fired, ordered most frequent first. |
//| Selection sort over nine entries: clearer than anything cleverer and |
//| called once per run, not per tick.                                   |
//+------------------------------------------------------------------+
string CDecisionEngine::DescribeDeclines(void) const
  {
   const int total=ArraySize(m_decline_tally);
   int order[];
   ArrayResize(order,total);
   for(int i=0;i<total;i++)
      order[i]=i;
   for(int i=0;i<total-1;i++)
      for(int j=i+1;j<total;j++)
         if(m_decline_tally[order[j]]>m_decline_tally[order[i]])
           {
            const int swap=order[i];
            order[i]=order[j];
            order[j]=swap;
           }

   string text="declines by reason:";
   bool any=false;
   for(int i=0;i<total;i++)
     {
      const int slot=order[i];
      if(m_decline_tally[slot]<=0)
         continue;
      text+=" "+DeclineToString((ENUM_SRP_DECLINE_REASON)slot)+
            "="+IntegerToString(m_decline_tally[slot]);
      any=true;
     }
   if(!any)
      text+=" none";
   return(text);
  }
//+------------------------------------------------------------------+
//| STAGE FUNNEL.                                                      |
//|                                                                  |
//| Each line reads: stage, how many passes reached it, how many it        |
//| removed, and the removal as a share OF WHAT REACHED IT.                |
//|                                                                  |
//| Reporting the share is the whole point. A raw decline count is         |
//| dominated by pipeline position: the first stage sees every pass, so    |
//| its count is always large whether or not it is selective. The share    |
//| is position-independent and identifies the real constraint.            |
//+------------------------------------------------------------------+
string CDecisionEngine::DescribeFunnel(void) const
  {
   string text="STAGE FUNNEL (share is of what REACHED each stage)";

   //--- Losses are derived from consecutive reach counts rather than from
   //--- the decline tally, so the two are independent and disagreement
   //--- between them would be visible rather than hidden.
   const long lost_session   = m_reached_session  - m_reached_news;
   const long lost_news      = m_reached_news     - m_reached_snapshot;
   const long lost_snapshot  = m_reached_snapshot - m_reached_regime;
   const long lost_regime    = m_reached_regime   - m_reached_poll;
   const long lost_poll      = m_reached_poll     - m_reached_vote;
   const long lost_vote      = m_reached_vote     - m_reached_confirm;
   const long lost_confirm   = m_reached_confirm  - m_reached_confidence;
   const long lost_conf      = m_reached_confidence - m_actionable;

   text+=StringFormat("\n  evaluations       %10I64d", m_evaluations);
   text+=StringFormat("\n  session           reached %10I64d  removed %10I64d  %6.2f%%",
                      m_reached_session,lost_session,
                      (m_reached_session>0 ? 100.0*lost_session/m_reached_session : 0.0));
   text+=StringFormat("\n  news              reached %10I64d  removed %10I64d  %6.2f%%",
                      m_reached_news,lost_news,
                      (m_reached_news>0 ? 100.0*lost_news/m_reached_news : 0.0));
   text+=StringFormat("\n  snapshot/data     reached %10I64d  removed %10I64d  %6.2f%%",
                      m_reached_snapshot,lost_snapshot,
                      (m_reached_snapshot>0 ? 100.0*lost_snapshot/m_reached_snapshot : 0.0));
   text+=StringFormat("\n  regime gate       reached %10I64d  removed %10I64d  %6.2f%%",
                      m_reached_regime,lost_regime,
                      (m_reached_regime>0 ? 100.0*lost_regime/m_reached_regime : 0.0));
   text+=StringFormat("\n  strategy poll     reached %10I64d  removed %10I64d  %6.2f%%",
                      m_reached_poll,lost_poll,
                      (m_reached_poll>0 ? 100.0*lost_poll/m_reached_poll : 0.0));
   text+=StringFormat("\n  vote/consensus    reached %10I64d  removed %10I64d  %6.2f%%",
                      m_reached_vote,lost_vote,
                      (m_reached_vote>0 ? 100.0*lost_vote/m_reached_vote : 0.0));
   text+=StringFormat("\n  confirmation      reached %10I64d  removed %10I64d  %6.2f%%",
                      m_reached_confirm,lost_confirm,
                      (m_reached_confirm>0 ? 100.0*lost_confirm/m_reached_confirm : 0.0));
   text+=StringFormat("\n  confidence floor  reached %10I64d  removed %10I64d  %6.2f%%",
                      m_reached_confidence,lost_conf,
                      (m_reached_confidence>0 ? 100.0*lost_conf/m_reached_confidence : 0.0));
   text+=StringFormat("\n  actionable        %10I64d", m_actionable);
   //--- WHICH session rule blocked, not merely that one did. "Session
   //--- blocked 100%" is true of a weekend, a misconfigured window and a
   //--- kill-zone requirement alike, and those need different fixes.
   if(m_sessions!=NULL && lost_session>0)
      text+="\n  session state: "+m_sessions.Describe();
   //--- WHY the news gate blocked, not merely that it did. "NEWS_BLOCKED
   //--- 100%" is equally true of a real FOMC blackout, an unavailable
   //--- calendar hitting the fail-safe, and a filter that could not be
   //--- switched off - and those need completely different fixes. A live
   //--- run lost five hours to that ambiguity.
   if(m_news!=NULL && lost_news>0)
      text+="\n  news state: "+m_news.Describe();
   //--- Passes where at least one strategy produced a setup. This is the
   //--- honest denominator for "how selective is everything downstream".
   text+=StringFormat("\n  passes with a setup %8I64d of %I64d reaching the poll (%.4f%%)",
                      m_raw_setups,m_reached_poll,
                      (m_reached_poll>0 ? 100.0*m_raw_setups/m_reached_poll : 0.0));
   return(text);
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::Evaluate(const datetime now,const bool is_new_bar,
                               STradeDecision &decision)
  {
   decision.Reset();
   decision.decided_at=now;
   m_evaluations++;

   //--- STEP 1: SESSION. Checked first so a weekend costs nothing.
   m_reached_session++;
   if(m_sessions!=NULL)
     {
      m_sessions.Evaluate(now);
      m_sessions.GetState(decision.session);
      if(!decision.session.trading_permitted)
        {
         Decline(decision,SRP_DECLINE_SESSION_BLOCKED,
                 "session: "+decision.session.block_detail);
         m_last_decision=decision;
         return(false);
        }
     }

   //--- STEP 2: NEWS. Also before any indicator read.
   m_reached_news++;
   if(m_news!=NULL)
     {
      m_news.Refresh(now);
      m_news.Evaluate(now);
      m_news.GetState(decision.news);
      if(!decision.news.trading_permitted)
        {
         Decline(decision,SRP_DECLINE_NEWS_BLOCKED,
                 "news: "+decision.news.detail);
         m_last_decision=decision;
         return(false);
        }
     }

   //--- STEP 3: SNAPSHOT.
   m_reached_snapshot++;
   if(!BuildSnapshot(now,is_new_bar))
     {
      Decline(decision,SRP_DECLINE_DATA_UNAVAILABLE,
              "could not build a valid market snapshot");
      m_last_decision=decision;
      return(false);
     }
   decision.session=m_snapshot.session;
   decision.news=m_snapshot.news;

   //--- STEP 3b: REGIME. Classified before polling so the gate can
   //--- exclude strategies whose premise is absent, and so a market that
   //--- should not be traded at all costs nothing further.
   m_reached_regime++;
   if(m_regime!=NULL)
     {
      m_regime.Evaluate(now);
      if(!m_regime.TradingAllowed())
        {
         SRegimeState rstate;
         m_regime.GetState(rstate);
         Decline(decision,SRP_DECLINE_REGIME_BLOCKED,
                 "regime: "+(rstate.block_reason!="" ? rstate.block_reason
                                                     : "not tradeable"));
         m_last_decision=decision;
         return(false);
        }
     }

   //--- STEP 4: POLL PLUGINS.
   m_reached_poll++;
   decision.candidates=PollPlugins();
   if(decision.candidates>0)
      m_raw_setups++;
   if(decision.candidates<1)
     {
      //--- DISTINGUISH the two reasons a poll finds nothing. "No setup
      //--- existed" and "the regime excluded every strategy that could
      //--- have found one" are different facts, and reporting them as the
      //--- same one sends the user looking in the wrong place.
      //---
      //--- THE TEST IS m_regime_polled==0, NOT m_regime_skipped>0.
      //--- The earlier condition was satisfied whenever the regime excluded
      //--- ANY strategy, so a pass where eight strategies were permitted,
      //--- ran, and simply found no setup was still reported as
      //--- REGIME_BLOCKED. On a real XAUUSD month that mislabelled roughly
      //--- a million ticks and pointed the entire diagnosis at the regime
      //--- gate instead of at setup scarcity. Only a pass where the regime
      //--- let NOTHING run was actually blocked by the regime.
      if(m_regime!=NULL && m_regime_polled==0 && m_regime_skipped>0)
        {
         SRegimeState rstate;
         m_regime.GetState(rstate);
         Decline(decision,SRP_DECLINE_REGIME_BLOCKED,
                 StringFormat("regime %s excluded %d strategy(ies): %s",
                              CRegimeEngine::RegimeToString(rstate.regime),
                              m_regime_skipped,m_regime_skipped_names));
        }
      else
         Decline(decision,SRP_DECLINE_NO_SIGNAL,"no plugin produced a signal");
      m_last_decision=decision;
      return(false);
     }

   //--- STEP 5: VOTE.
   m_reached_vote++;
   SStrategySignal winner;
   if(!ResolveVote(winner,decision))
     {
      Decline(decision,SRP_DECLINE_CONFLICTING_SIGNALS,
              StringFormat("%d candidate(s) but no consensus under %s "
                           "(buy %d/%.2f vs sell %d/%.2f)",
                           decision.candidates,
                           VoteModeToString(m_vote_mode),
                           decision.buy_votes,decision.buy_weight,
                           decision.sell_votes,decision.sell_weight));
      m_last_decision=decision;
      return(false);
     }
   decision.signal=winner;

   //--- STEP 6: CONFIRM.
   m_reached_confirm++;
   double confirmation_confidence=1.0;
   if(m_confirmation!=NULL)
     {
      const bool confirmed=m_confirmation.Confirm(m_snapshot,winner.decision,
                                                  decision.confirmation);
      confirmation_confidence=decision.confirmation.confidence;
      if(m_require_confirmation && !confirmed)
        {
         Decline(decision,SRP_DECLINE_CONFIRMATION_FAILED,
                 "confirmation: "+decision.confirmation.summary);
         m_last_decision=decision;
         return(false);
        }
     }

   //--- STEP 7: BLEND. Multiplying rather than averaging is deliberate:
   //--- a strong signal with weak confirmation should NOT reach the same
   //--- score as a moderate signal with strong confirmation. Both factors
   //--- must be present for high final confidence.
   decision.final_confidence=winner.confidence*confirmation_confidence;

   m_reached_confidence++;
   if(decision.final_confidence<m_min_final_confidence)
     {
      Decline(decision,SRP_DECLINE_LOW_CONFIDENCE,
              StringFormat("final confidence %.2f below floor %.2f "
                           "(signal %.2f x confirmation %.2f)",
                           decision.final_confidence,m_min_final_confidence,
                           winner.confidence,confirmation_confidence));
      m_last_decision=decision;
      return(false);
     }

   decision.actionable=true;
   decision.decision=winner.decision;
   //--- The risk rating reflects the BLENDED confidence, not the
   //--- strategy's own optimism.
   if(decision.final_confidence>=0.85)      decision.risk_rating=SRP_RISK_RATING_LOW;
   else if(decision.final_confidence>=0.70) decision.risk_rating=SRP_RISK_RATING_MEDIUM;
   else if(decision.final_confidence>=0.55) decision.risk_rating=SRP_RISK_RATING_HIGH;
   else                                     decision.risk_rating=SRP_RISK_RATING_EXTREME;

   decision.explanation=StringFormat("%s from %s (%.2f) x confirmation %.2f "
                                     "= %.2f | %s",
                                     CStrategyPlugin::DecisionToString(winner.decision),
                                     winner.strategy_name,
                                     winner.confidence,
                                     confirmation_confidence,
                                     decision.final_confidence,
                                     winner.reason);

   m_actionable++;
   m_last_decision=decision;
   if(m_logger!=NULL)
      m_logger.Info("CDecisionEngine",decision.explanation);
   return(true);
  }
//+------------------------------------------------------------------+
CStrategyPlugin *CDecisionEngine::PluginAt(const int index) const
  {
   if(index<0 || index>=ArraySize(m_plugins))
      return(NULL);
   return(m_plugins[index]);
  }
//+------------------------------------------------------------------+
bool CDecisionEngine::Validate(SValidationResult &result)
  {
   if(m_context==NULL)
      result.AddError("CDecisionEngine: no strategy context wired");
   if(ArraySize(m_plugins)==0)
      result.AddError("CDecisionEngine: no plugins registered");
   if(m_sessions==NULL)
      result.AddWarning("CDecisionEngine: no session manager; time filtering "
                        "will not apply");
   if(m_news==NULL)
      result.AddWarning("CDecisionEngine: no news engine; releases will not "
                        "pause trading");
   if(m_confirmation==NULL && m_require_confirmation)
      result.AddError("CDecisionEngine: confirmation required but no engine set");
   if(m_vote_mode==SRP_VOTE_UNANIMOUS && ArraySize(m_plugins)>4)
      result.AddWarning("CDecisionEngine: unanimous voting with many plugins "
                        "will rarely produce a trade");

   const int total=ArraySize(m_plugins);
   for(int i=0;i<total;i++)
      if(m_plugins[i]!=NULL)
         m_plugins[i].Validate(result);
   if(m_confirmation!=NULL)
      m_confirmation.Validate(result);
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
string CDecisionEngine::DeclineToString(const ENUM_SRP_DECLINE_REASON reason)
  {
   switch(reason)
     {
      case SRP_DECLINE_NO_SIGNAL:            return("NO_SIGNAL");
      case SRP_DECLINE_LOW_CONFIDENCE:       return("LOW_CONFIDENCE");
      case SRP_DECLINE_CONFIRMATION_FAILED:  return("CONFIRMATION_FAILED");
      case SRP_DECLINE_CONFLICTING_SIGNALS:  return("CONFLICTING_SIGNALS");
      case SRP_DECLINE_SESSION_BLOCKED:      return("SESSION_BLOCKED");
      case SRP_DECLINE_NEWS_BLOCKED:         return("NEWS_BLOCKED");
      case SRP_DECLINE_DATA_UNAVAILABLE:     return("DATA_UNAVAILABLE");
      case SRP_DECLINE_DISABLED:             return("DISABLED");
      case SRP_DECLINE_REGIME_BLOCKED:       return("REGIME_BLOCKED");
     }
   return("NONE");
  }
//+------------------------------------------------------------------+
string CDecisionEngine::VoteModeToString(const ENUM_SRP_VOTE_MODE mode)
  {
   switch(mode)
     {
      case SRP_VOTE_FIRST_MATCH:        return("FIRST_MATCH");
      case SRP_VOTE_HIGHEST_CONFIDENCE: return("HIGHEST_CONFIDENCE");
      case SRP_VOTE_MAJORITY:           return("MAJORITY");
      case SRP_VOTE_UNANIMOUS:          return("UNANIMOUS");
     }
   return("WEIGHTED");
  }
//+------------------------------------------------------------------+
string CDecisionEngine::Describe(void) const
  {
   return(StringFormat("decision engine: %d plugin(s) %s | eval=%I64d "
                       "actionable=%I64d declined=%I64d | last=%s %s",
                       ArraySize(m_plugins),
                       VoteModeToString(m_vote_mode),
                       m_evaluations,m_actionable,m_declined,
                       CStrategyPlugin::DecisionToString(m_last_decision.decision),
                       (m_last_decision.actionable
                        ? StringFormat("conf=%.2f",m_last_decision.final_confidence)
                        : DeclineToString(m_last_decision.decline_reason))));
  }

#endif // SRP_DECISION_CDECISIONENGINE_MQH
//+------------------------------------------------------------------+
