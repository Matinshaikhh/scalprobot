//+------------------------------------------------------------------+
//|                                       P6ProductionCheck.mq5 |
//|         Scalping Robot Pro - production integration check (expert) |
//|                                                                  |
//|   VERIFICATION ARTEFACT, NOT A PRODUCT FILE.                        |
//|                                                                  |
//|   Identical assertions to the script of the same name; this form      |
//|   exists only because the Strategy Tester can be driven from a        |
//|   command line and will not launch a script. That is what allows the  |
//|   build to verify RUNTIME behaviour instead of only compilation.      |
//|                                                                  |
//|   It returns INIT_FAILED on purpose: the checks have already run by    |
//|   then, and failing initialisation guarantees the tester stops        |
//|   immediately rather than simulating ticks. No order is ever sent.    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Runs the production integration assertions headlessly"

#include <ScalpRobotPro/Tests/ProductionCheck.mqh>

//+------------------------------------------------------------------+
int OnInit(void)
  {
   RunProductionCheck();
   //--- Deliberate: stop the pass now that the assertions are done.
   return(INIT_FAILED);
  }
//+------------------------------------------------------------------+
void OnTick(void)
  {
  }
//+------------------------------------------------------------------+
