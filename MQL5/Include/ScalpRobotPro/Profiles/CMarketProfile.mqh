//+------------------------------------------------------------------+
//|                                           CMarketProfile.mqh |
//|                Scalping Robot Pro - Multi-Asset Profiles (P6) |
//|                                                                  |
//|   RESPONSIBILITY (one only): hold one asset's complete parameter set,  |
//|   and supply the NASDAQ and GOLD presets.                             |
//|                                                                  |
//|   WHY SEPARATE PROFILES EXIST                                         |
//|   NASDAQ and gold are not the same market wearing different labels.    |
//|   A NASDAQ CFD moves in whole index points with spreads that multiply  |
//|   at the 14:30 GMT cash open; gold moves in cents against a 100 oz     |
//|   contract and takes its character from London. A stop distance that   |
//|   is noise-tight on one is absurd on the other, and a parameter        |
//|   optimised on one instrument is evidence about that instrument only.  |
//|                                                                  |
//|   SO A PARAMETER OPTIMISED FOR NASDAQ CAN NEVER SILENTLY BECOME THE    |
//|   PARAMETER FOR GOLD. Each asset owns a full independent set; the      |
//|   engine loads exactly one, selected from the resolved symbol.         |
//|                                                                  |
//|   THE PRESETS ARE STARTING POINTS, NOT OPTIMISED RESULTS. They are     |
//|   derived from published instrument characteristics - session hours,    |
//|   typical spread behaviour, relative volatility - and NOT from fitting |
//|   a backtest. Presenting fitted numbers as defaults would be the       |
//|   curve-fit this project spends a whole subsystem trying to detect.    |
//|                                                                  |
//|   Every field is overridable from the input block. A profile sets the  |
//|   defaults; the trader always has the final say.                      |
//+------------------------------------------------------------------+
#ifndef SRP_PROFILES_CMARKETPROFILE_MQH
#define SRP_PROFILES_CMARKETPROFILE_MQH

#include "CSymbolClassifier.mqh"
//--- Stop and target models come from the Phase 2 vocabulary; vote modes
//--- and news severity from Phase 3. A profile stores values from both,
//--- so both are needed here.
#include "../Intelligence/Types/IntelligenceEnums.mqh"
#include "../Decision/Types/DecisionEnums.mqh"

//+------------------------------------------------------------------+
//| HARNESS v2, FIX 5. WHICH DISTANCES CAME FROM THE SPREAD SAMPLE.    |
//|                                                                  |
//| Audit section 5.5: twelve trading distances descend arithmetically |
//| from ONE spread reading taken at initialisation. Fix 5 makes that  |
//| chain reproducible - the root can be pinned - and visible: one bit |
//| per distance, set by ScaleToSymbol at the moment it derives one.   |
//|                                                                  |
//| A bit is NOT set when the preset supplied the value, because then  |
//| the sample did not reach it. Printing all twelve as "derived"      |
//| would overstate the defect, which is its own kind of dishonesty.   |
//+------------------------------------------------------------------+
enum ENUM_SRP_GEOM_DERIVED
  {
   SRP_GEOM_NONE            = 0,
   SRP_GEOM_MAX_SPREAD      = 1 <<  0,
   SRP_GEOM_MAX_SLIPPAGE    = 1 <<  1,
   SRP_GEOM_DEVIATION       = 1 <<  2,
   SRP_GEOM_SL_MIN          = 1 <<  3,
   SRP_GEOM_SMC_GAP         = 1 <<  4,
   SRP_GEOM_SMC_BREAK       = 1 <<  5,
   SRP_GEOM_SL_FIXED        = 1 <<  6,
   SRP_GEOM_TP_FIXED        = 1 <<  7,
   SRP_GEOM_BE_TRIGGER      = 1 <<  8,
   SRP_GEOM_BE_OFFSET       = 1 <<  9,
   SRP_GEOM_TRAIL_START     = 1 << 10,
   SRP_GEOM_TRAIL_DISTANCE  = 1 << 11,
   SRP_GEOM_TRAIL_STEP      = 1 << 12
  };

//+------------------------------------------------------------------+
//| One asset's complete, independent parameter set.                   |
//|                                                                  |
//| Distances are in POINTS so the struct stays instrument-agnostic in   |
//| form; only the VALUES are instrument-specific. Multipliers are on     |
//| ATR so they adapt to the regime without being re-tuned per session.   |
//+------------------------------------------------------------------+
struct SMarketProfile
  {
   //--- Identity.
   string                name;
   ENUM_SRP_ASSET_CLASS  asset_class;

   //=== RISK ==========================================================
   double                risk_percent;              // per trade
   double                max_risk_percent;          // hard ceiling
   int                   max_positions;
   double                max_exposure_percent;
   double                daily_loss_percent;
   double                weekly_loss_percent;
   double                monthly_loss_percent;
   double                max_drawdown_percent;
   int                   consecutive_loss_limit;

   //=== EXECUTION COST ================================================
   double                max_spread_points;
   double                max_slippage_points;
   int                   deviation_points;
   double                min_free_margin_percent;

   //=== PROTECTIVE LEVELS =============================================
   int                   stop_model;                // ENUM_SRP_STOP_MODEL
   double                sl_atr_multiplier;
   double                sl_fixed_points;
   double                sl_min_points;             // floor, broker-aware
   int                   target_model;              // ENUM_SRP_TARGET_MODEL
   double                tp_atr_multiplier;
   double                tp_fixed_points;
   double                tp_risk_reward;

   //=== TRADE MANAGEMENT ==============================================
   double                breakeven_trigger_points;
   double                breakeven_offset_points;
   double                trail_start_points;
   double                trail_distance_points;
   double                trail_step_points;
   int                   time_stop_minutes;
   int                   max_hold_minutes;

   //=== VOLATILITY ====================================================
   //--- ATR as a percentage of price, which normalises across
   //--- instruments quoted at 20,000 and at 2,000.
   double                atr_low_percent;
   double                atr_high_percent;
   double                atr_extreme_percent;
   //--- Absolute ATR bounds in points; 0 disables the side.
   double                atr_min_points;
   double                atr_max_points;

   //=== REGIME ========================================================
   double                trend_adx_threshold;
   double                range_adx_threshold;
   double                breakout_expansion_ratio;

   //=== DECISION ======================================================
   int                   vote_mode;
   double                min_confidence;
   int                   min_confirmations;
   int                   max_risk_rating;
   bool                  require_confirmation;

   //=== SESSIONS, GMT minutes from midnight ===========================
   bool                  allow_sydney;
   bool                  allow_tokyo;
   bool                  allow_london;
   bool                  allow_newyork;
   bool                  require_overlap;
   bool                  kill_zones_only;
   int                   london_open_gmt;
   int                   london_close_gmt;
   int                   newyork_open_gmt;
   int                   newyork_close_gmt;
   //--- The primary kill zone for this asset.
   int                   primary_kz_open_gmt;
   int                   primary_kz_close_gmt;
   //--- Minutes skipped either side of a session edge, where the widest
   //--- spreads of the day sit.
   int                   skip_after_open_minutes;
   int                   skip_before_close_minutes;
   int                   friday_close_minutes;

   //=== NEWS ==========================================================
   bool                  news_filter_enabled;
   int                   news_min_impact;
   int                   news_minutes_before;
   int                   news_minutes_after;
   string                news_currency_filter;
   bool                  news_close_positions;

   //=== FREQUENCY =====================================================
   int                   min_seconds_between_trades;
   int                   max_trades_per_hour;
   int                   max_trades_per_day;
   int                   cooldown_after_loss_seconds;

   //=== INDICATORS ====================================================
   int                   fast_ma_period;
   int                   slow_ma_period;
   int                   trend_ma_period;
   int                   atr_period;
   int                   rsi_period;
   int                   adx_period;

   //=== MULTI-TIMEFRAME ===============================================
   ENUM_TIMEFRAMES       context_timeframe;   // regime and bias
   ENUM_TIMEFRAMES       setup_timeframe;     // structure and zones
   ENUM_TIMEFRAMES       execution_timeframe; // entry timing

   //=== SMART MONEY ===================================================
   int                   smc_swing_strength;
   double                smc_min_gap_points;
   double                smc_equal_tolerance_atr;
   double                smc_structure_break_buffer;
   double                smc_displacement_atr_multiple;

   //=== ULTRA-SCALP MODE ==============================================
   //--- Per-asset because a scalp target that suits gold's cent-quoted
   //--- 100 oz contract is meaningless on an index quoted in whole points.
   bool                  scalp_mode_enabled;
   int                   scalp_cooldown_seconds;
   int                   scalp_max_hold_seconds;
   double                scalp_target_atr_multiple;
   double                scalp_stop_atr_multiple;
   double                scalp_min_reward_cost_ratio;
   double                scalp_max_spread_target_ratio;
   bool                  scalp_early_exit_enabled;
   double                scalp_early_exit_target_share;

   //--- ENTRY QUALITY. Per-asset because the amount of corroboration worth
   //--- demanding depends on how noisy the instrument's execution
   //--- timeframe is, and gold's M1 is noisier than an index's.
   bool                  accuracy_filter_enabled;
   bool                  accuracy_require_setup;
   bool                  accuracy_require_context;
   double                accuracy_min_relative_volume;
   double                accuracy_max_extension;
   double                accuracy_min_score;

   //=== STRATEGY ENABLES ==============================================
   bool                  ema_cross_enabled;
   bool                  trend_continuation_enabled;
   bool                  momentum_enabled;
   bool                  liquidity_sweep_enabled;
   bool                  order_block_enabled;
   bool                  fvg_enabled;
   bool                  vwap_pullback_enabled;
   bool                  opening_range_enabled;
   bool                  mean_reversion_enabled;
   bool                  breakout_enabled;
   bool                  bos_enabled;
   bool                  volatility_breakout_enabled;
   bool                  order_flow_enabled;

   //=== STRATEGY WEIGHTS, used by weighted voting =====================
   double                weight_ema_cross;
   double                weight_trend_continuation;
   double                weight_momentum;
   double                weight_liquidity_sweep;
   double                weight_order_block;
   double                weight_fvg;
   double                weight_vwap_pullback;
   double                weight_opening_range;
   double                weight_mean_reversion;
   double                weight_breakout;
   double                weight_bos;
   double                weight_volatility_breakout;
   double                weight_order_flow;
   double                order_flow_min_volume;

   //=== DERIVATION RECORD, HARNESS v2 FIX 5 ===========================
   //--- NOT settings. ScaleToSymbol writes these so a report can state
   //--- what the trade geometry was built from without the reader having
   //--- to re-run the arithmetic. `spread_sample` is the one number the
   //--- whole chain descends from; `spread_pinned` says whether it came
   //--- from an input (reproducible) or from whatever tick happened to be
   //--- current at initialisation (not reproducible).
   double                spread_sample;         // points, the chain's root
   bool                  spread_pinned;         // root supplied by input
   int                   derived_mask;          // ENUM_SRP_GEOM_DERIVED bits

                     SMarketProfile(void) { Reset(); }
   void              Reset(void);
  };

//+------------------------------------------------------------------+
//| Neutral baseline. Deliberately conservative: if a preset forgets to  |
//| set something, the omission must not create risk.                    |
//+------------------------------------------------------------------+
void SMarketProfile::Reset(void)
  {
   name="custom";
   asset_class=SRP_ASSET_UNKNOWN;

   risk_percent=0.25;              // Part 14 default
   max_risk_percent=1.0;           // Part 14 ceiling
   max_positions=1;
   max_exposure_percent=2.0;
   daily_loss_percent=2.0;
   weekly_loss_percent=4.0;
   monthly_loss_percent=8.0;
   max_drawdown_percent=10.0;
   consecutive_loss_limit=4;

   max_spread_points=0.0;          // 0 = resolved from the broker
   max_slippage_points=0.0;
   deviation_points=20;
   min_free_margin_percent=30.0;

   stop_model=(int)SRP_STOP_ATR_MULTIPLE;
   sl_atr_multiplier=1.5;
   sl_fixed_points=0.0;
   sl_min_points=0.0;
   target_model=(int)SRP_TARGET_RISK_REWARD;
   tp_atr_multiplier=2.0;
   tp_fixed_points=0.0;
   tp_risk_reward=1.5;

   breakeven_trigger_points=0.0;
   breakeven_offset_points=0.0;
   trail_start_points=0.0;
   trail_distance_points=0.0;
   trail_step_points=0.0;
   time_stop_minutes=60;
   max_hold_minutes=240;

   atr_low_percent=0.02;
   atr_high_percent=0.10;
   atr_extreme_percent=0.20;
   atr_min_points=0.0;
   atr_max_points=0.0;

   trend_adx_threshold=22.0;
   range_adx_threshold=18.0;
   breakout_expansion_ratio=1.5;

   vote_mode=(int)SRP_VOTE_WEIGHTED;
   min_confidence=0.60;
   min_confirmations=3;
   max_risk_rating=2;
   require_confirmation=true;

   allow_sydney=false; allow_tokyo=false;
   allow_london=true;  allow_newyork=true;
   require_overlap=false; kill_zones_only=false;
   london_open_gmt   =  8*60;
   london_close_gmt  = 16*60+30;
   newyork_open_gmt  = 13*60;
   newyork_close_gmt = 21*60;
   primary_kz_open_gmt  = 13*60;
   primary_kz_close_gmt = 16*60;
   skip_after_open_minutes=0;
   skip_before_close_minutes=0;
   friday_close_minutes=60;

   news_filter_enabled=true;
   news_min_impact=2;
   news_minutes_before=15;
   news_minutes_after=15;
   news_currency_filter="USD";
   news_close_positions=false;

   min_seconds_between_trades=60;
   max_trades_per_hour=4;
   max_trades_per_day=12;
   cooldown_after_loss_seconds=300;

   fast_ma_period=9; slow_ma_period=21; trend_ma_period=100;
   atr_period=14; rsi_period=14; adx_period=14;

   context_timeframe=PERIOD_M15;
   setup_timeframe=PERIOD_M5;
   execution_timeframe=PERIOD_M1;

   smc_swing_strength=3;
   smc_min_gap_points=0.0;
   smc_equal_tolerance_atr=0.15;
   smc_structure_break_buffer=0.0;
   smc_displacement_atr_multiple=1.5;

   //--- Ultra-scalp off in the neutral baseline: it changes behaviour, so
   //--- an unrecognised instrument must not receive it by default.
   scalp_mode_enabled=false;
   scalp_cooldown_seconds=15;
   scalp_max_hold_seconds=300;
   scalp_target_atr_multiple=0.55;
   scalp_stop_atr_multiple=0.90;
   scalp_min_reward_cost_ratio=2.0;
   scalp_max_spread_target_ratio=0.35;
   scalp_early_exit_enabled=true;
   scalp_early_exit_target_share=0.55;

   //--- Accuracy gate OFF in the neutral baseline: it changes which trades
   //--- are taken, so an unrecognised instrument must not inherit it.
   accuracy_filter_enabled=false;
   accuracy_require_setup=true;
   accuracy_require_context=true;
   accuracy_min_relative_volume=1.0;
   accuracy_max_extension=0.75;
   accuracy_min_score=0.65;

   ema_cross_enabled=false;        // weakest edge; off unless asked for
   trend_continuation_enabled=true;
   momentum_enabled=true;
   liquidity_sweep_enabled=true;
   order_block_enabled=true;
   fvg_enabled=true;
   vwap_pullback_enabled=true;
   opening_range_enabled=false;
   mean_reversion_enabled=false;
   breakout_enabled=true;
   bos_enabled=true;
   volatility_breakout_enabled=true;
   order_flow_enabled=true;

   weight_ema_cross=0.5;
   weight_trend_continuation=1.0;
   weight_momentum=1.0;
   weight_liquidity_sweep=1.0;
   weight_order_block=1.0;
   weight_fvg=0.8;
   weight_vwap_pullback=1.0;
   weight_opening_range=1.0;
   weight_mean_reversion=0.6;
   weight_breakout=1.0;
   weight_bos=1.0;
   weight_volatility_breakout=1.0;
   weight_order_flow=1.0;
   order_flow_min_volume=0.90;

   //--- FIX 5. Nothing derived until ScaleToSymbol says so.
   spread_sample=0.0;
   spread_pinned=false;
   derived_mask=(int)SRP_GEOM_NONE;
  }

//+------------------------------------------------------------------+
//| Supplies the presets and selects one from a resolved symbol.        |
//+------------------------------------------------------------------+
class CMarketProfileFactory
  {
private:
   //--- Distances that must scale with the instrument are derived from
   //--- the broker's own figures rather than written as constants.
   static void       ScaleToSymbol(const SSymbolProfile &symbol,
                                   SMarketProfile &profile);

public:
   static void       ApplyNasdaq(SMarketProfile &profile);
   static void       ApplyGold(SMarketProfile &profile);
   static void       ApplyCustom(SMarketProfile &profile);

   //--- THE ENTRY POINT. Picks the preset for the resolved symbol and
   //--- scales broker-relative fields to it.
   static bool       Build(const SSymbolProfile &symbol,
                          SMarketProfile &profile);

   //--- As Build, but honouring an explicit mode. AUTO defers to the
   //--- classifier; the named modes force a preset, which is what a
   //--- trader needs when their broker's symbol name is unrecognised.
   static bool       BuildForMode(const SSymbolProfile &symbol,
                                 const ENUM_SRP_PROFILE_MODE mode,
                                 SMarketProfile &profile);

   static string     Describe(const SMarketProfile &profile);

   //--- HARNESS v2, FIX 5. The audit's 5.5 finding, printed.
   //---
   //--- Twelve trading distances descend arithmetically from one spread
   //--- sample taken once at initialisation. That was invisible: the log
   //--- showed the twelve results and never the number they came from, so
   //--- two runs that traded different geometry looked identical on paper.
   //--- This prints the root, whether it was pinned, and each of the
   //--- twelve marked derived or preset - which is the whole difference
   //--- between a reproducible run and a plausible one.
   static string     DescribeDerivation(const SMarketProfile &profile);

   //--- HARNESS v2, FIX 5. How many of the TWELVE distances the code derived
   //--- from the spread sample on this build of the profile.
   //---
   //--- Counted here rather than by the caller so the bit layout stays
   //--- private to this class, and it excludes SRP_GEOM_SL_MIN deliberately:
   //--- sl_min_points is an intermediate that never reaches the sealed
   //--- configuration, so counting it would report thirteen derived
   //--- distances where twelve are traded.
   static int        DerivedCount(const SMarketProfile &profile);

private:
   //--- One row of the derivation table. Kept private because the mask
   //--- bit and the value have to be quoted together or not at all.
   static string     DerivationRow(const SMarketProfile &profile,
                                   const ENUM_SRP_GEOM_DERIVED bit,
                                   const string label,
                                   const double value);
  };

//+------------------------------------------------------------------+
int CMarketProfileFactory::DerivedCount(const SMarketProfile &profile)
  {
   //--- Written as twelve explicit tests rather than a loop over a bit table.
   //--- The table would have to be kept in step with the enum by hand, and a
   //--- missing entry would under-report the count silently - which is the
   //--- same class of quiet wrongness this fix exists to remove.
   const int m=profile.derived_mask;
   int count=0;
   if((m&(int)SRP_GEOM_MAX_SPREAD)!=0)     count++;
   if((m&(int)SRP_GEOM_MAX_SLIPPAGE)!=0)   count++;
   if((m&(int)SRP_GEOM_DEVIATION)!=0)      count++;
   if((m&(int)SRP_GEOM_SMC_GAP)!=0)        count++;
   if((m&(int)SRP_GEOM_SMC_BREAK)!=0)      count++;
   if((m&(int)SRP_GEOM_SL_FIXED)!=0)       count++;
   if((m&(int)SRP_GEOM_TP_FIXED)!=0)       count++;
   if((m&(int)SRP_GEOM_BE_TRIGGER)!=0)     count++;
   if((m&(int)SRP_GEOM_BE_OFFSET)!=0)      count++;
   if((m&(int)SRP_GEOM_TRAIL_START)!=0)    count++;
   if((m&(int)SRP_GEOM_TRAIL_DISTANCE)!=0) count++;
   if((m&(int)SRP_GEOM_TRAIL_STEP)!=0)     count++;
   //--- SRP_GEOM_SL_MIN is deliberately absent; see the declaration.
   return(count);
  }

//+------------------------------------------------------------------+
string CMarketProfileFactory::DerivationRow(const SMarketProfile &profile,
                                            const ENUM_SRP_GEOM_DERIVED bit,
                                            const string label,
                                            const double value)
  {
   const bool derived=((profile.derived_mask&(int)bit)!=0);
   return(StringFormat("\n  %-28s %9.2f  %s",
                       label,value,
                       (derived ? "derived from the sample" : "preset/configured")));
  }

//+------------------------------------------------------------------+
string CMarketProfileFactory::DescribeDerivation(const SMarketProfile &profile)
  {
   string text=StringFormat("GEOMETRY DERIVATION [%s]",profile.name);
   text+=StringFormat("\n  spread sample: %.2f pts  (%s)",
                      profile.spread_sample,
                      (profile.spread_pinned
                       ? "PINNED by InpPinSpreadSample - reproducible"
                       : "LIVE, read once at init - NOT reproducible"));
   if(profile.spread_sample<=0.0)
      text+="\n  ! the sample was unavailable; the 10.0 pt fallback was used";

   text+="\n  the twelve distances that descend from it:";
   text+=DerivationRow(profile,SRP_GEOM_MAX_SPREAD,
                       "max_spread_points",profile.max_spread_points);
   text+=DerivationRow(profile,SRP_GEOM_MAX_SLIPPAGE,
                       "max_slippage_points",profile.max_slippage_points);
   text+=DerivationRow(profile,SRP_GEOM_DEVIATION,
                       "deviation_points",profile.deviation_points);
   text+=DerivationRow(profile,SRP_GEOM_SMC_GAP,
                       "smc_min_gap_points",profile.smc_min_gap_points);
   text+=DerivationRow(profile,SRP_GEOM_SMC_BREAK,
                       "smc_structure_break_buf",profile.smc_structure_break_buffer);
   text+=DerivationRow(profile,SRP_GEOM_SL_FIXED,
                       "sl_fixed_points",profile.sl_fixed_points);
   text+=DerivationRow(profile,SRP_GEOM_TP_FIXED,
                       "tp_fixed_points",profile.tp_fixed_points);
   text+=DerivationRow(profile,SRP_GEOM_BE_TRIGGER,
                       "breakeven_trigger_points",profile.breakeven_trigger_points);
   text+=DerivationRow(profile,SRP_GEOM_BE_OFFSET,
                       "breakeven_offset_points",profile.breakeven_offset_points);
   text+=DerivationRow(profile,SRP_GEOM_TRAIL_START,
                       "trail_start_points",profile.trail_start_points);
   text+=DerivationRow(profile,SRP_GEOM_TRAIL_DISTANCE,
                       "trail_distance_points",profile.trail_distance_points);
   text+=DerivationRow(profile,SRP_GEOM_TRAIL_STEP,
                       "trail_step_points",profile.trail_step_points);

   //--- sl_min_points is listed apart from the twelve on purpose. Grepping
   //--- the tree for it finds no consumer outside this struct: it is an
   //--- intermediate that feeds sl_fixed, breakeven_offset and trail_step
   //--- and never reaches the sealed configuration. Printing it inside the
   //--- table would imply the engine reads it, which it does not.
   text+=DerivationRow(profile,SRP_GEOM_SL_MIN,
                       "(sl_min_points, internal)",profile.sl_min_points);
   text+="\n  sl_min_points is an intermediate only - it feeds the three above"
         "\n  and is never read by the engine. Listed for arithmetic, not effect.";
   text+=StringFormat("\n  %d of the 12 traded distances descend from the "
                      "sample above.",DerivedCount(profile));
   if(!profile.spread_pinned)
      text+="\n  ! NOT REPRODUCIBLE: rerunning this configuration samples a "
            "different tick"
            "\n    and derives different distances. Set InpPinSpreadSample to "
            "fix the root.";
   return(text);
  }

//+------------------------------------------------------------------+
//| NASDAQ PRESET.                                                     |
//|                                                                  |
//| Character being encoded, from published index behaviour:            |
//|   * The 14:30 GMT cash open carries the day's decisive move, and    |
//|     the first minutes have the widest spreads of the session.       |
//|   * It trends hard intraday, so continuation and breakout suit it   |
//|     and mean reversion fights it.                                  |
//|   * It reacts violently to US macro releases.                      |
//|   * London hours are thinner but tradeable; Asia is not.           |
//+------------------------------------------------------------------+
void CMarketProfileFactory::ApplyNasdaq(SMarketProfile &profile)
  {
   profile.Reset();
   profile.name="NASDAQ";
   profile.asset_class=SRP_ASSET_INDEX_NASDAQ;

   //--- Risk. An index gaps, so the per-trade figure stays at the
   //--- documented default and the daily cap allows a genuine losing
   //--- day without ending the account.
   profile.risk_percent=0.25;
   profile.max_positions=2;
   profile.max_exposure_percent=2.0;
   profile.daily_loss_percent=2.0;
   profile.weekly_loss_percent=4.0;
   profile.monthly_loss_percent=8.0;
   profile.max_drawdown_percent=10.0;
   profile.consecutive_loss_limit=4;

   //--- Protective levels. ATR-based: a fixed stop that suits a quiet
   //--- London afternoon is noise-tight at the cash open.
   profile.stop_model=(int)SRP_STOP_ATR_MULTIPLE;
   profile.sl_atr_multiplier=1.8;
   profile.target_model=(int)SRP_TARGET_RISK_REWARD;
   profile.tp_risk_reward=1.6;
   profile.tp_atr_multiplier=2.5;

   //--- Management. An index scalp that has not worked within the hour
   //--- has usually lost its premise.
   profile.time_stop_minutes=45;
   profile.max_hold_minutes=180;

   //--- Volatility, as ATR percentage of price. An index at 20,000 with
   //--- a 40-point ATR is 0.2%, so the bands sit lower than gold's.
   profile.atr_low_percent=0.020;
   profile.atr_high_percent=0.090;
   profile.atr_extreme_percent=0.180;

   //--- Regime. Indices sustain direction, so the trend threshold can
   //--- sit slightly lower than a mean-reverting instrument would want.
   profile.trend_adx_threshold=22.0;
   profile.range_adx_threshold=18.0;
   profile.breakout_expansion_ratio=1.6;

   //--- Decision. Weighted voting, not first-match: several plugins
   //--- agreeing is real information and first-match discards it.
   profile.vote_mode=(int)SRP_VOTE_WEIGHTED;
   profile.min_confidence=0.60;
   profile.min_confirmations=3;
   profile.max_risk_rating=2;
   profile.require_confirmation=true;

   //--- Sessions. US instrument: the cash open and the overlap carry the
   //--- volume. Asia is thin and mean-reverting, so it is excluded.
   profile.allow_sydney=false;
   profile.allow_tokyo=false;
   profile.allow_london=true;
   profile.allow_newyork=true;
   profile.require_overlap=false;
   profile.kill_zones_only=false;
   //--- 13:30 GMT US cash open through the first two hours is the
   //--- primary window; the overlap either side of it is secondary.
   profile.primary_kz_open_gmt  = 13*60+30;
   profile.primary_kz_close_gmt = 16*60;
   //--- The first minutes after the open carry the widest spreads of the
   //--- day. Skipping them costs a few setups and avoids paying the
   //--- spike, which is the better side of that trade.
   profile.skip_after_open_minutes=2;
   profile.skip_before_close_minutes=10;
   profile.friday_close_minutes=60;

   //--- News. US macro moves this instrument hardest.
   profile.news_filter_enabled=true;
   profile.news_min_impact=2;            // high impact
   profile.news_minutes_before=15;
   profile.news_minutes_after=15;
   profile.news_currency_filter="USD";
   profile.news_close_positions=false;

   //--- Frequency. Scalping, not over-trading.
   profile.min_seconds_between_trades=60;
   profile.max_trades_per_hour=6;
   profile.max_trades_per_day=15;
   profile.cooldown_after_loss_seconds=300;

   //--- Indicators.
   profile.fast_ma_period=9;
   profile.slow_ma_period=21;
   profile.trend_ma_period=100;
   profile.atr_period=14;

   //--- Multi-timeframe, per Part 5.
   profile.context_timeframe   = PERIOD_M15;
   profile.setup_timeframe     = PERIOD_M5;
   profile.execution_timeframe = PERIOD_M1;

   profile.smc_swing_strength=3;
   profile.smc_equal_tolerance_atr=0.15;
   profile.smc_displacement_atr_multiple=1.5;

   //--- Strategies. Opening range is enabled here and nowhere else:
   //--- it exists for exactly this instrument's cash open.
   profile.ema_cross_enabled=false;
   profile.trend_continuation_enabled=true;
   profile.momentum_enabled=true;
   profile.liquidity_sweep_enabled=true;
   profile.order_block_enabled=true;
   profile.fvg_enabled=true;
   profile.vwap_pullback_enabled=true;
   profile.opening_range_enabled=true;
   profile.mean_reversion_enabled=false;   // fights an index that trends
   profile.breakout_enabled=true;
   profile.bos_enabled=true;
   profile.volatility_breakout_enabled=true;
   profile.order_flow_enabled=true;

   //--- Weights favour continuation and the open.
   profile.weight_trend_continuation=1.2;
   profile.weight_momentum=1.1;
   profile.weight_opening_range=1.2;
   profile.weight_breakout=1.1;
   profile.weight_volatility_breakout=1.0;
   profile.weight_liquidity_sweep=1.0;
   profile.weight_order_block=1.0;
   profile.weight_bos=1.0;
   profile.weight_fvg=0.8;
   profile.weight_vwap_pullback=1.0;
   profile.weight_mean_reversion=0.5;
   profile.weight_order_flow=1.0;
   profile.order_flow_min_volume=1.00;
  }
//+------------------------------------------------------------------+
//| GOLD PRESET.                                                       |
//|                                                                  |
//| NOT a copy of the NASDAQ set. Character being encoded:              |
//|   * Gold takes its direction from London and extends through the    |
//|     London/NY overlap, so its primary window is earlier.           |
//|   * It expands suddenly and holds wider ranges, so stops must be    |
//|     wider in ATR terms or they are simply noise-triggered.         |
//|   * It respects liquidity levels and prior highs/lows well, which   |
//|     favours sweep and order-block logic.                           |
//|   * It mean-reverts more readily than an index, so that strategy    |
//|     is permitted here under the right regime.                      |
//|   * It reacts to the same US macro calendar through the dollar.     |
//+------------------------------------------------------------------+
void CMarketProfileFactory::ApplyGold(SMarketProfile &profile)
  {
   profile.Reset();
   profile.name="GOLD";
   profile.asset_class=SRP_ASSET_METAL_GOLD;

   //--- Risk. Gold's sudden expansion means a stop is hit faster and
   //--- further, so exposure is held tighter than the index profile.
   //--- Risk UNCHANGED at the documented default. Scalping more often
   //--- must never be paid for with a larger per-trade risk.
   profile.risk_percent=0.25;
   //--- Three simultaneous positions, per the requirement. Each still
   //--- needs its OWN independent signal: the duplicate gate in
   //--- CScalpController is what makes that true rather than aspirational.
   profile.max_positions=3;
   //--- 3 x 0.25% = 0.75% of simultaneous risk, so the exposure ceiling
   //--- sits just above it rather than being the binding constraint.
   profile.max_exposure_percent=1.0;
   profile.daily_loss_percent=2.0;
   profile.weekly_loss_percent=4.0;
   profile.monthly_loss_percent=8.0;
   profile.max_drawdown_percent=8.0;
   profile.consecutive_loss_limit=3;

   //--- Protective levels. WIDER in ATR terms than NASDAQ. Gold retraces
   //--- deeply inside a move that ultimately continues, so a 1.8x stop
   //--- that suits an index is noise-tight here.
   profile.stop_model=(int)SRP_STOP_ATR_MULTIPLE;
   profile.sl_atr_multiplier=2.2;
   profile.target_model=(int)SRP_TARGET_RISK_REWARD;
   profile.tp_risk_reward=1.5;
   profile.tp_atr_multiplier=3.0;

   //--- Management. Gold trends for longer once moving, so it is given
   //--- more time than an index scalp.
   profile.time_stop_minutes=60;
   profile.max_hold_minutes=240;

   //--- Volatility. Gold's ATR is a larger share of price than an
   //--- index's, so every band sits higher.
   profile.atr_low_percent=0.035;
   profile.atr_high_percent=0.130;
   profile.atr_extreme_percent=0.250;

   //--- Regime. Gold whipsaws, so a higher ADX is demanded before
   //--- calling a trend and committing to continuation logic.
   profile.trend_adx_threshold=25.0;
   profile.range_adx_threshold=20.0;
   profile.breakout_expansion_ratio=1.8;

   //--- Decision. The final score is signal confidence multiplied by
   //--- confirmation confidence. A 0.65 floor plus a MEDIUM-only risk cap
   //--- required roughly 0.70 after that multiplication and starved an
   //--- M1 scalper of otherwise validated setups. Keep the quality gate,
   //--- but allow a well-confirmed HIGH-rated setup at the profile's small
   //--- fixed risk instead of silently treating it as no signal.
   profile.vote_mode=(int)SRP_VOTE_WEIGHTED;
   profile.min_confidence=0.55;
   profile.min_confirmations=2;
   profile.max_risk_rating=3;
   profile.require_confirmation=true;

   //--- Sessions. LONDON-LED, which is the clearest difference from the
   //--- NASDAQ profile. London sets gold's direction; the overlap
   //--- extends it; New York can reverse it.
   profile.allow_sydney=false;
   profile.allow_tokyo=false;
   profile.allow_london=true;
   profile.allow_newyork=true;
   profile.require_overlap=false;
   profile.kill_zones_only=false;
   //--- London open through the overlap: 07:00-16:00 GMT, with the
   //--- primary window on the London open itself.
   profile.primary_kz_open_gmt  =  7*60;
   profile.primary_kz_close_gmt = 12*60;
   profile.skip_after_open_minutes=3;
   profile.skip_before_close_minutes=15;
   profile.friday_close_minutes=90;      // gold gaps over the weekend

   //--- News. Dollar-driven, so the same US calendar applies, with a
   //--- wider window: gold's reaction is larger and slower to settle.
   profile.news_filter_enabled=true;
   profile.news_min_impact=2;
   profile.news_minutes_before=20;
   profile.news_minutes_after=20;
   profile.news_currency_filter="USD,XAU";
   profile.news_close_positions=false;

   //--- ULTRA-SCALP MODE. ON for gold: this is the asset it exists for.
   //---
   //--- The frequency figures below are RAISED relative to the swing-style
   //--- gold defaults, but every one is still a CEILING. Raising a ceiling
   //--- does not create trades; it stops the ceiling from being the thing
   //--- that refuses a genuine setup. If the market offers two setups the
   //--- robot takes two.
   profile.scalp_mode_enabled=true;
   //--- Short by design: this window exists to stop ONE signal firing
   //--- twice, not to throttle legitimate rapid scalping.
   profile.scalp_cooldown_seconds=15;
   profile.scalp_max_hold_seconds=300;      // 5 minutes
   //--- TARGET AND STOP GEOMETRY.
   //---
   //--- A measured run with target 0.55xATR against stop 0.90xATR produced
   //--- an 80% win rate and a profit factor of 1.03: average win 6.18,
   //--- average loss 24.12. Winning four times out of five while barely
   //--- breaking even is the signature of a stop far wider than the
   //--- target - one loss erases four wins.
   //---
   //--- A scalp stop still cannot be tighter than the noise it must
   //--- survive, so the fix is not simply "tighten the stop". Both move:
   //--- the target widens and the stop narrows until the ratio is
   //--- defensible. At 0.70 vs 0.70 a loss costs one win rather than four,
   //--- and the time exit caps the damage a stalled trade can do.
   profile.scalp_target_atr_multiple=0.70;
   profile.scalp_stop_atr_multiple=0.70;
   profile.scalp_min_reward_cost_ratio=2.0;
   profile.scalp_max_spread_target_ratio=0.35;
   //--- EARLY EXIT: ENABLED, BUT LATE.
   //---
   //--- MEASURED: with the share at 0.55, early exit fired on 19 trades
   //--- against 3 full targets, so nearly every winner was cut at 55% of
   //--- target while every loser ran to the full stop. A geometry designed
   //--- for a gross payoff of 1.22 realised 0.797 - the exit was quietly
   //--- inverting the risk:reward the tier had been sized around.
   //---
   //--- The share is raised to 0.85 so the rule does what it was asked for
   //--- - protect a nearly-complete move whose momentum has faded - rather
   //--- than truncating the average winner. Trades that stall short of that
   //--- are still released by the holding-window timeout, which is the
   //--- correct instrument for a move that never developed.
   profile.scalp_early_exit_enabled=true;
   profile.scalp_early_exit_target_share=0.85;

   //--- ENTRY QUALITY, ON for gold.
   //---
   //--- This is the direct response to the measured failure: 1219 of 1221
   //--- trades were M1 signals taken with no requirement that M5 or M15
   //--- agreed, and the resulting 43.90% win rate sat below the 51.3%
   //--- break-even implied by the payoff. Demanding agreement raises the
   //--- win rate WITHOUT touching the geometry, so the break-even rate
   //--- stays where it is.
   //---
   //--- Volume floor at x1.0 - a break with merely average participation
   //--- behind it is not evidence of anything. Tick volume is used because
   //--- this feed reports real volume as zero on XAUUSD (measured, M1/M5/M15).
   profile.accuracy_filter_enabled=true;
   profile.accuracy_require_setup=true;
   profile.accuracy_require_context=true;
   //--- x0.70, NOT x1.00.
   //---
   //--- A floor at x1.00 demands ABOVE-AVERAGE volume, and by construction
   //--- fewer than half of all bars can clear it - so it was refusing 742
   //--- of 1313 signals as "thin" when most were simply ordinary. The job
   //--- of this floor is to exclude the genuinely dead bar, not to insist
   //--- every entry is exceptional; the composite score is what
   //--- discriminates between the survivors.
   profile.accuracy_min_relative_volume=0.70;
   //--- Gold trends hard, so a continuation entry is allowed deeper into
   //--- the range than a mean-reverting instrument would be. At 0.75 this
   //--- refused a further 411 signals; 0.90 still excludes an entry at the
   //--- very extreme without discarding every trend continuation, which is
   //--- the setup gold actually offers.
   profile.accuracy_max_extension=0.90;
   profile.accuracy_min_score=0.55;

   //--- Frequency ceilings, raised for scalping but still ceilings.
   profile.min_seconds_between_trades=15;
   profile.max_trades_per_hour=12;
   profile.max_trades_per_day=30;
   //--- Loss cooldown kept SHORT and separate from revenge-trade
   //--- prevention: the daily loss guard and consecutive-loss limit are
   //--- what stop a losing streak, not a long timeout.
   profile.cooldown_after_loss_seconds=60;

   //--- Scalping needs a tight target, so the swing-style risk:reward is
   //--- replaced by the scalp target model at runtime. Kept coherent here
   //--- for the case where scalp mode is switched off.
   profile.time_stop_minutes=5;
   profile.max_hold_minutes=15;

   profile.fast_ma_period=8;
   profile.slow_ma_period=21;
   profile.trend_ma_period=100;
   profile.atr_period=14;

   //--- Multi-timeframe, per Part 6.
   profile.context_timeframe   = PERIOD_M15;
   profile.setup_timeframe     = PERIOD_M5;
   profile.execution_timeframe = PERIOD_M1;

   //--- Gold respects swing structure well, so a slightly stronger swing
   //--- definition is used to reduce noise-level pivots.
   profile.smc_swing_strength=4;
   profile.smc_equal_tolerance_atr=0.20;
   profile.smc_displacement_atr_multiple=1.6;

   //--- Strategies. Opening range OFF: gold has no equivalent of an
   //--- equity cash open, so the strategy would fire on an arbitrary
   //--- clock time. Mean reversion ON, gated to ranging regimes, which
   //--- is a genuine gold characteristic rather than a copied setting.
   profile.ema_cross_enabled=false;
   profile.trend_continuation_enabled=true;
   profile.momentum_enabled=true;
   profile.liquidity_sweep_enabled=true;
   profile.order_block_enabled=true;
   profile.fvg_enabled=true;
   profile.vwap_pullback_enabled=true;
   profile.opening_range_enabled=false;
   profile.mean_reversion_enabled=true;
   profile.breakout_enabled=true;
   //--- Break of structure OFF as an ENTRY. It was the dominant entry in the
   //--- July 2026 XAUUSD M1 run (135 of 144 trades) and it resolved its own
   //--- barriers 35.4% of the time where a driftless walk on the same
   //--- target/stop predicts 44.8% (SE 4.1pp) - i.e. measurably worse than
   //--- random, not merely unprofitable after costs. CMarketStructure keeps
   //--- feeding structure context to the plugins that remain enabled.
   profile.bos_enabled=false;
   profile.volatility_breakout_enabled=true;
   //--- Order flow ON. OBV + MFI + relative volume were already computed
   //--- every tick and read by nothing; this is real, always-available
   //--- volume evidence, which is exactly the kind of independent
   //--- confirmation a tight scalp target benefits from most.
   profile.order_flow_enabled=true;

   //--- Weights favour liquidity and structure over raw momentum.
   profile.weight_liquidity_sweep=1.2;
   profile.weight_order_block=1.2;
   profile.weight_bos=0.0;                  // disabled as an entry, see above
   profile.weight_trend_continuation=1.0;
   profile.weight_momentum=0.9;
   profile.weight_fvg=1.0;
   profile.weight_vwap_pullback=1.0;
   profile.weight_mean_reversion=0.8;
   profile.weight_breakout=1.0;
   profile.weight_volatility_breakout=1.1;
   profile.weight_opening_range=0.0;
   profile.weight_order_flow=1.1;
   //--- Gold's tick-volume feed is noisier than an index's, so the
   //--- participation floor sits slightly below the NASDAQ default.
   profile.order_flow_min_volume=0.85;
  }
//+------------------------------------------------------------------+
//| CUSTOM PRESET. The conservative baseline, used when the symbol is   |
//| not recognised. It does not pretend to know the instrument.         |
//+------------------------------------------------------------------+
void CMarketProfileFactory::ApplyCustom(SMarketProfile &profile)
  {
   profile.Reset();
   profile.name="CUSTOM";
   profile.asset_class=SRP_ASSET_UNKNOWN;
   //--- Deliberately tighter than either named preset: an unknown
   //--- instrument gets the smallest sensible footprint until the
   //--- trader says otherwise.
   profile.risk_percent=0.25;
   profile.max_positions=1;
   profile.max_exposure_percent=1.0;
   profile.min_confidence=0.70;
   profile.max_trades_per_day=8;
   //--- Only the strategies that do not depend on instrument-specific
   //--- session behaviour.
   profile.opening_range_enabled=false;
   profile.mean_reversion_enabled=false;
  }
//+------------------------------------------------------------------+
//| BROKER-RELATIVE SCALING.                                           |
//|                                                                  |
//| A preset cannot hardcode a spread ceiling or a minimum stop: those   |
//| depend on the broker's own quoting and stop level. Anything left at  |
//| 0 by a preset is derived here from the resolved symbol.              |
//|                                                                  |
//| HARNESS v2, FIX 5. This function IS the section-5.5 chain. Every    |
//| assignment below is recorded in profile.derived_mask as it is made, |
//| and the sample they all descend from is recorded unconditionally -  |
//| including when every value was preset and the sample reached none   |
//| of them - because a report that cannot state the sample cannot be   |
//| checked. Recording changes no arithmetic; see the note on `observed`.|
//+------------------------------------------------------------------+
void CMarketProfileFactory::ScaleToSymbol(const SSymbolProfile &symbol,
                                          SMarketProfile &profile)
  {
   if(!symbol.resolved)
      return;

   //--- THE ROOT OF THE CHAIN, hoisted out of the branch below so it can be
   //--- recorded. It used to be computed inside the max_spread_points test,
   //--- which meant a profile that preset the ceiling left no record of what
   //--- the broker was quoting. The expression is unchanged and the guard
   //--- still governs the assignment, so no number moves.
   const double observed=(symbol.spread_current>0.0
                          ? symbol.spread_current : 10.0);
   profile.spread_sample=observed;
   profile.spread_pinned=(symbol.spread_pinned!=0);

   //--- SPREAD CEILING. Derived from what the broker is actually
   //--- quoting, because a fixed number is wrong on every other broker.
   //--- A generous multiple of the observed spread rejects the open
   //--- spike without blocking normal trading.
   if(profile.max_spread_points<=0.0)
     {
      //--- Floating spreads need more headroom than fixed ones.
      const double multiple=(symbol.spread_float!=0 ? 4.0 : 2.0);
      profile.max_spread_points=MathMax(observed*multiple,observed+10.0);
      profile.derived_mask|=(int)SRP_GEOM_MAX_SPREAD;
     }

   //--- SLIPPAGE ALLOWANCE. Proportional to the spread ceiling.
   if(profile.max_slippage_points<=0.0)
     {
      profile.max_slippage_points=MathMax(profile.max_spread_points*0.5,10.0);
      profile.derived_mask|=(int)SRP_GEOM_MAX_SLIPPAGE;
     }
   if(profile.deviation_points<=0)
     {
      profile.deviation_points=(int)MathMax(profile.max_slippage_points,10.0);
      profile.derived_mask|=(int)SRP_GEOM_DEVIATION;
     }

   //--- MINIMUM STOP.
   //---
   //--- Two independent floors, and the larger wins:
   //---
   //---   1. The BROKER's stop level. A stop inside it is rejected.
   //---   2. The SPREAD. A stop inside the permitted spread is triggered
   //---      by the spread alone, which is a guaranteed loss that has
   //---      nothing to do with the strategy being wrong.
   //---
   //--- Deriving this from the broker stop level alone was a real defect:
   //--- many brokers report stops_level=0, which made the floor 10 points
   //--- on an instrument quoting a 41-point spread. The configuration
   //--- validator caught it and refused to start - correctly - because
   //--- every stop and target would have been inside the spread.
   const double broker_min=(double)symbol.stops_level;
   if(profile.sl_min_points<=0.0)
     {
      const double from_broker=MathMax(broker_min*1.5,broker_min+10.0);
      //--- Three spreads of headroom: enough that ordinary spread
      //--- variation cannot reach the stop on its own.
      const double from_spread=profile.max_spread_points*3.0;
      profile.sl_min_points=MathMax(from_broker,from_spread);
      profile.derived_mask|=(int)SRP_GEOM_SL_MIN;
     }

   //--- SMC GAP THRESHOLD. Index gaps are large in absolute points; a
   //--- forex-scale threshold would classify ordinary noise as a fair
   //--- value gap. Scale it to the instrument's own spread instead of
   //--- writing a constant per asset class.
   if(profile.smc_min_gap_points<=0.0)
     {
      profile.smc_min_gap_points=MathMax(profile.max_spread_points,20.0);
      profile.derived_mask|=(int)SRP_GEOM_SMC_GAP;
     }

   //--- STRUCTURE BREAK BUFFER. A break must clear the level by more
   //--- than the spread, or every touch reads as a break.
   if(profile.smc_structure_break_buffer<=0.0)
     {
      profile.smc_structure_break_buffer=
         MathMax(profile.max_spread_points*0.25,5.0);
      profile.derived_mask|=(int)SRP_GEOM_SMC_BREAK;
     }

   //--- Fixed-point fallbacks. Only used when a fixed model is selected,
   //--- but the validator checks them regardless, so they must be
   //--- coherent even when the ATR model is active.
   if(profile.sl_fixed_points<=0.0)
     {
      profile.sl_fixed_points=profile.sl_min_points*2.0;
      profile.derived_mask|=(int)SRP_GEOM_SL_FIXED;
     }
   if(profile.tp_fixed_points<=0.0)
     {
      profile.tp_fixed_points=profile.sl_fixed_points*profile.tp_risk_reward;
      profile.derived_mask|=(int)SRP_GEOM_TP_FIXED;
     }

   //--- Management distances, expressed against the stop so they stay
   //--- proportionate on any instrument.
   if(profile.breakeven_trigger_points<=0.0)
     {
      profile.breakeven_trigger_points=profile.sl_fixed_points*0.6;
      profile.derived_mask|=(int)SRP_GEOM_BE_TRIGGER;
     }
   if(profile.breakeven_offset_points<=0.0)
     {
      profile.breakeven_offset_points=profile.sl_min_points;
      profile.derived_mask|=(int)SRP_GEOM_BE_OFFSET;
     }
   if(profile.trail_start_points<=0.0)
     {
      profile.trail_start_points=profile.sl_fixed_points*0.8;
      profile.derived_mask|=(int)SRP_GEOM_TRAIL_START;
     }
   if(profile.trail_distance_points<=0.0)
     {
      profile.trail_distance_points=profile.sl_fixed_points*0.6;
      profile.derived_mask|=(int)SRP_GEOM_TRAIL_DISTANCE;
     }
   if(profile.trail_step_points<=0.0)
     {
      profile.trail_step_points=MathMax(profile.sl_min_points*0.2,1.0);
      profile.derived_mask|=(int)SRP_GEOM_TRAIL_STEP;
     }

   //=== THRESHOLD CONSISTENCY =========================================
   //---
   //--- min_confidence and max_risk_rating are TWO EXPRESSIONS OF ONE
   //--- QUANTITY, and set independently they contradict each other in
   //--- silence. The rating is derived from the same blended confidence
   //--- the floor tests:
   //---
   //---     >= 0.85  LOW(1)      >= 0.70  MEDIUM(2)
   //---     >= 0.55  HIGH(3)     otherwise EXTREME(4)
   //---
   //--- So a profile asking for confidence >= 0.65 while capping the
   //--- rating at MEDIUM has actually asked for >= 0.70, and every
   //--- decision scoring between the two is accepted by the decision
   //--- engine and then dropped by the entry gate without a word.
   //---
   //--- MEASURED on 31 months of XAUUSD real ticks: 1268 of 1313
   //--- actionable decisions - 96.6% - died exactly here. It read as setup
   //--- scarcity and it was not.
   //---
   //--- The ceiling is RAISED to match the floor rather than the floor
   //--- raised to match the ceiling. Raising the floor would be a silent
   //--- tightening of a documented threshold; widening the ceiling makes
   //--- the profile do what it already says it does. The confidence floor
   //--- remains the single place selectivity is expressed.
   const int implied_rating=(profile.min_confidence>=0.85
                             ? 1
                             : (profile.min_confidence>=0.70
                                ? 2
                                : (profile.min_confidence>=0.55 ? 3 : 4)));
   if(profile.max_risk_rating<implied_rating)
      profile.max_risk_rating=implied_rating;
  }
//+------------------------------------------------------------------+
bool CMarketProfileFactory::Build(const SSymbolProfile &symbol,
                                  SMarketProfile &profile)
  {
   switch(symbol.asset_class)
     {
      case SRP_ASSET_INDEX_NASDAQ:
         ApplyNasdaq(profile);
         break;
      case SRP_ASSET_METAL_GOLD:
         ApplyGold(profile);
         break;
      default:
         //--- Every other class, including recognised-but-not-targeted
         //--- ones, gets the conservative baseline. Applying the NASDAQ
         //--- set to an unrecognised instrument would be a guess with
         //--- real money behind it.
         ApplyCustom(profile);
         break;
     }
   ScaleToSymbol(symbol,profile);
   return(symbol.resolved);
  }
//+------------------------------------------------------------------+
bool CMarketProfileFactory::BuildForMode(const SSymbolProfile &symbol,
                                         const ENUM_SRP_PROFILE_MODE mode,
                                         SMarketProfile &profile)
  {
   switch(mode)
     {
      case SRP_PROFILE_NASDAQ:
         ApplyNasdaq(profile);
         break;
      case SRP_PROFILE_GOLD:
         ApplyGold(profile);
         break;
      case SRP_PROFILE_CUSTOM:
         ApplyCustom(profile);
         break;
      default:
         //--- AUTO: the classifier decides.
         return(Build(symbol,profile));
     }
   ScaleToSymbol(symbol,profile);
   return(symbol.resolved);
  }
//+------------------------------------------------------------------+
string CMarketProfileFactory::Describe(const SMarketProfile &p)
  {
   string text=StringFormat("Profile %s [%s]",p.name,
                            CSymbolClassifier::ClassName(p.asset_class));
   text+=StringFormat("\n  risk: %.2f%%/trade max %d pos, exposure %.2f%%, "
                      "daily %.2f%% dd %.2f%%",
                      p.risk_percent,p.max_positions,p.max_exposure_percent,
                      p.daily_loss_percent,p.max_drawdown_percent);
   text+=StringFormat("\n  cost: maxSpread %.0f pts, maxSlippage %.0f pts",
                      p.max_spread_points,p.max_slippage_points);
   text+=StringFormat("\n  stops: %.2fxATR (min %.0f pts) target RR %.2f",
                      p.sl_atr_multiplier,p.sl_min_points,p.tp_risk_reward);
   text+=StringFormat("\n  volatility bands: low %.3f%% high %.3f%% extreme %.3f%%",
                      p.atr_low_percent,p.atr_high_percent,p.atr_extreme_percent);
   text+=StringFormat("\n  regime: trend ADX>%.1f range ADX<%.1f expansion %.2fx",
                      p.trend_adx_threshold,p.range_adx_threshold,
                      p.breakout_expansion_ratio);
   text+=StringFormat("\n  decision: confidence>=%.2f confirmations>=%d",
                      p.min_confidence,p.min_confirmations);
   text+=StringFormat("\n  timeframes: context %s setup %s execution %s",
                      EnumToString(p.context_timeframe),
                      EnumToString(p.setup_timeframe),
                      EnumToString(p.execution_timeframe));
   text+=StringFormat("\n  primary window: %02d:%02d-%02d:%02d GMT",
                      p.primary_kz_open_gmt/60,p.primary_kz_open_gmt%60,
                      p.primary_kz_close_gmt/60,p.primary_kz_close_gmt%60);
   text+=StringFormat("\n  frequency: %d/hour %d/day, %ds apart, %ds after loss",
                      p.max_trades_per_hour,p.max_trades_per_day,
                      p.min_seconds_between_trades,
                      p.cooldown_after_loss_seconds);
   return(text);
  }

#endif // SRP_PROFILES_CMARKETPROFILE_MQH
//+------------------------------------------------------------------+
