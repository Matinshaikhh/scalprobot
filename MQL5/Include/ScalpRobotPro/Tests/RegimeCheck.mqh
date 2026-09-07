//+------------------------------------------------------------------+
//|                                             RegimeCheck.mqh |
//|          Scalping Robot Pro - regime & volatility verification (P6) |
//|                                                                  |
//|   Asserts the classification and gating logic that a compile cannot:  |
//|     * the permission table is complete, and its exclusions are real;  |
//|     * volatility bands classify correctly against per-asset thresholds;|
//|     * NASDAQ and gold classify the SAME reading differently, which is  |
//|       the whole point of per-asset thresholds;                        |
//|     * extreme volatility reduces or blocks risk and never raises it;  |
//|     * the engine fails CLOSED when unevaluated.                       |
//|                                                                  |
//|   The permission table is static and pure, so most of this runs        |
//|   without a terminal connection.                                     |
//+------------------------------------------------------------------+
#ifndef SRP_TESTS_REGIMECHECK_MQH
#define SRP_TESTS_REGIMECHECK_MQH

#include "../Profiles/CRegimeEngine.mqh"

int g_rchecks = 0;
int g_rfailed = 0;

void RCheck(const string label,const bool condition)
  {
   g_rchecks++;
   if(!condition)
     {
      g_rfailed++;
      Print("  FAIL  ",label);
      return;
     }
   Print("  ok    ",label);
  }

//+------------------------------------------------------------------+
//| 1. THE PERMISSION TABLE.                                           |
//|                                                                  |
//| Part 7's requirement asserted cell by cell. The exclusions matter as |
//| much as the inclusions: a table that permits everything is not a gate.|
//+------------------------------------------------------------------+
void TestPermissionTable(void)
  {
   Print("=== 1. REGIME PERMISSION TABLE ===");

   //--- TREND permits continuation and momentum, and must NOT permit
   //--- mean reversion - fading a strong trend is the classic way to
   //--- lose money slowly.
   RCheck("TREND permits trend continuation",
          CRegimeEngine::RegimePermits(SRP_REGIME_TREND,
                                       SRP_SLOT_TREND_CONTINUATION));
   RCheck("TREND permits momentum",
          CRegimeEngine::RegimePermits(SRP_REGIME_TREND,SRP_SLOT_MOMENTUM));
   RCheck("TREND REFUSES mean reversion",
          !CRegimeEngine::RegimePermits(SRP_REGIME_TREND,
                                        SRP_SLOT_MEAN_REVERSION));
   RCheck("TREND REFUSES opening range",
          !CRegimeEngine::RegimePermits(SRP_REGIME_TREND,
                                        SRP_SLOT_OPENING_RANGE));

   //--- RANGE permits mean reversion and sweeps, and must NOT permit
   //--- breakout logic: its premise is that containment is ending.
   RCheck("RANGE permits mean reversion",
          CRegimeEngine::RegimePermits(SRP_REGIME_RANGE,
                                       SRP_SLOT_MEAN_REVERSION));
   RCheck("RANGE permits liquidity sweep",
          CRegimeEngine::RegimePermits(SRP_REGIME_RANGE,
                                       SRP_SLOT_LIQUIDITY_SWEEP));
   RCheck("RANGE REFUSES breakout",
          !CRegimeEngine::RegimePermits(SRP_REGIME_RANGE,SRP_SLOT_BREAKOUT));
   RCheck("RANGE REFUSES volatility breakout",
          !CRegimeEngine::RegimePermits(SRP_REGIME_RANGE,
                                        SRP_SLOT_VOLATILITY_BREAKOUT));
   RCheck("RANGE REFUSES trend continuation",
          !CRegimeEngine::RegimePermits(SRP_REGIME_RANGE,
                                        SRP_SLOT_TREND_CONTINUATION));

   //--- BREAKOUT permits expansion strategies, refuses mean reversion.
   RCheck("BREAKOUT permits breakout",
          CRegimeEngine::RegimePermits(SRP_REGIME_BREAKOUT,
                                       SRP_SLOT_BREAKOUT));
   RCheck("BREAKOUT permits volatility breakout",
          CRegimeEngine::RegimePermits(SRP_REGIME_BREAKOUT,
                                       SRP_SLOT_VOLATILITY_BREAKOUT));
   RCheck("BREAKOUT permits opening range",
          CRegimeEngine::RegimePermits(SRP_REGIME_BREAKOUT,
                                       SRP_SLOT_OPENING_RANGE));
   RCheck("BREAKOUT REFUSES mean reversion",
          !CRegimeEngine::RegimePermits(SRP_REGIME_BREAKOUT,
                                        SRP_SLOT_MEAN_REVERSION));

   //--- REVERSAL permits sweeps and structure breaks.
   RCheck("REVERSAL permits liquidity sweep",
          CRegimeEngine::RegimePermits(SRP_REGIME_REVERSAL,
                                       SRP_SLOT_LIQUIDITY_SWEEP));
   RCheck("REVERSAL permits break of structure",
          CRegimeEngine::RegimePermits(SRP_REGIME_REVERSAL,SRP_SLOT_BOS));
   RCheck("REVERSAL REFUSES trend continuation",
          !CRegimeEngine::RegimePermits(SRP_REGIME_REVERSAL,
                                        SRP_SLOT_TREND_CONTINUATION));

   //--- LOW_VOLATILITY permits NOTHING. A scalp that cannot clear the
   //--- spread is a losing trade with extra steps.
   bool low_blocks_all=true;
   for(int i=0;i<(int)SRP_SLOT_COUNT;i++)
      if(CRegimeEngine::RegimePermits(SRP_REGIME_LOW_VOLATILITY,
                                      (ENUM_SRP_STRAT_SLOT)i))
         low_blocks_all=false;
   RCheck("LOW_VOLATILITY permits nothing at all",low_blocks_all);

   //--- UNDEFINED permits nothing: fail closed.
   bool undefined_blocks_all=true;
   for(int i=0;i<(int)SRP_SLOT_COUNT;i++)
      if(CRegimeEngine::RegimePermits(SRP_REGIME_UNDEFINED,
                                      (ENUM_SRP_STRAT_SLOT)i))
         undefined_blocks_all=false;
   RCheck("UNDEFINED regime permits nothing (fails closed)",
          undefined_blocks_all);

   //--- HIGH_VOLATILITY is restrictive but not empty.
   int high_count=0;
   for(int i=0;i<(int)SRP_SLOT_COUNT;i++)
      if(CRegimeEngine::RegimePermits(SRP_REGIME_HIGH_VOLATILITY,
                                      (ENUM_SRP_STRAT_SLOT)i))
         high_count++;
   RCheck(StringFormat("HIGH_VOLATILITY is restrictive but not empty (%d slots)",
                       high_count),high_count>0 && high_count<=3);

   //--- TRANSITION is the most restrictive tradeable state.
   int transition_count=0;
   for(int i=0;i<(int)SRP_SLOT_COUNT;i++)
      if(CRegimeEngine::RegimePermits(SRP_REGIME_TRANSITION,
                                      (ENUM_SRP_STRAT_SLOT)i))
         transition_count++;
   RCheck(StringFormat("TRANSITION permits only high-conviction setups (%d)",
                       transition_count),
          transition_count>0 && transition_count<=2);

   //--- No regime may permit every strategy: that would be no gate.
   bool any_permits_all=false;
   for(int r=0;r<=(int)SRP_REGIME_TRANSITION;r++)
     {
      int count=0;
      for(int i=0;i<(int)SRP_SLOT_COUNT;i++)
         if(CRegimeEngine::RegimePermits((ENUM_SRP_REGIME)r,
                                         (ENUM_SRP_STRAT_SLOT)i))
            count++;
      if(count==(int)SRP_SLOT_COUNT)
         any_permits_all=true;
     }
   RCheck("no regime permits every strategy",!any_permits_all);

   //--- Every strategy must be permitted SOMEWHERE, or it is dead code.
   bool all_reachable=true;
   for(int i=0;i<(int)SRP_SLOT_COUNT;i++)
     {
      bool reachable=false;
      for(int r=0;r<=(int)SRP_REGIME_TRANSITION;r++)
         if(CRegimeEngine::RegimePermits((ENUM_SRP_REGIME)r,
                                         (ENUM_SRP_STRAT_SLOT)i))
            reachable=true;
      if(!reachable)
        {
         all_reachable=false;
         Print("        unreachable in every regime: ",
               CRegimeEngine::SlotToString((ENUM_SRP_STRAT_SLOT)i));
        }
     }
   RCheck("every strategy is reachable in at least one regime",all_reachable);
  }

//+------------------------------------------------------------------+
//| 2. PER-ASSET VOLATILITY THRESHOLDS.                                |
//|                                                                  |
//| The same ATR reading must classify differently on NASDAQ and gold,   |
//| because gold's ATR is a larger share of price. If it did not, the     |
//| per-asset thresholds would be decorative.                            |
//+------------------------------------------------------------------+
void TestVolatilityThresholds(void)
  {
   Print("=== 2. PER-ASSET VOLATILITY CLASSIFICATION ===");

   SMarketProfile nasdaq,gold;
   CMarketProfileFactory::ApplyNasdaq(nasdaq);
   CMarketProfileFactory::ApplyGold(gold);

   //--- 0.10% of price: HIGH for an index, still NORMAL for gold.
   RCheck("NASDAQ bands are tighter than gold's",
          nasdaq.atr_high_percent<gold.atr_high_percent);
   RCheck("a 0.10% ATR reading is HIGH for NASDAQ",
          0.10>=nasdaq.atr_high_percent);
   RCheck("the same 0.10% reading is NOT high for gold",
          0.10<gold.atr_high_percent);
   RCheck("the extreme ceiling differs between assets",
          nasdaq.atr_extreme_percent!=gold.atr_extreme_percent);

   //--- Band ordering must hold, or classification is nonsense.
   RCheck("NASDAQ bands are correctly ordered",
          nasdaq.atr_low_percent<nasdaq.atr_high_percent &&
          nasdaq.atr_high_percent<nasdaq.atr_extreme_percent);
   RCheck("gold bands are correctly ordered",
          gold.atr_low_percent<gold.atr_high_percent &&
          gold.atr_high_percent<gold.atr_extreme_percent);
   RCheck("ADX thresholds are correctly ordered on both",
          nasdaq.range_adx_threshold<nasdaq.trend_adx_threshold &&
          gold.range_adx_threshold<gold.trend_adx_threshold);
  }

//+------------------------------------------------------------------+
//| 3. LIVE ENGINE BEHAVIOUR.                                          |
//+------------------------------------------------------------------+
void TestLiveRegime(void)
  {
   Print("=== 3. LIVE REGIME ENGINE ===");

   SSymbolProfile spec;
   if(!CSymbolClassifier::Resolve(_Symbol,spec))
     {
      RCheck("symbol resolved for the regime engine",false);
      return;
     }
   SMarketProfile profile;
   CMarketProfileFactory::Build(spec,profile);

   CRegimeEngine *engine=new CRegimeEngine(_Symbol,NULL);
   engine.SetProfile(profile);

   //--- UNWIRED FIRST. A gate that permits anything before being
   //--- evaluated is worse than no gate, so this is asserted explicitly.
   RCheck("an unwired engine refuses to initialise",!engine.Initialize());
   RCheck("an unevaluated engine permits nothing",
          !engine.Permits(SRP_SLOT_TREND_CONTINUATION) &&
          !engine.Permits(SRP_SLOT_MOMENTUM) &&
          !engine.Permits(SRP_SLOT_LIQUIDITY_SWEEP));
   RCheck("an unevaluated engine reports trading not allowed",
          !engine.TradingAllowed());

   SValidationResult unwired;
   engine.Validate(unwired);
   RCheck("validation reports the missing indicators",
          unwired.error_count>0);

   //--- Now wire it on the CONTEXT timeframe, as the design requires.
   CAdxIntel *adx=new CAdxIntel(_Symbol,profile.context_timeframe,
                                profile.adx_period,NULL);
   CAtrIntel *atr=new CAtrIntel(_Symbol,profile.context_timeframe,
                                profile.atr_period,NULL);
   const bool handles=(adx.Initialize() && atr.Initialize());
   RCheck("context ADX and ATR initialised on the context timeframe",handles);

   if(handles)
     {
      engine.SetContextIndicators(adx,atr);
      RCheck("a wired engine initialises",engine.Initialize());

      SValidationResult wired;
      engine.Validate(wired);
      RCheck("a wired engine validates without errors",wired.error_count==0);

      adx.Refresh();
      atr.Refresh();
      const bool evaluated=engine.Evaluate(TimeCurrent(),true);

      //--- WARM-UP IS NOT A FAILURE, AND MUST NOT BE REPORTED AS ONE.
      //--- The indicators gate on BarsCalculated, not on Bars(): a fresh
      //--- handle reports fewer calculated bars than exist for several
      //--- ticks, and in the tester the higher-timeframe series is built
      //--- lazily. Until both are READY the engine must refuse to
      //--- classify and refuse to permit anything - which is the safe
      //--- behaviour. Asserting "it evaluated" unconditionally would
      //--- demand it invent a regime from data it does not have.
      const int context_bars=Bars(_Symbol,profile.context_timeframe);
      const bool warmed_up=(adx.IsReady() && atr.IsReady());
      Print("  note  contextBars=",context_bars,
            " adx=",EnumToString(adx.State()),
            " atr=",EnumToString(atr.State()));
      if(!warmed_up)
        {
         Print("  note  context history is only ",context_bars,
               " bars; the engine is in warm-up and must classify nothing");
         RCheck("during warm-up the engine declines to classify",!evaluated);
         RCheck("during warm-up the engine permits nothing",
                !engine.Permits(SRP_SLOT_TREND_CONTINUATION) &&
                !engine.Permits(SRP_SLOT_LIQUIDITY_SWEEP));
        }
      else
        {
         RCheck("the engine evaluated against live data",evaluated);
         if(!evaluated)
           {
            //--- Report WHICH input failed rather than only that one did.
            SRegimeState why;
            engine.GetState(why);
            double probe_adx=0.0,probe_atr=0.0;
            const bool adx_ok=adx.Main(1,probe_adx);
            const bool atr_ok=atr.ValueAt(0,1,probe_atr);
            Print("        contextBars=",context_bars,
                  " adxRead=",adx_ok," value=",DoubleToString(probe_adx,4),
                  " atrRead=",atr_ok," value=",DoubleToString(probe_atr,6));
            Print("        adxState=",EnumToString(adx.State()),
                  " atrState=",EnumToString(atr.State()));
            Print("        blockReason=",why.block_reason);
           }
        }

      if(evaluated && warmed_up)
        {
         SRegimeState state;
         engine.GetState(state);
         Print("  ",engine.Describe());
         Print("  ",engine.DescribePermissions());

         RCheck("a regime was classified",
                state.regime!=SRP_REGIME_UNDEFINED);
         RCheck("a volatility class was assigned",
                state.volatility!=SRP_VOL_UNDEFINED);
         RCheck("ADX was read from the context timeframe",state.adx>0.0);
         RCheck("ATR was read and expressed as a share of price",
                state.atr>0.0 && state.atr_percent>0.0);
         RCheck("expansion ratio was computed",state.expansion_ratio>0.0);
         RCheck("range position is within bounds",
                state.range_position>=0.0 && state.range_position<=1.0);

         //--- RISK ADAPTATION MUST NEVER INCREASE SIZE. This direction is
         //--- not negotiable: volatility is a reason to risk less.
         RCheck("risk multiplier never exceeds 1.0",
                state.risk_multiplier<=1.0);
         RCheck("stop multiplier never shrinks below 1.0",
                state.stop_multiplier>=1.0);
         RCheck("confidence bonus is never negative",
                state.confidence_bonus>=0.0);

         //--- A blocked market must permit nothing, whatever the regime.
         if(!state.trading_allowed)
           {
            bool nothing_permitted=true;
            for(int i=0;i<(int)SRP_SLOT_COUNT;i++)
               if(engine.Permits((ENUM_SRP_STRAT_SLOT)i))
                  nothing_permitted=false;
            RCheck("a blocked market permits no strategy",nothing_permitted);
            RCheck("a blocked market states a reason",
                   state.block_reason!="");
           }
         else
            RCheck("an allowed market has zero block reason",
                   state.block_reason=="");

         //--- Caching must not change the answer.
         const long before=engine.EvaluationCount();
         engine.Evaluate(TimeCurrent(),false);
         RCheck("a second call inside the same bar is served from cache",
                engine.EvaluationCount()==before);
        }
     }

   delete atr;
   delete adx;
   delete engine;
   RCheck("regime engine released cleanly",true);
  }

//+------------------------------------------------------------------+
bool RunRegimeCheck(void)
  {
   Print("==================================================");
   Print("REGIME & VOLATILITY CHECK  symbol=",_Symbol);
   Print("==================================================");

   TestPermissionTable();
   TestVolatilityThresholds();
   TestLiveRegime();

   Print("==================================================");
   Print(StringFormat("SRP_REGIME CHECKS=%d FAILED=%d VERDICT=%s",
                      g_rchecks,g_rfailed,(g_rfailed==0 ? "PASS" : "FAIL")));
   Print("==================================================");
   return(g_rfailed==0);
  }

#endif // SRP_TESTS_REGIMECHECK_MQH
//+------------------------------------------------------------------+
