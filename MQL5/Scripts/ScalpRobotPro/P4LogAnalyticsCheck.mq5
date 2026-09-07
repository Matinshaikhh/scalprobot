//+------------------------------------------------------------------+
//|                                     P4LogAnalyticsCheck.mq5 |
//|   Phase 4 harness: enterprise logging + performance analytics.      |
//|                                                                  |
//|   Exercises all six channels, all three export formats, and every    |
//|   analytic on a synthetic trade series with a KNOWN answer, so the   |
//|   output can be checked by eye rather than merely compiling.         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Interface/Analytics/CPerformanceAnalytics.mqh>
#include <ScalpRobotPro/Interface/Logging/CEnterpriseLogger.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   const string sym=_Symbol;

   //=== ENTERPRISE LOGGER ============================================
   CEnterpriseLogger *log=new CEnterpriseLogger(sym,"",SRP_LOG_DEBUG);
   log.SetFolder("ScalpRobotPro\\Logs\\P4Check");
   log.SetFlushEvery(1);
   log.SetDailyRotation(true);
   log.SetMirrorErrorsToJournal(true);

   SValidationResult validation;
   log.Validate(validation);
   Print("logger valid=",validation.is_valid,
         " errors=",validation.error_count,
         " warnings=",validation.warning_count);
   if(validation.report!="")
      Print(validation.report);

   const bool opened=log.Open();
   Print("logger opened=",opened);

   //--- All six channels through the typed API.
   log.LogError("Harness","synthetic error for the audit trail",4756);
   log.LogRetcode("Harness","OrderSend",10004);
   log.LogTrade("Harness","manual trade row",12345,1.10250,0.10,4.75);
   log.LogIndicator("ATR(14)",0.00123,0.00119,0.00100,"expansion");
   log.LogRiskEvent("DailyLossGuard","daily loss at 60% of limit",
                    60.0,100.0,40.0);
   log.LogPerformance("Session",10250.00,1.85,3.20,"midday snapshot");
   log.LogExecutionTime("OrderSend",87.5,1,2.0,12345);
   log.LogExecutionTime("OrderSend",41.0,0,0.5,12346);
   log.LogExecutionTime("PositionModify",212.75,2,0.0,12345);

   //--- ILogger surface: proves Phase 1-3 modules route here unchanged.
   log.Info("LegacyModule","routed through the ILogger surface");
   log.Warn("LegacyModule","warning goes to the ERRORS channel");
   log.Error("LegacyModule","error goes to the ERRORS channel");
   log.Trace("LegacyModule","trace below threshold, expect a drop");

   //--- Structured intent and position rows.
   SManagedPosition position;
   position.ticket        = 12345;
   position.symbol        = sym;
   position.magic         = 990011;
   position.is_buy        = true;
   position.volume        = 0.10;
   position.initial_volume= 0.10;
   position.open_price    = 1.10250;
   position.current_price = 1.10310;
   position.stop_loss     = 1.10150;
   position.take_profit   = 1.10450;
   position.open_time     = TimeCurrent()-600;
   position.age_seconds   = 600;
   log.LogTradeOpened(position,"TrendContinuation");

   STradeIntent intent;
   intent.action  = SRP_TM_MOVE_STOP;
   intent.trigger = SRP_TM_TRIGGER_BREAK_EVEN;
   intent.ticket  = 12345;
   intent.new_stop= 1.10260;
   intent.reason  = "break-even reached at 60 points";
   intent.urgency = 0.4;
   log.LogTradeIntent(intent);

   //--- Per-channel format switching, all three formats.
   log.SetChannelFormat(SRP_LOG4_INDICATORS,SRP_LOG4_FORMAT_TXT);
   log.LogIndicator("RSI(14)",71.4,68.2,70.0,"overbought, TXT format");
   log.SetChannelFormat(SRP_LOG4_INDICATORS,SRP_LOG4_FORMAT_JOURNAL);
   log.LogIndicator("RSI(14)",72.1,71.4,70.0,"overbought, JOURNAL format");
   log.SetChannelFormat(SRP_LOG4_INDICATORS,SRP_LOG4_FORMAT_CSV);

   //--- Muting must drop, not fail.
   log.SetChannelEnabled(SRP_LOG4_INDICATORS,false);
   log.LogIndicator("MACD",0.0,0.0,0.0,"dropped: channel muted");
   Print("indicators enabled=",log.IsChannelEnabled(SRP_LOG4_INDICATORS));
   log.SetChannelEnabled(SRP_LOG4_INDICATORS,true);

   //--- History ring, newest first.
   SLogRecord newest;
   if(log.HistoryAt(0,newest))
      Print("newest history record: channel=",
            CEnterpriseLogger::ChannelToString(newest.channel),
            " ctx=",newest.context," msg=",newest.message);
   Print("history=",log.HistoryCount(),
         " total=",log.TotalRecords(),
         " dropped=",log.DroppedRecords(),
         " failed=",log.FailedWrites());
   Print("exec avg=",DoubleToString(log.AverageExecutionMs(),2),
         "ms worst=",DoubleToString(log.WorstExecutionMs(),2),
         "ms samples=",log.ExecutionSamples());
   Print("trades channel path=",log.ChannelPath(SRP_LOG4_TRADES));

   //--- All three export formats.
   const string dir="ScalpRobotPro\\Logs\\P4Check\\";
   Print("export CSV     =",log.ExportHistory(dir+"export_all.csv",
                                              SRP_LOG4_FORMAT_CSV));
   Print("export TXT     =",log.ExportHistory(dir+"export_all.txt",
                                              SRP_LOG4_FORMAT_TXT));
   Print("export JOURNAL =",log.ExportHistory("",SRP_LOG4_FORMAT_JOURNAL));
   Print("export channel =",log.ExportChannel(SRP_LOG4_TRADES,
                                              dir+"export_trades.csv",
                                              SRP_LOG4_FORMAT_CSV));
   Print(log.Describe());

   //=== PERFORMANCE ANALYTICS ========================================
   //--- Synthetic series with a hand-computable answer:
   //---   wins   : +100, +200, +150, +50   -> gross profit 500
   //---   losses : -50, -100, -25          -> gross loss   175
   //---   PF = 500/175 = 2.857, win rate = 4/7 = 57.14%
   //---   balance path from 10000:
   //---     10100, 10050, 10250, 9950(?)...  drawdown checked below.
   CPerformanceAnalytics *pa=new CPerformanceAnalytics(sym,10000.0,log);
   pa.SetMinimumSample(5);

   const double series[]={100.0,-50.0,200.0,-100.0,150.0,-25.0,50.0};
   datetime when=TimeCurrent()-(datetime)(7*3600);
   for(int i=0;i<ArraySize(series);i++)
     {
      SClosedTrade trade;
      trade.ticket        = (ulong)(20000+i);
      trade.symbol        = sym;
      trade.is_buy        = (i%2==0);
      trade.volume        = 0.10;
      trade.open_price    = 1.10000;
      trade.close_price   = 1.10000+series[i]/100000.0;
      trade.open_time     = when;
      trade.close_time    = when+(datetime)(300+i*60);
      trade.gross_profit  = series[i];
      trade.commission    = -0.70;
      trade.swap          = 0.0;
      //--- net left at zero on purpose: AddTrade must derive it.
      trade.risk_amount   = 50.0;
      trade.strategy_name = "Harness";
      trade.exit_reason   = (series[i]>0.0 ? "take_profit" : "stop_loss");
      pa.AddTrade(trade);
      when=trade.close_time+(datetime)600;
     }

   SValidationResult pav;
   pa.Validate(pav);
   Print("analytics valid=",pav.is_valid," warnings=",pav.warning_count);
   Print(pa.Describe());

   SAnalyticsReport all;
   const bool got=pa.AllTime(all);
   Print("allTime valid=",got);
   Print(pa.FormatReport(all));

   //--- Every single-metric accessor.
   Print("PF=",DoubleToString(pa.ProfitFactor(),4),
         " sharpe=",DoubleToString(pa.SharpeRatio(),4),
         " sortino=",DoubleToString(pa.SortinoRatio(),4),
         " recovery=",DoubleToString(pa.RecoveryFactor(),4));
   Print("maxDD=",DoubleToString(pa.MaxDrawdownMoney(),2),
         " (",DoubleToString(pa.MaxDrawdownPercent(),3),"%)",
         " avgWin=",DoubleToString(pa.AverageWin(),2),
         " avgLoss=",DoubleToString(pa.AverageLoss(),2));
   Print("winRate=",DoubleToString(pa.WinRate(),2),
         " expectancy=",DoubleToString(pa.Expectancy(),2),
         " avgRR=",DoubleToString(pa.AverageRr(),3),
         " net=",DoubleToString(pa.NetProfit(),2));
   Print("avgDuration=",CPerformanceAnalytics::DurationToString(
            (int)pa.AverageDurationSeconds()));

   //--- Period windows.
   Print("today=",DoubleToString(pa.PeriodProfit(SRP_PA_PERIOD_DAY),2),
         " week=",DoubleToString(pa.PeriodProfit(SRP_PA_PERIOD_WEEK),2),
         " month=",DoubleToString(pa.PeriodProfit(SRP_PA_PERIOD_MONTH),2),
         " year=",DoubleToString(pa.PeriodProfit(SRP_PA_PERIOD_YEAR),2));

   SAnalyticsReport day;
   if(pa.ForPeriod(SRP_PA_PERIOD_DAY,day))
      Print("day trades=",day.total_trades," net=",
            DoubleToString(day.net_profit,2));

   SAnalyticsReport ranged;
   if(pa.ForRange(0,TimeCurrent(),ranged))
      Print("ranged trades=",ranged.total_trades);

   //--- Calendar reports.
   MqlDateTime now_parts;
   TimeToStruct(TimeCurrent(),now_parts);
   SAnalyticsReport month,year;
   Print("monthly(",now_parts.year,",",now_parts.mon,") valid=",
         pa.MonthlyReport(now_parts.year,now_parts.mon,month),
         " trades=",month.total_trades);
   Print("yearly(",now_parts.year,") valid=",
         pa.YearlyReport(now_parts.year,year),
         " trades=",year.total_trades);
   //--- Out-of-range month must be refused, not computed.
   Print("monthly(bad month) valid=",pa.MonthlyReport(2026,13,month));

   Print(pa.FormatMonthlyTable());
   Print(pa.FormatYearlyTable());

   SAnalyticsReport months[],years[];
   Print("monthly buckets=",pa.MonthlyBreakdown(months),
         " yearly buckets=",pa.YearlyBreakdown(years));

   //--- R-multiple basis must change Sharpe, not the money totals.
   pa.SetUseRMultiples(true);
   Print("sharpe on R=",DoubleToString(pa.SharpeRatio(),4),
         " net unchanged=",DoubleToString(pa.NetProfit(),2));
   pa.SetUseRMultiples(false);

   //--- Small-sample guard: below the minimum, ratios must read zero.
   CPerformanceAnalytics *tiny=new CPerformanceAnalytics(sym,1000.0,log);
   tiny.SetMinimumSample(10);
   SClosedTrade one;
   one.ticket=1; one.symbol=sym; one.gross_profit=25.0;
   one.open_time=TimeCurrent()-120; one.close_time=TimeCurrent();
   one.risk_amount=10.0;
   tiny.AddTrade(one);
   Print("tiny sample: trades=",tiny.TradeCount(),
         " sharpe=",DoubleToString(tiny.SharpeRatio(),4),
         " (expected 0 below minimum sample)",
         " PF=",DoubleToString(tiny.ProfitFactor(),4),
         " (expected 0, no losses)");
   //--- Empty analytics must not divide by zero.
   tiny.Reset();
   SAnalyticsReport empty;
   Print("empty valid=",tiny.AllTime(empty),
         " PF=",DoubleToString(tiny.ProfitFactor(),2),
         " sharpe=",DoubleToString(tiny.SharpeRatio(),2));
   Print(tiny.FormatMonthlyTable());
   Print("empty export refused=",!tiny.ExportTradesCsv(dir+"empty.csv"));

   //--- Exports.
   Print("trades CSV =",pa.ExportTradesCsv(dir+"analytics_trades.csv"));
   Print("monthly CSV=",pa.ExportMonthlyCsv(dir+"analytics_monthly.csv"));

   //--- Reported through the logger, closing the loop between the two.
   log.LogAnalyticsReport(all);

   //--- Retention: index 0 is the oldest retained trade.
   SClosedTrade first;
   if(pa.TradeAt(0,first))
      Print("oldest retained: #",first.ticket,
            " net=",DoubleToString(first.net_profit,2),
            " balanceAfter=",DoubleToString(first.balance_after,2),
            " R=",DoubleToString(first.r_multiple,3));

   Print("=== P4 LOG + ANALYTICS CHECK COMPLETE ===");

   delete tiny;
   delete pa;
   log.Close();
   delete log;
  }
//+------------------------------------------------------------------+
