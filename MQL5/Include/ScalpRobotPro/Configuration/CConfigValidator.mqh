//+------------------------------------------------------------------+
//|                                            CConfigValidator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Configuration : coherence checks across settings.                  |
//|                                                                  |
//|   RESPONSIBILITY (one only): decide whether a configuration is       |
//|   sane. Split from CInputConfiguration because storage and           |
//|   validation change for different reasons - new rules are added      |
//|   here without touching the container.                              |
//|                                                                  |
//|   It catches the cross-field contradictions that individually        |
//|   valid inputs still produce: a take profit tighter than the         |
//|   spread, a trailing step larger than its distance, a daily loss     |
//|   limit smaller than a single trade's risk. Each of those silently   |
//|   breaks a live account, so validation happens BEFORE the first      |
//|   tick and aborts OnInit on failure.                                 |
//+------------------------------------------------------------------+
#ifndef SRP_CONFIGURATION_CCONFIGVALIDATOR_MQH
#define SRP_CONFIGURATION_CCONFIGVALIDATOR_MQH

#include "../Core/Interfaces/IConfigProvider.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Types/Structs.mqh"
//--- risk.mode is stored in the Phase 2 sizing vocabulary, so the rules
//--- below must be written against those enumerators.
#include "../Intelligence/Types/IntelligenceEnums.mqh"

class CConfigValidator
  {
private:
   ILogger          *m_logger;            // borrowed
   SSymbolSpec       m_spec;              // for broker-relative checks
   bool              m_spec_available;

   //--- Grouped rule sets, one method per concern.
   void              ValidateGeneral(IConfigProvider *config,SValidationResult &result);
   void              ValidateRisk(IConfigProvider *config,SValidationResult &result);
   void              ValidateStopLevels(IConfigProvider *config,SValidationResult &result);
   void              ValidateGuards(IConfigProvider *config,SValidationResult &result);
   void              ValidateSchedule(IConfigProvider *config,SValidationResult &result);
   void              ValidateNews(IConfigProvider *config,SValidationResult &result);
   void              ValidateFilters(IConfigProvider *config,SValidationResult &result);
   void              ValidateStrategies(IConfigProvider *config,SValidationResult &result);
   void              ValidateIndicators(IConfigProvider *config,SValidationResult &result);
   void              ValidateDashboard(IConfigProvider *config,SValidationResult &result);

   //--- Cross-cutting checks that involve more than one group.
   void              ValidateCrossConstraints(IConfigProvider *config,
                                              SValidationResult &result);
   //--- Broker-relative checks (stop level, volume step, filling mode).
   void              ValidateAgainstBroker(IConfigProvider *config,
                                          SValidationResult &result);

public:
                     CConfigValidator(ILogger *logger);
                    ~CConfigValidator(void) { }

   //--- Supplying the spec enables broker-relative rules. Without it
   //--- validation still runs, but reports those checks as skipped.
   void              SetSymbolSpec(const SSymbolSpec &spec);

   //--- Runs every rule set. Returns result.is_valid.
   bool              ValidateAll(IConfigProvider *config,SValidationResult &result);
  };

#include "CConfigKeys.mqh"

//+------------------------------------------------------------------+
CConfigValidator::CConfigValidator(ILogger *logger)
  : m_logger(logger),
    m_spec_available(false)
  {
   m_spec.Reset();
  }
//+------------------------------------------------------------------+
void CConfigValidator::SetSymbolSpec(const SSymbolSpec &spec)
  {
   m_spec=spec;
   m_spec_available=spec.is_resolved;
  }
//+------------------------------------------------------------------+
bool CConfigValidator::ValidateAll(IConfigProvider *config,
                                   SValidationResult &result)
  {
   if(config==NULL)
     {
      result.AddError("no configuration provider supplied");
      return(false);
     }
   ValidateGeneral(config,result);
   ValidateRisk(config,result);
   ValidateStopLevels(config,result);
   ValidateGuards(config,result);
   ValidateSchedule(config,result);
   ValidateNews(config,result);
   ValidateFilters(config,result);
   ValidateStrategies(config,result);
   ValidateIndicators(config,result);
   ValidateDashboard(config,result);
   ValidateCrossConstraints(config,result);
   ValidateAgainstBroker(config,result);

   if(m_logger!=NULL)
     {
      if(result.is_valid)
         m_logger.Info("ConfigValidator",
                       "configuration accepted with "+
                       IntegerToString(result.warning_count)+" warning(s)");
      else
         m_logger.Error("ConfigValidator",
                        "configuration REJECTED: "+result.first_error);
     }
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
void CConfigValidator::ValidateGeneral(IConfigProvider *config,
                                       SValidationResult &result)
  {
   //--- A zero magic number makes the EA adopt every manual trade on the
   //--- chart, including ones a human opened. That is a real account risk,
   //--- not a style preference.
   if(config.GetLong(CConfigKeys::GENERAL_MAGIC,0)<=0)
      result.AddError("general.magic must be a positive number, otherwise the "
                      "EA cannot distinguish its own positions");

   const int throttle=config.GetInt(CConfigKeys::GENERAL_TICK_THROTTLE_MS,0);
   if(throttle<0)
      result.AddError("general.tick_throttle_ms cannot be negative");
   if(throttle>5000)
      result.AddWarning("general.tick_throttle_ms above 5000 will miss "
                        "scalping entries");
  }
//+------------------------------------------------------------------+
void CConfigValidator::ValidateRisk(IConfigProvider *config,
                                    SValidationResult &result)
  {
   const double risk_percent=config.GetDouble(CConfigKeys::RISK_PERCENT,0.0);
   const double fixed_lot=config.GetDouble(CConfigKeys::RISK_FIXED_LOT,0.0);
   const double max_lot=config.GetDouble(CConfigKeys::RISK_MAX_LOT,0.0);
   //--- risk.mode is stored in the Phase 2 SIZING vocabulary, which is
   //--- what the production engine builds its sizer from. Validating
   //--- against the Phase 1 RISK_MODE numbering would check a different
   //--- model than the one that will actually run.
   const int mode=config.GetInt(CConfigKeys::RISK_MODE,0);

   if(mode==(int)SRP_SIZING_FIXED_LOT && fixed_lot<=0.0)
      result.AddError("risk.fixed_lot must be positive when risk.mode is "
                      "FIXED_LOT");
   //--- Every percentage-of-capital model divides by this figure.
   if((mode==(int)SRP_SIZING_RISK_PERCENT ||
       mode==(int)SRP_SIZING_ATR ||
       mode==(int)SRP_SIZING_DYNAMIC ||
       mode==(int)SRP_SIZING_KELLY) && risk_percent<=0.0)
      result.AddError("risk.percent must be positive for the selected "
                      "risk-based sizing model");

   if(risk_percent<0.0)
      result.AddError("risk.percent cannot be negative");
   //--- Not an arbitrary ceiling: above ~5% per trade, a normal losing
   //--- streak is mathematically likely to end the account.
   if(risk_percent>5.0)
      result.AddError("risk.percent above 5.0 is rejected as unsurvivable; "
                      "a routine losing streak would end the account");
   else
      if(risk_percent>2.0)
         result.AddWarning("risk.percent above 2.0 is aggressive for scalping");

   if(max_lot<0.0)
      result.AddError("risk.max_lot cannot be negative");
   if(max_lot>0.0 && fixed_lot>max_lot)
      result.AddError("risk.fixed_lot exceeds risk.max_lot");

   if(config.GetInt(CConfigKeys::RISK_MAX_POSITIONS,1)<1)
      result.AddError("risk.max_positions must be at least 1");

   const double margin_floor=
      config.GetDouble(CConfigKeys::RISK_MIN_FREE_MARGIN_PERCENT,0.0);
   if(margin_floor<0.0 || margin_floor>100.0)
      result.AddError("risk.min_free_margin_percent must be within 0..100");

   const double max_spread=config.GetDouble(CConfigKeys::RISK_MAX_SPREAD_POINTS,0.0);
   if(max_spread<0.0)
      result.AddError("risk.max_spread_points cannot be negative");
   //--- Zero means "no limit" in most EAs and silently disables spread
   //--- protection. On an index during a news spike that is expensive.
   if(max_spread==0.0)
      result.AddWarning("risk.max_spread_points is 0, spread protection is "
                        "effectively disabled");

   if(config.GetInt(CConfigKeys::RISK_MAX_SLIPPAGE_POINTS,0)<0)
      result.AddError("risk.max_slippage_points cannot be negative");

   const double kelly=config.GetDouble(CConfigKeys::RISK_KELLY_FRACTION,0.0);
   if(kelly<0.0 || kelly>1.0)
      result.AddError("risk.kelly_fraction must be within 0..1");
   //--- Full Kelly is theoretically growth-optimal and practically
   //--- ruinous, because it assumes the edge is known exactly.
   if(kelly>0.5)
      result.AddWarning("risk.kelly_fraction above 0.5 produces very large "
                        "position swings; half-Kelly or less is usual");
  }
//+------------------------------------------------------------------+
void CConfigValidator::ValidateStopLevels(IConfigProvider *config,
                                          SValidationResult &result)
  {
   const int sl_mode=config.GetInt(CConfigKeys::SL_MODE,0);
   const double sl_points=config.GetDouble(CConfigKeys::SL_FIXED_POINTS,0.0);
   const double sl_atr=config.GetDouble(CConfigKeys::SL_ATR_MULTIPLIER,0.0);

   //--- Trading with no stop at all is a product-level decision, not a
   //--- parameter. It is refused outright.
   if(sl_mode==(int)SRP_SL_NONE)
      result.AddError("sl.mode NONE is not permitted in production: an "
                      "unprotected position can exceed the account");
   if(sl_mode==(int)SRP_SL_FIXED_POINTS && sl_points<=0.0)
      result.AddError("sl.fixed_points must be positive for a fixed stop");
   if(sl_mode==(int)SRP_SL_ATR_MULTIPLE && sl_atr<=0.0)
      result.AddError("sl.atr_multiplier must be positive for an ATR stop");

   const int tp_mode=config.GetInt(CConfigKeys::TP_MODE,0);
   const double tp_points=config.GetDouble(CConfigKeys::TP_FIXED_POINTS,0.0);
   const double rr=config.GetDouble(CConfigKeys::TP_RISK_REWARD,0.0);

   if(tp_mode==(int)SRP_TP_FIXED_POINTS && tp_points<=0.0)
      result.AddError("tp.fixed_points must be positive for a fixed target");
   if(tp_mode==(int)SRP_TP_RISK_REWARD && rr<=0.0)
      result.AddError("tp.risk_reward must be positive for an RR target");
   //--- Scalping below 1:0.5 needs an exceptional win rate to break even.
   if(rr>0.0 && rr<0.5)
      result.AddWarning("tp.risk_reward below 0.5 requires a very high win "
                        "rate merely to break even");

   //--- Trailing coherence. A step wider than the distance means the
   //--- stop leapfrogs past price and the trail never settles.
   const double trail_distance=
      config.GetDouble(CConfigKeys::TRAIL_DISTANCE_POINTS,0.0);
   const double trail_step=config.GetDouble(CConfigKeys::TRAIL_STEP_POINTS,0.0);
   const double trail_start=config.GetDouble(CConfigKeys::TRAIL_START_POINTS,0.0);
   const int trail_mode=config.GetInt(CConfigKeys::TRAIL_MODE,0);

   if(trail_mode!=(int)SRP_TRAIL_DISABLED)
     {
      if(trail_distance<=0.0)
         result.AddError("trail.distance_points must be positive when "
                         "trailing is enabled");
      if(trail_step<0.0)
         result.AddError("trail.step_points cannot be negative");
      if(trail_step>trail_distance && trail_distance>0.0)
         result.AddError("trail.step_points exceeds trail.distance_points; "
                         "the stop would jump past price and never settle");
      if(trail_start>0.0 && trail_start<trail_distance)
         result.AddWarning("trail.start_points is below trail.distance_points, "
                           "so the first trail would move the stop backwards "
                           "and be rejected");
     }

   //--- Break-even.
   if(config.GetBool(CConfigKeys::BREAKEVEN_ENABLED,false))
     {
      const double be_trigger=
         config.GetDouble(CConfigKeys::BREAKEVEN_TRIGGER_POINTS,0.0);
      const double be_offset=
         config.GetDouble(CConfigKeys::BREAKEVEN_OFFSET_POINTS,0.0);
      if(be_trigger<=0.0)
         result.AddError("breakeven.trigger_points must be positive");
      if(be_offset<0.0)
         result.AddError("breakeven.offset_points cannot be negative");
      if(be_offset>=be_trigger && be_trigger>0.0)
         result.AddError("breakeven.offset_points must be smaller than its "
                         "trigger, otherwise the stop lands beyond price");
     }

   //--- Partial close.
   if(config.GetBool(CConfigKeys::PARTIAL_CLOSE_ENABLED,false))
     {
      const double percent=
         config.GetDouble(CConfigKeys::PARTIAL_CLOSE_PERCENT,0.0);
      if(percent<=0.0 || percent>=100.0)
         result.AddError("partial.percent must be within 0..100 exclusive");
      if(config.GetDouble(CConfigKeys::PARTIAL_CLOSE_TRIGGER_POINTS,0.0)<=0.0)
         result.AddError("partial.trigger_points must be positive");
     }

   if(config.GetBool(CConfigKeys::TIME_STOP_ENABLED,false) &&
      config.GetInt(CConfigKeys::TIME_STOP_MINUTES,0)<=0)
      result.AddError("timestop.minutes must be positive when the time stop "
                      "is enabled");
  }
//+------------------------------------------------------------------+
void CConfigValidator::ValidateGuards(IConfigProvider *config,
                                      SValidationResult &result)
  {
   const double daily_loss=
      config.GetDouble(CConfigKeys::GUARD_DAILY_LOSS_PERCENT,0.0);
   const double weekly_loss=
      config.GetDouble(CConfigKeys::RISK_WEEKLY_LOSS_PERCENT,0.0);
   const double monthly_loss=
      config.GetDouble(CConfigKeys::RISK_MONTHLY_LOSS_PERCENT,0.0);
   const double max_dd=
      config.GetDouble(CConfigKeys::GUARD_MAX_DRAWDOWN_PERCENT,0.0);

   if(config.GetBool(CConfigKeys::GUARD_DAILY_LOSS_ENABLED,false))
     {
      if(daily_loss<=0.0)
         result.AddError("guard.daily_loss_percent must be positive when the "
                         "daily loss guard is enabled");
      if(daily_loss>50.0)
         result.AddWarning("guard.daily_loss_percent above 50 is not a "
                           "meaningful daily limit");
     }
   if(config.GetBool(CConfigKeys::GUARD_MAX_DRAWDOWN_ENABLED,false))
     {
      if(max_dd<=0.0)
         result.AddError("guard.max_drawdown_percent must be positive when "
                         "the drawdown guard is enabled");
      if(max_dd>=100.0)
         result.AddError("guard.max_drawdown_percent of 100 or more can never "
                         "trip before the account is gone");
     }

   //--- The limit ladder must be monotonic. A weekly limit tighter than
   //--- the daily one means the daily guard can never fire, which is a
   //--- silent misconfiguration rather than an obvious error.
   if(daily_loss>0.0 && weekly_loss>0.0 && weekly_loss<daily_loss)
      result.AddError("risk.weekly_loss_percent is below "
                      "guard.daily_loss_percent, so the daily guard can "
                      "never trip first");
   if(weekly_loss>0.0 && monthly_loss>0.0 && monthly_loss<weekly_loss)
      result.AddError("risk.monthly_loss_percent is below "
                      "risk.weekly_loss_percent, so the weekly guard can "
                      "never trip first");
   if(daily_loss>0.0 && max_dd>0.0 && max_dd<daily_loss)
      result.AddWarning("guard.max_drawdown_percent is below the daily loss "
                        "limit, so the drawdown guard will always trip first");

   if(config.GetInt(CConfigKeys::GUARD_CONSECUTIVE_LOSS_LIMIT,0)<0)
      result.AddError("guard.consecutive_loss_limit cannot be negative");

   //--- Profit lock.
   if(config.GetBool(CConfigKeys::RISK_PROFIT_LOCK_ENABLED,false))
     {
      const double trigger=
         config.GetDouble(CConfigKeys::RISK_PROFIT_LOCK_TRIGGER_PERCENT,0.0);
      const double keep=
         config.GetDouble(CConfigKeys::RISK_PROFIT_LOCK_KEEP_PERCENT,0.0);
      if(trigger<=0.0)
         result.AddError("risk.profit_lock_trigger_percent must be positive");
      if(keep<=0.0 || keep>100.0)
         result.AddError("risk.profit_lock_keep_percent must be within 0..100");
     }
  }
//+------------------------------------------------------------------+
void CConfigValidator::ValidateSchedule(IConfigProvider *config,
                                        SValidationResult &result)
  {
   if(config.GetBool(CConfigKeys::SESSION_FILTER_ENABLED,false))
     {
      //--- Every session disabled with the filter on means the EA will
      //--- never trade. It compiles, it runs, it does nothing.
      const bool any=config.GetBool(CConfigKeys::SESSION_ALLOW_SYDNEY,false) ||
                     config.GetBool(CConfigKeys::SESSION_ALLOW_TOKYO,false) ||
                     config.GetBool(CConfigKeys::SESSION_ALLOW_LONDON,false) ||
                     config.GetBool(CConfigKeys::SESSION_ALLOW_NEWYORK,false);
      if(!any)
         result.AddError("the session filter is enabled but every session is "
                         "disabled, so no trade can ever be taken");
     }

   const int gmt=config.GetInt(CConfigKeys::SESSION_BROKER_GMT_OFFSET,0);
   if(gmt<-12 || gmt>14)
      result.AddError("session.broker_gmt_offset must be within -12..+14");

   const int friday_close=
      config.GetInt(CConfigKeys::SCHEDULE_FRIDAY_CLOSE_MINUTES,0);
   if(friday_close<0 || friday_close>1440)
      result.AddError("schedule.friday_close_minutes must be within 0..1440");
  }
//+------------------------------------------------------------------+
void CConfigValidator::ValidateNews(IConfigProvider *config,
                                    SValidationResult &result)
  {
   if(!config.GetBool(CConfigKeys::NEWS_FILTER_ENABLED,false))
      return;

   const int before=config.GetInt(CConfigKeys::NEWS_MINUTES_BEFORE,0);
   const int after=config.GetInt(CConfigKeys::NEWS_MINUTES_AFTER,0);
   if(before<0 || after<0)
      result.AddError("news blackout windows cannot be negative");
   if(before==0 && after==0)
      result.AddWarning("the news filter is enabled but both blackout windows "
                        "are 0, so nothing is actually blocked");
   if(before>240 || after>240)
      result.AddWarning("a news blackout beyond 4 hours will suppress most of "
                        "a scalping session");

   //--- A CSV source with no file is the classic silent failure: the EA
   //--- reports "news filter on" and blocks nothing.
   if(config.GetInt(CConfigKeys::NEWS_SOURCE,0)==(int)SRP_NEWS_SOURCE_CSV_FILE &&
      config.GetString(CConfigKeys::NEWS_CSV_FILE,"")=="")
      result.AddError("news.source is CSV but news.csv_file is empty");

   if(!config.GetBool(CConfigKeys::NEWS_FAIL_SAFE_BLOCK,false))
      result.AddWarning("news.fail_safe_block is off: if the calendar is "
                        "unavailable the EA will trade through news");
  }
//+------------------------------------------------------------------+
void CConfigValidator::ValidateFilters(IConfigProvider *config,
                                       SValidationResult &result)
  {
   if(config.GetBool(CConfigKeys::FILTER_VOLATILITY_ENABLED,false))
     {
      const double min_atr=
         config.GetDouble(CConfigKeys::FILTER_VOLATILITY_MIN_ATR,0.0);
      const double max_atr=
         config.GetDouble(CConfigKeys::FILTER_VOLATILITY_MAX_ATR,0.0);
      if(min_atr<0.0 || max_atr<0.0)
         result.AddError("volatility filter bounds cannot be negative");
      if(max_atr>0.0 && min_atr>0.0 && min_atr>=max_atr)
         result.AddError("filter.volatility_min_atr is not below "
                         "filter.volatility_max_atr, so the window is empty");
     }

   if(config.GetBool(CConfigKeys::FILTER_FREQUENCY_ENABLED,false))
     {
      if(config.GetInt(CConfigKeys::FILTER_MIN_SECONDS_BETWEEN_TRADES,0)<0)
         result.AddError("filter.min_seconds_between_trades cannot be negative");
      const int per_day=config.GetInt(CConfigKeys::FILTER_MAX_TRADES_PER_DAY,0);
      const int per_hour=config.GetInt(CConfigKeys::FILTER_MAX_TRADES_PER_HOUR,0);
      if(per_day<0 || per_hour<0)
         result.AddError("trade frequency caps cannot be negative");
      //--- An hourly cap above the daily cap is dead configuration.
      if(per_day>0 && per_hour>0 && per_hour>per_day)
         result.AddWarning("filter.max_trades_per_hour exceeds the daily cap, "
                           "so the hourly limit can never bind");
     }
  }
//+------------------------------------------------------------------+
void CConfigValidator::ValidateStrategies(IConfigProvider *config,
                                          SValidationResult &result)
  {
   //--- At least one strategy must be live, or the decision engine has
   //--- nothing to vote on.
   const bool any=
      config.GetBool(CConfigKeys::STRATEGY_MOMENTUM_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_MEAN_REVERSION_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_BREAKOUT_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_EMA_CROSS_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_VWAP_PULLBACK_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_LIQUIDITY_SWEEP_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_ORDER_BLOCK_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_FVG_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_OPENING_RANGE_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_TREND_CONTINUATION_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_BOS_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_VOLATILITY_BREAKOUT_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_ORDER_FLOW_ENABLED,false);
   if(!any)
      result.AddError("no strategy is enabled, the EA would never generate a "
                      "signal");

   const double min_confidence=
      config.GetDouble(CConfigKeys::STRATEGY_MIN_CONFIDENCE,0.0);
   if(min_confidence<0.0 || min_confidence>1.0)
      result.AddError("strategy.min_confidence must be within 0..1");
   if(min_confidence>=0.95)
      result.AddWarning("strategy.min_confidence at 0.95 or above will reject "
                        "almost every signal");

   const int min_confirmations=
      config.GetInt(CConfigKeys::DECISION_MIN_CONFIRMATIONS,0);
   if(min_confirmations<0 || min_confirmations>13)
      result.AddError("decision.min_confirmations must be within 0..13, the "
                      "number of available checks");

   //--- Negative weights would invert a strategy's vote, which is never
   //--- what a user means.
   const double weights[]=
     {
      config.GetDouble(CConfigKeys::STRATEGY_MOMENTUM_WEIGHT,0.0),
      config.GetDouble(CConfigKeys::STRATEGY_MEAN_REVERSION_WEIGHT,0.0),
      config.GetDouble(CConfigKeys::STRATEGY_BREAKOUT_WEIGHT,0.0)
     };
   for(int i=0;i<ArraySize(weights);i++)
      if(weights[i]<0.0)
        {
         result.AddError("strategy weights cannot be negative; a negative "
                         "weight would invert the strategy's vote");
         break;
        }
  }
//+------------------------------------------------------------------+
void CConfigValidator::ValidateIndicators(IConfigProvider *config,
                                          SValidationResult &result)
  {
   const int fast=config.GetInt(CConfigKeys::INDICATOR_FAST_MA_PERIOD,0);
   const int slow=config.GetInt(CConfigKeys::INDICATOR_SLOW_MA_PERIOD,0);
   const int trend=config.GetInt(CConfigKeys::INDICATOR_TREND_MA_PERIOD,0);

   if(fast<1) result.AddError("indicator.fast_ma_period must be at least 1");
   if(slow<1) result.AddError("indicator.slow_ma_period must be at least 1");
   //--- Fast above slow inverts every crossover signal in the product.
   if(fast>0 && slow>0 && fast>=slow)
      result.AddError("indicator.fast_ma_period must be below the slow "
                      "period, otherwise every crossover signal is inverted");
   if(slow>0 && trend>0 && slow>=trend)
      result.AddWarning("indicator.slow_ma_period is not below the trend "
                        "period, so the trend filter adds little information");

   const int periods[]=
     {
      config.GetInt(CConfigKeys::INDICATOR_RSI_PERIOD,14),
      config.GetInt(CConfigKeys::INDICATOR_ATR_PERIOD,14),
      config.GetInt(CConfigKeys::INDICATOR_ADX_PERIOD,14),
      config.GetInt(CConfigKeys::INDICATOR_BOLLINGER_PERIOD,20)
     };
   for(int i=0;i<ArraySize(periods);i++)
      if(periods[i]<2)
        {
         result.AddError("every indicator period must be at least 2");
         break;
        }

   const double deviation=
      config.GetDouble(CConfigKeys::INDICATOR_BOLLINGER_DEVIATION,0.0);
   if(deviation<=0.0)
      result.AddError("indicator.bollinger_deviation must be positive");

   const int swing_strength=config.GetInt(CConfigKeys::SMC_SWING_STRENGTH,0);
   if(swing_strength<1)
      result.AddError("smc.swing_strength must be at least 1");
   const int lookback=config.GetInt(CConfigKeys::SMC_SWING_LOOKBACK,0);
   if(lookback>0 && lookback<swing_strength*2+1)
      result.AddError("smc.swing_lookback is too small to contain a single "
                      "swing at the configured strength");
  }
//+------------------------------------------------------------------+
void CConfigValidator::ValidateDashboard(IConfigProvider *config,
                                         SValidationResult &result)
  {
   const int corner=config.GetInt(CConfigKeys::DASHBOARD_CORNER,0);
   if(corner<0 || corner>3)
      result.AddError("dashboard.corner must be within 0..3");
   if(config.GetInt(CConfigKeys::DASHBOARD_X_OFFSET,0)<0 ||
      config.GetInt(CConfigKeys::DASHBOARD_Y_OFFSET,0)<0)
      result.AddError("dashboard offsets cannot be negative");

   const int refresh=config.GetInt(CConfigKeys::DASHBOARD_REFRESH_MS,0);
   if(refresh<0)
      result.AddError("dashboard.refresh_ms cannot be negative");
   //--- Repainting on every tick of an index is the most common cause of
   //--- a visibly laggy chart.
   if(refresh>0 && refresh<100)
      result.AddWarning("dashboard.refresh_ms below 100 repaints far more "
                        "often than a human can read and will load the chart");

   if(config.GetInt(CConfigKeys::DRAW_MAX_ZONES,0)<0)
      result.AddError("draw.max_zones cannot be negative");

   const int flush=config.GetInt(CConfigKeys::LOG_FLUSH_EVERY,1);
   if(flush<1)
      result.AddError("log.flush_every must be at least 1");

   if(config.GetInt(CConfigKeys::ANALYTICS_MIN_SAMPLE,10)<2)
      result.AddError("analytics.min_sample must be at least 2 for a standard "
                      "deviation to exist");
  }
//+------------------------------------------------------------------+
//| Cross-group rules: the contradictions that individually valid       |
//| settings still produce. These are the ones that quietly break live  |
//| accounts, which is why they run before the first tick.              |
//+------------------------------------------------------------------+
void CConfigValidator::ValidateCrossConstraints(IConfigProvider *config,
                                                SValidationResult &result)
  {
   const double sl_points=config.GetDouble(CConfigKeys::SL_FIXED_POINTS,0.0);
   const double tp_points=config.GetDouble(CConfigKeys::TP_FIXED_POINTS,0.0);
   const double max_spread=
      config.GetDouble(CConfigKeys::RISK_MAX_SPREAD_POINTS,0.0);

   //--- A target inside the spread cannot be reached: the position opens
   //--- already past it and closes at a loss after costs.
   if(tp_points>0.0 && max_spread>0.0 && tp_points<=max_spread)
      result.AddError("tp.fixed_points is inside the permitted spread, so the "
                      "target can never be profitably reached");
   if(sl_points>0.0 && max_spread>0.0 && sl_points<=max_spread)
      result.AddError("sl.fixed_points is inside the permitted spread, so the "
                      "stop would trigger on the spread alone");

   //--- Break-even must trigger before the target, or it never fires.
   const double be_trigger=
      config.GetDouble(CConfigKeys::BREAKEVEN_TRIGGER_POINTS,0.0);
   if(config.GetBool(CConfigKeys::BREAKEVEN_ENABLED,false) &&
      be_trigger>0.0 && tp_points>0.0 && be_trigger>=tp_points)
      result.AddError("breakeven.trigger_points is at or beyond the take "
                      "profit, so break-even can never fire");

   //--- Same for the partial close and the scale-out ladder.
   const double partial_trigger=
      config.GetDouble(CConfigKeys::PARTIAL_CLOSE_TRIGGER_POINTS,0.0);
   if(config.GetBool(CConfigKeys::PARTIAL_CLOSE_ENABLED,false) &&
      partial_trigger>0.0 && tp_points>0.0 && partial_trigger>=tp_points)
      result.AddWarning("partial.trigger_points is at or beyond the take "
                        "profit, so the partial close will rarely fire");

   //--- A single trade's risk must be smaller than the daily budget, or
   //--- one loss trips the day.
   const double risk_percent=config.GetDouble(CConfigKeys::RISK_PERCENT,0.0);
   const double daily_loss=
      config.GetDouble(CConfigKeys::GUARD_DAILY_LOSS_PERCENT,0.0);
   if(risk_percent>0.0 && daily_loss>0.0 && risk_percent>=daily_loss)
      result.AddError("risk.percent is at or above guard.daily_loss_percent, "
                      "so a single losing trade would halt the day");

   //--- Max hold must exceed the time stop, otherwise the time exit is
   //--- unreachable dead configuration.
   const int time_stop=config.GetInt(CConfigKeys::TIME_STOP_MINUTES,0);
   const int max_hold=config.GetInt(CConfigKeys::TM_MAX_HOLD_MINUTES,0);
   if(config.GetBool(CConfigKeys::TIME_STOP_ENABLED,false) &&
      config.GetBool(CConfigKeys::TM_MAX_HOLD_ENABLED,false) &&
      time_stop>0 && max_hold>0 && max_hold<=time_stop)
      result.AddWarning("tm.max_hold_minutes is at or below "
                        "timestop.minutes, so the time stop never fires");

   //--- Scale-out fractions must leave something behind.
   const double scale_out_fraction=
      config.GetDouble(CConfigKeys::TM_SCALE_OUT_FRACTION,0.0);
   const int scale_out_max=config.GetInt(CConfigKeys::TM_SCALE_OUT_MAX,0);
   if(config.GetBool(CConfigKeys::TM_SCALE_OUT_ENABLED,false))
     {
      if(scale_out_fraction<=0.0 || scale_out_fraction>=1.0)
         result.AddError("tm.scale_out_fraction must be within 0..1 exclusive");
      if(scale_out_max<1)
         result.AddError("tm.scale_out_max must be at least 1 when scaling out");
     }
   if(config.GetBool(CConfigKeys::TM_SCALE_IN_ENABLED,false))
     {
      const double fraction=
         config.GetDouble(CConfigKeys::TM_SCALE_IN_FRACTION,0.0);
      if(fraction<=0.0)
         result.AddError("tm.scale_in_fraction must be positive when scaling in");
      if(config.GetInt(CConfigKeys::TM_SCALE_IN_MAX,0)<1)
         result.AddError("tm.scale_in_max must be at least 1 when scaling in");
      //--- Adding to a position enlarges the risk that was sized once.
      if(config.GetInt(CConfigKeys::RISK_MAX_POSITIONS,1)<=1)
         result.AddWarning("scale-in is enabled but risk.max_positions is 1; "
                           "on a netting account the addition still increases "
                           "the sized risk");
     }

   //--- ATR-based levels need an ATR period to exist.
   if((config.GetInt(CConfigKeys::SL_MODE,0)==(int)SRP_SL_ATR_MULTIPLE ||
       config.GetBool(CConfigKeys::TM_ATR_EXIT_ENABLED,false) ||
       config.GetBool(CConfigKeys::TM_ATR_TRAIL_ENABLED,false)) &&
      config.GetInt(CConfigKeys::INDICATOR_ATR_PERIOD,0)<2)
      result.AddError("an ATR-based stop, trail or exit is enabled but "
                      "indicator.atr_period is not usable");

   //--- SMC strategies without the SMC engine produce no signals at all.
   const bool smc_strategy=
      config.GetBool(CConfigKeys::STRATEGY_ORDER_BLOCK_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_FVG_ENABLED,false) ||
      config.GetBool(CConfigKeys::STRATEGY_LIQUIDITY_SWEEP_ENABLED,false);
   if(smc_strategy && !config.GetBool(CConfigKeys::SMC_ENABLED,true))
      result.AddError("an SMC strategy is enabled but smc.enabled is false, "
                      "so those strategies can never see a zone");

   //=== HARNESS v2, FIX 3: THE COST MODEL MUST BE STATED ==============
   //--- Nothing validated any scalp.* key before this. Commission in
   //--- particular sat at 0.0 through every historical run, and a zero
   //--- commission is not a neutral default on a system whose entire edge
   //--- is a few points wide: it silently widens the set of targets that
   //--- look viable, lowers the early-exit floor and lets the cost block
   //--- pass trades that in reality never cleared their own costs.
   //---
   //--- Warning, not error, because zero is legitimate on a spread-only
   //--- account. The point is that the run must SAY so rather than inherit
   //--- it, and fix 4 stamps whatever is chosen into the report header.
   const double commission=
      config.GetDouble(CConfigKeys::SCALP_COMMISSION_POINTS,0.0);
   if(commission<=0.0)
      result.AddWarning("scalp.commission_points is 0: the run models a "
                        "broker that charges nothing to trade. Set it to the "
                        "real round-turn cost (on XAUUSD 1 point = $1 per "
                        "lot) or state explicitly that the account is "
                        "spread-only");
   //--- A commission larger than the minimum target is self-contradictory:
   //--- every trade would be a loser before it began.
   const double target_min=
      config.GetDouble(CConfigKeys::SCALP_TARGET_MIN_POINTS,0.0);
   if(target_min>0.0 && commission>=target_min)
      result.AddError("scalp.commission_points is at or above "
                      "scalp.target_min_points, so no target can ever repay "
                      "its own cost");

   //=== HARNESS v2, FIX 4: THE RUN MUST SAY WHAT IT IS ================
   //--- Warning, not error. An undeclared run is still a legitimate thing
   //--- to execute - a smoke test, a visual check, a live account - and
   //--- refusing to build one would make the harness harder to use than the
   //--- thing it replaced. What must not happen is an undeclared run
   //--- producing a figure that later reads as validation, and the report
   //--- header now refuses to let it: it prints UNDECLARED and QUOTABLE=NO.
   //--- This warning is the earlier of the two chances to notice.
   const int segment=config.GetInt(CConfigKeys::GENERAL_DATA_SEGMENT,
                                   (int)SRP_SEGMENT_UNDECLARED);
   if(segment==(int)SRP_SEGMENT_UNDECLARED)
      result.AddWarning("general.data_segment is UNDECLARED: this run's "
                        "results may not be quoted as in-sample or "
                        "out-of-sample evidence. Set it to DEV or OOS to say "
                        "which half of the data the run is speaking for");

   //=== HARNESS v2, FIX 5: THE ROOT OF THE GEOMETRY ===================
   //--- Unlike the segment above, this input moves orders, so it is checked
   //--- for coherence and not merely for presence.
   const double pin=
      config.GetDouble(CConfigKeys::GENERAL_PIN_SPREAD_SAMPLE,0.0);
   //--- ERROR, not a warning. A negative pin would fail the >0 test in
   //--- CSymbolClassifier::PinSpreadSample and be silently ignored, so the
   //--- run would report a pinned geometry it did not have. A configuration
   //--- that lies about being reproducible is worse than one that admits it
   //--- is not, which is why this refuses to start.
   if(pin<0.0)
      result.AddError("general.pin_spread_sample is negative. Use 0 for the "
                      "live tick sample or a positive number of points; a "
                      "negative value would be ignored and the run would "
                      "still claim to be pinned");
   //--- Warning only, and the threshold is deliberately loose. 500 points is
   //--- $5 per lot on XAUUSD - far outside anything this feed has quoted
   //--- (the audit measured 9.5 to 33.5 on real ticks) but not impossible on
   //--- a different instrument or a rollover minute. The stop floor is three
   //--- spread ceilings, so a pin this large inflates every distance in the
   //--- chain and the run silently stops trading rather than failing.
   if(pin>500.0)
      result.AddWarning(StringFormat(
                           "general.pin_spread_sample is %.1f points, which is "
                           "far above anything observed on this feed. Every "
                           "trading distance is derived from it, so the stop "
                           "floor and spread ceiling will be inflated to the "
                           "point where few setups can pass",pin));
  }
//+------------------------------------------------------------------+
//| Broker-relative rules. Skipped rather than guessed when no spec is  |
//| available, because a wrong assumption here rejects a valid config.   |
//+------------------------------------------------------------------+
void CConfigValidator::ValidateAgainstBroker(IConfigProvider *config,
                                             SValidationResult &result)
  {
   if(!m_spec_available)
     {
      result.AddWarning("no symbol spec supplied, broker-relative checks "
                        "(stop level, volume step, trade mode) were skipped");
      return;
     }

   if(m_spec.trade_mode==SYMBOL_TRADE_MODE_DISABLED)
      result.AddError("the broker reports trading disabled for "+m_spec.symbol);
   if(m_spec.trade_mode==SYMBOL_TRADE_MODE_CLOSEONLY)
      result.AddError("the broker permits close-only on "+m_spec.symbol+
                      ", no new position can be opened");

   //--- Stops inside the broker's minimum distance are rejected at the
   //--- server with error 130 and look like a broken EA to the user.
   const double stops_level=(double)m_spec.stops_level_points;
   const double sl_points=config.GetDouble(CConfigKeys::SL_FIXED_POINTS,0.0);
   const double tp_points=config.GetDouble(CConfigKeys::TP_FIXED_POINTS,0.0);
   if(stops_level>0.0)
     {
      if(sl_points>0.0 && sl_points<stops_level)
         result.AddError("sl.fixed_points ("+DoubleToString(sl_points,0)+
                         ") is below the broker minimum stop distance ("+
                         DoubleToString(stops_level,0)+" points)");
      if(tp_points>0.0 && tp_points<stops_level)
         result.AddError("tp.fixed_points ("+DoubleToString(tp_points,0)+
                         ") is below the broker minimum stop distance ("+
                         DoubleToString(stops_level,0)+" points)");
      const double be_offset=
         config.GetDouble(CConfigKeys::BREAKEVEN_OFFSET_POINTS,0.0);
      if(config.GetBool(CConfigKeys::BREAKEVEN_ENABLED,false) &&
         be_offset>0.0 && be_offset<stops_level)
         result.AddWarning("breakeven.offset_points is below the broker stop "
                           "level; the break-even move may be rejected");
     }

   //--- Volume bounds.
   const double fixed_lot=config.GetDouble(CConfigKeys::RISK_FIXED_LOT,0.0);
   if(fixed_lot>0.0)
     {
      if(m_spec.volume_min>0.0 && fixed_lot<m_spec.volume_min)
         result.AddError("risk.fixed_lot is below the broker minimum volume "
                         "of "+DoubleToString(m_spec.volume_min,2));
      if(m_spec.volume_max>0.0 && fixed_lot>m_spec.volume_max)
         result.AddError("risk.fixed_lot exceeds the broker maximum volume "
                         "of "+DoubleToString(m_spec.volume_max,2));
      //--- A lot that is not a multiple of the step is silently rounded
      //--- by the server, so the sized risk is not the risk taken.
      if(m_spec.volume_step>0.0)
        {
         const double steps=fixed_lot/m_spec.volume_step;
         if(MathAbs(steps-MathRound(steps))>0.0001)
            result.AddWarning("risk.fixed_lot is not a multiple of the broker "
                              "volume step and will be rounded on send");
        }
     }

   const double max_lot=config.GetDouble(CConfigKeys::RISK_MAX_LOT,0.0);
   if(max_lot>0.0 && m_spec.volume_max>0.0 && max_lot>m_spec.volume_max)
      result.AddWarning("risk.max_lot exceeds the broker maximum volume; the "
                        "broker limit will bind first");

   //--- Scale-out must be able to leave a legal remainder.
   if(config.GetBool(CConfigKeys::TM_SCALE_OUT_ENABLED,false) &&
      fixed_lot>0.0 && m_spec.volume_min>0.0)
     {
      const double fraction=
         config.GetDouble(CConfigKeys::TM_SCALE_OUT_FRACTION,0.5);
      if(fixed_lot*(1.0-fraction)<m_spec.volume_min)
         result.AddError("a scale-out of "+DoubleToString(fraction*100.0,0)+
                         "% would leave less than the broker minimum volume, "
                         "so the partial close will be rejected");
     }
  }

#endif // SRP_CONFIGURATION_CCONFIGVALIDATOR_MQH
//+------------------------------------------------------------------+
