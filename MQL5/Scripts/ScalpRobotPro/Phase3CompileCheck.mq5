//+------------------------------------------------------------------+
//|                                        Phase3CompileCheck.mq5 |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   FULL PHASE 3 VERIFICATION HARNESS - not part of the product.        |
//|   Wires the complete decision pipeline end to end: Phase 2 modules ->  |
//|   context -> 10 plugins -> confirmation -> session -> news ->          |
//|   decision engine, and touches the entire public API.                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Decision/CDecisionEngine.mqh>
#include <ScalpRobotPro/Decision/Strategies/CTrendStrategies.mqh>
#include <ScalpRobotPro/Decision/Strategies/CSmcStrategies.mqh>
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
   const datetime now=TimeCurrent();
   SValidationResult validation;

   //=== PHASE 2 MODULES (reused, not rewritten) ======================
   CEmaIndicator *ema_fast=new CEmaIndicator(sym,tf,8,logger);
   CEmaIndicator *ema_slow=new CEmaIndicator(sym,tf,21,logger);
   CEmaIndicator *ema_trend=new CEmaIndicator(sym,tf,100,logger);
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
   CVwapIndicator *vwap=new CVwapIndicator(sym,tf,logger,0);
   CVolumeIndicator *vol=new CVolumeIndicator(sym,tf,logger);

   ema_fast.Initialize();  ema_fast.Refresh();
   ema_slow.Initialize();  ema_slow.Refresh();
   ema_trend.Initialize(); ema_trend.Refresh();
   sma.Initialize();   sma.Refresh();
   atr.Initialize();   atr.Refresh();
   rsi.Initialize();   rsi.Refresh();
   adx.Initialize();   adx.Refresh();
   macd.Initialize();  macd.Refresh();
   bb.Initialize();    bb.Refresh();
   cci.Initialize();   cci.Refresh();
   stoch.Initialize(); stoch.Refresh();
   ichi.Initialize();  ichi.Refresh();
   obv.Initialize();   obv.Refresh();
   mfi.Initialize();   mfi.Refresh();
   vwap.Initialize();  vwap.Refresh();
   vol.Initialize();   vol.Refresh();

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

   //=== SESSION + NEWS ==============================================
   CSessionManager *sessions=new CSessionManager(sym,logger);
   sessions.SetWeekendFilter(true,60,0);
   sessions.SetSessionEdgeSkip(5,5);
   sessions.SetHolidayFilter(true,true);
   sessions.SetKillZones(false);
   sessions.Initialize();
   sessions.Evaluate(now,true);
   sessions.Validate(validation);
   Print(sessions.Describe());

   CNewsEngine *news=new CNewsEngine(sym,logger);
   news.SetSource(true,true,"srp_news.csv");
   news.SetMinimumSeverity(SRP_NEWS_SEV_HIGH);
   news.SetFailSafeBlock(false);   // allow, so the pipeline can be exercised
   news.SetFlattenOnCritical(true);
   news.Initialize();
   news.Refresh(now,true);
   news.Evaluate(now);
   news.Validate(validation);
   Print(news.Describe());

   //=== CONTEXT =====================================================
   CStrategyContext *context=new CStrategyContext();
   context.SetEmaSet(ema_fast,ema_slow,ema_trend);
   context.SetSma(sma);
   context.SetAtr(atr);
   context.SetRsi(rsi);
   context.SetAdx(adx);
   context.SetMacd(macd);
   context.SetBollinger(bb);
   context.SetCci(cci);
   context.SetStochastic(stoch);
   context.SetIchimoku(ichi);
   context.SetObv(obv);
   context.SetMfi(mfi);
   context.SetVwap(vwap);
   context.SetVolume(vol);
   context.SetSwings(swings);
   context.SetStructure(structure);
   context.SetZones(zones);
   context.SetDisplacement(disp);
   context.SetLiquidity(liquidity);
   context.Validate(validation);
   Print(context.Describe());

   //=== CONFIRMATION ENGINE =========================================
   CConfirmationEngine *confirm=new CConfirmationEngine(context,logger);
   confirm.SetMinConfidence(0.50);
   confirm.SetAdxThreshold(22.0);
   confirm.SetRsiBands(48.0,52.0);
   confirm.SetMinVolumeRatio(0.8);
   confirm.SetAtrBounds(0.0,0.0);
   confirm.SetMaxSpread(500.0);
   confirm.SetMinSessionLiquidity(0.0);
   confirm.SetMinDecisiveChecks(3);
   confirm.SetCheckEnabled(SRP_CONFIRM_TREND,true);
   confirm.SetCheckWeight(SRP_CONFIRM_STRUCTURE,1.5);
   confirm.SetCheckBlocking(SRP_CONFIRM_SPREAD,true);
   confirm.Validate(validation);

   //=== DECISION ENGINE =============================================
   CDecisionEngine *engine=new CDecisionEngine(sym,tf,logger);
   engine.SetCollaborators(sessions,news,context);
   engine.SetConfirmationEngine(confirm);   // engine now OWNS confirm
   engine.SetVoteMode(SRP_VOTE_WEIGHTED);
   engine.SetMinFinalConfidence(0.50);
   engine.SetMinVoteMargin(0.15);
   engine.SetRequireConfirmation(true);

   //--- Register all ten plugins. The engine takes ownership.
   engine.AddPlugin(new CEmaCrossStrategy(context,logger));
   engine.AddPlugin(new CVwapPullbackStrategy(context,logger));
   engine.AddPlugin(new CLiquiditySweepStrategy(context,logger));
   engine.AddPlugin(new COrderBlockStrategy(context,logger));
   engine.AddPlugin(new CFairValueGapStrategy(context,logger));
   engine.AddPlugin(new CMomentumScalpPlugin(context,logger));
   engine.AddPlugin(new COpeningRangeBreakout(context,logger));
   engine.AddPlugin(new CTrendContinuationStrategy(context,logger));
   engine.AddPlugin(new CMeanReversionPlugin(context,logger));
   engine.AddPlugin(new CBreakoutStrategyPlugin(context,logger));

   if(!engine.Initialize())
     {
      Print("decision engine initialisation FAILED");
      delete engine;
      logger.Close(); delete logger;
      return;
     }
   engine.Validate(validation);

   //--- Run the pipeline.
   STradeDecision decision;
   const bool actionable=engine.Evaluate(now,true,decision);
   Print("=== DECISION ===");
   Print("actionable=",actionable,
         " decision=",CStrategyPlugin::DecisionToString(decision.decision),
         " reason=",CDecisionEngine::DeclineToString(decision.decline_reason));
   Print("candidates=",decision.candidates,
         " buyVotes=",decision.buy_votes," sellVotes=",decision.sell_votes,
         " buyW=",DoubleToString(decision.buy_weight,3),
         " sellW=",DoubleToString(decision.sell_weight,3));
   Print("finalConfidence=",DoubleToString(decision.final_confidence,3),
         " risk=",CStrategyPlugin::RatingToString(decision.risk_rating));
   Print("explanation: ",decision.explanation);
   Print("confirmation: ",decision.confirmation.summary,
         " passRatio=",DoubleToString(decision.confirmation.PassRatio(),2));

   //--- Per-check confirmation detail.
   CConfirmationEngine *ce=engine.Confirmation();
   if(ce!=NULL)
     {
      for(int i=0;i<ce.ResultCount();i++)
        {
         SConfirmation c;
         if(!ce.GetResult(i,c))
            continue;
         Print(StringFormat("  %-10s %-8s score=%.2f w=%.1f %s | %s",
               c.name,
               CConfirmationEngine::ResultToString(c.result),
               c.score,c.weight,
               (c.is_blocking ? "[block]" : "       "),
               c.detail));
        }
      Print(ce.Describe());
     }

   //--- Exercise every vote mode so all resolvers compile and run.
   ENUM_SRP_VOTE_MODE modes[5]={SRP_VOTE_FIRST_MATCH,SRP_VOTE_HIGHEST_CONFIDENCE,
                                SRP_VOTE_MAJORITY,SRP_VOTE_WEIGHTED,
                                SRP_VOTE_UNANIMOUS};
   for(int i=0;i<5;i++)
     {
      engine.SetVoteMode(modes[i]);
      STradeDecision d;
      engine.Evaluate(now,true,d);
      Print(StringFormat("vote %-19s -> %-8s %s",
            CDecisionEngine::VoteModeToString(modes[i]),
            CStrategyPlugin::DecisionToString(d.decision),
            (d.actionable ? StringFormat("conf=%.2f",d.final_confidence)
                          : CDecisionEngine::DeclineToString(d.decline_reason))));
     }

   //--- Plugin diagnostics.
   for(int i=0;i<engine.PluginCount();i++)
     {
      CStrategyPlugin *p=engine.PluginAt(i);
      if(p!=NULL)
         Print("  ",p.Describe());
     }

   SDecisionInput snap;
   engine.GetSnapshot(snap);
   Print("snapshot valid=",snap.is_valid," spread=",
         DoubleToString(snap.spread_points,1),
         " structureValid=",snap.structure_valid);

   STradeDecision last;
   engine.GetLastDecision(last);
   Print(engine.Describe());
   Print("validation errors=",validation.error_count,
         " warnings=",validation.warning_count);
   if(StringLen(validation.report)>0)
      Print(validation.report);
   Print("=== PHASE 3 FULL CHECK COMPLETE ===");

   //=== TEARDOWN (reverse of construction) ==========================
   engine.Shutdown();
   delete engine;              // deletes plugins + confirmation engine
   delete context;
   news.Shutdown();     delete news;
   sessions.Shutdown(); delete sessions;
   delete liquidity; delete blocks; delete disp; delete zones;
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
   ema_trend.Shutdown(); delete ema_trend;
   ema_slow.Shutdown();  delete ema_slow;
   ema_fast.Shutdown();  delete ema_fast;
   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
