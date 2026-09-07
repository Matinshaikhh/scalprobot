//+------------------------------------------------------------------+
//|                                   COptimizationCriterion.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Optimization : computes the OnTester custom fitness value.                |
//|                                                                  |
//|   RESPONSIBILITY (one only): turn a completed pass's metrics into a single  |
//|   fitness number.                                                        |
//|                                                                  |
//|   WHY A CUSTOM CRITERION IS NOT OPTIONAL                                 |
//|   Optimising on net profit reliably produces a curve-fitted robot: the     |
//|   winner is usually a handful of lucky trades with a catastrophic          |
//|   drawdown. The composite criterion here rewards consistency and           |
//|   penalises the things that destroy live accounts:                        |
//|     * too few trades          -> statistically meaningless, rejected       |
//|     * deep drawdown           -> penalised proportionally                 |
//|     * one dominant trade      -> penalised (concentration risk)           |
//|     * long losing streaks     -> penalised                                |
//|   The result is a fitness that prefers a modest, stable curve over a       |
//|   spectacular fragile one - which is the difference between a product      |
//|   that survives contact with a live account and one that does not.         |
//+------------------------------------------------------------------+
#ifndef SRP_OPTIMIZATION_COPTIMIZATIONCRITERION_MQH
#define SRP_OPTIMIZATION_COPTIMIZATIONCRITERION_MQH

#include "../Core/Types/Structs.mqh"
#include "../Core/Interfaces/ILogger.mqh"

class COptimizationCriterion
  {
private:
   ILogger                        *m_logger;   // borrowed
   ENUM_SRP_OPTIMIZATION_CRITERION m_criterion;
   int                             m_minimum_trades;
   double                          m_drawdown_penalty_weight;
   double                          m_concentration_penalty_weight;
   double                          m_streak_penalty_weight;
   //--- Passes failing the minimum-trade test return this, so the
   //--- optimiser discards them rather than ranking noise.
   double                          m_rejection_value;

   //--- One evaluator per criterion.
   double            ScoreNetProfit(const SPerformanceMetrics &metrics) const;
   double            ScoreProfitFactor(const SPerformanceMetrics &metrics) const;
   double            ScoreExpectancy(const SPerformanceMetrics &metrics) const;
   double            ScoreSharpe(const SPerformanceMetrics &metrics) const;
   double            ScoreRecoveryFactor(const SPerformanceMetrics &metrics) const;
   //--- The recommended default.
   double            ScoreComposite(const SPerformanceMetrics &metrics,
                                    const STradeRecord &records[],
                                    const int count) const;

   //--- Penalty components, each in the range 0..1 where 1 is no penalty.
   double            DrawdownFactor(const SPerformanceMetrics &metrics) const;
   double            ConcentrationFactor(const SPerformanceMetrics &metrics) const;
   double            StreakFactor(const SPerformanceMetrics &metrics) const;

public:
                     COptimizationCriterion(ILogger *logger);
                    ~COptimizationCriterion(void) { }

   void              SetCriterion(const ENUM_SRP_OPTIMIZATION_CRITERION criterion);
   void              SetMinimumTrades(const int trades);
   void              SetPenaltyWeights(const double drawdown,
                                       const double concentration,
                                       const double streak);

   //--- Called from OnTester. Returns the fitness value.
   double            Evaluate(const SPerformanceMetrics &metrics,
                              const STradeRecord &records[],
                              const int count) const;

   //--- Human-readable breakdown, written to the tester log so a user
   //--- can see why one pass outranked another.
   string            Explain(const SPerformanceMetrics &metrics) const;

   //--- The value returned for a rejected pass, so callers can detect it.
   double            RejectionValue(void) const { return(m_rejection_value); }
   int               MinimumTrades(void) const { return(m_minimum_trades); }
   static string     CriterionToString(const ENUM_SRP_OPTIMIZATION_CRITERION c);
  };

#include "../Utilities/CMathUtils.mqh"

//+------------------------------------------------------------------+
COptimizationCriterion::COptimizationCriterion(ILogger *logger)
  : m_logger(logger),
    m_criterion(SRP_CRITERION_CUSTOM_COMPOSITE),
    m_minimum_trades(30),
    m_drawdown_penalty_weight(1.0),
    m_concentration_penalty_weight(1.0),
    m_streak_penalty_weight(1.0),
    //--- Large and negative so a rejected pass sorts below every real
    //--- result, including a genuinely loss-making one.
    m_rejection_value(-1000000.0)
  {
  }
//+------------------------------------------------------------------+
void COptimizationCriterion::SetCriterion(const ENUM_SRP_OPTIMIZATION_CRITERION criterion)
  {
   m_criterion=criterion;
  }
//+------------------------------------------------------------------+
void COptimizationCriterion::SetMinimumTrades(const int trades)
  {
   m_minimum_trades=(trades<1 ? 1 : trades);
  }
//+------------------------------------------------------------------+
void COptimizationCriterion::SetPenaltyWeights(const double drawdown,
                                               const double concentration,
                                               const double streak)
  {
   //--- Clamped rather than rejected: a weight is a dial, and an out of
   //--- range dial should saturate, not abort an optimisation run.
   m_drawdown_penalty_weight=CMathUtils::Clamp(drawdown,0.0,10.0);
   m_concentration_penalty_weight=CMathUtils::Clamp(concentration,0.0,10.0);
   m_streak_penalty_weight=CMathUtils::Clamp(streak,0.0,10.0);
  }
//+------------------------------------------------------------------+
double COptimizationCriterion::Evaluate(const SPerformanceMetrics &metrics,
                                        const STradeRecord &records[],
                                        const int count) const
  {
   //--- THE GATE. A pass with too few trades is noise, and ranking noise
   //--- is how a curve-fitted parameter set wins an optimisation. It is
   //--- rejected before any scoring happens.
   if(metrics.total_trades<m_minimum_trades)
      return(m_rejection_value);

   switch(m_criterion)
     {
      case SRP_CRITERION_NET_PROFIT:      return(ScoreNetProfit(metrics));
      case SRP_CRITERION_PROFIT_FACTOR:   return(ScoreProfitFactor(metrics));
      case SRP_CRITERION_EXPECTANCY:      return(ScoreExpectancy(metrics));
      case SRP_CRITERION_SHARPE_RATIO:    return(ScoreSharpe(metrics));
      case SRP_CRITERION_RECOVERY_FACTOR: return(ScoreRecoveryFactor(metrics));
      default:                            break;
     }
   return(ScoreComposite(metrics,records,count));
  }
//+------------------------------------------------------------------+
double COptimizationCriterion::ScoreNetProfit(const SPerformanceMetrics &metrics) const
  {
   return(metrics.net_profit);
  }
//+------------------------------------------------------------------+
double COptimizationCriterion::ScoreProfitFactor(const SPerformanceMetrics &metrics) const
  {
   //--- A losing set must not be flattered by a high ratio computed on a
   //--- tiny gross loss, so profitability gates the score.
   if(metrics.net_profit<=0.0)
      return(metrics.net_profit);
   return(metrics.profit_factor);
  }
//+------------------------------------------------------------------+
double COptimizationCriterion::ScoreExpectancy(const SPerformanceMetrics &metrics) const
  {
   return(metrics.expectancy);
  }
//+------------------------------------------------------------------+
double COptimizationCriterion::ScoreSharpe(const SPerformanceMetrics &metrics) const
  {
   return(metrics.sharpe_ratio);
  }
//+------------------------------------------------------------------+
double COptimizationCriterion::ScoreRecoveryFactor(const SPerformanceMetrics &metrics) const
  {
   if(metrics.net_profit<=0.0)
      return(metrics.net_profit);
   return(metrics.recovery_factor);
  }
//+------------------------------------------------------------------+
//| THE RECOMMENDED CRITERION.                                          |
//|                                                                  |
//| Base is net profit per unit of drawdown - the return the account     |
//| actually earned for the pain it actually endured. Three multiplicative|
//| penalties then discount the failure modes that make a backtest       |
//| unrepeatable. Multiplicative, not additive, because a pass that is    |
//| bad in two ways should be discounted twice, not once.                |
//+------------------------------------------------------------------+
double COptimizationCriterion::ScoreComposite(const SPerformanceMetrics &metrics,
                                              const STradeRecord &records[],
                                              const int count) const
  {
   //--- A losing pass is returned as its loss. Penalising it further
   //--- would compress all losers together and lose the ordering that
   //--- tells the user how badly each failed.
   if(metrics.net_profit<=0.0)
      return(metrics.net_profit);

   //--- Base: net profit divided by peak drawdown. With no drawdown at
   //--- all the pass is almost certainly too short to be meaningful, so
   //--- the trade count carries it instead of an infinite ratio.
   double base=metrics.net_profit;
   if(metrics.max_drawdown_money>SRP_EPSILON)
      base=metrics.net_profit/metrics.max_drawdown_money;

   const double dd=DrawdownFactor(metrics);
   const double concentration=ConcentrationFactor(metrics);
   const double streak=StreakFactor(metrics);

   double score=base*dd*concentration*streak;

   //--- A modest reward for sample size. sqrt, not linear: going from 30
   //--- to 120 trades should matter, going from 1000 to 4000 much less.
   if(count>0 && metrics.total_trades>0)
      score*=MathSqrt((double)metrics.total_trades/(double)m_minimum_trades);

   return(score);
  }
//+------------------------------------------------------------------+
//| Each factor returns 0..1, where 1 means no penalty. Expressing them  |
//| in one range is what makes them safely multiplicative.               |
//+------------------------------------------------------------------+
double COptimizationCriterion::DrawdownFactor(const SPerformanceMetrics &metrics) const
  {
   //--- Linear decay to zero at 100% drawdown, scaled by the weight.
   //--- A 20% drawdown at weight 1.0 keeps 80% of the score.
   const double dd=CMathUtils::Clamp(metrics.max_drawdown_percent,0.0,100.0);
   const double penalty=(dd/100.0)*m_drawdown_penalty_weight;
   return(CMathUtils::Clamp(1.0-penalty,0.0,1.0));
  }
//+------------------------------------------------------------------+
double COptimizationCriterion::ConcentrationFactor(const SPerformanceMetrics &metrics) const
  {
   //--- CONCENTRATION RISK: if one trade produced most of the profit, the
   //--- result is an accident rather than an edge. Remove the best trade
   //--- and ask whether anything is left.
   if(metrics.net_profit<=SRP_EPSILON || metrics.largest_win<=0.0)
      return(1.0);

   const double share=CMathUtils::SafeDivide(metrics.largest_win,
                                             metrics.net_profit,0.0);
   //--- Up to 25% from one trade is normal for a small sample and is not
   //--- penalised. Beyond that the discount grows with the excess.
   if(share<=0.25)
      return(1.0);
   const double excess=CMathUtils::Clamp(share-0.25,0.0,1.0);
   //--- Divided by 0.75 so a single trade being the ENTIRE profit
   //--- (share 1.0) saturates the penalty exactly.
   const double penalty=(excess/0.75)*m_concentration_penalty_weight;
   return(CMathUtils::Clamp(1.0-penalty,0.0,1.0));
  }
//+------------------------------------------------------------------+
double COptimizationCriterion::StreakFactor(const SPerformanceMetrics &metrics) const
  {
   //--- A long losing streak is what makes a user abandon a profitable
   //--- system, so it is a real cost even when the equity curve recovers.
   if(metrics.max_consecutive_losses<=0 || metrics.total_trades<=0)
      return(1.0);

   const double share=CMathUtils::SafeDivide((double)metrics.max_consecutive_losses,
                                             (double)metrics.total_trades,0.0);
   //--- Streaks up to 10% of all trades are unremarkable.
   if(share<=0.10)
      return(1.0);
   const double excess=CMathUtils::Clamp(share-0.10,0.0,0.9);
   const double penalty=(excess/0.9)*m_streak_penalty_weight;
   return(CMathUtils::Clamp(1.0-penalty,0.0,1.0));
  }
//+------------------------------------------------------------------+
string COptimizationCriterion::Explain(const SPerformanceMetrics &metrics) const
  {
   string text="criterion="+CriterionToString(m_criterion);
   text+=" trades="+IntegerToString(metrics.total_trades);
   text+="/"+IntegerToString(m_minimum_trades)+" required";

   if(metrics.total_trades<m_minimum_trades)
     {
      text+="\n  REJECTED: too few trades to be statistically meaningful, "
            "fitness="+DoubleToString(m_rejection_value,1);
      return(text);
     }

   text+="\n  net="+DoubleToString(metrics.net_profit,2);
   text+=" maxDD="+DoubleToString(metrics.max_drawdown_money,2);
   text+=" ("+DoubleToString(metrics.max_drawdown_percent,2)+"%)";
   text+=" pf="+DoubleToString(metrics.profit_factor,3);
   text+="\n  penalties (1.0 = none):";
   text+=" drawdown="+DoubleToString(DrawdownFactor(metrics),4);
   text+=" concentration="+DoubleToString(ConcentrationFactor(metrics),4);
   text+=" streak="+DoubleToString(StreakFactor(metrics),4);
   text+="\n  largestWin="+DoubleToString(metrics.largest_win,2);
   text+=" share of net="+
         DoubleToString(CMathUtils::SafeDivide(metrics.largest_win,
                                               metrics.net_profit,0.0)*100.0,1)+"%";
   text+=" worstStreak="+IntegerToString(metrics.max_consecutive_losses);

   STradeRecord empty[];
   text+="\n  fitness="+DoubleToString(Evaluate(metrics,empty,
                                                metrics.total_trades),6);
   return(text);
  }
//+------------------------------------------------------------------+
string COptimizationCriterion::CriterionToString(const ENUM_SRP_OPTIMIZATION_CRITERION c)
  {
   switch(c)
     {
      case SRP_CRITERION_NET_PROFIT:       return("NET_PROFIT");
      case SRP_CRITERION_PROFIT_FACTOR:    return("PROFIT_FACTOR");
      case SRP_CRITERION_EXPECTANCY:       return("EXPECTANCY");
      case SRP_CRITERION_SHARPE_RATIO:     return("SHARPE_RATIO");
      case SRP_CRITERION_RECOVERY_FACTOR:  return("RECOVERY_FACTOR");
      case SRP_CRITERION_CUSTOM_COMPOSITE: return("CUSTOM_COMPOSITE");
     }
   return("UNKNOWN");
  }

#endif // SRP_OPTIMIZATION_COPTIMIZATIONCRITERION_MQH
//+------------------------------------------------------------------+
