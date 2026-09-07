//+------------------------------------------------------------------+
//|                                          CEngineBootstrapper.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : the composition root. The ONLY place that says 'new'.      |
//|                                                                  |
//|   RESPONSIBILITY (one only): construct the object graph and inject |
//|   dependencies. It contains zero trading logic.                    |
//|                                                                  |
//|   WHY A COMPOSITION ROOT                                          |
//|   Because every other class receives its collaborators through its |
//|   constructor, no class needs to know how to build anything. That  |
//|   is what makes each module independently testable and what keeps  |
//|   the Dependency Inversion Principle real rather than decorative.  |
//|   If you want to know what this product is made of, read this one  |
//|   file.                                                          |
//|                                                                  |
//|   ORDERING RULE                                                   |
//|   Build order is layered: infrastructure -> data -> analysis ->    |
//|   decision -> execution -> reporting -> UI. Registration order in  |
//|   CModuleRegistry mirrors it, so reverse-order teardown is always  |
//|   safe.                                                           |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CENGINEBOOTSTRAPPER_MQH
#define SRP_CORE_CENGINEBOOTSTRAPPER_MQH

#include "CTradingEngine.mqh"
#include "CServerClock.mqh"
#include "CModuleRegistry.mqh"
#include "CErrorHandler.mqh"
#include "CHealthMonitor.mqh"
#include "CDecisionPipeline.mqh"
#include "Events/CEventBus.mqh"
#include "Events/CEventListenerAdapter.mqh"
#include "Interfaces/IConfigProvider.mqh"

//--- Everything the bootstrapper creates, forward-declared.
class CLogger;
class CInputConfiguration;
//--- Any IStateStore implementation. The production graph injects
//--- CRiskStateStore; this scaffold names only the contract's role.
class CRiskStateStore;
class CSymbolInfoProvider;
class CAccountInfoProvider;
class CMarketDataService;
class CMarketRegimeAnalyzer;
class CIndicatorManager;
class CStrategyOrchestrator;
class CFilterChain;
class CRiskManager;
class CRiskGuardChain;
class CKillSwitch;
class CTradeRequestBuilder;
class CTradeExecutor;
class CPositionRepository;
class CPositionManager;
class CNewsService;
class CNewsBlackoutEvaluator;
class CStatisticsEngine;
class CSessionStatistics;
class CTradeJournal;
class CDashboardManager;
class CDashboardViewModel;
class CNotificationService;
class COptimizationGuard;

class CEngineBootstrapper
  {
private:
   //--- OWNED: infrastructure that is not an IModule.
   CLogger              *m_logger;
   CServerClock         *m_clock;
   CEventBus            *m_bus;
   CModuleRegistry      *m_registry;
   CErrorHandler        *m_errors;
   CHealthMonitor       *m_health;
   CDecisionPipeline    *m_pipeline;
   CInputConfiguration  *m_config;
   COptimizationGuard   *m_optimization_guard;
   CDashboardViewModel  *m_view_model;
   CTradingEngine       *m_engine;

   //--- OWNED: event adapters, one per observing module. Held here
   //--- because they are not modules and must outlive the bus.
   CEventListenerAdapter *m_adapters[];

   //--- BORROWED: modules owned by m_registry, cached for wiring.
   CSymbolInfoProvider    *m_symbol_info;
   CAccountInfoProvider   *m_account_info;
   CMarketDataService     *m_market_data;
   CMarketRegimeAnalyzer  *m_regime;
   CIndicatorManager      *m_indicators;
   CStrategyOrchestrator  *m_strategies;
   CFilterChain           *m_filters;
   CRiskManager           *m_risk;
   CRiskGuardChain        *m_guards;
   CKillSwitch            *m_kill_switch;
   CTradeRequestBuilder   *m_request_builder;
   CTradeExecutor         *m_executor;
   CPositionRepository    *m_positions;
   CPositionManager       *m_position_manager;
   CNewsService           *m_news_service;
   CNewsBlackoutEvaluator *m_news_evaluator;
   CStatisticsEngine      *m_statistics;
   CSessionStatistics     *m_session_stats;
   CTradeJournal          *m_journal;
   CDashboardManager      *m_dashboard;
   CNotificationService   *m_notifications;
   CRiskStateStore        *m_state_store;

   bool                    m_built;
   SValidationResult       m_validation;

   //--- Layered build steps, executed in this exact order.
   bool              BuildInfrastructure(void);
   bool              BuildConfiguration(void);
   bool              BuildDataProviders(void);
   bool              BuildIndicators(void);
   bool              BuildAnalysis(void);
   bool              BuildNews(void);
   bool              BuildRiskLayer(void);
   bool              BuildStrategies(void);
   bool              BuildFilters(void);
   bool              BuildTradeLayer(void);
   bool              BuildStatistics(void);
   bool              BuildDashboard(void);
   bool              WirePipeline(void);
   bool              WireEventSubscriptions(void);
   bool              WireEngine(void);

   //--- Adapter factory: creates, stores and subscribes an adapter for
   //--- a module that needs to observe the bus.
   CEventListenerAdapter *CreateAdapter(IModule *target);

   void              ReleaseOwned(void);

public:
                     CEngineBootstrapper(void);
                    ~CEngineBootstrapper(void);

   //--- Construct and wire everything. On failure the caller must call
   //--- Teardown() and abort OnInit with the validation report.
   bool              Build(void);

   //--- Destroy in the exact reverse of construction order.
   void              Teardown(void);

   //--- The fully wired engine, or NULL when Build() failed.
   CTradingEngine   *Engine(void) const { return(m_engine); }

   void              GetValidation(SValidationResult &out) const { out=m_validation; }
   string            ValidationReport(void) const { return(m_validation.report); }
  };

#endif // SRP_CORE_CENGINEBOOTSTRAPPER_MQH
//+------------------------------------------------------------------+
