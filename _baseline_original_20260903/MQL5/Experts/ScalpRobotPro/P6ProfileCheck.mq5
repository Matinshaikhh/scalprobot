//+------------------------------------------------------------------+
//|                                         P6ProfileCheck.mq5 |
//|      Scalping Robot Pro - profile verification, tester-launchable |
//|                                                                  |
//|   VERIFICATION ARTEFACT, NOT A PRODUCT FILE.                        |
//|   Identical assertions to the script of the same name; this form     |
//|   exists because only the Strategy Tester can be driven from a       |
//|   command line, and it will not launch a script.                     |
//|                                                                  |
//|   Returns INIT_FAILED deliberately: the assertions have already run  |
//|   by then, so the pass stops immediately. No order is ever sent.     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Verifies the multi-asset market profile system"

#include <ScalpRobotPro/Tests/ProfileCheck.mqh>

int OnInit(void)
  {
   RunProfileCheck();
   return(INIT_FAILED);
  }
void OnTick(void) { }
//+------------------------------------------------------------------+
