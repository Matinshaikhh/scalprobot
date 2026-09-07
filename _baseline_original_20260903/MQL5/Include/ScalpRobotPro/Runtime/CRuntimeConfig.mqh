//+------------------------------------------------------------------+
//|                                            CRuntimeConfig.mqh |
//|                    Scalping Robot Pro - Production Runtime (P5) |
//|                                                                  |
//|   RESPONSIBILITY (one only): translate the keyed configuration store   |
//|   into the strongly-typed settings each subsystem constructor needs.   |
//|                                                                  |
//|   WHY THIS EXISTS                                                    |
//|   Modules must not read IConfigProvider directly. If they did, every   |
//|   class would depend on the configuration vocabulary, a key rename     |
//|   would ripple through the codebase, and no module could be built in   |
//|   a test without a populated config object. This class is the single   |
//|   translation point: config keys stop here, typed values continue on.  |
//|                                                                  |
//|   NO HARDCODED VALUES DOWNSTREAM. Every fallback in this file is the   |
//|   documented default for one setting, declared exactly once. A         |
//|   subsystem never invents a number of its own.                        |
//|                                                                  |
//|   It is a passive struct with a Load method - no behaviour beyond      |
//|   reading. Validation belongs to CConfigValidator, which has already   |
//|   run by the time this is used.                                       |
//+------------------------------------------------------------------+
#ifndef SRP_RUNTIME_CRUNTIMECONFIG_MQH
#define SRP_RUNTIME_CRUNTIMECONFIG_MQH

#include "../Configuration/CConfigKeys.mqh"
#include "../Core/Interfaces/IConfigProvider.mqh"
#include "../Core/Types/Constants.mqh"
#include "../Core/Types/Enums.mqh"
//--- The Phase 2 vocabulary: sizing models, capital bases, stop and
//--- target models. Needed here because this struct holds their values.
#include "../Intelligence/Types/IntelligenceEnums.mqh"

//+------------------------------------------------------------------+
//| Every runtime setting, grouped by the subsystem that consumes it.   |
//+------------------------------------------------------------------+
struct SRuntimeConfig
  {
   //--- General.
   string            symbol;
   ENUM_TIMEFRAMES   timeframe;
   //--- MULTI-TIMEFRAME (Part 10). Context carries regime and bias; setup
   //--- carries structure; execution is the chart timeframe. Held as ints
   //--- so they round-trip through the keyed config store.
   int               context_timeframe;
   int               setup_timeframe;
   long              magic;
   string            order_comment;
   int               direction_mode;
   int               tick_throttle_ms;

   //--- Execution.
   int               deviation_points;
   double            max_slippage_points;
   double            max_spread_points;
   double            min_free_margin_percent;
   int               max_retry_attempts;

   //--- Sizing and risk.
   int               risk_model;
   int               risk_capital_base;      // ENUM_SRP_CAPITAL_BASE
   double            fixed_lot;
   double            risk_percent;
   double            max_lot;
   double            min_lot;
   int               max_positions;
   double            kelly_fraction;
   int               kelly_min_trades;
   double            auto_lot_capital_per_step;
   double            auto_lot_per_step;
   double            atr_risk_multiple;
   double            daily_loss_percent;
   double            weekly_loss_percent;
   double            monthly_loss_percent;
   double            max_drawdown_percent;
   double            max_exposure_percent;
   bool              flatten_on_trip;
   bool              kill_switch_enabled;

   //--- Protective levels.
   int               sl_model;
   double            sl_fixed_points;
   double            sl_atr_multiplier;
   int               tp_model;
   double            tp_fixed_points;
   double            tp_atr_multiplier;
   double            tp_risk_reward;
   bool              breakeven_enabled;
   double            breakeven_trigger_points;
   double            breakeven_offset_points;
   int               trail_mode;
   double            trail_start_points;
   double            trail_step_points;
   double            trail_distance_points;
   bool              profit_lock_enabled;
   double            profit_lock_trigger_percent;
   double            profit_lock_keep_percent;

   //--- Indicators.
   int               fast_ma_period;
   int               slow_ma_period;
   int               trend_ma_period;
   int               rsi_period;
   int               atr_period;
   int               adx_period;
   int               bollinger_period;
   double            bollinger_deviation;

   //--- Smart money concepts.
   bool              smc_enabled;
   int               smc_swing_strength;
   int               smc_swing_lookback;
   int               smc_zone_capacity;
   int               smc_zone_max_age_bars;
   double            smc_displacement_atr_multiple;
   double            smc_min_gap_points;
   bool              smc_require_displacement;
   double            smc_equal_tolerance_atr;
   int               smc_sweep_lookback_bars;
   double            smc_structure_break_buffer;

   //--- Decision engine.
   int               vote_mode;
   int               min_confirmations;
   double            min_confidence;
   int               max_risk_rating;
   bool              require_confirmation;
   bool              ema_cross_enabled;
   bool              vwap_pullback_enabled;
   bool              liquidity_sweep_enabled;
   bool              order_block_enabled;
   bool              fvg_enabled;
   bool              opening_range_enabled;
   bool              trend_continuation_enabled;
   bool              momentum_enabled;
   bool              mean_reversion_enabled;
   bool              breakout_enabled;
   //--- Added in Phase 6.
   bool              bos_enabled;
   bool              volatility_breakout_enabled;
   //--- Order flow / volume delta (OBV + MFI + relative volume).
   bool              order_flow_enabled;
   double            order_flow_weight;
   double            order_flow_min_volume;

   //--- Frequency ceilings. Read into the runtime config in this phase:
   //--- they were previously written to the keyed store and never read,
   //--- so the per-day cap was inert.
   int               min_seconds_between_trades;
   int               max_trades_per_hour;
   int               max_trades_per_day;

   //=== ULTRA-SCALP MODE ==============================================
   //--- Every field here can only REDUCE trading. There is no setting
   //--- that manufactures an entry.
   bool              scalp_mode_enabled;
   int               scalp_cooldown_seconds;      // anti-double-fire only
   int               scalp_max_hold_seconds;
   double            scalp_target_atr_multiple;
   double            scalp_target_min_points;
   double            scalp_target_max_points;
   double            scalp_stop_atr_multiple;
   double            scalp_commission_points;
   double            scalp_execution_cost_points;
   double            scalp_min_reward_cost_ratio;
   double            scalp_max_spread_target_ratio;
   bool              scalp_early_exit_enabled;
   double            scalp_early_exit_min_points;
   double            scalp_early_exit_target_share;
   double            scalp_atr_min_points;
   double            scalp_atr_max_points;

   //--- ENTRY QUALITY (accuracy) GATE.
   //---
   //--- Raises the win rate by SELECTIVITY rather than by shrinking the
   //--- target. Shrinking the target raises the win rate and lowers the
   //--- payoff by the same mechanism, so the break-even win rate rises to
   //--- meet it and nothing is gained. These settings leave the geometry
   //--- untouched.
   bool              accuracy_filter_enabled;
   bool              accuracy_require_setup;
   bool              accuracy_require_context;
   double            accuracy_min_relative_volume;
   int               accuracy_volume_lookback;
   double            accuracy_max_extension;
   double            accuracy_min_score;
   //--- Scalp tiers: SUPER, STANDARD, SWING.
   bool              tier_enabled[3];
   double            tier_target_atr[3];
   double            tier_stop_atr[3];
   int               tier_hold_seconds[3];
   double            tier_win_rate[3];
   int               tier_timeframe[3];

   //--- Sessions.
   bool              session_filter_enabled;
   bool              allow_sydney;
   bool              allow_tokyo;
   bool              allow_london;
   bool              allow_newyork;
   bool              kill_zones_only;
   bool              require_overlap;
   bool              weekend_filter;
   int               friday_close_minutes;
   bool              holiday_filter_enabled;
   //--- "YYYY.MM.DD;YYYY.MM.DD;..." The filter was previously enabled
   //--- with no dates, which is inert but looks active.
   string            holiday_list;
   int               broker_gmt_offset;
   bool              dst_adjust;
   //--- Session window times in GMT minutes, supplied by the market
   //--- profile so each asset keeps its own schedule.
   int               london_open_gmt;
   int               london_close_gmt;
   int               newyork_open_gmt;
   int               newyork_close_gmt;
   int               primary_kz_open_gmt;
   int               primary_kz_close_gmt;
   int               skip_after_open_minutes;
   int               skip_before_close_minutes;

   //--- News.
   bool              news_filter_enabled;
   int               news_source;
   int               news_min_impact;
   int               news_minutes_before;
   int               news_minutes_after;
   bool              news_close_positions;
   //--- Currencies whose events are treated as affecting this symbol.
   //---
   //--- The EA input and the market profile have both carried this since
   //--- Phase 6, and the runtime config never declared it - so the value
   //--- reached the configuration store and stopped there. With no filter
   //--- applied, CNewsEngine marked EVERY calendar event as affecting the
   //--- traded symbol, which on a full economic calendar is a near
   //--- permanent blackout.
   string            news_currency_filter;
   string            news_csv_file;
   bool              news_fail_safe_block;

   //--- Trade manager.
   bool              tm_atr_trail_enabled;
   double            tm_atr_trail_multiple;
   bool              tm_atr_exit_enabled;
   double            tm_atr_exit_multiple;
   bool              time_stop_enabled;
   int               time_stop_minutes;
   bool              tm_max_hold_enabled;
   int               tm_max_hold_minutes;
   bool              tm_scale_in_enabled;
   double            tm_scale_in_trigger_points;
   double            tm_scale_in_fraction;
   int               tm_scale_in_max;
   bool              tm_scale_out_enabled;
   double            tm_scale_out_trigger_points;
   double            tm_scale_out_fraction;
   int               tm_scale_out_max;
   bool              tm_reverse_enabled;

   //--- Interface.
   bool              dashboard_enabled;
   int               dashboard_theme;
   int               dashboard_x_offset;
   int               dashboard_y_offset;
   int               dashboard_refresh_ms;
   bool              dashboard_show_in_tester;
   bool              draw_overlay_enabled;
   bool              draw_entries;
   bool              draw_stops;
   bool              draw_zones;
   bool              draw_liquidity;
   bool              draw_structure;
   bool              draw_session_boxes;
   bool              draw_trade_labels;
   bool              draw_statistics;
   int               draw_max_zones;
   int               draw_zone_extend_bars;

   //--- Logging.
   int               log_level;
   string            log_folder;
   bool              log_channel_errors;
   bool              log_channel_trades;
   bool              log_channel_indicators;
   bool              log_channel_risk;
   bool              log_channel_performance;
   bool              log_channel_execution;
   int               log_format_default;
   bool              log_mirror_errors_to_journal;
   bool              log_daily_rotation;
   int               log_flush_every;

   //--- Persistence.
   bool              persist_state;
   string            state_folder;
   bool              journal_enabled;

   //--- Analytics and optimisation.
   int               analytics_min_sample;
   bool              analytics_use_r_multiples;
   double            analytics_initial_balance;
   int               opt_criterion;
   int               opt_min_trades;
   double            opt_drawdown_penalty;
   double            opt_concentration_penalty;
   double            opt_streak_penalty;
   bool              opt_monte_carlo_enabled;
   int               opt_monte_carlo_runs;
   int               opt_monte_carlo_seed;
   double            opt_monte_carlo_ruin_percent;
   bool              opt_export_csv;
   string            opt_export_folder;

                     SRuntimeConfig(void) { Reset(); }

   //--- Defaults are NASDAQ-oriented but symbol-agnostic in form: every
   //--- distance is in POINTS, never in pips or price, so switching to a
   //--- 5-digit FX symbol is a preset change and not a code change.
   void              Reset(void)
     {
      symbol=_Symbol; timeframe=PERIOD_M1;
      context_timeframe=(int)PERIOD_M15;
      setup_timeframe=(int)PERIOD_M5;
      magic=20260806; order_comment=SRP_PRODUCT_SHORT;
      direction_mode=0; tick_throttle_ms=0;

      deviation_points=SRP_DEFAULT_DEVIATION_POINTS;
      max_slippage_points=30.0; max_spread_points=300.0;
      min_free_margin_percent=30.0; max_retry_attempts=SRP_MAX_EXECUTION_RETRIES;

      risk_model=0; risk_capital_base=(int)SRP_CAPITAL_EQUITY;
      fixed_lot=0.01; risk_percent=1.0; max_lot=1.0; min_lot=0.0;
      max_positions=3;
      kelly_fraction=0.25; kelly_min_trades=30;
      auto_lot_capital_per_step=1000.0; auto_lot_per_step=0.01;
      atr_risk_multiple=2.0;
      daily_loss_percent=3.0; weekly_loss_percent=6.0;
      monthly_loss_percent=10.0; max_drawdown_percent=15.0;
      max_exposure_percent=5.0; flatten_on_trip=true;
      kill_switch_enabled=true;

      sl_model=0; sl_fixed_points=1500.0; sl_atr_multiplier=2.0;
      tp_model=0; tp_fixed_points=2000.0; tp_atr_multiplier=3.0;
      tp_risk_reward=1.5;
      breakeven_enabled=true; breakeven_trigger_points=800.0;
      breakeven_offset_points=100.0;
      trail_mode=0; trail_start_points=1000.0; trail_step_points=100.0;
      trail_distance_points=600.0;
      profit_lock_enabled=false; profit_lock_trigger_percent=2.0;
      profit_lock_keep_percent=50.0;

      fast_ma_period=8; slow_ma_period=21; trend_ma_period=100;
      rsi_period=14; atr_period=14; adx_period=14;
      bollinger_period=20; bollinger_deviation=2.0;

      smc_enabled=true; smc_swing_strength=3; smc_swing_lookback=300;
      smc_zone_capacity=64; smc_zone_max_age_bars=500;
      smc_displacement_atr_multiple=1.5; smc_min_gap_points=50.0;
      smc_require_displacement=true; smc_equal_tolerance_atr=0.15;
      smc_sweep_lookback_bars=10; smc_structure_break_buffer=10.0;

      vote_mode=3; min_confirmations=3; min_confidence=0.55;
      max_risk_rating=2; require_confirmation=true;
      ema_cross_enabled=true; vwap_pullback_enabled=true;
      liquidity_sweep_enabled=true; order_block_enabled=true;
      fvg_enabled=true; opening_range_enabled=true;
      trend_continuation_enabled=true; momentum_enabled=true;
      mean_reversion_enabled=false; breakout_enabled=true;
      bos_enabled=true; volatility_breakout_enabled=true;
      order_flow_enabled=true; order_flow_weight=1.0;
      order_flow_min_volume=0.90;

      min_seconds_between_trades=60;
      max_trades_per_hour=6;
      max_trades_per_day=20;

      //--- Ultra-scalp. OFF by default: it changes trading behaviour, so
      //--- it must be an explicit choice rather than a silent upgrade.
      scalp_mode_enabled=false;
      scalp_cooldown_seconds=15;        // 10-30s band, per the requirement
      scalp_max_hold_seconds=300;       // 5 minutes
      scalp_target_atr_multiple=0.55;
      scalp_target_min_points=0.0;      // 0 = derive from broker + costs
      scalp_target_max_points=0.0;      // 0 = no ceiling
      scalp_stop_atr_multiple=0.90;
      scalp_commission_points=0.0;
      scalp_execution_cost_points=0.0;  // 0 = derive from spread
      scalp_min_reward_cost_ratio=2.0;
      scalp_max_spread_target_ratio=0.35;
      scalp_early_exit_enabled=true;
      scalp_early_exit_min_points=0.0;  // 0 = derive from round-trip cost
      scalp_early_exit_target_share=0.55;
      scalp_atr_min_points=0.0;
      scalp_atr_max_points=0.0;

      //--- OFF in the neutral baseline. It changes which trades are taken,
      //--- so an unrecognised instrument must not receive it silently; the
      //--- gold profile switches it on deliberately.
      accuracy_filter_enabled=false;
      accuracy_require_setup=true;
      accuracy_require_context=true;
      accuracy_min_relative_volume=1.0;
      accuracy_volume_lookback=20;
      accuracy_max_extension=0.75;
      accuracy_min_score=0.65;
      tier_enabled[0]=true; tier_target_atr[0]=0.30;
      tier_stop_atr[0]=0.42; tier_hold_seconds[0]=90;
      tier_win_rate[0]=0.72; tier_timeframe[0]=(int)PERIOD_M1;
      tier_enabled[1]=true; tier_target_atr[1]=0.70;
      tier_stop_atr[1]=0.70; tier_hold_seconds[1]=300;
      tier_win_rate[1]=0.58; tier_timeframe[1]=(int)PERIOD_M1;
      tier_enabled[2]=true; tier_target_atr[2]=1.40;
      tier_stop_atr[2]=0.90; tier_hold_seconds[2]=900;
      tier_win_rate[2]=0.48; tier_timeframe[2]=(int)PERIOD_M5;

      session_filter_enabled=true;
      allow_sydney=false; allow_tokyo=false;
      allow_london=true;  allow_newyork=true;
      kill_zones_only=false; require_overlap=false;
      weekend_filter=true; friday_close_minutes=60;
      holiday_filter_enabled=true; holiday_list="";
      broker_gmt_offset=0; dst_adjust=true;
      //--- Conventional GMT hours as the neutral default. The market
      //--- profile overwrites these per asset.
      london_open_gmt=8*60;      london_close_gmt=16*60+30;
      newyork_open_gmt=13*60;    newyork_close_gmt=21*60;
      primary_kz_open_gmt=13*60; primary_kz_close_gmt=16*60;
      skip_after_open_minutes=0; skip_before_close_minutes=0;

      news_filter_enabled=true;
      news_source=(int)SRP_NEWS_SOURCE_TERMINAL_CALENDAR;
      news_min_impact=2;
      news_minutes_before=15; news_minutes_after=15;
      news_close_positions=false; news_csv_file=SRP_NEWS_CACHE_FILE;
      news_currency_filter="USD";
      news_fail_safe_block=false;

      tm_atr_trail_enabled=false; tm_atr_trail_multiple=2.0;
      tm_atr_exit_enabled=true;   tm_atr_exit_multiple=3.0;
      time_stop_enabled=true;     time_stop_minutes=120;
      tm_max_hold_enabled=true;   tm_max_hold_minutes=240;
      tm_scale_in_enabled=false;  tm_scale_in_trigger_points=1200.0;
      tm_scale_in_fraction=0.5;   tm_scale_in_max=1;
      tm_scale_out_enabled=true;  tm_scale_out_trigger_points=1000.0;
      tm_scale_out_fraction=0.5;  tm_scale_out_max=1;
      tm_reverse_enabled=false;

      dashboard_enabled=true; dashboard_theme=0;
      dashboard_x_offset=12; dashboard_y_offset=22;
      dashboard_refresh_ms=500; dashboard_show_in_tester=false;
      draw_overlay_enabled=true;
      draw_entries=true; draw_stops=true; draw_zones=true;
      draw_liquidity=true; draw_structure=true;
      draw_session_boxes=true; draw_trade_labels=true;
      draw_statistics=true; draw_max_zones=12; draw_zone_extend_bars=20;

      log_level=(int)SRP_LOG_INFO;
      log_folder=SRP_DATA_FOLDER+"\\Logs";
      log_channel_errors=true; log_channel_trades=true;
      log_channel_indicators=false;    // noisiest channel, off by default
      log_channel_risk=true; log_channel_performance=true;
      log_channel_execution=true;
      log_format_default=0; log_mirror_errors_to_journal=true;
      log_daily_rotation=true; log_flush_every=8;

      persist_state=true;
      state_folder=SRP_DATA_FOLDER+"\\State";
      journal_enabled=true;

      analytics_min_sample=10; analytics_use_r_multiples=false;
      analytics_initial_balance=0.0;   // 0 == take the live balance
      opt_criterion=5; opt_min_trades=30;
      opt_drawdown_penalty=1.0; opt_concentration_penalty=1.0;
      opt_streak_penalty=1.0;
      opt_monte_carlo_enabled=false; opt_monte_carlo_runs=500;
      opt_monte_carlo_seed=0; opt_monte_carlo_ruin_percent=50.0;
      opt_export_csv=false;
      opt_export_folder=SRP_DATA_FOLDER+"\\Reports";
     }
  };

//+------------------------------------------------------------------+
//| The translator. Static because it holds no state: it reads a config  |
//| provider and fills a struct.                                        |
//+------------------------------------------------------------------+
class CRuntimeConfig
  {
public:
   //--- Every read passes the corresponding field of a default-constructed
   //--- SRuntimeConfig as its fallback, so a key absent from the store
   //--- yields the documented default rather than a zero.
   static bool       Load(IConfigProvider *config,
                         const string symbol,
                         const ENUM_TIMEFRAMES timeframe,
                         SRuntimeConfig &out);
   static string     Describe(const SRuntimeConfig &config);
  };

//+------------------------------------------------------------------+
bool CRuntimeConfig::Load(IConfigProvider *config,
                          const string symbol,
                          const ENUM_TIMEFRAMES timeframe,
                          SRuntimeConfig &out)
  {
   out.Reset();
   out.symbol=symbol;
   out.timeframe=timeframe;
   //--- A null provider is legal: the caller gets the documented defaults.
   //--- That is what makes every module constructible in a test harness.
   if(config==NULL)
      return(false);

   SRuntimeConfig d;   // defaults, used as the fallback for every read

   //--- General.
   out.context_timeframe = config.GetInt(CConfigKeys::GENERAL_CONTEXT_TIMEFRAME,d.context_timeframe);
   out.setup_timeframe   = config.GetInt(CConfigKeys::GENERAL_SETUP_TIMEFRAME,d.setup_timeframe);
   out.magic            = config.GetLong(CConfigKeys::GENERAL_MAGIC,d.magic);
   out.order_comment    = config.GetString(CConfigKeys::GENERAL_ORDER_COMMENT,d.order_comment);
   out.direction_mode   = config.GetInt(CConfigKeys::GENERAL_DIRECTION_MODE,d.direction_mode);
   out.tick_throttle_ms = config.GetInt(CConfigKeys::GENERAL_TICK_THROTTLE_MS,d.tick_throttle_ms);

   //--- Execution.
   out.deviation_points        = config.GetInt(CConfigKeys::RISK_MAX_SLIPPAGE_POINTS,d.deviation_points);
   out.max_slippage_points     = config.GetDouble(CConfigKeys::RISK_MAX_SLIPPAGE_POINTS,d.max_slippage_points);
   out.max_spread_points       = config.GetDouble(CConfigKeys::RISK_MAX_SPREAD_POINTS,d.max_spread_points);
   out.min_free_margin_percent = config.GetDouble(CConfigKeys::RISK_MIN_FREE_MARGIN_PERCENT,d.min_free_margin_percent);

   //--- Sizing and risk.
   out.risk_model           = config.GetInt(CConfigKeys::RISK_MODE,d.risk_model);
   out.risk_capital_base    = config.GetInt(CConfigKeys::RISK_CAPITAL_BASE,d.risk_capital_base);
   out.fixed_lot            = config.GetDouble(CConfigKeys::RISK_FIXED_LOT,d.fixed_lot);
   out.risk_percent         = config.GetDouble(CConfigKeys::RISK_PERCENT,d.risk_percent);
   out.max_lot              = config.GetDouble(CConfigKeys::RISK_MAX_LOT,d.max_lot);
   out.min_lot              = config.GetDouble(CConfigKeys::RISK_MIN_LOT,d.min_lot);
   out.max_positions        = config.GetInt(CConfigKeys::RISK_MAX_POSITIONS,d.max_positions);
   out.kelly_fraction       = config.GetDouble(CConfigKeys::RISK_KELLY_FRACTION,d.kelly_fraction);
   out.kelly_min_trades     = config.GetInt(CConfigKeys::RISK_KELLY_MIN_TRADES,d.kelly_min_trades);
   out.auto_lot_capital_per_step = config.GetDouble(CConfigKeys::RISK_AUTO_LOT_CAPITAL_PER_STEP,d.auto_lot_capital_per_step);
   out.auto_lot_per_step    = config.GetDouble(CConfigKeys::RISK_AUTO_LOT_PER_STEP,d.auto_lot_per_step);
   out.atr_risk_multiple    = config.GetDouble(CConfigKeys::RISK_ATR_RISK_MULTIPLE,d.atr_risk_multiple);
   out.daily_loss_percent   = config.GetDouble(CConfigKeys::GUARD_DAILY_LOSS_PERCENT,d.daily_loss_percent);
   out.weekly_loss_percent  = config.GetDouble(CConfigKeys::RISK_WEEKLY_LOSS_PERCENT,d.weekly_loss_percent);
   out.monthly_loss_percent = config.GetDouble(CConfigKeys::RISK_MONTHLY_LOSS_PERCENT,d.monthly_loss_percent);
   out.max_drawdown_percent = config.GetDouble(CConfigKeys::GUARD_MAX_DRAWDOWN_PERCENT,d.max_drawdown_percent);
   out.max_exposure_percent = config.GetDouble(CConfigKeys::RISK_MAX_RISK_PERCENT_TOTAL,d.max_exposure_percent);
   out.flatten_on_trip      = config.GetBool(CConfigKeys::GUARD_FLATTEN_ON_TRIP,d.flatten_on_trip);
   out.kill_switch_enabled  = config.GetBool(CConfigKeys::KILL_SWITCH_ENABLED,d.kill_switch_enabled);

   //--- Protective levels.
   out.sl_model                 = config.GetInt(CConfigKeys::SL_MODE,d.sl_model);
   out.sl_fixed_points          = config.GetDouble(CConfigKeys::SL_FIXED_POINTS,d.sl_fixed_points);
   out.sl_atr_multiplier        = config.GetDouble(CConfigKeys::SL_ATR_MULTIPLIER,d.sl_atr_multiplier);
   out.tp_model                 = config.GetInt(CConfigKeys::TP_MODE,d.tp_model);
   out.tp_fixed_points          = config.GetDouble(CConfigKeys::TP_FIXED_POINTS,d.tp_fixed_points);
   out.tp_atr_multiplier        = config.GetDouble(CConfigKeys::TP_ATR_MULTIPLIER,d.tp_atr_multiplier);
   out.tp_risk_reward           = config.GetDouble(CConfigKeys::TP_RISK_REWARD,d.tp_risk_reward);
   out.breakeven_enabled        = config.GetBool(CConfigKeys::BREAKEVEN_ENABLED,d.breakeven_enabled);
   out.breakeven_trigger_points = config.GetDouble(CConfigKeys::BREAKEVEN_TRIGGER_POINTS,d.breakeven_trigger_points);
   out.breakeven_offset_points  = config.GetDouble(CConfigKeys::BREAKEVEN_OFFSET_POINTS,d.breakeven_offset_points);
   out.trail_mode               = config.GetInt(CConfigKeys::TRAIL_MODE,d.trail_mode);
   out.trail_start_points       = config.GetDouble(CConfigKeys::TRAIL_START_POINTS,d.trail_start_points);
   out.trail_step_points        = config.GetDouble(CConfigKeys::TRAIL_STEP_POINTS,d.trail_step_points);
   out.trail_distance_points    = config.GetDouble(CConfigKeys::TRAIL_DISTANCE_POINTS,d.trail_distance_points);
   out.profit_lock_enabled      = config.GetBool(CConfigKeys::RISK_PROFIT_LOCK_ENABLED,d.profit_lock_enabled);
   out.profit_lock_trigger_percent = config.GetDouble(CConfigKeys::RISK_PROFIT_LOCK_TRIGGER_PERCENT,d.profit_lock_trigger_percent);
   out.profit_lock_keep_percent = config.GetDouble(CConfigKeys::RISK_PROFIT_LOCK_KEEP_PERCENT,d.profit_lock_keep_percent);

   //--- Indicators.
   out.fast_ma_period      = config.GetInt(CConfigKeys::INDICATOR_FAST_MA_PERIOD,d.fast_ma_period);
   out.slow_ma_period      = config.GetInt(CConfigKeys::INDICATOR_SLOW_MA_PERIOD,d.slow_ma_period);
   out.trend_ma_period     = config.GetInt(CConfigKeys::INDICATOR_TREND_MA_PERIOD,d.trend_ma_period);
   out.rsi_period          = config.GetInt(CConfigKeys::INDICATOR_RSI_PERIOD,d.rsi_period);
   out.atr_period          = config.GetInt(CConfigKeys::INDICATOR_ATR_PERIOD,d.atr_period);
   out.adx_period          = config.GetInt(CConfigKeys::INDICATOR_ADX_PERIOD,d.adx_period);
   out.bollinger_period    = config.GetInt(CConfigKeys::INDICATOR_BOLLINGER_PERIOD,d.bollinger_period);
   out.bollinger_deviation = config.GetDouble(CConfigKeys::INDICATOR_BOLLINGER_DEVIATION,d.bollinger_deviation);

   //--- Smart money concepts.
   out.smc_enabled                   = config.GetBool(CConfigKeys::SMC_ENABLED,d.smc_enabled);
   out.smc_swing_strength            = config.GetInt(CConfigKeys::SMC_SWING_STRENGTH,d.smc_swing_strength);
   out.smc_swing_lookback            = config.GetInt(CConfigKeys::SMC_SWING_LOOKBACK,d.smc_swing_lookback);
   out.smc_zone_capacity             = config.GetInt(CConfigKeys::SMC_ZONE_CAPACITY,d.smc_zone_capacity);
   out.smc_zone_max_age_bars         = config.GetInt(CConfigKeys::SMC_ZONE_MAX_AGE_BARS,d.smc_zone_max_age_bars);
   out.smc_displacement_atr_multiple = config.GetDouble(CConfigKeys::SMC_DISPLACEMENT_ATR_MULTIPLE,d.smc_displacement_atr_multiple);
   out.smc_min_gap_points            = config.GetDouble(CConfigKeys::SMC_MIN_GAP_POINTS,d.smc_min_gap_points);
   out.smc_require_displacement      = config.GetBool(CConfigKeys::SMC_REQUIRE_DISPLACEMENT,d.smc_require_displacement);
   out.smc_equal_tolerance_atr       = config.GetDouble(CConfigKeys::SMC_EQUAL_TOLERANCE_ATR,d.smc_equal_tolerance_atr);
   out.smc_sweep_lookback_bars       = config.GetInt(CConfigKeys::SMC_SWEEP_LOOKBACK_BARS,d.smc_sweep_lookback_bars);
   out.smc_structure_break_buffer    = config.GetDouble(CConfigKeys::SMC_STRUCTURE_BREAK_BUFFER,d.smc_structure_break_buffer);

   //--- Decision engine.
   out.vote_mode            = config.GetInt(CConfigKeys::DECISION_VOTE_MODE,d.vote_mode);
   out.min_confirmations    = config.GetInt(CConfigKeys::DECISION_MIN_CONFIRMATIONS,d.min_confirmations);
   out.min_confidence       = config.GetDouble(CConfigKeys::DECISION_MIN_CONFIDENCE,d.min_confidence);
   out.max_risk_rating      = config.GetInt(CConfigKeys::DECISION_MAX_RISK_RATING,d.max_risk_rating);
   out.require_confirmation = config.GetBool(CConfigKeys::DECISION_REQUIRE_CONFIRMATION,
                                             d.require_confirmation);
   out.ema_cross_enabled    = config.GetBool(CConfigKeys::STRATEGY_EMA_CROSS_ENABLED,d.ema_cross_enabled);
   out.vwap_pullback_enabled= config.GetBool(CConfigKeys::STRATEGY_VWAP_PULLBACK_ENABLED,d.vwap_pullback_enabled);
   out.liquidity_sweep_enabled = config.GetBool(CConfigKeys::STRATEGY_LIQUIDITY_SWEEP_ENABLED,d.liquidity_sweep_enabled);
   out.order_block_enabled  = config.GetBool(CConfigKeys::STRATEGY_ORDER_BLOCK_ENABLED,d.order_block_enabled);
   out.fvg_enabled          = config.GetBool(CConfigKeys::STRATEGY_FVG_ENABLED,d.fvg_enabled);
   out.opening_range_enabled= config.GetBool(CConfigKeys::STRATEGY_OPENING_RANGE_ENABLED,d.opening_range_enabled);
   out.trend_continuation_enabled = config.GetBool(CConfigKeys::STRATEGY_TREND_CONTINUATION_ENABLED,d.trend_continuation_enabled);
   out.momentum_enabled     = config.GetBool(CConfigKeys::STRATEGY_MOMENTUM_ENABLED,d.momentum_enabled);
   out.mean_reversion_enabled = config.GetBool(CConfigKeys::STRATEGY_MEAN_REVERSION_ENABLED,d.mean_reversion_enabled);
   out.breakout_enabled     = config.GetBool(CConfigKeys::STRATEGY_BREAKOUT_ENABLED,d.breakout_enabled);
   out.bos_enabled          = config.GetBool(CConfigKeys::STRATEGY_BOS_ENABLED,d.bos_enabled);
   out.volatility_breakout_enabled = config.GetBool(CConfigKeys::STRATEGY_VOLATILITY_BREAKOUT_ENABLED,d.volatility_breakout_enabled);
   out.order_flow_enabled   = config.GetBool(CConfigKeys::STRATEGY_ORDER_FLOW_ENABLED,d.order_flow_enabled);
   out.order_flow_weight    = config.GetDouble(CConfigKeys::STRATEGY_ORDER_FLOW_WEIGHT,d.order_flow_weight);
   out.order_flow_min_volume= config.GetDouble(CConfigKeys::STRATEGY_ORDER_FLOW_MIN_VOLUME,d.order_flow_min_volume);

   //--- Frequency ceilings.
   out.min_seconds_between_trades = config.GetInt(CConfigKeys::FILTER_MIN_SECONDS_BETWEEN_TRADES,d.min_seconds_between_trades);
   out.max_trades_per_hour        = config.GetInt(CConfigKeys::FILTER_MAX_TRADES_PER_HOUR,d.max_trades_per_hour);
   out.max_trades_per_day         = config.GetInt(CConfigKeys::FILTER_MAX_TRADES_PER_DAY,d.max_trades_per_day);

   //--- Ultra-scalp mode.
   out.scalp_mode_enabled          = config.GetBool(CConfigKeys::SCALP_MODE_ENABLED,d.scalp_mode_enabled);
   out.scalp_cooldown_seconds      = config.GetInt(CConfigKeys::SCALP_COOLDOWN_SECONDS,d.scalp_cooldown_seconds);
   out.scalp_max_hold_seconds      = config.GetInt(CConfigKeys::SCALP_MAX_HOLD_SECONDS,d.scalp_max_hold_seconds);
   out.scalp_target_atr_multiple   = config.GetDouble(CConfigKeys::SCALP_TARGET_ATR_MULTIPLE,d.scalp_target_atr_multiple);
   out.scalp_target_min_points     = config.GetDouble(CConfigKeys::SCALP_TARGET_MIN_POINTS,d.scalp_target_min_points);
   out.scalp_target_max_points     = config.GetDouble(CConfigKeys::SCALP_TARGET_MAX_POINTS,d.scalp_target_max_points);
   out.scalp_stop_atr_multiple     = config.GetDouble(CConfigKeys::SCALP_STOP_ATR_MULTIPLE,d.scalp_stop_atr_multiple);
   out.scalp_commission_points     = config.GetDouble(CConfigKeys::SCALP_COMMISSION_POINTS,d.scalp_commission_points);
   out.scalp_execution_cost_points = config.GetDouble(CConfigKeys::SCALP_EXECUTION_COST_POINTS,d.scalp_execution_cost_points);
   out.scalp_min_reward_cost_ratio = config.GetDouble(CConfigKeys::SCALP_MIN_REWARD_COST_RATIO,d.scalp_min_reward_cost_ratio);
   out.scalp_max_spread_target_ratio = config.GetDouble(CConfigKeys::SCALP_MAX_SPREAD_TARGET_RATIO,d.scalp_max_spread_target_ratio);
   out.scalp_early_exit_enabled    = config.GetBool(CConfigKeys::SCALP_EARLY_EXIT_ENABLED,d.scalp_early_exit_enabled);
   out.scalp_early_exit_min_points = config.GetDouble(CConfigKeys::SCALP_EARLY_EXIT_MIN_POINTS,d.scalp_early_exit_min_points);
   out.scalp_early_exit_target_share = config.GetDouble(CConfigKeys::SCALP_EARLY_EXIT_TARGET_SHARE,d.scalp_early_exit_target_share);
   out.scalp_atr_min_points        = config.GetDouble(CConfigKeys::SCALP_ATR_MIN_POINTS,d.scalp_atr_min_points);
   out.scalp_atr_max_points        = config.GetDouble(CConfigKeys::SCALP_ATR_MAX_POINTS,d.scalp_atr_max_points);

   out.accuracy_filter_enabled      = config.GetBool(CConfigKeys::ACCURACY_FILTER_ENABLED,d.accuracy_filter_enabled);
   out.accuracy_require_setup       = config.GetBool(CConfigKeys::ACCURACY_REQUIRE_SETUP,d.accuracy_require_setup);
   out.accuracy_require_context     = config.GetBool(CConfigKeys::ACCURACY_REQUIRE_CONTEXT,d.accuracy_require_context);
   out.accuracy_min_relative_volume = config.GetDouble(CConfigKeys::ACCURACY_MIN_RELATIVE_VOLUME,d.accuracy_min_relative_volume);
   out.accuracy_volume_lookback     = config.GetInt(CConfigKeys::ACCURACY_VOLUME_LOOKBACK,d.accuracy_volume_lookback);
   out.accuracy_max_extension       = config.GetDouble(CConfigKeys::ACCURACY_MAX_EXTENSION,d.accuracy_max_extension);
   out.accuracy_min_score           = config.GetDouble(CConfigKeys::ACCURACY_MIN_SCORE,d.accuracy_min_score);
   for(int t=0;t<3;t++)
     {
      const string sfx=IntegerToString(t);
      out.tier_enabled[t]      = config.GetBool(CConfigKeys::TIER_ENABLED_PREFIX+sfx,d.tier_enabled[t]);
      out.tier_target_atr[t]   = config.GetDouble(CConfigKeys::TIER_TARGET_ATR_PREFIX+sfx,d.tier_target_atr[t]);
      out.tier_stop_atr[t]     = config.GetDouble(CConfigKeys::TIER_STOP_ATR_PREFIX+sfx,d.tier_stop_atr[t]);
      out.tier_hold_seconds[t] = config.GetInt(CConfigKeys::TIER_HOLD_SECONDS_PREFIX+sfx,d.tier_hold_seconds[t]);
      out.tier_win_rate[t]     = config.GetDouble(CConfigKeys::TIER_WIN_RATE_PREFIX+sfx,d.tier_win_rate[t]);
      out.tier_timeframe[t]    = config.GetInt(CConfigKeys::TIER_TIMEFRAME_PREFIX+sfx,d.tier_timeframe[t]);
     }

   //--- Sessions.
   out.session_filter_enabled = config.GetBool(CConfigKeys::SESSION_FILTER_ENABLED,d.session_filter_enabled);
   out.allow_sydney         = config.GetBool(CConfigKeys::SESSION_ALLOW_SYDNEY,d.allow_sydney);
   out.allow_tokyo          = config.GetBool(CConfigKeys::SESSION_ALLOW_TOKYO,d.allow_tokyo);
   out.allow_london         = config.GetBool(CConfigKeys::SESSION_ALLOW_LONDON,d.allow_london);
   out.allow_newyork        = config.GetBool(CConfigKeys::SESSION_ALLOW_NEWYORK,d.allow_newyork);
   out.kill_zones_only      = config.GetBool(CConfigKeys::SESSION_KILL_ZONES_ONLY,d.kill_zones_only);
   out.require_overlap      = config.GetBool(CConfigKeys::SESSION_REQUIRE_OVERLAP,d.require_overlap);
   out.weekend_filter       = config.GetBool(CConfigKeys::SESSION_WEEKEND_FILTER,d.weekend_filter);
   out.friday_close_minutes = config.GetInt(CConfigKeys::SCHEDULE_FRIDAY_CLOSE_MINUTES,d.friday_close_minutes);
   out.holiday_filter_enabled = config.GetBool(CConfigKeys::HOLIDAY_FILTER_ENABLED,d.holiday_filter_enabled);
   out.holiday_list         = config.GetString(CConfigKeys::HOLIDAY_LIST,d.holiday_list);
   out.broker_gmt_offset    = config.GetInt(CConfigKeys::SESSION_BROKER_GMT_OFFSET,d.broker_gmt_offset);
   out.dst_adjust           = config.GetBool(CConfigKeys::SESSION_DST_ADJUST,d.dst_adjust);
   out.london_open_gmt      = config.GetInt(CConfigKeys::SESSION_LONDON_OPEN_GMT,d.london_open_gmt);
   out.london_close_gmt     = config.GetInt(CConfigKeys::SESSION_LONDON_CLOSE_GMT,d.london_close_gmt);
   out.newyork_open_gmt     = config.GetInt(CConfigKeys::SESSION_NEWYORK_OPEN_GMT,d.newyork_open_gmt);
   out.newyork_close_gmt    = config.GetInt(CConfigKeys::SESSION_NEWYORK_CLOSE_GMT,d.newyork_close_gmt);
   out.primary_kz_open_gmt  = config.GetInt(CConfigKeys::SESSION_PRIMARY_KZ_OPEN_GMT,d.primary_kz_open_gmt);
   out.primary_kz_close_gmt = config.GetInt(CConfigKeys::SESSION_PRIMARY_KZ_CLOSE_GMT,d.primary_kz_close_gmt);
   out.skip_after_open_minutes   = config.GetInt(CConfigKeys::SESSION_SKIP_AFTER_OPEN,d.skip_after_open_minutes);
   out.skip_before_close_minutes = config.GetInt(CConfigKeys::SESSION_SKIP_BEFORE_CLOSE,d.skip_before_close_minutes);

   //--- News.
   out.news_filter_enabled  = config.GetBool(CConfigKeys::NEWS_FILTER_ENABLED,d.news_filter_enabled);
   out.news_source          = config.GetInt(CConfigKeys::NEWS_SOURCE,
                                             (int)SRP_NEWS_SOURCE_TERMINAL_CALENDAR);
   out.news_min_impact      = config.GetInt(CConfigKeys::NEWS_MIN_IMPACT,d.news_min_impact);
   out.news_minutes_before  = config.GetInt(CConfigKeys::NEWS_MINUTES_BEFORE,d.news_minutes_before);
   out.news_minutes_after   = config.GetInt(CConfigKeys::NEWS_MINUTES_AFTER,d.news_minutes_after);
   out.news_close_positions = config.GetBool(CConfigKeys::NEWS_CLOSE_POSITIONS,d.news_close_positions);
   out.news_currency_filter = config.GetString(CConfigKeys::NEWS_CURRENCY_FILTER,d.news_currency_filter);
   out.news_csv_file        = config.GetString(CConfigKeys::NEWS_CSV_FILE,d.news_csv_file);
   out.news_fail_safe_block = config.GetBool(CConfigKeys::NEWS_FAIL_SAFE_BLOCK,d.news_fail_safe_block);

   //--- Trade manager.
   out.tm_atr_trail_enabled  = config.GetBool(CConfigKeys::TM_ATR_TRAIL_ENABLED,d.tm_atr_trail_enabled);
   out.tm_atr_trail_multiple = config.GetDouble(CConfigKeys::TM_ATR_TRAIL_MULTIPLE,d.tm_atr_trail_multiple);
   out.tm_atr_exit_enabled   = config.GetBool(CConfigKeys::TM_ATR_EXIT_ENABLED,d.tm_atr_exit_enabled);
   out.tm_atr_exit_multiple  = config.GetDouble(CConfigKeys::TM_ATR_EXIT_MULTIPLE,d.tm_atr_exit_multiple);
   out.time_stop_enabled     = config.GetBool(CConfigKeys::TIME_STOP_ENABLED,d.time_stop_enabled);
   out.time_stop_minutes     = config.GetInt(CConfigKeys::TIME_STOP_MINUTES,d.time_stop_minutes);
   out.tm_max_hold_enabled   = config.GetBool(CConfigKeys::TM_MAX_HOLD_ENABLED,d.tm_max_hold_enabled);
   out.tm_max_hold_minutes   = config.GetInt(CConfigKeys::TM_MAX_HOLD_MINUTES,d.tm_max_hold_minutes);
   out.tm_scale_in_enabled   = config.GetBool(CConfigKeys::TM_SCALE_IN_ENABLED,d.tm_scale_in_enabled);
   out.tm_scale_in_trigger_points = config.GetDouble(CConfigKeys::TM_SCALE_IN_TRIGGER_POINTS,d.tm_scale_in_trigger_points);
   out.tm_scale_in_fraction  = config.GetDouble(CConfigKeys::TM_SCALE_IN_FRACTION,d.tm_scale_in_fraction);
   out.tm_scale_in_max       = config.GetInt(CConfigKeys::TM_SCALE_IN_MAX,d.tm_scale_in_max);
   out.tm_scale_out_enabled  = config.GetBool(CConfigKeys::TM_SCALE_OUT_ENABLED,d.tm_scale_out_enabled);
   out.tm_scale_out_trigger_points = config.GetDouble(CConfigKeys::TM_SCALE_OUT_TRIGGER_POINTS,d.tm_scale_out_trigger_points);
   out.tm_scale_out_fraction = config.GetDouble(CConfigKeys::TM_SCALE_OUT_FRACTION,d.tm_scale_out_fraction);
   out.tm_scale_out_max      = config.GetInt(CConfigKeys::TM_SCALE_OUT_MAX,d.tm_scale_out_max);
   out.tm_reverse_enabled    = config.GetBool(CConfigKeys::TM_REVERSE_ENABLED,d.tm_reverse_enabled);

   //--- Interface.
   out.dashboard_enabled    = config.GetBool(CConfigKeys::DASHBOARD_ENABLED,d.dashboard_enabled);
   out.dashboard_theme      = config.GetInt(CConfigKeys::DASHBOARD_THEME,d.dashboard_theme);
   out.dashboard_x_offset   = config.GetInt(CConfigKeys::DASHBOARD_X_OFFSET,d.dashboard_x_offset);
   out.dashboard_y_offset   = config.GetInt(CConfigKeys::DASHBOARD_Y_OFFSET,d.dashboard_y_offset);
   out.dashboard_refresh_ms = config.GetInt(CConfigKeys::DASHBOARD_REFRESH_MS,d.dashboard_refresh_ms);
   out.dashboard_show_in_tester = config.GetBool(CConfigKeys::DASHBOARD_SHOW_IN_TESTER,d.dashboard_show_in_tester);
   out.draw_overlay_enabled = config.GetBool(CConfigKeys::DRAW_OVERLAY_ENABLED,d.draw_overlay_enabled);
   out.draw_entries         = config.GetBool(CConfigKeys::DRAW_ENTRIES,d.draw_entries);
   out.draw_stops           = config.GetBool(CConfigKeys::DRAW_STOPS,d.draw_stops);
   out.draw_zones           = config.GetBool(CConfigKeys::DRAW_ZONES,d.draw_zones);
   out.draw_liquidity       = config.GetBool(CConfigKeys::DRAW_LIQUIDITY,d.draw_liquidity);
   out.draw_structure       = config.GetBool(CConfigKeys::DRAW_STRUCTURE,d.draw_structure);
   out.draw_session_boxes   = config.GetBool(CConfigKeys::DRAW_SESSION_BOXES,d.draw_session_boxes);
   out.draw_trade_labels    = config.GetBool(CConfigKeys::DRAW_TRADE_LABELS,d.draw_trade_labels);
   out.draw_statistics      = config.GetBool(CConfigKeys::DRAW_STATISTICS,d.draw_statistics);
   out.draw_max_zones       = config.GetInt(CConfigKeys::DRAW_MAX_ZONES,d.draw_max_zones);
   out.draw_zone_extend_bars= config.GetInt(CConfigKeys::DRAW_ZONE_EXTEND_BARS,d.draw_zone_extend_bars);

   //--- Logging.
   out.log_level            = config.GetInt(CConfigKeys::LOG_LEVEL,d.log_level);
   out.log_folder           = config.GetString(CConfigKeys::LOG_FOLDER,d.log_folder);
   out.log_channel_errors   = config.GetBool(CConfigKeys::LOG_CHANNEL_ERRORS,d.log_channel_errors);
   out.log_channel_trades   = config.GetBool(CConfigKeys::LOG_CHANNEL_TRADES,d.log_channel_trades);
   out.log_channel_indicators = config.GetBool(CConfigKeys::LOG_CHANNEL_INDICATORS,d.log_channel_indicators);
   out.log_channel_risk     = config.GetBool(CConfigKeys::LOG_CHANNEL_RISK,d.log_channel_risk);
   out.log_channel_performance = config.GetBool(CConfigKeys::LOG_CHANNEL_PERFORMANCE,d.log_channel_performance);
   out.log_channel_execution= config.GetBool(CConfigKeys::LOG_CHANNEL_EXECUTION,d.log_channel_execution);
   out.log_format_default   = config.GetInt(CConfigKeys::LOG_FORMAT_DEFAULT,d.log_format_default);
   out.log_mirror_errors_to_journal = config.GetBool(CConfigKeys::LOG_MIRROR_ERRORS_TO_JOURNAL,d.log_mirror_errors_to_journal);
   out.log_daily_rotation   = config.GetBool(CConfigKeys::LOG_DAILY_ROTATION,d.log_daily_rotation);
   out.log_flush_every      = config.GetInt(CConfigKeys::LOG_FLUSH_EVERY,d.log_flush_every);

   //--- Persistence.
   out.persist_state        = config.GetBool(CConfigKeys::STATS_PERSIST_STATE,d.persist_state);
   out.state_folder         = config.GetString(CConfigKeys::STATS_STATE_FOLDER,d.state_folder);
   out.journal_enabled      = config.GetBool(CConfigKeys::STATS_JOURNAL_ENABLED,d.journal_enabled);

   //--- Analytics and optimisation.
   out.analytics_min_sample = config.GetInt(CConfigKeys::ANALYTICS_MIN_SAMPLE,d.analytics_min_sample);
   out.analytics_use_r_multiples = config.GetBool(CConfigKeys::ANALYTICS_USE_R_MULTIPLES,d.analytics_use_r_multiples);
   out.analytics_initial_balance = config.GetDouble(CConfigKeys::ANALYTICS_INITIAL_BALANCE,d.analytics_initial_balance);
   out.opt_criterion        = config.GetInt(CConfigKeys::OPT_CRITERION,d.opt_criterion);
   out.opt_min_trades       = config.GetInt(CConfigKeys::OPT_MIN_TRADES,d.opt_min_trades);
   out.opt_drawdown_penalty = config.GetDouble(CConfigKeys::OPT_MAX_DRAWDOWN_PENALTY,d.opt_drawdown_penalty);
   out.opt_concentration_penalty = config.GetDouble(CConfigKeys::OPT_CONCENTRATION_PENALTY,d.opt_concentration_penalty);
   out.opt_streak_penalty   = config.GetDouble(CConfigKeys::OPT_STREAK_PENALTY,d.opt_streak_penalty);
   out.opt_monte_carlo_enabled = config.GetBool(CConfigKeys::OPT_MONTE_CARLO_ENABLED,d.opt_monte_carlo_enabled);
   out.opt_monte_carlo_runs = config.GetInt(CConfigKeys::OPT_MONTE_CARLO_RUNS,d.opt_monte_carlo_runs);
   out.opt_monte_carlo_seed = config.GetInt(CConfigKeys::OPT_MONTE_CARLO_SEED,d.opt_monte_carlo_seed);
   out.opt_monte_carlo_ruin_percent = config.GetDouble(CConfigKeys::OPT_MONTE_CARLO_RUIN_PERCENT,d.opt_monte_carlo_ruin_percent);
   out.opt_export_csv       = config.GetBool(CConfigKeys::OPT_EXPORT_CSV,d.opt_export_csv);
   out.opt_export_folder    = config.GetString(CConfigKeys::OPT_EXPORT_FOLDER,d.opt_export_folder);

   return(true);
  }
//+------------------------------------------------------------------+
string CRuntimeConfig::Describe(const SRuntimeConfig &config)
  {
   string text="RuntimeConfig "+config.symbol+" "+EnumToString(config.timeframe);
   text+="\n  magic="+IntegerToString(config.magic);
   //--- Named, not numbered: a bare integer here is what allowed a
   //--- vocabulary mismatch to hide in plain sight in the startup log.
   text+=" sizing="+EnumToString((ENUM_SRP_SIZING_MODEL)config.risk_model);
   text+=" risk%="+DoubleToString(config.risk_percent,2);
   text+=" maxLot="+DoubleToString(config.max_lot,2);
   text+=" maxPositions="+IntegerToString(config.max_positions);
   text+="\n  sl="+DoubleToString(config.sl_fixed_points,0)+"pts";
   text+=" tp="+DoubleToString(config.tp_fixed_points,0)+"pts";
   text+=" maxSpread="+DoubleToString(config.max_spread_points,0)+"pts";
   text+="\n  guards: daily="+DoubleToString(config.daily_loss_percent,2)+"%";
   text+=" weekly="+DoubleToString(config.weekly_loss_percent,2)+"%";
   text+=" monthly="+DoubleToString(config.monthly_loss_percent,2)+"%";
   text+=" maxDD="+DoubleToString(config.max_drawdown_percent,2)+"%";
   text+="\n  decision: voteMode="+IntegerToString(config.vote_mode);
   text+=" minConfidence="+DoubleToString(config.min_confidence,2);
   text+=" minConfirmations="+IntegerToString(config.min_confirmations);
   text+="\n  sessions: london="+(config.allow_london ? "y" : "n");
   text+=" ny="+(config.allow_newyork ? "y" : "n");
   text+=" tokyo="+(config.allow_tokyo ? "y" : "n");
   text+=" sydney="+(config.allow_sydney ? "y" : "n");
   text+="\n  interface: dashboard="+(config.dashboard_enabled ? "on" : "off");
   text+=" overlay="+(config.draw_overlay_enabled ? "on" : "off");
   return(text);
  }

#endif // SRP_RUNTIME_CRUNTIMECONFIG_MQH
//+------------------------------------------------------------------+
