//+------------------------------------------------------------------+
//|                                        Phase2CompileCheck.mq5 |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   FULL PHASE 2 VERIFICATION HARNESS - not part of the product.        |
//|   Instantiates every class across all four subsystems and touches the |
//|   entire public API so the compiler verifies signatures for real.     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Intelligence/Indicators/CStandardIndicators.mqh>
#include <ScalpRobotPro/Intelligence/Indicators/CComputedIndicators.mqh>
#include <ScalpRobotPro/Intelligence/Structure/CSwingDetector.mqh>
#include <ScalpRobotPro/Intelligence/Structure/CMarketStructure.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CZoneRegistry.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CDisplacementDetector.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CBlockDetector.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CLiquidityDetector.mqh>
#include <ScalpRobotPro/Intelligence/Risk/CRiskEngine.mqh>
#include <ScalpRobotPro/Intelligence/Risk/CRiskStateStore.mqh>
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
   const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   const datetime now=TimeCurrent();
   SValidationResult validation;

   //=== INDICATOR ENGINE (all 14) ===================================
   CEmaIndicator    *ema   = new CEmaIndicator(sym,tf,21,logger);
   CSmaIndicator    *sma   = new CSmaIndicator(sym,tf,50,logger);
   CAtrIntel        *atr   = new CAtrIntel(sym,tf,14,logger);
   CRsiIntel        *rsi   = new CRsiIntel(sym,tf,14,logger);
   CAdxIntel        *adx   = new CAdxIntel(sym,tf,14,logger);
   CMacdIntel       *macd  = new CMacdIntel(sym,tf,12,26,9,logger);
   CBollingerIntel  *bb    = new CBollingerIntel(sym,tf,20,2.0,logger);
   CCciIntel        *cci   = new CCciIntel(sym,tf,14,logger);
   CStochasticIntel *stoch = new CStochasticIntel(sym,tf,5,3,3,logger);
   CIchimokuIntel   *ichi  = new CIchimokuIntel(sym,tf,9,26,52,logger);
   CObvIntel        *obv   = new CObvIntel(sym,tf,logger);
   CMfiIntel        *mfi   = new CMfiIntel(sym,tf,14,logger);
   CVwapIndicator   *vwap  = new CVwapIndicator(sym,tf,logger,0);
   CVolumeIndicator *vol   = new CVolumeIndicator(sym,tf,logger);

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
   vwap.Initialize(); vwap.Refresh(); vwap.Validate(validation);
   vol.Initialize();  vol.Refresh();  vol.Validate(validation);
   Print("indicators ready: ",ema.Describe());

   //=== MARKET STRUCTURE ============================================
   CSwingDetector *swings=new CSwingDetector(sym,tf,logger,3,300,64);
   swings.Initialize(); swings.Refresh(); swings.Validate(validation);

   CMarketStructure *structure=new CMarketStructure(sym,tf,swings,logger);
   structure.Initialize();
   structure.Refresh(price);
   structure.Validate(validation);
   Print(structure.Describe());

   //=== SMART MONEY CONCEPTS ========================================
   CZoneRegistry *registry=new CZoneRegistry(logger,64);
   CDisplacementDetector *disp=new CDisplacementDetector(sym,tf,atr,logger);
   disp.Validate(validation);

   CBlockDetector *blocks=new CBlockDetector(sym,tf,disp,registry,logger);
   blocks.SetVolumeIndicator(vol);
   blocks.Validate(validation);
   blocks.Scan(true);

   CLiquidityDetector *liquidity=
      new CLiquidityDetector(sym,tf,swings,atr,registry,logger);
   liquidity.Validate(validation);
   liquidity.Scan(true);
   Print(blocks.Describe()," | ",liquidity.Describe());
   Print(registry.Describe());

   //=== RISK MANAGEMENT =============================================
   CRiskStateStore *store=new CRiskStateStore("srp_phase2_state.txt",logger);
   store.Initialize();
   store.Validate(validation);

   //--- Exercise EVERY sizing model so all six compile.
   CFixedLotModel      *m1=new CFixedLotModel(0.10,logger);
   CRiskPercentModel   *m2=new CRiskPercentModel(1.0,SRP_CAPITAL_EQUITY,logger);
   CAutoLotModel       *m3=new CAutoLotModel(1000.0,0.01,logger);
   CKellyModel         *m4=new CKellyModel(logger,30,0.25,2.0);
   CAtrSizingModel     *m5=new CAtrSizingModel(1.0,2.0,logger);
   CDynamicSizingModel *m6=new CDynamicSizingModel(1.0,logger);

   m1.SetLot(0.10);
   m2.SetPercent(1.0); m2.SetBase(SRP_CAPITAL_HIGH_WATER_MARK);
   m3.SetRatio(1000.0,0.01); m3.SetBase(SRP_CAPITAL_BALANCE);
   m4.SetMinTrades(30); m4.SetKellyFraction(0.25); m4.SetMaxRiskPercent(2.0);
   m5.SetRiskPercent(1.0); m5.SetAtrMultiple(2.0);
   m6.SetBounds(0.1,2.0);
   m6.SetLossReduction(2,0.5);
   m6.SetDrawdownReduction(5.0,0.5);
   m6.SetScaleUpOnWins(false,1.2);

   //--- Direct calculation through each model.
   SSizingContext context;
   context.balance=equity; context.equity=equity;
   context.peak_equity=equity;
   context.point=SymbolInfoDouble(sym,SYMBOL_POINT);
   context.tick_size=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   context.tick_value=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   context.stop_distance_points=500.0;
   context.atr_value=0.5;
   context.total_trades=50; context.winning_trades=30;
   context.gross_profit=3000.0; context.gross_loss=-1500.0;
   string why="";
   Print("fixed=",   DoubleToString(m1.Calculate(context,why),4)," ",why);
   Print("percent=", DoubleToString(m2.Calculate(context,why),4)," ",why);
   Print("autolot=", DoubleToString(m3.Calculate(context,why),4)," ",why);
   Print("kelly=",   DoubleToString(m4.Calculate(context,why),4)," ",why);
   Print("atr=",     DoubleToString(m5.Calculate(context,why),4)," ",why);
   Print("dynamic=", DoubleToString(m6.Calculate(context,why),4)," ",why);
   Print("moneyPerLot=",DoubleToString(context.MoneyPerLotAtStop(),2));

   //--- Models 1..5 are exercised above then released; the engine takes
   //--- ownership of exactly one, so the rest must not leak.
   delete m1; delete m3; delete m4; delete m5; delete m6;

   //=== LIMIT GUARD =================================================
   CRiskLimitGuard *guard=new CRiskLimitGuard(logger,store);
   guard.SetDailyLossLimit(5.0,true);
   guard.SetWeeklyLossLimit(10.0);
   guard.SetMonthlyLossLimit(20.0);
   guard.SetMaxDrawdown(20.0,true);
   guard.SetMaxExposure(10.0,5.0);
   guard.SetEmergencyShutdown(true,equity*0.5);

   //=== PROTECTION ==================================================
   CProtectionManager *protection=new CProtectionManager(sym,atr,logger);
   protection.SetSwingDetector(swings);
   protection.ConfigureStop(SRP_STOP_ATR_MULTIPLE,500.0,2.0);
   protection.SetStopBounds(100.0,5000.0);
   protection.SetStructureBuffer(50.0);
   protection.ConfigureTarget(SRP_TARGET_RISK_REWARD,1000.0,3.0,1.5);
   protection.ConfigureBreakEven(true,300.0,50.0);
   protection.ConfigureTrailing(true,400.0,300.0,50.0);
   protection.ConfigureProfitLock(true,600.0,0.5);
   Print(protection.Describe());

   //=== RISK ENGINE =================================================
   CRiskEngine *risk=new CRiskEngine(sym,atr,logger);
   risk.SetSizer(m2);                      // engine now OWNS m2
   risk.SetLimitGuard(guard);              // engine now OWNS guard
   risk.SetProtectionManager(protection);  // engine now OWNS protection
   risk.SetSwingDetector(swings);
   risk.SetMaxRiskPercentPerTrade(2.0);
   risk.SetMaxVolume(5.0);
   risk.Initialize(equity,now);
   risk.Validate(validation);
   risk.UpdateAccountState(equity,0.0,now);

   SSizingResult sizing;
   SProtectionPlan plan;
   SRiskVerdict verdict;
   const bool approved=risk.EvaluateEntry(true,price,0.0,0.0,sizing,plan,verdict);
   Print("entry approved=",approved,
         " volume=",DoubleToString(sizing.volume,2),
         " risk=",DoubleToString(sizing.risk_percent,2),"%",
         " reason=",sizing.rejection_reason);
   Print("plan: stop=",DoubleToString(plan.stop_price,5),
         " target=",DoubleToString(plan.target_price,5),
         " RR=",DoubleToString(plan.reward_risk_ratio,2),
         " | ",plan.explanation);
   Print("verdict allowed=",verdict.entries_allowed,
         " flatten=",verdict.flatten_required,
         " breach=",EnumToString(verdict.breach));

   //--- In-trade stop management across all three mechanisms.
   SStopAdjustment adjustment;
   risk.EvaluateStopAdjustment(true,price,price*1.01,price*1.02,0.0,adjustment);
   Print("adjust=",adjustment.adjust,
         " stage=",EnumToString(adjustment.stage)," ",adjustment.reason);

   CProtectionManager *prot=risk.Protection();
   prot.EvaluateBreakEven(true,price,price*1.01,0.0,adjustment);
   prot.EvaluateTrailing(true,price,price*1.01,0.0,adjustment);
   prot.EvaluateProfitLock(true,price,price*1.02,0.0,adjustment);
   double distance=0.0;
   prot.ResolveDynamicStopPoints(distance,why);
   prot.ResolveStopDistance(true,price,distance,why);
   double level=0.0;
   prot.ResolveStopPrice(true,price,level,why);
   prot.ResolveTargetPrice(true,price,500.0,level,why);

   //--- Ledger and limit surface.
   CRiskLimitGuard *g=risk.Guard();
   risk.RecordClosedTrade(-50.0,now);
   SRiskLedger ledger;
   g.GetLedger(ledger);
   Print("ledger: day=",DoubleToString(ledger.DayTotal(),2),
         " week=",DoubleToString(ledger.WeekTotal(),2),
         " month=",DoubleToString(ledger.MonthTotal(),2),
         " losses=",ledger.consecutive_losses);
   Print("daily=",DoubleToString(g.DailyLossPercent(),2),"%",
         " weekly=",DoubleToString(g.WeeklyLossPercent(),2),"%",
         " monthly=",DoubleToString(g.MonthlyLossPercent(),2),"%",
         " dd=",DoubleToString(g.DrawdownPercent(),2),"%",
         " budget=",DoubleToString(g.RemainingDailyBudget(),2));
   Print("tripped=",g.IsAnyTripped()," breaches=",g.BreachCount());
   Print(g.Describe());

   //--- Emergency path.
   risk.TriggerEmergencyShutdown("harness test",now);
   Print("emergencyActive=",risk.IsEmergencyActive());
   risk.ClearEmergencyShutdown("operator acknowledged in harness");
   Print("emergencyCleared=",!risk.IsEmergencyActive());

   Print(risk.Describe());
   Print("validation errors=",validation.error_count,
         " warnings=",validation.warning_count);
   Print("=== PHASE 2 FULL CHECK COMPLETE ===");

   //=== TEARDOWN (reverse of construction) ==========================
   risk.Shutdown();
   delete risk;              // deletes m2, guard, protection
   delete store;
   delete liquidity;
   delete blocks;
   delete disp;
   delete registry;
   structure.Shutdown(); delete structure;
   swings.Shutdown();    delete swings;
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
