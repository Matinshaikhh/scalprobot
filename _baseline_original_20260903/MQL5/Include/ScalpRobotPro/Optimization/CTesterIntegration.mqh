//+------------------------------------------------------------------+
//|                                       CTesterIntegration.mqh |
//|                    Scalping Robot Pro - Production Phase (P5) |
//|                                                                  |
//|   RESPONSIBILITY (one only): be the Strategy Tester boundary. It reads  |
//|   the tester's own statistics, hands them to the criterion, and writes  |
//|   the per-pass CSV row.                                               |
//|                                                                  |
//|   WHY A SEPARATE CLASS: TesterStatistics() only exists during a         |
//|   tester run, and OnTester/OnTesterInit/OnTesterDeinit are entry        |
//|   points no other code should know about. Confining all of that here    |
//|   keeps every other module testable outside the tester, and keeps the   |
//|   .mq5 file free of statistics plumbing.                              |
//|                                                                  |
//|   IT READS THE TESTER'S NUMBERS RATHER THAN RECOMPUTING THEM.          |
//|   MT5 already computed the drawdown, profit factor and Sharpe for the   |
//|   pass. Recomputing from deal history would be slower and would        |
//|   silently disagree with the tester report the user is looking at.      |
//|   Where a metric the criterion needs is genuinely absent (consecutive   |
//|   loss count in money terms, largest win) it is taken from the          |
//|   equivalent tester field rather than invented.                        |
//|                                                                  |
//|   CSV EXPORT: one row per pass, appended. During optimisation each      |
//|   pass runs in its own agent process, so the file is opened, appended   |
//|   and closed per pass - holding a handle across passes would lock the   |
//|   file and lose every row after the first.                             |
//+------------------------------------------------------------------+
#ifndef SRP_OPTIMIZATION_CTESTERINTEGRATION_MQH
#define SRP_OPTIMIZATION_CTESTERINTEGRATION_MQH

#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Types/Structs.mqh"
#include "../Utilities/CMathUtils.mqh"
#include "COptimizationCriterion.mqh"
#include "CMonteCarloSimulator.mqh"

class CTesterIntegration
  {
private:
   ILogger               *m_logger;                // borrowed
   COptimizationCriterion *m_criterion;            // borrowed
   CMonteCarloSimulator  *m_monte_carlo;           // borrowed, optional

   string                 m_export_folder;
   string                 m_export_file;
   bool                   m_export_enabled;
   bool                   m_run_monte_carlo;
   double                 m_last_fitness;
   SPerformanceMetrics    m_last_metrics;

   //--- Reads TesterStatistics into our own metric struct so the
   //--- criterion never touches a platform API.
   void                   ReadTesterStatistics(SPerformanceMetrics &metrics) const;
   string                 CsvHeader(void) const;
   string                 CsvRow(const SPerformanceMetrics &metrics,
                                 const double fitness) const;

public:
                     CTesterIntegration(COptimizationCriterion *criterion,
                                        ILogger *logger);
                    ~CTesterIntegration(void) { }

   void              SetMonteCarlo(CMonteCarloSimulator *simulator)
     { m_monte_carlo=simulator; }
   void              SetExport(const bool enabled,const string folder,
                               const string file="optimization_passes.csv");
   void              SetRunMonteCarlo(const bool enabled)
     { m_run_monte_carlo=enabled; }

   //--- Called from OnTester. Returns the fitness value verbatim.
   double            Evaluate(void);
   //--- Called from OnDeinit in a single (non-optimisation) backtest to
   //--- print the readable breakdown.
   void              PublishPassReport(void);

   bool              IsTesting(void) const { return((bool)MQLInfoInteger(MQL_TESTER)); }
   bool              IsOptimizing(void) const { return((bool)MQLInfoInteger(MQL_OPTIMIZATION)); }
   bool              IsVisualMode(void) const { return((bool)MQLInfoInteger(MQL_VISUAL_MODE)); }
   //--- True when drawing should be suppressed: an optimisation pass has
   //--- no chart, and drawing there is pure waste.
   bool              ShouldSuppressUi(void) const;

   double            LastFitness(void) const { return(m_last_fitness); }
   void              GetLastMetrics(SPerformanceMetrics &out) const
     { out=m_last_metrics; }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CTesterIntegration::CTesterIntegration(COptimizationCriterion *criterion,
                                       ILogger *logger)
  : m_logger(logger),
    m_criterion(criterion),
    m_monte_carlo(NULL),
    m_export_folder("ScalpRobotPro\\Optimization"),
    m_export_file("optimization_passes.csv"),
    m_export_enabled(false),
    m_run_monte_carlo(false),
    m_last_fitness(0.0)
  {
   m_last_metrics.Reset();
  }
//+------------------------------------------------------------------+
void CTesterIntegration::SetExport(const bool enabled,const string folder,
                                   const string file)
  {
   m_export_enabled=enabled;
   if(folder!="")
      m_export_folder=folder;
   if(file!="")
      m_export_file=file;
  }
//+------------------------------------------------------------------+
bool CTesterIntegration::ShouldSuppressUi(void) const
  {
   //--- Visual mode has a chart and a watching human, so the dashboard is
   //--- wanted. A headless optimisation pass has neither.
   if(IsOptimizing())
      return(true);
   if(IsTesting() && !IsVisualMode())
      return(true);
   return(false);
  }
//+------------------------------------------------------------------+
//| Maps the tester's own statistics onto SPerformanceMetrics.          |
//|                                                                  |
//| Every value comes from TesterStatistics rather than being recomputed, |
//| so the fitness cannot disagree with the report the user reads.        |
//+------------------------------------------------------------------+
void CTesterIntegration::ReadTesterStatistics(SPerformanceMetrics &metrics) const
  {
   metrics.Reset();

   metrics.total_trades=(int)TesterStatistics(STAT_TRADES);
   metrics.winning_trades=(int)TesterStatistics(STAT_PROFIT_TRADES);
   metrics.losing_trades=(int)TesterStatistics(STAT_LOSS_TRADES);
   metrics.gross_profit=TesterStatistics(STAT_GROSS_PROFIT);
   //--- STAT_GROSS_LOSS is reported negative; the struct holds it as a
   //--- positive magnitude so every ratio downstream reads naturally.
   metrics.gross_loss=MathAbs(TesterStatistics(STAT_GROSS_LOSS));
   metrics.net_profit=TesterStatistics(STAT_PROFIT);
   metrics.profit_factor=TesterStatistics(STAT_PROFIT_FACTOR);
   metrics.expectancy=TesterStatistics(STAT_EXPECTED_PAYOFF);
   metrics.largest_win=TesterStatistics(STAT_MAX_PROFITTRADE);
   metrics.largest_loss=TesterStatistics(STAT_MAX_LOSSTRADE);
   metrics.average_win=CMathUtils::SafeDivide(metrics.gross_profit,
                                              (double)metrics.winning_trades,0.0);
   metrics.average_loss=CMathUtils::SafeDivide(metrics.gross_loss,
                                               (double)metrics.losing_trades,0.0);
   metrics.payoff_ratio=CMathUtils::SafeDivide(metrics.average_win,
                                               metrics.average_loss,0.0);
   metrics.win_rate=CMathUtils::SafeDivide((double)metrics.winning_trades*100.0,
                                           (double)metrics.total_trades,0.0);

   //--- STREAK COUNTS, AND THE FIELD NAMES THAT INVITE THE WRONG ONE.
   //--- STAT_MAX_CONWINS / STAT_MAX_CONLOSSES are the MONEY of the longest
   //--- streaks, not their length. The counts are
   //--- STAT_MAX_CONPROFIT_TRADES / STAT_MAX_CONLOSS_TRADES.
   //--- Using the money fields exported nonsense - a 56-trade pass
   //--- reported 360 consecutive wins and -221 consecutive losses - and
   //--- fed those figures straight into the criterion's streak penalty,
   //--- so passes were ranked partly on a number that meant currency.
   metrics.max_consecutive_wins=
      (int)TesterStatistics(STAT_MAX_CONPROFIT_TRADES);
   metrics.max_consecutive_losses=
      (int)TesterStatistics(STAT_MAX_CONLOSS_TRADES);
   //--- The money of those streaks is still worth carrying: the largest
   //--- losing run in currency is what a user actually feels.
   metrics.max_consecutive_loss_money=
      MathAbs(TesterStatistics(STAT_CONLOSSMAX));

   //--- Equity drawdown, not balance drawdown: equity is what a margin
   //--- call is computed against.
   metrics.max_drawdown_money=TesterStatistics(STAT_EQUITY_DD);
   metrics.max_drawdown_percent=TesterStatistics(STAT_EQUITYDD_PERCENT);
   metrics.recovery_factor=TesterStatistics(STAT_RECOVERY_FACTOR);
   metrics.sharpe_ratio=TesterStatistics(STAT_SHARPE_RATIO);
   //--- The tester reports no Sortino. Leaving it at zero is honest;
   //--- deriving a fake one from Sharpe would be worse than absent.

   //--- Profit factor of exactly 0 with a profit means no losing trade
   //--- occurred, which the tester reports as 0 rather than infinity.
   //--- The criterion already treats 0 as "unavailable", so it is left.
  }
//+------------------------------------------------------------------+
double CTesterIntegration::Evaluate(void)
  {
   if(m_criterion==NULL)
      return(0.0);

   ReadTesterStatistics(m_last_metrics);

   STradeRecord empty[];
   m_last_fitness=m_criterion.Evaluate(m_last_metrics,empty,
                                       m_last_metrics.total_trades);

   //--- Optional Monte Carlo on the pass's own trade distribution. It is
   //--- off during optimisation by default: a thousand extra simulations
   //--- per pass would dominate the run time.
   if(m_run_monte_carlo && m_monte_carlo!=NULL && !IsOptimizing())
     {
      SMonteCarloReport mc;
      if(m_monte_carlo.Run(mc))
         Print(m_monte_carlo.FormatReport(mc));
     }

   if(m_export_enabled)
     {
      const string path=(m_export_folder=="" ? m_export_file
                                             : m_export_folder+"\\"+m_export_file);
      //--- WHERE THIS FILE ACTUALLY LANDS DURING AN OPTIMISATION.
      //--- Each tester agent runs in its own sandbox, so a 12-agent
      //--- optimisation writes twelve files:
      //---   <terminal>\Tester\Agent-127.0.0.1-300N\MQL5\Files\<path>
      //--- and only a single-threaded backtest writes to the terminal's
      //--- own MQL5\Files. That is a platform constraint, not a bug: an
      //--- agent cannot see another agent's folder, and sharing one handle
      //--- across processes would lose rows to write contention.
      //--- Collect the parts by concatenating the per-agent files; the
      //--- header is identical in each, and a measured 1,176-pass run
      //--- produced exactly 1,176 data rows across the set.
      //---
      //--- FILE_READ alongside FILE_WRITE is what allows seeking to the
      //--- end; without it the file is truncated on every open.
      const bool existed=FileIsExist(path);
      const int handle=FileOpen(path,FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|
                                FILE_SHARE_READ);
      if(handle!=INVALID_HANDLE)
        {
         FileSeek(handle,0,SEEK_END);
         if(!existed)
            FileWrite(handle,CsvHeader());
         FileWrite(handle,CsvRow(m_last_metrics,m_last_fitness));
         FileFlush(handle);
         FileClose(handle);
        }
      else
         if(m_logger!=NULL)
            m_logger.Error("Tester","could not open the pass export: "+path);
     }

   return(m_last_fitness);
  }
//+------------------------------------------------------------------+
void CTesterIntegration::PublishPassReport(void)
  {
   if(m_criterion==NULL)
      return;
   if(m_last_metrics.total_trades<=0)
      ReadTesterStatistics(m_last_metrics);
   //--- Print, not the logger: the tester journal is where a user looks
   //--- for a pass summary, and it must appear even with logging muted.
   Print("=== ",SRP_PRODUCT_NAME," pass report ===");
   Print(m_criterion.Explain(m_last_metrics));
  }
//+------------------------------------------------------------------+
string CTesterIntegration::CsvHeader(void) const
  {
   return("timestamp,symbol,timeframe,fitness,trades,wins,losses,win_rate,"
          "net_profit,gross_profit,gross_loss,profit_factor,expectancy,"
          "payoff_ratio,largest_win,largest_loss,max_dd_money,max_dd_percent,"
          "recovery_factor,sharpe,max_con_wins,max_con_losses,"
          "max_con_loss_money");
  }
//+------------------------------------------------------------------+
string CTesterIntegration::CsvRow(const SPerformanceMetrics &metrics,
                                  const double fitness) const
  {
   string row=TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS);
   row+=","+_Symbol;
   row+=","+EnumToString(_Period);
   row+=","+DoubleToString(fitness,6);
   row+=","+IntegerToString(metrics.total_trades);
   row+=","+IntegerToString(metrics.winning_trades);
   row+=","+IntegerToString(metrics.losing_trades);
   row+=","+DoubleToString(metrics.win_rate,2);
   row+=","+DoubleToString(metrics.net_profit,2);
   row+=","+DoubleToString(metrics.gross_profit,2);
   row+=","+DoubleToString(metrics.gross_loss,2);
   row+=","+DoubleToString(metrics.profit_factor,4);
   row+=","+DoubleToString(metrics.expectancy,4);
   row+=","+DoubleToString(metrics.payoff_ratio,4);
   row+=","+DoubleToString(metrics.largest_win,2);
   row+=","+DoubleToString(metrics.largest_loss,2);
   row+=","+DoubleToString(metrics.max_drawdown_money,2);
   row+=","+DoubleToString(metrics.max_drawdown_percent,2);
   row+=","+DoubleToString(metrics.recovery_factor,4);
   row+=","+DoubleToString(metrics.sharpe_ratio,4);
   row+=","+IntegerToString(metrics.max_consecutive_wins);
   row+=","+IntegerToString(metrics.max_consecutive_losses);
   row+=","+DoubleToString(metrics.max_consecutive_loss_money,2);
   return(row);
  }
//+------------------------------------------------------------------+
string CTesterIntegration::Describe(void) const
  {
   string text="CTesterIntegration";
   text+=" testing="+(IsTesting() ? "yes" : "no");
   text+=" optimizing="+(IsOptimizing() ? "yes" : "no");
   text+=" visual="+(IsVisualMode() ? "yes" : "no");
   text+=" suppressUi="+(ShouldSuppressUi() ? "yes" : "no");
   text+=" export="+(m_export_enabled ? m_export_folder+"\\"+m_export_file
                                      : "off");
   text+=" lastFitness="+DoubleToString(m_last_fitness,6);
   return(text);
  }

#endif // SRP_OPTIMIZATION_CTESTERINTEGRATION_MQH
//+------------------------------------------------------------------+
