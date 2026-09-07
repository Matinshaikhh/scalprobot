//+------------------------------------------------------------------+
//|                                         IntelCompileCheck.mq5 |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   VERIFICATION HARNESS - not part of the shipped product.            |
//|   Instantiates every Phase 2 class and touches the full API surface   |
//|   so the compiler checks signatures and types for real.              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Intelligence/Indicators/CStandardIndicators.mqh>
#include <ScalpRobotPro/Intelligence/Indicators/CComputedIndicators.mqh>
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
   SValidationResult validation;
   double value=0.0;
   double series[];

   //=== Handle-backed indicators =====================================
   CEmaIndicator *ema=new CEmaIndicator(sym,tf,21,logger);
   CSmaIndicator *sma=new CSmaIndicator(sym,tf,50,logger);
   CAtrIntel *atr=new CAtrIntel(sym,tf,14,logger);
   CRsiIntel *rsi=new CRsiIntel(sym,tf,14,logger);
   CAdxIntel *adx=new CAdxIntel(sym,tf,14,logger);
   CMacdIntel *macd=new CMacdIntel(sym,tf,12,26,9,logger);
   CBollingerIntel *bb=new CBollingerIntel(sym,tf,20,2.0,logger);
   CCciIntel *cci=new CCciIntel(sym,tf,14,logger);
   CStochasticIntel *stoch=new CStochasticIntel(sym,tf,5,3,3,logger);
   CIchimokuIntel *ichi=new CIchimokuIntel(sym,tf,9,26,52,logger);
   CObvIntel *obv=new CObvIntel(sym,tf,logger);
   CMfiIntel *mfi=new CMfiIntel(sym,tf,14,logger);

   //=== Self-computed indicators =====================================
   CVwapIndicator *vwap=new CVwapIndicator(sym,tf,logger,0);
   CVolumeIndicator *vol=new CVolumeIndicator(sym,tf,logger);

   //--- Initialize + refresh + validate the whole set.
   ema.Initialize();  ema.Refresh();  ema.Validate(validation);
   sma.Initialize();  sma.Refresh();  sma.Validate(validation);
   atr.Initialize();  atr.Refresh();  atr.Validate(validation);
   rsi.Initialize();  rsi.Refresh();  rsi.Validate(validation);
   adx.Initialize();  adx.Refresh();  adx.Validate(validation);
   macd.Initialize(); macd.Refresh(); macd.Validate(validation);
   bb.Initialize();   bb.Refresh();   bb.Validate(validation);
   cci.Initialize();  cci.Refresh();  cci.Validate(validation);
   stoch.Initialize();stoch.Refresh();stoch.Validate(validation);
   ichi.Initialize(); ichi.Refresh(); ichi.Validate(validation);
   obv.Initialize();  obv.Refresh();  obv.Validate(validation);
   mfi.Initialize();  mfi.Refresh();  mfi.Validate(validation);
   vwap.SetBandDeviations(2.0);
   vwap.Initialize(); vwap.Refresh(); vwap.Validate(validation);
   vol.Initialize();  vol.Refresh();  vol.Validate(validation);

   Print("validation errors=",validation.error_count,
         " warnings=",validation.warning_count);

   //=== Exercise the generic base API ================================
   Print(ema.Describe());
   Print("emaReady=",ema.IsReady()," warming=",ema.IsWarmingUp(),
         " failed=",ema.HasFailed());
   ema.Value(0,value);
   ema.ValueAt(0,1,value);
   ema.Series(0,0,5,series);
   ema.Slope(0,5,value);
   ema.Highest(0,0,10,value);
   ema.Lowest(0,0,10,value);
   ema.Average(0,0,10,value);
   ema.CrossedAbove(0,value);
   ema.CrossedBelow(0,value);
   Print("emaCacheHit=",DoubleToString(ema.CacheHitRatio(),1),"%");

   SIndicatorReading reading;
   ema.Read(0,0,reading);
   Print("reading valid=",reading.valid," value=",reading.value);

   //=== Semantic accessors ==========================================
   const double price=SymbolInfoDouble(sym,SYMBOL_BID);
   Print("emaAbove=",ema.IsPriceAbove(price),
         " smaAbove=",sma.IsPriceAbove(price));

   atr.Points(0,SymbolInfoDouble(sym,SYMBOL_POINT),value);
   atr.PercentOfPrice(price,0,value);
   atr.ExpansionRatio(20,value);

   Print("rsiOB=",rsi.IsOverbought(70.0)," rsiOS=",rsi.IsOversold(30.0),
         " rsiRising=",rsi.IsRising(3));

   adx.Main(0,value); adx.PlusDi(0,value); adx.MinusDi(0,value);
   adx.StrengthScore(value);
   Print("adxTrending=",adx.IsTrending(25.0)," bullBias=",adx.IsBullishBias());

   macd.Main(0,value); macd.Signal(0,value); macd.Histogram(0,value);
   Print("macdUp=",macd.CrossedUp()," macdDown=",macd.CrossedDown());

   bb.Middle(0,value); bb.Upper(0,value); bb.Lower(0,value);
   bb.WidthPoints(0,SymbolInfoDouble(sym,SYMBOL_POINT),value);
   bb.PercentB(price,0,value);
   Print("bbSqueeze=",bb.IsSqueezing(20,0.8));

   Print("cciOB=",cci.IsOverbought()," cciOS=",cci.IsOversold());

   stoch.Main(0,value); stoch.Signal(0,value);
   Print("stochOB=",stoch.IsOverbought()," crossUp=",stoch.CrossedUp());

   ichi.Tenkan(0,value); ichi.Kijun(0,value);
   ichi.SenkouA(0,value); ichi.SenkouB(0,value); ichi.Chikou(0,value);
   ichi.CloudTop(0,value); ichi.CloudBottom(0,value);
   Print("aboveCloud=",ichi.IsPriceAboveCloud(price),
         " belowCloud=",ichi.IsPriceBelowCloud(price));

   Print("obvRising=",obv.IsRising(5));
   Print("mfiOB=",mfi.IsOverbought()," mfiOS=",mfi.IsOversold());

   //=== VWAP and Volume =============================================
   vwap.Value(0,value); vwap.Upper(0,value); vwap.Lower(0,value);
   vwap.Read(0,reading);
   vwap.DistancePoints(price,SymbolInfoDouble(sym,SYMBOL_POINT),0,value);
   Print("vwapState=",EnumToString(vwap.State()),
         " aboveVwap=",vwap.IsPriceAbove(price),
         " ready=",vwap.IsReady());

   vol.Value(0,value); vol.Average(1,20,value); vol.Highest(0,20,value);
   vol.RelativeVolume(20,value);
   vol.Read(0,reading);
   Print("volState=",EnumToString(vol.State()),
         " relVol=",DoubleToString(value,2),
         " high=",vol.IsHighVolume(20,1.5),
         " low=",vol.IsLowVolume(20,0.5));

   //=== Buffer-level cache API ======================================
   CIndicatorBuffer buffer;
   buffer.Configure(0,64);
   Print("bufferValid=",buffer.IsValid()," filled=",buffer.Filled(),
         " hits=",buffer.HitCount()," copies=",buffer.CopyCount());
   buffer.Invalidate();

   Print("=== PHASE 2 INDICATOR CHECK COMPLETE ===");

   //--- Teardown, reverse of construction.
   vol.Shutdown();   delete vol;
   vwap.Shutdown();  delete vwap;
   mfi.Shutdown();   delete mfi;
   obv.Shutdown();   delete obv;
   ichi.Shutdown();  delete ichi;
   stoch.Shutdown(); delete stoch;
   cci.Shutdown();   delete cci;
   bb.Shutdown();    delete bb;
   macd.Shutdown();  delete macd;
   adx.Shutdown();   delete adx;
   rsi.Shutdown();   delete rsi;
   atr.Shutdown();   delete atr;
   sma.Shutdown();   delete sma;
   ema.Shutdown();   delete ema;

   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
