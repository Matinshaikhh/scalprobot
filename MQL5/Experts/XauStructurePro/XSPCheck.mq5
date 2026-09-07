//+------------------------------------------------------------------+
//|                                                     XSPCheck.mq5 |
//|          XauStructurePro - self-test, tester-launchable, no orders |
//|                                                                  |
//|   VERIFICATION ARTEFACT, NOT A PRODUCT FILE. No order function is      |
//|   compiled in and no CTrade is included, so this EA cannot place a     |
//|   trade even if the tester is pointed at a live-like account.          |
//|                                                                  |
//|   THIS RUNS BEFORE THE STUDY, AND THE STUDY IS NOT QUOTABLE UNTIL IT   |
//|   PASSES. Phase A's whole output is one CSV of per-instance records;   |
//|   if the barrier tracker mismeasures an excursion, or the row builder  |
//|   is off by one column, or one market event yields two instances, then |
//|   every number the analysis prints afterwards is wrong in a way no     |
//|   amount of re-cutting can reveal. The four assertions the plan        |
//|   requires are all here: one event yields exactly one instance while   |
//|   price stays beyond the level (the defect-2 regression); barriers     |
//|   resolve correctly for monotone-up, monotone-down and straddling      |
//|   tick sequences; MFE and MAE never move the wrong way; a buy is       |
//|   filled at the ask and a sell at the bid.                            |
//|                                                                  |
//|   WHY IT ASSERTS IN OnTick AND NOT IN OnInit. The suite's              |
//|   history-dependent blocks need an ATR at shift 1, two confirmed       |
//|   swings on each side of M15, an H1 class derived from two swings and   |
//|   a pool list. None of that exists at OnInit, when the indicator is    |
//|   still warming up. So it ticks until the probe reports READY, runs    |
//|   the suite once, and stops the pass itself.                          |
//|                                                                  |
//|   Requires a tick model: run with -Model 1 or better. Real ticks       |
//|   (Model 4) are preferred, since the spread the regime ranks is then   |
//|   the broker's own rather than a generated one.                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "XauStructurePro self-test: event identity, barriers, schema"

#include <XauStructurePro/Tests/XspCheck.mqh>

bool g_xdone  = false;
int  g_xticks = 0;

//--- The cap stops a run that never warms up from ticking to the end of
//--- the pass in silence. When it fires the suite still runs, and the
//--- readiness assertions below are what report the failure.
#define XSP_CHECK_TICK_CAP 200000

int OnInit(void)
  {
   if(!XspProbeInit())
     {
      Print("  FAIL  probe could not be created");
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }

void OnTick(void)
  {
   if(g_xdone)
      return;
   g_xticks++;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   XspProbeRefresh(tick);

   if(!XspProbeReady() && g_xticks<XSP_CHECK_TICK_CAP)
      return;

   PrintFormat("  note  asserting after %d ticks",g_xticks);
   //--- Recorded as assertions rather than as a bare log line: a suite that
   //--- ran against a cold probe would report PASS for every synthetic
   //--- block and silently skip what the live-history ones prove.
   XCheck("the probe warmed up before the suite ran",XspProbeReady());
   XCheck("and it did so inside the tick cap",g_xticks<XSP_CHECK_TICK_CAP);

   RunXspCheck();

   g_xdone=true;
   //--- Assertions complete; further ticks would only add noise.
   TesterStop();
  }

void OnDeinit(const int reason)
  {
   XspProbeRelease();
  }
//+------------------------------------------------------------------+
