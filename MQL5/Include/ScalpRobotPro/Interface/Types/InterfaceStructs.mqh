//+------------------------------------------------------------------+
//|                                         InterfaceStructs.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   Passive data-transfer objects for Phase 4. Data plus trivial reset    |
//|   helpers only - no business logic.                                   |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_TYPES_STRUCTS_MQH
#define SRP_INTERFACE_TYPES_STRUCTS_MQH

#include "../../Core/Types/Constants.mqh"
#include "../../Core/Types/Structs.mqh"
#include "InterfaceEnums.mqh"

//=== DASHBOARD =====================================================
//+------------------------------------------------------------------+
//| THE UI FIREWALL.                                                  |
//|                                                                  |
//| Every field is a COPY, never a pointer. Widgets receive a const      |
//| reference to this and nothing else, so the dashboard is structurally |
//| incapable of reaching the engine, the executor or a position. A UI   |
//| defect can garble a label but can never move a stop loss.           |
//|                                                                  |
//| It also decouples refresh rates: the engine writes at its own pace,  |
//| the panel repaints on a throttle, and neither waits for the other.   |
//+------------------------------------------------------------------+
struct SDashboardModel
  {
   //--- Account.
   double            balance;
   double            equity;
   double            margin_used;
   double            margin_free;
   double            margin_level;
   double            floating_profit;
   string            currency;
   //--- Period results.
   double            today_profit;
   double            week_profit;
   double            month_profit;
   double            today_profit_percent;
   //--- Performance.
   double            win_rate;
   double            profit_factor;
   double            average_rr;
   int               total_trades;
   //--- Execution quality.
   double            spread_points;
   double            latency_ms;
   double            average_slippage_points;
   //--- Context.
   string            session_text;
   string            news_countdown;
   string            strategy_text;
   string            signal_text;
   ENUM_SRP_UI_TONE  signal_tone;
   bool              news_paused;
   bool              session_blocked;
   //--- Exposure.
   int               open_trades;
   double            risk_percent;
   double            lot_size;
   double            total_volume;
   //--- Engine state.
   string            engine_state;
   string            health_text;
   ENUM_SRP_UI_TONE  health_tone;
   //--- Identity.
   string            symbol;
   string            product_version;
   datetime          updated_at;
   bool              is_valid;

                     SDashboardModel(void) { Reset(); }
   void              Reset(void)
     {
      balance=0.0; equity=0.0; margin_used=0.0; margin_free=0.0;
      margin_level=0.0; floating_profit=0.0; currency="";
      today_profit=0.0; week_profit=0.0; month_profit=0.0;
      today_profit_percent=0.0;
      win_rate=0.0; profit_factor=0.0; average_rr=0.0; total_trades=0;
      spread_points=0.0; latency_ms=0.0; average_slippage_points=0.0;
      session_text=""; news_countdown=""; strategy_text="";
      signal_text="WAITING"; signal_tone=SRP_UI_TONE_MUTED;
      news_paused=false; session_blocked=false;
      open_trades=0; risk_percent=0.0; lot_size=0.0; total_volume=0.0;
      engine_state=""; health_text=""; health_tone=SRP_UI_TONE_NEUTRAL;
      symbol=""; product_version=""; updated_at=0;
      is_valid=false;
     }
  };

//=== TRADE MANAGER =================================================
//+------------------------------------------------------------------+
//| One position as the trade manager sees it, plus the tracking state   |
//| the manager itself maintains (peak price, applied stages).           |
//+------------------------------------------------------------------+
struct SManagedPosition
  {
   ulong             ticket;
   string            symbol;
   long              magic;
   bool              is_buy;
   double            volume;
   double            initial_volume;
   double            open_price;
   double            current_price;
   double            stop_loss;
   double            take_profit;
   double            profit_money;
   double            profit_points;
   datetime          open_time;
   int               age_seconds;
   //--- Manager-maintained tracking. Peak is required for profit-lock
   //--- and for an ATR exit measured from the best excursion.
   double            peak_price;
   double            peak_profit_points;
   bool              break_even_done;
   bool              scaled_in;
   int               scale_out_count;
   bool              trailing_active;

                     SManagedPosition(void) { Reset(); }
   void              Reset(void)
     {
      ticket=SRP_INVALID_TICKET; symbol=""; magic=0;
      is_buy=true; volume=0.0; initial_volume=0.0;
      open_price=0.0; current_price=0.0;
      stop_loss=0.0; take_profit=0.0;
      profit_money=0.0; profit_points=0.0;
      open_time=0; age_seconds=0;
      peak_price=0.0; peak_profit_points=0.0;
      break_even_done=false; scaled_in=false;
      scale_out_count=0; trailing_active=false;
     }
  };

//+------------------------------------------------------------------+
//| An intent produced by the trade manager. It DECIDES; the Phase 1     |
//| trade engine executes. Keeping them apart is what lets all of this   |
//| be verified without a broker connection.                            |
//+------------------------------------------------------------------+
struct STradeIntent
  {
   ENUM_SRP_TM_ACTION  action;
   ENUM_SRP_TM_TRIGGER trigger;
   ulong               ticket;
   double              new_stop;
   double              new_target;
   double              volume;          // scale in/out amount
   string              reason;
   double              urgency;         // 0..1, for ordering competing intents

                     STradeIntent(void) { Reset(); }
   void              Reset(void)
     {
      action=SRP_TM_NONE;
      trigger=SRP_TM_TRIGGER_NONE;
      ticket=SRP_INVALID_TICKET;
      new_stop=0.0; new_target=0.0; volume=0.0;
      reason=""; urgency=0.0;
     }
   bool              IsActionable(void) const { return(action!=SRP_TM_NONE); }
  };

//=== LOGGING =======================================================
//+------------------------------------------------------------------+
//| One structured log record. Fields are explicit rather than a single  |
//| formatted string so the CSV writer can emit real columns.           |
//+------------------------------------------------------------------+
struct SLogRecord
  {
   ENUM_SRP_LOG4_CHANNEL channel;
   datetime              timestamp;
   ulong                 timestamp_ms;
   string                context;
   string                message;
   //--- Optional numeric payload, used by trade and performance rows.
   ulong                 ticket;
   double                value_a;
   double                value_b;
   double                value_c;

                     SLogRecord(void) { Reset(); }
   void              Reset(void)
     {
      channel=SRP_LOG4_ERRORS;
      timestamp=0; timestamp_ms=0;
      context=""; message="";
      ticket=SRP_INVALID_TICKET;
      value_a=0.0; value_b=0.0; value_c=0.0;
     }
  };

//=== ANALYTICS =====================================================
//+------------------------------------------------------------------+
//| One closed trade. The atomic input of every analytic.               |
//+------------------------------------------------------------------+
struct SClosedTrade
  {
   ulong             ticket;
   string            symbol;
   bool              is_buy;
   double            volume;
   double            open_price;
   double            close_price;
   datetime          open_time;
   datetime          close_time;
   int               duration_seconds;
   double            gross_profit;
   double            commission;
   double            swap;
   double            net_profit;
   double            risk_amount;
   double            r_multiple;
   double            balance_after;
   string            strategy_name;
   string            exit_reason;
   //=== HARNESS v2: EXECUTION QUALITY ON THE EXIT ====================
   //--- The EA measured slippage only on orders IT sent. Most scalp exits
   //--- are not EA-sent: the broker fires the stop or the target. Those
   //--- fills were therefore assumed perfect, which is the single most
   //--- flattering assumption a scalping backtest can make - the whole
   //--- edge lives inside a few points.
   //---
   //--- close_reason is the BROKER's own account of why the position went
   //--- (ENUM_DEAL_REASON), not a parse of the comment string.
   //--- exit_slippage_points is signed so that POSITIVE ALWAYS MEANS WORSE
   //--- FOR THE ACCOUNT, for longs and shorts alike, on stops and targets
   //--- alike. Zero on OHLC-modelled runs by construction, which is itself
   //--- the diagnostic.
   int               close_reason;             // ENUM_DEAL_REASON as int
   bool              server_side_exit;         // broker fired SL or TP
   double            exit_trigger_price;       // the SL/TP that fired
   double            exit_slippage_points;     // + = adverse
   double            exit_slippage_money;      // + = cost to the account

                     SClosedTrade(void) { Reset(); }
   void              Reset(void)
     {
      ticket=SRP_INVALID_TICKET; symbol=""; is_buy=true;
      volume=0.0; open_price=0.0; close_price=0.0;
      open_time=0; close_time=0; duration_seconds=0;
      gross_profit=0.0; commission=0.0; swap=0.0; net_profit=0.0;
      risk_amount=0.0; r_multiple=0.0; balance_after=0.0;
      strategy_name=""; exit_reason="";
      close_reason=-1; server_side_exit=false;
      exit_trigger_price=0.0; exit_slippage_points=0.0;
      exit_slippage_money=0.0;
     }
   bool              IsWin(void) const { return(net_profit>SRP_EPSILON); }
   bool              IsLoss(void) const { return(net_profit<-SRP_EPSILON); }
  };

//+------------------------------------------------------------------+
//| Computed analytics for one period.                                 |
//+------------------------------------------------------------------+
struct SAnalyticsReport
  {
   ENUM_SRP_PA_PERIOD period;
   datetime          from;
   datetime          to;
   //--- Counts.
   int               total_trades;
   int               wins;
   int               losses;
   int               breakeven;
   double            win_rate;
   //--- Money.
   double            gross_profit;
   double            gross_loss;
   double            net_profit;
   double            average_win;
   double            average_loss;
   double            largest_win;
   double            largest_loss;
   double            total_commission;
   double            total_swap;
   //--- Ratios.
   double            profit_factor;
   double            expectancy;
   double            payoff_ratio;
   double            sharpe_ratio;
   double            sortino_ratio;
   double            recovery_factor;
   double            average_r_multiple;
   //--- Drawdown.
   double            max_drawdown_money;
   double            max_drawdown_percent;
   double            peak_balance;
   //--- Duration.
   double            average_duration_seconds;
   int               longest_duration_seconds;
   int               shortest_duration_seconds;
   //--- Streaks.
   int               max_consecutive_wins;
   int               max_consecutive_losses;
   bool              is_valid;

                     SAnalyticsReport(void) { Reset(); }
   void              Reset(void)
     {
      period=SRP_PA_PERIOD_ALL; from=0; to=0;
      total_trades=0; wins=0; losses=0; breakeven=0; win_rate=0.0;
      gross_profit=0.0; gross_loss=0.0; net_profit=0.0;
      average_win=0.0; average_loss=0.0;
      largest_win=0.0; largest_loss=0.0;
      total_commission=0.0; total_swap=0.0;
      profit_factor=0.0; expectancy=0.0; payoff_ratio=0.0;
      sharpe_ratio=0.0; sortino_ratio=0.0; recovery_factor=0.0;
      average_r_multiple=0.0;
      max_drawdown_money=0.0; max_drawdown_percent=0.0; peak_balance=0.0;
      average_duration_seconds=0.0;
      longest_duration_seconds=0; shortest_duration_seconds=0;
      max_consecutive_wins=0; max_consecutive_losses=0;
      is_valid=false;
     }
  };

#endif // SRP_INTERFACE_TYPES_STRUCTS_MQH
//+------------------------------------------------------------------+
