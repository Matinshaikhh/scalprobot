//+------------------------------------------------------------------+
//|                                                CStrategyBase.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Base : abstract base for every entry strategy.            |
//|                                                                  |
//|   Implements the plumbing of IStrategy (identity, enable flag,    |
//|   weight, health, no-op event hook) and leaves exactly ONE        |
//|   abstract method - OnEvaluate - for concrete strategies. A new   |
//|   strategy author therefore writes signal logic and nothing else. |
//|                                                                  |
//|   Template Method pattern: Evaluate() is final-by-convention and  |
//|   performs the guard checks, then delegates to OnEvaluate().      |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_BASE_CSTRATEGYBASE_MQH
#define SRP_CORE_BASE_CSTRATEGYBASE_MQH

#include "../Interfaces/IStrategy.mqh"
#include "CModuleIdentity.mqh"

class CStrategyBase : public IStrategy
  {
protected:
   CModuleIdentity      m_id;             // composed shared state
   ENUM_SRP_STRATEGY_ID m_strategy_id;
   double               m_weight;
   int                  m_required_bars;
   SSignal              m_last_signal;    // for dashboard / diagnostics

   //--- The single extension point for subclasses.
   virtual bool      OnEvaluate(const SDecisionContext &context,SSignal &signal)=0;

   //--- Optional hooks with safe defaults.
   virtual bool      OnInitialize(void)                 { return(true); }
   virtual void      OnShutdown(void)                   { }
   virtual void      OnValidate(SValidationResult &result) { }

   //--- Helper so subclasses fill the boilerplate signal fields once.
   void              StampSignal(SSignal &signal,
                                 const SDecisionContext &context,
                                 const ENUM_SRP_SIGNAL_DIRECTION direction,
                                 const double confidence,
                                 const string rationale)
     {
      signal.direction         = direction;
      signal.strategy_id       = m_strategy_id;
      signal.strategy_name     = m_id.Name();
      signal.confidence        = confidence;
      signal.weight            = m_weight;
      signal.generated_at      = context.market.server_time;
      signal.snapshot_sequence = context.market.sequence_id;
      signal.rationale         = rationale;
     }

public:
                     CStrategyBase(const string name,
                                   const ENUM_SRP_STRATEGY_ID id,
                                   ILogger *logger,
                                   const double weight=1.0,
                                   const int required_bars=100)
     : m_strategy_id(id),
       m_weight(weight),
       m_required_bars(required_bars)
     {
      m_id.Configure(name,logger);
     }
   virtual          ~CStrategyBase(void) { }

   //--- IModule -----------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }

   virtual bool      Initialize(void) override
     {
      if(m_id.IsInitialized())
         return(true);
      if(!OnInitialize())
        {
         m_id.SetHealth(SRP_HEALTH_CRITICAL,"strategy initialisation failed");
         return(false);
        }
      m_id.SetInitialized(true);
      return(true);
     }

   virtual void      Validate(SValidationResult &result) override
     {
      if(m_weight<0.0)
         result.AddError(m_id.Name()+": negative aggregation weight");
      if(m_required_bars<1)
         result.AddError(m_id.Name()+": RequiredBars must be positive");
      OnValidate(result);
     }

   virtual void      Shutdown(void) override
     {
      OnShutdown();
      m_id.SetInitialized(false);
     }

   virtual void      ReportHealth(SHealthReport &report) override
     {
      m_id.FillReport(report,m_last_signal.generated_at);
     }

   //--- Strategies ignore bus traffic by default.
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- IStrategy ---------------------------------------------------
   virtual ENUM_SRP_STRATEGY_ID StrategyId(void) override { return(m_strategy_id); }
   virtual string    StrategyName(void) override { return(m_id.Name()); }

   virtual bool      IsEnabled(void) override { return(m_id.IsEnabled()); }
   virtual void      SetEnabled(const bool enabled) override { m_id.SetEnabled(enabled); }

   virtual double    Weight(void) override { return(m_weight); }
   virtual void      SetWeight(const double weight) override
     {
      if(weight>=0.0)
         m_weight=weight;
     }

   virtual int       RequiredBars(void) override { return(m_required_bars); }

   //--- Template method: uniform preconditions, delegated logic.
   virtual bool      Evaluate(const SDecisionContext &context,SSignal &signal) override
     {
      signal.Reset();
      if(!m_id.IsEnabled() || !m_id.IsInitialized())
         return(false);
      if(!context.market.is_valid)
         return(false);
      if(!OnEvaluate(context,signal))
         return(false);
      m_last_signal=signal;
      return(signal.IsActionable());
     }

   //--- Most strategies delegate exits to the rule engine.
   virtual bool      ShouldExit(const SDecisionContext &context,
                                const SPositionSnapshot &position,
                                ENUM_SRP_EXIT_REASON &reason) override
     {
      reason=SRP_EXIT_UNKNOWN;
      return(false);
     }

   //--- Diagnostics ------------------------------------------------
   void              LastSignal(SSignal &out) const { out=m_last_signal; }
  };

#endif // SRP_CORE_BASE_CSTRATEGYBASE_MQH
//+------------------------------------------------------------------+
