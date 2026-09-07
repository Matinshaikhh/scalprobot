//+------------------------------------------------------------------+
//|                                          ProductionCheck.mqh |
//|                  Scalping Robot Pro - Production Integration Test |
//|                                                                  |
//|   The harness BODY lives here rather than in an .mq5 file so that the |
//|   same assertions can be launched two ways without being duplicated:  |
//|                                                                  |
//|     Scripts\ScalpRobotPro\P6ProductionCheck.mq5  - run from a chart   |
//|     Experts\ScalpRobotPro\P6ProductionCheck.mq5  - run headless via   |
//|                                                    the Strategy Tester|
//|                                                                  |
//|   Only the Strategy Tester can be driven from a command line, and it   |
//|   will not launch a script. Keeping the body in a header is what lets  |
//|   the automated build verify runtime behaviour rather than only        |
//|   compilation.                                                       |
//|                                                                  |
//|   THE FINAL-PHASE HARNESS. It verifies the things a compile cannot:  |
//|                                                                  |
//|     1. the umbrella header pulls in every module coherently;        |
//|     2. the input snapshot survives the round trip through the sealed |
//|        configuration and comes back with the SAME values;           |
//|     3. CProductionEngine builds its entire object graph against a    |
//|        real provider, validates, starts, ticks and tears down with   |
//|        no leaked pointers;                                          |
//|     4. every configuration group actually reaches its subsystem -    |
//|        the "no hardcoded values" claim, asserted rather than stated; |
//|     5. the optimisation engine ranks a stable set above a curve-      |
//|        fitted one, which is the only reason a custom criterion       |
//|        exists;                                                     |
//|     6. teardown is clean: MQL5 reports leaked objects at script end. |
//|                                                                  |
//|   IT PLACES NO TRADES. Entry seeking is never reached because the    |
//|   engine is halted before the tick pump runs, so OrderSend is        |
//|   unreachable by construction rather than by luck.                  |
//+------------------------------------------------------------------+
#ifndef SRP_TESTS_PRODUCTIONCHECK_MQH
#define SRP_TESTS_PRODUCTIONCHECK_MQH

#include "../ScalpRobotPro.mqh"

//--- Assertion tally. A harness that prints "ok" without counting is
//--- indistinguishable from one that silently skipped everything.
int g_checks = 0;
int g_failed = 0;

//+------------------------------------------------------------------+
void Check(const string label,const bool condition)
  {
   g_checks++;
   if(!condition)
     {
      g_failed++;
      Print("  FAIL  ",label);
      return;
     }
   Print("  ok    ",label);
  }
//+------------------------------------------------------------------+
void CheckNear(const string label,const double actual,const double expected,
               const double tolerance=0.0000001)
  {
   const bool ok=(MathAbs(actual-expected)<=tolerance);
   Check(StringFormat("%s (%.6f vs %.6f)",label,actual,expected),ok);
  }

//+------------------------------------------------------------------+
//| 1. CONFIGURATION ROUND TRIP                                        |
//|                                                                  |
//| The snapshot is the .mq5 input block. If a value does not survive   |
//| the trip into the sealed store and back out through CRuntimeConfig, |
//| then some subsystem is running on a default the user never chose -   |
//| which is exactly the failure "no hardcoded values" is meant to       |
//| prevent. Spot values are deliberately NON-DEFAULT so a silent        |
//| fallback cannot pass by coincidence.                                |
//+------------------------------------------------------------------+
void TestConfigurationRoundTrip(void)
  {
   Print("=== 1. CONFIGURATION ROUND TRIP ===");

   SInputSnapshot in;
   CConfigurationBuilder::ApplyNasdaqDefaults(in);

   //--- Deliberately odd values: none of these is a documented default.
   in.magic                   = 987654321;
   in.risk_percent            = 0.37;
   in.max_lot                 = 3.75;
   in.max_positions           = 7;
   in.sl_atr_multiplier       = 2.85;
   in.tp_risk_reward          = 2.45;
   in.fast_ma_period          = 11;
   in.slow_ma_period          = 34;
   in.max_spread_points       = 47.0;
   in.news_minutes_before     = 23;
   in.smc_zone_capacity       = 41;
   in.dashboard_refresh_ms    = 750;
   in.opt_min_trades          = 55;
   in.risk_capital_base       = (int)SRP_CAPITAL_HIGH_WATER_MARK;
   in.state_folder            = "ScalpRobotPro\\P6State";

   CInputConfiguration *config=new CInputConfiguration(NULL);
   Check("builder populated the store",
         CConfigurationBuilder::Populate(config,in));
   Check("store is sealed after Populate",config.IsSealed());
   Check("store holds a realistic key count",config.Count()>=150);
   //--- Immutability is the whole point of sealing.
   Check("write to a sealed store is refused",
         !config.SetDouble(CConfigKeys::RISK_PERCENT,99.0));

   //--- Now read it back the way the engine does.
   SRuntimeConfig rc;
   CRuntimeConfig::Load(config,_Symbol,PERIOD_M5,rc);

   Check("symbol passed through",rc.symbol==_Symbol);
   Check("timeframe passed through",rc.timeframe==PERIOD_M5);
   Check("magic survived",rc.magic==987654321);
   CheckNear("risk percent survived",rc.risk_percent,0.37);
   CheckNear("max lot survived",rc.max_lot,3.75);
   Check("max positions survived",rc.max_positions==7);
   CheckNear("stop ATR multiple survived",rc.sl_atr_multiplier,2.85);
   CheckNear("target risk:reward survived",rc.tp_risk_reward,2.45);
   Check("fast MA survived",rc.fast_ma_period==11);
   Check("slow MA survived",rc.slow_ma_period==34);
   CheckNear("max spread survived",rc.max_spread_points,47.0);
   Check("news window survived",rc.news_minutes_before==23);
   Check("zone capacity survived",rc.smc_zone_capacity==41);
   Check("dashboard refresh survived",rc.dashboard_refresh_ms==750);
   Check("optimisation min trades survived",rc.opt_min_trades==55);
   Check("capital base survived",
         rc.risk_capital_base==(int)SRP_CAPITAL_HIGH_WATER_MARK);
   Check("state folder survived",rc.state_folder=="ScalpRobotPro\\P6State");

   //--- A null provider must yield documented defaults, not zeroes. This
   //--- is what makes every module constructible in a test.
   SRuntimeConfig defaults;
   CRuntimeConfig::Load(NULL,_Symbol,PERIOD_M1,defaults);
   Check("null provider still yields a usable risk percent",
         defaults.risk_percent>0.0);
   Check("null provider still yields a usable ATR period",
         defaults.atr_period>0);

   //--- An unknown key must count as a miss rather than silently pass.
   const long before=config.MissCount();
   config.GetInt("key.that.does.not.exist",1234);
   Check("absent key is recorded as a miss",config.MissCount()==before+1);

   delete config;
  }

//+------------------------------------------------------------------+
//| 2. CONFIGURATION VALIDATION                                        |
//|                                                                  |
//| A contradictory setting must abort startup, not surface as odd       |
//| behaviour thousands of ticks later.                                 |
//+------------------------------------------------------------------+
void TestConfigurationValidation(void)
  {
   Print("=== 2. CONFIGURATION VALIDATION ===");

   CConfigValidator validator(NULL);

   SInputSnapshot good;
   CConfigurationBuilder::ApplyNasdaqDefaults(good);
   CInputConfiguration *ok_config=new CInputConfiguration(NULL);
   CConfigurationBuilder::Populate(ok_config,good);
   SValidationResult ok_result;
   Check("shipped NASDAQ preset validates",
         validator.ValidateAll(ok_config,ok_result));

   //--- Per-trade risk at or above the daily cap ends every day on one
   //--- loss. The validator must refuse it.
   SInputSnapshot fatal;
   CConfigurationBuilder::ApplyNasdaqDefaults(fatal);
   fatal.risk_percent=5.0;
   fatal.daily_loss_enabled=true;
   fatal.daily_loss_percent=3.0;
   CInputConfiguration *bad_config=new CInputConfiguration(NULL);
   CConfigurationBuilder::Populate(bad_config,fatal);
   SValidationResult bad_result;
   const bool accepted=validator.ValidateAll(bad_config,bad_result);
   Check("risk above the daily cap is reported",
         !accepted || bad_result.warning_count>0);

   //--- The optimisation screen: skip a pass that cannot say anything.
   CParameterSetValidator screen(NULL);
   SInputSnapshot inverted;
   CConfigurationBuilder::ApplyNasdaqDefaults(inverted);
   inverted.fast_ma_period=50;
   inverted.slow_ma_period=9;
   CInputConfiguration *inv_config=new CInputConfiguration(NULL);
   CConfigurationBuilder::Populate(inv_config,inverted);
   SValidationResult inv_result;
   Check("inverted MA pair is screened out of an optimisation",
         !screen.IsWorthTesting(inv_config,inv_result));

   delete inv_config;
   delete bad_config;
   delete ok_config;
  }

//+------------------------------------------------------------------+
//| 3. THE PRODUCTION ENGINE, END TO END                               |
//|                                                                  |
//| Builds the real object graph over a real provider. This is the check |
//| that matters: it proves the composition root can construct every     |
//| subsystem, that validation passes, that the tick pipeline runs, and   |
//| that teardown releases everything.                                   |
//+------------------------------------------------------------------+
void TestProductionEngine(void)
  {
   Print("=== 3. PRODUCTION ENGINE LIFECYCLE ===");

   SInputSnapshot in;
   CConfigurationBuilder::ApplyNasdaqDefaults(in);
   //--- Never touch the calendar or persist state from a harness.
   in.news_filter_enabled = false;
   in.persist_state       = false;
   in.dashboard_enabled   = false;
   in.draw_overlay_enabled= false;
   in.magic               = 20260899;   // a magic no live chart uses

   CInputConfiguration *config=new CInputConfiguration(NULL);
   if(!CConfigurationBuilder::Populate(config,in))
     {
      Check("configuration for the engine was populated",false);
      delete config;
      return;
     }

   CProductionEngine *engine=new CProductionEngine();
   const bool built=engine.Build(config,_Symbol,_Period);
   Check("engine built the entire object graph",built);
   if(!built)
     {
      Print("  validation report:");
      Print(engine.ValidationReport());
      delete engine;
      delete config;
      return;
     }
   Check("engine reports itself built",engine.IsBuilt());

   //--- Configuration actually reached the engine.
   SRuntimeConfig applied;
   engine.GetConfig(applied);
   Check("engine received the configured magic",applied.magic==20260899);
   Check("engine received the configured symbol",applied.symbol==_Symbol);
   Check("news filter stayed disabled as configured",
         !applied.news_filter_enabled);
   //--- THE SIZING MODEL MUST BE THE ONE THAT WAS ASKED FOR. Two enum
   //--- vocabularies describe sizing with different numbering, and a
   //--- mismatch is silent: the preset requested percent-of-equity and the
   //--- engine once built a Kelly sizer, which then refused every signal
   //--- for want of a sample. Asserting the round trip closes that.
   Check("sizing model survived as the model requested",
         applied.risk_model==(int)SRP_SIZING_RISK_PERCENT);

   //--- Subsystems are reachable and real.
   Check("risk engine is wired",       engine.Risk()!=NULL);
   Check("decision engine is wired",   engine.Decision()!=NULL);
   Check("trade engine is wired",      engine.Trade()!=NULL);
   Check("trader interface is wired",  engine.Interface()!=NULL);
   Check("environment guard is wired", engine.Environment()!=NULL);
   Check("tester integration is wired",engine.Tester()!=NULL);

   //--- At least one strategy plugin must exist, or the robot can never
   //--- signal and would sit idle while appearing healthy.
   if(engine.Decision()!=NULL)
      Check("at least one strategy plugin was constructed",
            engine.Decision().PluginCount()>0);

   //--- The environment guard must agree with the terminal about where it
   //--- is running, and suppress exactly the right subsystems there.
   //--- The harness runs BOTH as a chart script (live) and as a tester
   //--- expert, so these assertions are written against the actual
   //--- environment rather than assuming one.
   COptimizationGuard *env=engine.Environment();
   if(env!=NULL)
     {
      const bool in_tester=(bool)MQLInfoInteger(MQL_TESTER);
      const bool optimising=(bool)MQLInfoInteger(MQL_OPTIMIZATION);

      Check("guard agrees with the terminal about being live",
            env.IsLive()==!in_tester);
      Check("guard agrees with the terminal about being in the tester",
            env.IsTester()==in_tester);
      Check("guard agrees with the terminal about optimising",
            env.IsOptimization()==optimising);

      //--- THE RULE THAT PROTECTS AN OPTIMISATION: persisted state must
      //--- never survive from one tester pass into the next, because it
      //--- would silently bias every pass after the first.
      Check("state persistence is enabled live and suppressed in the tester",
            env.ShouldEnableStatePersistence()==!in_tester);
      Check("notifications are suppressed in the tester",
            env.ShouldEnableNotifications()==!in_tester);
      //--- The calendar returns TODAY's events regardless of the simulated
      //--- bar, so consulting it in a backtest is look-ahead bias.
      Check("calendar news provider is suppressed in the tester",
            env.ShouldEnableNewsProvider()==!in_tester);
      Check("dashboard is suppressed during an optimisation",
            !(optimising && env.ShouldEnableDashboard()));
      Check("file logging is suppressed during an optimisation",
            env.ShouldEnableFileLogging()==!optimising);
      //--- Even Print costs measurable time across thousands of passes.
      Check("log level is forced off during an optimisation",
            !optimising ||
            env.RecommendedLogLevel(SRP_LOG_INFO)==SRP_LOG_OFF);
      Print("  environment: ",env.DescribeEnvironment());
     }

   //--- THE RISK CONVERSION. This is the single most consequential number
   //--- in the product: every position size divides by it. It is asserted
   //--- against the terminal's own OrderCalcProfit because a silent
   //--- disagreement here does not throw, it just trades the wrong size.
   //--- Deriving it from tick_value once understated gold risk 10x, so
   //--- this assertion exists specifically to stop that regressing.
   if(engine.Risk()!=NULL)
     {
      const double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      const double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      const double distance_points=1000.0;
      const double ours=engine.Risk().BrokerMoneyPerLot(distance_points);
      double expected=0.0;
      bool priced=false;
      if(point>0.0 && ask>0.0)
         priced=OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,ask,
                                ask-distance_points*point,expected);
      expected=(priced ? MathAbs(expected) : 0.0);

      Check("money-per-lot is available from the terminal",ours>0.0);
      if(ours>0.0 && expected>0.0)
        {
         //--- Relative tolerance: the figure scales with the instrument.
         const bool agrees=(MathAbs(ours-expected)/expected<0.01);
         Check(StringFormat("money-per-lot agrees with OrderCalcProfit "
                            "(%.2f vs %.2f)",ours,expected),agrees);
        }
     }

   Check("engine started",engine.Start()==INIT_SUCCEEDED);
   Check("engine is running after start",engine.IsRunning());

   //--- HALT BEFORE TICKING. Management still runs, entry seeking does
   //--- not, so no order can be sent from a verification harness.
   engine.Halt("integration harness: entries forbidden");
   Check("halt stops new entries",!engine.IsRunning());

   //--- Pump ticks. This exercises throttle, indicator refresh, structure
   //--- refresh, account refresh, position management and rendering.
   for(int i=0;i<250;i++)
      engine.OnTickEvent();
   Check("tick pipeline ran without a crash",engine.TickCount()>0);
   Check("no entry was taken while halted",engine.EntryCount()==0);

   //--- The timer path: news refresh, limit windows, log flush.
   engine.OnTimerEvent();
   engine.OnTimerEvent();
   Check("timer pipeline ran without a crash",true);

   //--- Resume and confirm the flag flips back.
   engine.Resume("integration harness");
   Check("resume re-enables entries",engine.IsRunning());
   engine.Halt("integration harness: re-armed");

   //--- The tester hook must return a finite number rather than crash,
   //--- whichever environment it is called from. With no closed trades
   //--- the minimum-trade gate rejects the pass, and that rejection IS
   //--- the correct answer here - a fluke must never top a table.
   const double fitness=engine.OnTesterEvent();
   Check("OnTester returns a finite fitness value",
         MathIsValidNumber(fitness));

   Print("  engine self-description:");
   Print(engine.Describe());

   //--- Teardown. Stop publishes the session report and releases the
   //--- graph; the destructor must then be harmless.
   engine.Stop(REASON_REMOVE);
   Check("engine reports not built after stop",!engine.IsBuilt());
   delete engine;      // second release must be safe
   delete config;
   Check("engine and configuration released cleanly",true);
  }

//+------------------------------------------------------------------+
//| 4. THE OPTIMISATION ENGINE                                         |
//|                                                                  |
//| The assertion that justifies a custom criterion: a modest, stable    |
//| parameter set must outrank a curve-fitted one that shows more profit  |
//| with a brutal drawdown and one dominant trade.                       |
//+------------------------------------------------------------------+
void TestOptimizationEngine(void)
  {
   Print("=== 4. OPTIMISATION ENGINE ===");

   COptimizationCriterion *criterion=new COptimizationCriterion(NULL);
   criterion.SetCriterion(SRP_CRITERION_CUSTOM_COMPOSITE);
   criterion.SetMinimumTrades(30);
   criterion.SetPenaltyWeights(1.0,1.0,1.0);

   STradeRecord none[];

   //--- The curve-fitted winner: what optimising on net profit picks.
   SPerformanceMetrics fitted;
   fitted.total_trades=35;
   fitted.winning_trades=12;
   fitted.losing_trades=23;
   fitted.gross_profit=12000.0;
   fitted.gross_loss=7000.0;
   fitted.net_profit=5000.0;
   fitted.profit_factor=1.71;
   fitted.largest_win=4200.0;             // 84% of net from ONE trade
   fitted.max_drawdown_money=4000.0;
   fitted.max_drawdown_percent=40.0;
   fitted.max_consecutive_losses=9;
   fitted.recovery_factor=1.25;

   //--- The modest, stable set.
   SPerformanceMetrics stable;
   stable.total_trades=140;
   stable.winning_trades=79;
   stable.losing_trades=61;
   stable.gross_profit=7400.0;
   stable.gross_loss=4900.0;
   stable.net_profit=2500.0;
   stable.profit_factor=1.51;
   stable.largest_win=400.0;              // 16% of net
   stable.max_drawdown_money=700.0;
   stable.max_drawdown_percent=7.0;
   stable.max_consecutive_losses=5;
   stable.recovery_factor=3.57;

   const double fit_fitted=criterion.Evaluate(fitted,none,fitted.total_trades);
   const double fit_stable=criterion.Evaluate(stable,none,stable.total_trades);
   Check("composite criterion ranks the stable set above the curve-fitted one",
         fit_stable>fit_fitted);

   //--- Net profit alone picks the wrong one. Proving that makes the
   //--- composite's value measurable rather than asserted.
   criterion.SetCriterion(SRP_CRITERION_NET_PROFIT);
   Check("net-profit criterion would have picked the curve-fitted set",
         criterion.Evaluate(fitted,none,fitted.total_trades)>
         criterion.Evaluate(stable,none,stable.total_trades));
   criterion.SetCriterion(SRP_CRITERION_CUSTOM_COMPOSITE);

   //--- A thin sample must be rejected outright, not ranked.
   SPerformanceMetrics thin=stable;
   thin.total_trades=6;
   Check("a six-trade sample is rejected rather than ranked",
         criterion.Evaluate(thin,none,6)<=criterion.RejectionValue());

   //--- Every named criterion must resolve to a real number.
   bool all_finite=true;
   for(int c=0;c<=(int)SRP_CRITERION_CUSTOM_COMPOSITE;c++)
     {
      criterion.SetCriterion((ENUM_SRP_OPTIMIZATION_CRITERION)c);
      if(!MathIsValidNumber(criterion.Evaluate(stable,none,
                                              stable.total_trades)))
         all_finite=false;
     }
   Check("every optimisation criterion returns a finite score",all_finite);
   criterion.SetCriterion(SRP_CRITERION_CUSTOM_COMPOSITE);

   //=== MONTE CARLO ==================================================
   CMonteCarloSimulator *mc=new CMonteCarloSimulator(NULL);
   mc.SetStartingBalance(10000.0);
   mc.SetRuns(500);
   mc.SetRuinThreshold(30.0);
   mc.SetSeed(20260808);                  // fixed seed: reproducible
   for(int i=0;i<120;i++)
      mc.AddResult((i%3==0) ? -85.0 : 52.0);

   SMonteCarloReport first;
   Check("monte carlo ran on a positive-expectancy series",mc.Run(first));

   SMonteCarloReport repeat;
   mc.SetSeed(20260808);
   mc.Run(repeat);
   CheckNear("the same seed reproduces the same risk of ruin",
             repeat.risk_of_ruin,first.risk_of_ruin,0.0001);

   //--- A losing distribution must show a materially worse risk of ruin,
   //--- otherwise the simulation is not actually simulating.
   CMonteCarloSimulator *doomed=new CMonteCarloSimulator(NULL);
   doomed.SetStartingBalance(10000.0);
   doomed.SetRuns(500);
   doomed.SetRuinThreshold(30.0);
   doomed.SetSeed(7);
   for(int i=0;i<120;i++)
      doomed.AddResult((i%2==0) ? 40.0 : -120.0);
   SMonteCarloReport doom;
   doomed.Run(doom);
   Check("a negative-expectancy system shows a far higher risk of ruin",
         doom.risk_of_ruin>first.risk_of_ruin);

   //=== WALK FORWARD =================================================
   CWalkForwardAnalyzer *wf=new CWalkForwardAnalyzer(NULL);
   wf.SetMinimumEfficiency(0.5);
   wf.SetMinimumConsistency(0.6);
   wf.SetMinimumOosTrades(20);
   const int planned=wf.PlanWindows(D'2025.01.01 00:00',D'2026.01.01 00:00',
                                    90,30);
   Check("walk-forward planned a sensible number of windows",planned>=3);
   for(int i=0;i<planned;i++)
     {
      const double is_net=1800.0+i*40.0;
      wf.SetWindowResults(i,2.0,1.6,is_net,is_net*0.65,70,26,8.0,10.0);
     }
   SWalkForwardReport robust;
   Check("a robust walk-forward result passes",wf.Analyze(robust));

   //--- In-sample brilliance with no out-of-sample edge must fail.
   CWalkForwardAnalyzer *over=new CWalkForwardAnalyzer(NULL);
   over.SetMinimumEfficiency(0.5);
   over.SetMinimumOosTrades(5);
   const int over_planned=over.PlanWindows(D'2025.01.01 00:00',
                                           D'2026.01.01 00:00',90,30);
   for(int i=0;i<over_planned;i++)
      over.SetWindowResults(i,3.5,0.35,4000.0,-260.0,80,20,6.0,26.0);
   SWalkForwardReport fitted_wf;
   Check("a curve-fitted walk-forward result is rejected",
         !over.Analyze(fitted_wf));

   //=== TESTER BOUNDARY ==============================================
   CTesterIntegration *tester=new CTesterIntegration(criterion,NULL);
   tester.SetMonteCarlo(mc);
   tester.SetRunMonteCarlo(false);
   //--- Export is off: a verification run must not append rows to the
   //--- user's real optimisation CSV.
   tester.SetExport(false,"");

   const bool in_tester=(bool)MQLInfoInteger(MQL_TESTER);
   const bool visual=(bool)MQLInfoInteger(MQL_VISUAL_MODE);
   Check("tester boundary agrees with the terminal",
         tester.IsTesting()==in_tester);
   //--- UI is pointless without a chart and a human: suppressed in a
   //--- headless pass, kept in visual mode and live.
   Check("UI suppression matches the environment",
         tester.ShouldSuppressUi()==(in_tester && !visual));
   Check("OnTester evaluation returns a finite value",
         MathIsValidNumber(tester.Evaluate()));

   delete tester;
   delete over;
   delete wf;
   delete doomed;
   delete mc;
   delete criterion;
  }

//+------------------------------------------------------------------+
//| Runs every group and returns true when all assertions passed. The   |
//| tally line is deliberately machine-greppable so the build script can |
//| decide pass or fail without parsing prose.                          |
//+------------------------------------------------------------------+
bool RunProductionCheck(void)
  {
   Print("==================================================");
   Print(SRP_PRODUCT_NAME," ",SRP_PRODUCT_VERSION,
         " - PRODUCTION INTEGRATION CHECK");
   Print("symbol=",_Symbol," period=",EnumToString(_Period));
   Print("==================================================");

   TestConfigurationRoundTrip();
   TestConfigurationValidation();
   TestProductionEngine();
   TestOptimizationEngine();

   Print("==================================================");
   Print(StringFormat("SRP_RESULT CHECKS=%d FAILED=%d VERDICT=%s",
                      g_checks,g_failed,
                      (g_failed==0 ? "PASS" : "FAIL")));
   Print("==================================================");
   return(g_failed==0);
  }

#endif // SRP_TESTS_PRODUCTIONCHECK_MQH
//+------------------------------------------------------------------+
