//+------------------------------------------------------------------+
//|                                      CStrategyOrchestrator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Strategies : owns the strategy collection and runs one round.        |
//|                                                                  |
//|   RESPONSIBILITY (one only): poll every enabled IStrategy, collect     |
//|   the candidate signals, and delegate resolution to                    |
//|   CSignalAggregator. It contains no trading logic and no               |
//|   aggregation logic - it is a coordinator.                            |
//|                                                                  |
//|   Because it depends only on IStrategy, a customer-specific strategy   |
//|   can be dropped in without this class changing at all.                |
//|                                                                  |
//|   OWNERSHIP: owns its IStrategy instances and deletes them.            |
//+------------------------------------------------------------------+
#ifndef SRP_STRATEGIES_CSTRATEGYORCHESTRATOR_MQH
#define SRP_STRATEGIES_CSTRATEGYORCHESTRATOR_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IStrategy.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"
#include "CSignalAggregator.mqh"

class CStrategyOrchestrator : public IModule
  {
private:
   CModuleIdentity   m_id;
   IStrategy        *m_strategies[];        // OWNED
   CSignalAggregator m_aggregator;          // owned by value
   ENUM_SRP_DIRECTION_MODE m_direction_mode;

   //--- Per-pass scratch space, sized once to avoid per-tick allocation.
   SSignal           m_candidates[];
   int               m_candidate_count;
   SSignal           m_last_decision;
   long              m_evaluation_count;
   long              m_signal_count;

   //--- Enforces the user's Buy-only / Sell-only / Disabled preference
   //--- centrally, so no individual strategy has to know about it.
   bool              IsDirectionPermitted(const ENUM_SRP_SIGNAL_DIRECTION direction) const;

public:
                     CStrategyOrchestrator(ILogger *logger);
                    ~CStrategyOrchestrator(void);

   //--- Composition. Takes ownership.
   bool              Add(IStrategy *strategy);
   int               Count(void) const { return(ArraySize(m_strategies)); }
   IStrategy        *At(const int index) const;

   CSignalAggregator *Aggregator(void) { return(GetPointer(m_aggregator)); }
   void              SetDirectionMode(const ENUM_SRP_DIRECTION_MODE mode);

   //--- Largest RequiredBars across strategies; the market data service
   //--- uses it to guarantee history before the first pass.
   int               MaximumRequiredBars(void) const;

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Pipeline stage 8. Returns false when no actionable signal.
   bool              ResolveSignal(const SDecisionContext &context,
                                   SSignal &out_signal);

   //--- Consulted by CPositionManager so a strategy can close what it
   //--- opened, without ever touching the trade API.
   bool              QueryExit(const SDecisionContext &context,
                               const SPositionSnapshot &position,
                               ENUM_SRP_EXIT_REASON &reason);

   //--- Diagnostics for the dashboard -------------------------------
   void              LastDecision(SSignal &out) const { out=m_last_decision; }
   int               CandidateCount(void)       const { return(m_candidate_count); }
   long              SignalCount(void)          const { return(m_signal_count); }
  };

#endif // SRP_STRATEGIES_CSTRATEGYORCHESTRATOR_MQH
//+------------------------------------------------------------------+
