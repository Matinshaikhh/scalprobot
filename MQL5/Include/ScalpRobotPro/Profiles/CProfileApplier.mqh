//+------------------------------------------------------------------+
//|                                          CProfileApplier.mqh |
//|                Scalping Robot Pro - Multi-Asset Profiles (P6) |
//|                                                                  |
//|   RESPONSIBILITY (one only): copy a resolved SMarketProfile onto the    |
//|   input snapshot, so the rest of the product needs no knowledge that    |
//|   profiles exist.                                                    |
//|                                                                  |
//|   WHY A SEPARATE CLASS RATHER THAN A METHOD ON EITHER SIDE             |
//|   SMarketProfile must not depend on the configuration vocabulary, and   |
//|   SInputSnapshot must not depend on the profile system - otherwise the  |
//|   two become impossible to test apart. This class is the single seam    |
//|   between them, and it is the ONLY place that knows both.              |
//|                                                                  |
//|   THE ORDER OF PRECEDENCE, which is the whole design decision:         |
//|                                                                  |
//|     1. ApplyNasdaqDefaults or equivalent fills the snapshot with the    |
//|        shipped baseline.                                             |
//|     2. THIS class overwrites the asset-specific fields from the         |
//|        profile, so NASDAQ and gold cannot share a value by accident.    |
//|     3. The .mq5 input block may then override anything, because the     |
//|        trader must always have the final say.                          |
//|                                                                  |
//|   Step 2 is what Part 4 asks for. Without it a parameter tuned on one   |
//|   instrument silently becomes the parameter for the other.             |
//|                                                                  |
//|   IT COPIES AND NOTHING ELSE. No validation, no clamping, no broker     |
//|   calls - the validator and the risk engine own those, and duplicating  |
//|   their rules here would give two places to disagree.                  |
//+------------------------------------------------------------------+
#ifndef SRP_PROFILES_CPROFILEAPPLIER_MQH
#define SRP_PROFILES_CPROFILEAPPLIER_MQH

#include "CMarketProfile.mqh"
#include "../Configuration/CConfigurationBuilder.mqh"

class CProfileApplier
  {
public:
   //--- Writes every asset-specific field from the profile into the
   //--- snapshot. Fields a profile does not own (magic, log folder,
   //--- dashboard geometry) are left exactly as the caller set them.
   static void       Apply(const SMarketProfile &profile,
                          SInputSnapshot &snapshot);

   //--- Reports what changed, so a startup log can show the trader which
   //--- values came from the profile rather than from their inputs.
   static string     DescribeApplication(const SMarketProfile &profile,
                                        const SSymbolProfile &symbol);
  };

//+------------------------------------------------------------------+
void CProfileApplier::Apply(const SMarketProfile &p,SInputSnapshot &s)
  {
   //=== RISK ==========================================================
   s.risk_percent             = p.risk_percent;
   s.max_positions            = p.max_positions;
   s.max_exposure_percent     = p.max_exposure_percent;
   s.daily_loss_percent       = p.daily_loss_percent;
   s.weekly_loss_percent      = p.weekly_loss_percent;
   s.monthly_loss_percent     = p.monthly_loss_percent;
   s.max_drawdown_percent     = p.max_drawdown_percent;
   s.consecutive_loss_limit   = p.consecutive_loss_limit;

   //=== EXECUTION COST ================================================
   s.max_spread_points        = p.max_spread_points;
   s.max_slippage_points      = (int)p.max_slippage_points;
   s.min_free_margin_percent  = p.min_free_margin_percent;

   //=== PROTECTIVE LEVELS =============================================
   //--- Stored as the Phase 2 vocabulary, which is what the engine reads.
   s.sl_mode                  = (ENUM_SRP_SL_MODE)p.stop_model;
   s.sl_atr_multiplier        = p.sl_atr_multiplier;
   s.sl_fixed_points          = p.sl_fixed_points;
   s.tp_mode                  = (ENUM_SRP_TP_MODE)p.target_model;
   s.tp_atr_multiplier        = p.tp_atr_multiplier;
   s.tp_fixed_points          = p.tp_fixed_points;
   s.tp_risk_reward           = p.tp_risk_reward;

   //=== TRADE MANAGEMENT ==============================================
   s.breakeven_trigger_points = p.breakeven_trigger_points;
   s.breakeven_offset_points  = p.breakeven_offset_points;
   s.trail_start_points       = p.trail_start_points;
   s.trail_distance_points    = p.trail_distance_points;
   s.trail_step_points        = p.trail_step_points;
   s.time_stop_minutes        = p.time_stop_minutes;
   s.tm_max_hold_minutes      = p.max_hold_minutes;

   //--- SCALE-OUT AND PARTIAL CLOSE must trigger BELOW the take profit,
   //--- or they can never fire: the position would already have closed at
   //--- its target. Derived from the target rather than set independently
   //--- so the relationship holds whatever the profile chose.
   const double partial_trigger=p.tp_fixed_points*0.55;
   s.tm_scale_out_trigger_points   = partial_trigger;
   s.partial_close_trigger_points  = partial_trigger;
   s.partial_close_percent         = s.tm_scale_out_fraction*100.0;

   //=== DECISION ======================================================
   s.decision_vote_mode       = p.vote_mode;
   s.min_confidence           = p.min_confidence;
   s.decision_min_confidence  = p.min_confidence;
   s.decision_min_confirmations = p.min_confirmations;
   s.decision_max_risk_rating = p.max_risk_rating;
   s.require_confirmation     = p.require_confirmation;

   //=== SESSIONS ======================================================
   s.allow_sydney             = p.allow_sydney;
   s.allow_tokyo              = p.allow_tokyo;
   s.allow_london             = p.allow_london;
   s.allow_newyork            = p.allow_newyork;
   s.require_overlap          = p.require_overlap;
   s.kill_zones_only          = p.kill_zones_only;
   s.friday_close_minutes     = p.friday_close_minutes;
   //--- Window times: the clearest difference between the two target
   //--- assets. Gold is London-led, NASDAQ is US-led.
   s.london_open_gmt          = p.london_open_gmt;
   s.london_close_gmt         = p.london_close_gmt;
   s.newyork_open_gmt         = p.newyork_open_gmt;
   s.newyork_close_gmt        = p.newyork_close_gmt;
   s.primary_kz_open_gmt      = p.primary_kz_open_gmt;
   s.primary_kz_close_gmt     = p.primary_kz_close_gmt;
   s.skip_after_open_minutes  = p.skip_after_open_minutes;
   s.skip_before_close_minutes= p.skip_before_close_minutes;

   //=== NEWS ==========================================================
   s.news_filter_enabled      = p.news_filter_enabled;
   s.news_min_impact          = (ENUM_SRP_NEWS_IMPACT)p.news_min_impact;
   s.news_minutes_before      = p.news_minutes_before;
   s.news_minutes_after       = p.news_minutes_after;
   s.news_currency_filter     = p.news_currency_filter;
   s.news_close_positions     = p.news_close_positions;

   //=== FREQUENCY =====================================================
   s.min_seconds_between_trades = p.min_seconds_between_trades;
   s.max_trades_per_hour      = p.max_trades_per_hour;
   s.max_trades_per_day       = p.max_trades_per_day;

   //=== MULTI-TIMEFRAME ===============================================
   s.context_timeframe        = (int)p.context_timeframe;
   s.setup_timeframe          = (int)p.setup_timeframe;

   //=== INDICATORS ====================================================
   s.fast_ma_period           = p.fast_ma_period;
   s.slow_ma_period           = p.slow_ma_period;
   s.trend_ma_period          = p.trend_ma_period;
   s.atr_period               = p.atr_period;
   s.rsi_period               = p.rsi_period;
   s.adx_period               = p.adx_period;

   //=== SMART MONEY ===================================================
   s.smc_swing_strength       = p.smc_swing_strength;
   s.smc_min_gap_points       = p.smc_min_gap_points;
   s.smc_equal_tolerance_atr  = p.smc_equal_tolerance_atr;
   s.smc_structure_break_buffer = p.smc_structure_break_buffer;
   s.smc_displacement_atr_multiple = p.smc_displacement_atr_multiple;

   //=== ULTRA-SCALP MODE ==============================================
   s.scalp_mode_enabled            = p.scalp_mode_enabled;
   s.scalp_cooldown_seconds        = p.scalp_cooldown_seconds;
   s.scalp_max_hold_seconds        = p.scalp_max_hold_seconds;
   s.scalp_target_atr_multiple     = p.scalp_target_atr_multiple;
   s.scalp_stop_atr_multiple       = p.scalp_stop_atr_multiple;
   s.scalp_min_reward_cost_ratio   = p.scalp_min_reward_cost_ratio;
   s.scalp_max_spread_target_ratio = p.scalp_max_spread_target_ratio;
   s.scalp_early_exit_enabled      = p.scalp_early_exit_enabled;
   s.scalp_early_exit_target_share = p.scalp_early_exit_target_share;

   //=== ENTRY QUALITY =================================================
   s.accuracy_filter_enabled       = p.accuracy_filter_enabled;
   s.accuracy_require_setup        = p.accuracy_require_setup;
   s.accuracy_require_context      = p.accuracy_require_context;
   s.accuracy_min_relative_volume  = p.accuracy_min_relative_volume;
   s.accuracy_max_extension        = p.accuracy_max_extension;
   s.accuracy_min_score            = p.accuracy_min_score;

   //=== SCALP TIERS ===================================================
   //--- The tiers are deliberately NOT overwritten from the profile.
   //---
   //--- Every other field here is asset-specific and the profile is the
   //--- authority on it. A tier is different: it describes the RELATIONSHIP
   //--- between target size and win rate, which is arithmetic rather than
   //--- an instrument property, and the same three tiers are correct on any
   //--- symbol. Copying them from the profile would also make the tier
   //--- inputs inert whenever the profile is authoritative - which is the
   //--- default - and an input that silently does nothing is worse than no
   //--- input at all.
   //---
   //--- The tier's TIMEFRAMES do follow the profile, because those are the
   //--- instrument's own execution and setup timeframes.
   s.tier_timeframe[0] = (int)p.execution_timeframe;
   s.tier_timeframe[1] = (int)p.execution_timeframe;
   s.tier_timeframe[2] = (int)p.setup_timeframe;

   //=== STRATEGY ENABLES ==============================================
   s.ema_cross_enabled          = p.ema_cross_enabled;
   s.trend_continuation_enabled = p.trend_continuation_enabled;
   s.momentum_enabled           = p.momentum_enabled;
   s.liquidity_sweep_enabled    = p.liquidity_sweep_enabled;
   s.order_block_enabled        = p.order_block_enabled;
   s.fvg_enabled                = p.fvg_enabled;
   s.vwap_pullback_enabled      = p.vwap_pullback_enabled;
   s.opening_range_enabled      = p.opening_range_enabled;
   s.mean_reversion_enabled     = p.mean_reversion_enabled;
   s.breakout_enabled           = p.breakout_enabled;
   s.bos_enabled                = p.bos_enabled;
   s.volatility_breakout_enabled= p.volatility_breakout_enabled;
   s.order_flow_enabled         = p.order_flow_enabled;

   //=== STRATEGY WEIGHTS ==============================================
   s.momentum_weight            = p.weight_momentum;
   s.mean_reversion_weight      = p.weight_mean_reversion;
   s.breakout_weight            = p.weight_breakout;
   s.bos_weight                 = p.weight_bos;
   s.volatility_breakout_weight = p.weight_volatility_breakout;
   s.order_flow_weight          = p.weight_order_flow;
   s.order_flow_min_volume      = p.order_flow_min_volume;
  }
//+------------------------------------------------------------------+
string CProfileApplier::DescribeApplication(const SMarketProfile &profile,
                                           const SSymbolProfile &symbol)
  {
   string text=StringFormat("Market profile applied: %s for %s (%s)",
                            profile.name,symbol.symbol,symbol.class_name);
   if(profile.name=="CUSTOM" &&
      symbol.asset_class!=SRP_ASSET_UNKNOWN)
      text+="\n  note: the symbol was recognised but is not a Phase 6 target "
            "asset, so the conservative baseline is used";
   if(symbol.asset_class==SRP_ASSET_UNKNOWN)
      text+="\n  note: this symbol was NOT recognised. The conservative "
            "baseline is in use. Set the profile mode explicitly if your "
            "broker uses an unusual name for NASDAQ or gold.";
   return(text);
  }

#endif // SRP_PROFILES_CPROFILEAPPLIER_MQH
//+------------------------------------------------------------------+
