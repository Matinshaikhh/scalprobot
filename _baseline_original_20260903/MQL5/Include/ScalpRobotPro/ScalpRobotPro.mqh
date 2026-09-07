//+------------------------------------------------------------------+
//|                                             ScalpRobotPro.mqh |
//|                          Scalping Robot Pro - THE UMBRELLA HEADER |
//|                                                                  |
//|   The .mq5 entry point includes only this file. Include order below is     |
//|   dependency order, bottom-up: types, then contracts, then bases, then     |
//|   infrastructure, then domain layers, then the composition root.           |
//|                                                                  |
//|   Every header additionally carries its own include guard and its own      |
//|   includes, so this file is a convenience rather than a requirement -      |
//|   any header can be included in isolation for testing.                     |
//|                                                                  |
//|   WHAT THIS HEADER DELIBERATELY DOES NOT INCLUDE                          |
//|                                                                  |
//|   The Phase 1 architectural scaffold - CTradingEngine,                     |
//|   CEngineBootstrapper, CDecisionPipeline and the domain classes they       |
//|   compose (Indicators\, Strategies\, Filters\, Risk\, Trade\ excluding      |
//|   Trade\Engine\, Dashboard\, Statistics\, News\) - is NOT included here.   |
//|                                                                  |
//|   Those files declare complete, correct contracts but were intentionally   |
//|   left without method bodies: they are the reference design this product   |
//|   grew from. Phases 2-5 then built fully implemented equivalents, and      |
//|   those are what this header wires:                                       |
//|                                                                  |
//|       scaffold (declaration-only)     implemented replacement            |
//|       ------------------------------  ------------------------------      |
//|       Indicators\                     Intelligence\Indicators\           |
//|       Strategies\                     Decision\Strategies\               |
//|       Filters\ + News\                Decision\Session\ + Decision\News\ |
//|       Risk\                           Intelligence\Risk\                 |
//|       Trade\ (rules, executor)        Trade\Engine\ + Interface\Manager\  |
//|       Dashboard\ + Statistics\        Interface\Dashboard\ + Analytics\   |
//|       Core\CTradingEngine             Runtime\CProductionEngine           |
//|                                                                  |
//|   MQL5 links a function body only when that function is CALLED, so        |
//|   including a bodiless declaration is legal until something calls it.     |
//|   Including the scaffold here would therefore compile but break the       |
//|   moment any consumer touched it - a trap rather than a convenience.      |
//|   Anything needing the scaffold as a reference includes it directly.      |
//+------------------------------------------------------------------+
#ifndef SRP_SCALPROBOTPRO_MQH
#define SRP_SCALPROBOTPRO_MQH

//==================================================================
// LAYER 0 - Shared vocabulary. Depends on nothing.
//==================================================================
#include "Core/Types/Constants.mqh"
#include "Core/Types/Enums.mqh"
#include "Core/Types/Structs.mqh"

//==================================================================
// LAYER 1 - Contracts. Depend only on Layer 0.
//==================================================================
#include "Core/Interfaces/ILogger.mqh"
#include "Core/Interfaces/ILogSink.mqh"
#include "Core/Interfaces/IClock.mqh"
#include "Core/Interfaces/IEventPublisher.mqh"
#include "Core/Interfaces/IEventListener.mqh"
#include "Core/Interfaces/IModule.mqh"
#include "Core/Interfaces/IConfigProvider.mqh"
#include "Core/Interfaces/IStateStore.mqh"
#include "Core/Interfaces/IIndicator.mqh"
#include "Core/Interfaces/IStrategy.mqh"
#include "Core/Interfaces/IFilter.mqh"
#include "Core/Interfaces/IRiskGuard.mqh"
#include "Core/Interfaces/IPositionSizer.mqh"
#include "Core/Interfaces/IStopLevelCalculator.mqh"
#include "Core/Interfaces/IPositionRule.mqh"
#include "Core/Interfaces/ITradeExecutor.mqh"
#include "Core/Interfaces/INewsProvider.mqh"
#include "Core/Interfaces/INotifier.mqh"
#include "Core/Interfaces/IWidget.mqh"

//==================================================================
// LAYER 2 - Stateless utilities. Reusable, no collaborators.
//==================================================================
#include "Utilities/CMathUtils.mqh"
#include "Utilities/CStringUtils.mqh"
#include "Utilities/CTimeUtils.mqh"
#include "Utilities/CPriceUtils.mqh"
#include "Utilities/CCircularBuffer.mqh"
#include "Utilities/CObjectNameFactory.mqh"
#include "Utilities/CFileReader.mqh"
#include "Utilities/CFileWriter.mqh"

//==================================================================
// LAYER 3 - Abstract bases. Absorb per-role boilerplate.
//==================================================================
#include "Core/Base/CModuleIdentity.mqh"
#include "Core/Base/CStrategyBase.mqh"
#include "Core/Base/CFilterBase.mqh"
#include "Core/Base/CIndicatorBase.mqh"
#include "Core/Base/CRiskGuardBase.mqh"
#include "Core/Base/CPositionRuleBase.mqh"
#include "Core/Base/CWidgetBase.mqh"

//==================================================================
// LAYER 4 - Infrastructure: logging, events, clock, kernel services.
//
// Only the sinks with real bodies are wired. Production file logging is
// CEnterpriseLogger's channel writer (Layer 9), which supersedes the
// scaffold's CFileLogSink.
//==================================================================
#include "Logger/CLogFormatter.mqh"
#include "Logger/CTerminalLogSink.mqh"
#include "Logger/CLogger.mqh"

#include "Core/Events/CEventBus.mqh"
#include "Core/Events/CEventListenerAdapter.mqh"

#include "Core/CServerClock.mqh"
#include "Core/CModuleRegistry.mqh"
#include "Core/CEngineStateMachine.mqh"
#include "Core/CErrorHandler.mqh"
#include "Core/CTickThrottle.mqh"

//==================================================================
// LAYER 5 - Configuration. Inputs stop here; modules read the provider.
//==================================================================
#include "Configuration/CConfigKeys.mqh"
#include "Configuration/CInputConfiguration.mqh"
#include "Configuration/CConfigValidator.mqh"
#include "Configuration/CConfigurationBuilder.mqh"

//==================================================================
// LAYER 6 - Market intelligence: indicators, structure, smart money.
//==================================================================
#include "Intelligence/Types/IntelligenceEnums.mqh"
#include "Intelligence/Types/IntelligenceStructs.mqh"
#include "Intelligence/Indicators/CIndicatorBuffer.mqh"
#include "Intelligence/Indicators/CIndicatorBase.mqh"
#include "Intelligence/Indicators/CStandardIndicators.mqh"
#include "Intelligence/Indicators/CComputedIndicators.mqh"
#include "Intelligence/Structure/CSwingDetector.mqh"
#include "Intelligence/Structure/CMarketStructure.mqh"
#include "Intelligence/SmartMoney/CZoneRegistry.mqh"
#include "Intelligence/SmartMoney/CDisplacementDetector.mqh"
#include "Intelligence/SmartMoney/CBlockDetector.mqh"
#include "Intelligence/SmartMoney/CLiquidityDetector.mqh"

//==================================================================
// LAYER 7 - Risk: state, sizing, limits, protective levels.
//==================================================================
#include "Intelligence/Risk/CRiskStateStore.mqh"
#include "Intelligence/Risk/CPositionSizers.mqh"
#include "Intelligence/Risk/CRiskLimitGuard.mqh"
#include "Intelligence/Risk/CProtectionManager.mqh"
#include "Intelligence/Risk/CRiskEngine.mqh"

//==================================================================
// LAYER 8 - Decision: sessions, news, strategies, confirmation, vote.
//==================================================================
#include "Decision/Types/DecisionEnums.mqh"
#include "Decision/Types/DecisionStructs.mqh"
#include "Decision/Session/CSessionManager.mqh"
#include "Decision/News/CNewsEngine.mqh"
#include "Decision/Strategies/CStrategyContext.mqh"
#include "Decision/Strategies/CStrategyPlugin.mqh"
#include "Decision/Strategies/CTrendStrategies.mqh"
#include "Decision/Strategies/CSmcStrategies.mqh"
#include "Decision/Strategies/COrderFlowStrategy.mqh"
#include "Decision/Confirmation/CConfirmationEngine.mqh"
#include "Decision/CDecisionEngine.mqh"

//==================================================================
// LAYER 9 - Execution. The ONLY door to the broker.
//==================================================================
#include "Trade/Engine/CMagicNumberManager.mqh"
#include "Trade/Engine/CBrokerManager.mqh"
#include "Trade/Engine/CExecutionEngine.mqh"
#include "Trade/Engine/COrderManager.mqh"
#include "Trade/Engine/CEnginePositionManager.mqh"
#include "Trade/Engine/CTradeEngine.mqh"

//==================================================================
// LAYER 10 - Trader interface: logging, analytics, dashboard, overlay,
// in-trade management. Structurally incapable of moving a stop loss
// except through the intents the engine chooses to apply.
//==================================================================
#include "Interface/Types/InterfaceEnums.mqh"
#include "Interface/Types/InterfaceStructs.mqh"
#include "Interface/Logging/CLogChannelWriter.mqh"
#include "Interface/Logging/CEnterpriseLogger.mqh"
#include "Interface/Analytics/CPerformanceAnalytics.mqh"
#include "Interface/Dashboard/CUiTheme.mqh"
#include "Interface/Dashboard/CObjectPainter.mqh"
#include "Interface/Dashboard/CDashboardPanel.mqh"
#include "Interface/Chart/CChartOverlay.mqh"
#include "Interface/Manager/CTradeManager.mqh"
#include "Interface/CTraderInterface.mqh"

//==================================================================
// LAYER 11 - Optimisation engine.
//==================================================================
#include "Optimization/COptimizationGuard.mqh"
#include "Optimization/COptimizationCriterion.mqh"
#include "Optimization/CParameterSetValidator.mqh"
#include "Optimization/CWalkForwardAnalyzer.mqh"
#include "Optimization/CMonteCarloSimulator.mqh"
#include "Optimization/CTesterIntegration.mqh"

//==================================================================
// LAYER 12 - THE COMPOSITION ROOT.
//
// CProductionEngine is the only class that says `new` on the trading
// path. Read Build() to see what the product is made of, and
// OnTickEvent() to see how a tick becomes a trade.
//==================================================================
#include "Runtime/CRuntimeConfig.mqh"
#include "Runtime/CProductionEngine.mqh"

#endif // SRP_SCALPROBOTPRO_MQH
//+------------------------------------------------------------------+
