//+------------------------------------------------------------------+
//|                                       Phase4CompileCheck.mq5 |
//|   Full Phase 4 regression: the CTraderInterface facade wiring the    |
//|   dashboard, chart overlay, trade manager, enterprise logger and     |
//|   performance analytics together over borrowed Phase 2 modules.      |
//|                                                                  |
//|   This is the integration test. The subsystem harnesses prove each   |
//|   class; this proves they compose, that construction/teardown order  |
//|   is sound, and that the chart is left clean.                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Interface/CTraderInterface.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CBlockDetector.mqh>
#include <ScalpRobotPro/Intelligence/SmartMoney/CDisplacementDetector.mqh>
#include <ScalpRobotPro/Logger/CLogger.mqh>
#include <ScalpRobotPro/Logger/CTerminalLogSink.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   const string sym=_Symbol;
   const ENUM_TIMEFRAMES tf=PERIOD_M5;
   const double point=SymbolInfoDouble(sym,SYMBOL_POINT);

   //=== BORROWED PHASE 2 MODULES (the engine owns these) =============
   CLogger *boot=new CLogger(SRP_LOG_WARN);
   boot.AddSink(new CTerminalLogSink(SRP_LOG_WARN));
   boot.Open();

   CAtrIntel *atr=new CAtrIntel(sym,tf,14,boot);
   atr.Initialize();
   atr.Refresh();

   CSwingDetector *swings=new CSwingDetector(sym,tf,boot,3,300,64);
   swings.Initialize();
   swings.Refresh();

   CMarketStructure *structure=new CMarketStructure(sym,tf,swings,boot);
   structure.Initialize();
   structure.Refresh(SymbolInfoDouble(sym,SYMBOL_BID));

   CZoneRegistry *zones=new CZoneRegistry(boot,64);
   //--- The zone producers are not reachable through CTraderInterface's
   //--- includes, so the harness pulls them in explicitly. That is the
   //--- correct dependency direction: the interface reads the registry
   //--- and does not care who filled it.
   CDisplacementDetector *displacement=new CDisplacementDetector(sym,tf,atr,boot);
   CBlockDetector *blocks=new CBlockDetector(sym,tf,displacement,zones,boot);
   blocks.Scan(true);

   //=== THE FACADE ===================================================
   CTraderInterface *ui=new CTraderInterface(sym,tf,
                                             AccountInfoDouble(ACCOUNT_BALANCE),
                                             SRP_UI_THEME_DARK,"SRP_P4_");
   Print("initialize=",ui.Initialize(atr,zones,swings,structure));
   Print("isInitialized=",ui.IsInitialized());

   SValidationResult validation;
   ui.Validate(validation);
   Print("facade valid=",validation.is_valid,
         " errors=",validation.error_count,
         " warnings=",validation.warning_count);
   if(validation.report!="")
      Print(validation.report);

   //--- Borrowed subsystem pointers must all resolve.
   Print("subsystems: logger=",(ui.Logger()!=NULL),
         " analytics=",(ui.Analytics()!=NULL),
         " manager=",(ui.Manager()!=NULL),
         " panel=",(ui.Panel()!=NULL),
         " overlay=",(ui.Overlay()!=NULL),
         " theme=",(ui.Theme()!=NULL),
         " painter=",(ui.Painter()!=NULL));

   //--- Configure the trade manager through the facade's accessor.
   CTradeManager *manager=ui.Manager();
   manager.ConfigureBreakEven(true,150.0,20.0);
   manager.ConfigureTrailing(true,200.0,120.0,10.0);
   manager.ConfigureAtrExit(true,3.0);
   manager.ConfigureTimeExit(true,120,true);
   manager.ConfigureMaxHold(true,240);
   manager.ConfigureScaleOut(true,180.0,0.5,1);
   manager.ConfigureScaleIn(true,250.0,0.5,1);
   manager.SetBrokerVolumeLimits(SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN),
                                 SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP));

   //=== CLOSED TRADES FEED ANALYTICS ================================
   const double series[]={120.0,-60.0,180.0,-40.0,95.0,-70.0,210.0,-30.0};
   datetime when=TimeCurrent()-(datetime)(9*3600);
   for(int i=0;i<ArraySize(series);i++)
     {
      SClosedTrade trade;
      trade.ticket        = (ulong)(50000+i);
      trade.symbol        = sym;
      trade.is_buy        = (i%2==0);
      trade.volume        = 0.10;
      trade.open_price    = 1.10000;
      trade.close_price   = 1.10000+series[i]/100000.0;
      trade.open_time     = when;
      trade.close_time    = when+(datetime)(420+i*30);
      trade.gross_profit  = series[i];
      trade.commission    = -0.60;
      trade.risk_amount   = 60.0;
      trade.strategy_name = "OrderBlock";
      trade.exit_reason   = (series[i]>0.0 ? "take_profit" : "stop_loss");
      ui.OnTradeClosed(trade);
      when=trade.close_time+(datetime)900;
     }
   Print("analytics retained=",ui.Analytics().TradeCount());

   //=== RENDER =======================================================
   SDashboardModel model;
   model.symbol          = sym;
   model.product_version = SRP_PRODUCT_VERSION;
   model.currency        = AccountInfoString(ACCOUNT_CURRENCY);
   model.balance         = AccountInfoDouble(ACCOUNT_BALANCE);
   model.equity          = AccountInfoDouble(ACCOUNT_EQUITY);
   model.margin_used     = AccountInfoDouble(ACCOUNT_MARGIN);
   model.margin_free     = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   model.margin_level    = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   model.floating_profit = 6.20;
   model.spread_points   = (double)SymbolInfoInteger(sym,SYMBOL_SPREAD);
   model.session_text    = "LONDON +NY";
   model.news_countdown  = "next: NFP in 1h 05m";
   model.strategy_text   = "OrderBlock";
   model.engine_state    = "TRADING";
   model.health_text     = "OK";
   model.health_tone     = SRP_UI_TONE_POSITIVE;
   model.open_trades     = 1;
   model.risk_percent    = 1.00;
   model.lot_size        = 0.10;
   model.total_volume    = 0.10;
   model.updated_at      = TimeCurrent();
   model.is_valid        = true;

   //--- Analytics fills the performance rows; the caller keeps account data.
   ui.ApplyAnalytics(model);
   Print("after ApplyAnalytics: winRate=",DoubleToString(model.win_rate,2),
         " pf=",DoubleToString(model.profit_factor,3),
         " avgRR=",DoubleToString(model.average_rr,3),
         " trades=",model.total_trades,
         " today=",DoubleToString(model.today_profit,2),
         " week=",DoubleToString(model.week_profit,2),
         " month=",DoubleToString(model.month_profit,2));

   //--- Several ticks, to prove throttling and bar gating do not fault.
   for(int i=0;i<5;i++)
      ui.Render(model);
   Print("ticks=",ui.TickCount());

   //=== POSITION MANAGEMENT VIA THE FACADE ===========================
   const double bid=SymbolInfoDouble(sym,SYMBOL_BID);
   SManagedPosition position;
   position.ticket        = 60001;
   position.symbol        = sym;
   position.magic         = 990011;
   position.is_buy        = true;
   position.volume        = 0.20;
   position.initial_volume= 0.20;
   position.open_price    = bid-320*point;
   position.current_price = bid;
   position.stop_loss     = bid-520*point;
   position.take_profit   = bid+380*point;
   position.profit_points = 320.0;
   position.profit_money  = 6.40;
   position.open_time     = TimeCurrent()-2400;
   position.age_seconds   = 2400;
   position.peak_price    = bid+30*point;
   position.peak_profit_points = 350.0;

   ui.OnTradeOpened(position,"OrderBlock");

   STradeIntent intent;
   const bool actionable=ui.ManagePosition(position,intent);
   Print("managePosition actionable=",actionable,
         " action=",CTradeManager::ActionToString(intent.action),
         " trigger=",CTradeManager::TriggerToString(intent.trigger),
         " stop=",DoubleToString(intent.new_stop,_Digits),
         " vol=",DoubleToString(intent.volume,2),
         " reason=",intent.reason);

   //--- Execution confirmations flow back so tracked state is truthful.
   if(intent.action==SRP_TM_MOVE_STOP)
      ui.ConfirmStopMoved(intent.ticket,intent.new_stop,intent.trigger);
   ui.ConfirmScaledOut(position.ticket);
   ui.ConfirmScaledIn(position.ticket);

   //--- Execution timing feeds the dashboard latency row.
   ui.Logger().LogExecutionTime("OrderSend",63.5,0,1.0,position.ticket);
   ui.Logger().LogExecutionTime("PositionModify",121.0,1,0.0,position.ticket);
   ui.ApplyAnalytics(model);
   Print("latency from exec channel=",DoubleToString(model.latency_ms,2),"ms");

   //--- Risk and indicator channels, as the engine would use them.
   ui.Logger().LogRiskEvent("ExposureGuard","exposure at 40% of cap",
                            0.40,1.00,0.60);
   double atr_now=0.0,atr_prev=0.0;
   atr.Value(0,atr_now);
   atr.Value(1,atr_prev);
   ui.Logger().LogIndicator("ATR(14)",atr_now,atr_prev,0.0,"refresh");

   //=== VIEW CONTROL =================================================
   ui.ToggleCollapsed();
   ui.Render(model);
   ui.ToggleCollapsed();
   ui.SetLayerEnabled(SRP_DRAW_ORDER_BLOCKS,false);
   ui.SetLayerEnabled(SRP_DRAW_ORDER_BLOCKS,true);
   ui.SetOverlayEnabled(false);
   ui.Render(model);
   ui.SetOverlayEnabled(true);
   ui.SetDashboardEnabled(false);
   ui.Render(model);
   ui.SetDashboardEnabled(true);
   ui.SetTheme(SRP_UI_THEME_LIGHT);
   ui.SetTheme(SRP_UI_THEME_CONTRAST);
   ui.SetTheme(SRP_UI_THEME_DARK);
   ui.Render(model);
   ui.RedrawAll();
   ui.Render(model);

   //=== CLOSE A POSITION, MARKUP MUST GO ============================
   SClosedTrade closed;
   closed.ticket        = position.ticket;
   closed.symbol        = sym;
   closed.is_buy        = position.is_buy;
   closed.volume        = position.volume;
   closed.open_price    = position.open_price;
   closed.close_price   = bid+50*point;
   closed.open_time     = position.open_time;
   closed.close_time    = TimeCurrent();
   closed.gross_profit  = 74.00;
   closed.commission    = -1.20;
   closed.risk_amount   = 40.00;
   closed.strategy_name = "OrderBlock";
   closed.exit_reason   = "trailing_stop";
   ui.OnTradeClosed(closed);
   Print("after close: tracked=",ui.Manager().TrackedCount(),
         " retained=",ui.Analytics().TradeCount());

   //=== REPORTING ====================================================
   ui.PublishSessionReport();
   Print("exportAll=",ui.ExportAll("ScalpRobotPro\\Reports\\P4Check"));
   Print(ui.Describe());

   //=== SHUTDOWN =====================================================
   ui.Shutdown();
   Print("after shutdown initialized=",ui.IsInitialized());
   Print("=== PHASE 4 COMPILE CHECK COMPLETE ===");

   //--- Facade first: it must release its chart objects before the
   //--- borrowed Phase 2 modules disappear.
   delete ui;
   delete blocks;
   delete displacement;
   delete zones;
   delete structure;
   delete swings;
   delete atr;
   boot.Close();
   delete boot;
  }
//+------------------------------------------------------------------+
