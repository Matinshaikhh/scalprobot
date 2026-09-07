//+------------------------------------------------------------------+
//|                                          P3StrategyCheck.mq5 |
//|   Phase 3 harness: all ten strategy plugins.                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Decision/Strategies/CTrendStrategies.mqh>
#include <ScalpRobotPro/Decision/Strategies/CSmcStrategies.mqh>
//--- CBlockDetector is used to populate the zone registry in this
//--- harness; the strategies themselves only read the registry.
#include <ScalpRobotPro/Intelligence/SmartMoney/CBlockDetector.mqh>
#include <ScalpRobotPro/Logger/CLogger.mqh>
#include <ScalpRobotPro/Logger/CTerminalLogSink.mqh>

void OnStart(void)
  {
   CLogger *logger=new CLogger(SRP_LOG_DEBUG);
   logger.AddSink(new CTerminalLogSink(SRP_LOG_DEBUG));
   logger.Open();

   const string sym=_Symbol;
   const ENUM_TIMEFRAMES tf=PERIOD_M1;
   SValidationResult validation;

   //=== Phase 2 modules the strategies read ==========================
   CEmaIndicator *ema_fast=new CEmaIndicator(sym,tf,8,logger);
   CEmaIndicator *ema_slow=new CEmaIndicator(sym,tf,21,logger);
   CEmaIndicator *ema_trend=new CEmaIndicator(sym,tf,100,logger);
   CAtrIntel *atr=new CAtrIntel(sym,tf,14,logger);
   CRsiIntel *rsi=new CRsiIntel(sym,tf,14,logger);
   CAdxIntel *adx=new CAdxIntel(sym,tf,14,logger);
   CMacdIntel *macd=new CMacdIntel(sym,tf,12,26,9,logger);
   CBollingerIntel *bb=new CBollingerIntel(sym,tf,20,2.0,logger);
   CVwapIndicator *vwap=new CVwapIndicator(sym,tf,logger,0);
   CVolumeIndicator *vol=new CVolumeIndicator(sym,tf,logger);

   ema_fast.Initialize();  ema_fast.Refresh();
   ema_slow.Initialize();  ema_slow.Refresh();
   ema_trend.Initialize(); ema_trend.Refresh();
   atr.Initialize();  atr.Refresh();
   rsi.Initialize();  rsi.Refresh();
   adx.Initialize();  adx.Refresh();
   macd.Initialize(); macd.Refresh();
   bb.Initialize();   bb.Refresh();
   vwap.Initialize(); vwap.Refresh();
   vol.Initialize();  vol.Refresh();

   CSwingDetector *swings=new CSwingDetector(sym,tf,logger,3,300,64);
   swings.Initialize(); swings.Refresh();
   CMarketStructure *structure=new CMarketStructure(sym,tf,swings,logger);
   structure.Initialize();
   structure.Refresh(SymbolInfoDouble(sym,SYMBOL_BID));

   CZoneRegistry *zones=new CZoneRegistry(logger,64);
   CDisplacementDetector *disp=new CDisplacementDetector(sym,tf,atr,logger);
   CBlockDetector *blocks=new CBlockDetector(sym,tf,disp,zones,logger);
   blocks.SetVolumeIndicator(vol);
   blocks.Scan(true);
   CLiquidityDetector *liquidity=
      new CLiquidityDetector(sym,tf,swings,atr,zones,logger);
   liquidity.Scan(true);

   //=== Context ======================================================
   CStrategyContext *context=new CStrategyContext();
   context.SetEmaSet(ema_fast,ema_slow,ema_trend);
   context.SetAtr(atr);
   context.SetRsi(rsi);
   context.SetAdx(adx);
   context.SetMacd(macd);
   context.SetBollinger(bb);
   context.SetVwap(vwap);
   context.SetVolume(vol);
   context.SetSwings(swings);
   context.SetStructure(structure);
   context.SetZones(zones);
   context.SetDisplacement(disp);
   context.SetLiquidity(liquidity);
   context.Validate(validation);
   Print(context.Describe());

   //--- Null-safe readers.
   double v1=0.0,v2=0.0,v3=0.0;
   context.AtrValue(v1);
   context.AtrPoints(SymbolInfoDouble(sym,SYMBOL_POINT),v1);
   context.RsiValue(v1);
   context.AdxValue(v1);
   context.AdxDi(v1,v2);
   context.MacdHistogram(v1);
   context.VwapValue(v1);
   context.RelativeVolume(20,v1);
   context.EmaValues(v1,v2);
   context.EmaTrendValue(v1);
   context.BollingerBands(v1,v2,v3);

   //=== Build the decision snapshot ====================================
   SDecisionInput snapshot;
   snapshot.symbol=sym;
   snapshot.timeframe=tf;
   snapshot.server_time=TimeCurrent();
   snapshot.bid=SymbolInfoDouble(sym,SYMBOL_BID);
   snapshot.ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   snapshot.mid=(snapshot.bid+snapshot.ask)*0.5;
   snapshot.point=SymbolInfoDouble(sym,SYMBOL_POINT);
   snapshot.digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   snapshot.spread_points=(snapshot.point>0.0 ? (snapshot.ask-snapshot.bid)/snapshot.point : 0.0);
   snapshot.is_new_bar=true;
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(sym,tf,0,2,rates)==2)
     {
      snapshot.bar_time=rates[0].time;
      snapshot.open=rates[0].open;  snapshot.high=rates[0].high;
      snapshot.low=rates[0].low;    snapshot.close=rates[0].close;
      snapshot.prev_open=rates[1].open; snapshot.prev_high=rates[1].high;
      snapshot.prev_low=rates[1].low;   snapshot.prev_close=rates[1].close;
     }
   structure.GetState(snapshot.structure);
   snapshot.structure_valid=structure.IsValid();
   //--- Permit trading so plugin logic is actually reached.
   snapshot.session.trading_permitted=true;
   snapshot.session.active_session=SRP_TS_LONDON;
   snapshot.session.liquidity_score=0.8;
   snapshot.session.minutes_into_session=45;
   snapshot.news.trading_permitted=true;
   snapshot.is_valid=true;

   //=== All ten plugins =============================================
   CStrategyPlugin *plugins[];
   ArrayResize(plugins,10);
   CEmaCrossStrategy *p0=new CEmaCrossStrategy(context,logger);
   p0.SetRequireTrendAgreement(true); p0.SetMinSeparation(0.10);
   CVwapPullbackStrategy *p1=new CVwapPullbackStrategy(context,logger);
   p1.SetTouchTolerance(0.2); p1.SetMaxDistance(0.6);
   p1.SetRequireTrendAgreement(false); p1.SetUseBands(true);
   CLiquiditySweepStrategy *p2=new CLiquiditySweepStrategy(context,logger);
   p2.SetMaxBarsSinceSweep(3); p2.SetMinSweepStrength(0.35);
   p2.SetRequireStructureAgreement(false);
   COrderBlockStrategy *p3=new COrderBlockStrategy(context,logger);
   p3.SetMinZoneStrength(0.4); p3.SetRequireMidpoint(false);
   p3.SetRequireRangeAgreement(true); p3.SetMaxTouches(2);
   CFairValueGapStrategy *p4=new CFairValueGapStrategy(context,logger);
   p4.SetMinZoneStrength(0.35); p4.SetMinGapAtr(0.15); p4.SetRequireFresh(true);
   CMomentumScalpPlugin *p5=new CMomentumScalpPlugin(context,logger);
   p5.SetRsiThresholds(55.0,45.0); p5.SetRequireMacd(true);
   p5.SetMinVolumeRatio(1.0);
   COpeningRangeBreakout *p6=new COpeningRangeBreakout(context,logger);
   p6.SetRangeMinutes(30); p6.SetValidForMinutes(180);
   p6.SetMarginAtr(0.15); p6.SetMinRangeAtr(0.5);
   CTrendContinuationStrategy *p7=new CTrendContinuationStrategy(context,logger);
   p7.SetMinAdx(22.0); p7.SetMinStructureScore(0.45); p7.SetRequirePullback(true);
   CMeanReversionPlugin *p8=new CMeanReversionPlugin(context,logger);
   p8.SetRsiThresholds(30.0,70.0); p8.SetMaxAdx(30.0);
   p8.SetMinBandWidth(1.0); p8.SetRequireRsi(true);
   CBreakoutStrategyPlugin *p9=new CBreakoutStrategyPlugin(context,logger);
   p9.SetMarginAtr(0.25); p9.SetMinVolumeRatio(1.2);
   p9.SetRequireDisplacement(false);

   plugins[0]=p0; plugins[1]=p1; plugins[2]=p2; plugins[3]=p3; plugins[4]=p4;
   plugins[5]=p5; plugins[6]=p6; plugins[7]=p7; plugins[8]=p8; plugins[9]=p9;

   //--- Exercise the full contract on every plugin.
   for(int i=0;i<10;i++)
     {
      plugins[i].SetEnabled(true);
      plugins[i].SetWeight(1.0);
      plugins[i].SetMinConfidence(0.5);
      plugins[i].SetRequireNewBar(true);
      plugins[i].Validate(validation);

      SStrategySignal sig;
      const bool fired=plugins[i].Evaluate(snapshot,sig);
      Print(StringFormat("%-22s %-8s conf=%.2f risk=%-7s | %s",
            plugins[i].Name(),
            CStrategyPlugin::DecisionToString(sig.decision),
            sig.confidence,
            CStrategyPlugin::RatingToString(sig.risk_rating),
            (StringLen(sig.reason)>0 ? sig.reason : "(no setup)")));
      if(fired)
         Print("   -> stop=",DoubleToString(sig.suggested_stop,snapshot.digits),
               " target=",DoubleToString(sig.suggested_target,snapshot.digits));
     }

   //--- Opening range accessor.
   double rh=0.0,rl=0.0; bool built=false;
   p6.GetRange(rh,rl,built);
   Print("openingRange built=",built," high=",DoubleToString(rh,snapshot.digits),
         " low=",DoubleToString(rl,snapshot.digits));

   for(int i=0;i<10;i++)
      Print(plugins[i].Describe());

   Print("validation errors=",validation.error_count,
         " warnings=",validation.warning_count);
   Print("=== P3 STRATEGY CHECK COMPLETE ===");

   for(int i=9;i>=0;i--)
      delete plugins[i];
   delete context;
   delete liquidity; delete blocks; delete disp; delete zones;
   structure.Shutdown(); delete structure;
   swings.Shutdown();    delete swings;
   vol.Shutdown();  delete vol;
   vwap.Shutdown(); delete vwap;
   bb.Shutdown();   delete bb;
   macd.Shutdown(); delete macd;
   adx.Shutdown();  delete adx;
   rsi.Shutdown();  delete rsi;
   atr.Shutdown();  delete atr;
   ema_trend.Shutdown(); delete ema_trend;
   ema_slow.Shutdown();  delete ema_slow;
   ema_fast.Shutdown();  delete ema_fast;
   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
