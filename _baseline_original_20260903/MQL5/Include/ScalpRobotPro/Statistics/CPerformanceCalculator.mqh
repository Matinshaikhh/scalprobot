//+------------------------------------------------------------------+
//|                                     CPerformanceCalculator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Statistics : pure metric arithmetic.                                    |
//|                                                                  |
//|   RESPONSIBILITY (one only): compute metrics from an array of trade        |
//|   records. It holds no state, performs no IO, and subscribes to nothing.   |
//|                                                                  |
//|   Being pure is the point: every formula here is independently             |
//|   verifiable against a known trade set, which matters because these        |
//|   numbers are what a customer judges the product by and what the           |
//|   optimiser optimises against.                                           |
//+------------------------------------------------------------------+
#ifndef SRP_STATISTICS_CPERFORMANCECALCULATOR_MQH
#define SRP_STATISTICS_CPERFORMANCECALCULATOR_MQH

#include "../Core/Types/Structs.mqh"

class CPerformanceCalculator
  {
public:
   //--- Fills every field of SPerformanceMetrics in one pass where
   //--- possible, so a long history does not cost repeated traversals.
   static void       Compute(const STradeRecord &records[],
                             const int count,
                             SPerformanceMetrics &metrics);

   //--- Individual metrics, exposed for targeted use and for testing.
   static double     ProfitFactor(const double gross_profit,
                                  const double gross_loss);
   static double     Expectancy(const int total_trades,
                                const double net_profit);
   static double     PayoffRatio(const double average_win,
                                 const double average_loss);
   static double     WinRate(const int wins,const int total);
   static double     RecoveryFactor(const double net_profit,
                                    const double max_drawdown);

   //--- Risk-adjusted returns, computed from the per-trade return series.
   static double     SharpeRatio(const double &returns[],
                                 const double risk_free_rate=0.0);
   static double     SortinoRatio(const double &returns[],
                                  const double target_return=0.0);

   //--- Drawdown is computed from the balance curve rather than from
   //--- individual results, because consecutive losses compound.
   static void       ComputeDrawdown(const STradeRecord &records[],
                                     const int count,
                                     double &max_drawdown_money,
                                     double &max_drawdown_percent);

   //--- Streaks.
   static void       ComputeStreaks(const STradeRecord &records[],
                                    const int count,
                                    int &max_consecutive_wins,
                                    int &max_consecutive_losses,
                                    int &current_streak);

   //--- R-multiple: profit expressed in units of initial risk. The most
   //--- meaningful cross-instrument measure of a scalper's edge.
   static double     AverageRMultiple(const STradeRecord &records[],
                                      const int count);

   //--- Extracts the per-trade return series the ratio functions need.
   static void       ExtractReturns(const STradeRecord &records[],
                                    const int count,
                                    double &returns[]);
  };

#endif // SRP_STATISTICS_CPERFORMANCECALCULATOR_MQH
//+------------------------------------------------------------------+
