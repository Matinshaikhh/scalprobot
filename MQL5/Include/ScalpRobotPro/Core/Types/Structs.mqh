//+------------------------------------------------------------------+
//|                                                      Structs.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Types : passive data-transfer objects.                    |
//|   These structs carry state BETWEEN modules. They contain no     |
//|   business logic - only data plus trivial reset/validity helpers |
//|   so that no module ever reads an uninitialised field.           |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_TYPES_STRUCTS_MQH
#define SRP_CORE_TYPES_STRUCTS_MQH

#include "Constants.mqh"
#include "Enums.mqh"

//+------------------------------------------------------------------+
//| Immutable description of the traded instrument. Resolved once at |
//| init by CSymbolInfoProvider so no module calls SymbolInfo* ad hoc |
//+------------------------------------------------------------------+
struct SSymbolSpec
  {
   string            symbol;
   int               digits;
   double            point;
   double            tick_size;
   double            tick_value;
   double            contract_size;
   double            volume_min;
   double            volume_max;
   double            volume_step;
   int               stops_level_points;
   int               freeze_level_points;
   double            margin_initial;
   double            swap_long;
   double            swap_short;
   ENUM_SYMBOL_TRADE_MODE trade_mode;
   ENUM_SYMBOL_CALC_MODE  calc_mode;
   bool              is_resolved;

                     SSymbolSpec(void) { Reset(); }
   void              Reset(void)
     {
      symbol=""; digits=0; point=0.0; tick_size=0.0; tick_value=0.0;
      contract_size=0.0; volume_min=0.0; volume_max=0.0; volume_step=0.0;
      stops_level_points=0; freeze_level_points=0; margin_initial=0.0;
      swap_long=0.0; swap_short=0.0;
      trade_mode=SYMBOL_TRADE_MODE_DISABLED;
      calc_mode=SYMBOL_CALC_MODE_FOREX;
      is_resolved=false;
     }
  };

//+------------------------------------------------------------------+
//| One coherent read of the market. Built once per pipeline pass by |
//| CMarketDataService; every downstream module reads THIS instead   |
//| of querying the terminal, which guarantees all filters and       |
//| strategies evaluate against identical prices.                    |
//+------------------------------------------------------------------+
struct SMarketSnapshot
  {
   //--- identity
   string            symbol;
   ENUM_TIMEFRAMES   timeframe;
   datetime          server_time;
   ulong             tick_msc;
   ulong             sequence_id;        // monotonic snapshot counter
   //--- quotes
   double            bid;
   double            ask;
   double            mid;
   double            last;
   long              volume;
   double            spread_points;
   double            spread_average;
   //--- bar context
   datetime          bar_time;
   bool              is_new_bar;
   double            open;
   double            high;
   double            low;
   double            close;
   double            prev_open;
   double            prev_high;
   double            prev_low;
   double            prev_close;
   //--- derived regime (populated by CMarketRegimeAnalyzer)
   double            atr;
   double            atr_percent;
   ENUM_SRP_TREND_STATE      trend_state;
   ENUM_SRP_VOLATILITY_STATE volatility_state;
   ENUM_SRP_SESSION          session;
   //--- validity
   bool              is_valid;

                     SMarketSnapshot(void) { Reset(); }
   void              Reset(void)
     {
      symbol=""; timeframe=PERIOD_CURRENT; server_time=0; tick_msc=0; sequence_id=0;
      bid=0.0; ask=0.0; mid=0.0; last=0.0; volume=0;
      spread_points=0.0; spread_average=0.0;
      bar_time=0; is_new_bar=false;
      open=0.0; high=0.0; low=0.0; close=0.0;
      prev_open=0.0; prev_high=0.0; prev_low=0.0; prev_close=0.0;
      atr=0.0; atr_percent=0.0;
      trend_state=SRP_TREND_UNDEFINED;
      volatility_state=SRP_VOLATILITY_UNDEFINED;
      session=SRP_SESSION_OFF_HOURS;
      is_valid=false;
     }
  };

//+------------------------------------------------------------------+
//| A single strategy's opinion. Produced by IStrategy, consumed by  |
//| CSignalAggregator.                                               |
//+------------------------------------------------------------------+
struct SSignal
  {
   ENUM_SRP_SIGNAL_DIRECTION direction;
   ENUM_SRP_STRATEGY_ID      strategy_id;
   string            strategy_name;
   double            confidence;         // normalised 0.0 .. 1.0
   double            weight;             // aggregation weight
   double            suggested_entry;    // 0 == use market
   double            suggested_sl;       // 0 == delegate to SL calculator
   double            suggested_tp;       // 0 == delegate to TP calculator
   datetime          generated_at;
   ulong             snapshot_sequence;  // snapshot this decision came from
   string            rationale;          // human-readable, for journal/UI

                     SSignal(void) { Reset(); }
   void              Reset(void)
     {
      direction=SRP_SIGNAL_NONE;
      strategy_id=SRP_STRATEGY_MOMENTUM;
      strategy_name=""; confidence=0.0; weight=0.0;
      suggested_entry=SRP_INVALID_PRICE;
      suggested_sl=SRP_INVALID_PRICE;
      suggested_tp=SRP_INVALID_PRICE;
      generated_at=0; snapshot_sequence=0; rationale="";
     }
   bool              IsActionable(void) const { return(direction!=SRP_SIGNAL_NONE); }
  };

//+------------------------------------------------------------------+
//| Verdict of one filter. Produced by IFilter, collected by         |
//| CFilterChain.                                                     |
//+------------------------------------------------------------------+
struct SFilterVerdict
  {
   string                   filter_name;
   ENUM_SRP_FILTER_CATEGORY category;
   bool                     passed;
   ENUM_SRP_VETO_REASON     veto_reason;
   string                   detail;
   bool                     is_blocking;   // false => advisory only

                     SFilterVerdict(void) { Reset(); }
   void              Reset(void)
     {
      filter_name=""; category=SRP_FILTER_CATEGORY_MARKET;
      passed=true; veto_reason=SRP_VETO_NONE; detail=""; is_blocking=true;
     }
  };

//+------------------------------------------------------------------+
//| Aggregate outcome of the whole filter chain.                      |
//+------------------------------------------------------------------+
struct SFilterChainResult
  {
   bool                     allowed;
   ENUM_SRP_VETO_REASON     first_veto;
   string                   first_veto_filter;
   int                      evaluated_count;
   int                      veto_count;
   string                   summary;

                     SFilterChainResult(void) { Reset(); }
   void              Reset(void)
     {
      allowed=true; first_veto=SRP_VETO_NONE; first_veto_filter="";
      evaluated_count=0; veto_count=0; summary="";
     }
  };

//+------------------------------------------------------------------+
//| Output of the risk layer: the sanctioned size and levels.        |
//+------------------------------------------------------------------+
struct SRiskDecision
  {
   bool              approved;
   double            volume;
   double            stop_loss;
   double            take_profit;
   double            risk_amount;        // account currency at risk
   double            risk_percent;
   double            reward_risk_ratio;
   double            required_margin;
   ENUM_SRP_VETO_REASON rejection_reason;
   string            explanation;

                     SRiskDecision(void) { Reset(); }
   void              Reset(void)
     {
      approved=false; volume=0.0;
      stop_loss=SRP_INVALID_PRICE; take_profit=SRP_INVALID_PRICE;
      risk_amount=0.0; risk_percent=0.0; reward_risk_ratio=0.0;
      required_margin=0.0; rejection_reason=SRP_VETO_NONE; explanation="";
     }
  };

//+------------------------------------------------------------------+
//| Fully-formed instruction handed to the execution layer.          |
//+------------------------------------------------------------------+
struct STradeRequest
  {
   ENUM_SRP_SIGNAL_DIRECTION direction;
   string            symbol;
   double            volume;
   double            price;              // 0 == market execution
   double            stop_loss;
   double            take_profit;
   int               deviation_points;
   long              magic;
   string            comment;
   ENUM_ORDER_TYPE_FILLING filling;
   datetime          expiration;

                     STradeRequest(void) { Reset(); }
   void              Reset(void)
     {
      direction=SRP_SIGNAL_NONE; symbol=""; volume=0.0;
      price=SRP_INVALID_PRICE;
      stop_loss=SRP_INVALID_PRICE; take_profit=SRP_INVALID_PRICE;
      deviation_points=SRP_DEFAULT_DEVIATION_POINTS;
      magic=0; comment=""; filling=ORDER_FILLING_FOK; expiration=0;
     }
  };

//+------------------------------------------------------------------+
//| Result of an execution attempt, including retry telemetry.       |
//+------------------------------------------------------------------+
struct STradeResult
  {
   bool              success;
   ulong             order_ticket;
   ulong             deal_ticket;
   ulong             position_ticket;
   double            executed_volume;
   double            executed_price;
   double            requested_price;
   double            slippage_points;
   uint              retcode;
   string            retcode_text;
   int               attempts;
   ulong             latency_ms;

                     STradeResult(void) { Reset(); }
   void              Reset(void)
     {
      success=false; order_ticket=SRP_INVALID_TICKET;
      deal_ticket=SRP_INVALID_TICKET; position_ticket=SRP_INVALID_TICKET;
      executed_volume=0.0; executed_price=SRP_INVALID_PRICE;
      requested_price=SRP_INVALID_PRICE; slippage_points=0.0;
      retcode=0; retcode_text=""; attempts=0; latency_ms=0;
     }
  };

//+------------------------------------------------------------------+
//| Normalised view of one open position owned by this EA.           |
//+------------------------------------------------------------------+
struct SPositionSnapshot
  {
   ulong             ticket;
   string            symbol;
   long              magic;
   ENUM_POSITION_TYPE type;
   double            volume;
   double            initial_volume;
   double            open_price;
   double            current_price;
   double            stop_loss;
   double            take_profit;
   double            profit;
   double            swap;
   double            commission;
   double            profit_points;
   datetime          open_time;
   int               age_seconds;
   bool              break_even_applied;
   bool              partial_taken;
   ENUM_SRP_STRATEGY_ID origin_strategy;
   string            comment;

                     SPositionSnapshot(void) { Reset(); }
   void              Reset(void)
     {
      ticket=SRP_INVALID_TICKET; symbol=""; magic=0;
      type=POSITION_TYPE_BUY; volume=0.0; initial_volume=0.0;
      open_price=SRP_INVALID_PRICE; current_price=SRP_INVALID_PRICE;
      stop_loss=SRP_INVALID_PRICE; take_profit=SRP_INVALID_PRICE;
      profit=0.0; swap=0.0; commission=0.0; profit_points=0.0;
      open_time=0; age_seconds=0;
      break_even_applied=false; partial_taken=false;
      origin_strategy=SRP_STRATEGY_MOMENTUM; comment="";
     }
  };

//+------------------------------------------------------------------+
//| Aggregate exposure across all EA-owned positions.               |
//+------------------------------------------------------------------+
struct SPortfolioExposure
  {
   int               total_positions;
   int               buy_positions;
   int               sell_positions;
   double            total_volume;
   double            buy_volume;
   double            sell_volume;
   double            net_volume;
   double            floating_pnl;
   double            floating_pnl_percent;
   double            used_margin;
   double            free_margin;
   double            margin_level;
   double            aggregate_risk_percent;

                     SPortfolioExposure(void) { Reset(); }
   void              Reset(void)
     {
      total_positions=0; buy_positions=0; sell_positions=0;
      total_volume=0.0; buy_volume=0.0; sell_volume=0.0; net_volume=0.0;
      floating_pnl=0.0; floating_pnl_percent=0.0;
      used_margin=0.0; free_margin=0.0; margin_level=0.0;
      aggregate_risk_percent=0.0;
     }
  };

//+------------------------------------------------------------------+
//| Account state sampled once per pipeline pass.                    |
//+------------------------------------------------------------------+
struct SAccountSnapshot
  {
   long              login;
   string            currency;
   string            company;
   string            server;
   int               leverage;
   double            balance;
   double            equity;
   double            margin;
   double            free_margin;
   double            margin_level;
   double            credit;
   double            profit;
   bool              trade_allowed;
   bool              trade_expert;
   ENUM_ACCOUNT_MARGIN_MODE margin_mode;
   bool              is_hedging;

                     SAccountSnapshot(void) { Reset(); }
   void              Reset(void)
     {
      login=0; currency=""; company=""; server=""; leverage=0;
      balance=0.0; equity=0.0; margin=0.0; free_margin=0.0;
      margin_level=0.0; credit=0.0; profit=0.0;
      trade_allowed=false; trade_expert=false;
      margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
      is_hedging=false;
     }
  };

//+------------------------------------------------------------------+
//| One economic calendar entry, source-agnostic.                    |
//+------------------------------------------------------------------+
struct SNewsEvent
  {
   ulong             event_id;
   string            title;
   string            country;
   string            currency;
   ENUM_SRP_NEWS_IMPACT impact;
   datetime          event_time;
   int               minutes_before;
   int               minutes_after;
   bool              affects_symbol;

                     SNewsEvent(void) { Reset(); }
   void              Reset(void)
     {
      event_id=0; title=""; country=""; currency="";
      impact=SRP_NEWS_IMPACT_NONE; event_time=0;
      minutes_before=0; minutes_after=0; affects_symbol=false;
     }
  };

//+------------------------------------------------------------------+
//| Current news blackout status.                                    |
//+------------------------------------------------------------------+
struct SNewsBlackoutState
  {
   bool              in_blackout;
   datetime          blackout_until;
   int              seconds_remaining;
   SNewsEvent        active_event;
   SNewsEvent        next_event;
   int               seconds_to_next;

                     SNewsBlackoutState(void) { Reset(); }
   void              Reset(void)
     {
      in_blackout=false; blackout_until=0; seconds_remaining=0;
      active_event.Reset(); next_event.Reset(); seconds_to_next=0;
     }
  };

//+------------------------------------------------------------------+
//| Closed-trade record. The atomic input of all statistics.         |
//+------------------------------------------------------------------+
struct STradeRecord
  {
   ulong             position_ticket;
   string            symbol;
   ENUM_POSITION_TYPE type;
   double            volume;
   double            open_price;
   double            close_price;
   double            stop_loss;
   double            take_profit;
   datetime          open_time;
   datetime          close_time;
   int               duration_seconds;
   double            gross_profit;
   double            commission;
   double            swap;
   double            net_profit;
   double            profit_points;
   double            mae_points;         // max adverse excursion
   double            mfe_points;         // max favourable excursion
   double            risk_amount;
   double            r_multiple;
   ENUM_SRP_EXIT_REASON  exit_reason;
   ENUM_SRP_STRATEGY_ID  origin_strategy;
   double            balance_after;
   double            equity_peak_after;

                     STradeRecord(void) { Reset(); }
   void              Reset(void)
     {
      position_ticket=SRP_INVALID_TICKET; symbol="";
      type=POSITION_TYPE_BUY; volume=0.0;
      open_price=SRP_INVALID_PRICE; close_price=SRP_INVALID_PRICE;
      stop_loss=SRP_INVALID_PRICE; take_profit=SRP_INVALID_PRICE;
      open_time=0; close_time=0; duration_seconds=0;
      gross_profit=0.0; commission=0.0; swap=0.0; net_profit=0.0;
      profit_points=0.0; mae_points=0.0; mfe_points=0.0;
      risk_amount=0.0; r_multiple=0.0;
      exit_reason=SRP_EXIT_UNKNOWN; origin_strategy=SRP_STRATEGY_MOMENTUM;
      balance_after=0.0; equity_peak_after=0.0;
     }
   bool              IsWin(void) const { return(net_profit>SRP_EPSILON); }
   bool              IsLoss(void) const { return(net_profit<-SRP_EPSILON); }
  };

//+------------------------------------------------------------------+
//| Computed performance metrics. Read-only for the dashboard.       |
//+------------------------------------------------------------------+
struct SPerformanceMetrics
  {
   int               total_trades;
   int               winning_trades;
   int               losing_trades;
   double            win_rate;
   double            gross_profit;
   double            gross_loss;
   double            net_profit;
   double            profit_factor;
   double            expectancy;
   double            average_win;
   double            average_loss;
   double            payoff_ratio;
   double            largest_win;
   double            largest_loss;
   int               max_consecutive_wins;
   int               max_consecutive_losses;
   //--- Money lost in the worst losing run. Kept alongside the count
   //--- because "nine losses in a row" and "nine losses that cost 40% of
   //--- the account" are very different facts.
   double            max_consecutive_loss_money;
   int               current_streak;
   double            max_drawdown_money;
   double            max_drawdown_percent;
   double            current_drawdown_percent;
   double            recovery_factor;
   double            sharpe_ratio;
   double            sortino_ratio;
   double            average_r_multiple;
   double            average_duration_seconds;
   double            total_commission;
   double            total_swap;
   datetime          first_trade_time;
   datetime          last_trade_time;

                     SPerformanceMetrics(void) { Reset(); }
   void              Reset(void)
     {
      total_trades=0; winning_trades=0; losing_trades=0; win_rate=0.0;
      gross_profit=0.0; gross_loss=0.0; net_profit=0.0;
      profit_factor=0.0; expectancy=0.0;
      average_win=0.0; average_loss=0.0; payoff_ratio=0.0;
      largest_win=0.0; largest_loss=0.0;
      max_consecutive_wins=0; max_consecutive_losses=0;
      max_consecutive_loss_money=0.0; current_streak=0;
      max_drawdown_money=0.0; max_drawdown_percent=0.0;
      current_drawdown_percent=0.0; recovery_factor=0.0;
      sharpe_ratio=0.0; sortino_ratio=0.0; average_r_multiple=0.0;
      average_duration_seconds=0.0;
      total_commission=0.0; total_swap=0.0;
      first_trade_time=0; last_trade_time=0;
     }
  };

//+------------------------------------------------------------------+
//| Per-session (daily) counters, reset by CSessionStatistics.       |
//+------------------------------------------------------------------+
struct SDailyStatistics
  {
   datetime          day_start;
   double            starting_balance;
   double            starting_equity;
   double            peak_equity;
   double            trough_equity;
   double            realized_pnl;
   double            realized_pnl_percent;
   double            drawdown_percent;
   int               trades_opened;
   int               trades_closed;
   int               wins;
   int               losses;
   bool              profit_target_hit;
   bool              loss_limit_hit;

                     SDailyStatistics(void) { Reset(); }
   void              Reset(void)
     {
      day_start=0; starting_balance=0.0; starting_equity=0.0;
      peak_equity=0.0; trough_equity=0.0;
      realized_pnl=0.0; realized_pnl_percent=0.0; drawdown_percent=0.0;
      trades_opened=0; trades_closed=0; wins=0; losses=0;
      profit_target_hit=false; loss_limit_hit=false;
     }
  };

//+------------------------------------------------------------------+
//| Payload carried on the event bus. Deliberately generic so the    |
//| bus never depends on concrete module types.                      |
//+------------------------------------------------------------------+
struct SEventPayload
  {
   ENUM_SRP_EVENT    event_id;
   datetime          timestamp;
   ulong             timestamp_msc;
   string            source_module;
   string            message;
   long              integer_value;
   double            double_value;
   ulong             ticket;

                     SEventPayload(void) { Reset(); }
   void              Reset(void)
     {
      event_id=SRP_EVENT_HEARTBEAT; timestamp=0; timestamp_msc=0;
      source_module=""; message=""; integer_value=0; double_value=0.0;
      ticket=SRP_INVALID_TICKET;
     }
  };

//+------------------------------------------------------------------+
//| Result of a validation pass (config, preflight, module init).    |
//+------------------------------------------------------------------+
struct SValidationResult
  {
   bool              is_valid;
   int               error_count;
   int               warning_count;
   string            first_error;
   string            report;

                     SValidationResult(void) { Reset(); }
   void              Reset(void)
     {
      is_valid=true; error_count=0; warning_count=0;
      first_error=""; report="";
     }
   void              AddError(const string text)
     {
      is_valid=false; error_count++;
      if(first_error=="") first_error=text;
      report+="[ERROR] "+text+"\n";
     }
   void              AddWarning(const string text)
     {
      warning_count++;
      report+="[WARN ] "+text+"\n";
     }
  };

//+------------------------------------------------------------------+
//| Health report from one module, collected by CHealthMonitor.      |
//+------------------------------------------------------------------+
struct SHealthReport
  {
   string                  module_name;
   ENUM_SRP_HEALTH_STATUS  status;
   string                  detail;
   datetime                checked_at;

                     SHealthReport(void) { Reset(); }
   void              Reset(void)
     {
      module_name=""; status=SRP_HEALTH_OK; detail=""; checked_at=0;
     }
  };

//+------------------------------------------------------------------+
//| Immutable per-pass context handed to strategies and filters.     |
//| Bundling the snapshots means adding a new data source never      |
//| changes a single strategy or filter signature (Open/Closed).     |
//+------------------------------------------------------------------+
struct SDecisionContext
  {
   SMarketSnapshot     market;
   SAccountSnapshot    account;
   SPortfolioExposure  exposure;
   SNewsBlackoutState  news;
   SDailyStatistics    daily;
   ENUM_SRP_ENGINE_STATE engine_state;

                     SDecisionContext(void) { Reset(); }
   void              Reset(void)
     {
      market.Reset(); account.Reset(); exposure.Reset();
      news.Reset(); daily.Reset();
      engine_state=SRP_STATE_CREATED;
     }
  };

#endif // SRP_CORE_TYPES_STRUCTS_MQH
//+------------------------------------------------------------------+
