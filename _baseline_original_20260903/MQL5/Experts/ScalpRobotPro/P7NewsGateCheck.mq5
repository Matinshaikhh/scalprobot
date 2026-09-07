//+------------------------------------------------------------------+
//|                                         P7NewsGateCheck.mq5 |
//|      Scalping Robot Pro - news gating precedence, tester-launchable |
//|                                                                  |
//|   VERIFICATION ARTEFACT, NOT A PRODUCT FILE. No order is ever sent.  |
//|                                                                  |
//|   Every assertion supplies its own timestamp and, where a source is    |
//|   needed, writes its own temporary CSV - so nothing depends on the      |
//|   terminal calendar, which is unavailable in the tester by design.      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Verifies news filter precedence, fail-safe and blackout windows"

#include <ScalpRobotPro/Tests/NewsGateCheck.mqh>

int OnInit(void)
  {
   RunNewsGateCheck();
   return(INIT_FAILED);
  }
void OnTick(void) { }
//+------------------------------------------------------------------+
