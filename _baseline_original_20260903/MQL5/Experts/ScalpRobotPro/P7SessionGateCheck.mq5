//+------------------------------------------------------------------+
//|                                      P7SessionGateCheck.mq5 |
//|   Scalping Robot Pro - session gating precedence, tester-launchable |
//|                                                                  |
//|   VERIFICATION ARTEFACT, NOT A PRODUCT FILE. No order is ever sent.  |
//|                                                                  |
//|   Runs entirely in OnInit: every assertion supplies its own timestamp,  |
//|   so nothing here depends on indicator warm-up or on live market data.  |
//|   INIT_FAILED is returned deliberately - the pass is complete once the  |
//|   assertions have run, and there is nothing to tick.                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Verifies session filter precedence and the master switch"

#include <ScalpRobotPro/Tests/SessionGateCheck.mqh>

int OnInit(void)
  {
   RunSessionGateCheck();
   return(INIT_FAILED);
  }
void OnTick(void) { }
//+------------------------------------------------------------------+
