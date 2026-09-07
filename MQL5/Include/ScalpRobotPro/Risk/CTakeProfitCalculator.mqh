//+------------------------------------------------------------------+
//|                                      CTakeProfitCalculator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : composite take-profit resolution.                              |
//|                                                                  |
//|   Mirrors CStopLossCalculator. The risk-reward mode is special: it      |
//|   needs the already-resolved stop distance, which is why Resolve()      |
//|   accepts it as a parameter. Making that dependency explicit in the    |
//|   signature is better than having this class reach back into the SL    |
//|   calculator and create a cycle between them.                          |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CTAKEPROFITCALCULATOR_MQH
#define SRP_RISK_CTAKEPROFITCALCULATOR_MQH

#include "../Core/Interfaces/IStopLevelCalculator.mqh"
#include "../Core/Interfaces/ILogger.mqh"

class CTakeProfitCalculator
  {
private:
   ILogger              *m_logger;         // borrowed
   ENUM_SRP_TP_MODE      m_mode;
   IStopLevelCalculator *m_fixed;          // OWNED
   IStopLevelCalculator *m_atr;            // OWNED
   double                m_risk_reward_ratio;

   IStopLevelCalculator *Selected(void) const;
   //--- RR mode is computed here rather than in a calculator class,
   //--- because it is derived from the stop rather than from the market.
   bool                  ResolveByRiskReward(const SSymbolSpec &spec,
                                            const ENUM_SRP_SIGNAL_DIRECTION direction,
                                            const double entry_price,
                                            const double stop_distance_points,
                                            double &level_price,
                                            string &explanation) const;

public:
                     CTakeProfitCalculator(ILogger *logger);
                    ~CTakeProfitCalculator(void);

   void              SetMode(const ENUM_SRP_TP_MODE mode);
   void              SetRiskRewardRatio(const double ratio);
   void              SetFixedCalculator(IStopLevelCalculator *calculator);
   void              SetAtrCalculator(IStopLevelCalculator *calculator);

   ENUM_SRP_TP_MODE  Mode(void) const { return(m_mode); }

   bool              Resolve(const SDecisionContext &context,
                             const SSymbolSpec &spec,
                             const ENUM_SRP_SIGNAL_DIRECTION direction,
                             const double entry_price,
                             const double stop_distance_points,
                             double &take_profit_price,
                             string &explanation) const;
  };

#endif // SRP_RISK_CTAKEPROFITCALCULATOR_MQH
//+------------------------------------------------------------------+
