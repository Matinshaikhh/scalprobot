//+------------------------------------------------------------------+
//|                                        EngineCompileCheck.mq5 |
//|                          Scalping Robot Pro - Core Trading Engine |
//|                                                                  |
//|   VERIFICATION HARNESS - not part of the shipped product.           |
//|                                                                  |
//|   Purpose: compile the Core Trading Engine in isolation so the       |
//|   engine's own correctness is proven without the rest of the         |
//|   architecture (whose method bodies are still declarations) being     |
//|   dragged in. It instantiates every class and touches the full API    |
//|   surface, so the compiler checks signatures and types for real.      |
//|                                                                  |
//|   It never sends an order: OnStart returns before any trade call.     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property script_show_inputs

#include <ScalpRobotPro/Trade/Engine/CTradeEngine.mqh>
#include <ScalpRobotPro/Core/CServerClock.mqh>
#include <ScalpRobotPro/Logger/CLogger.mqh>
#include <ScalpRobotPro/Logger/CTerminalLogSink.mqh>
#include <ScalpRobotPro/Core/Events/CEventBus.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   //--- Infrastructure -----------------------------------------------
   CLogger *logger=new CLogger(SRP_LOG_DEBUG);
   logger.AddSink(new CTerminalLogSink(SRP_LOG_DEBUG));
   logger.Open();

   CServerClock *clock=new CServerClock();
   clock.ResolveOffset();

   CEventBus *bus=new CEventBus();
   bus.SetLogger(logger);

   //--- Engine configuration ----------------------------------------
   STradeEngineConfig config;
   config.symbol                   = _Symbol;
   config.magic_base               = 20260806;
   config.magic_slots              = 16;
   config.comment_tag              = "SRP";
   config.max_retry_attempts       = 3;
   config.retry_backoff_ms         = 150;
   config.progressive_backoff      = true;
   config.deviation_points         = 20;
   config.max_slippage_points      = 50.0;
   config.use_order_check          = true;
   config.log_execution_speed      = true;
   config.max_spread_points        = 300.0;
   config.min_free_margin_percent  = 30.0;
   config.min_margin_level_percent = 200.0;
   config.margin_safety_factor     = 1.1;

   CTradeEngine *engine=new CTradeEngine(config,clock,bus,logger);

   if(!engine.Initialize())
     {
      Print("engine initialisation failed");
      delete engine; delete bus; delete clock; delete logger;
      return;
     }

   //--- Validation ---------------------------------------------------
   SValidationResult validation;
   engine.Validate(validation);
   Print("validation valid=",validation.is_valid,
         " errors=",validation.error_count,
         " warnings=",validation.warning_count);
   if(StringLen(validation.report)>0)
      Print(validation.report);

   //--- Environment --------------------------------------------------
   Print(engine.DescribeEnvironment());
   Print("hedging=",engine.IsHedging()," netting=",engine.IsNetting());
   Print("spread=",DoubleToString(engine.SpreadPoints(),1)," points");

   //--- Read-only queries exercise the whole query surface -----------
   engine.RefreshAll();
   Print("positions=",engine.PositionCount(),
         " pending=",engine.PendingOrderCount(),
         " totalVol=",DoubleToString(engine.TotalVolume(),2),
         " netVol=",DoubleToString(engine.NetVolume(),2),
         " floatPnL=",DoubleToString(engine.FloatingProfit(),2));

   //--- Component access --------------------------------------------
   CBrokerManager *broker=engine.Broker();
   SBrokerCheckResult check;
   Print("tradingAllowed=",broker.CheckTradingAllowed(check)," ",check.detail);
   Print("marketOpen=",broker.CheckMarketOpen(check)," ",check.detail);
   Print("spreadOk=",broker.CheckSpread(check)," ",check.detail);

   const double test_volume=broker.NormalizeVolume(broker.VolumeMin());
   Print("volumeOk=",broker.CheckVolume(test_volume,check)," ",check.detail);
   Print("marginOk=",broker.CheckMargin(ORDER_TYPE_BUY,test_volume,
                                        broker.Ask(),check)," ",check.detail);
   Print("maxAffordable=",
         DoubleToString(broker.MaxAffordableVolume(ORDER_TYPE_BUY,broker.Ask()),2));

   //--- Magic ownership ---------------------------------------------
   CMagicNumberManager *magic=engine.Magic();
   Print(magic.Describe());
   Print("isOurs(base)=",magic.IsOurs(magic.BaseMagic()),
         " isOurs(999)=",magic.IsOurs(999));
   ENUM_SRP_STRATEGY_ID resolved;
   Print("resolveStrategy=",
         magic.ResolveStrategy(magic.MagicForStrategy(SRP_STRATEGY_BREAKOUT),resolved),
         " -> ",EnumToString(resolved));
   Print("comment='",magic.BuildComment("test/detail*99"),"'");

   //--- Execution telemetry -----------------------------------------
   SExecutionStatistics stats;
   engine.GetExecutionStatistics(stats);
   Print(engine.DescribeStatistics());

   //--- Health -------------------------------------------------------
   SHealthReport health;
   engine.ReportHealth(health);
   Print("health=",EnumToString(health.status)," ",health.detail);

   //--- NO ORDERS ARE SENT. The calls below are compiled but never
   //--- reached, which is the point: signatures are verified without
   //--- touching a live account.
   if(false)
     {
      SExecutionReport report;
      STradeResult result;
      STradeRequest request;

      engine.Buy(0.01,0.0,0.0,"test",report);
      engine.Sell(0.01,0.0,0.0,"test",report);
      engine.BuyLimit(0.01,1.0,0.0,0.0,"test",report,0);
      engine.SellLimit(0.01,1.0,0.0,0.0,"test",report,0);
      engine.BuyStop(0.01,1.0,0.0,0.0,"test",report,0);
      engine.SellStop(0.01,1.0,0.0,0.0,"test",report,0);
      engine.ModifyOrder(1,1.0,0.0,0.0,report);
      engine.DeleteOrder(1,report);
      engine.DeleteAllOrders();
      engine.ClosePositionEx(1,"test",report);
      engine.ClosePartialEx(1,0.01,"test",report);
      engine.ClosePartialPercent(1,50.0,"test",report);
      engine.CloseAll("test");
      engine.CloseSymbol(_Symbol,"test");
      engine.CloseBuys("test");
      engine.CloseSells("test");
      engine.Reverse(1,0.01,0.0,0.0,"test",report);

      int closed=0,deleted=0;
      engine.FlattenAll("test",closed,deleted);

      //--- ITradeExecutor surface
      engine.OpenPosition(request,result);
      engine.ClosePosition(1,SRP_EXIT_MANUAL,result);
      engine.ClosePartial(1,0.01,SRP_EXIT_PARTIAL_CLOSE,result);
      engine.ModifyStops(1,0.0,0.0,result);
      engine.DeletePendingOrder(1,result);
      Print(engine.AverageSlippagePoints(),engine.AverageLatencyMs(),
            engine.RejectionCount());

      //--- Stop-limit and typed deletion
      COrderManager *orders=engine.Orders();
      orders.PlaceStopLimit(ORDER_TYPE_BUY_STOP_LIMIT,0.01,1.0,1.0,
                            0.0,0.0,"test",report,0);
      orders.DeletePendingOrdersByType(ORDER_TYPE_BUY_LIMIT);

      //--- Position manager extras
      CEnginePositionManager *positions=engine.Positions();
      positions.RemoveStops(1,report);
      positions.CloseProfitable("test");
      positions.CloseLosing("test");
      SEnginePosition netted;
      positions.GetNettedPosition(netted);
     }

   Print("=== COMPILE CHECK COMPLETE ===");

   engine.Shutdown();
   delete engine;
   delete bus;
   delete clock;
   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
