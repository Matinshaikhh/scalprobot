//+------------------------------------------------------------------+
//|                                          CSignalAggregator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Strategies : collapses many opinions into one decision.              |
//|                                                                  |
//|   RESPONSIBILITY (one only): apply an aggregation policy to a set of   |
//|   SSignal values. It never evaluates market data and never talks to    |
//|   an indicator.                                                       |
//|                                                                  |
//|   This is where conflicting strategies are resolved explicitly rather  |
//|   than by whichever one happened to run first. Four policies are       |
//|   supported (first match, majority vote, weighted score, unanimous),   |
//|   and adding a fifth means adding one branch here and nothing else.    |
//+------------------------------------------------------------------+
#ifndef SRP_STRATEGIES_CSIGNALAGGREGATOR_MQH
#define SRP_STRATEGIES_CSIGNALAGGREGATOR_MQH

#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Types/Structs.mqh"

class CSignalAggregator
  {
private:
   ILogger                  *m_logger;     // borrowed
   ENUM_SRP_AGGREGATION_MODE m_mode;
   double                    m_min_confidence;
   double                    m_min_score_margin; // weighted mode tie-break

   //--- One method per policy. Each receives the candidate set and
   //--- produces the winning signal.
   bool              ResolveFirstMatch(const SSignal &candidates[],
                                       const int count,
                                       SSignal &out_signal) const;
   bool              ResolveMajorityVote(const SSignal &candidates[],
                                         const int count,
                                         SSignal &out_signal) const;
   bool              ResolveWeightedScore(const SSignal &candidates[],
                                          const int count,
                                          SSignal &out_signal) const;
   bool              ResolveUnanimous(const SSignal &candidates[],
                                      const int count,
                                      SSignal &out_signal) const;

   //--- Builds the human-readable rationale that ends up in the
   //--- journal and on the dashboard, explaining WHY this trade.
   string            BuildRationale(const SSignal &candidates[],
                                    const int count,
                                    const SSignal &winner) const;

public:
                     CSignalAggregator(ILogger *logger);
                    ~CSignalAggregator(void) { }

   void              SetMode(const ENUM_SRP_AGGREGATION_MODE mode);
   void              SetMinConfidence(const double min_confidence);
   void              SetMinScoreMargin(const double margin);

   ENUM_SRP_AGGREGATION_MODE Mode(void) const { return(m_mode); }

   //--- The single public operation. Returns false when no actionable
   //--- consensus exists, which is the common case on most ticks.
   bool              Aggregate(const SSignal &candidates[],
                               const int count,
                               SSignal &out_signal) const;
  };

#endif // SRP_STRATEGIES_CSIGNALAGGREGATOR_MQH
//+------------------------------------------------------------------+
