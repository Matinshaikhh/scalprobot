//+------------------------------------------------------------------+
//|                                          P6RegimeCheck.mq5 |
//|            Scalping Robot Pro - regime & volatility check (P6) |
//|                                                                  |
//|   Adapter. Assertions live in Tests\RegimeCheck.mqh so the same       |
//|   checks run from a chart and headlessly through the tester.          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Verifies the regime and volatility engine"

#include <ScalpRobotPro/Tests/RegimeCheck.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   RunRegimeCheck();
  }
//+------------------------------------------------------------------+
