//+------------------------------------------------------------------+
//|                                           CDecisionPipeline.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : the ordered decision path from tick to trade request.     |
//|                                                                  |
//|   RESPONSIBILITY (one only): SEQUENCE the stages. It contains no   |
//|   trading rules whatsoever - each stage is delegated to the module |
//|   that owns that concern. Read this class to understand the whole  |
//|   system's control flow in one screen.                             |
//|                                                                  |
//|   THE PATH (each stage may abort the pass):                        |
//|     1  CMarketDataService     -> capture one coherent snapshot     |
//|     2  CIndicatorManager      -> refresh buffers once              |
//|     3  CMarketRegimeAnalyzer  -> label trend/volatility/session    |
//|     4  CAccountInfoProvider   -> sample equity/margin              |
//|     5  CPositionRepository    -> current exposure                  |
//|     6  CNewsBlackoutEvaluator -> blackout state                    |
//|     7  CRiskGuardChain        -> may the ACCOUNT trade?            |
//|     8  CStrategyOrchestrator  -> collect opinions -> one signal    |
//|     9  CFilterChain           -> may THIS trade happen?            |
//|    10  CRiskManager           -> size + protective levels          |
//|    11  CTradeRequestBuilder   -> assemble a validated request      |
//|                                                                  |
//|   Position MANAGEMENT is a separate path (CPositionManager) that   |
//|   runs even when entries are forbidden, because open risk must be  |
//|   tended to regardless of whether new risk is allowed.             |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CDECISIONPIPELINE_MQH
#define SRP_CORE_CDECISIONPIPELINE_MQH

#include "Interfaces/ILogger.mqh"
#include "Interfaces/IEventPublisher.mqh"
#include "Interfaces/IClock.mqh"
#include "Types/Structs.mqh"

//--- Collaborators are forward-declared: the pipeline depends on
//--- their abstractions, and forward declaration keeps this header
//--- from dragging the entire codebase into every translation unit.
class CMarketDataService;
class CMarketRegimeAnalyzer;
class CAccountInfoProvider;
class CSymbolInfoProvider;
class CIndicatorManager;
class CPositionRepository;
class CNewsBlackoutEvaluator;
class CRiskGuardChain;
class CStrategyOrchestrator;
class CFilterChain;
class CRiskManager;
class CTradeRequestBuilder;
class CSessionStatistics;

//--- Outcome of one pass, returned to the engine.
struct SPipelineOutcome
  {
   bool                 context_built;
   bool                 signal_found;
   bool                 filters_passed;
   bool                 risk_approved;
   bool                 request_ready;
   ENUM_SRP_VETO_REASON abort_reason;
   string               abort_stage;
   string               abort_detail;

                     SPipelineOutcome(void) { Reset(); }
   void              Reset(void)
     {
      context_built=false; signal_found=false; filters_passed=false;
      risk_approved=false; request_ready=false;
      abort_reason=SRP_VETO_NONE; abort_stage=""; abort_detail="";
     }
  };

class CDecisionPipeline
  {
private:
   //--- All borrowed; the registry owns them.
   CMarketDataService     *m_market_data;
   CMarketRegimeAnalyzer  *m_regime;
   CAccountInfoProvider   *m_account;
   CSymbolInfoProvider    *m_symbol;
   CIndicatorManager      *m_indicators;
   CPositionRepository    *m_positions;
   CNewsBlackoutEvaluator *m_news;
   CRiskGuardChain        *m_guards;
   CStrategyOrchestrator  *m_strategies;
   CFilterChain           *m_filters;
   CRiskManager           *m_risk;
   CTradeRequestBuilder   *m_request_builder;
   CSessionStatistics     *m_session_stats;
   ILogger                *m_logger;
   IEventPublisher        *m_publisher;
   IClock                 *m_clock;

   //--- Per-pass working state.
   SDecisionContext        m_context;
   SSignal                 m_signal;
   SFilterChainResult      m_filter_result;
   SRiskDecision           m_risk_decision;
   STradeRequest           m_request;
   SPipelineOutcome        m_outcome;

   //--- Stage 1-6: assemble the immutable context every decision uses.
   bool              BuildContext(void);
   //--- Stage 7.
   bool              PassGuards(void);
   //--- Stage 8.
   bool              ResolveSignal(void);
   //--- Stage 9.
   bool              PassFilters(void);
   //--- Stage 10.
   bool              ResolveRisk(void);
   //--- Stage 11.
   bool              BuildRequest(void);

   void              Abort(const string stage,
                           const ENUM_SRP_VETO_REASON reason,
                           const string detail);

public:
                     CDecisionPipeline(void);
                    ~CDecisionPipeline(void) { }

   //--- Explicit setter injection. Verbose on purpose: the wiring is
   //--- visible in CEngineBootstrapper rather than hidden in a
   //--- service locator, so the dependency graph is auditable.
   void              SetDataSources(CMarketDataService *market_data,
                                    CMarketRegimeAnalyzer *regime,
                                    CAccountInfoProvider *account,
                                    CSymbolInfoProvider *symbol,
                                    CIndicatorManager *indicators,
                                    CPositionRepository *positions);
   void              SetDecisionModules(CNewsBlackoutEvaluator *news,
                                        CRiskGuardChain *guards,
                                        CStrategyOrchestrator *strategies,
                                        CFilterChain *filters,
                                        CRiskManager *risk,
                                        CTradeRequestBuilder *request_builder);
   void              SetInfrastructure(ILogger *logger,
                                       IEventPublisher *publisher,
                                       IClock *clock,
                                       CSessionStatistics *session_stats);

   //--- Confirms every mandatory collaborator was injected. The engine
   //--- refuses to start if this fails, so a wiring mistake surfaces
   //--- at init rather than as a null dereference on tick 10,000.
   bool              VerifyWiring(SValidationResult &result) const;

   //--- Run one full pass. 'engine_state' is supplied so the pipeline
   //--- never queries the state machine itself.
   bool              Execute(const ENUM_SRP_ENGINE_STATE engine_state);

   //--- Results, read by the engine and the dashboard.
   void              GetOutcome(SPipelineOutcome &out)      const { out=m_outcome; }
   void              GetContext(SDecisionContext &out)      const { out=m_context; }
   void              GetSignal(SSignal &out)                const { out=m_signal; }
   void              GetFilterResult(SFilterChainResult &out) const { out=m_filter_result; }
   void              GetRiskDecision(SRiskDecision &out)    const { out=m_risk_decision; }
   void              GetTradeRequest(STradeRequest &out)    const { out=m_request; }
  };

#endif // SRP_CORE_CDECISIONPIPELINE_MQH
//+------------------------------------------------------------------+
