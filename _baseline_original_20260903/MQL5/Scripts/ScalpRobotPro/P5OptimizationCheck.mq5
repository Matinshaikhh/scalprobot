//+------------------------------------------------------------------+
//|                                      P5OptimizationCheck.mq5 |
//|   Production phase harness: optimisation criterion, parameter set    |
//|   validator, walk-forward analyzer, Monte Carlo simulator and the    |
//|   tester integration boundary.                                      |
//|                                                                  |
//|   The criterion is checked by CONSTRUCTING PASSES THAT SHOULD LOSE    |
//|   to a more modest one, which is the whole reason a custom criterion  |
//|   exists.                                                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Configuration/CConfigurationBuilder.mqh>
#include <ScalpRobotPro/Logger/CLogger.mqh>
#include <ScalpRobotPro/Logger/CTerminalLogSink.mqh>
#include <ScalpRobotPro/Optimization/CMonteCarloSimulator.mqh>
#include <ScalpRobotPro/Optimization/COptimizationCriterion.mqh>
#include <ScalpRobotPro/Optimization/CParameterSetValidator.mqh>
#include <ScalpRobotPro/Optimization/CTesterIntegration.mqh>
#include <ScalpRobotPro/Optimization/CWalkForwardAnalyzer.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   CLogger *logger=new CLogger(SRP_LOG_INFO);
   logger.AddSink(new CTerminalLogSink(SRP_LOG_INFO));
   logger.Open();

   //=== OPTIMISATION CRITERION =======================================
   COptimizationCriterion *criterion=new COptimizationCriterion(logger);
   criterion.SetMinimumTrades(30);
   criterion.SetPenaltyWeights(1.0,1.0,1.0);
   criterion.SetCriterion(SRP_CRITERION_CUSTOM_COMPOSITE);

   STradeRecord no_records[];

   //--- A: the curve-fitted winner. Big profit, but a brutal drawdown and
   //--- one trade carrying almost all of it. This is what optimising on
   //--- net profit picks, and what destroys live accounts.
   SPerformanceMetrics fitted;
   fitted.total_trades=35;
   fitted.winning_trades=12;
   fitted.losing_trades=23;
   fitted.gross_profit=12000.0;
   fitted.gross_loss=7000.0;
   fitted.net_profit=5000.0;
   fitted.profit_factor=1.71;
   fitted.largest_win=4200.0;            // 84% of net from ONE trade
   fitted.max_drawdown_money=4000.0;
   fitted.max_drawdown_percent=40.0;
   fitted.max_consecutive_losses=9;
   fitted.recovery_factor=1.25;

   //--- B: the modest, stable set. Half the profit, shallow drawdown, no
   //--- single dominant trade, short losing streaks.
   SPerformanceMetrics stable;
   stable.total_trades=140;
   stable.winning_trades=79;
   stable.losing_trades=61;
   stable.gross_profit=7400.0;
   stable.gross_loss=4900.0;
   stable.net_profit=2500.0;
   stable.profit_factor=1.51;
   stable.largest_win=400.0;             // 16% of net
   stable.max_drawdown_money=700.0;
   stable.max_drawdown_percent=7.0;
   stable.max_consecutive_losses=5;
   stable.recovery_factor=3.57;

   //--- C: too few trades. Must be rejected outright.
   SPerformanceMetrics thin;
   thin.total_trades=6;
   thin.winning_trades=5;
   thin.losing_trades=1;
   thin.gross_profit=3000.0;
   thin.gross_loss=100.0;
   thin.net_profit=2900.0;
   thin.profit_factor=30.0;
   thin.largest_win=1500.0;
   thin.max_drawdown_money=100.0;
   thin.max_drawdown_percent=1.0;
   thin.max_consecutive_losses=1;

   const double fit_fitted=criterion.Evaluate(fitted,no_records,fitted.total_trades);
   const double fit_stable=criterion.Evaluate(stable,no_records,stable.total_trades);
   const double fit_thin=criterion.Evaluate(thin,no_records,thin.total_trades);

   Print("=== COMPOSITE CRITERION ===");
   Print("curve-fitted (net 5000, 40% DD, 84% from one trade): fitness=",
         DoubleToString(fit_fitted,4));
   Print("stable       (net 2500,  7% DD, 16% from one trade): fitness=",
         DoubleToString(fit_stable,4));
   Print("thin sample  (6 trades):                            fitness=",
         DoubleToString(fit_thin,1));
   //--- THE ASSERTION THIS CLASS EXISTS FOR.
   Print("stable outranks the curve-fitted set = ",(fit_stable>fit_fitted),
         "  <- the entire point of a custom criterion");
   Print("thin sample rejected = ",
         (fit_thin<=criterion.RejectionValue()));
   Print(criterion.Explain(fitted));
   Print(criterion.Explain(stable));
   Print(criterion.Explain(thin));

   //--- Net profit alone would pick the wrong one; proving that makes the
   //--- composite's value measurable rather than asserted.
   criterion.SetCriterion(SRP_CRITERION_NET_PROFIT);
   const double np_fitted=criterion.Evaluate(fitted,no_records,fitted.total_trades);
   const double np_stable=criterion.Evaluate(stable,no_records,stable.total_trades);
   Print("on NET_PROFIT the curve-fitted set wins = ",(np_fitted>np_stable),
         " (",DoubleToString(np_fitted,0)," vs ",DoubleToString(np_stable,0),")");

   //--- Every criterion must return a number.
   ENUM_SRP_OPTIMIZATION_CRITERION all[]=
     {
      SRP_CRITERION_NET_PROFIT,SRP_CRITERION_PROFIT_FACTOR,
      SRP_CRITERION_EXPECTANCY,SRP_CRITERION_SHARPE_RATIO,
      SRP_CRITERION_RECOVERY_FACTOR,SRP_CRITERION_CUSTOM_COMPOSITE
     };
   for(int i=0;i<ArraySize(all);i++)
     {
      criterion.SetCriterion(all[i]);
      Print("  ",COptimizationCriterion::CriterionToString(all[i]),
            " -> ",DoubleToString(criterion.Evaluate(stable,no_records,
                                                     stable.total_trades),4));
     }
   criterion.SetCriterion(SRP_CRITERION_CUSTOM_COMPOSITE);

   //=== PARAMETER SET VALIDATOR ======================================
   Print("=== PARAMETER SET VALIDATOR ===");
   CParameterSetValidator *params=new CParameterSetValidator(logger);

   SInputSnapshot good_set;
   CConfigurationBuilder::ApplyNasdaqDefaults(good_set);
   CInputConfiguration *good_config=new CInputConfiguration(logger);
   CConfigurationBuilder::Populate(good_config,good_set);
   SValidationResult good_outcome;
   Print("defaults worth testing=",
         params.IsWorthTesting(good_config,good_outcome),
         " warnings=",good_outcome.warning_count);

   //--- Fast MA above slow: the single most common wasted pass.
   SInputSnapshot inverted;
   CConfigurationBuilder::ApplyNasdaqDefaults(inverted);
   inverted.fast_ma_period=50;
   inverted.slow_ma_period=20;
   CInputConfiguration *inverted_config=new CInputConfiguration(logger);
   CConfigurationBuilder::Populate(inverted_config,inverted);
   SValidationResult inverted_outcome;
   Print("inverted MA skipped=",
         !params.IsWorthTesting(inverted_config,inverted_outcome),
         " -> ",inverted_outcome.first_error);

   //--- Target inside the spread: guaranteed loss for the wrong reason.
   SInputSnapshot unreachable;
   CConfigurationBuilder::ApplyNasdaqDefaults(unreachable);
   unreachable.tp_mode=SRP_TP_FIXED_POINTS;
   unreachable.tp_fixed_points=30.0;
   unreachable.max_spread_points=60.0;
   CInputConfiguration *unreachable_config=new CInputConfiguration(logger);
   CConfigurationBuilder::Populate(unreachable_config,unreachable);
   SValidationResult unreachable_outcome;
   Print("unreachable TP skipped=",
         !params.IsWorthTesting(unreachable_config,unreachable_outcome),
         " -> ",unreachable_outcome.first_error);

   //--- One loss ending each day.
   SInputSnapshot suicidal;
   CConfigurationBuilder::ApplyNasdaqDefaults(suicidal);
   suicidal.risk_percent=3.0;
   suicidal.daily_loss_percent=3.0;
   CInputConfiguration *suicidal_config=new CInputConfiguration(logger);
   CConfigurationBuilder::Populate(suicidal_config,suicidal);
   SValidationResult suicidal_outcome;
   Print("risk >= daily limit skipped=",
         !params.IsWorthTesting(suicidal_config,suicidal_outcome),
         " -> ",suicidal_outcome.first_error);

   Print("validator tally: accepted=",params.AcceptedCount(),
         " rejected=",params.RejectedCount());

   //=== WALK-FORWARD ANALYSIS ========================================
   Print("=== WALK-FORWARD ANALYSIS ===");
   CWalkForwardAnalyzer *wf=new CWalkForwardAnalyzer(logger);
   wf.SetMinimumEfficiency(0.5);
   wf.SetMinimumConsistency(0.6);
   wf.SetMinimumOosTrades(10);

   //--- One year, 90-day in-sample, 30-day out-of-sample.
   const datetime year_start=D'2025.01.01 00:00';
   const datetime year_end=D'2025.12.31 23:59';
   const int planned=wf.PlanWindows(year_start,year_end,90,30,false);
   Print("planned windows=",planned);

   //--- A ROBUST result: out-of-sample retains most of the in-sample edge.
   const double is_scores[]={2.10,1.95,2.40,2.05,1.88,2.22,2.00};
   const double oos_scores[]={1.70,1.55,1.90,1.62,1.40,1.80,1.65};
   for(int i=0;i<planned && i<ArraySize(is_scores);i++)
      wf.SetWindowResults(i,is_scores[i],oos_scores[i],
                          1800.0+i*40.0,1150.0+i*30.0,
                          70,24,8.0,9.5);
   Print(wf.FormatReport());

   SWalkForwardReport robust;
   Print("robust passes=",wf.Analyze(robust),
         " avgWFE=",DoubleToString(robust.average_efficiency,3),
         " consistency=",DoubleToString(robust.consistency*100.0,1),"%");

   //--- A CURVE-FITTED result: brilliant in sample, nothing out of it.
   CWalkForwardAnalyzer *wf_bad=new CWalkForwardAnalyzer(logger);
   wf_bad.SetMinimumOosTrades(5);
   const int bad_planned=wf_bad.PlanWindows(year_start,year_end,90,30,false);
   for(int i=0;i<bad_planned;i++)
      wf_bad.SetWindowResults(i,3.50,0.35,             // WFE 0.10
                              4000.0,(i%3==0 ? 120.0 : -260.0),
                              80,20,6.0,26.0);
   SWalkForwardReport fitted_wf;
   Print("curve-fitted passes=",wf_bad.Analyze(fitted_wf),
         " avgWFE=",DoubleToString(fitted_wf.average_efficiency,3),
         " verdict=",fitted_wf.verdict);
   Print("  <- correctly rejected: in-sample brilliance, no out-of-sample edge");

   //--- Anchored planning and an excluded thin window.
   CWalkForwardAnalyzer *wf_anchored=new CWalkForwardAnalyzer(logger);
   wf_anchored.SetMinimumOosTrades(20);
   const int anchored=wf_anchored.PlanWindows(year_start,year_end,90,30,true);
   wf_anchored.SetWindowResults(0,2.0,1.6,1000.0,800.0,60,25,7.0,8.0);
   //--- Only 3 OOS trades: must be excluded, not averaged in.
   wf_anchored.SetWindowResults(1,2.0,0.1,1000.0,-500.0,60,3,7.0,30.0);
   SWalkForwardReport anchored_report;
   wf_anchored.Analyze(anchored_report);
   Print("anchored windows=",anchored,
         " judged=",anchored_report.windows,
         " (thin window excluded rather than averaged in)");
   Print("wf export=",wf.ExportCsv("ScalpRobotPro\\Optimization\\walk_forward.csv"));
   Print(wf.Describe());

   //=== MONTE CARLO ==================================================
   Print("=== MONTE CARLO ===");
   CMonteCarloSimulator *mc=new CMonteCarloSimulator(logger);
   mc.SetStartingBalance(10000.0);
   mc.SetRuns(2000);
   mc.SetWithReplacement(true);
   mc.SetRuinThreshold(30.0);
   mc.SetSeed(20260808);                 // reproducible

   //--- A realistic scalping distribution: many small wins, fewer larger
   //--- losses, marginally positive expectancy.
   for(int i=0;i<120;i++)
     {
      if(i%3==0)
         mc.AddResult(-85.0);
      else
         mc.AddResult(52.0);
     }
   SValidationResult mc_validation;
   Print("mc valid=",mc.Validate(mc_validation),
         " warnings=",mc_validation.warning_count);

   SMonteCarloReport mc_report;
   Print("mc run=",mc.Run(mc_report));
   Print(mc.FormatReport(mc_report));

   //--- Reproducibility: the same seed must give the same answer.
   SMonteCarloReport repeat;
   mc.SetSeed(20260808);
   mc.Run(repeat);
   Print("same seed reproduces result=",
         (MathAbs(repeat.risk_of_ruin-mc_report.risk_of_ruin)<0.0001));

   //--- Shuffle mode, the without-replacement question.
   mc.SetWithReplacement(false);
   SMonteCarloReport shuffled;
   mc.Run(shuffled);
   Print("shuffle riskOfRuin=",DoubleToString(shuffled.risk_of_ruin,2),
         "% vs bootstrap ",DoubleToString(mc_report.risk_of_ruin,2),"%");

   //--- A losing distribution must show a high risk of ruin.
   CMonteCarloSimulator *doomed=new CMonteCarloSimulator(logger);
   doomed.SetStartingBalance(10000.0);
   doomed.SetRuns(1000);
   doomed.SetSeed(7);
   doomed.SetRuinThreshold(30.0);
   for(int i=0;i<100;i++)
      doomed.AddResult(i%2==0 ? 40.0 : -120.0);
   SMonteCarloReport doom_report;
   doomed.Run(doom_report);
   Print("losing system: P(profit)=",
         DoubleToString(doom_report.probability_of_profit,2),
         "% riskOfRuin=",DoubleToString(doom_report.risk_of_ruin,2),"%");
   Print("  <- high risk of ruin correctly detected=",
         (doom_report.risk_of_ruin>50.0));

   Print("mc export=",
         mc.ExportCsv("ScalpRobotPro\\Optimization\\monte_carlo.csv"));
   Print(mc.Describe());

   //=== TESTER INTEGRATION ===========================================
   Print("=== TESTER INTEGRATION ===");
   CTesterIntegration *tester=new CTesterIntegration(criterion,logger);
   tester.SetExport(true,"ScalpRobotPro\\Optimization");
   tester.SetMonteCarlo(mc);
   tester.SetRunMonteCarlo(false);
   Print(tester.Describe());
   //--- Outside the tester these must all read false, which is exactly
   //--- how the EA decides whether to build a dashboard.
   Print("isTesting=",tester.IsTesting(),
         " isOptimizing=",tester.IsOptimizing(),
         " suppressUi=",tester.ShouldSuppressUi());

   Print("=== P5 OPTIMIZATION CHECK COMPLETE ===");

   delete tester;
   delete doomed;
   delete mc;
   delete wf_anchored;
   delete wf_bad;
   delete wf;
   delete suicidal_config;
   delete unreachable_config;
   delete inverted_config;
   delete good_config;
   delete params;
   delete criterion;
   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
