//+------------------------------------------------------------------+
//|                                         P6ProfileCheck.mq5 |
//|         Scalping Robot Pro - multi-asset profile verification (P6) |
//|                                                                  |
//|   A three-line adapter. Every assertion lives in                    |
//|   Include\ScalpRobotPro\Tests\ProfileCheck.mqh so the same checks    |
//|   can also run headlessly through the Strategy Tester via the Expert |
//|   of the same name.                                                |
//|                                                                  |
//|   Attach to any chart and read the Experts tab.                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Verifies the multi-asset market profile system"

#include <ScalpRobotPro/Tests/ProfileCheck.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   RunProfileCheck();
  }
//+------------------------------------------------------------------+
