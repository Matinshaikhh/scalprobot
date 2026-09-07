//+------------------------------------------------------------------+
//|                                           CPositionSizers.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   The six sizing models. Each is a separate class implementing one     |
//|   policy - the GoF Strategy pattern - so a new model is a new class    |
//|   rather than another branch in a growing switch.                     |
//|                                                                  |
//|   Every model returns a RAW volume. Broker normalisation (step, min,   |
//|   max, margin) is CRiskEngine's job, which keeps each model pure       |
//|   arithmetic and independently verifiable.                            |
//|                                                                  |
//|   A CRITICAL SHARED RULE                                             |
//|   Models that derive volume from risk REQUIRE a stop distance. Asked   |
//|   to size without one they return 0 rather than silently falling back  |
//|   to a fixed lot: quietly abandoning the user's stated risk contract   |
//|   is worse than refusing the trade.                                   |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_RISK_CPOSITIONSIZERS_MQH
#define SRP_INTELLIGENCE_RISK_CPOSITIONSIZERS_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "../Types/IntelligenceStructs.mqh"

//+------------------------------------------------------------------+
//| Everything a sizer needs, gathered once by the caller. Passing one  |
//| context keeps every sizer signature identical and stable.           |
//+------------------------------------------------------------------+
struct SSizingContext
  {
   double            balance;
   double            equity;
   double            free_margin;
   double            peak_equity;
   //--- Instrument facts.
   double            point;
   double            tick_size;
   double            tick_value;
   double            volume_min;
   double            volume_max;
   double            volume_step;
   //--- Trade specifics.
   double            stop_distance_points;
   double            atr_value;
   //--- Realised performance, for Kelly and dynamic sizing.
   int               total_trades;
   int               winning_trades;
   double            gross_profit;
   double            gross_loss;
   int               consecutive_losses;
   double            current_drawdown_percent;

                     SSizingContext(void) { Reset(); }
   void              Reset(void)
     {
      balance=0.0; equity=0.0; free_margin=0.0; peak_equity=0.0;
      point=0.0; tick_size=0.0; tick_value=0.0;
      broker_money_per_lot=0.0;
      volume_min=0.0; volume_max=0.0; volume_step=0.0;
      stop_distance_points=0.0; atr_value=0.0;
      total_trades=0; winning_trades=0;
      gross_profit=0.0; gross_loss=0.0;
      consecutive_losses=0; current_drawdown_percent=0.0;
     }
   //--- Authoritative money-per-lot for the current stop, supplied by the
   //--- risk engine from the terminal's own OrderCalcProfit. Zero means
   //--- "unavailable, derive it".
   double            broker_money_per_lot;

   //--- Money lost per lot if the stop is hit. The single conversion every
   //--- risk-based model depends on, so it lives here once.
   //---
   //--- WHY THE BROKER FIGURE WINS WHEN AVAILABLE.
   //--- The tick arithmetic below is textbook correct and still produced a
   //--- 10x under-estimate on gold. On this broker XAUUSD reports
   //--- tick_size 0.01 with tick_value 0.10, yet the contract is 100 oz,
   //--- so a 0.01 move is really worth 1.00 per lot. Trusting tick_value
   //--- sized every gold trade TEN TIMES too large: a measured backtest
   //--- risked 5.01% on a position configured for 0.5% and tripped the
   //--- daily loss guard on a single trade.
   //---
   //--- OrderCalcProfit is the terminal's own answer, computed with the
   //--- same code that will price the real fill, so it cannot disagree
   //--- with the account. The tick math is kept as the fallback for the
   //--- case where the call fails.
   double            MoneyPerLotAtStop(void) const
     {
      if(stop_distance_points<=0.0)
         return(0.0);
      if(broker_money_per_lot>0.0)
         return(broker_money_per_lot);
      if(tick_size<=0.0 || tick_value<=0.0)
         return(0.0);
      const double price_distance=stop_distance_points*point;
      const double ticks=price_distance/tick_size;
      return(ticks*tick_value);
     }
  };

//+------------------------------------------------------------------+
//| Abstract sizer. Parentless by design: a sizer is a stateless          |
//| calculator with nothing to initialise or release.                    |
//+------------------------------------------------------------------+
class CSizerBase
  {
protected:
   ILogger          *m_logger;            // borrowed
   string            m_name;

public:
                     CSizerBase(const string name,ILogger *logger)
     : m_logger(logger),m_name(name) { }
   virtual          ~CSizerBase(void) { }

   virtual ENUM_SRP_SIZING_MODEL Model(void)=0;
   //--- Returns raw, unnormalised volume. 0 means "cannot size".
   virtual double    Calculate(const SSizingContext &context,
                               string &explanation)=0;
   string            Name(void) const { return(m_name); }
  };

//+------------------------------------------------------------------+
//| FIXED LOT - constant volume.                                        |
//+------------------------------------------------------------------+
class CFixedLotModel : public CSizerBase
  {
private:
   double            m_lot;
public:
                     CFixedLotModel(const double lot,ILogger *logger)
     : CSizerBase("FixedLot",logger),m_lot(lot>0.0 ? lot : 0.01) { }

   void              SetLot(const double lot) { if(lot>0.0) m_lot=lot; }

   virtual ENUM_SRP_SIZING_MODEL Model(void) override { return(SRP_SIZING_FIXED_LOT); }
   virtual double    Calculate(const SSizingContext &context,
                               string &explanation) override
     {
      explanation="fixed lot "+DoubleToString(m_lot,2);
      return(m_lot);
     }
  };

//+------------------------------------------------------------------+
//| RISK PERCENT - risk a fixed % of capital per trade.                  |
//+------------------------------------------------------------------+
class CRiskPercentModel : public CSizerBase
  {
private:
   double                m_percent;
   ENUM_SRP_CAPITAL_BASE m_base;

   double            Capital(const SSizingContext &context) const
     {
      switch(m_base)
        {
         case SRP_CAPITAL_EQUITY:      return(context.equity);
         case SRP_CAPITAL_FREE_MARGIN: return(context.free_margin);
         //--- High-water mark is the most conservative reference: it does
         //--- not let a drawdown quietly shrink the risk denominator.
         case SRP_CAPITAL_HIGH_WATER_MARK:
            return(context.peak_equity>0.0 ? context.peak_equity : context.equity);
        }
      return(context.balance);
     }

public:
                     CRiskPercentModel(const double percent,
                                       const ENUM_SRP_CAPITAL_BASE base,
                                       ILogger *logger)
     : CSizerBase("RiskPercent",logger),
       m_percent(percent>0.0 ? percent : 1.0),
       m_base(base) { }

   void              SetPercent(const double percent)
     { if(percent>0.0) m_percent=percent; }
   void              SetBase(const ENUM_SRP_CAPITAL_BASE base) { m_base=base; }

   virtual ENUM_SRP_SIZING_MODEL Model(void) override
     { return(SRP_SIZING_RISK_PERCENT); }

   virtual double    Calculate(const SSizingContext &context,
                               string &explanation) override
     {
      //--- REQUIRES a stop. Without one there is no risk to size against.
      const double money_per_lot=context.MoneyPerLotAtStop();
      if(money_per_lot<=0.0)
        {
         explanation="risk-percent sizing requires a stop distance";
         return(0.0);
        }
      const double capital=Capital(context);
      if(capital<=0.0)
        {
         explanation="capital base is zero";
         return(0.0);
        }
      const double risk_money=capital*m_percent/100.0;
      const double volume=risk_money/money_per_lot;
      explanation=StringFormat("risk %.2f%% of %.2f = %.2f money / %.2f per lot",
                               m_percent,capital,risk_money,money_per_lot);
      return(volume);
     }
  };

//+------------------------------------------------------------------+
//| AUTO LOT - one lot step per N currency units of capital.            |
//|                                                                  |
//| Scales with the account but ignores the stop, so exposure grows      |
//| linearly with capital rather than being risk-normalised. Simple and   |
//| predictable, which is why many users prefer it.                      |
//+------------------------------------------------------------------+
class CAutoLotModel : public CSizerBase
  {
private:
   double                m_capital_per_step;
   double                m_lot_per_step;
   ENUM_SRP_CAPITAL_BASE m_base;
public:
                     CAutoLotModel(const double capital_per_step,
                                   const double lot_per_step,
                                   ILogger *logger)
     : CSizerBase("AutoLot",logger),
       m_capital_per_step(capital_per_step>0.0 ? capital_per_step : 1000.0),
       m_lot_per_step(lot_per_step>0.0 ? lot_per_step : 0.01),
       m_base(SRP_CAPITAL_BALANCE) { }

   void              SetRatio(const double capital_per_step,const double lot_per_step)
     {
      if(capital_per_step>0.0) m_capital_per_step=capital_per_step;
      if(lot_per_step>0.0)     m_lot_per_step=lot_per_step;
     }
   void              SetBase(const ENUM_SRP_CAPITAL_BASE base) { m_base=base; }

   virtual ENUM_SRP_SIZING_MODEL Model(void) override { return(SRP_SIZING_AUTO_LOT); }

   virtual double    Calculate(const SSizingContext &context,
                               string &explanation) override
     {
      const double capital=(m_base==SRP_CAPITAL_EQUITY ? context.equity
                                                       : context.balance);
      if(capital<=0.0)
        {
         explanation="capital base is zero";
         return(0.0);
        }
      const double volume=(capital/m_capital_per_step)*m_lot_per_step;
      explanation=StringFormat("auto lot: %.2f capital / %.2f per %.2f lot",
                               capital,m_capital_per_step,m_lot_per_step);
      return(volume);
     }
  };

//+------------------------------------------------------------------+
//| KELLY CRITERION - optimal fraction from the realised edge.           |
//|                                                                  |
//|   f* = W - (1 - W) / R    where W = win rate, R = payoff ratio        |
//|                                                                  |
//| WHY THIS IS FRACTIONALLY SCALED AND CAPPED                           |
//| Full Kelly maximises long-run growth but produces brutal drawdowns   |
//| and assumes the measured edge is the TRUE edge. On a small sample it  |
//| is not, so full Kelly routinely over-bets. This implementation:      |
//|   * refuses to size until a minimum sample exists                    |
//|   * applies a fraction (default 25%) of the Kelly result             |
//|   * hard-caps the resulting risk percentage                          |
//|   * returns 0 when the edge is negative, rather than betting against  |
//|     the strategy                                                    |
//+------------------------------------------------------------------+
class CKellyModel : public CSizerBase
  {
private:
   int               m_min_trades;
   double            m_kelly_fraction;
   double            m_max_risk_percent;
   ENUM_SRP_CAPITAL_BASE m_base;
public:
                     CKellyModel(ILogger *logger,
                                 const int min_trades=30,
                                 const double kelly_fraction=0.25,
                                 const double max_risk_percent=2.0)
     : CSizerBase("Kelly",logger),
       m_min_trades(min_trades<10 ? 10 : min_trades),
       m_kelly_fraction(kelly_fraction>0.0 && kelly_fraction<=1.0
                        ? kelly_fraction : 0.25),
       m_max_risk_percent(max_risk_percent>0.0 ? max_risk_percent : 2.0),
       m_base(SRP_CAPITAL_EQUITY) { }

   void              SetMinTrades(const int trades)
     { if(trades>=10) m_min_trades=trades; }
   void              SetKellyFraction(const double fraction)
     { if(fraction>0.0 && fraction<=1.0) m_kelly_fraction=fraction; }
   void              SetMaxRiskPercent(const double percent)
     { if(percent>0.0) m_max_risk_percent=percent; }

   virtual ENUM_SRP_SIZING_MODEL Model(void) override { return(SRP_SIZING_KELLY); }

   virtual double    Calculate(const SSizingContext &context,
                               string &explanation) override
     {
      //--- SAMPLE GATE. Kelly on a handful of trades is noise amplified.
      if(context.total_trades<m_min_trades)
        {
         explanation=StringFormat("Kelly needs %d trades, have %d",
                                  m_min_trades,context.total_trades);
         return(0.0);
        }
      const double money_per_lot=context.MoneyPerLotAtStop();
      if(money_per_lot<=0.0)
        {
         explanation="Kelly sizing requires a stop distance";
         return(0.0);
        }

      const double win_rate=(double)context.winning_trades/
                            (double)context.total_trades;
      const int losing_trades=context.total_trades-context.winning_trades;
      if(losing_trades<=0)
        {
         //--- No losses yet means R is undefined. Rather than assume an
         //--- infinite edge, fall back to the risk cap.
         explanation="no losing trades yet; using max risk cap";
         const double capital=(m_base==SRP_CAPITAL_EQUITY ? context.equity
                                                          : context.balance);
         return(capital*m_max_risk_percent/100.0/money_per_lot);
        }

      const double average_win=CMathUtils::SafeDivide(context.gross_profit,
                                                      (double)context.winning_trades,0.0);
      const double average_loss=CMathUtils::SafeDivide(MathAbs(context.gross_loss),
                                                       (double)losing_trades,0.0);
      if(average_loss<=0.0 || average_win<=0.0)
        {
         explanation="cannot compute payoff ratio";
         return(0.0);
        }

      const double payoff=average_win/average_loss;
      //--- The Kelly formula.
      const double kelly=win_rate-((1.0-win_rate)/payoff);

      //--- NEGATIVE EDGE. The honest response is not to trade, not to
      //--- reverse the bet.
      if(kelly<=0.0)
        {
         explanation=StringFormat("Kelly negative (%.3f): win=%.1f%% payoff=%.2f",
                                  kelly,win_rate*100.0,payoff);
         return(0.0);
        }

      //--- Fractional Kelly, then a hard cap.
      double risk_percent=kelly*m_kelly_fraction*100.0;
      risk_percent=CMathUtils::Clamp(risk_percent,0.0,m_max_risk_percent);

      const double capital=(m_base==SRP_CAPITAL_EQUITY ? context.equity
                                                       : context.balance);
      if(capital<=0.0)
        {
         explanation="capital base is zero";
         return(0.0);
        }
      const double volume=capital*risk_percent/100.0/money_per_lot;
      explanation=StringFormat("Kelly %.3f x %.2f = %.2f%% risk "
                               "(win=%.1f%% payoff=%.2f n=%d)",
                               kelly,m_kelly_fraction,risk_percent,
                               win_rate*100.0,payoff,context.total_trades);
      return(volume);
     }
  };

//+------------------------------------------------------------------+
//| ATR POSITION SIZING - volatility-normalised volume.                 |
//|                                                                  |
//| Targets constant risk rather than constant size: as ATR expands the   |
//| volume shrinks, so a quiet session and a volatile session put the     |
//| same money at risk. This is what stops a gold scalper's equity curve  |
//| being dominated by a handful of high-volatility days.                 |
//+------------------------------------------------------------------+
class CAtrSizingModel : public CSizerBase
  {
private:
   double            m_risk_percent;
   double            m_atr_multiple;
   ENUM_SRP_CAPITAL_BASE m_base;
public:
                     CAtrSizingModel(const double risk_percent,
                                     const double atr_multiple,
                                     ILogger *logger)
     : CSizerBase("AtrSizing",logger),
       m_risk_percent(risk_percent>0.0 ? risk_percent : 1.0),
       m_atr_multiple(atr_multiple>0.0 ? atr_multiple : 2.0),
       m_base(SRP_CAPITAL_EQUITY) { }

   void              SetRiskPercent(const double percent)
     { if(percent>0.0) m_risk_percent=percent; }
   void              SetAtrMultiple(const double multiple)
     { if(multiple>0.0) m_atr_multiple=multiple; }

   virtual ENUM_SRP_SIZING_MODEL Model(void) override { return(SRP_SIZING_ATR); }

   virtual double    Calculate(const SSizingContext &context,
                               string &explanation) override
     {
      if(context.atr_value<=0.0)
        {
         explanation="ATR sizing requires a valid ATR value";
         return(0.0);
        }
      if(context.point<=0.0 || context.tick_size<=0.0 || context.tick_value<=0.0)
        {
         explanation="incomplete instrument specification";
         return(0.0);
        }

      //--- Derive the stop distance from ATR rather than using the
      //--- supplied one: that is the whole point of this model.
      const double stop_price_distance=context.atr_value*m_atr_multiple;
      const double ticks=stop_price_distance/context.tick_size;
      const double money_per_lot=ticks*context.tick_value;
      if(money_per_lot<=0.0)
        {
         explanation="computed money-per-lot is zero";
         return(0.0);
        }

      const double capital=(m_base==SRP_CAPITAL_EQUITY ? context.equity
                                                       : context.balance);
      if(capital<=0.0)
        {
         explanation="capital base is zero";
         return(0.0);
        }
      const double risk_money=capital*m_risk_percent/100.0;
      const double volume=risk_money/money_per_lot;
      explanation=StringFormat("ATR sizing: %.2f x %.1f ATR stop, risk %.2f%%",
                               context.atr_value,m_atr_multiple,m_risk_percent);
      return(volume);
     }
  };

//+------------------------------------------------------------------+
//| DYNAMIC POSITION SIZE - performance-adaptive.                        |
//|                                                                  |
//| Starts from a base risk percentage and adjusts it by recent results:  |
//|   * shrinks after consecutive losses (anti-martingale)                |
//|   * shrinks while in drawdown                                        |
//|   * optionally grows modestly during a winning run                    |
//|                                                                  |
//| Anti-martingale by default and deliberately: increasing size after    |
//| losses is the fastest known route to a blown account, so this class   |
//| will not do it.                                                     |
//+------------------------------------------------------------------+
class CDynamicSizingModel : public CSizerBase
  {
private:
   double            m_base_percent;
   double            m_min_percent;
   double            m_max_percent;
   //--- Reduction applied per consecutive loss, as a multiplier.
   double            m_loss_reduction;
   int               m_loss_threshold;
   //--- Drawdown scaling.
   double            m_drawdown_trigger_percent;
   double            m_drawdown_reduction;
   //--- Optional upward scaling on a winning streak.
   bool              m_scale_up_on_wins;
   double            m_win_increase;
   ENUM_SRP_CAPITAL_BASE m_base;

public:
                     CDynamicSizingModel(const double base_percent,ILogger *logger)
     : CSizerBase("DynamicSizing",logger),
       m_base_percent(base_percent>0.0 ? base_percent : 1.0),
       m_min_percent(0.1),
       m_max_percent(2.0),
       m_loss_reduction(0.5),
       m_loss_threshold(2),
       m_drawdown_trigger_percent(5.0),
       m_drawdown_reduction(0.5),
       m_scale_up_on_wins(false),
       m_win_increase(1.2),
       m_base(SRP_CAPITAL_EQUITY) { }

   void              SetBounds(const double min_percent,const double max_percent)
     {
      if(min_percent>0.0) m_min_percent=min_percent;
      if(max_percent>=min_percent) m_max_percent=max_percent;
     }
   void              SetLossReduction(const int threshold,const double multiplier)
     {
      if(threshold>=1) m_loss_threshold=threshold;
      if(multiplier>0.0 && multiplier<=1.0) m_loss_reduction=multiplier;
     }
   void              SetDrawdownReduction(const double trigger_percent,
                                          const double multiplier)
     {
      if(trigger_percent>0.0) m_drawdown_trigger_percent=trigger_percent;
      if(multiplier>0.0 && multiplier<=1.0) m_drawdown_reduction=multiplier;
     }
   void              SetScaleUpOnWins(const bool enabled,const double multiplier)
     {
      m_scale_up_on_wins=enabled;
      if(multiplier>=1.0) m_win_increase=multiplier;
     }

   virtual ENUM_SRP_SIZING_MODEL Model(void) override { return(SRP_SIZING_DYNAMIC); }

   virtual double    Calculate(const SSizingContext &context,
                               string &explanation) override
     {
      const double money_per_lot=context.MoneyPerLotAtStop();
      if(money_per_lot<=0.0)
        {
         explanation="dynamic sizing requires a stop distance";
         return(0.0);
        }

      double percent=m_base_percent;
      string adjustments="";

      //--- ANTI-MARTINGALE: shrink after a losing run.
      if(context.consecutive_losses>=m_loss_threshold)
        {
         percent*=m_loss_reduction;
         adjustments+=StringFormat(" -losses(%d)",context.consecutive_losses);
        }

      //--- Shrink while in drawdown: preserve capital when the strategy
      //--- and the market disagree.
      if(context.current_drawdown_percent>=m_drawdown_trigger_percent)
        {
         percent*=m_drawdown_reduction;
         adjustments+=StringFormat(" -drawdown(%.1f%%)",
                                   context.current_drawdown_percent);
        }

      //--- Optional modest scale-up on a clean run.
      if(m_scale_up_on_wins && context.consecutive_losses==0 &&
         context.total_trades>0 && context.current_drawdown_percent<1.0)
        {
         percent*=m_win_increase;
         adjustments+=" +winstreak";
        }

      percent=CMathUtils::Clamp(percent,m_min_percent,m_max_percent);

      const double capital=(m_base==SRP_CAPITAL_EQUITY ? context.equity
                                                       : context.balance);
      if(capital<=0.0)
        {
         explanation="capital base is zero";
         return(0.0);
        }
      const double volume=capital*percent/100.0/money_per_lot;
      explanation=StringFormat("dynamic %.2f%% (base %.2f%%)%s",
                               percent,m_base_percent,adjustments);
      return(volume);
     }
  };

#endif // SRP_INTELLIGENCE_RISK_CPOSITIONSIZERS_MQH
//+------------------------------------------------------------------+
