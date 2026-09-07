//+------------------------------------------------------------------+
//|                                           SmcCompileCheck.mq5 |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|   VERIFICATION HARNESS for Structure + Smart Money Concepts.        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Intelligence/Structure/CSwingDetector.mqh>
#include <ScalpRobotPro/Intelligence/Structure/CMarketStructure.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CZoneRegistry.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CDisplacementDetector.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CBlockDetector.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CLiquidityDetector.mqh>
#include <ScalpRobotPro/Logger/CLogger.mqh>
#include <ScalpRobotPro/Logger/CTerminalLogSink.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   CLogger *logger=new CLogger(SRP_LOG_DEBUG);
   logger.AddSink(new CTerminalLogSink(SRP_LOG_DEBUG));
   logger.Open();

   const string sym=_Symbol;
   const ENUM_TIMEFRAMES tf=PERIOD_M1;
   const double price=SymbolInfoDouble(sym,SYMBOL_BID);
   SValidationResult validation;

   //=== Indicators the SMC layer depends on ==========================
   CAtrIntel *atr=new CAtrIntel(sym,tf,14,logger);
   atr.Initialize(); atr.Refresh();

   CVolumeIndicator *vol=new CVolumeIndicator(sym,tf,logger);
   vol.Initialize(); vol.Refresh();

   //=== Market structure ============================================
   CSwingDetector *swings=new CSwingDetector(sym,tf,logger,3,300,64);
   swings.SetStrength(3);
   swings.SetLookback(300);
   swings.Initialize();
   swings.Refresh();
   swings.Validate(validation);
   Print(swings.Describe());
   Print("swingDetections=",swings.DetectionCount(),
         " strength=",swings.Strength()," valid=",swings.IsValid());

   SSwingPoint swing;
   swings.LastHigh(swing);
   swings.PriorHigh(swing);
   swings.LastLow(swing);
   swings.PriorLow(swing);
   swings.GetHigh(0,swing);
   swings.GetLow(0,swing);
   Print("hh=",swings.ConsecutiveHigherHighs(),
         " ll=",swings.ConsecutiveLowerLows());
   double level=0.0;
   swings.HighestSwing(8,level);
   swings.LowestSwing(8,level);
   swings.MarkHighSwept(0);
   swings.MarkLowSwept(0);

   CMarketStructure *structure=new CMarketStructure(sym,tf,swings,logger);
   structure.SetRangeSwingCount(8);
   structure.SetBreakBuffer(10.0);
   structure.SetEquilibriumBand(0.05);
   structure.SetPullbackMaxBars(20);
   structure.Initialize();
   structure.Refresh(price);
   structure.Validate(validation);
   Print(structure.Describe());

   SStructureState state;
   structure.GetState(state);
   Print("dir=",CMarketStructure::DirectionToString(structure.Direction()),
         " grade=",CMarketStructure::GradeToString(structure.Grade()),
         " phase=",CMarketStructure::PhaseToString(structure.Phase()),
         " event=",CMarketStructure::EventToString(structure.LastEvent()));
   Print("score=",DoubleToString(structure.StrengthScore(),3),
         " bull=",structure.IsBullish()," bear=",structure.IsBearish(),
         " trending=",structure.IsTrending()," ranging=",structure.IsRanging());
   Print("bosBull=",structure.HasBullishBos()," bosBear=",structure.HasBearishBos(),
         " chochBull=",structure.HasBullishChoch(),
         " chochBear=",structure.HasBearishChoch());
   Print("breakout=",structure.IsBreakout()," pullback=",structure.IsPullback(),
         " reversal=",structure.IsReversal(),
         " consolidation=",structure.IsConsolidating());
   SDealingRange range;
   structure.GetRange(range);
   Print("premium=",structure.IsPremium()," discount=",structure.IsDiscount(),
         " rangeValid=",range.valid," height=",DoubleToString(range.Height(),5));
   Print("bos=",structure.BosCount()," choch=",structure.ChochCount());

   //=== Zone registry ===============================================
   CZoneRegistry *registry=new CZoneRegistry(logger,64);
   registry.SetCapacity(64);
   registry.SetMaxAgeBars(500);
   registry.SetMitigationFraction(0.5);

   //=== Displacement ================================================
   CDisplacementDetector *disp=new CDisplacementDetector(sym,tf,atr,logger);
   disp.SetThresholds(1.5,0.6,0.7);
   disp.SetLookback(20);
   disp.Validate(validation);
   SDisplacement displacement;
   disp.TestBar(1,displacement);
   disp.FindRecent(displacement);
   disp.GetLast(displacement);
   Print("displacement detected=",displacement.detected,
         " atrMult=",DoubleToString(displacement.atr_multiple,2),
         " bodyRatio=",DoubleToString(displacement.body_ratio,2),
         " count=",disp.DetectionCount());
   Print("isDispBull=",disp.IsDisplacement(1,SRP_BIAS_BULLISH));

   //=== Blocks and FVGs =============================================
   CBlockDetector *blocks=new CBlockDetector(sym,tf,disp,registry,logger);
   blocks.SetVolumeIndicator(vol);
   blocks.SetScanBars(120);
   blocks.SetMinGapPoints(0.0);
   blocks.SetRequireDisplacement(true);
   blocks.Validate(validation);
   blocks.Scan(true);
   Print(blocks.Describe());

   //=== Liquidity ===================================================
   CLiquidityDetector *liquidity=
      new CLiquidityDetector(sym,tf,swings,atr,registry,logger);
   liquidity.SetEqualTolerance(0.15);
   liquidity.SetMinEqualTouches(2);
   liquidity.SetPoolDepth(0.3);
   liquidity.SetSweepLookback(10);
   liquidity.SetMinPenetration(0.05);
   liquidity.Validate(validation);
   liquidity.Scan(true);
   Print(liquidity.Describe());

   SEqualLevels equal_highs,equal_lows;
   liquidity.GetEqualHighs(equal_highs);
   liquidity.GetEqualLows(equal_lows);
   liquidity.FindEqualHighs(equal_highs);
   liquidity.FindEqualLows(equal_lows);
   liquidity.RegisterLiquidityPools();

   SLiquiditySweep sweep;
   liquidity.DetectSweep(sweep);
   liquidity.GetLastSweep(sweep);
   liquidity.DetectSweepOfLevel(price,SRP_SWEEP_HIGH,sweep);
   Print("sweepKind=",EnumToString(sweep.kind)," reversed=",sweep.reversed,
         " hasRecent=",liquidity.HasRecentSweep());

   double inducement=0.0;
   liquidity.FindInducement(SRP_BIAS_BULLISH,inducement);
   liquidity.FindInducement(SRP_BIAS_BEARISH,inducement);

   //=== Registry queries ============================================
   Print(registry.Describe());
   SPriceZone zone;
   registry.At(0,zone);
   registry.NearestAbove(price,zone);
   registry.NearestBelow(price,zone);
   registry.ZoneContaining(price,zone);
   registry.StrongestOfKind(SRP_ZONE_ORDER_BLOCK,zone);
   registry.NearestOfKind(SRP_ZONE_FAIR_VALUE_GAP,price,SRP_BIAS_BULLISH,zone);
   Print("inZone=",registry.IsPriceInZone(price),
         " actionable=",registry.CountActionable(),
         " obs=",registry.CountByKind(SRP_ZONE_ORDER_BLOCK));
   registry.UpdateStates(price,price,price,0);

   Print("validation errors=",validation.error_count,
         " warnings=",validation.warning_count);
   Print("=== PHASE 2 STRUCTURE + SMC CHECK COMPLETE ===");

   delete liquidity;
   delete blocks;
   delete disp;
   delete registry;
   structure.Shutdown(); delete structure;
   swings.Shutdown();    delete swings;
   vol.Shutdown();       delete vol;
   atr.Shutdown();       delete atr;
   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
