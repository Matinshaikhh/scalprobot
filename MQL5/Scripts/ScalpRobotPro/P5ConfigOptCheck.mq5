//+------------------------------------------------------------------+
//|                                        P5ConfigOptCheck.mq5 |
//|   Phase 5 harness: configuration system + optimisation engine.      |
//|                                                                  |
//|   Exercises the full config round trip (snapshot -> builder -> keyed  |
//|   store -> validator) and every optimisation component on data with   |
//|   a known answer, including the rejection paths that matter most.     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Configuration/CConfigurationBuilder.mqh>
#include <ScalpRobotPro/Configuration/CConfigValidator.mqh>
#include <ScalpRobotPro/Optimization/CMonteCarloSimulator.mqh>
#include <ScalpRobotPro/Optimization/COptimizationCriterion.mqh>
#include <ScalpRobotPro/Optimization/COptimizationGuard.mqh>
#include <ScalpRobotPro/Optimization/CParameterSetValidator.mqh>
#include <ScalpRobotPro/Optimization/CTesterIntegration.mqh>
#include <ScalpRobotPro/Optimization/CWalkForwardAnalyzer.mqh>
#include <ScalpRobotPro/Core/CServerClock.mqh>
#include <ScalpRobotPro/Logger/CLogger.mqh>
#include <ScalpRobotPro/Logger/CTerminalLogSink.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   CLogger *logger=new CLogger(SRP_LOG_INFO);
   logger.AddSink(new CTerminalLogSink(SRP_LOG_INFO));
   logger.Open();

   //=== ENVIRONMENT POLICY ===========================================
   CServerClock *clock=new CServerClock();
   COptimizationGuard *guard=new COptimizationGuard(clock);
   Print("env: live=",guard.IsLive()," tester=",guard.IsTester(),
         " opt=",guard.IsOptimization()," visual=",guard.IsVisualTest());
   Print("policy: dashboard=",guard.ShouldEnableDashboard(),
         " fileLog=",guard.ShouldEnableFileLogging(),
         " journal=",guard.ShouldEnableJournal(),
         " notify=",guard.ShouldEnableNotifications(),
         " state=",guard.ShouldEnableStatePersistence(),
         " news=",guard.ShouldEnableNewsProvider());
   Print("logLevel(DEBUG) -> ",
         EnumToString(guard.RecommendedLogLevel(SRP_LOG_DEBUG)));
   Print(guard.DescribeEnvironment());

   //=== CONFIGURATION ROUND TRIP =====================================
   //--- NASDAQ defaults are the shipped preset; the snapshot is what the
   //--- .mq5 input block copies in.
   SInputSnapshot snapshot;
   CConfigurationBuilder::ApplyNasdaqDefaults(snapshot);
   Print("nasdaq defaults: risk%=",DoubleToString(snapshot.risk_percent,2),
         " maxSpread=",DoubleToString(snapshot.max_spread_points,0),
         " slPoints=",DoubleToString(snapshot.sl_fixed_points,0),
         " tpPoints=",DoubleToString(snapshot.tp_fixed_points,0),
         " fastMA=",snapshot.fast_ma_period,
         " slowMA=",snapshot.slow_ma_period);

   CInputConfiguration *config=new CInputConfiguration(logger);
   Print("populate=",CConfigurationBuilder::Populate(config,snapshot));
   Print("keys stored=",config.Count());
   config.Seal();
   Print("sealed=",config.IsSealed());
   //--- A write after sealing must be refused, not silently accepted.
   Print("write after seal refused=",
         !config.SetDouble(CConfigKeys::RISK_PERCENT,99.0));

   //--- Spot-check that keys survived the round trip with their values.
   Print("readback: risk.percent=",
         DoubleToString(config.GetDouble(CConfigKeys::RISK_PERCENT,-1.0),2),
         " magic=",config.GetLong(CConfigKeys::GENERAL_MAGIC,-1),
         " dashboard=",config.GetBool(CConfigKeys::DASHBOARD_ENABLED,false),
         " smc=",config.GetBool(CConfigKeys::SMC_ENABLED,false));
   //--- An absent key must yield the fallback and be counted.
   Print("absent key fallback=",
         config.GetInt("does.not.exist",4242),
         " missCount=",config.MissCount());

   //=== CONFIG VALIDATION ============================================
   CConfigValidator *validator=new CConfigValidator(logger);
   SValidationResult cfg_result;
   const bool cfg_ok=validator.ValidateAll(config,cfg_result);
   Print("config valid=",cfg_ok,
         " errors=",cfg_result.error_count,
         " warnings=",cfg_result.warning_count);
   if(cfg_result.report!="")
      Print(cfg_result.report);

   //=== PARAMETER SET VALIDATOR ======================================
   CParameterSetValidator *params=new CParameterSetValidator(logger);
   SValidationResult p_ok;
   Print("shipped preset worth testing=",
         params.IsWorthTesting(config,p_ok),
         " errors=",p_ok.error_count);
   if(p_ok.report!="")
      Print(p_ok.report);

   //--- Now an incoherent set: fast MA above slow. The single most common
   //--- wasted-pass case in a naive two-MA optimisation grid.
   SInputSnapshot bad=snapshot;
   bad.fast_ma_period=50;
   bad.slow_ma_period=9;
   CInputConfiguration *bad_config=new CInputConfiguration(logger);
   CConfigurationBuilder::Populate(bad_config,bad);
   SValidationResult bad_result;
   Print("inverted MA set rejected=",
         !params.IsWorthTesting(bad_config,bad_result),
         " firstError=",bad_result.first_error);

   //--- Target inside the spread can never be reached.
   SInputSnapshot bad2=snapshot;
   bad2.tp_fixed_points=5.0;
   bad2.max_spread_points=50.0;
   CInputConfiguration *bad_config2=new CInputConfiguration(logger);
   CConfigurationBuilder::Populate(bad_config2,bad2);
   SValidationResult bad_result2;
   Print("TP-inside-spread rejected=",
         !params.IsWorthTesting(bad_config2,bad_result2),
         " firstError=",bad_result2.first_error);

   //--- Per-trade risk at or above the daily cap ends every day on one loss.
   SInputSnapshot bad3=snapshot;
   bad3.risk_percent=5.0;
   bad3.daily_loss_enabled=true;
   bad3.daily_loss_percent=3.0;
   CInputConfiguration *bad_config3=new CInputConfiguration(logger);
   CConfigurationBuilder::Populate(bad_config3,bad3);
   SValidationResult bad_result3;
   Print("risk>=dailyCap rejected=",
         !params.IsWorthTesting(bad_config3,bad_result3),
         " firstError=",bad_result3.first_error);
   Print("validator tally: accepted=",params.AcceptedCount(),
         " rejected=",params.RejectedCount());

   //=== OPTIMISATION CRITERION =======================================
   COptimizationCriterion *criterion=new COptimizationCriterion(logger);
   criterion.SetMinimumTrades(30);
   criterion.SetPenaltyWeights(1.0,1.0,1.0);

   STradeRecord no_records[];

   //--- A healthy pass.
   SPerformanceMetrics good;
   good.total_trades=180;
   good.net_profit=4200.0;
   good.gross_profit=9800.0;
   good.gross_loss=5600.0;
   good.profit_factor=1.75;
   good.expectancy=23.33;
   good.sharpe_ratio=1.42;
   good.recovery_factor=3.5;
   good.max_drawdown_money=1200.0;
   good.max_drawdown_percent=11.0;
   good.largest_win=380.0;
   good.max_consecutive_losses=6;
   const double good_fitness=criterion.Evaluate(good,no_records,
                                                good.total_trades);
   Print("healthy pass fitness=",DoubleToString(good_fitness,6));
   Print(criterion.Explain(good));

   //--- Too few trades: must be rejected outright, not ranked.
   SPerformanceMetrics thin=good;
   thin.total_trades=9;
   const double thin_fitness=criterion.Evaluate(thin,no_records,9);
   Print("thin pass fitness=",DoubleToString(thin_fitness,1),
         " rejected=",(thin_fitness<=criterion.RejectionValue()));

   //--- One trade carrying the whole profit: concentration penalty.
   SPerformanceMetrics lucky=good;
   lucky.largest_win=4000.0;      // 95% of net
   const double lucky_fitness=criterion.Evaluate(lucky,no_records,
                                                 lucky.total_trades);
   Print("concentrated pass fitness=",DoubleToString(lucky_fitness,6),
         " lower than healthy=",(lucky_fitness<good_fitness));

   //--- Deep drawdown must score below the same profit with a shallow one.
   SPerformanceMetrics deep=good;
   deep.max_drawdown_percent=65.0;
   deep.max_drawdown_money=7000.0;
   const double deep_fitness=criterion.Evaluate(deep,no_records,
                                                deep.total_trades);
   Print("deep-drawdown fitness=",DoubleToString(deep_fitness,6),
         " lower than healthy=",(deep_fitness<good_fitness));

   //--- A losing pass returns its loss so losers stay ordered.
   SPerformanceMetrics losing=good;
   losing.net_profit=-850.0;
   Print("losing pass fitness=",
         DoubleToString(criterion.Evaluate(losing,no_records,
                                           losing.total_trades),2));

   //--- Every named criterion must resolve.
   for(int c=0;c<=(int)SRP_CRITERION_CUSTOM_COMPOSITE;c++)
     {
      criterion.SetCriterion((ENUM_SRP_OPTIMIZATION_CRITERION)c);
      Print("  criterion ",
            COptimizationCriterion::CriterionToString(
               (ENUM_SRP_OPTIMIZATION_CRITERION)c),
            " fitness=",DoubleToString(criterion.Evaluate(good,no_records,
                                                          good.total_trades),4));
     }
   criterion.SetCriterion(SRP_CRITERION_CUSTOM_COMPOSITE);

   //=== MONTE CARLO ==================================================
   CMonteCarloSimulator *mc=new CMonteCarloSimulator(logger);
   mc.SetStartingBalance(10000.0);
   mc.SetRuns(500);
   mc.SetTradesPerRun(200);
   mc.SetWithReplacement(true);
   mc.SetRuinThreshold(50.0);
   mc.SetSeed(20260808);            // fixed seed: reproducible run

   SValidationResult mc_valid;
   Print("monte carlo valid=",mc.Validate(mc_valid),
         " warnings=",mc_valid.warning_count);

   //--- A positive-expectancy series: 55% win rate, 1.4:1 payoff.
   for(int i=0;i<100;i++)
      mc.AddResult((i%100)<55 ? 140.0 : -100.0);
   Print("sample size=",mc.SampleSize());

   SMonteCarloReport mc_report;
   const bool mc_ok=mc.Run(mc_report);
   Print("monte carlo ran=",mc_ok);
   Print(mc.FormatReport(mc_report));
   Print("export=",mc.ExportCsv("ScalpRobotPro\\Reports\\P5Check\\montecarlo.csv"));
   Print(mc.Describe());

   //--- A negative-expectancy series must show a materially worse risk of
   //--- ruin. If it does not, the simulation is not doing anything.
   CMonteCarloSimulator *mc_bad=new CMonteCarloSimulator(logger);
   mc_bad.SetStartingBalance(10000.0);
   mc_bad.SetRuns(500);
   mc_bad.SetTradesPerRun(200);
   mc_bad.SetSeed(20260808);
   mc_bad.SetRuinThreshold(50.0);
   for(int i=0;i<100;i++)
      mc_bad.AddResult((i%100)<45 ? 100.0 : -120.0);
   SMonteCarloReport mc_bad_report;
   mc_bad.Run(mc_bad_report);
   Print("negative-expectancy report:");
   Print(mc_bad.FormatReport(mc_bad_report));

   //=== WALK FORWARD =================================================
   CWalkForwardAnalyzer *wf=new CWalkForwardAnalyzer(logger);
   wf.SetMinimumEfficiency(0.5);
   wf.SetMinimumConsistency(0.6);
   wf.SetMinimumOosTrades(20);

   SValidationResult wf_valid;
   Print("walk forward valid=",wf.Validate(wf_valid));

   const datetime wf_from=D'2025.01.01 00:00';
   const datetime wf_to=D'2026.01.01 00:00';
   const int planned=wf.PlanWindows(wf_from,wf_to,90,30);
   Print("planned windows=",planned);

   //--- Populate each window with in-sample and out-of-sample results.
   //--- OOS deliberately weaker than IS, which is the realistic case.
   for(int i=0;i<planned;i++)
     {
      const double is_net=1000.0+i*120.0;
      //--- Out-of-sample deliberately weaker than in-sample, which is the
      //--- realistic case; efficiency near 1.0 would be the suspicious one.
      const double oos_net=is_net*(0.55+0.05*(i%3));
      wf.SetWindowResults(i,
                          is_net,            // is_score  (fitness)
                          oos_net,           // oos_score
                          is_net,            // is_net    (money)
                          oos_net,           // oos_net
                          60,                // is_trades
                          28,                // oos_trades
                          9.0,               // is_dd_percent
                          14.0);             // oos_dd_percent
     }
   SWalkForwardReport wf_report;
   Print("walk forward analyzed=",wf.Analyze(wf_report));
   Print(wf.FormatReport());
   Print("export=",wf.ExportCsv("ScalpRobotPro\\Reports\\P5Check\\walkforward.csv"));
   Print("verdict(0.85)=",CWalkForwardAnalyzer::EfficiencyVerdict(0.85),
         " verdict(0.30)=",CWalkForwardAnalyzer::EfficiencyVerdict(0.30));
   Print(wf.Describe());

   //=== TESTER INTEGRATION ===========================================
   CTesterIntegration *tester=new CTesterIntegration(criterion,logger);
   tester.SetMonteCarlo(mc);
   tester.SetRunMonteCarlo(false);   // no OnTester data outside the tester
   tester.SetExport(true,"ScalpRobotPro\\Reports\\P5Check",
                    "optimization_passes.csv");
   Print("tester: isTesting=",(string)tester.IsTesting(),
         " isOptimizing=",(string)tester.IsOptimizing(),
         " suppressUi=",(string)tester.ShouldSuppressUi());
   //--- Evaluate() reads terminal statistics; outside the tester those are
   //--- zero, so the minimum-trade gate must reject rather than produce a
   //--- meaningless number. That rejection IS the expected result here.
   const double fitness=tester.Evaluate();
   Print("OnTester fitness outside tester=",DoubleToString(fitness,1),
         " (rejection expected)");
   tester.PublishPassReport();
   Print(tester.Describe());

   Print("=== P5 CONFIG + OPTIMISATION CHECK COMPLETE ===");

   delete tester;
   delete wf;
   delete mc_bad;
   delete mc;
   delete criterion;
   delete bad_config3;
   delete bad_config2;
   delete bad_config;
   delete params;
   delete validator;
   delete config;
   delete guard;
   delete clock;
   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
