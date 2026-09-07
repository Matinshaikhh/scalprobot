//+------------------------------------------------------------------+
//|                                         CProductionEngine.mqh |
//|                    Scalping Robot Pro - Production Runtime (P5) |
//|                                                                  |
//|   THE COMPOSITION ROOT. This is the single class that owns the whole    |
//|   object graph and turns a terminal event into a trade.                |
//|                                                                  |
//|   RESPONSIBILITY (one only): construct the modules in dependency        |
//|   order, sequence the per-tick pipeline, and destroy everything in      |
//|   exact reverse. It performs no analysis, no sizing, no drawing and     |
//|   no order sending of its own - every line is delegation.              |
//|                                                                  |
//|   WHY IT REPLACES THE PHASE 1 CTradingEngine                          |
//|   CTradingEngine was declared against the Phase 1 scaffold, whose       |
//|   filters, guards, sizers and strategies were left declaration-only by  |
//|   design. Phases 2-4 then built fully implemented equivalents           |
//|   (CRiskEngine, CDecisionEngine, CTradeEngine, CTraderInterface). This  |
//|   class wires the IMPLEMENTED stack. The scaffold is left untouched     |
//|   as the architectural reference it was written to be.                 |
//|                                                                  |
//|   THE PIPELINE, in fixed order, and the order is the whole design:      |
//|     1. throttle          - cheapest possible early exit                |
//|     2. refresh state     - account, positions, indicators              |
//|     3. manage open trades- protect capital BEFORE seeking more risk     |
//|     4. risk gate         - guards may forbid or demand flatten         |
//|     5. decide            - strategies, confirmation, session, news      |
//|     6. size and protect  - risk engine produces volume, stop, target   |
//|     7. execute           - trade engine sends the order                |
//|     8. render            - dashboard and overlay, last and optional     |
//|                                                                  |
//|   MANAGEMENT BEFORE ENTRY IS DELIBERATE. An engine that looks for a     |
//|   new signal before trailing an open winner will, on a fast tick,       |
//|   add risk while an existing position sits unprotected.                |
//|                                                                  |
//|   OWNERSHIP IS TOTAL AND SINGLE. Every pointer this class news, it      |
//|   deletes, in reverse order, exactly once. Modules that receive a       |
//|   pointer borrow it and never delete it. The two exceptions are         |
//|   documented at their assignment: CDecisionEngine takes ownership of    |
//|   its plugins and its confirmation engine.                             |
//+------------------------------------------------------------------+
#ifndef SRP_RUNTIME_CPRODUCTIONENGINE_MQH
#define SRP_RUNTIME_CPRODUCTIONENGINE_MQH

#include "../Core/CServerClock.mqh"
#include "../Core/Events/CEventBus.mqh"
#include "../Decision/CDecisionEngine.mqh"
#include "../Decision/Strategies/CSmcStrategies.mqh"
#include "../Decision/Strategies/CTrendStrategies.mqh"
#include "../Decision/Strategies/CStructureStrategies.mqh"
#include "../Decision/Strategies/COrderFlowStrategy.mqh"
#include "../Intelligence/Risk/CProtectionManager.mqh"
#include "../Intelligence/Risk/CRiskEngine.mqh"
#include "../Intelligence/Risk/CRiskLimitGuard.mqh"
#include "../Intelligence/Risk/CRiskStateStore.mqh"
#include "../Intelligence/Risk/CPositionSizers.mqh"
#include "../Intelligence/SmartMoney/CBlockDetector.mqh"
#include "../Intelligence/SmartMoney/CDisplacementDetector.mqh"
#include "../Intelligence/SmartMoney/CLiquidityDetector.mqh"
#include "../Interface/CTraderInterface.mqh"
#include "../Optimization/COptimizationGuard.mqh"
#include "../Profiles/CRegimeEngine.mqh"
#include "../Profiles/CScalpController.mqh"
#include "../Profiles/CAccuracyFilter.mqh"
#include "../Optimization/COptimizationCriterion.mqh"
#include "../Optimization/CMonteCarloSimulator.mqh"
#include "../Optimization/CTesterIntegration.mqh"
#include "../Trade/Engine/CTradeEngine.mqh"
#include "CRuntimeConfig.mqh"

class CProductionEngine
  {
private:
   SRuntimeConfig         m_config;
   //--- The asset's parameter set. Held so the regime engine can use this
   //--- asset's own thresholds rather than a global set, which is what
   //--- keeps NASDAQ and gold genuinely independent.
   SMarketProfile         m_market_profile;

   //=== OWNED, in construction order ==================================
   CServerClock          *m_clock;
   CEventBus             *m_bus;
   COptimizationGuard    *m_env;
   //--- Indicators.
   CEmaIndicator         *m_ema_fast;
   CEmaIndicator         *m_ema_slow;
   CEmaIndicator         *m_ema_trend;
   CSmaIndicator         *m_sma;
   CAtrIntel             *m_atr;
   CRsiIntel             *m_rsi;
   CAdxIntel             *m_adx;
   CMacdIntel            *m_macd;
   CBollingerIntel       *m_bollinger;
   CCciIntel             *m_cci;
   CStochasticIntel      *m_stochastic;
   CIchimokuIntel        *m_ichimoku;
   CObvIntel             *m_obv;
   CMfiIntel             *m_mfi;
   CVwapIndicator        *m_vwap;
   CVolumeIndicator      *m_volume;
   //--- Structure and smart money.
   CSwingDetector        *m_swings;
   CMarketStructure      *m_structure;
   CZoneRegistry         *m_zones;
   CDisplacementDetector *m_displacement;
   CBlockDetector        *m_blocks;
   CLiquidityDetector    *m_liquidity;
   //--- Risk.
   CRiskStateStore       *m_risk_state;
   CSizerBase            *m_sizer;
   CRiskLimitGuard       *m_limits;
   CProtectionManager    *m_protection;
   CRiskEngine           *m_risk;
   //--- Regime. Its indicators live on the CONTEXT timeframe (M15 by
   //--- default), separate from the execution-timeframe set above: an M1
   //--- reading of "trend" is noise, so classification must not use it.
   CAdxIntel             *m_adx_context;
   CAtrIntel             *m_atr_context;
   //--- ATR on the SETUP timeframe, for the wider scalp tier.
   CAtrIntel             *m_atr_setup;
   //--- EMAs on the SETUP and CONTEXT timeframes. These exist solely so
   //--- multi-timeframe agreement can be measured: the execution EMAs say
   //--- what M1 thinks, and M1 agreeing with itself is not corroboration.
   CEmaIndicator         *m_ema_setup;
   CEmaIndicator         *m_ema_context;
   //--- ENTRY QUALITY GATE. Owned. Refuse-only: it returns no size, no
   //--- stop and no target, so it can only ever reduce the trade count.
   CAccuracyFilter       *m_accuracy;
   CRegimeEngine         *m_regime;
   //--- Ultra-scalp mode. Owned. Gates entries on duplicate signals and
   //--- round-trip cost; never sizes, never sends an order.
   CScalpController      *m_scalp;
   //--- Per-position scalp bookkeeping, so a timeout or early exit can be
   //--- attributed to the position that earned it.
   ulong                  m_scalp_tickets[16];
   double                 m_scalp_targets[16];
   //--- The TIER each open scalp was entered under, and the hold window
   //--- that tier granted it. Held per position because several tiers can
   //--- be open at once and a SUPER_SCALP must not inherit a SWING window.
   int                    m_scalp_tiers[16];
   int                    m_scalp_holds[16];
   int                    m_scalp_tracked;
   //--- Decision.
   CSessionManager       *m_sessions;
   CNewsEngine           *m_news;
   CStrategyContext      *m_context;
   CDecisionEngine       *m_decision;
   //--- Execution.
   CTradeEngine          *m_trade;
   //--- Interface (owns its own logger, dashboard, overlay, manager,
   //--- analytics).
   CTraderInterface      *m_ui;
   //--- Optimisation. Built last because it reads the tester's own
   //--- statistics and touches nothing on the trading path.
   COptimizationCriterion *m_criterion;
   CMonteCarloSimulator  *m_monte_carlo;
   CTesterIntegration    *m_tester;

   //=== STATE ========================================================
   bool                   m_built;
   bool                   m_running;
   //--- True in the tester, where a real-time tick throttle would discard
   //--- simulated ticks and corrupt the result. Resolved once at build.
   bool                   m_throttle_disabled;
   string                 m_halt_reason;
   datetime               m_last_bar;
   datetime               m_last_managed_bar;
   ulong                  m_last_tick_ms;
   long                   m_ticks;
   long                   m_entries;
   long                   m_managed_actions;
   //--- Stop price of the most recent entry, kept so a closed trade can
   //--- be attributed a real risk amount and therefore a real R-multiple.
   //--- Approximate when several positions are open at once, which is why
   //--- the R metric is documented as indicative rather than exact.
   double                 m_last_entry_stop;
   double                 m_session_start_balance;
   string                 m_validation_report;

   //=== ENTRY-STAGE FUNNEL ============================================
   //--- The decision engine's funnel ends at "actionable". Between that
   //--- and an order there were four further gates, every one of which
   //--- returned SILENTLY. On a 31-month XAUUSD pass that gap swallowed
   //--- 1268 of 1313 actionable decisions with no record of which gate
   //--- did it, which made the shortfall look like setup scarcity when it
   //--- was not. These count each one.
   long                   m_gate_pre_risk;      // risk/exposure pre-check
   long                   m_gate_risk_rating;   // rating above the ceiling
   long                   m_gate_direction;     // direction mode
   long                   m_gate_accuracy;      // multi-timeframe/volume gate
   long                   m_gate_scalp;         // scalp controller
   long                   m_gate_risk_engine;   // sizing/protection refusal

   //--- Construction steps, one per subsystem.
   bool              BuildKernel(void);
   bool              BuildIndicators(void);
   bool              BuildStructure(void);
   bool              BuildRisk(void);
   bool              BuildDecision(void);
   bool              BuildExecution(void);
   bool              BuildInterface(void);
   bool              BuildOptimization(void);
   void              Release(void);

   CSizerBase       *CreateSizer(void);

   //--- Pipeline steps.
   bool              PassesThrottle(void);
   void              RefreshAnalysis(const bool is_new_bar);
   void              RefreshAccountState(void);
   void              ManageOpenPositions(void);
   bool              RiskAllowsEntry(SRiskVerdict &verdict);
   //--- Which scalp tier suits the CURRENT market, not the current wish.
   ENUM_SRP_SCALP_TIER SelectScalpTier(void) const;
   void              SeekEntry(const bool is_new_bar);
   void              Render(void);
   void              BuildDashboardModel(SDashboardModel &model);
   //--- Scalp bookkeeping. Each tracked ticket keeps the target it was
   //--- entered with, so an early exit can be measured against the right
   //--- figure when several positions are open at once.
   void              TrackScalp(const ulong ticket,const double target_points,
                                const ENUM_SRP_SCALP_TIER tier,
                                const int hold_seconds);
   void              UntrackScalp(const ulong ticket);
   double            ScalpTargetFor(const ulong ticket) const;
   ENUM_SRP_SCALP_TIER ScalpTierFor(const ulong ticket) const;
   int               ScalpHoldFor(const ulong ticket) const;
   //--- CLOSED-TIER MEMORY.
   //---
   //--- The tier lookup is keyed on an OPEN position, but a scalp closed by
   //--- this engine is untracked immediately and the close notification
   //--- arrives afterwards, so by then the key is gone and every
   //--- engine-closed exit was attributed to the default tier. That put all
   //--- the early-profit wins under STANDARD and all the broker-side stops
   //--- under SWING, producing a 99% and a 2% win rate that described the
   //--- exit route rather than the tier. The tier is therefore remembered
   //--- across the gap.
   void              RememberClosedTier(const ulong ticket,
                                        const ENUM_SRP_SCALP_TIER tier);
   ENUM_SRP_SCALP_TIER RecallClosedTier(const ulong ticket) const;
   ulong                  m_closed_tickets[32];
   int                    m_closed_tiers[32];
   int                    m_closed_cursor;
   //--- Scalp-specific exits: early profit and holding-window timeout.
   //--- Returns true when the position was closed here.
   bool              ApplyScalpExits(const SManagedPosition &position);

   //--- Reads one live position into the interface's view of it.
   bool              LoadPosition(const int index,SManagedPosition &out);
   void              ApplyIntent(const STradeIntent &intent,
                                 const SManagedPosition &position);
   double            TotalOpenLots(void) const;
   double            ExposureRiskPercent(void) const;

public:
                     CProductionEngine(void);
                    ~CProductionEngine(void);

   //=== LIFECYCLE ====================================================
   //--- Build reads configuration, constructs everything and validates.
   //--- Returns false with a populated report rather than half-building.
   bool              Build(IConfigProvider *config,
                          const string symbol,
                          const ENUM_TIMEFRAMES timeframe);
   int               Start(void);
   void              Stop(const int deinit_reason);

   //=== TERMINAL EVENTS ==============================================
   void              OnTickEvent(void);
   void              OnTimerEvent(void);
   void              OnTradeTransactionEvent(const MqlTradeTransaction &transaction,
                                             const MqlTradeRequest &request,
                                             const MqlTradeResult &result);
   void              OnChartEventReceived(const int id,const long &lparam,
                                          const double &dparam,
                                          const string &sparam);
   //--- Strategy Tester fitness. Returns the configured criterion's score
   //--- for the pass, which is what the genetic optimiser ranks on.
   double            OnTesterEvent(void);

   //=== OPERATOR COMMANDS ============================================
   void              Halt(const string reason);
   void              Resume(const string reason);
   bool              IsRunning(void) const { return(m_running); }
   //--- Flattens everything through the trade engine and arms the
   //--- emergency latch, so nothing re-enters until acknowledged.
   int               EmergencyFlatten(const string reason);

   //=== ACCESS (borrowed, never delete) ==============================
   CTraderInterface *Interface(void)  { return(m_ui); }
   CTradeEngine     *Trade(void)      { return(m_trade); }
   CRiskEngine      *Risk(void)       { return(m_risk); }
   CDecisionEngine  *Decision(void)   { return(m_decision); }
   COptimizationGuard *Environment(void) { return(m_env); }
   CTesterIntegration *Tester(void)   { return(m_tester); }
   CRegimeEngine    *Regime(void)     { return(m_regime); }
   CScalpController *Scalp(void)      { return(m_scalp); }
   void              GetMarketProfile(SMarketProfile &out) const
     { out=m_market_profile; }
   void              GetConfig(SRuntimeConfig &out) const { out=m_config; }

   bool              IsBuilt(void) const { return(m_built); }
   string            ValidationReport(void) const { return(m_validation_report); }
   long              TickCount(void) const { return(m_ticks); }
   long              EntryCount(void) const { return(m_entries); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CProductionEngine::CProductionEngine(void)
  : m_clock(NULL),m_bus(NULL),m_env(NULL),
    m_ema_fast(NULL),m_ema_slow(NULL),m_ema_trend(NULL),m_sma(NULL),
    m_atr(NULL),m_rsi(NULL),m_adx(NULL),m_macd(NULL),m_bollinger(NULL),
    m_cci(NULL),m_stochastic(NULL),m_ichimoku(NULL),m_obv(NULL),
    m_mfi(NULL),m_vwap(NULL),m_volume(NULL),
    m_swings(NULL),m_structure(NULL),m_zones(NULL),
    m_displacement(NULL),m_blocks(NULL),m_liquidity(NULL),
    m_risk_state(NULL),m_sizer(NULL),m_limits(NULL),
    m_protection(NULL),m_risk(NULL),
    m_adx_context(NULL),m_atr_context(NULL),m_atr_setup(NULL),
    m_ema_setup(NULL),m_ema_context(NULL),m_accuracy(NULL),m_regime(NULL),
    m_scalp(NULL),m_scalp_tracked(0),m_closed_cursor(0),
    m_sessions(NULL),m_news(NULL),m_context(NULL),m_decision(NULL),
    m_trade(NULL),m_ui(NULL),
    m_criterion(NULL),m_monte_carlo(NULL),m_tester(NULL),
    m_built(false),m_running(false),m_throttle_disabled(false),
    m_halt_reason(""),
    m_gate_pre_risk(0),m_gate_risk_rating(0),m_gate_direction(0),
    m_gate_accuracy(0),m_gate_scalp(0),m_gate_risk_engine(0),
    m_last_bar(0),m_last_managed_bar(0),m_last_tick_ms(0),
    m_ticks(0),m_entries(0),m_managed_actions(0),m_last_entry_stop(0.0),
    m_session_start_balance(0.0),m_validation_report("")
  {
  }
//+------------------------------------------------------------------+
CProductionEngine::~CProductionEngine(void)
  {
   Release();
  }
//+------------------------------------------------------------------+
//| BUILD. Ordered by dependency: kernel, indicators, structure, risk,   |
//| decision, execution, interface. A failure at any step reports and    |
//| releases rather than leaving a half-built graph running.              |
//+------------------------------------------------------------------+
bool CProductionEngine::Build(IConfigProvider *config,
                              const string symbol,
                              const ENUM_TIMEFRAMES timeframe)
  {
   if(m_built)
      return(true);

   CRuntimeConfig::Load(config,symbol,timeframe,m_config);

   //--- THE ASSET'S PARAMETER SET.
   //---
   //--- Resolved here so the regime engine classifies against THIS
   //--- instrument's thresholds. The entry point already applied the
   //--- profile to the configuration, so this call re-derives the same
   //--- profile rather than introducing a second source of truth: the
   //--- values the engine runs on still come from the sealed config.
   //--- What the profile object adds is the fields the config does not
   //--- carry - volatility bands and regime thresholds.
   SSymbolProfile symbol_spec;
   CSymbolClassifier::Resolve(symbol,symbol_spec);
   CMarketProfileFactory::Build(symbol_spec,m_market_profile);
   //--- Configuration wins where it overlaps, because the trader may have
   //--- overridden the preset and the engine must honour that.
   m_market_profile.context_timeframe=(ENUM_TIMEFRAMES)m_config.context_timeframe;
   m_market_profile.setup_timeframe=(ENUM_TIMEFRAMES)m_config.setup_timeframe;
   m_market_profile.adx_period=m_config.adx_period;
   m_market_profile.atr_period=m_config.atr_period;

   SValidationResult result;
   if(!BuildKernel())        result.AddError("kernel construction failed");
   else if(!BuildIndicators())result.AddError("indicator construction failed");
   else if(!BuildStructure()) result.AddError("structure construction failed");
   else if(!BuildRisk())      result.AddError("risk construction failed");
   else if(!BuildDecision())  result.AddError("decision construction failed");
   else if(!BuildExecution()) result.AddError("execution construction failed");
   else if(!BuildInterface()) result.AddError("interface construction failed");
   else if(!BuildOptimization()) result.AddError("optimisation construction failed");

   if(!result.is_valid)
     {
      m_validation_report=result.report;
      Release();
      return(false);
     }

   //--- Every subsystem reports its own health. Collecting it here means
   //--- one report explains a failed startup completely.
   if(m_risk!=NULL)      m_risk.Validate(result);
   if(m_decision!=NULL)  m_decision.Validate(result);
   if(m_trade!=NULL)     m_trade.Validate(result);
   if(m_ui!=NULL)        m_ui.Validate(result);
   if(m_context!=NULL)   m_context.Validate(result);
   //--- The accuracy gate reports its own wiring. A volume floor with no
   //--- volume series, or required agreement with no higher-timeframe EMA,
   //--- is an inert filter that looks active - which this refuses to be.
   if(m_accuracy!=NULL)  m_accuracy.Validate(result);
   if(m_scalp!=NULL)     m_scalp.Validate(result);

   m_validation_report=result.report;
   if(!result.is_valid)
     {
      Release();
      return(false);
     }
   m_built=true;
   return(true);
  }
//+------------------------------------------------------------------+
bool CProductionEngine::BuildKernel(void)
  {
   m_clock=new CServerClock();
   m_bus=new CEventBus();
   if(m_clock==NULL || m_bus==NULL)
      return(false);
   m_env=new COptimizationGuard(m_clock);
   if(m_env==NULL)
      return(false);
   //--- Resolved once here rather than queried per tick: the environment
   //--- cannot change mid-run, and the throttle sits on the hottest path
   //--- in the product.
   m_throttle_disabled=m_env.IsTester();
   return(true);
  }
//+------------------------------------------------------------------+
bool CProductionEngine::BuildIndicators(void)
  {
   const string s=m_config.symbol;
   const ENUM_TIMEFRAMES t=m_config.timeframe;
   //--- The interface owns the enterprise logger, which does not exist
   //--- yet, so indicators are constructed with no logger and inherit
   //--- one only where a module genuinely needs to log. Passing a
   //--- half-built logger here would be worse than passing none.
   ILogger *nolog=NULL;

   m_ema_fast   = new CEmaIndicator(s,t,m_config.fast_ma_period,nolog);
   m_ema_slow   = new CEmaIndicator(s,t,m_config.slow_ma_period,nolog);
   m_ema_trend  = new CEmaIndicator(s,t,m_config.trend_ma_period,nolog);
   m_sma        = new CSmaIndicator(s,t,m_config.slow_ma_period,nolog);
   m_atr        = new CAtrIntel(s,t,m_config.atr_period,nolog);
   m_rsi        = new CRsiIntel(s,t,m_config.rsi_period,nolog);
   m_adx        = new CAdxIntel(s,t,m_config.adx_period,nolog);
   m_macd       = new CMacdIntel(s,t,12,26,9,nolog);
   m_bollinger  = new CBollingerIntel(s,t,m_config.bollinger_period,
                                      m_config.bollinger_deviation,nolog);
   m_cci        = new CCciIntel(s,t,14,nolog);
   m_stochastic = new CStochasticIntel(s,t,5,3,3,nolog);
   m_ichimoku   = new CIchimokuIntel(s,t,9,26,52,nolog);
   m_obv        = new CObvIntel(s,t,nolog);
   m_mfi        = new CMfiIntel(s,t,14,nolog);
   m_vwap       = new CVwapIndicator(s,t,nolog,0);
   m_volume     = new CVolumeIndicator(s,t,nolog);

   if(m_ema_fast==NULL || m_ema_slow==NULL || m_ema_trend==NULL ||
      m_sma==NULL || m_atr==NULL || m_rsi==NULL || m_adx==NULL ||
      m_macd==NULL || m_bollinger==NULL || m_cci==NULL ||
      m_stochastic==NULL || m_ichimoku==NULL || m_obv==NULL ||
      m_mfi==NULL || m_vwap==NULL || m_volume==NULL)
      return(false);

   //--- A handle failure here is fatal: every downstream decision would
   //--- silently read zeroes.
   if(!m_ema_fast.Initialize() || !m_ema_slow.Initialize() ||
      !m_ema_trend.Initialize() || !m_sma.Initialize() ||
      !m_atr.Initialize() || !m_rsi.Initialize() || !m_adx.Initialize() ||
      !m_macd.Initialize() || !m_bollinger.Initialize() ||
      !m_cci.Initialize() || !m_stochastic.Initialize() ||
      !m_ichimoku.Initialize() || !m_obv.Initialize() ||
      !m_mfi.Initialize() || !m_vwap.Initialize() || !m_volume.Initialize())
      return(false);
   return(true);
  }
//+------------------------------------------------------------------+
bool CProductionEngine::BuildStructure(void)
  {
   const string s=m_config.symbol;
   const ENUM_TIMEFRAMES t=m_config.timeframe;
   ILogger *nolog=NULL;

   m_swings=new CSwingDetector(s,t,nolog,m_config.smc_swing_strength,
                               m_config.smc_swing_lookback,64);
   if(m_swings==NULL || !m_swings.Initialize())
      return(false);

   m_structure=new CMarketStructure(s,t,m_swings,nolog);
   if(m_structure==NULL)
      return(false);
   m_structure.SetRangeSwingCount(8);
   m_structure.SetBreakBuffer(m_config.smc_structure_break_buffer);
   if(!m_structure.Initialize())
      return(false);

   m_zones=new CZoneRegistry(nolog,m_config.smc_zone_capacity);
   if(m_zones==NULL)
      return(false);
   m_zones.SetCapacity(m_config.smc_zone_capacity);
   m_zones.SetMaxAgeBars(m_config.smc_zone_max_age_bars);

   m_displacement=new CDisplacementDetector(s,t,m_atr,nolog);
   if(m_displacement==NULL)
      return(false);

   m_blocks=new CBlockDetector(s,t,m_displacement,m_zones,nolog);
   if(m_blocks==NULL)
      return(false);
   m_blocks.SetVolumeIndicator(m_volume);
   m_blocks.SetMinGapPoints(m_config.smc_min_gap_points);
   m_blocks.SetRequireDisplacement(m_config.smc_require_displacement);

   m_liquidity=new CLiquidityDetector(s,t,m_swings,m_atr,m_zones,nolog);
   if(m_liquidity==NULL)
      return(false);
   m_liquidity.SetEqualTolerance(m_config.smc_equal_tolerance_atr);
   m_liquidity.SetSweepLookback(m_config.smc_sweep_lookback_bars);
   return(true);
  }
//+------------------------------------------------------------------+
//| Sizer selection is the only place a sizing model is chosen. Adding a |
//| seventh model means one case here and one new class - nothing else   |
//| in the engine changes.                                              |
//+------------------------------------------------------------------+
CSizerBase *CProductionEngine::CreateSizer(void)
  {
   ILogger *nolog=NULL;
   //--- The capital reference is a configured choice, not an assumption.
   //--- Equity includes floating P/L, so sizing shrinks while losing -
   //--- which is why it is the default for a scalper.
   const ENUM_SRP_CAPITAL_BASE base=
      (ENUM_SRP_CAPITAL_BASE)m_config.risk_capital_base;

   switch((ENUM_SRP_SIZING_MODEL)m_config.risk_model)
     {
      case SRP_SIZING_FIXED_LOT:
         return(new CFixedLotModel(m_config.fixed_lot,nolog));
      case SRP_SIZING_RISK_PERCENT:
         return(new CRiskPercentModel(m_config.risk_percent,base,nolog));
      case SRP_SIZING_AUTO_LOT:
         return(new CAutoLotModel(m_config.auto_lot_capital_per_step,
                                  m_config.auto_lot_per_step,nolog));
      case SRP_SIZING_KELLY:
         return(new CKellyModel(nolog,m_config.kelly_min_trades,
                                m_config.kelly_fraction,
                                m_config.risk_percent));
      case SRP_SIZING_ATR:
         return(new CAtrSizingModel(m_config.risk_percent,
                                    m_config.atr_risk_multiple,nolog));
      case SRP_SIZING_DYNAMIC:
         return(new CDynamicSizingModel(m_config.risk_percent,nolog));
     }
   //--- Unknown model: fall back to the most conservative option rather
   //--- than refusing to start. Fixed minimum lot cannot surprise anyone.
   return(new CFixedLotModel(m_config.fixed_lot,nolog));
  }
//+------------------------------------------------------------------+
bool CProductionEngine::BuildRisk(void)
  {
   ILogger *nolog=NULL;

   //--- The state file is namespaced per symbol and magic, so two charts
   //--- running the robot never overwrite each other's latched guards.
   const string state_file=StringFormat("%s\\risk_state_%s_%I64d.csv",
                                        m_config.state_folder,
                                        m_config.symbol,m_config.magic);
   m_risk_state=new CRiskStateStore(state_file,nolog);
   if(m_risk_state==NULL)
      return(false);
   //--- State persistence is suppressed in the tester: state leaking from
   //--- pass N into pass N+1 invalidates an optimisation silently. The
   //--- environment guard owns that decision, not this method.
   const bool persist=(m_config.persist_state &&
                       (m_env==NULL || m_env.ShouldEnableStatePersistence()));
   m_risk_state.SetEnabled(persist);
   if(persist && !m_risk_state.Initialize())
      return(false);

   m_sizer=CreateSizer();
   if(m_sizer==NULL)
      return(false);

   m_limits=new CRiskLimitGuard(nolog,m_risk_state);
   if(m_limits==NULL)
      return(false);
   m_limits.SetDailyLossLimit(m_config.daily_loss_percent,
                              m_config.flatten_on_trip);
   m_limits.SetWeeklyLossLimit(m_config.weekly_loss_percent);
   m_limits.SetMonthlyLossLimit(m_config.monthly_loss_percent);
   m_limits.SetMaxDrawdown(m_config.max_drawdown_percent,
                           m_config.flatten_on_trip);
   m_limits.SetMaxExposure(m_config.max_exposure_percent,m_config.max_lot);

   m_protection=new CProtectionManager(m_config.symbol,m_atr,nolog);
   if(m_protection==NULL)
      return(false);
   m_protection.SetSwingDetector(m_swings);
   m_protection.ConfigureStop((ENUM_SRP_STOP_MODEL)m_config.sl_model,
                              m_config.sl_fixed_points,
                              m_config.sl_atr_multiplier);
   m_protection.ConfigureTarget((ENUM_SRP_TARGET_MODEL)m_config.tp_model,
                                m_config.tp_fixed_points,
                                m_config.tp_atr_multiplier,
                                m_config.tp_risk_reward);
   m_protection.ConfigureBreakEven(m_config.breakeven_enabled,
                                   m_config.breakeven_trigger_points,
                                   m_config.breakeven_offset_points);
   m_protection.ConfigureTrailing(m_config.trail_mode!=0,
                                  m_config.trail_start_points,
                                  m_config.trail_distance_points,
                                  m_config.trail_step_points);
   m_protection.ConfigureAtrTrailing(m_config.tm_atr_trail_enabled,
                                     m_config.tm_atr_trail_multiple,
                                     m_config.trail_step_points);
   m_protection.ConfigureProfitLock(m_config.profit_lock_enabled,
                                    m_config.profit_lock_trigger_percent,
                                    m_config.profit_lock_keep_percent);

   m_risk=new CRiskEngine(m_config.symbol,m_atr,nolog);
   if(m_risk==NULL)
      return(false);
   m_risk.SetSizer(m_sizer);
   m_risk.SetLimitGuard(m_limits);
   m_risk.SetProtectionManager(m_protection);
   m_risk.SetSwingDetector(m_swings);
   m_risk.SetMaxRiskPercentPerTrade(m_config.risk_percent);
   m_risk.SetMaxVolume(m_config.max_lot);
   return(true);
  }
//+------------------------------------------------------------------+
bool CProductionEngine::BuildDecision(void)
  {
   const string s=m_config.symbol;
   ILogger *nolog=NULL;

   m_sessions=new CSessionManager(s,nolog);
   if(m_sessions==NULL)
      return(false);

   //--- SESSION SELECTION, WIRED IN PHASE 6.
   //---
   //--- These four inputs were read into configuration and printed in the
   //--- startup log but NEVER applied: every window stayed enabled, so a
   //--- trader who disabled Asia was still trading it. The window setters
   //--- existed and worked; nothing called them. Passing the allow_*
   //--- flags is what makes the session inputs mean something.
   //---
   //--- Window times come from the market profile, so gold's London-led
   //--- schedule and NASDAQ's US-led one are genuinely different rather
   //--- than sharing one hardcoded set of GMT constants.
   m_sessions.SetSydneyWindow(21*60,6*60,m_config.allow_sydney);
   m_sessions.SetTokyoWindow(0,9*60,m_config.allow_tokyo);
   m_sessions.SetLondonWindow(m_config.london_open_gmt,
                              m_config.london_close_gmt,
                              m_config.allow_london);
   m_sessions.SetNewYorkWindow(m_config.newyork_open_gmt,
                               m_config.newyork_close_gmt,
                               m_config.allow_newyork);

   //--- The asset's primary kill zone. For NASDAQ this is the US cash
   //--- open; for gold it is the London open. Previously both used the
   //--- same hardcoded constants.
   m_sessions.SetNewYorkOpenKillZone(m_config.primary_kz_open_gmt,
                                     m_config.primary_kz_close_gmt);

   //--- SESSION EDGES. The widest spreads of the day sit either side of a
   //--- session boundary. Skipping them costs a few setups and avoids
   //--- paying the spike, which is the better side of that trade.
   m_sessions.SetSessionEdgeSkip(m_config.skip_after_open_minutes,
                                 m_config.skip_before_close_minutes);

   m_sessions.SetWeekendFilter(m_config.weekend_filter,
                               m_config.friday_close_minutes,0);
   m_sessions.SetHolidayFilter(m_config.holiday_filter_enabled,true);
   m_sessions.SetKillZones(m_config.kill_zones_only);
   //--- OVERLAP requirement. Read from config since Phase 3, applied only
   //--- now: it had been stored and ignored, so a trader who asked for the
   //--- London/NY overlap was silently allowed either session alone.
   m_sessions.SetRequireOverlap(m_config.require_overlap);

   //=== THE MASTER SWITCH ============================================
   //--- Applied LAST, so no window, edge or kill-zone setting above can
   //--- reinstate gating the operator switched off.
   //---
   //--- This is the line whose absence caused SESSION_BLOCKED on every
   //--- tick with InpSessionFilterEnabled=false: the value existed in
   //--- configuration and was never handed to the object that acts on it.
   m_sessions.SetEnabled(m_config.session_filter_enabled);
   if(!m_config.session_filter_enabled)
      Print(SRP_PRODUCT_NAME,": session filter DISABLED by input - no "
            "session, weekend, holiday, edge, overlap or kill-zone rule "
            "will refuse a trade. News, spread, regime, confidence, "
            "accuracy and risk guards remain active.");

   //--- HOLIDAY DATES. The filter was previously enabled with zero dates
   //--- loaded, which is an inert filter that looks active. Loading the
   //--- configured list is what makes it real; an empty list now leaves
   //--- the filter reporting honestly through Validate().
   if(m_config.holiday_filter_enabled && m_config.holiday_list!="")
     {
      const int parsed=m_sessions.LoadHolidays(m_config.holiday_list);
      Print(SRP_PRODUCT_NAME,": loaded ",parsed," holiday date(s)");
     }

   //--- Broker offset override, for brokers whose reported GMT is
   //--- unreliable. Zero means "auto-detect", which is the default.
   if(m_config.broker_gmt_offset!=0)
      m_sessions.SetManualBrokerOffset(m_config.broker_gmt_offset*60);
   m_sessions.SetDstEnabled(m_config.dst_adjust);

   if(!m_sessions.Initialize())
      return(false);

   m_news=new CNewsEngine(s,nolog);
   if(m_news==NULL)
      return(false);
   //--- The calendar is consulted only outside the tester: MQL5 returns
   //--- TODAY's events regardless of the simulated bar, so using it in a
   //--- backtest blocks trades on information from the future.
   const bool in_tester=(m_env!=NULL && m_env.IsTester());
   const ENUM_SRP_NEWS_SOURCE news_source=
      (ENUM_SRP_NEWS_SOURCE)m_config.news_source;
   const bool have_csv=(m_config.news_csv_file!="");
   const bool use_calendar=(m_config.news_filter_enabled &&
                            news_source==SRP_NEWS_SOURCE_TERMINAL_CALENDAR &&
                            m_env!=NULL && m_env.ShouldEnableNewsProvider());
   //--- A CSV explicitly selected by the operator is authoritative. When
   //--- the terminal calendar is selected it remains a fallback, which is
   //--- especially important in the tester where the calendar is unusable.
   const bool use_csv=(m_config.news_filter_enabled && have_csv &&
                       (news_source==SRP_NEWS_SOURCE_CSV_FILE ||
                        news_source==SRP_NEWS_SOURCE_TERMINAL_CALENDAR));
   //--- There is no honest calendar source in the tester. With no CSV,
   //--- disable the news gate rather than constructing an enabled gate with
   //--- no possible source, which otherwise fails closed for every entry.
   const bool news_enabled=(m_config.news_filter_enabled &&
                            news_source!=SRP_NEWS_SOURCE_DISABLED &&
                            (!in_tester || use_csv));
   //--- In the tester the CSV is the ONLY honest source, so it is the only
   //--- one offered there.
   m_news.SetSource(use_calendar,use_csv,m_config.news_csv_file);
   m_news.SetMinimumSeverity((ENUM_SRP_NEWS_SEVERITY)m_config.news_min_impact);

   //=== THE MASTER SWITCH ============================================
   //--- MEASURED DEFECT, and the reason a live run took no trades for five
   //--- hours: 100% of evaluations declined as NEWS_BLOCKED on every chart.
   //---
   //--- CNewsEngine has had SetEnabled since Phase 3 and NOTHING EVER
   //--- CALLED IT, so the object stayed enabled whatever the input said and
   //--- InpNewsFilterEnabled=false was inert. Identical in shape to the
   //--- session-filter defect: the value was stored, read, validated and
   //--- never handed to the object that acts on it.
   m_news.SetEnabled(news_enabled);
   if(!news_enabled)
     {
      const string why=(news_source==SRP_NEWS_SOURCE_DISABLED
                        ? "news source is disabled"
                        : (in_tester ? "tester has no news CSV"
                                     : "news filter is disabled"));
      Print(SRP_PRODUCT_NAME,": news filter DISABLED (",why,
            ") - no news blackout will refuse a trade. Session, spread, "
            "regime, confidence, accuracy and risk guards remain active.");
     }

   //--- BLACKOUT WINDOWS, from configuration rather than the constructor's
   //--- defaults. These were also never applied: the profile asks for
   //--- 20 minutes either side, the engine kept its built-in 60/60 for
   //--- CRITICAL and 30/30 for HIGH, so every blackout was up to three
   //--- times wider than configured. Two well-spaced releases were enough
   //--- to cover an entire trading day.
   //---
   //--- Critical keeps a wider window than high, because FOMC and NFP
   //--- genuinely do move gold for longer than a second-tier release, but
   //--- both are now derived from what the operator asked for.
   const int news_before=(m_config.news_minutes_before>=0
                          ? m_config.news_minutes_before : 15);
   const int news_after=(m_config.news_minutes_after>=0
                         ? m_config.news_minutes_after : 15);
   m_news.SetCriticalWindow((int)(news_before*1.5),(int)(news_after*1.5));
   m_news.SetHighWindow(news_before,news_after);
   m_news.SetMediumWindow(news_before/2,news_after/2);

   //--- CURRENCY FILTER. Never applied either, so an event in any currency
   //--- was treated as affecting gold - which on a full economic calendar
   //--- is a near-permanent blackout. The profile supplies "USD,XAU" for
   //--- gold and "USD" for the index.
   if(m_config.news_currency_filter!="")
      m_news.SetCurrencyFilter(m_config.news_currency_filter);

   //--- THE FAIL-SAFE, AND WHY IT IS ENVIRONMENT-DEPENDENT.
   //---
   //--- Live, "block when the source is unavailable" is the correct and
   //--- conservative choice: trading blind into an unknown release risks
   //--- real capital, so the filter fails closed.
   //---
   //--- In the tester that same rule is not caution, it is a silent
   //--- no-op. The calendar is deliberately unavailable there (it would
   //--- be look-ahead bias), so if no CSV was supplied the source can
   //--- NEVER become available and the fail-safe blocks 100% of entries.
   //--- The first measured backtest declined 117,742 of 124,635 ticks for
   //--- exactly this reason and reported a clean pass with zero trades -
   //--- a result that looks like a working robot and means nothing.
   //---
   //--- So: fail closed live, and in the tester fail closed only when a
   //--- CSV was actually provided and failed to load. Absent a CSV the
   //--- run proceeds WITHOUT news filtering, stated plainly, because a
   //--- backtest the user cannot interpret is worse than one with a
   //--- documented gap.
   const bool fail_safe=(in_tester ? (m_config.news_fail_safe_block && have_csv)
                                   : m_config.news_fail_safe_block);
   m_news.SetFailSafeBlock(fail_safe);
   if(in_tester && m_config.news_filter_enabled && !use_csv)
      Print(SRP_PRODUCT_NAME,": news filtering is INACTIVE for this test. ",
            "The terminal calendar cannot be used in the tester without ",
            "look-ahead bias, and no news CSV was supplied. Results do not ",
            "account for news. Set the news CSV input to model it.");
   m_news.SetFlattenOnCritical(m_config.news_close_positions);
   if(!m_news.Initialize())
      return(false);

   m_context=new CStrategyContext();
   if(m_context==NULL)
      return(false);
   m_context.SetEmaSet(m_ema_fast,m_ema_slow,m_ema_trend);
   m_context.SetSma(m_sma);
   m_context.SetAtr(m_atr);
   m_context.SetRsi(m_rsi);
   m_context.SetAdx(m_adx);
   m_context.SetMacd(m_macd);
   m_context.SetBollinger(m_bollinger);
   m_context.SetCci(m_cci);
   m_context.SetStochastic(m_stochastic);
   m_context.SetIchimoku(m_ichimoku);
   m_context.SetObv(m_obv);
   m_context.SetMfi(m_mfi);
   m_context.SetVwap(m_vwap);
   m_context.SetVolume(m_volume);
   m_context.SetSwings(m_swings);
   m_context.SetStructure(m_structure);
   m_context.SetZones(m_zones);
   m_context.SetDisplacement(m_displacement);
   m_context.SetLiquidity(m_liquidity);

   //--- REGIME ENGINE, on the CONTEXT timeframe.
   //---
   //--- Its own ADX and ATR are built here rather than reusing the
   //--- execution-timeframe indicators, because classifying regime from
   //--- M1 data measures noise. This is the multi-timeframe requirement
   //--- of Part 10 made concrete: context is read from M15, setups and
   //--- execution from the configured chart timeframe.
   //--- A timeframe of 0 is PERIOD_CURRENT to MQL5, but it is also what an
   //--- unset configuration key looks like, and the two mean very different
   //--- things: reading "context" from the execution timeframe silently
   //--- defeats the entire multi-timeframe design. An unusable value is
   //--- therefore replaced with the documented default and SAID OUT LOUD,
   //--- rather than being absorbed.
   ENUM_TIMEFRAMES ctf=(ENUM_TIMEFRAMES)m_config.context_timeframe;
   if((int)ctf<=0 || ctf==m_config.timeframe)
     {
      Print(SRP_PRODUCT_NAME,": context timeframe unusable (",
            (int)m_config.context_timeframe,
            "), falling back to PERIOD_M15 - regime would otherwise be "
            "classified from execution-timeframe noise");
      ctf=PERIOD_M15;
     }
   m_adx_context=new CAdxIntel(s,ctf,m_config.adx_period,nolog);
   m_atr_context=new CAtrIntel(s,ctf,m_config.atr_period,nolog);
   if(m_adx_context==NULL || m_atr_context==NULL)
      return(false);
   if(!m_adx_context.Initialize() || !m_atr_context.Initialize())
      return(false);

   //--- SETUP-TIMEFRAME ATR, for the wider scalp tier. Same fallback
   //--- reasoning as the context timeframe: an unset value is 0, which
   //--- MQL5 reads as PERIOD_CURRENT and would silently make this series
   //--- identical to the execution one.
   ENUM_TIMEFRAMES stf=(ENUM_TIMEFRAMES)m_config.setup_timeframe;
   if((int)stf<=0)
      stf=PERIOD_M5;
   m_atr_setup=new CAtrIntel(s,stf,m_config.atr_period,nolog);
   if(m_atr_setup==NULL || !m_atr_setup.Initialize())
      return(false);

   //--- SETUP AND CONTEXT EMAs, for multi-timeframe agreement.
   //---
   //--- The slow period is used on both higher timeframes rather than the
   //--- fast one: the question asked of M5 and M15 is "which way does this
   //--- timeframe lean", and a fast average on a higher timeframe answers a
   //--- narrower question than that while flipping more often.
   m_ema_setup  =new CEmaIndicator(s,stf,m_config.slow_ma_period,nolog);
   m_ema_context=new CEmaIndicator(s,ctf,m_config.slow_ma_period,nolog);
   if(m_ema_setup==NULL || m_ema_context==NULL)
      return(false);
   if(!m_ema_setup.Initialize() || !m_ema_context.Initialize())
      return(false);

   //--- ENTRY QUALITY GATE.
   //---
   //--- Built here because it needs the setup and context series that were
   //--- only just created. It is given the profile's own thresholds so gold
   //--- and an index can demand different amounts of corroboration.
   m_accuracy=new CAccuracyFilter(s,nolog);
   if(m_accuracy==NULL)
      return(false);
   m_accuracy.SetIndicators(m_ema_fast,m_ema_slow,m_ema_setup,m_ema_context,
                            m_volume,m_atr);
   m_accuracy.SetTimeframes(m_config.timeframe,stf,ctf);
   m_accuracy.SetEnabled(m_config.accuracy_filter_enabled);
   m_accuracy.ConfigureAgreement(m_config.accuracy_require_setup,
                                 m_config.accuracy_require_context);
   m_accuracy.ConfigureVolume(m_config.accuracy_min_relative_volume,
                              m_config.accuracy_volume_lookback);
   m_accuracy.ConfigureExtension(m_config.accuracy_max_extension);
   m_accuracy.ConfigureScore(m_config.accuracy_min_score,0.5,0.3,0.2);
   if(!m_accuracy.Initialize())
      return(false);
   if(m_accuracy.IsEnabled())
      Print(SRP_PRODUCT_NAME,": accuracy filter active - ",
            EnumToString(m_config.timeframe)," signal must agree with ",
            EnumToString(stf)," and ",EnumToString(ctf),
            ", volume >= x",
            DoubleToString(m_config.accuracy_min_relative_volume,2));

   m_regime=new CRegimeEngine(s,nolog);
   if(m_regime==NULL)
      return(false);
   m_regime.SetProfile(m_market_profile);
   m_regime.SetContextIndicators(m_adx_context,m_atr_context);
   m_regime.SetStructure(m_structure);
   if(!m_regime.Initialize())
      return(false);

   m_decision=new CDecisionEngine(s,m_config.timeframe,nolog);
   if(m_decision==NULL)
      return(false);
   m_decision.SetCollaborators(m_sessions,m_news,m_context);
   //--- Turning on strategy gating. Without this the engine polls every
   //--- enabled plugin regardless of whether its premise exists.
   m_decision.SetRegimeEngine(m_regime);

   //--- The engine takes ownership of the confirmation engine.
   CConfirmationEngine *confirm=new CConfirmationEngine(m_context,nolog);
   if(confirm==NULL)
      return(false);
   confirm.SetMinConfidence(m_config.min_confidence);
   confirm.SetMaxSpread(m_config.max_spread_points);
   confirm.SetMinDecisiveChecks(m_config.min_confirmations);
   m_decision.SetConfirmationEngine(confirm);

   m_decision.SetVoteMode((ENUM_SRP_VOTE_MODE)m_config.vote_mode);
   m_decision.SetMinFinalConfidence(m_config.min_confidence);
   m_decision.SetRequireConfirmation(m_config.require_confirmation);

   //--- Only enabled plugins are constructed. A disabled strategy costs
   //--- nothing at runtime because it does not exist.
   if(m_config.ema_cross_enabled)
      m_decision.AddPlugin(new CEmaCrossStrategy(m_context,nolog));
   if(m_config.vwap_pullback_enabled)
      m_decision.AddPlugin(new CVwapPullbackStrategy(m_context,nolog));
   if(m_config.liquidity_sweep_enabled)
      m_decision.AddPlugin(new CLiquiditySweepStrategy(m_context,nolog));
   if(m_config.order_block_enabled)
      m_decision.AddPlugin(new COrderBlockStrategy(m_context,nolog));
   if(m_config.fvg_enabled)
      m_decision.AddPlugin(new CFairValueGapStrategy(m_context,nolog));
   if(m_config.momentum_enabled)
      m_decision.AddPlugin(new CMomentumScalpPlugin(m_context,nolog));
   if(m_config.opening_range_enabled)
      m_decision.AddPlugin(new COpeningRangeBreakout(m_context,nolog));
   if(m_config.trend_continuation_enabled)
      m_decision.AddPlugin(new CTrendContinuationStrategy(m_context,nolog));
   if(m_config.mean_reversion_enabled)
      m_decision.AddPlugin(new CMeanReversionPlugin(m_context,nolog));
   if(m_config.breakout_enabled)
      m_decision.AddPlugin(new CBreakoutStrategyPlugin(m_context,nolog));
   //--- Added in Phase 6. Break of structure trades a STRUCTURAL change,
   //--- which is a different premise from the price-level break that
   //--- CBreakoutStrategyPlugin trades; volatility breakout trades range
   //--- expansion with no level involved at all.
   if(m_config.bos_enabled)
      m_decision.AddPlugin(new CBreakOfStructureStrategy(m_context,nolog));
   if(m_config.volatility_breakout_enabled)
      m_decision.AddPlugin(new CVolatilityBreakoutStrategy(m_context,nolog));
   //--- Order flow / volume delta. Reads the OBV and MFI indicators
   //--- BuildIndicators already constructs and refreshes every tick -
   //--- previously wired into CStrategyContext and read by nothing.
   if(m_config.order_flow_enabled)
     {
      COrderFlowStrategy *order_flow=new COrderFlowStrategy(m_context,nolog);
      if(order_flow!=NULL)
        {
         order_flow.SetWeight(m_config.order_flow_weight);
         order_flow.SetMinVolumeRatio(m_config.order_flow_min_volume);
         m_decision.AddPlugin(order_flow);
        }
     }

   //--- Zero plugins means the pass can never signal. Better to refuse
   //--- startup than to run a robot that silently never trades.
   if(m_decision.PluginCount()<=0)
      return(false);
   if(!m_decision.Initialize())
      return(false);

   //--- ULTRA-SCALP CONTROLLER.
   //---
   //--- Built last in this stage because it borrows the execution-timeframe
   //--- ATR and RSI created by BuildIndicators. It gates entries; it never
   //--- sizes and never sends an order, so the existing execution and risk
   //--- paths remain the only ones.
   //---
   //--- THE STOP IS RECONFIGURED ON THE PROTECTION MANAGER, not applied
   //--- afterwards. Sizing is computed FROM the stop inside CRiskEngine,
   //--- so overriding the stop after the fact would break the link between
   //--- risk and volume. A measured run with the swing stop (2.2xATR) left
   //--- in place against a 0.55xATR scalp target produced an 80% win rate
   //--- at profit factor 1.03 - one loss erased four wins. Telling the
   //--- protection manager the scalp stop is what makes the geometry real.
   m_scalp=new CScalpController(s,nolog);
   if(m_scalp==NULL)
      return(false);
   m_scalp.SetIndicators(m_atr,m_rsi);
   //--- TIER ATRs. SUPER and STANDARD read the execution timeframe; SWING
   //--- reads the setup timeframe, because a target it may hold for
   //--- fifteen minutes cannot be sized from one-minute volatility.
   //--- m_atr_context is already built on the context timeframe, so the
   //--- setup-timeframe series is the one addition.
   m_scalp.SetTierAtr(SRP_TIER_SUPER,m_atr);
   m_scalp.SetTierAtr(SRP_TIER_STANDARD,m_atr);
   m_scalp.SetTierAtr(SRP_TIER_SWING,
                      (m_atr_setup!=NULL ? m_atr_setup : m_atr));
   m_scalp.SetEnabled(m_config.scalp_mode_enabled);
   m_scalp.ConfigureTiming(m_config.scalp_cooldown_seconds,
                           m_config.scalp_max_hold_seconds);
   m_scalp.ConfigureTarget(m_config.scalp_target_atr_multiple,
                           m_config.scalp_target_min_points,
                           m_config.scalp_target_max_points);
   m_scalp.ConfigureStop(m_config.scalp_stop_atr_multiple);
   m_scalp.ConfigureCosts(m_config.scalp_commission_points,
                          m_config.scalp_execution_cost_points,
                          m_config.scalp_min_reward_cost_ratio,
                          m_config.scalp_max_spread_target_ratio);
   m_scalp.ConfigureEarlyExit(m_config.scalp_early_exit_enabled,
                              m_config.scalp_early_exit_min_points,
                              m_config.scalp_early_exit_target_share);
   m_scalp.ConfigureAtrBounds(m_config.scalp_atr_min_points,
                              m_config.scalp_atr_max_points);
   m_scalp.SetMaxScalpsPerDay(m_config.max_trades_per_day);
   //--- TIERS from configuration, so the geometry is testable instead of
   //--- compiled in. The values are printed AS RECEIVED, because three
   //--- attempts to disable a tier from the input block appeared to work
   //--- and did not, and the only way to tell a plumbing fault from a
   //--- selector fault is to see what actually arrived.
   Print(SRP_PRODUCT_NAME,": tier config as received - ",
         StringFormat("SUPER=%s(%.2f/%.2f,%ds) STANDARD=%s(%.2f/%.2f,%ds) "
                      "SWING=%s(%.2f/%.2f,%ds)",
                      (m_config.tier_enabled[0] ? "on" : "off"),
                      m_config.tier_target_atr[0],m_config.tier_stop_atr[0],
                      m_config.tier_hold_seconds[0],
                      (m_config.tier_enabled[1] ? "on" : "off"),
                      m_config.tier_target_atr[1],m_config.tier_stop_atr[1],
                      m_config.tier_hold_seconds[1],
                      (m_config.tier_enabled[2] ? "on" : "off"),
                      m_config.tier_target_atr[2],m_config.tier_stop_atr[2],
                      m_config.tier_hold_seconds[2]));
   for(int t=0;t<3;t++)
      m_scalp.ConfigureTier((ENUM_SRP_SCALP_TIER)t,
                            m_config.tier_enabled[t],
                            m_config.tier_target_atr[t],
                            m_config.tier_stop_atr[t],
                            m_config.tier_hold_seconds[t],
                            m_config.tier_win_rate[t],
                            (ENUM_TIMEFRAMES)m_config.tier_timeframe[t]);
   if(!m_scalp.Initialize())
      return(false);

   //--- Hand the scalp stop to the protection manager so the risk engine
   //--- sizes against it. Without this the robot would size for a 2.2xATR
   //--- swing stop while aiming at a 0.7xATR scalp target.
   if(m_scalp.IsEnabled() && m_protection!=NULL)
     {
      //--- Sized against the STANDARD tier's stop. Sizing must be settled
      //--- before a signal exists, and the tier is only known per trade,
      //--- so the middle tier is the honest compromise: SUPER runs a
      //--- slightly tighter stop than sized for and SWING a slightly wider
      //--- one. Both stay inside the 0.25% risk ceiling because volume is
      //--- computed from the stop the risk engine was given, never
      //--- increased afterwards.
      m_protection.ConfigureStop(SRP_STOP_ATR_MULTIPLE,
                                 m_config.scalp_target_min_points,
                                 m_config.scalp_stop_atr_multiple);
      //--- The target is still substituted per-trade in SeekEntry, because
      //--- it must clear the CURRENT spread rather than a startup estimate.
      Print(SRP_PRODUCT_NAME,": scalp geometry active - stop ",
            DoubleToString(m_config.scalp_stop_atr_multiple,2),
            "xATR, target ",
            DoubleToString(m_config.scalp_target_atr_multiple,2),"xATR");
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool CProductionEngine::BuildExecution(void)
  {
   STradeEngineConfig cfg;
   cfg.symbol                   = m_config.symbol;
   cfg.magic_base               = m_config.magic;
   cfg.comment_tag              = m_config.order_comment;
   cfg.deviation_points         = m_config.deviation_points;
   cfg.max_slippage_points      = m_config.max_slippage_points;
   cfg.max_spread_points        = m_config.max_spread_points;
   cfg.min_free_margin_percent  = m_config.min_free_margin_percent;
   cfg.log_execution_speed      = true;

   m_trade=new CTradeEngine(cfg,m_clock,m_bus,NULL);
   if(m_trade==NULL)
      return(false);
   return(m_trade.Initialize());
  }
//+------------------------------------------------------------------+
bool CProductionEngine::BuildInterface(void)
  {
   double initial=m_config.analytics_initial_balance;
   if(initial<=0.0)
      initial=AccountInfoDouble(ACCOUNT_BALANCE);
   m_session_start_balance=initial;

   m_ui=new CTraderInterface(m_config.symbol,m_config.timeframe,initial,
                             (ENUM_SRP_UI_THEME)m_config.dashboard_theme,
                             "SRP_");
   if(m_ui==NULL)
      return(false);
   if(!m_ui.Initialize(m_atr,m_zones,m_swings,m_structure))
      return(false);

   //--- The environment guard decides visibility, not the user's wish:
   //--- drawing during an optimisation is pure waste.
   const bool show=(m_env!=NULL ? m_env.ShouldEnableDashboard() : true);
   m_ui.SetDashboardEnabled(m_config.dashboard_enabled && show);
   m_ui.SetOverlayEnabled(m_config.draw_overlay_enabled && show);

   //--- Per-layer visibility from configuration.
   m_ui.SetLayerEnabled(SRP_DRAW_ENTRIES,m_config.draw_entries);
   m_ui.SetLayerEnabled(SRP_DRAW_STOP_LOSS,m_config.draw_stops);
   m_ui.SetLayerEnabled(SRP_DRAW_TAKE_PROFIT,m_config.draw_stops);
   m_ui.SetLayerEnabled(SRP_DRAW_ORDER_BLOCKS,m_config.draw_zones);
   m_ui.SetLayerEnabled(SRP_DRAW_FAIR_VALUE_GAPS,m_config.draw_zones);
   m_ui.SetLayerEnabled(SRP_DRAW_LIQUIDITY,m_config.draw_liquidity);
   m_ui.SetLayerEnabled(SRP_DRAW_BOS,m_config.draw_structure);
   m_ui.SetLayerEnabled(SRP_DRAW_CHOCH,m_config.draw_structure);
   m_ui.SetLayerEnabled(SRP_DRAW_SESSION_BOXES,m_config.draw_session_boxes);
   m_ui.SetLayerEnabled(SRP_DRAW_TRADE_LABELS,m_config.draw_trade_labels);
   m_ui.SetLayerEnabled(SRP_DRAW_STATISTICS,m_config.draw_statistics);

   //--- Logging channels and rotation.
   CEnterpriseLogger *log=m_ui.Logger();
   if(log!=NULL)
     {
      log.SetFolder(m_config.log_folder);
      log.SetDailyRotation(m_config.log_daily_rotation);
      log.SetFlushEvery(m_config.log_flush_every);
      log.SetMirrorErrorsToJournal(m_config.log_mirror_errors_to_journal);
      log.SetChannelEnabled(SRP_LOG4_ERRORS,m_config.log_channel_errors);
      log.SetChannelEnabled(SRP_LOG4_TRADES,m_config.log_channel_trades);
      log.SetChannelEnabled(SRP_LOG4_INDICATORS,m_config.log_channel_indicators);
      log.SetChannelEnabled(SRP_LOG4_RISK_EVENTS,m_config.log_channel_risk);
      log.SetChannelEnabled(SRP_LOG4_PERFORMANCE,m_config.log_channel_performance);
      log.SetChannelEnabled(SRP_LOG4_EXECUTION_TIME,m_config.log_channel_execution);
      //--- Verbosity is forced down in the tester; even Print costs
      //--- measurable time across thousands of passes.
      if(m_env!=NULL)
         log.SetMinimumLevel(m_env.RecommendedLogLevel(
                                (ENUM_SRP_LOG_LEVEL)m_config.log_level));
      if(!m_env.ShouldEnableFileLogging())
        {
         log.SetChannelEnabled(SRP_LOG4_INDICATORS,false);
         log.SetChannelEnabled(SRP_LOG4_PERFORMANCE,false);
         log.SetChannelEnabled(SRP_LOG4_EXECUTION_TIME,false);
        }
     }

   //--- Trade manager configuration, all from config.
   CTradeManager *manager=m_ui.Manager();
   if(manager!=NULL)
     {
      manager.ConfigureBreakEven(m_config.breakeven_enabled,
                                 m_config.breakeven_trigger_points,
                                 m_config.breakeven_offset_points);
      manager.ConfigureTrailing(m_config.trail_mode!=0,
                                m_config.trail_start_points,
                                m_config.trail_distance_points,
                                m_config.trail_step_points);
      manager.ConfigureAtrTrailing(m_config.tm_atr_trail_enabled,
                                   m_config.tm_atr_trail_multiple,
                                   m_config.trail_step_points);
      manager.ConfigureAtrExit(m_config.tm_atr_exit_enabled,
                               m_config.tm_atr_exit_multiple);
      manager.ConfigureTimeExit(m_config.time_stop_enabled,
                                m_config.time_stop_minutes,true);
      manager.ConfigureMaxHold(m_config.tm_max_hold_enabled,
                               m_config.tm_max_hold_minutes);
      manager.ConfigureScaleIn(m_config.tm_scale_in_enabled,
                               m_config.tm_scale_in_trigger_points,
                               m_config.tm_scale_in_fraction,
                               m_config.tm_scale_in_max);
      manager.ConfigureScaleOut(m_config.tm_scale_out_enabled,
                                m_config.tm_scale_out_trigger_points,
                                m_config.tm_scale_out_fraction,
                                m_config.tm_scale_out_max);
      manager.ConfigureReverse(m_config.tm_reverse_enabled);
      manager.SetBrokerVolumeLimits(
         SymbolInfoDouble(m_config.symbol,SYMBOL_VOLUME_MIN),
         SymbolInfoDouble(m_config.symbol,SYMBOL_VOLUME_STEP));
     }

   CPerformanceAnalytics *analytics=m_ui.Analytics();
   if(analytics!=NULL)
     {
      analytics.SetMinimumSample(m_config.analytics_min_sample);
      analytics.SetUseRMultiples(m_config.analytics_use_r_multiples);
     }
   return(true);
  }
//+------------------------------------------------------------------+
//| OPTIMISATION. Built unconditionally but consulted only from the       |
//| tester entry points, so it costs one allocation and nothing else      |
//| live. Every knob comes from configuration.                           |
//|                                                                  |
//| WHY THE CRITERION IS ALWAYS BUILT: OnTester is called by the terminal |
//| whether or not the user asked for a custom criterion. Building it     |
//| here means the hook can never find a null collaborator and silently   |
//| return zero, which would make every genetic pass score identically.   |
//+------------------------------------------------------------------+
bool CProductionEngine::BuildOptimization(void)
  {
   ILogger *nolog=NULL;

   m_criterion=new COptimizationCriterion(nolog);
   if(m_criterion==NULL)
      return(false);
   m_criterion.SetCriterion(
      (ENUM_SRP_OPTIMIZATION_CRITERION)m_config.opt_criterion);
   //--- The minimum-trade gate is what stops a 3-trade fluke from topping
   //--- an optimisation table.
   m_criterion.SetMinimumTrades(m_config.opt_min_trades);
   m_criterion.SetPenaltyWeights(m_config.opt_drawdown_penalty,
                                 m_config.opt_concentration_penalty,
                                 m_config.opt_streak_penalty);

   m_monte_carlo=new CMonteCarloSimulator(nolog);
   if(m_monte_carlo==NULL)
      return(false);
   double starting=m_config.analytics_initial_balance;
   if(starting<=0.0)
      starting=AccountInfoDouble(ACCOUNT_BALANCE);
   m_monte_carlo.SetStartingBalance(starting);
   m_monte_carlo.SetRuns(m_config.opt_monte_carlo_runs);
   m_monte_carlo.SetRuinThreshold(m_config.opt_monte_carlo_ruin_percent);
   m_monte_carlo.SetSeed(m_config.opt_monte_carlo_seed);

   m_tester=new CTesterIntegration(m_criterion,nolog);
   if(m_tester==NULL)
      return(false);
   m_tester.SetMonteCarlo(m_monte_carlo);
   //--- Monte Carlo is never run per optimisation pass: a thousand extra
   //--- simulations per pass would dominate the run time. The integration
   //--- enforces that itself, and this is the user's opt-in for a single
   //--- backtest.
   m_tester.SetRunMonteCarlo(m_config.opt_monte_carlo_enabled);
   m_tester.SetExport(m_config.opt_export_csv,m_config.opt_export_folder);
   return(true);
  }
//+------------------------------------------------------------------+
//| Release. Strict reverse of construction. Every owned pointer is      |
//| deleted exactly once and nulled, so a double Stop() is harmless.     |
//+------------------------------------------------------------------+
void CProductionEngine::Release(void)
  {
   if(m_tester!=NULL)    { delete m_tester;    m_tester=NULL; }
   if(m_monte_carlo!=NULL){ delete m_monte_carlo; m_monte_carlo=NULL; }
   if(m_criterion!=NULL) { delete m_criterion; m_criterion=NULL; }
   if(m_ui!=NULL)        { delete m_ui;        m_ui=NULL; }
   if(m_trade!=NULL)     { m_trade.Shutdown(); delete m_trade; m_trade=NULL; }
   //--- The decision engine deletes its plugins and confirmation engine.
   if(m_decision!=NULL)  { m_decision.Shutdown(); delete m_decision; m_decision=NULL; }
   if(m_context!=NULL)   { delete m_context;   m_context=NULL; }
   if(m_news!=NULL)      { m_news.Shutdown();  delete m_news; m_news=NULL; }
   if(m_sessions!=NULL)  { m_sessions.Shutdown(); delete m_sessions; m_sessions=NULL; }
   //--- The scalp controller BORROWS its indicators; deleting it does not
   //--- touch them.
   if(m_scalp!=NULL)     { delete m_scalp;     m_scalp=NULL; }
   //--- The regime engine BORROWS its indicators, so it is released first
   //--- and the indicators are deleted separately below.
   if(m_regime!=NULL)    { delete m_regime;    m_regime=NULL; }
   //--- The accuracy filter BORROWS every indicator it uses, so deleting it
   //--- must not touch them. It is released before the series it points at.
   if(m_accuracy!=NULL)  { delete m_accuracy;  m_accuracy=NULL; }
   if(m_ema_context!=NULL){ m_ema_context.Shutdown(); delete m_ema_context; m_ema_context=NULL; }
   if(m_ema_setup!=NULL)  { m_ema_setup.Shutdown();   delete m_ema_setup;   m_ema_setup=NULL; }
   if(m_atr_setup!=NULL)  { m_atr_setup.Shutdown();   delete m_atr_setup;   m_atr_setup=NULL; }
   if(m_atr_context!=NULL){ m_atr_context.Shutdown(); delete m_atr_context; m_atr_context=NULL; }
   if(m_adx_context!=NULL){ m_adx_context.Shutdown(); delete m_adx_context; m_adx_context=NULL; }
   //--- OWNERSHIP TRANSFER, AND THE REASON THIS LOOKS ASYMMETRIC.
   //--- CRiskEngine::SetSizer, SetLimitGuard and SetProtectionManager
   //--- each TAKE OWNERSHIP of their argument, and ~CRiskEngine deletes
   //--- all three. Deleting them here as well was a double free, and it
   //--- surfaced as "invalid pointer access" the first time a real
   //--- teardown ran.
   //---
   //--- So: if the risk engine exists, it owns them and they are merely
   //--- forgotten. If it does NOT exist, construction failed before the
   //--- handover and this class is still the owner - so they are deleted
   //--- here. Either path frees each pointer exactly once.
   if(m_risk!=NULL)
     {
      m_risk.Shutdown();
      delete m_risk;
      m_risk=NULL;
      m_protection=NULL;
      m_limits=NULL;
      m_sizer=NULL;
     }
   else
     {
      if(m_protection!=NULL){ delete m_protection; m_protection=NULL; }
      if(m_limits!=NULL)    { delete m_limits;     m_limits=NULL;     }
      if(m_sizer!=NULL)     { delete m_sizer;      m_sizer=NULL;      }
     }
   if(m_risk_state!=NULL){ delete m_risk_state;m_risk_state=NULL; }
   if(m_liquidity!=NULL) { delete m_liquidity; m_liquidity=NULL; }
   if(m_blocks!=NULL)    { delete m_blocks;    m_blocks=NULL; }
   if(m_displacement!=NULL){ delete m_displacement; m_displacement=NULL; }
   if(m_zones!=NULL)     { delete m_zones;     m_zones=NULL; }
   if(m_structure!=NULL) { m_structure.Shutdown(); delete m_structure; m_structure=NULL; }
   if(m_swings!=NULL)    { m_swings.Shutdown(); delete m_swings; m_swings=NULL; }
   if(m_volume!=NULL)    { m_volume.Shutdown(); delete m_volume; m_volume=NULL; }
   if(m_vwap!=NULL)      { m_vwap.Shutdown();  delete m_vwap; m_vwap=NULL; }
   if(m_mfi!=NULL)       { m_mfi.Shutdown();   delete m_mfi; m_mfi=NULL; }
   if(m_obv!=NULL)       { m_obv.Shutdown();   delete m_obv; m_obv=NULL; }
   if(m_ichimoku!=NULL)  { m_ichimoku.Shutdown(); delete m_ichimoku; m_ichimoku=NULL; }
   if(m_stochastic!=NULL){ m_stochastic.Shutdown(); delete m_stochastic; m_stochastic=NULL; }
   if(m_cci!=NULL)       { m_cci.Shutdown();   delete m_cci; m_cci=NULL; }
   if(m_bollinger!=NULL) { m_bollinger.Shutdown(); delete m_bollinger; m_bollinger=NULL; }
   if(m_macd!=NULL)      { m_macd.Shutdown();  delete m_macd; m_macd=NULL; }
   if(m_adx!=NULL)       { m_adx.Shutdown();   delete m_adx; m_adx=NULL; }
   if(m_rsi!=NULL)       { m_rsi.Shutdown();   delete m_rsi; m_rsi=NULL; }
   if(m_atr!=NULL)       { m_atr.Shutdown();   delete m_atr; m_atr=NULL; }
   if(m_sma!=NULL)       { m_sma.Shutdown();   delete m_sma; m_sma=NULL; }
   if(m_ema_trend!=NULL) { m_ema_trend.Shutdown(); delete m_ema_trend; m_ema_trend=NULL; }
   if(m_ema_slow!=NULL)  { m_ema_slow.Shutdown(); delete m_ema_slow; m_ema_slow=NULL; }
   if(m_ema_fast!=NULL)  { m_ema_fast.Shutdown(); delete m_ema_fast; m_ema_fast=NULL; }
   if(m_env!=NULL)       { delete m_env;       m_env=NULL; }
   if(m_bus!=NULL)       { delete m_bus;       m_bus=NULL; }
   if(m_clock!=NULL)     { delete m_clock;     m_clock=NULL; }
   m_built=false;
   m_running=false;
  }
//+------------------------------------------------------------------+
int CProductionEngine::Start(void)
  {
   if(!m_built)
      return(INIT_FAILED);

   const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   const datetime now=TimeCurrent();
   if(m_risk!=NULL && !m_risk.Initialize(equity,now))
      return(INIT_FAILED);

   m_running=true;
   m_halt_reason="";
   m_last_bar=iTime(m_config.symbol,m_config.timeframe,0);

   CEnterpriseLogger *log=(m_ui!=NULL ? m_ui.Logger() : NULL);
   if(log!=NULL)
     {
      log.Info("Engine",SRP_PRODUCT_NAME+" "+SRP_PRODUCT_VERSION+" started");
      if(m_env!=NULL)
         log.Info("Engine",m_env.DescribeEnvironment());
      log.Info("Engine",CRuntimeConfig::Describe(m_config));
      if(m_trade!=NULL)
         log.Info("Engine",m_trade.DescribeEnvironment());
     }
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void CProductionEngine::Stop(const int deinit_reason)
  {
   m_running=false;
   CEnterpriseLogger *log=(m_ui!=NULL ? m_ui.Logger() : NULL);
   if(log!=NULL)
      log.Info("Engine","stopping, reason="+IntegerToString(deinit_reason)+
               " ticks="+IntegerToString(m_ticks)+
               " entries="+IntegerToString(m_entries));

   //--- WHY THIS IS PRINTED RATHER THAN LOGGED.
   //--- "Why so few trades" is the most common thing an operator needs
   //--- explained, and the answer must be visible even with logging muted
   //--- or file logging suppressed in a tester pass.
   //---
   //--- Printed on EVERY run, not only on zero-entry runs: a run that took
   //--- two trades when the user expected twenty needs the same
   //--- explanation as one that took none, and the earlier
   //--- zero-entries-only condition hid exactly that case.
   if(m_ticks>0)
     {
      if(m_entries<=0)
         Print(SRP_PRODUCT_NAME,": no entries were taken in this run.");
      else
         Print(SRP_PRODUCT_NAME,": run summary (",m_entries," entries).");
      Print("  ticks=",m_ticks," managed actions=",m_managed_actions);
      if(m_regime!=NULL)
        {
         Print("  ",m_regime.Describe());
         Print("  ",m_regime.DescribeDistribution());
        }
      if(m_decision!=NULL)
        {
         Print("  ",m_decision.Describe());
         Print("  ",m_decision.DescribeDeclines());
         //--- The per-stage funnel. The decline tally says WHY passes
         //--- stopped; this says HOW FAR they got, and only the pair
         //--- identifies which stage is actually the constraint.
         Print("  ",m_decision.DescribeFunnel());
         //--- ENTRY-STAGE GATES. These sit AFTER "actionable" and every one
         //--- of them used to return silently, so the difference between
         //--- actionable decisions and orders sent was unexplained.
         Print(StringFormat("  ENTRY GATES: actionable=%I64d -> "
                            "preRisk=%I64d riskRating=%I64d direction=%I64d "
                            "accuracy=%I64d scalp=%I64d riskEngine=%I64d "
                            "-> entries=%I64d",
                            m_decision.ActionableCount(),
                            m_gate_pre_risk,m_gate_risk_rating,
                            m_gate_direction,m_gate_accuracy,m_gate_scalp,
                            m_gate_risk_engine,m_entries));
         if(m_decision.RegimeSkippedCount()>0)
            Print("  last pass, regime excluded: ",
                  m_decision.RegimeSkippedNames());
        }
      if(m_risk!=NULL)
         Print("  ",m_risk.Describe());
      if(m_trade!=NULL)
         Print("  ",m_trade.DescribeStatistics());
      //--- The scalp funnel and metrics, printed unconditionally so a run
      //--- with few trades is explainable without enabling file logging.
      //--- ACCURACY GATE. Reported before the scalp funnel because it runs
      //--- first, so the two read in pipeline order.
      if(m_accuracy!=NULL && m_accuracy.IsEnabled())
         Print("  ",m_accuracy.DescribeFunnel());
      if(m_scalp!=NULL && m_scalp.IsEnabled())
        {
         Print("  ",m_scalp.DescribeFunnel());
         Print("  ",m_scalp.DescribeMetrics());
         //--- PER-TIER RESULTS. Achieved win rate against the rate each
         //--- tier was designed around: the only way to see whether the
         //--- tier hypothesis held or merely sounded reasonable.
         Print("  ",m_scalp.DescribeTiers());
        }
     }
   //--- The session report is the last useful artefact of a run, so it is
   //--- published before anything is torn down.
   if(m_ui!=NULL)
     {
      m_ui.PublishSessionReport();
      //--- PER-TRADE RECORD, written every run.
      //---
      //--- The journal tables aggregate; attribution needs the rows. Each
      //--- carries strategy, exit reason, duration, R multiple and net P/L,
      //--- which is what makes "which strategy is paying for the others"
      //--- answerable instead of a matter of opinion. ExportAll already
      //--- existed and was never called, so the data was being discarded
      //--- at the end of every pass.
      if(m_entries>0 && m_ui.ExportAll())
         Print(SRP_PRODUCT_NAME,": per-trade CSV written to ",
               SRP_DATA_FOLDER,"\\Reports");
      m_ui.Shutdown();
     }
   Release();
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| CPU THROTTLE.                                                        |
//|                                                                  |
//| Purpose: stop a fast-ticking index from running the full pipeline    |
//| more often than the decision logic can benefit from.                 |
//|                                                                  |
//| IT IS DISABLED IN THE TESTER, AND THAT IS NOT AN OPTIMISATION.       |
//| GetTickCount64 measures REAL elapsed time, while the tester replays  |
//| a month of market data in a fraction of a second. Applying a 250 ms   |
//| real-time gate to simulated ticks silently discards almost all of     |
//| them: the first measured backtest ran 124,635 ticks in 0.24 s and     |
//| took zero trades, because the throttle rejected nearly every one.    |
//| A throttle that changes how many bars a strategy sees is not a        |
//| performance control, it is a correctness bug - and it would make      |
//| every backtest and optimisation result meaningless.                  |
//|                                                                  |
//| The tester is CPU-bound by design and has no user interface to keep   |
//| responsive, so there is nothing to protect there anyway.             |
//+------------------------------------------------------------------+
bool CProductionEngine::PassesThrottle(void)
  {
   if(m_config.tick_throttle_ms<=0)
      return(true);
   //--- Resolved once at build time by the environment guard.
   if(m_throttle_disabled)
      return(true);
   const ulong now=GetTickCount64();
   if(m_last_tick_ms!=0 &&
      (now-m_last_tick_ms)<(ulong)m_config.tick_throttle_ms)
      return(false);
   m_last_tick_ms=now;
   return(true);
  }
//+------------------------------------------------------------------+
//| THE TICK PIPELINE. Read the order; it is the design.                 |
//+------------------------------------------------------------------+
void CProductionEngine::OnTickEvent(void)
  {
   if(!m_built)
      return;
   m_ticks++;

   //--- 1. Cheapest possible exit first.
   if(!PassesThrottle())
      return;

   const datetime bar=iTime(m_config.symbol,m_config.timeframe,0);
   const bool is_new_bar=(bar!=m_last_bar && bar>0);
   if(is_new_bar)
      m_last_bar=bar;

   //--- 2. Refresh state before anything reads it.
   RefreshAnalysis(is_new_bar);
   RefreshAccountState();

   //--- 3. PROTECT CAPITAL BEFORE SEEKING MORE OF IT. Management runs
   //--- even while halted: an open position must still be trailed and
   //--- exited when the operator has paused new entries.
   ManageOpenPositions();

   //--- 4-7. New entries only when running.
   if(m_running)
      SeekEntry(is_new_bar);

   //--- 8. Presentation last: it must never delay a trading decision.
   Render();
  }
//+------------------------------------------------------------------+
void CProductionEngine::RefreshAnalysis(const bool is_new_bar)
  {
   //--- Indicators are internally cached per bar, so calling every tick
   //--- is cheap; the expensive scans are gated on a new bar.
   if(m_ema_fast!=NULL)  m_ema_fast.Refresh();
   if(m_ema_slow!=NULL)  m_ema_slow.Refresh();
   if(m_ema_trend!=NULL) m_ema_trend.Refresh();
   if(m_sma!=NULL)       m_sma.Refresh();
   if(m_atr!=NULL)       m_atr.Refresh();
   if(m_rsi!=NULL)       m_rsi.Refresh();
   if(m_adx!=NULL)       m_adx.Refresh();
   if(m_macd!=NULL)      m_macd.Refresh();
   if(m_bollinger!=NULL) m_bollinger.Refresh();
   if(m_cci!=NULL)       m_cci.Refresh();
   if(m_stochastic!=NULL)m_stochastic.Refresh();
   if(m_ichimoku!=NULL)  m_ichimoku.Refresh();
   if(m_obv!=NULL)       m_obv.Refresh();
   if(m_mfi!=NULL)       m_mfi.Refresh();
   if(m_vwap!=NULL)      m_vwap.Refresh();
   if(m_volume!=NULL)    m_volume.Refresh();

   //--- Context-timeframe indicators for regime classification. These are
   //--- separate handles on a higher timeframe, so they must be refreshed
   //--- alongside the execution set or the regime read goes stale.
   if(m_adx_context!=NULL) m_adx_context.Refresh();
   if(m_atr_context!=NULL) m_atr_context.Refresh();
   if(m_atr_setup!=NULL)   m_atr_setup.Refresh();
   //--- The multi-timeframe EMAs are separate handles on higher timeframes,
   //--- so they must be refreshed alongside the rest or the agreement test
   //--- reads a stale series and silently stops discriminating.
   if(m_ema_setup!=NULL)   m_ema_setup.Refresh();
   if(m_ema_context!=NULL) m_ema_context.Refresh();

   if(m_swings!=NULL)    m_swings.Refresh();
   if(m_structure!=NULL)
      m_structure.Refresh(SymbolInfoDouble(m_config.symbol,SYMBOL_BID));

   //--- Zone detection is bar-gated: order blocks and gaps do not form
   //--- intrabar, and scanning per tick is the single most expensive
   //--- thing this engine could do.
   if(is_new_bar && m_config.smc_enabled)
     {
      if(m_blocks!=NULL)    m_blocks.Scan(true);
      if(m_liquidity!=NULL) m_liquidity.Scan(true);
     }
  }
//+------------------------------------------------------------------+
void CProductionEngine::RefreshAccountState(void)
  {
   if(m_trade!=NULL)
      m_trade.RefreshAll();
   if(m_risk!=NULL)
      m_risk.UpdateAccountState(AccountInfoDouble(ACCOUNT_EQUITY),
                                (m_trade!=NULL ? m_trade.FloatingProfit() : 0.0),
                                TimeCurrent());
  }
//+------------------------------------------------------------------+
double CProductionEngine::TotalOpenLots(void) const
  {
   return(m_trade!=NULL ? m_trade.TotalVolume() : 0.0);
  }
//+------------------------------------------------------------------+
double CProductionEngine::ExposureRiskPercent(void) const
  {
   //--- Open lots as a share of the configured maximum, expressed as a
   //--- risk percentage. Approximate by design: the authoritative check
   //--- is the limit guard's own exposure rule.
   if(m_config.max_lot<=0.0)
      return(0.0);
   return(TotalOpenLots()/m_config.max_lot*m_config.risk_percent);
  }
//+------------------------------------------------------------------+
bool CProductionEngine::LoadPosition(const int index,SManagedPosition &out)
  {
   out.Reset();
   //--- PositionGetSymbol returns the symbol string and selects the
   //--- position as a side effect; an empty result means the index is
   //--- no longer valid, which happens when the list shrinks mid-loop.
   if(PositionGetSymbol(index)=="")
      return(false);
   //--- Only this EA's own positions on its own symbol are touched. A
   //--- manual trade or another robot's position is left strictly alone.
   if(PositionGetString(POSITION_SYMBOL)!=m_config.symbol)
      return(false);
   if(PositionGetInteger(POSITION_MAGIC)!=m_config.magic)
      return(false);

   out.ticket        = (ulong)PositionGetInteger(POSITION_TICKET);
   out.symbol        = PositionGetString(POSITION_SYMBOL);
   out.magic         = PositionGetInteger(POSITION_MAGIC);
   out.is_buy        = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
   out.volume        = PositionGetDouble(POSITION_VOLUME);
   out.initial_volume= out.volume;
   out.open_price    = PositionGetDouble(POSITION_PRICE_OPEN);
   out.current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
   out.stop_loss     = PositionGetDouble(POSITION_SL);
   out.take_profit   = PositionGetDouble(POSITION_TP);
   out.profit_money  = PositionGetDouble(POSITION_PROFIT);
   out.open_time     = (datetime)PositionGetInteger(POSITION_TIME);
   out.age_seconds   = (int)(TimeCurrent()-out.open_time);

   const double point=SymbolInfoDouble(m_config.symbol,SYMBOL_POINT);
   if(point>0.0)
      out.profit_points=(out.is_buy
                         ? (out.current_price-out.open_price)/point
                         : (out.open_price-out.current_price)/point);
   return(true);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Scalp position bookkeeping. A small fixed array rather than a         |
//| dynamic list: the position count is capped by configuration, and a    |
//| fixed array cannot fragment on the hot path.                          |
//+------------------------------------------------------------------+
void CProductionEngine::TrackScalp(const ulong ticket,
                                   const double target_points,
                                   const ENUM_SRP_SCALP_TIER tier,
                                   const int hold_seconds)
  {
   if(ticket==0 || target_points<=0.0)
      return;
   const int capacity=ArraySize(m_scalp_tickets);
   //--- Replace an existing entry for the same ticket rather than adding
   //--- a second one, so a partial close cannot duplicate the record.
   for(int i=0;i<m_scalp_tracked;i++)
      if(m_scalp_tickets[i]==ticket)
        {
         m_scalp_targets[i]=target_points;
         m_scalp_tiers[i]=(int)tier;
         m_scalp_holds[i]=hold_seconds;
         return;
        }
   if(m_scalp_tracked>=capacity)
      return;
   m_scalp_tickets[m_scalp_tracked]=ticket;
   m_scalp_targets[m_scalp_tracked]=target_points;
   m_scalp_tiers[m_scalp_tracked]=(int)tier;
   m_scalp_holds[m_scalp_tracked]=hold_seconds;
   m_scalp_tracked++;
  }
//+------------------------------------------------------------------+
void CProductionEngine::UntrackScalp(const ulong ticket)
  {
   for(int i=0;i<m_scalp_tracked;i++)
      if(m_scalp_tickets[i]==ticket)
        {
         //--- Compact by moving the last entry into the gap.
         m_scalp_tickets[i]=m_scalp_tickets[m_scalp_tracked-1];
         m_scalp_targets[i]=m_scalp_targets[m_scalp_tracked-1];
         m_scalp_tiers[i]=m_scalp_tiers[m_scalp_tracked-1];
         m_scalp_holds[i]=m_scalp_holds[m_scalp_tracked-1];
         m_scalp_tracked--;
         return;
        }
  }
//+------------------------------------------------------------------+
double CProductionEngine::ScalpTargetFor(const ulong ticket) const
  {
   for(int i=0;i<m_scalp_tracked;i++)
      if(m_scalp_tickets[i]==ticket)
         return(m_scalp_targets[i]);
   return(0.0);
  }
//+------------------------------------------------------------------+
ENUM_SRP_SCALP_TIER CProductionEngine::ScalpTierFor(const ulong ticket) const
  {
   for(int i=0;i<m_scalp_tracked;i++)
      if(m_scalp_tickets[i]==ticket)
         return((ENUM_SRP_SCALP_TIER)m_scalp_tiers[i]);
   return(SRP_TIER_STANDARD);
  }
//+------------------------------------------------------------------+
int CProductionEngine::ScalpHoldFor(const ulong ticket) const
  {
   for(int i=0;i<m_scalp_tracked;i++)
      if(m_scalp_tickets[i]==ticket)
         return(m_scalp_holds[i]);
   //--- Zero means "use the controller's global window", which is the
   //--- correct answer for a position this engine is not tracking.
   return(0);
  }
//+------------------------------------------------------------------+
//| Remembers the tier of a scalp this engine has just closed, so the    |
//| close notification that follows can still attribute it.              |
//|                                                                  |
//| A small ring is enough: only positions closed since the last            |
//| notification need to be recalled, and that is a handful at most.       |
//+------------------------------------------------------------------+
void CProductionEngine::RememberClosedTier(const ulong ticket,
                                           const ENUM_SRP_SCALP_TIER tier)
  {
   if(ticket==0)
      return;
   const int capacity=ArraySize(m_closed_tickets);
   m_closed_tickets[m_closed_cursor]=ticket;
   m_closed_tiers[m_closed_cursor]=(int)tier;
   m_closed_cursor=(m_closed_cursor+1)%capacity;
  }
//+------------------------------------------------------------------+
ENUM_SRP_SCALP_TIER CProductionEngine::RecallClosedTier(const ulong ticket) const
  {
   const int capacity=ArraySize(m_closed_tickets);
   for(int i=0;i<capacity;i++)
      if(m_closed_tickets[i]==ticket)
         return((ENUM_SRP_SCALP_TIER)m_closed_tiers[i]);
   return(SRP_TIER_STANDARD);
  }
//+------------------------------------------------------------------+
//| SCALP EXITS: early profit and holding-window timeout.                |
//|                                                                  |
//| Both close through the EXISTING execution engine. Neither widens a     |
//| stop, neither changes size, and neither can turn a loss into a larger  |
//| position. Returns true when the position was closed, so the caller     |
//| skips the ordinary management pass for it.                             |
//+------------------------------------------------------------------+
bool CProductionEngine::ApplyScalpExits(const SManagedPosition &position)
  {
   if(m_scalp==NULL || !m_scalp.IsEnabled() || m_trade==NULL)
      return(false);

   const double point=SymbolInfoDouble(m_config.symbol,SYMBOL_POINT);
   if(point<=0.0)
      return(false);

   CEnterpriseLogger *log=(m_ui!=NULL ? m_ui.Logger() : NULL);
   SExecutionReport report;

   //--- 1. EARLY PROFIT. Checked first: banking a profit that is fading
   //--- outranks waiting for the clock.
   const double profit_points=position.profit_points;
   const double target_points=ScalpTargetFor(position.ticket);
   string reason="";
   if(profit_points>0.0 &&
      m_scalp.ShouldTakeEarlyProfit(position.is_buy,profit_points,
                                    target_points,reason))
     {
      if(m_trade.ClosePositionEx(position.ticket,"scalp early profit",report))
        {
         m_managed_actions++;
         //--- Remembered BEFORE untracking, or the close notification that
         //--- follows cannot tell which tier earned this exit.
         RememberClosedTier(position.ticket,ScalpTierFor(position.ticket));
         UntrackScalp(position.ticket);
         if(log!=NULL)
            log.LogTrade("ScalpEarlyExit","SCALP EARLY EXIT: "+reason,
                         position.ticket,position.current_price,
                         position.volume,position.profit_money);
         return(true);
        }
     }

   //--- 2. HOLDING WINDOW. The move did not develop in the time allowed.
   //--- The stop is NOT widened and the size is NOT increased; the trade
   //--- is simply closed at market through the normal path.
   //--- The window THIS position was granted by its own tier.
   if(m_scalp.ShouldTimeOut(position.open_time,TimeCurrent(),reason,
                            ScalpHoldFor(position.ticket)))
     {
      if(m_trade.ClosePositionEx(position.ticket,"scalp timeout",report))
        {
         m_managed_actions++;
         RememberClosedTier(position.ticket,ScalpTierFor(position.ticket));
         UntrackScalp(position.ticket);
         if(log!=NULL)
            log.LogTrade("ScalpTimeExit","SCALP TIME EXIT: "+reason,
                         position.ticket,position.current_price,
                         position.volume,position.profit_money);
         return(true);
        }
     }
   return(false);
  }
//+------------------------------------------------------------------+
void CProductionEngine::ManageOpenPositions(void)
  {
   if(m_ui==NULL || m_trade==NULL)
      return;

   //--- Iterate downwards: closing a position reindexes the list, and an
   //--- ascending loop would silently skip the next position.
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      SManagedPosition position;
      if(!LoadPosition(i,position))
         continue;

      //--- SCALP EXITS FIRST. A scalp's early-profit and timeout rules are
      //--- tighter than the general trade manager's, so they are given the
      //--- first look. When one fires the position is gone and the general
      //--- pass would be operating on a closed ticket.
      if(ApplyScalpExits(position))
         continue;

      STradeIntent intent;
      if(!m_ui.ManagePosition(position,intent))
         continue;
      ApplyIntent(intent,position);
     }
  }
//+------------------------------------------------------------------+
//| The one place an intent becomes an order. The trade manager decided;  |
//| the trade engine executes; confirmations flow back so tracked state   |
//| reflects reality rather than intent.                                  |
//+------------------------------------------------------------------+
void CProductionEngine::ApplyIntent(const STradeIntent &intent,
                                    const SManagedPosition &position)
  {
   if(m_trade==NULL || m_ui==NULL || !intent.IsActionable())
      return;

   SExecutionReport report;
   switch(intent.action)
     {
      case SRP_TM_MOVE_STOP:
        {
         //--- ModifyStops is the ITradeExecutor contract, so it reports
         //--- through STradeResult rather than the richer report.
         STradeResult modify;
         if(m_trade.ModifyStops(intent.ticket,intent.new_stop,
                                position.take_profit,modify))
            m_ui.ConfirmStopMoved(intent.ticket,intent.new_stop,intent.trigger);
         break;
        }

      case SRP_TM_SCALE_OUT:
         if(m_trade.ClosePartialEx(intent.ticket,intent.volume,
                                   intent.reason,report))
            m_ui.ConfirmScaledOut(intent.ticket);
         break;

      case SRP_TM_SCALE_IN:
        {
         //--- An add is a fresh order in the same direction, inheriting
         //--- the parent's protective levels.
         const bool ok=(position.is_buy
                        ? m_trade.Buy(intent.volume,position.stop_loss,
                                      position.take_profit,intent.reason,report)
                        : m_trade.Sell(intent.volume,position.stop_loss,
                                       position.take_profit,intent.reason,report));
         if(ok)
            m_ui.ConfirmScaledIn(intent.ticket);
         break;
        }

      case SRP_TM_CLOSE_FULL:
         m_trade.ClosePositionEx(intent.ticket,intent.reason,report);
         break;

      case SRP_TM_REVERSE:
         //--- A reversal inherits the parent's protective levels; the
         //--- trade engine re-derives them for the new direction.
         m_trade.Reverse(intent.ticket,intent.volume,
                         position.stop_loss,position.take_profit,
                         intent.reason,report);
         break;

      default:
         return;
     }
   m_managed_actions++;

   CEnterpriseLogger *log=m_ui.Logger();
   if(log!=NULL && report.total_elapsed_ms>0)
      log.LogExecutionTime(CTradeManager::ActionToString(intent.action),
                           (double)report.total_elapsed_ms,report.attempts,
                           report.slippage_points,report.position_ticket);
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| TIER SELECTION.                                                    |
//|                                                                  |
//| The tier is chosen from the MARKET, never from a preference, because   |
//| the choice is a claim about how far price is likely to travel before   |
//| reversing - and that is a property of the regime, not of the trader.   |
//|                                                                  |
//|   TREND / BREAKOUT  price runs, so a wide target is reachable and a    |
//|                     tight one leaves most of the move behind ->        |
//|                     SWING_SCALP.                                     |
//|   RANGE / REVERSAL  price returns, so a tight target is hit often and  |
//|                     a wide one gives the profit back -> SUPER_SCALP.   |
//|                     This is where a high win rate is genuinely         |
//|                     available rather than bought with a bad payoff.    |
//|   HIGH VOLATILITY   a tight target is inside the noise; the stop would |
//|                     be hit first -> SWING_SCALP regardless of regime.  |
//|   otherwise         STANDARD.                                        |
//|                                                                  |
//| A disabled tier falls back to STANDARD rather than refusing, so        |
//| turning a tier off reduces behaviour instead of stopping trading.      |
//+------------------------------------------------------------------+
ENUM_SRP_SCALP_TIER CProductionEngine::SelectScalpTier(void) const
  {
   if(m_regime==NULL || m_scalp==NULL)
      return(SRP_TIER_STANDARD);

   SRegimeState state;
   m_regime.GetState(state);
   if(!state.valid)
      return(SRP_TIER_STANDARD);

   ENUM_SRP_SCALP_TIER tier=SRP_TIER_STANDARD;

   //--- MEASURED ROUTING DEFECT, CORRECTED HERE.
   //---
   //--- The previous table sent TREND and BREAKOUT to SWING, and sent every
   //--- HIGH or EXTREME volatility bar there as well. On XAUUSD those two
   //--- conditions cover almost the whole sample - TREND 54.4% of context
   //--- bars, HIGH/EXTREME volatility 46.4% - so 265 of 270 trades landed
   //--- in the tier DESIGNED for a 48% win rate, and the SUPER tier that
   //--- exists for quick high-probability scalps took one trade in 31
   //--- months. The measured win rate fell to 36.3% as a direct result.
   //---
   //--- The corrected principle: the tier follows HOW FAR PRICE IS LIKELY
   //--- TO TRAVEL BEFORE STALLING, not merely which regime is named.
   //---
   //---   EXTREME volatility -> SWING. A 0.30xATR target genuinely sits
   //---     inside a single bar's range here, so it is reached by noise in
   //---     either direction and the stop is hit as often as the target.
   //---   TREND / BREAKOUT   -> SUPER. A directional market is exactly
   //---     where a small target is most likely to be reached, which is
   //---     the definition of a high-probability scalp. Sending these to a
   //---     1.40xATR target was asking a scalper to hold a swing position.
   //---   RANGE / REVERSAL   -> SUPER. Small targets near the extremes.
   //---   TRANSITION         -> STANDARD. Neither premise is strong.
   if(state.volatility==SRP_VOL_EXTREME)
      tier=SRP_TIER_SWING;
   else
      switch(state.regime)
        {
         case SRP_REGIME_TREND:
         case SRP_REGIME_BREAKOUT:
         case SRP_REGIME_RANGE:
         case SRP_REGIME_REVERSAL:
            tier=SRP_TIER_SUPER;
            break;
         case SRP_REGIME_HIGH_VOLATILITY:
            tier=SRP_TIER_STANDARD;
            break;
         default:
            tier=SRP_TIER_STANDARD;
            break;
        }

   //--- FALLBACK ORDER, and why it is not simply STANDARD.
   //---
   //--- Falling back to STANDARD unconditionally meant disabling STANDARD
   //--- had no effect: the selector kept choosing it and the tier's own
   //--- enable flag was silently ignored. A disabled tier must actually
   //--- stop trading, or an ablation measures nothing.
   //---
   //--- The preferred tier is tried first, then the remaining tiers in
   //--- order of decreasing similarity, and if every tier is off the scalp
   //--- is refused by Evaluate rather than forced into a tier the operator
   //--- turned off.
   if(!m_scalp.TierEnabled(tier))
     {
      if(m_scalp.TierEnabled(SRP_TIER_STANDARD))
         tier=SRP_TIER_STANDARD;
      else if(m_scalp.TierEnabled(SRP_TIER_SUPER))
         tier=SRP_TIER_SUPER;
      else if(m_scalp.TierEnabled(SRP_TIER_SWING))
         tier=SRP_TIER_SWING;
      //--- else: leave it as the disabled preference, and let Evaluate
      //--- refuse with a named reason.
     }
   return(tier);
  }
//+------------------------------------------------------------------+
bool CProductionEngine::RiskAllowsEntry(SRiskVerdict &verdict)
  {
   verdict.Reset();
   if(m_risk==NULL)
      return(false);

   //--- Position count is the engine's own cap, checked before the risk
   //--- engine so a full book costs nothing to reject.
   if(m_trade!=NULL && m_trade.PositionCount()>=m_config.max_positions)
     {
      verdict.entries_allowed=false;
      verdict.detail="position limit reached";
      return(false);
     }
   if(m_risk.IsEmergencyActive())
     {
      verdict.entries_allowed=false;
      verdict.detail="emergency shutdown active";
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
void CProductionEngine::SeekEntry(const bool is_new_bar)
  {
   if(m_decision==NULL || m_risk==NULL || m_trade==NULL || m_ui==NULL)
      return;

   SRiskVerdict pre;
   if(!RiskAllowsEntry(pre))
     {
      m_gate_pre_risk++;
      return;
     }

   //--- 5. Decide. Session, news, strategies and confirmation all live
   //--- behind this one call.
   STradeDecision decision;
   if(!m_decision.Evaluate(TimeCurrent(),is_new_bar,decision))
      return;
   if(!decision.actionable)
      return;
   //--- Risk rating is the engine's last veto on a signal the decision
   //--- layer was willing to take.
   //---
   //--- COUNTED, because this gate and the confidence floor are set
   //--- independently and can contradict each other. The rating is derived
   //--- from the SAME blended confidence the floor tests, so a profile with
   //--- min_confidence 0.65 and a MEDIUM rating ceiling silently discards
   //--- every decision scoring 0.65 to 0.70: the decision engine reports it
   //--- as actionable, and this line drops it without a word.
   if((int)decision.risk_rating>m_config.max_risk_rating)
     {
      m_gate_risk_rating++;
      return;
     }

   const bool is_buy=(decision.decision==SRP_DECISION_BUY);
   //--- Direction mode: 1 == long only, 2 == short only.
   if(m_config.direction_mode==1 && !is_buy) { m_gate_direction++; return; }
   if(m_config.direction_mode==2 && is_buy)  { m_gate_direction++; return; }

   const double entry=(is_buy
                       ? SymbolInfoDouble(m_config.symbol,SYMBOL_ASK)
                       : SymbolInfoDouble(m_config.symbol,SYMBOL_BID));

   //--- 5a. ENTRY QUALITY GATE.
   //---
   //--- Placed BEFORE the scalp gate and before sizing, so a signal that
   //--- lacks corroboration costs nothing further. It can only refuse.
   //---
   //--- This is where the measured accuracy problem is addressed: the
   //--- decision layer has already said the setup is valid, and this asks
   //--- the separate question of whether the higher timeframes and the
   //--- volume series agree with it.
   if(m_accuracy!=NULL)
     {
      SAccuracyVerdict acc;
      //--- The strategy kind decides whether the extension test applies:
      //--- a breakout premise puts price at an extreme by definition. See
      //--- CAccuracyFilter::IsBreakoutPremise.
      if(!m_accuracy.Evaluate(is_buy,acc,(int)decision.signal.strategy))
        {
         m_gate_accuracy++;
         CEnterpriseLogger *alog=m_ui.Logger();
         if(alog!=NULL)
            alog.LogRiskEvent("Accuracy",
                              "ACCURACY "+
                              CAccuracyFilter::BlockToString(acc.block)+
                              ": "+acc.detail,
                              acc.total_score,m_config.accuracy_min_score,0.0);
         return;
        }
     }

   //--- 5b. ULTRA-SCALP GATE.
   //---
   //--- Runs BEFORE sizing so a duplicate or uneconomic signal costs
   //--- nothing further. It can only refuse; it never creates an entry and
   //--- never returns a size.
   SScalpSignalId scalp_id;
   SScalpVerdict scalp_verdict;
   ENUM_SRP_SCALP_TIER scalp_tier=SRP_TIER_STANDARD;
   const bool scalping=(m_scalp!=NULL && m_scalp.IsEnabled());
   if(scalping)
     {
      //--- FINGERPRINT. Bar time + direction + strategy + structural
      //--- event. Two ticks inside one bar reporting the same setup
      //--- produce identical ids, so the second is refused.
      //---
      //--- The structural component comes from the structure engine this
      //--- class already owns rather than from the decision struct, which
      //--- does not carry it. It is what lets a SECOND genuine setup on
      //--- the same bar and same side - after a new break - still trade.
      int structure_event=0;
      datetime structure_time=0;
      if(m_structure!=NULL)
        {
         SStructureState sstate;
         m_structure.GetState(sstate);
         structure_event=(int)sstate.last_event;
         structure_time=sstate.last_event_time;
        }
      scalp_id=CScalpController::BuildSignalId(
                  iTime(m_config.symbol,m_config.timeframe,0),
                  is_buy,(int)decision.signal.strategy,
                  structure_event,structure_time);

      const double spread_points=(m_trade!=NULL ? m_trade.SpreadPoints() : 0.0);
      const int open_now=(m_trade!=NULL ? m_trade.PositionCount() : 0);
      //--- TIER FROM THE MARKET. Selected here so the geometry, the hold
      //--- window and the break-even test all belong to one decision.
      scalp_tier=SelectScalpTier();
      if(!m_scalp.Evaluate(scalp_id,TimeCurrent(),spread_points,
                           open_now,m_config.max_positions,scalp_verdict,
                           scalp_tier))
        {
         m_gate_scalp++;
         //--- SCALP REJECTED, with the primary reason named.
         CEnterpriseLogger *slog=m_ui.Logger();
         if(slog!=NULL)
            slog.LogRiskEvent("Scalp",
                              "SCALP "+
                              CScalpController::BlockToString(scalp_verdict.block)+
                              ": "+scalp_verdict.detail,
                              scalp_verdict.spread_points,
                              scalp_verdict.target_points,0.0);
         return;
        }
     }

   //--- 5c. THE TIER'S OWN STOP, APPLIED BEFORE SIZING.
   //---
   //--- Startup configured the protection manager with ONE stop multiple
   //--- for every tier, on the reasoning that sizing must be settled before
   //--- a signal exists. Measurement showed that reasoning cost real money:
   //--- regime routing sends essentially every gold trade to SUPER, so the
   //--- "middle tier compromise" was not a compromise at all - 48 of 48
   //--- trades ran a 0.70xATR stop while the tier had been designed, and
   //--- its break-even computed, around 0.45xATR. Losses came in at 25.1
   //--- against wins of 18.9, so the geometry inverted itself and profit
   //--- factor stayed at 0.797 even after the target was widened.
   //---
   //--- The tier IS known here: the scalp gate has already run and chosen
   //--- it. Applying its stop now means volume is computed from the stop the
   //--- trade will actually carry, which is what keeps the 0.25% risk
   //--- ceiling honest as well as the payoff.
   if(scalping && scalp_verdict.allowed && m_protection!=NULL)
     {
      const double tier_stop=m_scalp.TierStopAtrMultiple(scalp_tier);
      if(tier_stop>0.0)
         m_protection.ConfigureStop(SRP_STOP_ATR_MULTIPLE,
                                    m_config.scalp_target_min_points,
                                    tier_stop);
     }

   //--- 6. Size and protect. One call returns volume, stop, target and a
   //--- verdict; the guards can still refuse here.
   SSizingResult sizing;
   SProtectionPlan plan;
   SRiskVerdict verdict;
   if(!m_risk.EvaluateEntry(is_buy,entry,TotalOpenLots(),
                            ExposureRiskPercent(),sizing,plan,verdict))
     {
      m_gate_risk_engine++;
      CEnterpriseLogger *log=m_ui.Logger();
      if(log!=NULL)
         log.LogRiskEvent("RiskEngine",
                          "entry refused: "+
                          (verdict.detail!="" ? verdict.detail
                                              : sizing.rejection_reason),
                          verdict.measured,verdict.limit,0.0);
      //--- A guard demanding flatten outranks everything.
      if(verdict.flatten_required)
         EmergencyFlatten("risk guard: "+verdict.detail);
      return;
     }

   //--- 6b. SCALP TARGET OVERRIDE.
   //---
   //--- The risk engine produced a swing-style target from the configured
   //--- risk:reward. For a scalp that is far too distant. The scalp
   //--- controller's target is substituted, and it is already:
   //---   * ATR-derived, so volatility-aware
   //---   * clamped above the broker stop level, so broker-valid
   //---   * proven to clear spread + commission + execution cost
   //---
   //--- THE STOP IS LEFT EXACTLY AS THE RISK ENGINE SET IT. Sizing was
   //--- computed against that stop, so replacing it here would break the
   //--- link between risk and volume. Narrowing the target only ever
   //--- reduces reward, never increases risk.
   double scalp_target=0.0;
   if(scalping && scalp_verdict.allowed && scalp_verdict.target_points>0.0)
     {
      const double point=SymbolInfoDouble(m_config.symbol,SYMBOL_POINT);
      if(point>0.0)
        {
         const double offset=scalp_verdict.target_points*point;
         const double candidate=(is_buy ? entry+offset : entry-offset);
         //--- Only ever move the target CLOSER. If the risk engine already
         //--- chose something tighter, respect it.
         const bool closer=(!plan.has_target ||
                            (is_buy ? candidate<plan.target_price
                                    : candidate>plan.target_price));
         if(closer)
           {
            plan.target_price=NormalizeDouble(candidate,
                                (int)SymbolInfoInteger(m_config.symbol,
                                                       SYMBOL_DIGITS));
            plan.has_target=true;
            plan.target_distance_points=scalp_verdict.target_points;
           }
         scalp_target=plan.target_distance_points;
        }
     }

   //--- 7. Execute.
   SExecutionReport report;
   const bool sent=(is_buy
                    ? m_trade.Buy(sizing.volume,plan.stop_price,
                                  plan.target_price,decision.explanation,report)
                    : m_trade.Sell(sizing.volume,plan.stop_price,
                                   plan.target_price,decision.explanation,report));

   CEnterpriseLogger *log=m_ui.Logger();
   if(!sent)
     {
      if(log!=NULL)
         log.LogError("Execution","entry rejected: "+report.failure_detail,
                      (int)report.retcode);
      return;
     }
   m_entries++;
   //--- Remembered for R-multiple attribution when this position closes.
   m_last_entry_stop=plan.stop_price;

   //--- SCALP ENTRY RECORDED, and only now.
   //---
   //--- Recording on a CONFIRMED fill rather than on intent. Marking the
   //--- signal as traded before the order succeeded would consume the
   //--- setup while no position existed, permanently suppressing a signal
   //--- whose order the broker rejected.
   if(scalping && scalp_verdict.allowed)
     {
      m_scalp.RecordEntry(scalp_id,TimeCurrent(),scalp_verdict.spread_points,
                          scalp_tier);
      TrackScalp(report.position_ticket,scalp_target,scalp_tier,
                 scalp_verdict.max_hold_seconds);
      //--- Read the tracking BACK, and report it.
      //---
      //--- The early-profit exit is measured as a share of the target this
      //--- position was entered with, so a target of zero silently disables
      //--- it: ShouldTakeEarlyProfit requires target_points>0 while the
      //--- timeout does not. That asymmetry would look exactly like "the
      //--- early exit never happened to trigger", which is unfalsifiable
      //--- from the trade list alone. Printing the value that was actually
      //--- stored, against the ticket it was stored under, makes the
      //--- difference visible in the log.
      const double tracked=ScalpTargetFor(report.position_ticket);
      if(tracked<=0.0)
         Print(SRP_PRODUCT_NAME,": WARNING scalp target not tracked for "
               "ticket ",report.position_ticket,
               " - early profit exit is inert for this position");
      CEnterpriseLogger *elog=m_ui.Logger();
      if(elog!=NULL)
         elog.LogTrade("ScalpEntry",
                       StringFormat("SCALP ENTRY %s | %s | tracked target=%.0f "
                                    "pts | id=%s",
                                    (is_buy ? "BUY" : "SELL"),
                                    scalp_verdict.detail,tracked,
                                    scalp_id.Describe()),
                       report.position_ticket,report.executed_price,
                       report.executed_volume,0.0);
     }

   if(log!=NULL)
     {
      log.LogTrade("Entry",
                   (is_buy ? "BUY " : "SELL ")+
                   DoubleToString(sizing.volume,2)+" "+m_config.symbol+
                   " | "+decision.explanation,
                   report.position_ticket,report.executed_price,
                   report.executed_volume,0.0);
      log.LogExecutionTime("OrderSend",(double)report.total_elapsed_ms,
                           report.attempts,report.slippage_points,
                           report.position_ticket);
      log.LogRiskEvent("Sizing",sizing.explanation,
                       sizing.risk_percent,m_config.risk_percent,
                       sizing.risk_amount);
     }
  }
//+------------------------------------------------------------------+
void CProductionEngine::BuildDashboardModel(SDashboardModel &model)
  {
   model.Reset();
   model.symbol          = m_config.symbol;
   model.product_version = SRP_PRODUCT_VERSION;
   model.currency        = AccountInfoString(ACCOUNT_CURRENCY);
   model.balance         = AccountInfoDouble(ACCOUNT_BALANCE);
   model.equity          = AccountInfoDouble(ACCOUNT_EQUITY);
   model.margin_used     = AccountInfoDouble(ACCOUNT_MARGIN);
   model.margin_free     = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   model.margin_level    = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   if(m_trade!=NULL)
     {
      model.floating_profit = m_trade.FloatingProfit();
      model.open_trades     = m_trade.PositionCount();
      model.total_volume    = m_trade.TotalVolume();
      model.spread_points   = m_trade.SpreadPoints();
      model.average_slippage_points = m_trade.AverageSlippagePoints();
     }
   model.risk_percent = m_config.risk_percent;
   model.lot_size     = m_config.fixed_lot;

   if(m_decision!=NULL)
     {
      STradeDecision last;
      m_decision.GetLastDecision(last);
      model.strategy_text   = (last.signal.strategy_name!=""
                               ? last.signal.strategy_name
                               : "waiting");
      if(last.actionable)
        {
         model.signal_text=(last.decision==SRP_DECISION_BUY ? "BUY " : "SELL ")+
                           DoubleToString(last.final_confidence,2)+" | "+
                           last.signal.strategy_name;
         model.signal_tone=(last.decision==SRP_DECISION_BUY
                            ? SRP_UI_TONE_POSITIVE : SRP_UI_TONE_NEGATIVE);
        }
      else
        {
         model.signal_text="WAIT: "+
                           CDecisionEngine::DeclineToString(last.decline_reason)+
                           (last.explanation!="" ? " | "+last.explanation : "");
         model.signal_tone=(last.decline_reason==SRP_DECLINE_NONE
                            ? SRP_UI_TONE_MUTED : SRP_UI_TONE_WARNING);
        }
      //--- The session describes itself through its block detail when
      //--- blocked, and through the named session when trading.
      model.session_text    = (last.session.block_detail!=""
                               ? last.session.block_detail
                               : CSessionManager::SessionToString(
                                    last.session.active_session));
      model.news_countdown  = last.news.detail;
      model.news_paused     = !last.news.trading_permitted;
      model.session_blocked = !last.session.trading_permitted;
     }

   model.engine_state = (m_running ? "TRADING" : "HALTED");
   if(!m_running && m_halt_reason!="")
      model.engine_state="HALTED: "+m_halt_reason;

   if(m_risk!=NULL && m_risk.IsEmergencyActive())
     {
      model.health_text="EMERGENCY";
      model.health_tone=SRP_UI_TONE_CRITICAL;
     }
   else
      if(m_limits!=NULL && m_limits.IsAnyTripped())
        {
         model.health_text=m_limits.TripDetail();
         model.health_tone=SRP_UI_TONE_WARNING;
        }
      else
        {
         model.health_text="OK";
         model.health_tone=SRP_UI_TONE_POSITIVE;
        }

   model.updated_at=TimeCurrent();
   model.is_valid=true;

   //--- Analytics owns the performance rows and fills them itself.
   if(m_ui!=NULL)
      m_ui.ApplyAnalytics(model);
  }
//+------------------------------------------------------------------+
void CProductionEngine::Render(void)
  {
   if(m_ui==NULL)
      return;
   SDashboardModel model;
   BuildDashboardModel(model);
   m_ui.Render(model);
  }
//+------------------------------------------------------------------+
//| Slow, non-critical work belongs here and NOT on the tick path.       |
//+------------------------------------------------------------------+
void CProductionEngine::OnTimerEvent(void)
  {
   if(!m_built)
      return;
   const datetime now=TimeCurrent();
   if(m_news!=NULL)
      m_news.Refresh(now,false);
   if(m_limits!=NULL)
      m_limits.UpdateWindows(AccountInfoDouble(ACCOUNT_EQUITY),now);
   if(m_ui!=NULL && m_ui.Logger()!=NULL)
      m_ui.Logger().Flush();
  }
//+------------------------------------------------------------------+
//| Closed positions are recorded HERE, not by polling. OnTradeTransaction|
//| is the only authoritative notification that a stop or target was hit. |
//+------------------------------------------------------------------+
void CProductionEngine::OnTradeTransactionEvent(const MqlTradeTransaction &transaction,
                                                const MqlTradeRequest &request,
                                                const MqlTradeResult &result)
  {
   if(!m_built || m_ui==NULL)
      return;
   if(transaction.type!=TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(transaction.symbol!=m_config.symbol)
      return;

   //--- Only a closing deal produces a completed trade record.
   if(!HistoryDealSelect(transaction.deal))
      return;
   if(HistoryDealGetInteger(transaction.deal,DEAL_MAGIC)!=m_config.magic)
      return;
   const ENUM_DEAL_ENTRY entry=
      (ENUM_DEAL_ENTRY)HistoryDealGetInteger(transaction.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY)
      return;

   SClosedTrade trade;
   trade.ticket       = (ulong)HistoryDealGetInteger(transaction.deal,DEAL_POSITION_ID);
   trade.symbol       = m_config.symbol;
   //--- A closing SELL deal closes a BUY position, so the side is inverted.
   trade.is_buy       = (HistoryDealGetInteger(transaction.deal,DEAL_TYPE)==DEAL_TYPE_SELL);
   trade.volume       = HistoryDealGetDouble(transaction.deal,DEAL_VOLUME);
   trade.close_price  = HistoryDealGetDouble(transaction.deal,DEAL_PRICE);
   trade.close_time   = (datetime)HistoryDealGetInteger(transaction.deal,DEAL_TIME);
   trade.gross_profit = HistoryDealGetDouble(transaction.deal,DEAL_PROFIT);
   trade.commission   = HistoryDealGetDouble(transaction.deal,DEAL_COMMISSION);
   trade.swap         = HistoryDealGetDouble(transaction.deal,DEAL_SWAP);
   trade.net_profit   = trade.gross_profit+trade.commission+trade.swap;
   trade.exit_reason  = HistoryDealGetString(transaction.deal,DEAL_COMMENT);
   trade.balance_after= AccountInfoDouble(ACCOUNT_BALANCE);

   //--- OPENING SIDE. Without it every trade reports a zero duration and
   //--- a zero R-multiple, which quietly disables two of the analytics
   //--- the optimisation criterion and the user both rely on. The entry
   //--- deal is found by selecting the position's own history.
   if(HistorySelectByPosition(trade.ticket))
     {
      const int deals=HistoryDealsTotal();
      for(int i=0;i<deals;i++)
        {
         const ulong entry_deal=HistoryDealGetTicket(i);
         if(entry_deal==0)
            continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(entry_deal,DEAL_ENTRY)
            !=DEAL_ENTRY_IN)
            continue;
         trade.open_time  = (datetime)HistoryDealGetInteger(entry_deal,DEAL_TIME);
         trade.open_price = HistoryDealGetDouble(entry_deal,DEAL_PRICE);
         trade.strategy_name=HistoryDealGetString(entry_deal,DEAL_COMMENT);
         break;
        }
      if(trade.open_time>0 && trade.close_time>=trade.open_time)
         trade.duration_seconds=(int)(trade.close_time-trade.open_time);
     }

   //--- Risk actually committed, so R-multiples measure against what was
   //--- genuinely at stake. Priced through the risk engine, which asks the
   //--- terminal rather than deriving from tick_value - the same figure
   //--- the position was sized on, so the R is self-consistent.
   if(trade.open_price>0.0 && trade.volume>0.0 &&
      m_last_entry_stop>0.0 && m_risk!=NULL)
     {
      const double point=SymbolInfoDouble(m_config.symbol,SYMBOL_POINT);
      if(point>0.0)
        {
         const double distance_points=
            MathAbs(trade.open_price-m_last_entry_stop)/point;
         const double per_lot=m_risk.BrokerMoneyPerLot(distance_points);
         if(per_lot>0.0)
           {
            trade.risk_amount=per_lot*trade.volume;
            trade.r_multiple=trade.net_profit/trade.risk_amount;
           }
        }
     }

   //--- SCALP METRICS. Attribution comes from the exit comment where the
   //--- system authored it, and from the outcome where the broker closed
   //--- the position at its stop or target.
   if(m_scalp!=NULL && m_scalp.IsEnabled())
     {
      ENUM_SRP_TM_TRIGGER trigger=SRP_TM_TRIGGER_NONE;
      if(StringFind(trade.exit_reason,"early profit")>=0)
         trigger=SRP_TM_TRIGGER_EARLY_PROFIT;
      else
         if(StringFind(trade.exit_reason,"timeout")>=0)
            trigger=SRP_TM_TRIGGER_SCALP_TIMEOUT;
      //--- Tier read BEFORE untracking: the lookup is keyed on the ticket
      //--- and untracking removes it, so the order here decides whether
      //--- the trade is attributed to its own tier or to a default.
      //--- Still-tracked positions answer directly; ones this engine closed
      //--- itself are recalled from the ring, because untracking has
      //--- already removed the key by the time this notification arrives.
      ENUM_SRP_SCALP_TIER exit_tier=ScalpTierFor(trade.ticket);
      bool tracked=false;
      for(int t=0;t<m_scalp_tracked;t++)
         if(m_scalp_tickets[t]==trade.ticket)
           { tracked=true; break; }
      if(!tracked)
         exit_tier=RecallClosedTier(trade.ticket);
      m_scalp.RecordExit(trigger,trade.duration_seconds,trade.net_profit,
                         exit_tier);
      UntrackScalp(trade.ticket);
     }

   //--- Feeds analytics, the trade log, untracking and chart cleanup.
   m_ui.OnTradeClosed(trade);
   if(m_risk!=NULL)
      m_risk.RecordClosedTrade(trade.net_profit,trade.close_time);
  }
//+------------------------------------------------------------------+
void CProductionEngine::OnChartEventReceived(const int id,const long &lparam,
                                             const double &dparam,
                                             const string &sparam)
  {
   if(!m_built || m_ui==NULL)
      return;
   //--- Keyboard shortcuts, the only chart interaction the product needs.
   if(id!=CHARTEVENT_KEYDOWN)
      return;
   switch((int)lparam)
     {
      case 'D': case 'd':
         m_ui.ToggleCollapsed();
         break;
      case 'H': case 'h':
         if(m_running) Halt("operator keypress");
         else          Resume("operator keypress");
         break;
     }
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| STRATEGY TESTER FITNESS.                                             |
//|                                                                  |
//| The terminal calls OnTester after the last tick but BEFORE OnDeinit,  |
//| so the graph is still alive here and the integration can read the     |
//| pass statistics.                                                     |
//|                                                                  |
//| The closed-trade distribution is handed to the Monte Carlo simulator  |
//| first, so a single backtest can answer "what is the risk of ruin for  |
//| this equity curve" rather than only "what did it earn".               |
//+------------------------------------------------------------------+
double CProductionEngine::OnTesterEvent(void)
  {
   if(m_tester==NULL)
      return(0.0);

   //--- Feed the realised trade series in before scoring, so the report
   //--- describes this pass rather than an empty sample.
   if(m_monte_carlo!=NULL && m_ui!=NULL)
     {
      CPerformanceAnalytics *analytics=m_ui.Analytics();
      if(analytics!=NULL)
        {
         const int count=analytics.TradeCount();
         for(int i=0;i<count;i++)
           {
            SClosedTrade trade;
            if(analytics.TradeAt(i,trade))
               m_monte_carlo.AddResult(trade.net_profit);
           }
        }
     }
   return(m_tester.Evaluate());
  }
//+------------------------------------------------------------------+
void CProductionEngine::Halt(const string reason)
  {
   m_running=false;
   m_halt_reason=reason;
   //--- Halt stops NEW entries only. Open positions remain managed,
   //--- because abandoning a live position is never the safe default.
   if(m_ui!=NULL && m_ui.Logger()!=NULL)
      m_ui.Logger().LogRiskEvent("Engine","halted: "+reason,0.0,0.0,0.0);
  }
//+------------------------------------------------------------------+
void CProductionEngine::Resume(const string reason)
  {
   m_running=true;
   m_halt_reason="";
   if(m_ui!=NULL && m_ui.Logger()!=NULL)
      m_ui.Logger().LogRiskEvent("Engine","resumed: "+reason,0.0,0.0,0.0);
  }
//+------------------------------------------------------------------+
int CProductionEngine::EmergencyFlatten(const string reason)
  {
   if(m_trade==NULL)
      return(0);
   //--- Latch first, then flatten. Latching afterwards leaves a window in
   //--- which a tick could open a fresh position while closing the old.
   if(m_risk!=NULL)
      m_risk.TriggerEmergencyShutdown(reason,TimeCurrent());
   Halt("emergency: "+reason);

   const int closed=m_trade.CloseAll(reason);
   if(m_ui!=NULL && m_ui.Logger()!=NULL)
      m_ui.Logger().LogError("Engine","EMERGENCY FLATTEN: "+reason+
                             ", closed "+IntegerToString(closed));
   return(closed);
  }
//+------------------------------------------------------------------+
string CProductionEngine::Describe(void) const
  {
   string text="CProductionEngine["+m_config.symbol+" "+
               EnumToString(m_config.timeframe)+"]";
   text+=" built="+(m_built ? "yes" : "no");
   text+=" running="+(m_running ? "yes" : "no");
   text+=" ticks="+IntegerToString(m_ticks);
   text+=" entries="+IntegerToString(m_entries);
   text+=" managed="+IntegerToString(m_managed_actions);
   if(m_halt_reason!="")
      text+=" halt="+m_halt_reason;
   if(m_decision!=NULL)
      text+="\n  "+m_decision.Describe();
   if(m_risk!=NULL)
      text+="\n  "+m_risk.Describe();
   if(m_trade!=NULL)
      text+="\n  "+m_trade.DescribeStatistics();
   return(text);
  }

#endif // SRP_RUNTIME_CPRODUCTIONENGINE_MQH
//+------------------------------------------------------------------+
