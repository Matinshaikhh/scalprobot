//+------------------------------------------------------------------+
//|                                     CMonteCarloSimulator.mqh |
//|                    Scalping Robot Pro - Production Phase (P5) |
//|                                                                  |
//|   RESPONSIBILITY (one only): reshuffle a historical trade sequence     |
//|   many times and report the distribution of outcomes.                 |
//|                                                                  |
//|   THE QUESTION IT ANSWERS                                             |
//|   A backtest shows ONE ordering of trades - the one history happened   |
//|   to produce. The same set of trades in a different order gives a      |
//|   different drawdown, and it is drawdown that ends accounts. If the    |
//|   losses had clustered slightly differently, would the account have    |
//|   survived? A single equity curve cannot answer that. This can.        |
//|                                                                  |
//|   METHOD: sample the observed trade results (with or without           |
//|   replacement), replay each shuffled sequence as an equity curve, and  |
//|   record the distribution of final equity, peak drawdown and ruin.     |
//|     * WITHOUT replacement (shuffle) asks "what if the same trades      |
//|       had arrived in a different order?"                              |
//|     * WITH replacement (bootstrap) asks "what if the future draws      |
//|       from the same distribution?" - the more honest forward-looking   |
//|       question, and the default.                                      |
//|                                                                  |
//|   RISK OF RUIN is the headline output: the percentage of simulated     |
//|   runs whose drawdown breached the configured threshold. A strategy    |
//|   with a great backtest and a 20% risk of ruin is not tradeable, and   |
//|   no equity curve on its own will tell you that.                      |
//|                                                                  |
//|   WHAT IT ASSUMES, STATED PLAINLY: trades are independent and          |
//|   identically distributed. Real trades are not - they cluster by       |
//|   regime, and a strategy that loses repeatedly in one market state     |
//|   has serial correlation this model ignores. The output is therefore   |
//|   a floor on risk, not a complete picture.                            |
//+------------------------------------------------------------------+
#ifndef SRP_OPTIMIZATION_CMONTECARLOSIMULATOR_MQH
#define SRP_OPTIMIZATION_CMONTECARLOSIMULATOR_MQH

#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Types/Structs.mqh"
#include "../Utilities/CMathUtils.mqh"

#define SRP_MC_MAX_TRADES 4096
#define SRP_MC_MAX_RUNS   10000

//+------------------------------------------------------------------+
//| The distribution produced by a simulation.                        |
//+------------------------------------------------------------------+
struct SMonteCarloReport
  {
   int               runs;
   int               trades_per_run;
   double            starting_balance;
   //--- Final equity distribution.
   double            mean_final_equity;
   double            median_final_equity;
   double            best_final_equity;
   double            worst_final_equity;
   double            equity_std_dev;
   double            percentile_5_equity;
   double            percentile_95_equity;
   //--- Drawdown distribution: the part that decides tradeability.
   double            mean_max_drawdown_percent;
   double            median_max_drawdown_percent;
   double            worst_max_drawdown_percent;
   double            percentile_95_drawdown;
   //--- Outcomes.
   int               profitable_runs;
   int               ruined_runs;
   double            probability_of_profit;
   double            risk_of_ruin;
   double            ruin_threshold_percent;
   bool              is_valid;

                     SMonteCarloReport(void) { Reset(); }
   void              Reset(void)
     {
      runs=0; trades_per_run=0; starting_balance=0.0;
      mean_final_equity=0.0; median_final_equity=0.0;
      best_final_equity=0.0; worst_final_equity=0.0; equity_std_dev=0.0;
      percentile_5_equity=0.0; percentile_95_equity=0.0;
      mean_max_drawdown_percent=0.0; median_max_drawdown_percent=0.0;
      worst_max_drawdown_percent=0.0; percentile_95_drawdown=0.0;
      profitable_runs=0; ruined_runs=0;
      probability_of_profit=0.0; risk_of_ruin=0.0;
      ruin_threshold_percent=0.0;
      is_valid=false;
     }
  };

class CMonteCarloSimulator
  {
private:
   ILogger          *m_logger;            // borrowed

   //--- The observed sample: one net result per historical trade.
   double            m_results[SRP_MC_MAX_TRADES];
   int               m_count;

   double            m_starting_balance;
   int               m_runs;
   int               m_trades_per_run;    // 0 = same as the sample size
   bool              m_with_replacement;
   double            m_ruin_threshold_percent;
   int               m_seed;

   //--- Per-run outputs, retained so percentiles can be computed.
   double            m_final_equity[SRP_MC_MAX_RUNS];
   double            m_max_drawdown[SRP_MC_MAX_RUNS];
   int               m_completed_runs;

   //--- Replays one sequence and returns its final equity, writing the
   //--- peak drawdown percent through the out parameter.
   double            SimulateOne(double &out_max_drawdown_percent);
   static void       SortAscending(double &values[],const int count);
   static double     PercentileOf(const double &sorted[],const int count,
                                  const double percentile);

public:
                     CMonteCarloSimulator(ILogger *logger);
                    ~CMonteCarloSimulator(void) { }

   //=== CONFIGURATION ================================================
   void              SetStartingBalance(const double balance);
   void              SetRuns(const int runs);
   void              SetTradesPerRun(const int trades);
   void              SetWithReplacement(const bool value);
   void              SetRuinThreshold(const double percent);
   //--- A fixed seed makes a run reproducible, which matters when a
   //--- result is being reported to someone else.
   void              SetSeed(const int seed);
   bool              Validate(SValidationResult &result) const;

   //=== SAMPLE ENTRY =================================================
   bool              AddResult(const double net_profit);
   int               LoadFromRecords(const STradeRecord &records[],
                                     const int count);
   void              Reset(void);
   int               SampleSize(void) const { return(m_count); }

   //=== SIMULATION ===================================================
   bool              Run(SMonteCarloReport &report);

   string            FormatReport(const SMonteCarloReport &report) const;
   bool              ExportCsv(const string relative_path,
                               const bool common_folder=false) const;
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CMonteCarloSimulator::CMonteCarloSimulator(ILogger *logger)
  : m_logger(logger),
    m_count(0),
    m_starting_balance(10000.0),
    m_runs(1000),
    m_trades_per_run(0),
    //--- Bootstrap by default: the forward-looking question is the one
    //--- worth asking before risking money.
    m_with_replacement(true),
    m_ruin_threshold_percent(30.0),
    m_seed(0),
    m_completed_runs(0)
  {
  }
//+------------------------------------------------------------------+
void CMonteCarloSimulator::SetStartingBalance(const double balance)
  {
   if(balance>0.0)
      m_starting_balance=balance;
  }
//+------------------------------------------------------------------+
void CMonteCarloSimulator::SetRuns(const int runs)
  {
   m_runs=CMathUtils::ClampInt(runs,1,SRP_MC_MAX_RUNS);
  }
//+------------------------------------------------------------------+
void CMonteCarloSimulator::SetTradesPerRun(const int trades)
  {
   m_trades_per_run=(trades<0 ? 0 : trades);
  }
//+------------------------------------------------------------------+
void CMonteCarloSimulator::SetWithReplacement(const bool value)
  {
   m_with_replacement=value;
  }
//+------------------------------------------------------------------+
void CMonteCarloSimulator::SetRuinThreshold(const double percent)
  {
   m_ruin_threshold_percent=CMathUtils::Clamp(percent,1.0,100.0);
  }
//+------------------------------------------------------------------+
void CMonteCarloSimulator::SetSeed(const int seed)
  {
   m_seed=seed;
  }
//+------------------------------------------------------------------+
bool CMonteCarloSimulator::Validate(SValidationResult &result) const
  {
   if(m_count<=0)
     {
      result.AddError("no trade results loaded, nothing to simulate");
      return(false);
     }
   //--- Below ~30 observations the resampled distribution mostly reflects
   //--- the few trades present rather than the strategy.
   if(m_count<30)
      result.AddWarning("fewer than 30 observed trades: the simulated "
                        "distribution largely reproduces the small sample");
   if(m_runs<200)
      result.AddWarning("fewer than 200 runs gives a coarse distribution; "
                        "1000 or more is usual");
   if(m_starting_balance<=0.0)
      result.AddError("starting balance must be positive");
   //--- Shuffling without replacement cannot produce more trades than
   //--- were observed.
   if(!m_with_replacement && m_trades_per_run>m_count)
      result.AddError("trades per run exceeds the sample size, which is "
                      "impossible without replacement");
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
bool CMonteCarloSimulator::AddResult(const double net_profit)
  {
   if(m_count>=SRP_MC_MAX_TRADES)
      return(false);
   m_results[m_count]=net_profit;
   m_count++;
   return(true);
  }
//+------------------------------------------------------------------+
int CMonteCarloSimulator::LoadFromRecords(const STradeRecord &records[],
                                          const int count)
  {
   Reset();
   const int total=(count<ArraySize(records) ? count : ArraySize(records));
   for(int i=0;i<total;i++)
      if(!AddResult(records[i].net_profit))
         break;
   return(m_count);
  }
//+------------------------------------------------------------------+
void CMonteCarloSimulator::Reset(void)
  {
   m_count=0;
   m_completed_runs=0;
  }
//+------------------------------------------------------------------+
//| One simulated account history.                                     |
//+------------------------------------------------------------------+
double CMonteCarloSimulator::SimulateOne(double &out_max_drawdown_percent)
  {
   const int length=(m_trades_per_run>0 ? m_trades_per_run : m_count);

   double equity=m_starting_balance;
   double peak=m_starting_balance;
   double worst_drawdown=0.0;

   if(m_with_replacement)
     {
      //--- BOOTSTRAP: each draw is independent, so the sequence can be
      //--- generated on the fly with no bookkeeping.
      for(int i=0;i<length;i++)
        {
         const int pick=(int)(MathRand()%(uint)m_count);
         equity+=m_results[pick];
         if(equity>peak)
            peak=equity;
         const double drawdown=CMathUtils::SafeDivide((peak-equity)*100.0,
                                                      peak,0.0);
         if(drawdown>worst_drawdown)
            worst_drawdown=drawdown;
        }
     }
   else
     {
      //--- SHUFFLE: a partial Fisher-Yates over an index array. Drawing
      //--- without replacement needs the permutation to be tracked, and
      //--- Fisher-Yates is the only unbiased way to build one.
      int order[SRP_MC_MAX_TRADES];
      for(int i=0;i<m_count;i++)
         order[i]=i;
      for(int i=m_count-1;i>0;i--)
        {
         const int j=(int)(MathRand()%(uint)(i+1));
         const int swap=order[i];
         order[i]=order[j];
         order[j]=swap;
        }
      const int take=(length<m_count ? length : m_count);
      for(int i=0;i<take;i++)
        {
         equity+=m_results[order[i]];
         if(equity>peak)
            peak=equity;
         const double drawdown=CMathUtils::SafeDivide((peak-equity)*100.0,
                                                      peak,0.0);
         if(drawdown>worst_drawdown)
            worst_drawdown=drawdown;
        }
     }

   out_max_drawdown_percent=worst_drawdown;
   return(equity);
  }
//+------------------------------------------------------------------+
bool CMonteCarloSimulator::Run(SMonteCarloReport &report)
  {
   report.Reset();
   if(m_count<=0)
      return(false);

   //--- Seeding: a fixed seed makes the result reproducible, and 0 means
   //--- "vary with the clock" for exploratory use.
   if(m_seed!=0)
      MathSrand((uint)m_seed);
   else
      MathSrand((uint)GetTickCount());

   const int length=(m_trades_per_run>0 ? m_trades_per_run : m_count);
   const double ruin_equity=
      m_starting_balance*(1.0-m_ruin_threshold_percent/100.0);

   m_completed_runs=0;
   for(int run=0;run<m_runs && run<SRP_MC_MAX_RUNS;run++)
     {
      double drawdown=0.0;
      const double final_equity=SimulateOne(drawdown);
      m_final_equity[run]=final_equity;
      m_max_drawdown[run]=drawdown;
      m_completed_runs++;

      if(final_equity>m_starting_balance)
         report.profitable_runs++;
      //--- RUIN is defined by drawdown breaching the threshold OR equity
      //--- falling below the floor. Either ends the account in practice,
      //--- since a real trader stops long before zero.
      if(drawdown>=m_ruin_threshold_percent || final_equity<=ruin_equity)
         report.ruined_runs++;
     }

   if(m_completed_runs<=0)
      return(false);

   //--- Aggregate. Sorted copies give medians and percentiles.
   double equities[],drawdowns[];
   ArrayResize(equities,m_completed_runs);
   ArrayResize(drawdowns,m_completed_runs);
   double equity_total=0.0,drawdown_total=0.0;
   for(int i=0;i<m_completed_runs;i++)
     {
      equities[i]=m_final_equity[i];
      drawdowns[i]=m_max_drawdown[i];
      equity_total+=m_final_equity[i];
      drawdown_total+=m_max_drawdown[i];
     }
   SortAscending(equities,m_completed_runs);
   SortAscending(drawdowns,m_completed_runs);

   report.runs=m_completed_runs;
   report.trades_per_run=length;
   report.starting_balance=m_starting_balance;
   report.ruin_threshold_percent=m_ruin_threshold_percent;

   report.mean_final_equity=equity_total/(double)m_completed_runs;
   report.median_final_equity=PercentileOf(equities,m_completed_runs,50.0);
   report.worst_final_equity=equities[0];
   report.best_final_equity=equities[m_completed_runs-1];
   report.percentile_5_equity=PercentileOf(equities,m_completed_runs,5.0);
   report.percentile_95_equity=PercentileOf(equities,m_completed_runs,95.0);

   double variance=0.0;
   for(int i=0;i<m_completed_runs;i++)
     {
      const double deviation=m_final_equity[i]-report.mean_final_equity;
      variance+=deviation*deviation;
     }
   report.equity_std_dev=(m_completed_runs>1
                          ? MathSqrt(variance/(double)(m_completed_runs-1))
                          : 0.0);

   report.mean_max_drawdown_percent=drawdown_total/(double)m_completed_runs;
   report.median_max_drawdown_percent=PercentileOf(drawdowns,m_completed_runs,50.0);
   report.worst_max_drawdown_percent=drawdowns[m_completed_runs-1];
   //--- The 95th percentile drawdown is the practical planning number:
   //--- the pain to expect in a bad-but-not-worst case.
   report.percentile_95_drawdown=PercentileOf(drawdowns,m_completed_runs,95.0);

   report.probability_of_profit=
      CMathUtils::SafeDivide((double)report.profitable_runs*100.0,
                             (double)m_completed_runs,0.0);
   report.risk_of_ruin=
      CMathUtils::SafeDivide((double)report.ruined_runs*100.0,
                             (double)m_completed_runs,0.0);
   report.is_valid=true;

   if(m_logger!=NULL)
      m_logger.Info("MonteCarlo",
                    "simulated "+IntegerToString(m_completed_runs)+" runs, "+
                    "P(profit)="+DoubleToString(report.probability_of_profit,1)+
                    "% riskOfRuin="+DoubleToString(report.risk_of_ruin,2)+"%");
   return(true);
  }
//+------------------------------------------------------------------+
void CMonteCarloSimulator::SortAscending(double &values[],const int count)
  {
   //--- ArraySort is the platform's own sort; reimplementing one here
   //--- would be slower and another thing to get wrong.
   if(count>1)
      ArraySort(values);
  }
//+------------------------------------------------------------------+
double CMonteCarloSimulator::PercentileOf(const double &sorted[],
                                          const int count,
                                          const double percentile)
  {
   if(count<=0)
      return(0.0);
   if(count==1)
      return(sorted[0]);
   //--- Linear interpolation between neighbouring ranks, so a 95th
   //--- percentile of 1000 runs is not silently rounded to run 950.
   const double rank=(percentile/100.0)*(double)(count-1);
   const int lower=(int)MathFloor(rank);
   const int upper=(int)MathCeil(rank);
   if(lower==upper)
      return(sorted[CMathUtils::ClampInt(lower,0,count-1)]);
   const double weight=rank-(double)lower;
   const double a=sorted[CMathUtils::ClampInt(lower,0,count-1)];
   const double b=sorted[CMathUtils::ClampInt(upper,0,count-1)];
   return(a+(b-a)*weight);
  }
//+------------------------------------------------------------------+
string CMonteCarloSimulator::FormatReport(const SMonteCarloReport &report) const
  {
   if(!report.is_valid)
      return("MONTE CARLO: no valid simulation");

   string text="MONTE CARLO SIMULATION";
   text+="\n  runs="+IntegerToString(report.runs);
   text+="  trades/run="+IntegerToString(report.trades_per_run);
   text+="  sample="+IntegerToString(m_count);
   text+="  method="+(m_with_replacement ? "bootstrap (with replacement)"
                                         : "shuffle (without replacement)");
   text+="\n  starting balance = "+DoubleToString(report.starting_balance,2);
   text+="\n  final equity: mean="+DoubleToString(report.mean_final_equity,2);
   text+="  median="+DoubleToString(report.median_final_equity,2);
   text+="  sd="+DoubleToString(report.equity_std_dev,2);
   text+="\n                worst="+DoubleToString(report.worst_final_equity,2);
   text+="  best="+DoubleToString(report.best_final_equity,2);
   text+="\n                5th pct="+DoubleToString(report.percentile_5_equity,2);
   text+="  95th pct="+DoubleToString(report.percentile_95_equity,2);
   text+="\n  max drawdown: mean="+
         DoubleToString(report.mean_max_drawdown_percent,2)+"%";
   text+="  median="+DoubleToString(report.median_max_drawdown_percent,2)+"%";
   text+="\n                95th pct="+
         DoubleToString(report.percentile_95_drawdown,2)+"%";
   text+="  worst="+DoubleToString(report.worst_max_drawdown_percent,2)+"%";
   text+="\n  P(profit) = "+DoubleToString(report.probability_of_profit,2)+"%";
   text+="\n  RISK OF RUIN = "+DoubleToString(report.risk_of_ruin,2)+
         "% (breaching "+DoubleToString(report.ruin_threshold_percent,1)+
         "% drawdown)";
   //--- The interpretation, because a number without a threshold invites
   //--- the wrong conclusion.
   if(report.risk_of_ruin>=10.0)
      text+="\n  NOT TRADEABLE: a double-digit risk of ruin will eventually "
            "be realised";
   else
      if(report.risk_of_ruin>=5.0)
         text+="\n  MARGINAL: reduce position size before trading this live";
      else
         text+="\n  ACCEPTABLE risk of ruin at the configured threshold";
   text+="\n  NOTE: assumes trades are independent. Real results cluster by "
         "regime, so treat this as a floor on risk, not a ceiling.";
   return(text);
  }
//+------------------------------------------------------------------+
bool CMonteCarloSimulator::ExportCsv(const string relative_path,
                                     const bool common_folder) const
  {
   if(m_completed_runs<=0)
      return(false);
   int flags=FILE_WRITE|FILE_TXT|FILE_ANSI;
   if(common_folder)
      flags|=FILE_COMMON;
   const int handle=FileOpen(relative_path,flags);
   if(handle==INVALID_HANDLE)
      return(false);

   //--- One row per run: the raw distribution, so a user can plot a
   //--- histogram rather than trust a summary.
   FileWrite(handle,"run,final_equity,max_drawdown_percent,net_change");
   for(int i=0;i<m_completed_runs;i++)
     {
      string row=IntegerToString(i);
      row+=","+DoubleToString(m_final_equity[i],2);
      row+=","+DoubleToString(m_max_drawdown[i],4);
      row+=","+DoubleToString(m_final_equity[i]-m_starting_balance,2);
      FileWrite(handle,row);
     }
   FileFlush(handle);
   FileClose(handle);
   return(true);
  }
//+------------------------------------------------------------------+
string CMonteCarloSimulator::Describe(void) const
  {
   string text="CMonteCarloSimulator sample="+IntegerToString(m_count);
   text+=" runs="+IntegerToString(m_runs);
   text+=" method="+(m_with_replacement ? "bootstrap" : "shuffle");
   text+=" ruinThreshold="+DoubleToString(m_ruin_threshold_percent,1)+"%";
   text+=" seed="+IntegerToString(m_seed);
   text+=" completed="+IntegerToString(m_completed_runs);
   return(text);
  }

#endif // SRP_OPTIMIZATION_CMONTECARLOSIMULATOR_MQH
//+------------------------------------------------------------------+
