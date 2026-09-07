//+------------------------------------------------------------------+
//|                                           CPositionManager.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Trade : applies management rules to every open position.               |
//|                                                                  |
//|   RESPONSIBILITY (one only): for each owned position, ask the rules      |
//|   what to do and forward the winning intent to ITradeExecutor.           |
//|                                                                  |
//|   IT CONTAINS NO MANAGEMENT LOGIC. Break-even, trailing, partial close   |
//|   and time-stop are IPositionRule implementations. This class only        |
//|   sequences them and resolves conflicts by priority, which is why        |
//|   adding a new management behaviour cannot destabilise an existing one.  |
//|                                                                  |
//|   CONFLICT RULE: a CLOSE_FULL intent beats everything; otherwise the     |
//|   lowest-priority-number rule wins. Protective rules are given low       |
//|   numbers, so capital preservation always outranks profit-taking.        |
//|                                                                  |
//|   RUNS EVEN WHEN ENTRIES ARE FORBIDDEN. Open risk must be managed        |
//|   whether or not new risk is permitted.                                 |
//|                                                                  |
//|   OWNERSHIP: owns its rules and deletes them.                           |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_CPOSITIONMANAGER_MQH
#define SRP_TRADE_CPOSITIONMANAGER_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IPositionRule.mqh"
#include "../Core/Interfaces/ITradeExecutor.mqh"
#include "../Core/Interfaces/IEventPublisher.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CPositionRepository;
class CSymbolInfoProvider;
class CStrategyOrchestrator;
class CStopLevelValidator;

class CPositionManager : public IModule
  {
private:
   CModuleIdentity        m_id;
   IPositionRule         *m_rules[];        // OWNED
   //--- All borrowed.
   ITradeExecutor        *m_executor;
   CPositionRepository   *m_positions;
   CSymbolInfoProvider   *m_symbol_info;
   CStrategyOrchestrator *m_strategies;
   CStopLevelValidator   *m_stop_validator;
   IEventPublisher       *m_publisher;

   long                   m_modifications;
   long                   m_partial_closes;
   long                   m_full_closes;

   //--- Rules are sorted once by priority at Initialize(), so the hot
   //--- path does no sorting.
   void              SortRulesByPriority(void);

   //--- Collects rule intents for one position and returns the winner.
   bool              ResolveAction(const SDecisionContext &context,
                                   const SSymbolSpec &spec,
                                   const SPositionSnapshot &position,
                                   SPositionAction &winning_action);

   //--- Executes a resolved intent. Split out so ManageAll stays a
   //--- readable loop rather than a nest of branches.
   bool              ApplyAction(const SPositionSnapshot &position,
                                 const SPositionAction &action,
                                 const SDecisionContext &context,
                                 const SSymbolSpec &spec);

   //--- Consults strategy-owned exit opinions before the rules, since a
   //--- strategy invalidating its own thesis outranks a trailing stop.
   bool              QueryStrategyExit(const SDecisionContext &context,
                                       const SPositionSnapshot &position,
                                       SPositionAction &action);

public:
                     CPositionManager(ITradeExecutor *executor,
                                      CPositionRepository *positions,
                                      CSymbolInfoProvider *symbol_info,
                                      CStrategyOrchestrator *strategies,
                                      CStopLevelValidator *stop_validator,
                                      IEventPublisher *publisher,
                                      ILogger *logger);
                    ~CPositionManager(void);

   //--- Composition. Takes ownership.
   bool              AddRule(IPositionRule *rule);
   int               RuleCount(void) const { return(ArraySize(m_rules)); }
   IPositionRule    *RuleAt(const int index) const;

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- The management pass. Called every tick the engine allows
   //--- position management, which includes PAUSED and HALTED states.
   int               ManageAll(const SDecisionContext &context);

   //--- Emergency liquidation, invoked by the engine when a guard or the
   //--- kill switch demands it. Attempts every position and reports how
   //--- many closed, so a partial failure is visible rather than assumed.
   int               FlattenAll(const ENUM_SRP_EXIT_REASON reason,
                                const SDecisionContext &context);

   //--- Diagnostics ---------------------------------------------------
   long              ModificationCount(void) const { return(m_modifications); }
   long              PartialCloseCount(void) const { return(m_partial_closes); }
   long              FullCloseCount(void)    const { return(m_full_closes); }
  };

#endif // SRP_TRADE_CPOSITIONMANAGER_MQH
//+------------------------------------------------------------------+
