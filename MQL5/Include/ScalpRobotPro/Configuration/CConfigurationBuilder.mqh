//+------------------------------------------------------------------+
//|                                      CConfigurationBuilder.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Configuration : the input-to-provider translation boundary.         |
//|                                                                  |
//|   RESPONSIBILITY (one only): copy the .mq5 input block into a        |
//|   CInputConfiguration and seal it.                                   |
//|                                                                  |
//|   This is the ONE class permitted to know the names of the EA's      |
//|   input variables. Because MQL5 inputs are file-scoped globals, the  |
//|   builder receives them as an explicit parameter struct that the     |
//|   .mq5 file fills in. Everything downstream is input-agnostic, so    |
//|   adding a setting touches this file plus CConfigKeys - never a      |
//|   trading module.                                                    |
//+------------------------------------------------------------------+
#ifndef SRP_CONFIGURATION_CCONFIGURATIONBUILDER_MQH
#define SRP_CONFIGURATION_CCONFIGURATIONBUILDER_MQH

#include "CInputConfiguration.mqh"
#include "CConfigKeys.mqh"
#include "../Core/Types/Enums.mqh"
//--- Phase 2 vocabulary, for the capital-base default below.
#include "../Intelligence/Types/IntelligenceEnums.mqh"

//+------------------------------------------------------------------+
//| Mirror of the EA input block. The .mq5 file fills this struct and |
//| hands it over, which keeps input plumbing out of every module.     |
//+------------------------------------------------------------------+
struct SInputSnapshot
  {
   //--- General
   long              magic;
   string            order_comment;
   ENUM_SRP_DIRECTION_MODE direction_mode;
   int               tick_throttle_ms;
   //--- Multi-timeframe, added in Phase 6. Held as ints so this struct
   //--- stays free of any dependency on the profile system.
   int               context_timeframe;
   int               setup_timeframe;
   //--- Logging
   ENUM_SRP_LOG_LEVEL log_level;
   bool              log_to_file;
   bool              log_to_terminal;
   bool              log_to_alert;
   bool              log_to_push;
   //--- Risk.
   //---
   //--- TWO VOCABULARIES, ONE KEY - READ THIS BEFORE CHANGING IT.
   //--- ENUM_SRP_RISK_MODE (Phase 1) and ENUM_SRP_SIZING_MODEL (Phase 2)
   //--- both describe sizing but NUMBER THEIR MEMBERS DIFFERENTLY:
   //---   RISK_MODE 3 == SRP_RISK_PERCENT_EQUITY
   //---   SIZING    3 == SRP_SIZING_KELLY
   //--- The production engine consumes the SIZING vocabulary. Writing a
   //--- RISK_MODE value into this field therefore silently selects a
   //--- DIFFERENT sizing model: the shipped preset asked for percent-of-
   //--- equity and the engine built a Kelly sizer, which then refused
   //--- every one of 28 valid signals for want of a sample.
   //---
   //--- So this field is authoritative in the SIZING vocabulary, and is
   //--- typed as the sizing enum to make a mismatched assignment a
   //--- compile error rather than a silent behaviour change.
   ENUM_SRP_SIZING_MODEL sizing_model;
   double            fixed_lot;
   double            risk_percent;
   double            max_lot;
   int               max_positions;
   double            max_spread_points;
   int               max_slippage_points;
   double            min_free_margin_percent;
   //--- Protective levels
   ENUM_SRP_SL_MODE  sl_mode;
   double            sl_fixed_points;
   double            sl_atr_multiplier;
   ENUM_SRP_TP_MODE  tp_mode;
   double            tp_fixed_points;
   double            tp_atr_multiplier;
   double            tp_risk_reward;
   ENUM_SRP_TRAIL_MODE trail_mode;
   double            trail_start_points;
   double            trail_step_points;
   double            trail_distance_points;
   bool              breakeven_enabled;
   double            breakeven_trigger_points;
   double            breakeven_offset_points;
   bool              partial_close_enabled;
   double            partial_close_trigger_points;
   double            partial_close_percent;
   bool              time_stop_enabled;
   int               time_stop_minutes;
   //--- Guards
   bool              daily_profit_enabled;
   double            daily_profit_percent;
   bool              daily_loss_enabled;
   double            daily_loss_percent;
   bool              max_drawdown_enabled;
   double            max_drawdown_percent;
   int               consecutive_loss_limit;
   bool              flatten_on_trip;
   //--- HARNESS v2: does a daily-loss breach END the run, or only stand the
   //--- EA down until the next session? These were one flag; they are not
   //--- the same decision.
   bool              daily_limit_terminal;
   bool              kill_switch_enabled;
   //--- Sessions and schedule
   bool              session_filter_enabled;
   bool              allow_sydney;
   bool              allow_tokyo;
   bool              allow_london;
   bool              allow_newyork;
   bool              schedule_enabled;
   bool              holiday_filter_enabled;
   string            holiday_list;
   //--- News
   bool              news_filter_enabled;
   ENUM_SRP_NEWS_SOURCE news_source;
   ENUM_SRP_NEWS_IMPACT news_min_impact;
   int               news_minutes_before;
   int               news_minutes_after;
   bool              news_close_positions;
   string            news_csv_file;
   bool              news_fail_safe_block;
   //--- Filters
   bool              spread_filter_enabled;
   bool              volatility_filter_enabled;
   double            volatility_min_atr;
   double            volatility_max_atr;
   bool              trend_filter_enabled;
   ENUM_TIMEFRAMES   trend_timeframe;
   bool              frequency_filter_enabled;
   int               min_seconds_between_trades;
   int               max_trades_per_day;
   //--- Strategies
   ENUM_SRP_AGGREGATION_MODE aggregation_mode;
   double            min_confidence;
   bool              momentum_enabled;
   double            momentum_weight;
   bool              mean_reversion_enabled;
   double            mean_reversion_weight;
   bool              breakout_enabled;
   double            breakout_weight;
   //--- Indicators
   int               fast_ma_period;
   int               slow_ma_period;
   int               trend_ma_period;
   int               rsi_period;
   int               atr_period;
   int               adx_period;
   int               bollinger_period;
   double            bollinger_deviation;
   //--- Dashboard
   bool              dashboard_enabled;
   ENUM_SRP_THEME    dashboard_theme;
   int               dashboard_corner;
   int               dashboard_x_offset;
   int               dashboard_y_offset;
   bool              dashboard_show_in_tester;
   //--- Statistics
   bool              journal_enabled;
   bool              persist_state;
   string            state_folder;
   //--- Optimisation
   ENUM_SRP_OPTIMIZATION_CRITERION opt_criterion;
   int               opt_min_trades;

   //=== ADDED IN THE PRODUCTION PHASE ================================
   //--- Phases 2-4 added whole subsystems. Appending keeps every existing
   //--- field at its current name, so nothing that reads this breaks.

   //--- Logging (Phase 4 enterprise logger)
   bool              log_daily_rotation;
   string            log_folder;
   bool              log_channel_errors;
   bool              log_channel_trades;
   bool              log_channel_indicators;
   bool              log_channel_risk;
   bool              log_channel_performance;
   bool              log_channel_execution;
   int               log_format_default;
   bool              log_mirror_errors_to_journal;
   int               log_flush_every;
   //--- Risk (Phase 2 sizing and limits)
   double            kelly_fraction;
   int               kelly_min_trades;
   //--- ENUM_SRP_CAPITAL_BASE: which capital figure a percentage model
   //--- measures against. Held as int so this struct stays independent
   //--- of the Phase 2 vocabulary.
   int               risk_capital_base;
   double            auto_lot_capital_per_step;
   double            auto_lot_per_step;
   double            atr_risk_multiple;
   double            weekly_loss_percent;
   double            monthly_loss_percent;
   //--- Ceiling on total simultaneous risk across all open positions.
   double            max_exposure_percent;
   bool              profit_lock_enabled;
   double            profit_lock_trigger_percent;
   double            profit_lock_keep_percent;
   //--- Trade manager (Phase 4)
   bool              tm_atr_trail_enabled;
   double            tm_atr_trail_multiple;
   bool              tm_atr_exit_enabled;
   double            tm_atr_exit_multiple;
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
   //--- Sessions (Phase 3)
   bool              kill_zones_only;
   bool              require_overlap;
   bool              weekend_filter;
   int               broker_gmt_offset;
   bool              dst_adjust;
   int               friday_close_minutes;
   //--- Session window times in GMT minutes, added in Phase 6 so each
   //--- asset keeps its own schedule instead of sharing hardcoded hours.
   int               london_open_gmt;
   int               london_close_gmt;
   int               newyork_open_gmt;
   int               newyork_close_gmt;
   int               primary_kz_open_gmt;
   int               primary_kz_close_gmt;
   int               skip_after_open_minutes;
   int               skip_before_close_minutes;
   //--- News (Phase 3)
   string            news_currency_filter;
   //--- Filters
   int               max_trades_per_hour;
   //--- Decision engine (Phase 3)
   int               decision_vote_mode;
   int               decision_min_confirmations;
   double            decision_min_confidence;
   int               decision_max_risk_rating;
   bool              require_confirmation;
   bool              ema_cross_enabled;
   bool              vwap_pullback_enabled;
   bool              liquidity_sweep_enabled;
   bool              order_block_enabled;
   bool              fvg_enabled;
   bool              opening_range_enabled;
   bool              trend_continuation_enabled;
   //--- Added in Phase 6.
   bool              bos_enabled;
   double            bos_weight;
   bool              volatility_breakout_enabled;
   double            volatility_breakout_weight;
   //--- Order flow / volume delta (OBV + MFI + relative volume).
   bool              order_flow_enabled;
   double            order_flow_weight;
   double            order_flow_min_volume;
   //--- Ultra-scalp mode.
   bool              scalp_mode_enabled;
   int               scalp_cooldown_seconds;
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
   //--- Scalp tiers, flattened so this struct stays free of the tier enum.
   //--- Index order is SUPER, STANDARD, SWING.
   bool              tier_enabled[3];
   double            tier_target_atr[3];
   double            tier_stop_atr[3];
   int               tier_hold_seconds[3];
   double            tier_win_rate[3];
   int               tier_timeframe[3];
   double            scalp_atr_min_points;
   double            scalp_atr_max_points;
   //--- HARNESS v2, FIX 4. Reporting only. Held as the enum rather than an
   //--- int so the EA input, this snapshot and the report header all name
   //--- the same three states instead of agreeing on 0, 1 and 2.
   ENUM_SRP_DATA_SEGMENT data_segment;
   //--- HARNESS v2, FIX 5. Points, 0.0 = use the live tick. Unlike the
   //--- segment above this is NOT reporting-only: at any positive value it
   //--- replaces the root that twelve trading distances descend from.
   double            pin_spread_sample;
   //--- Entry quality gate (Phase 7)
   bool              accuracy_filter_enabled;
   bool              accuracy_require_setup;
   bool              accuracy_require_context;
   double            accuracy_min_relative_volume;
   int               accuracy_volume_lookback;
   double            accuracy_max_extension;
   double            accuracy_min_score;
   //--- Smart money concepts (Phase 2)
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
   //--- Dashboard and overlay (Phase 4)
   int               dashboard_refresh_ms;
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
   //--- Analytics (Phase 4)
   int               analytics_min_sample;
   bool              analytics_use_r_multiples;
   double            analytics_initial_balance;
   //--- Optimisation
   double            opt_drawdown_penalty;
   double            opt_concentration_penalty;
   double            opt_streak_penalty;
   bool              opt_walk_forward_enabled;
   int               opt_wf_is_days;
   int               opt_wf_oos_days;
   double            opt_wf_min_efficiency;
   bool              opt_monte_carlo_enabled;
   int               opt_monte_carlo_runs;
   int               opt_monte_carlo_seed;
   double            opt_monte_carlo_ruin_percent;
   bool              opt_export_csv;
   string            opt_export_folder;
   bool              opt_forward_test_mode;
   bool              opt_reject_incoherent;
  };

class CConfigurationBuilder
  {
private:
   //--- One method per section, mirroring CConfigValidator's grouping
   //--- so the two stay easy to keep in sync.
   static void       ApplyGeneral(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyLogging(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyRisk(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyStopLevels(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyGuards(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplySchedule(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyNews(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyFilters(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyStrategies(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyIndicators(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyDashboard(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyStatistics(CInputConfiguration *config,const SInputSnapshot &in);
   static void       ApplyOptimization(CInputConfiguration *config,const SInputSnapshot &in);

public:
   //--- Populates and seals the provider. Returns false when a key
   //--- could not be stored, which aborts startup.
   static bool       Populate(CInputConfiguration *config,const SInputSnapshot &in);

   //--- Fills the snapshot with the NASDAQ-scalping defaults documented
   //--- in the user manual. The .mq5 input block starts from these, so
   //--- the shipped preset and the code cannot drift apart.
   static void       ApplyNasdaqDefaults(SInputSnapshot &in);
  };

//+------------------------------------------------------------------+
bool CConfigurationBuilder::Populate(CInputConfiguration *config,
                                     const SInputSnapshot &in)
  {
   if(config==NULL)
      return(false);

   ApplyGeneral(config,in);
   ApplyLogging(config,in);
   ApplyRisk(config,in);
   ApplyStopLevels(config,in);
   ApplyGuards(config,in);
   ApplySchedule(config,in);
   ApplyNews(config,in);
   ApplyFilters(config,in);
   ApplyStrategies(config,in);
   ApplyIndicators(config,in);
   ApplyDashboard(config,in);
   ApplyStatistics(config,in);
   ApplyOptimization(config,in);

   //--- Sealing here, and only here, is what makes configuration
   //--- immutable for the rest of the run.
   config.Seal();
   return(config.Count()>0);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyGeneral(CInputConfiguration *config,
                                         const SInputSnapshot &in)
  {
   config.SetLong(CConfigKeys::GENERAL_MAGIC,in.magic);
   config.SetString(CConfigKeys::GENERAL_ORDER_COMMENT,in.order_comment);
   config.SetInt(CConfigKeys::GENERAL_DIRECTION_MODE,(int)in.direction_mode);
   config.SetInt(CConfigKeys::GENERAL_TICK_THROTTLE_MS,in.tick_throttle_ms);
   config.SetInt(CConfigKeys::GENERAL_CONTEXT_TIMEFRAME,in.context_timeframe);
   config.SetInt(CConfigKeys::GENERAL_SETUP_TIMEFRAME,in.setup_timeframe);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyLogging(CInputConfiguration *config,
                                         const SInputSnapshot &in)
  {
   config.SetInt(CConfigKeys::LOG_LEVEL,(int)in.log_level);
   config.SetBool(CConfigKeys::LOG_TO_FILE,in.log_to_file);
   config.SetBool(CConfigKeys::LOG_TO_TERMINAL,in.log_to_terminal);
   config.SetBool(CConfigKeys::LOG_TO_ALERT,in.log_to_alert);
   config.SetBool(CConfigKeys::LOG_TO_PUSH,in.log_to_push);
   config.SetBool(CConfigKeys::LOG_DAILY_ROTATION,in.log_daily_rotation);
   config.SetString(CConfigKeys::LOG_FOLDER,in.log_folder);
   config.SetBool(CConfigKeys::LOG_CHANNEL_ERRORS,in.log_channel_errors);
   config.SetBool(CConfigKeys::LOG_CHANNEL_TRADES,in.log_channel_trades);
   config.SetBool(CConfigKeys::LOG_CHANNEL_INDICATORS,in.log_channel_indicators);
   config.SetBool(CConfigKeys::LOG_CHANNEL_RISK,in.log_channel_risk);
   config.SetBool(CConfigKeys::LOG_CHANNEL_PERFORMANCE,in.log_channel_performance);
   config.SetBool(CConfigKeys::LOG_CHANNEL_EXECUTION,in.log_channel_execution);
   config.SetInt(CConfigKeys::LOG_FORMAT_DEFAULT,in.log_format_default);
   config.SetBool(CConfigKeys::LOG_MIRROR_ERRORS_TO_JOURNAL,
                  in.log_mirror_errors_to_journal);
   config.SetInt(CConfigKeys::LOG_FLUSH_EVERY,in.log_flush_every);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyRisk(CInputConfiguration *config,
                                      const SInputSnapshot &in)
  {
   //--- Stored in the SIZING vocabulary, which is what the runtime reads.
   config.SetInt(CConfigKeys::RISK_MODE,(int)in.sizing_model);
   config.SetDouble(CConfigKeys::RISK_FIXED_LOT,in.fixed_lot);
   config.SetDouble(CConfigKeys::RISK_PERCENT,in.risk_percent);
   config.SetDouble(CConfigKeys::RISK_MAX_LOT,in.max_lot);
   config.SetInt(CConfigKeys::RISK_MAX_POSITIONS,in.max_positions);
   config.SetInt(CConfigKeys::RISK_CAPITAL_BASE,in.risk_capital_base);
   config.SetInt(CConfigKeys::RISK_KELLY_MIN_TRADES,in.kelly_min_trades);
   config.SetDouble(CConfigKeys::RISK_AUTO_LOT_CAPITAL_PER_STEP,
                    in.auto_lot_capital_per_step);
   config.SetDouble(CConfigKeys::RISK_AUTO_LOT_PER_STEP,in.auto_lot_per_step);
   config.SetDouble(CConfigKeys::RISK_MAX_SPREAD_POINTS,in.max_spread_points);
   config.SetInt(CConfigKeys::RISK_MAX_SLIPPAGE_POINTS,in.max_slippage_points);
   config.SetDouble(CConfigKeys::RISK_MIN_FREE_MARGIN_PERCENT,
                    in.min_free_margin_percent);
   config.SetDouble(CConfigKeys::RISK_KELLY_FRACTION,in.kelly_fraction);
   config.SetDouble(CConfigKeys::RISK_ATR_RISK_MULTIPLE,in.atr_risk_multiple);
   config.SetDouble(CConfigKeys::RISK_WEEKLY_LOSS_PERCENT,in.weekly_loss_percent);
   config.SetDouble(CConfigKeys::RISK_MONTHLY_LOSS_PERCENT,in.monthly_loss_percent);
   config.SetDouble(CConfigKeys::RISK_MAX_RISK_PERCENT_TOTAL,
                    in.max_exposure_percent);
   config.SetBool(CConfigKeys::RISK_PROFIT_LOCK_ENABLED,in.profit_lock_enabled);
   config.SetDouble(CConfigKeys::RISK_PROFIT_LOCK_TRIGGER_PERCENT,
                    in.profit_lock_trigger_percent);
   config.SetDouble(CConfigKeys::RISK_PROFIT_LOCK_KEEP_PERCENT,
                    in.profit_lock_keep_percent);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyStopLevels(CInputConfiguration *config,
                                            const SInputSnapshot &in)
  {
   config.SetInt(CConfigKeys::SL_MODE,(int)in.sl_mode);
   config.SetDouble(CConfigKeys::SL_FIXED_POINTS,in.sl_fixed_points);
   config.SetDouble(CConfigKeys::SL_ATR_MULTIPLIER,in.sl_atr_multiplier);
   config.SetInt(CConfigKeys::TP_MODE,(int)in.tp_mode);
   config.SetDouble(CConfigKeys::TP_FIXED_POINTS,in.tp_fixed_points);
   config.SetDouble(CConfigKeys::TP_ATR_MULTIPLIER,in.tp_atr_multiplier);
   config.SetDouble(CConfigKeys::TP_RISK_REWARD,in.tp_risk_reward);
   config.SetInt(CConfigKeys::TRAIL_MODE,(int)in.trail_mode);
   config.SetDouble(CConfigKeys::TRAIL_START_POINTS,in.trail_start_points);
   config.SetDouble(CConfigKeys::TRAIL_STEP_POINTS,in.trail_step_points);
   config.SetDouble(CConfigKeys::TRAIL_DISTANCE_POINTS,in.trail_distance_points);
   config.SetBool(CConfigKeys::BREAKEVEN_ENABLED,in.breakeven_enabled);
   config.SetDouble(CConfigKeys::BREAKEVEN_TRIGGER_POINTS,
                    in.breakeven_trigger_points);
   config.SetDouble(CConfigKeys::BREAKEVEN_OFFSET_POINTS,
                    in.breakeven_offset_points);
   config.SetBool(CConfigKeys::PARTIAL_CLOSE_ENABLED,in.partial_close_enabled);
   config.SetDouble(CConfigKeys::PARTIAL_CLOSE_TRIGGER_POINTS,
                    in.partial_close_trigger_points);
   config.SetDouble(CConfigKeys::PARTIAL_CLOSE_PERCENT,in.partial_close_percent);
   config.SetBool(CConfigKeys::TIME_STOP_ENABLED,in.time_stop_enabled);
   config.SetInt(CConfigKeys::TIME_STOP_MINUTES,in.time_stop_minutes);

   //--- Phase 4 trade manager.
   config.SetBool(CConfigKeys::TM_ATR_TRAIL_ENABLED,in.tm_atr_trail_enabled);
   config.SetDouble(CConfigKeys::TM_ATR_TRAIL_MULTIPLE,in.tm_atr_trail_multiple);
   config.SetBool(CConfigKeys::TM_ATR_EXIT_ENABLED,in.tm_atr_exit_enabled);
   config.SetDouble(CConfigKeys::TM_ATR_EXIT_MULTIPLE,in.tm_atr_exit_multiple);
   config.SetBool(CConfigKeys::TM_MAX_HOLD_ENABLED,in.tm_max_hold_enabled);
   config.SetInt(CConfigKeys::TM_MAX_HOLD_MINUTES,in.tm_max_hold_minutes);
   config.SetBool(CConfigKeys::TM_SCALE_IN_ENABLED,in.tm_scale_in_enabled);
   config.SetDouble(CConfigKeys::TM_SCALE_IN_TRIGGER_POINTS,
                    in.tm_scale_in_trigger_points);
   config.SetDouble(CConfigKeys::TM_SCALE_IN_FRACTION,in.tm_scale_in_fraction);
   config.SetInt(CConfigKeys::TM_SCALE_IN_MAX,in.tm_scale_in_max);
   config.SetBool(CConfigKeys::TM_SCALE_OUT_ENABLED,in.tm_scale_out_enabled);
   config.SetDouble(CConfigKeys::TM_SCALE_OUT_TRIGGER_POINTS,
                    in.tm_scale_out_trigger_points);
   config.SetDouble(CConfigKeys::TM_SCALE_OUT_FRACTION,in.tm_scale_out_fraction);
   config.SetInt(CConfigKeys::TM_SCALE_OUT_MAX,in.tm_scale_out_max);
   config.SetBool(CConfigKeys::TM_REVERSE_ENABLED,in.tm_reverse_enabled);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyGuards(CInputConfiguration *config,
                                        const SInputSnapshot &in)
  {
   config.SetBool(CConfigKeys::GUARD_DAILY_PROFIT_ENABLED,in.daily_profit_enabled);
   config.SetDouble(CConfigKeys::GUARD_DAILY_PROFIT_PERCENT,in.daily_profit_percent);
   config.SetBool(CConfigKeys::GUARD_DAILY_LOSS_ENABLED,in.daily_loss_enabled);
   config.SetDouble(CConfigKeys::GUARD_DAILY_LOSS_PERCENT,in.daily_loss_percent);
   config.SetBool(CConfigKeys::GUARD_MAX_DRAWDOWN_ENABLED,in.max_drawdown_enabled);
   config.SetDouble(CConfigKeys::GUARD_MAX_DRAWDOWN_PERCENT,in.max_drawdown_percent);
   config.SetInt(CConfigKeys::GUARD_CONSECUTIVE_LOSS_LIMIT,
                 in.consecutive_loss_limit);
   config.SetBool(CConfigKeys::GUARD_FLATTEN_ON_TRIP,in.flatten_on_trip);
   config.SetBool(CConfigKeys::GUARD_DAILY_LIMIT_TERMINAL,
                  in.daily_limit_terminal);
   config.SetBool(CConfigKeys::KILL_SWITCH_ENABLED,in.kill_switch_enabled);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplySchedule(CInputConfiguration *config,
                                          const SInputSnapshot &in)
  {
   config.SetBool(CConfigKeys::SESSION_FILTER_ENABLED,in.session_filter_enabled);
   config.SetBool(CConfigKeys::SESSION_ALLOW_SYDNEY,in.allow_sydney);
   config.SetBool(CConfigKeys::SESSION_ALLOW_TOKYO,in.allow_tokyo);
   config.SetBool(CConfigKeys::SESSION_ALLOW_LONDON,in.allow_london);
   config.SetBool(CConfigKeys::SESSION_ALLOW_NEWYORK,in.allow_newyork);
   config.SetBool(CConfigKeys::SCHEDULE_ENABLED,in.schedule_enabled);
   config.SetBool(CConfigKeys::HOLIDAY_FILTER_ENABLED,in.holiday_filter_enabled);
   config.SetString(CConfigKeys::HOLIDAY_LIST,in.holiday_list);
   config.SetBool(CConfigKeys::SESSION_KILL_ZONES_ONLY,in.kill_zones_only);
   config.SetBool(CConfigKeys::SESSION_REQUIRE_OVERLAP,in.require_overlap);
   config.SetBool(CConfigKeys::SESSION_WEEKEND_FILTER,in.weekend_filter);
   config.SetInt(CConfigKeys::SESSION_BROKER_GMT_OFFSET,in.broker_gmt_offset);
   config.SetBool(CConfigKeys::SESSION_DST_ADJUST,in.dst_adjust);
   config.SetInt(CConfigKeys::SCHEDULE_FRIDAY_CLOSE_MINUTES,
                 in.friday_close_minutes);
   config.SetInt(CConfigKeys::SESSION_LONDON_OPEN_GMT,in.london_open_gmt);
   config.SetInt(CConfigKeys::SESSION_LONDON_CLOSE_GMT,in.london_close_gmt);
   config.SetInt(CConfigKeys::SESSION_NEWYORK_OPEN_GMT,in.newyork_open_gmt);
   config.SetInt(CConfigKeys::SESSION_NEWYORK_CLOSE_GMT,in.newyork_close_gmt);
   config.SetInt(CConfigKeys::SESSION_PRIMARY_KZ_OPEN_GMT,
                 in.primary_kz_open_gmt);
   config.SetInt(CConfigKeys::SESSION_PRIMARY_KZ_CLOSE_GMT,
                 in.primary_kz_close_gmt);
   config.SetInt(CConfigKeys::SESSION_SKIP_AFTER_OPEN,
                 in.skip_after_open_minutes);
   config.SetInt(CConfigKeys::SESSION_SKIP_BEFORE_CLOSE,
                 in.skip_before_close_minutes);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyNews(CInputConfiguration *config,
                                      const SInputSnapshot &in)
  {
   config.SetBool(CConfigKeys::NEWS_FILTER_ENABLED,in.news_filter_enabled);
   config.SetInt(CConfigKeys::NEWS_SOURCE,(int)in.news_source);
   config.SetInt(CConfigKeys::NEWS_MIN_IMPACT,(int)in.news_min_impact);
   config.SetInt(CConfigKeys::NEWS_MINUTES_BEFORE,in.news_minutes_before);
   config.SetInt(CConfigKeys::NEWS_MINUTES_AFTER,in.news_minutes_after);
   config.SetBool(CConfigKeys::NEWS_CLOSE_POSITIONS,in.news_close_positions);
   config.SetString(CConfigKeys::NEWS_CSV_FILE,in.news_csv_file);
   config.SetBool(CConfigKeys::NEWS_FAIL_SAFE_BLOCK,in.news_fail_safe_block);
   config.SetString(CConfigKeys::NEWS_CURRENCY_FILTER,in.news_currency_filter);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyFilters(CInputConfiguration *config,
                                         const SInputSnapshot &in)
  {
   config.SetBool(CConfigKeys::FILTER_SPREAD_ENABLED,in.spread_filter_enabled);
   config.SetBool(CConfigKeys::FILTER_VOLATILITY_ENABLED,
                  in.volatility_filter_enabled);
   config.SetDouble(CConfigKeys::FILTER_VOLATILITY_MIN_ATR,in.volatility_min_atr);
   config.SetDouble(CConfigKeys::FILTER_VOLATILITY_MAX_ATR,in.volatility_max_atr);
   config.SetBool(CConfigKeys::FILTER_TREND_ENABLED,in.trend_filter_enabled);
   config.SetInt(CConfigKeys::FILTER_TREND_TIMEFRAME,(int)in.trend_timeframe);
   config.SetBool(CConfigKeys::FILTER_FREQUENCY_ENABLED,
                  in.frequency_filter_enabled);
   config.SetInt(CConfigKeys::FILTER_MIN_SECONDS_BETWEEN_TRADES,
                 in.min_seconds_between_trades);
   config.SetInt(CConfigKeys::FILTER_MAX_TRADES_PER_DAY,in.max_trades_per_day);
   config.SetInt(CConfigKeys::FILTER_MAX_TRADES_PER_HOUR,in.max_trades_per_hour);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyStrategies(CInputConfiguration *config,
                                            const SInputSnapshot &in)
  {
   config.SetInt(CConfigKeys::STRATEGY_AGGREGATION_MODE,(int)in.aggregation_mode);
   config.SetDouble(CConfigKeys::STRATEGY_MIN_CONFIDENCE,in.min_confidence);
   config.SetBool(CConfigKeys::STRATEGY_MOMENTUM_ENABLED,in.momentum_enabled);
   config.SetDouble(CConfigKeys::STRATEGY_MOMENTUM_WEIGHT,in.momentum_weight);
   config.SetBool(CConfigKeys::STRATEGY_MEAN_REVERSION_ENABLED,
                  in.mean_reversion_enabled);
   config.SetDouble(CConfigKeys::STRATEGY_MEAN_REVERSION_WEIGHT,
                    in.mean_reversion_weight);
   config.SetBool(CConfigKeys::STRATEGY_BREAKOUT_ENABLED,in.breakout_enabled);
   config.SetDouble(CConfigKeys::STRATEGY_BREAKOUT_WEIGHT,in.breakout_weight);

   config.SetInt(CConfigKeys::DECISION_VOTE_MODE,in.decision_vote_mode);
   config.SetInt(CConfigKeys::DECISION_MIN_CONFIRMATIONS,
                 in.decision_min_confirmations);
   config.SetDouble(CConfigKeys::DECISION_MIN_CONFIDENCE,
                    in.decision_min_confidence);
   config.SetInt(CConfigKeys::DECISION_MAX_RISK_RATING,in.decision_max_risk_rating);
   config.SetBool(CConfigKeys::DECISION_REQUIRE_CONFIRMATION,
                  in.require_confirmation);
   config.SetBool(CConfigKeys::STRATEGY_EMA_CROSS_ENABLED,in.ema_cross_enabled);
   config.SetBool(CConfigKeys::STRATEGY_VWAP_PULLBACK_ENABLED,
                  in.vwap_pullback_enabled);
   config.SetBool(CConfigKeys::STRATEGY_LIQUIDITY_SWEEP_ENABLED,
                  in.liquidity_sweep_enabled);
   config.SetBool(CConfigKeys::STRATEGY_ORDER_BLOCK_ENABLED,in.order_block_enabled);
   config.SetBool(CConfigKeys::STRATEGY_FVG_ENABLED,in.fvg_enabled);
   config.SetBool(CConfigKeys::STRATEGY_OPENING_RANGE_ENABLED,
                  in.opening_range_enabled);
   config.SetBool(CConfigKeys::STRATEGY_TREND_CONTINUATION_ENABLED,
                  in.trend_continuation_enabled);
   config.SetBool(CConfigKeys::STRATEGY_BOS_ENABLED,in.bos_enabled);
   config.SetDouble(CConfigKeys::STRATEGY_BOS_WEIGHT,in.bos_weight);
   config.SetBool(CConfigKeys::STRATEGY_VOLATILITY_BREAKOUT_ENABLED,
                  in.volatility_breakout_enabled);
   config.SetDouble(CConfigKeys::STRATEGY_VOLATILITY_BREAKOUT_WEIGHT,
                    in.volatility_breakout_weight);
   config.SetBool(CConfigKeys::STRATEGY_ORDER_FLOW_ENABLED,in.order_flow_enabled);
   config.SetDouble(CConfigKeys::STRATEGY_ORDER_FLOW_WEIGHT,in.order_flow_weight);
   config.SetDouble(CConfigKeys::STRATEGY_ORDER_FLOW_MIN_VOLUME,
                    in.order_flow_min_volume);

   //--- Ultra-scalp mode.
   config.SetBool(CConfigKeys::SCALP_MODE_ENABLED,in.scalp_mode_enabled);
   config.SetInt(CConfigKeys::SCALP_COOLDOWN_SECONDS,in.scalp_cooldown_seconds);
   config.SetInt(CConfigKeys::SCALP_MAX_HOLD_SECONDS,in.scalp_max_hold_seconds);
   config.SetDouble(CConfigKeys::SCALP_TARGET_ATR_MULTIPLE,
                    in.scalp_target_atr_multiple);
   config.SetDouble(CConfigKeys::SCALP_TARGET_MIN_POINTS,
                    in.scalp_target_min_points);
   config.SetDouble(CConfigKeys::SCALP_TARGET_MAX_POINTS,
                    in.scalp_target_max_points);
   config.SetDouble(CConfigKeys::SCALP_STOP_ATR_MULTIPLE,
                    in.scalp_stop_atr_multiple);
   config.SetDouble(CConfigKeys::SCALP_COMMISSION_POINTS,
                    in.scalp_commission_points);
   config.SetDouble(CConfigKeys::SCALP_EXECUTION_COST_POINTS,
                    in.scalp_execution_cost_points);
   config.SetDouble(CConfigKeys::SCALP_MIN_REWARD_COST_RATIO,
                    in.scalp_min_reward_cost_ratio);
   config.SetDouble(CConfigKeys::SCALP_MAX_SPREAD_TARGET_RATIO,
                    in.scalp_max_spread_target_ratio);
   config.SetBool(CConfigKeys::SCALP_EARLY_EXIT_ENABLED,
                  in.scalp_early_exit_enabled);
   config.SetDouble(CConfigKeys::SCALP_EARLY_EXIT_MIN_POINTS,
                    in.scalp_early_exit_min_points);
   config.SetDouble(CConfigKeys::SCALP_EARLY_EXIT_TARGET_SHARE,
                    in.scalp_early_exit_target_share);
   config.SetDouble(CConfigKeys::SCALP_ATR_MIN_POINTS,in.scalp_atr_min_points);
   config.SetDouble(CConfigKeys::SCALP_ATR_MAX_POINTS,in.scalp_atr_max_points);

   //--- HARNESS v2, FIX 4. Stored through the same keyed path as everything
   //--- else so that a set file, a profile and an input block cannot
   //--- disagree about what the run claims to be.
   config.SetInt(CConfigKeys::GENERAL_DATA_SEGMENT,(int)in.data_segment);

   //--- HARNESS v2, FIX 5. Same keyed path, for the opposite reason: this
   //--- one moves orders, so it must be visible to the validator and to the
   //--- report header rather than reaching the engine through a side door.
   config.SetDouble(CConfigKeys::GENERAL_PIN_SPREAD_SAMPLE,
                    in.pin_spread_sample);

   config.SetBool(CConfigKeys::ACCURACY_FILTER_ENABLED,in.accuracy_filter_enabled);
   config.SetBool(CConfigKeys::ACCURACY_REQUIRE_SETUP,in.accuracy_require_setup);
   config.SetBool(CConfigKeys::ACCURACY_REQUIRE_CONTEXT,in.accuracy_require_context);
   config.SetDouble(CConfigKeys::ACCURACY_MIN_RELATIVE_VOLUME,
                    in.accuracy_min_relative_volume);
   config.SetInt(CConfigKeys::ACCURACY_VOLUME_LOOKBACK,in.accuracy_volume_lookback);
   config.SetDouble(CConfigKeys::ACCURACY_MAX_EXTENSION,in.accuracy_max_extension);
   config.SetDouble(CConfigKeys::ACCURACY_MIN_SCORE,in.accuracy_min_score);

   //--- Tiers, one key set per index.
   for(int t=0;t<3;t++)
     {
      const string sfx=IntegerToString(t);
      config.SetBool(CConfigKeys::TIER_ENABLED_PREFIX+sfx,in.tier_enabled[t]);
      config.SetDouble(CConfigKeys::TIER_TARGET_ATR_PREFIX+sfx,
                       in.tier_target_atr[t]);
      config.SetDouble(CConfigKeys::TIER_STOP_ATR_PREFIX+sfx,
                       in.tier_stop_atr[t]);
      config.SetInt(CConfigKeys::TIER_HOLD_SECONDS_PREFIX+sfx,
                    in.tier_hold_seconds[t]);
      config.SetDouble(CConfigKeys::TIER_WIN_RATE_PREFIX+sfx,
                       in.tier_win_rate[t]);
      config.SetInt(CConfigKeys::TIER_TIMEFRAME_PREFIX+sfx,
                    in.tier_timeframe[t]);
     }
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyIndicators(CInputConfiguration *config,
                                            const SInputSnapshot &in)
  {
   config.SetInt(CConfigKeys::INDICATOR_FAST_MA_PERIOD,in.fast_ma_period);
   config.SetInt(CConfigKeys::INDICATOR_SLOW_MA_PERIOD,in.slow_ma_period);
   config.SetInt(CConfigKeys::INDICATOR_TREND_MA_PERIOD,in.trend_ma_period);
   config.SetInt(CConfigKeys::INDICATOR_RSI_PERIOD,in.rsi_period);
   config.SetInt(CConfigKeys::INDICATOR_ATR_PERIOD,in.atr_period);
   config.SetInt(CConfigKeys::INDICATOR_ADX_PERIOD,in.adx_period);
   config.SetInt(CConfigKeys::INDICATOR_BOLLINGER_PERIOD,in.bollinger_period);
   config.SetDouble(CConfigKeys::INDICATOR_BOLLINGER_DEVIATION,
                    in.bollinger_deviation);

   config.SetBool(CConfigKeys::SMC_ENABLED,in.smc_enabled);
   config.SetInt(CConfigKeys::SMC_SWING_STRENGTH,in.smc_swing_strength);
   config.SetInt(CConfigKeys::SMC_SWING_LOOKBACK,in.smc_swing_lookback);
   config.SetInt(CConfigKeys::SMC_ZONE_CAPACITY,in.smc_zone_capacity);
   config.SetInt(CConfigKeys::SMC_ZONE_MAX_AGE_BARS,in.smc_zone_max_age_bars);
   config.SetDouble(CConfigKeys::SMC_DISPLACEMENT_ATR_MULTIPLE,
                    in.smc_displacement_atr_multiple);
   config.SetDouble(CConfigKeys::SMC_MIN_GAP_POINTS,in.smc_min_gap_points);
   config.SetBool(CConfigKeys::SMC_REQUIRE_DISPLACEMENT,
                  in.smc_require_displacement);
   config.SetDouble(CConfigKeys::SMC_EQUAL_TOLERANCE_ATR,
                    in.smc_equal_tolerance_atr);
   config.SetInt(CConfigKeys::SMC_SWEEP_LOOKBACK_BARS,in.smc_sweep_lookback_bars);
   config.SetDouble(CConfigKeys::SMC_STRUCTURE_BREAK_BUFFER,
                    in.smc_structure_break_buffer);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyDashboard(CInputConfiguration *config,
                                           const SInputSnapshot &in)
  {
   config.SetBool(CConfigKeys::DASHBOARD_ENABLED,in.dashboard_enabled);
   config.SetInt(CConfigKeys::DASHBOARD_THEME,(int)in.dashboard_theme);
   config.SetInt(CConfigKeys::DASHBOARD_CORNER,in.dashboard_corner);
   config.SetInt(CConfigKeys::DASHBOARD_X_OFFSET,in.dashboard_x_offset);
   config.SetInt(CConfigKeys::DASHBOARD_Y_OFFSET,in.dashboard_y_offset);
   config.SetInt(CConfigKeys::DASHBOARD_REFRESH_MS,in.dashboard_refresh_ms);
   config.SetBool(CConfigKeys::DASHBOARD_SHOW_IN_TESTER,
                  in.dashboard_show_in_tester);

   config.SetBool(CConfigKeys::DRAW_OVERLAY_ENABLED,in.draw_overlay_enabled);
   config.SetBool(CConfigKeys::DRAW_ENTRIES,in.draw_entries);
   config.SetBool(CConfigKeys::DRAW_STOPS,in.draw_stops);
   config.SetBool(CConfigKeys::DRAW_ZONES,in.draw_zones);
   config.SetBool(CConfigKeys::DRAW_LIQUIDITY,in.draw_liquidity);
   config.SetBool(CConfigKeys::DRAW_STRUCTURE,in.draw_structure);
   config.SetBool(CConfigKeys::DRAW_SESSION_BOXES,in.draw_session_boxes);
   config.SetBool(CConfigKeys::DRAW_TRADE_LABELS,in.draw_trade_labels);
   config.SetBool(CConfigKeys::DRAW_STATISTICS,in.draw_statistics);
   config.SetInt(CConfigKeys::DRAW_MAX_ZONES,in.draw_max_zones);
   config.SetInt(CConfigKeys::DRAW_ZONE_EXTEND_BARS,in.draw_zone_extend_bars);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyStatistics(CInputConfiguration *config,
                                            const SInputSnapshot &in)
  {
   config.SetBool(CConfigKeys::STATS_JOURNAL_ENABLED,in.journal_enabled);
   config.SetBool(CConfigKeys::STATS_PERSIST_STATE,in.persist_state);
   config.SetString(CConfigKeys::STATS_STATE_FOLDER,in.state_folder);
   config.SetInt(CConfigKeys::ANALYTICS_MIN_SAMPLE,in.analytics_min_sample);
   config.SetBool(CConfigKeys::ANALYTICS_USE_R_MULTIPLES,
                  in.analytics_use_r_multiples);
   config.SetDouble(CConfigKeys::ANALYTICS_INITIAL_BALANCE,
                    in.analytics_initial_balance);
  }
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyOptimization(CInputConfiguration *config,
                                              const SInputSnapshot &in)
  {
   config.SetInt(CConfigKeys::OPT_CRITERION,(int)in.opt_criterion);
   config.SetInt(CConfigKeys::OPT_MIN_TRADES,in.opt_min_trades);
   config.SetDouble(CConfigKeys::OPT_MAX_DRAWDOWN_PENALTY,
                    in.opt_drawdown_penalty);
   config.SetDouble(CConfigKeys::OPT_CONCENTRATION_PENALTY,
                    in.opt_concentration_penalty);
   config.SetDouble(CConfigKeys::OPT_STREAK_PENALTY,in.opt_streak_penalty);
   config.SetBool(CConfigKeys::OPT_WALK_FORWARD_ENABLED,in.opt_walk_forward_enabled);
   config.SetInt(CConfigKeys::OPT_WALK_FORWARD_IS_DAYS,in.opt_wf_is_days);
   config.SetInt(CConfigKeys::OPT_WALK_FORWARD_OOS_DAYS,in.opt_wf_oos_days);
   config.SetDouble(CConfigKeys::OPT_WALK_FORWARD_MIN_EFFICIENCY,
                    in.opt_wf_min_efficiency);
   config.SetBool(CConfigKeys::OPT_MONTE_CARLO_ENABLED,in.opt_monte_carlo_enabled);
   config.SetInt(CConfigKeys::OPT_MONTE_CARLO_RUNS,in.opt_monte_carlo_runs);
   config.SetInt(CConfigKeys::OPT_MONTE_CARLO_SEED,in.opt_monte_carlo_seed);
   config.SetDouble(CConfigKeys::OPT_MONTE_CARLO_RUIN_PERCENT,
                    in.opt_monte_carlo_ruin_percent);
   config.SetBool(CConfigKeys::OPT_EXPORT_CSV,in.opt_export_csv);
   config.SetString(CConfigKeys::OPT_EXPORT_FOLDER,in.opt_export_folder);
   config.SetBool(CConfigKeys::OPT_FORWARD_TEST_MODE,in.opt_forward_test_mode);
   config.SetBool(CConfigKeys::OPT_REJECT_INCOHERENT,in.opt_reject_incoherent);
  }
//+------------------------------------------------------------------+
//| NASDAQ scalping defaults.                                          |
//|                                                                  |
//| These are tuned for US100/NAS100 on M1-M5: an index with a wide     |
//| point-value spread, high intraday range and a decisive cash open.   |
//| Every one is a plain assignment, so switching to FX means editing    |
//| the input block - not the code. The values, not the structure, are   |
//| what is instrument-specific.                                        |
//+------------------------------------------------------------------+
void CConfigurationBuilder::ApplyNasdaqDefaults(SInputSnapshot &in)
  {
   //--- General.
   in.magic=20260808;
   in.order_comment="SRP";
   in.direction_mode=SRP_DIRECTION_BOTH;
   //--- An index ticks far faster than the decision logic needs; 250 ms
   //--- keeps CPU sane without missing a scalp entry.
   in.tick_throttle_ms=250;
   in.context_timeframe=(int)PERIOD_M15;
   in.setup_timeframe=(int)PERIOD_M5;

   //--- Logging.
   in.log_level=SRP_LOG_INFO;
   in.log_to_file=true;
   in.log_to_terminal=true;
   in.log_to_alert=false;
   in.log_to_push=false;
   in.log_daily_rotation=true;
   in.log_folder="ScalpRobotPro\\Logs";
   in.log_channel_errors=true;
   in.log_channel_trades=true;
   //--- Indicator tracing is off by default: it is the highest-volume
   //--- channel and is a diagnostic tool, not a production need.
   in.log_channel_indicators=false;
   in.log_channel_risk=true;
   in.log_channel_performance=true;
   in.log_channel_execution=true;
   in.log_format_default=0;                 // CSV
   in.log_mirror_errors_to_journal=true;
   in.log_flush_every=8;

   //--- Risk. Percent-of-equity so position size tracks the account, with
   //--- the capital base chosen separately below.
   in.sizing_model=SRP_SIZING_RISK_PERCENT;
   in.fixed_lot=0.10;
   in.risk_percent=0.5;
   in.max_lot=5.0;
   in.max_positions=2;
   //--- NASDAQ CFD spreads commonly sit near 10-20 points and blow out
   //--- at the open; 60 rejects the spike without blocking normal trade.
   in.max_spread_points=60.0;
   in.max_slippage_points=30;
   in.min_free_margin_percent=30.0;
   in.kelly_fraction=0.25;                  // quarter-Kelly
   in.kelly_min_trades=30;
   //--- Equity, not balance: it includes floating P/L, so size shrinks
   //--- while the account is under water instead of after the fact.
   in.risk_capital_base=(int)SRP_CAPITAL_EQUITY;
   in.auto_lot_capital_per_step=1000.0;
   in.auto_lot_per_step=0.10;
   in.atr_risk_multiple=1.5;
   in.weekly_loss_percent=6.0;
   in.monthly_loss_percent=12.0;
   //--- Two positions at 0.5% each leaves headroom for a scale-in.
   in.max_exposure_percent=5.0;
   in.profit_lock_enabled=true;
   in.profit_lock_trigger_percent=2.0;
   in.profit_lock_keep_percent=50.0;

   //--- Protective levels. ATR-based, because a fixed point stop that
   //--- suits a quiet afternoon is noise-tight at the cash open.
   in.sl_mode=SRP_SL_ATR_MULTIPLE;
   in.sl_fixed_points=250.0;
   in.sl_atr_multiplier=1.5;
   in.tp_mode=SRP_TP_RISK_REWARD;
   in.tp_fixed_points=400.0;
   in.tp_atr_multiplier=2.5;
   in.tp_risk_reward=1.6;
   in.trail_mode=SRP_TRAIL_FIXED_STEP;
   in.trail_start_points=200.0;
   in.trail_step_points=20.0;
   in.trail_distance_points=150.0;
   in.breakeven_enabled=true;
   in.breakeven_trigger_points=150.0;
   in.breakeven_offset_points=20.0;
   in.partial_close_enabled=true;
   in.partial_close_trigger_points=180.0;
   in.partial_close_percent=50.0;
   in.time_stop_enabled=true;
   in.time_stop_minutes=45;

   //--- Trade manager.
   in.tm_atr_trail_enabled=false;
   in.tm_atr_trail_multiple=2.0;
   in.tm_atr_exit_enabled=true;
   in.tm_atr_exit_multiple=3.0;
   in.tm_max_hold_enabled=true;
   in.tm_max_hold_minutes=120;
   in.tm_scale_in_enabled=false;
   in.tm_scale_in_trigger_points=250.0;
   in.tm_scale_in_fraction=0.5;
   in.tm_scale_in_max=1;
   in.tm_scale_out_enabled=true;
   in.tm_scale_out_trigger_points=180.0;
   in.tm_scale_out_fraction=0.5;
   in.tm_scale_out_max=1;
   in.tm_reverse_enabled=false;

   //--- Guards.
   in.daily_profit_enabled=true;
   in.daily_profit_percent=3.0;
   in.daily_loss_enabled=true;
   in.daily_loss_percent=3.0;
   in.max_drawdown_enabled=true;
   in.max_drawdown_percent=10.0;
   in.consecutive_loss_limit=4;
   in.flatten_on_trip=true;
   //--- FALSE deliberately. A daily loss cap is a routine session brake and
   //--- must rearm tomorrow; only a drawdown or equity-floor breach is
   //--- terminal. Defaulting this to TRUE is what silently truncated every
   //--- backtest in this project's history at its first losing day.
   in.daily_limit_terminal=false;
   in.kill_switch_enabled=true;

   //--- Sessions. NASDAQ is a US instrument: the London/NY overlap and
   //--- the cash open carry the volume, Asia is thin and mean-reverting.
   in.session_filter_enabled=true;
   in.allow_sydney=false;
   in.allow_tokyo=false;
   in.allow_london=true;
   in.allow_newyork=true;
   in.schedule_enabled=true;
   in.holiday_filter_enabled=true;
   in.holiday_list="";
   in.kill_zones_only=false;
   in.require_overlap=false;
   in.weekend_filter=true;
   in.broker_gmt_offset=0;
   in.dst_adjust=true;
   //--- Flat before the weekend gap.
   in.friday_close_minutes=60;
   //--- Conventional GMT hours; the market profile overwrites per asset.
   in.london_open_gmt=8*60;      in.london_close_gmt=16*60+30;
   in.newyork_open_gmt=13*60;    in.newyork_close_gmt=21*60;
   in.primary_kz_open_gmt=13*60+30; in.primary_kz_close_gmt=16*60;
   in.skip_after_open_minutes=2; in.skip_before_close_minutes=10;

   //--- News. An index reacts violently to US macro releases.
   in.news_filter_enabled=true;
   in.news_source=SRP_NEWS_SOURCE_TERMINAL_CALENDAR;
   in.news_min_impact=SRP_NEWS_IMPACT_HIGH;
   in.news_minutes_before=15;
   in.news_minutes_after=15;
   in.news_close_positions=false;
   in.news_csv_file="";
   //--- Fail safe: if the calendar cannot be read, block rather than
   //--- trade blind into an unknown release.
   in.news_fail_safe_block=true;
   in.news_currency_filter="USD";

   //--- Filters.
   in.spread_filter_enabled=true;
   in.volatility_filter_enabled=true;
   in.volatility_min_atr=0.0;
   in.volatility_max_atr=0.0;
   in.trend_filter_enabled=true;
   in.trend_timeframe=PERIOD_M15;
   in.frequency_filter_enabled=true;
   in.min_seconds_between_trades=60;
   in.max_trades_per_day=20;
   in.max_trades_per_hour=6;

   //--- Strategies. Trend continuation and order blocks suit an index
   //--- that trends hard intraday; mean reversion is off by default.
   in.aggregation_mode=SRP_AGGREGATION_WEIGHTED_SCORE;
   in.min_confidence=0.55;
   in.momentum_enabled=true;
   in.momentum_weight=1.0;
   in.mean_reversion_enabled=false;
   in.mean_reversion_weight=0.5;
   in.breakout_enabled=true;
   in.breakout_weight=1.0;
   in.decision_vote_mode=0;
   in.decision_min_confirmations=3;
   in.decision_min_confidence=0.55;
   in.decision_max_risk_rating=3;
   in.require_confirmation=true;
   in.ema_cross_enabled=true;
   in.vwap_pullback_enabled=true;
   in.liquidity_sweep_enabled=true;
   in.order_block_enabled=true;
   in.fvg_enabled=true;
   in.opening_range_enabled=true;
   in.trend_continuation_enabled=true;
   in.bos_enabled=false;  // disabled as an entry by default; see CMarketProfile gold notes
   in.bos_weight=1.0;
   in.volatility_breakout_enabled=true;
   in.volatility_breakout_weight=1.0;
   in.order_flow_enabled=true;
   in.order_flow_weight=1.0;
   in.order_flow_min_volume=0.90;

   //--- Ultra-scalp mode. Off in the NASDAQ preset: it is a gold-focused
   //--- behaviour, and the gold profile enables it explicitly.
   in.scalp_mode_enabled=false;
   in.scalp_cooldown_seconds=15;
   in.scalp_max_hold_seconds=300;
   in.scalp_target_atr_multiple=0.55;
   in.scalp_target_min_points=0.0;
   in.scalp_target_max_points=0.0;
   in.scalp_stop_atr_multiple=0.90;
   //--- HARNESS v2, FIX 3. 6.0 points == $6.00 per lot per round turn on
   //--- this XAUUSD spec. A MODELLED cost, not a measured one - see the
   //--- comment on InpScalpCommissionPoints. Kept identical to the EA input
   //--- default and to CRuntimeConfig::Reset so that a config built from
   //--- defaults, a config built from inputs and a config built from an
   //--- empty store all price a trade the same way.
   in.scalp_commission_points=6.0;
   in.scalp_execution_cost_points=0.0;
   in.scalp_min_reward_cost_ratio=2.0;
   in.scalp_max_spread_target_ratio=0.35;
   in.scalp_early_exit_enabled=true;
   in.scalp_early_exit_min_points=0.0;
   in.scalp_early_exit_target_share=0.55;
   in.scalp_atr_min_points=0.0;
   in.scalp_atr_max_points=0.0;
   //--- HARNESS v2, FIX 4. UNDECLARED, and deliberately not DEV. A default
   //--- of DEV would let a preset-built config claim a segment the operator
   //--- never chose, which is the omission this fix exists to close.
   in.data_segment=SRP_SEGMENT_UNDECLARED;
   //--- HARNESS v2, FIX 5. 0.0 = the live tick, which is the behaviour every
   //--- recorded run in this project had. A preset must not silently pin a
   //--- geometry the operator did not ask for.
   in.pin_spread_sample=0.0;

   in.accuracy_filter_enabled=true;
   in.accuracy_require_setup=true;
   in.accuracy_require_context=true;
   in.accuracy_min_relative_volume=1.0;
   in.accuracy_volume_lookback=20;
   in.accuracy_max_extension=0.75;
   in.accuracy_min_score=0.65;

   //--- Tier defaults, matching CScalpController's own so the two cannot
   //--- disagree about what "unset" means. Geometry widened 2026-09-05: the
   //--- old targets were ~0.55-0.70 ATR against a ~46.5pt round-trip cost,
   //--- so cost consumed ~30% of the gross target and the break-even win
   //--- rate sat above every tier's assumed rate once the early-profit exit
   //--- (which collects only target*share) was priced in. Derived from cost
   //--- algebra, not from a parameter search.
   in.tier_enabled[0]=true; in.tier_target_atr[0]=1.35;
   in.tier_stop_atr[0]=0.60; in.tier_hold_seconds[0]=600;
   in.tier_win_rate[0]=0.47; in.tier_timeframe[0]=(int)PERIOD_M1;
   in.tier_enabled[1]=true; in.tier_target_atr[1]=1.20;
   in.tier_stop_atr[1]=0.60; in.tier_hold_seconds[1]=300;
   in.tier_win_rate[1]=0.50; in.tier_timeframe[1]=(int)PERIOD_M1;
   in.tier_enabled[2]=true; in.tier_target_atr[2]=1.60;
   in.tier_stop_atr[2]=0.75; in.tier_hold_seconds[2]=1800;
   in.tier_win_rate[2]=0.45; in.tier_timeframe[2]=(int)PERIOD_M5;

   //--- Indicators.
   in.fast_ma_period=9;
   in.slow_ma_period=21;
   in.trend_ma_period=100;
   in.rsi_period=14;
   in.atr_period=14;
   in.adx_period=14;
   in.bollinger_period=20;
   in.bollinger_deviation=2.0;

   //--- Smart money.
   in.smc_enabled=true;
   in.smc_swing_strength=3;
   in.smc_swing_lookback=300;
   in.smc_zone_capacity=64;
   in.smc_zone_max_age_bars=500;
   in.smc_displacement_atr_multiple=1.5;
   //--- Index gaps are large in absolute points; a forex-scale threshold
   //--- would classify ordinary noise as a fair value gap.
   in.smc_min_gap_points=50.0;
   in.smc_require_displacement=true;
   in.smc_equal_tolerance_atr=0.15;
   in.smc_sweep_lookback_bars=10;
   in.smc_structure_break_buffer=10.0;

   //--- Dashboard.
   in.dashboard_enabled=true;
   in.dashboard_theme=SRP_THEME_DARK;
   in.dashboard_corner=0;
   in.dashboard_x_offset=12;
   in.dashboard_y_offset=22;
   in.dashboard_refresh_ms=500;
   //--- Off in the tester by default: drawing dominates a fast pass.
   in.dashboard_show_in_tester=false;
   in.draw_overlay_enabled=true;
   in.draw_entries=true;
   in.draw_stops=true;
   in.draw_zones=true;
   in.draw_liquidity=true;
   in.draw_structure=true;
   in.draw_session_boxes=true;
   in.draw_trade_labels=true;
   in.draw_statistics=true;
   in.draw_max_zones=12;
   in.draw_zone_extend_bars=20;

   //--- Statistics.
   in.journal_enabled=true;
   in.persist_state=true;
   in.state_folder="ScalpRobotPro\\State";
   in.analytics_min_sample=10;
   in.analytics_use_r_multiples=false;
   in.analytics_initial_balance=0.0;        // 0 = read from the account

   //--- Optimisation.
   in.opt_criterion=SRP_CRITERION_CUSTOM_COMPOSITE;
   in.opt_min_trades=30;
   in.opt_drawdown_penalty=1.0;
   in.opt_concentration_penalty=1.0;
   in.opt_streak_penalty=1.0;
   in.opt_walk_forward_enabled=false;
   in.opt_wf_is_days=90;
   in.opt_wf_oos_days=30;
   in.opt_wf_min_efficiency=0.5;
   in.opt_monte_carlo_enabled=false;
   in.opt_monte_carlo_runs=1000;
   in.opt_monte_carlo_seed=0;
   in.opt_monte_carlo_ruin_percent=30.0;
   in.opt_export_csv=true;
   in.opt_export_folder="ScalpRobotPro\\Optimization";
   in.opt_forward_test_mode=false;
   in.opt_reject_incoherent=true;
  }

#endif // SRP_CONFIGURATION_CCONFIGURATIONBUILDER_MQH
//+------------------------------------------------------------------+
