//+------------------------------------------------------------------+
//|                                           P6ScalpCheck.mq5 |
//|              Scalping Robot Pro - ultra-scalp verification (P6b) |
//|                                                                  |
//|   Adapter. Assertions live in Tests\ScalpCheck.mqh so the same checks |
//|   run from a chart and headlessly through the tester.                 |
//|                                                                  |
//|   The probe ATR is warmed here before asserting: on a live chart the   |
//|   history is already present, so a handful of refreshes suffice, but   |
//|   BarsCalculated is not guaranteed on the first one.                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Verifies ultra-scalp duplicate protection, costs and exits"

#include <ScalpRobotPro/Tests/ScalpCheck.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   if(!ScalpProbeInit())
     {
      Print("  FAIL  probe ATR could not be created");
      return;
     }

   for(int i=0;i<100 && !ScalpProbeReady();i++)
     {
      ScalpProbeRefresh();
      if(!ScalpProbeReady())
         Sleep(100);
     }

   RunScalpCheck();
   ScalpProbeRelease();
  }
//+------------------------------------------------------------------+
