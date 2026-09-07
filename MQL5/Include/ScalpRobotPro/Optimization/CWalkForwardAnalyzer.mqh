//+------------------------------------------------------------------+
//|                                     CWalkForwardAnalyzer.mqh |
//|                    Scalping Robot Pro - Production Phase (P5) |
//|                                                                  |
//|   RESPONSIBILITY (one only): compare in-sample against out-of-sample   |
//|   results and report whether an optimisation generalised.             |
//|                                                                  |
//|   WHY THIS DECIDES WHETHER A PARAMETER SET SHIPS                      |
//|   A backtest optimised over a period tells you only that the          |
//|   parameters fit that period. Walk-forward asks the one question that  |
//|   matters: did the parameters chosen on window N make money on the     |
//|   unseen window N+1? A set that scores brilliantly in-sample and       |
//|   poorly out-of-sample is curve-fitted, and that is the single most    |
//|   common reason a profitable backtest loses money live.                |
//|                                                                  |
//|   WALK-FORWARD EFFICIENCY (WFE) = OOS result / IS result.             |
//|     >= 0.7  robust; the edge survived unseen data.                    |
//|     0.5-0.7 usable but degraded, expect worse live than backtest.     |
//|     <  0.5  curve-fitted; the parameters describe history, not a      |
//|             market behaviour. Do not trade it.                        |
//|   The thresholds are conventional in systematic trading rather than    |
//|   derived here, and the class reports the number so a user can apply   |
//|   their own bar.                                                     |
//|                                                                  |
//|   IT COMPUTES, IT DOES NOT RUN THE TESTER. MQL5 cannot launch its own  |
//|   optimisation passes from inside an EA, so this consumes the results  |
//|   the user (or the tester's own walk-forward feature) produced. That   |
//|   boundary is honest: anything claiming to automate MT5 optimisation   |
//|   from inside an EA is misrepresenting the platform.                  |
//+------------------------------------------------------------------+
#ifndef SRP_OPTIMIZATION_CWALKFORWARDANALYZER_MQH
#define SRP_OPTIMIZATION_CWALKFORWARDANALYZER_MQH

#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Types/Structs.mqh"
#include "../Utilities/CMathUtils.mqh"

#define SRP_WF_MAX_WINDOWS 64

//+------------------------------------------------------------------+
//| One in-sample / out-of-sample pair.                               |
//+------------------------------------------------------------------+
struct SWalkForwardWindow
  {
   int               index;
   datetime          is_from;
   datetime          is_to;
   datetime          oos_from;
   datetime          oos_to;
   //--- Whatever metric the user optimised on, for both halves.
   double            is_score;
   double            oos_score;
   double            is_net_profit;
   double            oos_net_profit;
   int               is_trades;
   int               oos_trades;
   double            is_max_dd_percent;
   double            oos_max_dd_percent;
   double            efficiency;          // oos / is
   bool              is_valid;

                     SWalkForwardWindow(void) { Reset(); }
   void              Reset(void)
     {
      index=0;
      is_from=0; is_to=0; oos_from=0; oos_to=0;
      is_score=0.0; oos_score=0.0;
      is_net_profit=0.0; oos_net_profit=0.0;
      is_trades=0; oos_trades=0;
      is_max_dd_percent=0.0; oos_max_dd_percent=0.0;
      efficiency=0.0; is_valid=false;
     }
  };

//+------------------------------------------------------------------+
//| The verdict across every window.                                  |
//+------------------------------------------------------------------+
struct SWalkForwardReport
  {
   int               windows;
   int               profitable_oos_windows;
   double            average_efficiency;
   double            worst_efficiency;
   double            best_efficiency;
   double            total_is_profit;
   double            total_oos_profit;
   double            consistency;         // share of OOS windows in profit
   double            oos_worst_drawdown;
   bool              passes;
   string            verdict;

                     SWalkForwardReport(void) { Reset(); }
   void              Reset(void)
     {
      windows=0; profitable_oos_windows=0;
      average_efficiency=0.0; worst_efficiency=0.0; best_efficiency=0.0;
      total_is_profit=0.0; total_oos_profit=0.0;
      consistency=0.0; oos_worst_drawdown=0.0;
      passes=false; verdict="";
     }
  };

class CWalkForwardAnalyzer
  {
private:
   ILogger          *m_logger;            // borrowed
   SWalkForwardWindow m_windows[SRP_WF_MAX_WINDOWS];
   int               m_count;

   //--- Acceptance thresholds, all configurable.
   double            m_min_efficiency;
   double            m_min_consistency;
   int               m_min_oos_trades;

   double            ComputeEfficiency(const double is_score,
                                       const double oos_score) const;

public:
                     CWalkForwardAnalyzer(ILogger *logger);
                    ~CWalkForwardAnalyzer(void) { }

   void              SetMinimumEfficiency(const double value);
   void              SetMinimumConsistency(const double value);
   void              SetMinimumOosTrades(const int trades);
   bool              Validate(SValidationResult &result) const;

   //--- Window planning: splits a date range into rolling IS/OOS pairs.
   //--- Returns the number of windows the range supports, so a user can
   //--- see that a 6-month range with 90/30 day windows gives only 3.
   int               PlanWindows(const datetime from,const datetime to,
                                 const int is_days,const int oos_days,
                                 const bool anchored=false);

   //--- Result entry, one call per completed window.
   bool              AddWindow(const SWalkForwardWindow &window);
   bool              SetWindowResults(const int index,
                                      const double is_score,
                                      const double oos_score,
                                      const double is_net,
                                      const double oos_net,
                                      const int is_trades,
                                      const int oos_trades,
                                      const double is_dd_percent,
                                      const double oos_dd_percent);
   void              Reset(void);

   int               WindowCount(void) const { return(m_count); }
   bool              WindowAt(const int index,SWalkForwardWindow &out) const;

   //--- The verdict.
   bool              Analyze(SWalkForwardReport &report) const;
   string            FormatReport(void) const;
   bool              ExportCsv(const string relative_path,
                               const bool common_folder=false) const;
   string            Describe(void) const;

   static string     EfficiencyVerdict(const double efficiency);
  };

//+------------------------------------------------------------------+
CWalkForwardAnalyzer::CWalkForwardAnalyzer(ILogger *logger)
  : m_logger(logger),
    m_count(0),
    m_min_efficiency(0.5),
    m_min_consistency(0.6),
    m_min_oos_trades(10)
  {
  }
//+------------------------------------------------------------------+
void CWalkForwardAnalyzer::SetMinimumEfficiency(const double value)
  {
   m_min_efficiency=CMathUtils::Clamp(value,0.0,2.0);
  }
//+------------------------------------------------------------------+
void CWalkForwardAnalyzer::SetMinimumConsistency(const double value)
  {
   m_min_consistency=CMathUtils::Clamp(value,0.0,1.0);
  }
//+------------------------------------------------------------------+
void CWalkForwardAnalyzer::SetMinimumOosTrades(const int trades)
  {
   m_min_oos_trades=(trades<1 ? 1 : trades);
  }
//+------------------------------------------------------------------+
bool CWalkForwardAnalyzer::Validate(SValidationResult &result) const
  {
   if(m_min_efficiency<=0.0)
      result.AddWarning("minimum walk-forward efficiency is 0, every result "
                        "would pass");
   //--- Three windows is the practical floor for a trend to mean anything.
   if(m_count>0 && m_count<3)
      result.AddWarning("fewer than 3 walk-forward windows: the efficiency "
                        "trend is not yet meaningful");
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
//| Rolling or anchored window planning.                               |
//|                                                                  |
//| ROLLING (default) moves the in-sample start forward with each step,  |
//| so the parameters are always fitted on recent data - the right model  |
//| for a market whose character changes. ANCHORED keeps the start fixed  |
//| and grows the in-sample window, which suits a stable long-run edge.   |
//+------------------------------------------------------------------+
int CWalkForwardAnalyzer::PlanWindows(const datetime from,const datetime to,
                                      const int is_days,const int oos_days,
                                      const bool anchored)
  {
   Reset();
   if(from<=0 || to<=from || is_days<1 || oos_days<1)
     {
      if(m_logger!=NULL)
         m_logger.Error("WalkForward","invalid window plan request");
      return(0);
     }

   const long day=86400;
   const long is_span=(long)is_days*day;
   const long oos_span=(long)oos_days*day;

   datetime is_start=from;
   int produced=0;
   while(produced<SRP_WF_MAX_WINDOWS)
     {
      const datetime is_end=(datetime)((long)is_start+is_span);
      const datetime oos_end=(datetime)((long)is_end+oos_span);
      //--- A partial out-of-sample window would be compared against a
      //--- full in-sample one, which is not a fair test.
      if(oos_end>to)
         break;

      SWalkForwardWindow window;
      window.index=produced;
      window.is_from=(anchored ? from : is_start);
      window.is_to=is_end;
      window.oos_from=is_end;
      window.oos_to=oos_end;
      m_windows[produced]=window;
      produced++;

      //--- Step by the OOS length: consecutive out-of-sample periods
      //--- then tile the range with no gap and no overlap.
      is_start=(datetime)((long)is_start+oos_span);
     }
   m_count=produced;

   if(m_logger!=NULL)
      m_logger.Info("WalkForward","planned "+IntegerToString(produced)+
                    " window(s), "+(anchored ? "anchored" : "rolling")+
                    ", IS="+IntegerToString(is_days)+"d OOS="+
                    IntegerToString(oos_days)+"d");
   return(produced);
  }
//+------------------------------------------------------------------+
bool CWalkForwardAnalyzer::AddWindow(const SWalkForwardWindow &window)
  {
   if(m_count>=SRP_WF_MAX_WINDOWS)
      return(false);
   m_windows[m_count]=window;
   m_windows[m_count].index=m_count;
   m_windows[m_count].efficiency=ComputeEfficiency(window.is_score,
                                                   window.oos_score);
   m_windows[m_count].is_valid=(window.oos_trades>=m_min_oos_trades);
   m_count++;
   return(true);
  }
//+------------------------------------------------------------------+
bool CWalkForwardAnalyzer::SetWindowResults(const int index,
                                           const double is_score,
                                           const double oos_score,
                                           const double is_net,
                                           const double oos_net,
                                           const int is_trades,
                                           const int oos_trades,
                                           const double is_dd_percent,
                                           const double oos_dd_percent)
  {
   if(index<0 || index>=m_count)
      return(false);
   m_windows[index].is_score=is_score;
   m_windows[index].oos_score=oos_score;
   m_windows[index].is_net_profit=is_net;
   m_windows[index].oos_net_profit=oos_net;
   m_windows[index].is_trades=is_trades;
   m_windows[index].oos_trades=oos_trades;
   m_windows[index].is_max_dd_percent=is_dd_percent;
   m_windows[index].oos_max_dd_percent=oos_dd_percent;
   m_windows[index].efficiency=ComputeEfficiency(is_score,oos_score);
   //--- A window with too few out-of-sample trades is excluded from the
   //--- verdict rather than allowed to distort the average.
   m_windows[index].is_valid=(oos_trades>=m_min_oos_trades);
   return(true);
  }
//+------------------------------------------------------------------+
double CWalkForwardAnalyzer::ComputeEfficiency(const double is_score,
                                               const double oos_score) const
  {
   //--- An in-sample result at or below zero means the optimisation found
   //--- nothing to begin with; efficiency is undefined, not infinite.
   if(is_score<=SRP_EPSILON)
      return(0.0);
   //--- Not clamped at 1.0: an efficiency above 1 is real and means the
   //--- unseen period was simply kinder. Hiding it would be dishonest.
   return(oos_score/is_score);
  }
//+------------------------------------------------------------------+
void CWalkForwardAnalyzer::Reset(void)
  {
   for(int i=0;i<SRP_WF_MAX_WINDOWS;i++)
      m_windows[i].Reset();
   m_count=0;
  }
//+------------------------------------------------------------------+
bool CWalkForwardAnalyzer::WindowAt(const int index,
                                    SWalkForwardWindow &out) const
  {
   if(index<0 || index>=m_count)
      return(false);
   out=m_windows[index];
   return(true);
  }
//+------------------------------------------------------------------+
bool CWalkForwardAnalyzer::Analyze(SWalkForwardReport &report) const
  {
   report.Reset();
   if(m_count<=0)
     {
      report.verdict="no windows supplied";
      return(false);
     }

   double efficiency_total=0.0;
   int counted=0;
   bool seeded=false;

   for(int i=0;i<m_count;i++)
     {
      //--- Only windows with a usable out-of-sample sample count.
      if(!m_windows[i].is_valid)
         continue;
      counted++;
      efficiency_total+=m_windows[i].efficiency;
      report.total_is_profit+=m_windows[i].is_net_profit;
      report.total_oos_profit+=m_windows[i].oos_net_profit;
      if(m_windows[i].oos_net_profit>0.0)
         report.profitable_oos_windows++;
      if(m_windows[i].oos_max_dd_percent>report.oos_worst_drawdown)
         report.oos_worst_drawdown=m_windows[i].oos_max_dd_percent;

      if(!seeded)
        {
         report.worst_efficiency=m_windows[i].efficiency;
         report.best_efficiency=m_windows[i].efficiency;
         seeded=true;
        }
      else
        {
         if(m_windows[i].efficiency<report.worst_efficiency)
            report.worst_efficiency=m_windows[i].efficiency;
         if(m_windows[i].efficiency>report.best_efficiency)
            report.best_efficiency=m_windows[i].efficiency;
        }
     }

   report.windows=counted;
   if(counted<=0)
     {
      report.verdict="every window had too few out-of-sample trades to judge";
      return(false);
     }

   report.average_efficiency=efficiency_total/(double)counted;
   report.consistency=CMathUtils::SafeDivide((double)report.profitable_oos_windows,
                                             (double)counted,0.0);

   //--- THE VERDICT. All three conditions must hold: a good average that
   //--- hides one catastrophic window is not robustness, and profit that
   //--- comes from one lucky window out of six is not consistency.
   const bool efficiency_ok=(report.average_efficiency>=m_min_efficiency);
   const bool consistency_ok=(report.consistency>=m_min_consistency);
   const bool profitable=(report.total_oos_profit>0.0);
   report.passes=(efficiency_ok && consistency_ok && profitable);

   report.verdict=EfficiencyVerdict(report.average_efficiency);
   if(!profitable)
      report.verdict+="; out-of-sample total is not profitable";
   if(!consistency_ok)
      report.verdict+="; only "+
                      DoubleToString(report.consistency*100.0,0)+
                      "% of windows were profitable out of sample";
   return(report.passes);
  }
//+------------------------------------------------------------------+
string CWalkForwardAnalyzer::EfficiencyVerdict(const double efficiency)
  {
   if(efficiency>=0.7)
      return("ROBUST: the edge survived unseen data");
   if(efficiency>=0.5)
      return("USABLE BUT DEGRADED: expect live results below the backtest");
   if(efficiency>0.0)
      return("CURVE-FITTED: the parameters describe history, not the market");
   return("FAILED: no measurable out-of-sample performance");
  }
//+------------------------------------------------------------------+
string CWalkForwardAnalyzer::FormatReport(void) const
  {
   SWalkForwardReport report;
   Analyze(report);

   string text="WALK-FORWARD ANALYSIS";
   text+="\n  windows judged: "+IntegerToString(report.windows)+
         " of "+IntegerToString(m_count)+" supplied";
   if(report.windows<=0)
      return(text+"\n  "+report.verdict);

   text+="\n  idx  IS trades  OOS trades      IS net     OOS net   WFE";
   for(int i=0;i<m_count;i++)
     {
      text+=StringFormat("\n  %3d  %9d  %10d  %10.2f  %10.2f  %5.2f%s",
                         m_windows[i].index,
                         m_windows[i].is_trades,
                         m_windows[i].oos_trades,
                         m_windows[i].is_net_profit,
                         m_windows[i].oos_net_profit,
                         m_windows[i].efficiency,
                         (m_windows[i].is_valid ? "" : "  (excluded)"));
     }
   text+="\n  average WFE = "+DoubleToString(report.average_efficiency,3);
   text+="  worst = "+DoubleToString(report.worst_efficiency,3);
   text+="  best = "+DoubleToString(report.best_efficiency,3);
   text+="\n  IS total = "+DoubleToString(report.total_is_profit,2);
   text+="  OOS total = "+DoubleToString(report.total_oos_profit,2);
   text+="\n  consistency = "+DoubleToString(report.consistency*100.0,1)+
         "% of windows profitable out of sample";
   text+="\n  worst OOS drawdown = "+
         DoubleToString(report.oos_worst_drawdown,2)+"%";
   text+="\n  VERDICT: "+(report.passes ? "PASS" : "FAIL")+" - "+report.verdict;
   return(text);
  }
//+------------------------------------------------------------------+
bool CWalkForwardAnalyzer::ExportCsv(const string relative_path,
                                     const bool common_folder) const
  {
   if(m_count<=0)
      return(false);
   int flags=FILE_WRITE|FILE_TXT|FILE_ANSI;
   if(common_folder)
      flags|=FILE_COMMON;
   const int handle=FileOpen(relative_path,flags);
   if(handle==INVALID_HANDLE)
      return(false);

   FileWrite(handle,
             "window,is_from,is_to,oos_from,oos_to,is_trades,oos_trades,"
             "is_score,oos_score,is_net,oos_net,is_dd_pct,oos_dd_pct,"
             "efficiency,judged");
   for(int i=0;i<m_count;i++)
     {
      string row=IntegerToString(m_windows[i].index);
      row+=","+TimeToString(m_windows[i].is_from,TIME_DATE);
      row+=","+TimeToString(m_windows[i].is_to,TIME_DATE);
      row+=","+TimeToString(m_windows[i].oos_from,TIME_DATE);
      row+=","+TimeToString(m_windows[i].oos_to,TIME_DATE);
      row+=","+IntegerToString(m_windows[i].is_trades);
      row+=","+IntegerToString(m_windows[i].oos_trades);
      row+=","+DoubleToString(m_windows[i].is_score,6);
      row+=","+DoubleToString(m_windows[i].oos_score,6);
      row+=","+DoubleToString(m_windows[i].is_net_profit,2);
      row+=","+DoubleToString(m_windows[i].oos_net_profit,2);
      row+=","+DoubleToString(m_windows[i].is_max_dd_percent,2);
      row+=","+DoubleToString(m_windows[i].oos_max_dd_percent,2);
      row+=","+DoubleToString(m_windows[i].efficiency,4);
      row+=","+(m_windows[i].is_valid ? "1" : "0");
      FileWrite(handle,row);
     }
   FileFlush(handle);
   FileClose(handle);
   return(true);
  }
//+------------------------------------------------------------------+
string CWalkForwardAnalyzer::Describe(void) const
  {
   string text="CWalkForwardAnalyzer windows="+IntegerToString(m_count);
   text+=" minWFE="+DoubleToString(m_min_efficiency,2);
   text+=" minConsistency="+DoubleToString(m_min_consistency,2);
   text+=" minOosTrades="+IntegerToString(m_min_oos_trades);
   return(text);
  }

#endif // SRP_OPTIMIZATION_CWALKFORWARDANALYZER_MQH
//+------------------------------------------------------------------+
