//+------------------------------------------------------------------+
//|                                    CPerformanceAnalytics.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   RESPONSIBILITY (one only): turn a list of closed trades into        |
//|   numbers. It records nothing itself and asks the terminal for        |
//|   nothing; trades are pushed in by the caller.                       |
//|                                                                  |
//|   Metrics: Profit Factor · Sharpe Ratio · Sortino Ratio ·             |
//|   Recovery Factor · Maximum Drawdown · Average Win · Average Loss ·   |
//|   Trade Duration · Monthly Report · Yearly Report.                   |
//|                                                                  |
//|   WHY A PUSH MODEL: an analytics class that queries HistoryDeals is   |
//|   untestable and slow, and in the Strategy Tester it re-reads the     |
//|   entire deal history on every call. Pushing one SClosedTrade on      |
//|   close is O(1) and works identically live, in the tester and in a    |
//|   unit harness.                                                      |
//|                                                                  |
//|   HONEST STATISTICS. Two rules are enforced everywhere:              |
//|     1. Ratios with an empty denominator return 0.0, never infinity.   |
//|        A profit factor of "inf" after two winning trades is a lie     |
//|        that sells software and loses accounts.                       |
//|     2. Sharpe/Sortino need a sample. Below m_min_sample trades they   |
//|        return 0.0 rather than a number computed from three data       |
//|        points, and is_valid reports which reports are trustworthy.    |
//|                                                                  |
//|   SHARPE HERE IS PER-TRADE, NOT ANNUALISED, and Sortino uses downside |
//|   deviation about zero. Both are stated rather than hidden, because   |
//|   an unlabelled Sharpe is uncomparable between products.             |
//|                                                                  |
//|   DRAWDOWN is computed from the balance curve the trades imply,       |
//|   peak-to-trough, in money and percent of the running peak.          |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_ANALYTICS_CPERFORMANCEANALYTICS_MQH
#define SRP_INTERFACE_ANALYTICS_CPERFORMANCEANALYTICS_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Core/Types/Constants.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "../Types/InterfaceStructs.mqh"

//--- Ring capacity. 4096 closed scalps is several months of a busy
//--- account and costs about 700 KB, which is acceptable; unbounded
//--- growth in an EA that runs for a year is not.
#define SRP_PA_MAX_TRADES  4096
#define SRP_PA_MAX_BUCKETS 64
//--- Open-ended upper bound for a window. MQL5 datetime tops out at
//--- 31 Dec 3000, so this is the real maximum, not a cast of LONG_MAX.
#define SRP_PA_TIME_MAX    D'3000.12.31 23:59:59'

class CPerformanceAnalytics
  {
private:
   ILogger          *m_logger;            // borrowed
   string            m_symbol;

   //--- Closed-trade ring, oldest at m_first.
   SClosedTrade      m_trades[SRP_PA_MAX_TRADES];
   int               m_count;
   int               m_head;
   long              m_total_pushed;      // includes records aged out

   double            m_initial_balance;
   int               m_min_sample;        // below this, ratios stay 0
   bool              m_use_r_multiples;   // Sharpe on R instead of money

   //--- Cached all-time report, invalidated on push.
   SAnalyticsReport  m_cached_all;
   bool              m_cache_valid;

   //--- Period cache. The dashboard asks for today/week/month profit on
   //--- every repaint; without this, one refresh costs four full passes
   //--- over the trade history. Invalidated on push AND when the window
   //--- start moves, so a day rollover cannot serve yesterday's number.
   SAnalyticsReport  m_cached_period[5];
   datetime          m_cached_period_from[5];
   bool              m_cached_period_valid[5];

   void              InvalidatePeriodCache(void);
   int               Slot(const int index) const;
   bool              PeriodBounds(const ENUM_SRP_PA_PERIOD period,
                                 const datetime anchor,
                                 datetime &from,datetime &to) const;
   //--- The one real computation. Everything else selects a window and
   //--- delegates here, so a metric is defined exactly once.
   void              Compute(const datetime from,const datetime to,
                             const ENUM_SRP_PA_PERIOD period,
                             SAnalyticsReport &report) const;
   static datetime   StartOfDay(const datetime when);
   static datetime   StartOfWeek(const datetime when);
   static datetime   StartOfMonth(const datetime when);
   static datetime   StartOfYear(const datetime when);
   static datetime   AddMonths(const datetime when,const int months);

public:
                     CPerformanceAnalytics(const string symbol,
                                           const double initial_balance,
                                           ILogger *logger);
                    ~CPerformanceAnalytics(void) { }

   //=== CONFIGURATION ================================================
   void              SetInitialBalance(const double balance);
   void              SetMinimumSample(const int trades);
   void              SetUseRMultiples(const bool enabled);
   bool              Validate(SValidationResult &result) const;

   //=== INPUT ========================================================
   //--- Called once per closed trade. Derives duration, R-multiple and
   //--- running balance when the caller left them at zero, so a minimal
   //--- record is still enough to produce correct analytics.
   bool              AddTrade(const SClosedTrade &trade);
   void              Reset(void);
   int               TradeCount(void)  const { return(m_count); }
   long              TotalPushed(void) const { return(m_total_pushed); }
   bool              TradeAt(const int index,SClosedTrade &out) const;

   //=== REPORTS ======================================================
   //--- All-time. Cached, because the dashboard asks every repaint.
   bool              AllTime(SAnalyticsReport &report);
   //--- Window ending now.
   //--- Not const: it maintains the period cache.
   bool              ForPeriod(const ENUM_SRP_PA_PERIOD period,
                               SAnalyticsReport &report);
   //--- Explicit window, used by the monthly/yearly breakdowns.
   bool              ForRange(const datetime from,const datetime to,
                              SAnalyticsReport &report) const;
   //--- One calendar month / year.
   bool              MonthlyReport(const int year,const int month,
                                   SAnalyticsReport &report) const;
   bool              YearlyReport(const int year,
                                  SAnalyticsReport &report) const;
   //--- Every month/year that actually contains trades, oldest first.
   int               MonthlyBreakdown(SAnalyticsReport &reports[]) const;
   int               YearlyBreakdown(SAnalyticsReport &reports[]) const;

   //=== SINGLE METRICS ===============================================
   //--- Convenience accessors over the all-time window. They exist so
   //--- the dashboard does not need to hold a whole report.
   double            ProfitFactor(void)    const;
   double            SharpeRatio(void)     const;
   double            SortinoRatio(void)    const;
   double            RecoveryFactor(void)  const;
   double            MaxDrawdownMoney(void) const;
   double            MaxDrawdownPercent(void) const;
   double            AverageWin(void)      const;
   double            AverageLoss(void)     const;
   double            AverageDurationSeconds(void) const;
   double            WinRate(void)         const;
   double            Expectancy(void)      const;
   double            AverageRr(void)       const;
   double            NetProfit(void)       const;
   //--- Period money, for the dashboard's today/week/month rows.
   double            PeriodProfit(const ENUM_SRP_PA_PERIOD period);

   //=== TEXT =========================================================
   string            FormatReport(const SAnalyticsReport &report) const;
   string            FormatMonthlyTable(void) const;
   string            FormatYearlyTable(void) const;
   //--- CSV export of the closed-trade list, one row per trade.
   //---
   //--- HARNESS v2, FIX 4. `preamble`, when non-empty, is written verbatim as
   //--- the FIRST line of the file. It carries the run's provenance - tick
   //--- model, cost model, data segment - so a row of numbers can never be
   //--- read without the conditions that produced it. It is expected to be
   //--- '#'-prefixed and comma-free; consumers skip lines starting with '#'.
   bool              ExportTradesCsv(const string relative_path,
                                     const bool common_folder=false,
                                     const string preamble="") const;
   //--- CSV export of the monthly breakdown, one row per month.
   bool              ExportMonthlyCsv(const string relative_path,
                                      const bool common_folder=false,
                                      const string preamble="") const;
   string            Describe(void) const;

   static string     PeriodToString(const ENUM_SRP_PA_PERIOD period);
   static string     DurationToString(const int seconds);
  };

//+------------------------------------------------------------------+
CPerformanceAnalytics::CPerformanceAnalytics(const string symbol,
                                             const double initial_balance,
                                             ILogger *logger)
  : m_logger(logger),
    m_symbol(symbol),
    m_count(0),
    m_head(0),
    m_total_pushed(0),
    m_initial_balance(initial_balance>0.0 ? initial_balance : 0.0),
    m_min_sample(10),
    m_use_r_multiples(false),
    m_cache_valid(false)
  {
   for(int i=0;i<5;i++)
     {
      m_cached_period_from[i]=0;
      m_cached_period_valid[i]=false;
     }
  }
//+------------------------------------------------------------------+
void CPerformanceAnalytics::SetInitialBalance(const double balance)
  {
   m_initial_balance=(balance>0.0 ? balance : 0.0);
   m_cache_valid=false;
   InvalidatePeriodCache();
  }
//+------------------------------------------------------------------+
void CPerformanceAnalytics::SetMinimumSample(const int trades)
  {
   //--- Two is the absolute floor for a standard deviation.
   m_min_sample=(trades<2 ? 2 : trades);
   m_cache_valid=false;
   InvalidatePeriodCache();
  }
//+------------------------------------------------------------------+
void CPerformanceAnalytics::SetUseRMultiples(const bool enabled)
  {
   m_use_r_multiples=enabled;
   m_cache_valid=false;
   InvalidatePeriodCache();
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::Validate(SValidationResult &result) const
  {
   if(m_initial_balance<=0.0)
      result.AddWarning("initial balance is zero, drawdown percent "
                        "falls back to the running peak");
   if(m_min_sample<2)
      result.AddError("minimum sample must be at least 2");
   if(m_symbol=="")
      result.AddWarning("analytics symbol is empty");
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
void CPerformanceAnalytics::InvalidatePeriodCache(void)
  {
   for(int i=0;i<5;i++)
      m_cached_period_valid[i]=false;
  }
//+------------------------------------------------------------------+
int CPerformanceAnalytics::Slot(const int index) const
  {
   //--- index 0 is the OLDEST retained trade, which is the order every
   //--- sequential calculation (balance curve, streaks) needs.
   if(index<0 || index>=m_count)
      return(-1);
   if(m_count<SRP_PA_MAX_TRADES)
      return(index);
   int slot=m_head+index;
   while(slot>=SRP_PA_MAX_TRADES)
      slot-=SRP_PA_MAX_TRADES;
   return(slot);
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::TradeAt(const int index,SClosedTrade &out) const
  {
   const int slot=Slot(index);
   if(slot<0)
      return(false);
   out=m_trades[slot];
   return(true);
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::AddTrade(const SClosedTrade &trade)
  {
   if(trade.close_time==0)
      return(false);

   SClosedTrade stored=trade;

   //--- Derive whatever the caller omitted. A caller that only knows
   //--- profit and times still gets correct duration and R.
   if(stored.duration_seconds<=0 && stored.open_time>0 &&
      stored.close_time>=stored.open_time)
      stored.duration_seconds=(int)(stored.close_time-stored.open_time);

   if(stored.net_profit==0.0 &&
      (stored.gross_profit!=0.0 || stored.commission!=0.0 || stored.swap!=0.0))
      stored.net_profit=stored.gross_profit+stored.commission+stored.swap;

   if(stored.r_multiple==0.0 && stored.risk_amount>0.0)
      stored.r_multiple=CMathUtils::SafeDivide(stored.net_profit,
                                               stored.risk_amount,0.0);

   //--- Running balance. Needed for the drawdown curve, and the caller
   //--- usually does not have it to hand at close time.
   if(stored.balance_after==0.0)
     {
      double previous=m_initial_balance;
      if(m_count>0)
        {
         const int last=Slot(m_count-1);
         if(last>=0)
            previous=m_trades[last].balance_after;
        }
      stored.balance_after=previous+stored.net_profit;
     }

   const int write=(m_count<SRP_PA_MAX_TRADES
                    ? m_count
                    : m_head);
   m_trades[write]=stored;
   if(m_count<SRP_PA_MAX_TRADES)
      m_count++;
   else
     {
      m_head++;
      if(m_head>=SRP_PA_MAX_TRADES)
         m_head=0;
     }
   m_total_pushed++;
   m_cache_valid=false;
   InvalidatePeriodCache();

   if(m_logger!=NULL && m_logger.IsEnabled(SRP_LOG_DEBUG))
      m_logger.Debug("Analytics",
                     "trade #"+IntegerToString((long)stored.ticket)+
                     " net="+DoubleToString(stored.net_profit,2)+
                     " R="+DoubleToString(stored.r_multiple,2)+
                     " retained="+IntegerToString(m_count));
   return(true);
  }
//+------------------------------------------------------------------+
void CPerformanceAnalytics::Reset(void)
  {
   m_count=0;
   m_head=0;
   m_cache_valid=false;
   m_cached_all.Reset();
   InvalidatePeriodCache();
  }
//+------------------------------------------------------------------+
//| THE calculation. One pass for aggregates, one pass for the balance   |
//| curve, one pass for deviation. Three O(n) passes over at most 4096   |
//| records is trivial, and keeping them separate keeps each readable.   |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::Compute(const datetime from,const datetime to,
                                    const ENUM_SRP_PA_PERIOD period,
                                    SAnalyticsReport &report) const
  {
   report.Reset();
   report.period=period;
   report.from=from;
   report.to=to;

   double returns[];
   ArrayResize(returns,m_count);
   int sample=0;

   double running_balance=m_initial_balance;
   double peak_balance=m_initial_balance;
   //--- Deliberately NOT seeded from the initial balance. The peak must
   //--- start at the balance the WINDOW opened with, otherwise a monthly
   //--- report on an account that has since doubled would measure its
   //--- drawdown against the original deposit and report none at all.
   bool   peak_seeded=false;
   int    win_streak=0,loss_streak=0;
   double duration_total=0.0;
   bool   duration_seeded=false;
   double r_total=0.0;
   int    r_count=0;

   for(int i=0;i<m_count;i++)
     {
      const int slot=Slot(i);
      if(slot<0)
         continue;
      //--- The balance curve must advance across the WHOLE history, not
      //--- just the window, otherwise a monthly drawdown would start
      //--- from the initial deposit instead of the month's opening equity.
      running_balance=m_trades[slot].balance_after;

      const bool in_window=(m_trades[slot].close_time>=from &&
                            m_trades[slot].close_time<=to);
      if(!in_window)
         continue;

      //--- Seed the peak with the balance BEFORE the first in-window
      //--- trade, so an opening loss counts as drawdown.
      if(!peak_seeded)
        {
         peak_balance=running_balance-m_trades[slot].net_profit;
         peak_seeded=true;
        }

      const double net=m_trades[slot].net_profit;
      report.total_trades++;
      report.total_commission+=m_trades[slot].commission;
      report.total_swap+=m_trades[slot].swap;
      report.net_profit+=net;

      if(m_trades[slot].IsWin())
        {
         report.wins++;
         report.gross_profit+=net;
         if(net>report.largest_win)
            report.largest_win=net;
         win_streak++;
         loss_streak=0;
         if(win_streak>report.max_consecutive_wins)
            report.max_consecutive_wins=win_streak;
        }
      else
         if(m_trades[slot].IsLoss())
           {
            report.losses++;
            report.gross_loss+=MathAbs(net);
            if(net<report.largest_loss)
               report.largest_loss=net;
            loss_streak++;
            win_streak=0;
            if(loss_streak>report.max_consecutive_losses)
               report.max_consecutive_losses=loss_streak;
           }
         else
            report.breakeven++;

      //--- Drawdown from the running peak of the implied balance curve.
      if(running_balance>peak_balance)
         peak_balance=running_balance;
      const double dd_money=peak_balance-running_balance;
      if(dd_money>report.max_drawdown_money)
        {
         report.max_drawdown_money=dd_money;
         report.max_drawdown_percent=CMathUtils::SafeDivide(dd_money*100.0,
                                                            peak_balance,0.0);
        }

      //--- Duration.
      const int seconds=m_trades[slot].duration_seconds;
      duration_total+=(double)seconds;
      if(!duration_seeded)
        {
         report.longest_duration_seconds=seconds;
         report.shortest_duration_seconds=seconds;
         duration_seeded=true;
        }
      else
        {
         if(seconds>report.longest_duration_seconds)
            report.longest_duration_seconds=seconds;
         if(seconds<report.shortest_duration_seconds)
            report.shortest_duration_seconds=seconds;
        }

      if(m_trades[slot].r_multiple!=0.0)
        {
         r_total+=m_trades[slot].r_multiple;
         r_count++;
        }

      //--- Return series for Sharpe/Sortino. R-multiples make the series
      //--- comparable across lot sizes; money is what the account felt.
      returns[sample]=(m_use_r_multiples ? m_trades[slot].r_multiple : net);
      sample++;
     }

   report.peak_balance=peak_balance;

   if(report.total_trades<=0)
     {
      report.is_valid=false;
      return;
     }

   report.win_rate=CMathUtils::SafeDivide((double)report.wins*100.0,
                                          (double)report.total_trades,0.0);
   report.average_win=CMathUtils::SafeDivide(report.gross_profit,
                                             (double)report.wins,0.0);
   report.average_loss=CMathUtils::SafeDivide(report.gross_loss,
                                              (double)report.losses,0.0);
   //--- Zero, not infinity, when there is no loss to divide by.
   report.profit_factor=CMathUtils::SafeDivide(report.gross_profit,
                                               report.gross_loss,0.0);
   report.payoff_ratio=CMathUtils::SafeDivide(report.average_win,
                                              report.average_loss,0.0);
   report.expectancy=CMathUtils::SafeDivide(report.net_profit,
                                            (double)report.total_trades,0.0);
   report.average_r_multiple=CMathUtils::SafeDivide(r_total,
                                                    (double)r_count,0.0);
   report.average_duration_seconds=CMathUtils::SafeDivide(duration_total,
                                                          (double)report.total_trades,0.0);
   //--- Net profit per unit of worst pain endured.
   report.recovery_factor=CMathUtils::SafeDivide(report.net_profit,
                                                 report.max_drawdown_money,0.0);

   //--- Sharpe and Sortino, per trade, only with a real sample.
   if(sample>=m_min_sample)
     {
      ArrayResize(returns,sample);
      double total=0.0;
      for(int i=0;i<sample;i++)
         total+=returns[i];
      const double mean=total/(double)sample;

      double variance=0.0,downside=0.0;
      int downside_count=0;
      for(int i=0;i<sample;i++)
        {
         const double deviation=returns[i]-mean;
         variance+=deviation*deviation;
         //--- Sortino penalises only losses, measured about zero, which
         //--- is the threshold a trader actually cares about.
         if(returns[i]<0.0)
           {
            downside+=returns[i]*returns[i];
            downside_count++;
           }
        }
      //--- Sample standard deviation (n-1): these are observations, not
      //--- a population.
      const double stdev=MathSqrt(variance/(double)(sample-1));
      report.sharpe_ratio=CMathUtils::SafeDivide(mean,stdev,0.0);

      if(downside_count>0)
        {
         const double downside_dev=MathSqrt(downside/(double)sample);
         report.sortino_ratio=CMathUtils::SafeDivide(mean,downside_dev,0.0);
        }
      else
         //--- No losing trade in the sample. Sortino is undefined, so it
         //--- stays at zero rather than reporting a fabricated ceiling.
         report.sortino_ratio=0.0;
     }

   report.is_valid=true;
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::AllTime(SAnalyticsReport &report)
  {
   if(!m_cache_valid)
     {
      Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,m_cached_all);
      m_cache_valid=true;
     }
   report=m_cached_all;
   return(report.is_valid);
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::ForRange(const datetime from,const datetime to,
                                     SAnalyticsReport &report) const
  {
   Compute(from,to,SRP_PA_PERIOD_ALL,report);
   report.from=from;
   report.to=to;
   return(report.is_valid);
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::ForPeriod(const ENUM_SRP_PA_PERIOD period,
                                      SAnalyticsReport &report)
  {
   datetime from=0,to=0;
   if(!PeriodBounds(period,TimeCurrent(),from,to))
      return(false);

   const int slot=(int)period;
   //--- Serve the cache only when the window START is unchanged. A cached
   //--- "today" from before midnight is worse than no cache at all.
   if(slot>=0 && slot<5)
     {
      if(m_cached_period_valid[slot] && m_cached_period_from[slot]==from)
        {
         report=m_cached_period[slot];
         return(report.is_valid);
        }
      Compute(from,to,period,report);
      m_cached_period[slot]=report;
      m_cached_period_from[slot]=from;
      m_cached_period_valid[slot]=true;
      return(report.is_valid);
     }

   Compute(from,to,period,report);
   return(report.is_valid);
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::PeriodBounds(const ENUM_SRP_PA_PERIOD period,
                                         const datetime anchor,
                                         datetime &from,datetime &to) const
  {
   to=SRP_PA_TIME_MAX;
   switch(period)
     {
      case SRP_PA_PERIOD_ALL:   from=0;                    return(true);
      case SRP_PA_PERIOD_DAY:   from=StartOfDay(anchor);   return(true);
      case SRP_PA_PERIOD_WEEK:  from=StartOfWeek(anchor);  return(true);
      case SRP_PA_PERIOD_MONTH: from=StartOfMonth(anchor); return(true);
      case SRP_PA_PERIOD_YEAR:  from=StartOfYear(anchor);  return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::MonthlyReport(const int year,const int month,
                                          SAnalyticsReport &report) const
  {
   if(month<1 || month>12)
      return(false);
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(),parts);
   parts.year=year; parts.mon=month; parts.day=1;
   parts.hour=0; parts.min=0; parts.sec=0;
   const datetime from=StructToTime(parts);
   //--- One second before the next month starts, so the window is
   //--- inclusive on both ends without overlapping the neighbour.
   const datetime to=AddMonths(from,1)-1;
   Compute(from,to,SRP_PA_PERIOD_MONTH,report);
   return(report.is_valid);
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::YearlyReport(const int year,
                                         SAnalyticsReport &report) const
  {
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(),parts);
   parts.year=year; parts.mon=1; parts.day=1;
   parts.hour=0; parts.min=0; parts.sec=0;
   const datetime from=StructToTime(parts);
   parts.year=year+1;
   const datetime to=StructToTime(parts)-1;
   Compute(from,to,SRP_PA_PERIOD_YEAR,report);
   return(report.is_valid);
  }
//+------------------------------------------------------------------+
//| Only periods that contain trades are emitted. A monthly table with  |
//| eleven empty rows tells the trader nothing.                         |
//+------------------------------------------------------------------+
int CPerformanceAnalytics::MonthlyBreakdown(SAnalyticsReport &reports[]) const
  {
   ArrayResize(reports,0);
   if(m_count<=0)
      return(0);

   int years[SRP_PA_MAX_BUCKETS],months[SRP_PA_MAX_BUCKETS];
   int buckets=0;
   for(int i=0;i<m_count;i++)
     {
      const int slot=Slot(i);
      if(slot<0)
         continue;
      MqlDateTime parts;
      TimeToStruct(m_trades[slot].close_time,parts);
      bool known=false;
      for(int b=0;b<buckets;b++)
         if(years[b]==parts.year && months[b]==parts.mon)
           {
            known=true;
            break;
           }
      if(known || buckets>=SRP_PA_MAX_BUCKETS)
         continue;
      years[buckets]=parts.year;
      months[buckets]=parts.mon;
      buckets++;
     }

   //--- Trades arrive chronologically, so the bucket list already is.
   int produced=0;
   for(int b=0;b<buckets;b++)
     {
      SAnalyticsReport report;
      if(!MonthlyReport(years[b],months[b],report))
         continue;
      if(ArrayResize(reports,produced+1)!=produced+1)
         break;
      reports[produced]=report;
      produced++;
     }
   return(produced);
  }
//+------------------------------------------------------------------+
int CPerformanceAnalytics::YearlyBreakdown(SAnalyticsReport &reports[]) const
  {
   ArrayResize(reports,0);
   if(m_count<=0)
      return(0);

   int years[SRP_PA_MAX_BUCKETS];
   int buckets=0;
   for(int i=0;i<m_count;i++)
     {
      const int slot=Slot(i);
      if(slot<0)
         continue;
      MqlDateTime parts;
      TimeToStruct(m_trades[slot].close_time,parts);
      bool known=false;
      for(int b=0;b<buckets;b++)
         if(years[b]==parts.year)
           {
            known=true;
            break;
           }
      if(known || buckets>=SRP_PA_MAX_BUCKETS)
         continue;
      years[buckets]=parts.year;
      buckets++;
     }

   int produced=0;
   for(int b=0;b<buckets;b++)
     {
      SAnalyticsReport report;
      if(!YearlyReport(years[b],report))
         continue;
      if(ArrayResize(reports,produced+1)!=produced+1)
         break;
      reports[produced]=report;
      produced++;
     }
   return(produced);
  }
//+------------------------------------------------------------------+
//| Single-metric accessors. Each computes the all-time window; they are |
//| const so they cannot touch the cache, which is the correct trade-off |
//| for callers that want one number without holding a report.           |
//+------------------------------------------------------------------+
double CPerformanceAnalytics::ProfitFactor(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.profit_factor);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::SharpeRatio(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.sharpe_ratio);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::SortinoRatio(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.sortino_ratio);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::RecoveryFactor(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.recovery_factor);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::MaxDrawdownMoney(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.max_drawdown_money);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::MaxDrawdownPercent(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.max_drawdown_percent);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::AverageWin(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.average_win);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::AverageLoss(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.average_loss);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::AverageDurationSeconds(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.average_duration_seconds);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::WinRate(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.win_rate);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::Expectancy(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.expectancy);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::AverageRr(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   //--- Prefer measured R; fall back to the win/loss payoff when no
   //--- trade carried a risk amount.
   if(report.average_r_multiple!=0.0)
      return(report.average_r_multiple);
   return(report.payoff_ratio);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::NetProfit(void) const
  {
   SAnalyticsReport report;
   Compute(0,SRP_PA_TIME_MAX,SRP_PA_PERIOD_ALL,report);
   return(report.net_profit);
  }
//+------------------------------------------------------------------+
double CPerformanceAnalytics::PeriodProfit(const ENUM_SRP_PA_PERIOD period)
  {
   SAnalyticsReport report;
   if(!ForPeriod(period,report))
      return(0.0);
   return(report.net_profit);
  }
//+------------------------------------------------------------------+
datetime CPerformanceAnalytics::StartOfDay(const datetime when)
  {
   MqlDateTime parts;
   TimeToStruct(when,parts);
   parts.hour=0; parts.min=0; parts.sec=0;
   return(StructToTime(parts));
  }
//+------------------------------------------------------------------+
datetime CPerformanceAnalytics::StartOfWeek(const datetime when)
  {
   MqlDateTime parts;
   TimeToStruct(when,parts);
   //--- Monday-based, because a trading week is Monday to Friday even
   //--- though MQL5 numbers Sunday as 0.
   int shift=parts.day_of_week-1;
   if(shift<0)
      shift=6;
   return(StartOfDay(when)-(datetime)(shift*86400));
  }
//+------------------------------------------------------------------+
datetime CPerformanceAnalytics::StartOfMonth(const datetime when)
  {
   MqlDateTime parts;
   TimeToStruct(when,parts);
   parts.day=1; parts.hour=0; parts.min=0; parts.sec=0;
   return(StructToTime(parts));
  }
//+------------------------------------------------------------------+
datetime CPerformanceAnalytics::StartOfYear(const datetime when)
  {
   MqlDateTime parts;
   TimeToStruct(when,parts);
   parts.mon=1; parts.day=1; parts.hour=0; parts.min=0; parts.sec=0;
   return(StructToTime(parts));
  }
//+------------------------------------------------------------------+
datetime CPerformanceAnalytics::AddMonths(const datetime when,const int months)
  {
   MqlDateTime parts;
   TimeToStruct(when,parts);
   int total=parts.mon-1+months;
   parts.year+=total/12;
   total=total%12;
   if(total<0)
     {
      total+=12;
      parts.year--;
     }
   parts.mon=total+1;
   parts.day=1; parts.hour=0; parts.min=0; parts.sec=0;
   return(StructToTime(parts));
  }
//+------------------------------------------------------------------+
string CPerformanceAnalytics::DurationToString(const int seconds)
  {
   if(seconds<=0)
      return("0s");
   const int hours=seconds/3600;
   const int minutes=(seconds%3600)/60;
   const int rest=seconds%60;
   if(hours>0)
      return(StringFormat("%dh %02dm %02ds",hours,minutes,rest));
   if(minutes>0)
      return(StringFormat("%dm %02ds",minutes,rest));
   return(StringFormat("%ds",rest));
  }
//+------------------------------------------------------------------+
string CPerformanceAnalytics::PeriodToString(const ENUM_SRP_PA_PERIOD period)
  {
   switch(period)
     {
      case SRP_PA_PERIOD_ALL:   return("ALL");
      case SRP_PA_PERIOD_DAY:   return("DAY");
      case SRP_PA_PERIOD_WEEK:  return("WEEK");
      case SRP_PA_PERIOD_MONTH: return("MONTH");
      case SRP_PA_PERIOD_YEAR:  return("YEAR");
     }
   return("?");
  }
//+------------------------------------------------------------------+
string CPerformanceAnalytics::FormatReport(const SAnalyticsReport &report) const
  {
   if(!report.is_valid)
      return(PeriodToString(report.period)+": no trades in range");

   string text=PeriodToString(report.period)+" report "+m_symbol;
   if(report.from>0)
      text+=" from "+TimeToString(report.from,TIME_DATE);
   text+="\n  trades="+IntegerToString(report.total_trades);
   text+=" wins="+IntegerToString(report.wins);
   text+=" losses="+IntegerToString(report.losses);
   text+=" be="+IntegerToString(report.breakeven);
   text+=" winRate="+DoubleToString(report.win_rate,2)+"%";
   text+="\n  net="+DoubleToString(report.net_profit,2);
   text+=" gross+="+DoubleToString(report.gross_profit,2);
   text+=" gross-="+DoubleToString(report.gross_loss,2);
   text+=" commission="+DoubleToString(report.total_commission,2);
   text+=" swap="+DoubleToString(report.total_swap,2);
   text+="\n  profitFactor="+DoubleToString(report.profit_factor,3);
   text+=" expectancy="+DoubleToString(report.expectancy,2);
   text+=" payoff="+DoubleToString(report.payoff_ratio,3);
   text+=" avgR="+DoubleToString(report.average_r_multiple,3);
   text+="\n  sharpe="+DoubleToString(report.sharpe_ratio,3);
   text+=" sortino="+DoubleToString(report.sortino_ratio,3);
   text+=" recovery="+DoubleToString(report.recovery_factor,3);
   text+="\n  avgWin="+DoubleToString(report.average_win,2);
   text+=" avgLoss="+DoubleToString(report.average_loss,2);
   text+=" bestWin="+DoubleToString(report.largest_win,2);
   text+=" worstLoss="+DoubleToString(report.largest_loss,2);
   text+="\n  maxDD="+DoubleToString(report.max_drawdown_money,2);
   text+=" ("+DoubleToString(report.max_drawdown_percent,2)+"%)";
   text+=" peak="+DoubleToString(report.peak_balance,2);
   text+="\n  duration avg="+DurationToString((int)report.average_duration_seconds);
   text+=" longest="+DurationToString(report.longest_duration_seconds);
   text+=" shortest="+DurationToString(report.shortest_duration_seconds);
   text+="\n  streaks: wins="+IntegerToString(report.max_consecutive_wins);
   text+=" losses="+IntegerToString(report.max_consecutive_losses);
   return(text);
  }
//+------------------------------------------------------------------+
string CPerformanceAnalytics::FormatMonthlyTable(void) const
  {
   SAnalyticsReport reports[];
   const int total=MonthlyBreakdown(reports);
   if(total<=0)
      return("monthly report: no closed trades");

   string text="MONTHLY REPORT "+m_symbol;
   text+="\n  period    trades   win%      net       pf     maxDD%";
   for(int i=0;i<total;i++)
     {
      MqlDateTime parts;
      TimeToStruct(reports[i].from,parts);
      text+=StringFormat("\n  %04d-%02d  %6d  %6.2f  %9.2f  %6.2f  %6.2f",
                         parts.year,parts.mon,
                         reports[i].total_trades,
                         reports[i].win_rate,
                         reports[i].net_profit,
                         reports[i].profit_factor,
                         reports[i].max_drawdown_percent);
     }
   return(text);
  }
//+------------------------------------------------------------------+
string CPerformanceAnalytics::FormatYearlyTable(void) const
  {
   SAnalyticsReport reports[];
   const int total=YearlyBreakdown(reports);
   if(total<=0)
      return("yearly report: no closed trades");

   string text="YEARLY REPORT "+m_symbol;
   text+="\n  year    trades   win%      net       pf   sharpe   maxDD%";
   for(int i=0;i<total;i++)
     {
      MqlDateTime parts;
      TimeToStruct(reports[i].from,parts);
      text+=StringFormat("\n  %04d    %6d  %6.2f  %9.2f  %6.2f  %6.2f  %6.2f",
                         parts.year,
                         reports[i].total_trades,
                         reports[i].win_rate,
                         reports[i].net_profit,
                         reports[i].profit_factor,
                         reports[i].sharpe_ratio,
                         reports[i].max_drawdown_percent);
     }
   return(text);
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::ExportTradesCsv(const string relative_path,
                                            const bool common_folder,
                                            const string preamble) const
  {
   if(m_count<=0)
      return(false);
   int flags=FILE_WRITE|FILE_TXT|FILE_ANSI;
   if(common_folder)
      flags|=FILE_COMMON;
   const int handle=FileOpen(relative_path,flags);
   if(handle==INVALID_HANDLE)
      return(false);

   //--- HARNESS v2, FIX 4. Provenance first, then the column header. In that
   //--- order because a reader - human or parser - meets the conditions
   //--- before the columns, and a '#' line above the header is the one shape
   //--- every CSV consumer already knows how to skip.
   if(preamble!="")
      FileWrite(handle,preamble);
   FileWrite(handle,
             "ticket,symbol,side,volume,open_time,close_time,duration_s,"
             "open_price,close_price,gross,commission,swap,net,"
             "risk,r_multiple,balance_after,strategy,exit_reason");
   for(int i=0;i<m_count;i++)
     {
      const int slot=Slot(i);
      if(slot<0)
         continue;
      string row=IntegerToString((long)m_trades[slot].ticket);
      row+=","+m_trades[slot].symbol;
      row+=","+(m_trades[slot].is_buy ? "BUY" : "SELL");
      row+=","+DoubleToString(m_trades[slot].volume,2);
      row+=","+TimeToString(m_trades[slot].open_time,TIME_DATE|TIME_SECONDS);
      row+=","+TimeToString(m_trades[slot].close_time,TIME_DATE|TIME_SECONDS);
      row+=","+IntegerToString(m_trades[slot].duration_seconds);
      row+=","+DoubleToString(m_trades[slot].open_price,_Digits);
      row+=","+DoubleToString(m_trades[slot].close_price,_Digits);
      row+=","+DoubleToString(m_trades[slot].gross_profit,2);
      row+=","+DoubleToString(m_trades[slot].commission,2);
      row+=","+DoubleToString(m_trades[slot].swap,2);
      row+=","+DoubleToString(m_trades[slot].net_profit,2);
      row+=","+DoubleToString(m_trades[slot].risk_amount,2);
      row+=","+DoubleToString(m_trades[slot].r_multiple,3);
      row+=","+DoubleToString(m_trades[slot].balance_after,2);
      row+=","+m_trades[slot].strategy_name;
      row+=","+m_trades[slot].exit_reason;
      FileWrite(handle,row);
     }
   FileFlush(handle);
   FileClose(handle);
   return(true);
  }
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::ExportMonthlyCsv(const string relative_path,
                                             const bool common_folder,
                                             const string preamble) const
  {
   SAnalyticsReport reports[];
   const int total=MonthlyBreakdown(reports);
   if(total<=0)
      return(false);

   int flags=FILE_WRITE|FILE_TXT|FILE_ANSI;
   if(common_folder)
      flags|=FILE_COMMON;
   const int handle=FileOpen(relative_path,flags);
   if(handle==INVALID_HANDLE)
      return(false);

   //--- HARNESS v2, FIX 4. See ExportTradesCsv: same line, same position.
   if(preamble!="")
      FileWrite(handle,preamble);
   FileWrite(handle,
             "year,month,trades,wins,losses,win_rate,net,gross_profit,"
             "gross_loss,profit_factor,expectancy,sharpe,sortino,recovery,"
             "max_dd_money,max_dd_percent,avg_win,avg_loss,avg_duration_s");
   for(int i=0;i<total;i++)
     {
      MqlDateTime parts;
      TimeToStruct(reports[i].from,parts);
      string row=IntegerToString(parts.year);
      row+=","+IntegerToString(parts.mon);
      row+=","+IntegerToString(reports[i].total_trades);
      row+=","+IntegerToString(reports[i].wins);
      row+=","+IntegerToString(reports[i].losses);
      row+=","+DoubleToString(reports[i].win_rate,2);
      row+=","+DoubleToString(reports[i].net_profit,2);
      row+=","+DoubleToString(reports[i].gross_profit,2);
      row+=","+DoubleToString(reports[i].gross_loss,2);
      row+=","+DoubleToString(reports[i].profit_factor,3);
      row+=","+DoubleToString(reports[i].expectancy,2);
      row+=","+DoubleToString(reports[i].sharpe_ratio,3);
      row+=","+DoubleToString(reports[i].sortino_ratio,3);
      row+=","+DoubleToString(reports[i].recovery_factor,3);
      row+=","+DoubleToString(reports[i].max_drawdown_money,2);
      row+=","+DoubleToString(reports[i].max_drawdown_percent,2);
      row+=","+DoubleToString(reports[i].average_win,2);
      row+=","+DoubleToString(reports[i].average_loss,2);
      row+=","+DoubleToString(reports[i].average_duration_seconds,0);
      FileWrite(handle,row);
     }
   FileFlush(handle);
   FileClose(handle);
   return(true);
  }
//+------------------------------------------------------------------+
string CPerformanceAnalytics::Describe(void) const
  {
   string text="CPerformanceAnalytics["+m_symbol+"]";
   text+=" retained="+IntegerToString(m_count);
   text+="/"+IntegerToString(SRP_PA_MAX_TRADES);
   text+=" pushed="+IntegerToString(m_total_pushed);
   text+=" initialBalance="+DoubleToString(m_initial_balance,2);
   text+=" minSample="+IntegerToString(m_min_sample);
   text+=" basis="+(m_use_r_multiples ? "R" : "money");
   return(text);
  }

#endif // SRP_INTERFACE_ANALYTICS_CPERFORMANCEANALYTICS_MQH
//+------------------------------------------------------------------+
