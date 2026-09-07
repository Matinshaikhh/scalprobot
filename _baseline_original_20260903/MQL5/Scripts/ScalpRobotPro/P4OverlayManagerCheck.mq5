//+------------------------------------------------------------------+
//|                                   P4OverlayManagerCheck.mq5 |
//|   Phase 4 harness: chart overlay (15 layers) + trade manager.       |
//|                                                                  |
//|   The trade manager section drives every rule in priority order and   |
//|   asserts the ONE-WAY STOP RULE, which is the single most important   |
//|   invariant in the whole class.                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Interface/Chart/CChartOverlay.mqh>
#include <ScalpRobotPro/Interface/Manager/CTradeManager.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CBlockDetector.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CDisplacementDetector.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CLiquidityDetector.mqh>
#include <ScalpRobotPro/Logger/CLogger.mqh>
#include <ScalpRobotPro/Logger/CTerminalLogSink.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   const string sym=_Symbol;
   const ENUM_TIMEFRAMES tf=PERIOD_M5;

   CLogger *logger=new CLogger(SRP_LOG_INFO);
   logger.AddSink(new CTerminalLogSink(SRP_LOG_INFO));
   logger.Open();

   //=== PHASE 2 SOURCES THE OVERLAY READS ============================
   CAtrIntel *atr=new CAtrIntel(sym,tf,14,logger);
   atr.Initialize();
   atr.Refresh();

   CSwingDetector *swings=new CSwingDetector(sym,tf,logger,3,300,64);
   swings.Initialize();
   swings.Refresh();

   CMarketStructure *structure=new CMarketStructure(sym,tf,swings,logger);
   structure.Initialize();
   structure.Refresh(SymbolInfoDouble(sym,SYMBOL_BID));

   CZoneRegistry *zones=new CZoneRegistry(logger,64);
   CDisplacementDetector *disp=new CDisplacementDetector(sym,tf,atr,logger);
   CBlockDetector *blocks=new CBlockDetector(sym,tf,disp,zones,logger);
   CLiquidityDetector *liquidity=new CLiquidityDetector(sym,tf,swings,atr,
                                                        zones,logger);
   blocks.Scan(true);
   liquidity.Scan(true);
   Print("sources: swingHighs=",swings.HighCount(),
         " swingLows=",swings.LowCount(),
         " zones=",zones.Count(),
         " blocks=",blocks.OrderBlockCount(),
         " fvg=",blocks.FairValueGapCount(),
         " sweeps=",liquidity.SweepCount());

   //=== OVERLAY ======================================================
   CUiTheme *theme=new CUiTheme(SRP_UI_THEME_DARK);
   CObjectPainter *painter=new CObjectPainter(theme,logger,"SRP4O_");
   painter.Attach(0,0,CORNER_LEFT_UPPER);

   CChartOverlay *overlay=new CChartOverlay(painter,theme,sym,tf,logger);
   overlay.SetSources(zones,swings,structure);
   overlay.SetLimits(12,8,10);
   overlay.SetZoneExtendBars(20);
   overlay.SetEnabled(true);

   //--- Model the overlay's statistics and session layers consume.
   SDashboardModel model;
   model.symbol         = sym;
   model.session_text   = "LONDON";
   model.win_rate       = 61.0;
   model.profit_factor  = 1.72;
   model.total_trades   = 33;
   model.today_profit   = 88.40;
   model.equity         = AccountInfoDouble(ACCOUNT_EQUITY);
   model.balance        = AccountInfoDouble(ACCOUNT_BALANCE);
   model.open_trades    = 1;
   model.is_valid       = true;
   model.updated_at     = TimeCurrent();

   const datetime bar=iTime(sym,tf,0);
   Print("drawAnalysis(first)=",overlay.DrawAnalysis(bar,model,true));
   //--- Second call on the same bar must be gated out.
   Print("drawAnalysis(same bar, not forced)=",
         overlay.DrawAnalysis(bar,model,false));
   Print("drawAnalysis(forced)=",overlay.DrawAnalysis(bar,model,true));

   //--- Every one of the 15 layers off, then on again.
   for(int i=0;i<SRP_DRAW_LAYER_COUNT;i++)
     {
      const ENUM_SRP_DRAW_LAYER layer=(ENUM_SRP_DRAW_LAYER)i;
      overlay.SetLayerEnabled(layer,false);
      overlay.DrawAnalysis(bar,model,true);
      overlay.ClearLayer(layer);
      const bool toggled=overlay.ToggleLayer(layer);
      Print("layer ",CChartOverlay::LayerToString(layer),
            " toggled back to ",toggled);
     }
   overlay.DrawAnalysis(bar,model,true);
   Print(overlay.Describe());

   //=== TRADE MARKUP =================================================
   const double bid=SymbolInfoDouble(sym,SYMBOL_BID);
   const double point=SymbolInfoDouble(sym,SYMBOL_POINT);

   SManagedPosition position;
   position.ticket        = 77001;
   position.symbol        = sym;
   position.magic         = 990011;
   position.is_buy        = true;
   position.volume        = 0.20;
   position.initial_volume= 0.20;
   position.open_price    = bid-300*point;
   position.current_price = bid;
   position.stop_loss     = bid-500*point;
   position.take_profit   = bid+400*point;
   position.profit_points = 300.0;
   position.profit_money  = 6.00;
   position.open_time     = TimeCurrent()-1800;
   position.age_seconds   = 1800;
   position.peak_price    = bid+40*point;
   position.peak_profit_points = 340.0;

   overlay.DrawEntry(position);
   overlay.DrawStops(position);
   overlay.DrawTradeLabel(position);
   overlay.DrawTrailing(position,bid-120*point);
   Print("after trade markup: ",overlay.Describe());

   //=== TRADE MANAGER ================================================
   CTradeManager *manager=new CTradeManager(sym,atr,logger);
   manager.ConfigureBreakEven(true,150.0,20.0);
   manager.ConfigureTrailing(true,200.0,120.0,10.0);
   manager.ConfigureAtrTrailing(false,2.0,10.0);
   manager.ConfigureAtrExit(true,3.0);
   manager.ConfigureTimeExit(true,120,true);
   manager.ConfigureMaxHold(true,240);
   manager.ConfigureScaleIn(true,250.0,0.5,1);
   manager.ConfigureScaleOut(true,180.0,0.5,1);
   manager.ConfigureReverse(true);
   manager.SetBrokerVolumeLimits(
      SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN),
      SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP));

   SValidationResult validation;
   manager.Validate(validation);
   Print("manager valid=",validation.is_valid,
         " errors=",validation.error_count,
         " warnings=",validation.warning_count);
   if(validation.report!="")
      Print(validation.report);

   //--- Tracking.
   Print("track=",manager.Track(position)," count=",manager.TrackedCount());
   SManagedPosition tracked;
   Print("getTracked=",manager.GetTracked(position.ticket,tracked),
         " peak=",DoubleToString(tracked.peak_price,_Digits));

   //--- Profit protection: break-even, then trailing.
   STradeIntent intent;
   if(manager.Evaluate(position,intent))
      Print("intent#1 action=",CTradeManager::ActionToString(intent.action),
            " trigger=",CTradeManager::TriggerToString(intent.trigger),
            " stop=",DoubleToString(intent.new_stop,_Digits),
            " vol=",DoubleToString(intent.volume,2),
            " urgency=",DoubleToString(intent.urgency,2),
            " reason=",intent.reason);
   else
      Print("intent#1 none");

   //--- THE ONE-WAY STOP RULE. A stop already better than any proposal
   //--- must produce no MOVE_STOP intent, ever.
   const double protective=intent.new_stop;
   if(intent.action==SRP_TM_MOVE_STOP)
     {
      manager.NotifyStopMoved(position.ticket,protective,intent.trigger);
      position.stop_loss=protective;
      //--- Now push the stop far into profit and re-evaluate: nothing may
      //--- pull it back down.
      position.stop_loss=bid-10*point;
      manager.Track(position);
      STradeIntent again;
      const bool actionable=manager.Evaluate(position,again);
      const bool retreated=(actionable && again.action==SRP_TM_MOVE_STOP &&
                            again.new_stop<position.stop_loss);
      Print("one-way rule holds=",!retreated,
            " (proposed=",DoubleToString(again.new_stop,_Digits),
            " current=",DoubleToString(position.stop_loss,_Digits),")");
      position.stop_loss=protective;
      manager.Track(position);
     }

   //--- Scale out: deep in profit, below the reduction cap.
   position.profit_points=400.0;
   position.current_price=bid+100*point;
   manager.Track(position);
   STradeIntent scale;
   if(manager.Evaluate(position,scale))
      Print("intent#2 action=",CTradeManager::ActionToString(scale.action),
            " trigger=",CTradeManager::TriggerToString(scale.trigger),
            " vol=",DoubleToString(scale.volume,2),
            " reason=",scale.reason);
   if(scale.action==SRP_TM_SCALE_OUT)
      manager.NotifyScaledOut(position.ticket);

   //--- Scale in after the reduction is consumed.
   manager.Track(position);
   STradeIntent add;
   if(manager.Evaluate(position,add))
      Print("intent#3 action=",CTradeManager::ActionToString(add.action),
            " trigger=",CTradeManager::TriggerToString(add.trigger),
            " vol=",DoubleToString(add.volume,2));
   if(add.action==SRP_TM_SCALE_IN)
      manager.NotifyScaledIn(position.ticket);

   //--- Max holding time must outrank profit optimisation.
   SManagedPosition aged=position;
   aged.age_seconds=250*60;
   aged.open_time=TimeCurrent()-(datetime)aged.age_seconds;
   manager.Track(aged);
   STradeIntent hold;
   if(manager.Evaluate(aged,hold))
      Print("intent#4 (aged) action=",CTradeManager::ActionToString(hold.action),
            " trigger=",CTradeManager::TriggerToString(hold.trigger),
            " reason=",hold.reason);

   //--- Time exit on a losing position.
   SManagedPosition losing=position;
   losing.ticket=77002;
   losing.age_seconds=130*60;
   losing.open_time=TimeCurrent()-(datetime)losing.age_seconds;
   losing.profit_points=-80.0;
   losing.profit_money=-4.0;
   losing.current_price=losing.open_price-80*point;
   manager.Track(losing);
   STradeIntent timed;
   if(manager.Evaluate(losing,timed))
      Print("intent#5 (losing, timed) action=",
            CTradeManager::ActionToString(timed.action),
            " trigger=",CTradeManager::TriggerToString(timed.trigger));

   //--- Emergency must beat everything, including max hold.
   manager.ArmEmergency("kill switch: harness test");
   Print("emergency armed=",manager.IsEmergencyArmed());
   STradeIntent panic;
   if(manager.Evaluate(aged,panic))
      Print("intent#6 (emergency) action=",
            CTradeManager::ActionToString(panic.action),
            " trigger=",CTradeManager::TriggerToString(panic.trigger),
            " urgency=",DoubleToString(panic.urgency,2),
            " reason=",panic.reason);
   manager.DisarmEmergency();
   Print("emergency disarmed=",!manager.IsEmergencyArmed());

   //--- Explicit requests.
   STradeIntent reverse;
   Print("requestReverse=",manager.RequestReverse(position,0.30,
                                                  "decision engine flipped",
                                                  reverse),
         " action=",CTradeManager::ActionToString(reverse.action),
         " vol=",DoubleToString(reverse.volume,2));
   STradeIntent flatten;
   Print("requestEmergencyExit=",
         manager.RequestEmergencyExit(position,flatten),
         " action=",CTradeManager::ActionToString(flatten.action));

   //--- Untracking.
   manager.Untrack(losing.ticket);
   Print("after untrack count=",manager.TrackedCount());
   manager.UntrackAll();
   Print("after untrackAll count=",manager.TrackedCount(),
         " intents issued=",manager.IntentCount());
   Print(manager.Describe());

   //=== CLEANUP ======================================================
   overlay.ClearTrade(position.ticket);
   overlay.ClearAll();
   Print("after clearAll owned=",painter.OwnedCount());
   Print("=== P4 OVERLAY + MANAGER CHECK COMPLETE ===");

   delete manager;
   delete overlay;
   delete painter;
   delete theme;
   delete liquidity;
   delete blocks;
   delete disp;
   delete zones;
   delete structure;
   delete swings;
   delete atr;
   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
