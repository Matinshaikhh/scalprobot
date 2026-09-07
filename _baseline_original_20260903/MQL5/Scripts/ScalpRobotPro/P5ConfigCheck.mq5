//+------------------------------------------------------------------+
//|                                            P5ConfigCheck.mq5 |
//|   Production phase harness: configuration container, builder and    |
//|   validator.                                                       |
//|                                                                  |
//|   The validator is tested by FEEDING IT BAD CONFIGURATIONS and       |
//|   asserting it rejects them. A validator only ever tested against    |
//|   good input is not a validator.                                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Configuration/CConfigurationBuilder.mqh>
#include <ScalpRobotPro/Configuration/CConfigValidator.mqh>
#include <ScalpRobotPro/Logger/CLogger.mqh>
#include <ScalpRobotPro/Logger/CTerminalLogSink.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   CLogger *logger=new CLogger(SRP_LOG_INFO);
   logger.AddSink(new CTerminalLogSink(SRP_LOG_INFO));
   logger.Open();

   //=== HAPPY PATH: the shipped NASDAQ defaults must validate ========
   SInputSnapshot snapshot;
   CConfigurationBuilder::ApplyNasdaqDefaults(snapshot);

   CInputConfiguration *config=new CInputConfiguration(logger);
   CConfigValidator *validator=new CConfigValidator(logger);

   Print("populate=",CConfigurationBuilder::Populate(config,snapshot));
   Print("keys=",config.Count()," sealed=",config.IsSealed());

   //--- Sealing must refuse writes.
   Print("write after seal refused=",
         !config.SetDouble(CConfigKeys::RISK_PERCENT,99.0));
   Print("value unchanged=",
         DoubleToString(config.GetDouble(CConfigKeys::RISK_PERCENT,-1.0),2));

   //--- Broker spec enables the broker-relative rules.
   SSymbolSpec spec;
   spec.symbol=_Symbol;
   spec.digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   spec.point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   spec.volume_min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   spec.volume_max=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   spec.volume_step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   spec.stops_level_points=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   spec.trade_mode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   spec.is_resolved=true;
   validator.SetSymbolSpec(spec);

   SValidationResult good;
   //--- Structural check on the container, then the domain rules.
   config.Validate(good);
   const bool accepted=validator.ValidateAll(config,good);
   Print("=== DEFAULTS: valid=",accepted,
         " errors=",good.error_count,
         " warnings=",good.warning_count);
   if(good.report!="")
      Print(good.report);

   //--- Typed round-trips.
   Print("magic=",config.GetLong(CConfigKeys::GENERAL_MAGIC,0),
         " riskPct=",DoubleToString(config.GetDouble(CConfigKeys::RISK_PERCENT,0),2),
         " atrPeriod=",config.GetInt(CConfigKeys::INDICATOR_ATR_PERIOD,0),
         " smc=",config.GetBool(CConfigKeys::SMC_ENABLED,false),
         " logFolder=",config.GetString(CConfigKeys::LOG_FOLDER,""));
   Print("missing key uses fallback=",
         config.GetInt("no.such.key",4242),
         " misses=",config.MissCount(),
         " firstMissed=",config.FirstMissedKey());
   Print("hasKey(real)=",config.HasKey(CConfigKeys::RISK_MODE),
         " hasKey(fake)=",config.HasKey("no.such.key"));

   //=== NEGATIVE CASES: each must be REJECTED ========================
   //--- Helper pattern: build a fresh snapshot, break exactly one thing,
   //--- and confirm the validator catches it. One defect per case keeps
   //--- the assertion unambiguous.
   string names[];
   ArrayResize(names,0);
   int failures=0;
   int checked=0;

   //--- 1. Zero magic.
   SInputSnapshot bad1; CConfigurationBuilder::ApplyNasdaqDefaults(bad1);
   bad1.magic=0;
   //--- 2. Unsurvivable risk.
   SInputSnapshot bad2; CConfigurationBuilder::ApplyNasdaqDefaults(bad2);
   bad2.risk_percent=25.0;
   //--- 3. No stop loss at all.
   SInputSnapshot bad3; CConfigurationBuilder::ApplyNasdaqDefaults(bad3);
   bad3.sl_mode=SRP_SL_NONE;
   //--- 4. Fast MA above slow MA.
   SInputSnapshot bad4; CConfigurationBuilder::ApplyNasdaqDefaults(bad4);
   bad4.fast_ma_period=50; bad4.slow_ma_period=20;
   //--- 5. Trail step wider than distance.
   SInputSnapshot bad5; CConfigurationBuilder::ApplyNasdaqDefaults(bad5);
   bad5.trail_step_points=400.0; bad5.trail_distance_points=100.0;
   //--- 6. Session filter on, every session off.
   SInputSnapshot bad6; CConfigurationBuilder::ApplyNasdaqDefaults(bad6);
   bad6.allow_london=false; bad6.allow_newyork=false;
   bad6.allow_tokyo=false;  bad6.allow_sydney=false;
   //--- 7. Single-trade risk at or above the daily budget.
   SInputSnapshot bad7; CConfigurationBuilder::ApplyNasdaqDefaults(bad7);
   bad7.risk_percent=3.0; bad7.daily_loss_percent=3.0;
   //--- 8. Weekly limit tighter than daily.
   SInputSnapshot bad8; CConfigurationBuilder::ApplyNasdaqDefaults(bad8);
   bad8.daily_loss_percent=5.0; bad8.weekly_loss_percent=2.0;
   //--- 9. Take profit inside the permitted spread.
   SInputSnapshot bad9; CConfigurationBuilder::ApplyNasdaqDefaults(bad9);
   bad9.tp_mode=SRP_TP_FIXED_POINTS; bad9.tp_fixed_points=40.0;
   bad9.max_spread_points=60.0;
   //--- 10. No strategy enabled.
   SInputSnapshot bad10; CConfigurationBuilder::ApplyNasdaqDefaults(bad10);
   bad10.momentum_enabled=false; bad10.breakout_enabled=false;
   bad10.mean_reversion_enabled=false; bad10.ema_cross_enabled=false;
   bad10.vwap_pullback_enabled=false; bad10.liquidity_sweep_enabled=false;
   bad10.order_block_enabled=false; bad10.fvg_enabled=false;
   bad10.opening_range_enabled=false; bad10.trend_continuation_enabled=false;
   //--- 11. Break-even beyond the take profit.
   SInputSnapshot bad11; CConfigurationBuilder::ApplyNasdaqDefaults(bad11);
   bad11.tp_mode=SRP_TP_FIXED_POINTS; bad11.tp_fixed_points=200.0;
   bad11.breakeven_enabled=true; bad11.breakeven_trigger_points=300.0;
   //--- 12. SMC strategy with the SMC engine disabled.
   SInputSnapshot bad12; CConfigurationBuilder::ApplyNasdaqDefaults(bad12);
   bad12.smc_enabled=false; bad12.order_block_enabled=true;

   for(int c=1;c<=12;c++)
     {
      SInputSnapshot use;
      string label="";
      switch(c)
        {
         case 1:  use=bad1;  label="zero magic";                  break;
         case 2:  use=bad2;  label="risk 25%";                    break;
         case 3:  use=bad3;  label="no stop loss";                break;
         case 4:  use=bad4;  label="fast MA above slow";          break;
         case 5:  use=bad5;  label="trail step > distance";       break;
         case 6:  use=bad6;  label="all sessions disabled";       break;
         case 7:  use=bad7;  label="trade risk >= daily limit";   break;
         case 8:  use=bad8;  label="weekly limit < daily";        break;
         case 9:  use=bad9;  label="TP inside spread";            break;
         case 10: use=bad10; label="no strategy enabled";         break;
         case 11: use=bad11; label="break-even beyond TP";        break;
         case 12: use=bad12; label="SMC strategy, SMC off";       break;
        }

      CInputConfiguration *probe=new CInputConfiguration(logger);
      CConfigValidator *probe_validator=new CConfigValidator(logger);
      probe_validator.SetSymbolSpec(spec);
      CConfigurationBuilder::Populate(probe,use);

      SValidationResult outcome;
      const bool valid=probe_validator.ValidateAll(probe,outcome);
      checked++;
      if(valid)
        {
         failures++;
         Print("  MISSED [",c,"] ",label," -> validator accepted it");
        }
      else
         Print("  caught [",c,"] ",label," -> ",outcome.first_error);

      delete probe_validator;
      delete probe;
     }

   Print("=== NEGATIVE CASES: ",checked-failures,"/",checked," caught, ",
         failures," missed ===");

   //--- The full dump, as written to the log header at startup.
   const string dump=config.Describe();
   Print("describe length=",StringLen(dump)," chars");

   Print("=== P5 CONFIG CHECK COMPLETE ===");

   delete validator;
   delete config;
   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
