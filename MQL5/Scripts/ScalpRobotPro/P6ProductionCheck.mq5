//+------------------------------------------------------------------+
//|                                       P6ProductionCheck.mq5 |
//|         Scalping Robot Pro - production integration check (script) |
//|                                                                  |
//|   A three-line adapter. Every assertion lives in                    |
//|   Include\ScalpRobotPro\Tests\ProductionCheck.mqh so that the same   |
//|   checks can also be launched headless through the Strategy Tester   |
//|   by the Expert of the same name.                                   |
//|                                                                  |
//|   Attach to any chart and read the Experts tab.                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Runs the production integration assertions"

#include <ScalpRobotPro/Tests/ProductionCheck.mqh>

//+------------------------------------------------------------------+
void OnStart(void)
  {
   RunProductionCheck();
  }
//+------------------------------------------------------------------+
