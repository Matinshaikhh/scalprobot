//+------------------------------------------------------------------+
//|                                              CTradingEngine.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : the facade the .mq5 entry points talk to.                 |
//|                                                                  |
//|   RESPONSIBILITY (one only): translate terminal events            |
//|   (OnTick/OnTimer/OnTradeTransaction/OnChartEvent) into calls on   |
//|   the right collaborator, and own the engine's state transitions.  |
//|                                                                  |
//|   IT DOES NOT: read prices, size positions, evaluate filters,      |
//|   place orders, or draw anything. Those belong to the pipeline,    |
//|   the risk layer, the executor and the dashboard respectively.     |
//|   Keeping the engine this thin is what prevents the god-object     |
//|   that most commercial EAs collapse into.                          |
//|                                                                  |
//|   The .mq5 file contains no logic beyond forwarding to this class. |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CTRADINGENGINE_MQH
#define SRP_CORE_CTRADINGENGINE_MQH

#include "CEngineStateMachine.mqh"
#include "CModuleRegistry.mqh"
#include "CTickThrottle.mqh"
#include "CDecisionPipeline.mqh"
#include "CHealthMonitor.mqh"
#include "CErrorHandler.mqh"
#include "Events/CEventBus.mqh"
#include "Interfaces/IClock.mqh"
#include "Interfaces/ILogger.mqh"
#include "Interfaces/ITradeExecutor.mqh"
#include "Interfaces/IStateStore.mqh"

//--- Borrowed collaborators, forward-declared.
class CPositionManager;
class CPositionRepository;
class CDashboardManager;
class CStatisticsEngine;
class CSessionStatistics;
class CRiskGuardChain;
class CKillSwitch;
class CTradeJournal;

class CTradingEngine
  {
private:
   //--- Owned lifecycle helpers (value members: no allocation, no leak).
   CEngineStateMachine   m_state;
   CTickThrottle         m_throttle;

   //--- Borrowed infrastructure. The registry owns the modules; the
   //--- bootstrapper owns the non-module helpers.
   CModuleRegistry      *m_registry;
   CEventBus            *m_bus;
   ILogger              *m_logger;
   IClock               *m_clock;
   IStateStore          *m_state_store;
   CErrorHandler        *m_errors;
   CHealthMonitor       *m_health;
   CDecisionPipeline    *m_pipeline;
   ITradeExecutor       *m_executor;
   CPositionManager     *m_position_manager;
   CPositionRepository  *m_positions;
   CRiskGuardChain      *m_guards;
   CKillSwitch          *m_kill_switch;
   CDashboardManager    *m_dashboard;
   CStatisticsEngine    *m_statistics;
   CSessionStatistics   *m_session_stats;
   CTradeJournal        *m_journal;

   //--- Timing bookkeeping.
   datetime              m_last_heartbeat;
   datetime              m_last_day_checked;
   long                  m_tick_count;

   //--- Internal steps of OnTick, each one intention-revealing.
   void              ProcessDayBoundary(void);
   void              ProcessGuardFlattenDemands(void);
   void              ProcessOpenPositions(void);
   void              ProcessNewEntry(void);
   void              ExecuteApprovedRequest(void);
   void              ApplyErrorPolicy(void);

public:
                     CTradingEngine(void);
                    ~CTradingEngine(void) { }

   //--- Wiring, performed exclusively by CEngineBootstrapper ---------
   void              SetKernel(CModuleRegistry *registry,
                               CEventBus *bus,
                               ILogger *logger,
                               IClock *clock,
                               CErrorHandler *errors,
                               CHealthMonitor *health,
                               IStateStore *state_store);
   void              SetTradingModules(CDecisionPipeline *pipeline,
                                       ITradeExecutor *executor,
                                       CPositionManager *position_manager,
                                       CPositionRepository *positions,
                                       CRiskGuardChain *guards,
                                       CKillSwitch *kill_switch);
   void              SetReportingModules(CDashboardManager *dashboard,
                                         CStatisticsEngine *statistics,
                                         CSessionStatistics *session_stats,
                                         CTradeJournal *journal);
   void              SetThrottleIntervalMs(const int ms);

   //--- Lifecycle, called from the .mq5 entry points ------------------
   //--- Returns an INIT_* code so OnInit can propagate it verbatim.
   int               Start(void);
   void              Stop(const int deinit_reason);

   //--- Terminal event forwarding ------------------------------------
   void              OnTickEvent(void);
   void              OnTimerEvent(void);
   void              OnTradeTransactionEvent(const MqlTradeTransaction &transaction,
                                             const MqlTradeRequest &request,
                                             const MqlTradeResult &result);
   void              OnChartEventReceived(const int id,const long &lparam,
                                          const double &dparam,const string &sparam);
   //--- Tester-only optimisation criterion hook.
   double            OnTesterEvent(void);

   //--- Operator commands, exposed for the dashboard and hooks -------
   bool              Pause(const string reason);
   bool              Resume(const string reason);
   bool              EnterManageOnlyMode(const string reason);
   bool              Halt(const string reason);

   //--- Queries ------------------------------------------------------
   ENUM_SRP_ENGINE_STATE State(void) const { return(m_state.State()); }
   long              TickCount(void) const { return(m_tick_count); }
  };

#endif // SRP_CORE_CTRADINGENGINE_MQH
//+------------------------------------------------------------------+
