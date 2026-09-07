//+------------------------------------------------------------------+
//|                                           P6ScalpCheck.mq5 |
//|        Scalping Robot Pro - ultra-scalp check, tester-launchable |
//|                                                                  |
//|   VERIFICATION ARTEFACT, NOT A PRODUCT FILE. No order is ever sent.  |
//|                                                                  |
//|   WHY THIS ONE RUNS IN OnTick RATHER THAN OnInit                     |
//|   The scalp controller sizes its target from ATR and refuses outright  |
//|   when it has none - correctly, since inventing a target from a zero   |
//|   would be worse than declining. At OnInit the indicator is still      |
//|   warming up, so asserting there would prove only that the ATR gate    |
//|   works and nothing about duplicate suppression, cost protection or    |
//|   the exit rules. So it ticks until the probe reports READY, runs the  |
//|   assertions once, and stops the pass itself.                         |
//|                                                                  |
//|   Requires a tick model: run with -Model 1 or better.                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Verifies ultra-scalp duplicate protection, costs and exits"

#include <ScalpRobotPro/Tests/ScalpCheck.mqh>

bool g_sdone  = false;
int  g_sticks = 0;

int OnInit(void)
  {
   if(!ScalpProbeInit())
     {
      Print("  FAIL  probe ATR could not be created");
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }

void OnTick(void)
  {
   if(g_sdone)
      return;
   g_sticks++;

   ScalpProbeRefresh();

   //--- Wait for genuine readiness. The cap stops a run that never warms
   //--- up from ticking forever; the suite then reports the failure of the
   //--- readiness assertion rather than hanging.
   if(!ScalpProbeReady() && g_sticks<200000)
      return;

   Print("  note  asserting after ",g_sticks," ticks");
   RunScalpCheck();

   g_sdone=true;
   //--- Assertions complete; further ticks would only add noise.
   TesterStop();
  }

void OnDeinit(const int reason)
  {
   ScalpProbeRelease();
  }
//+------------------------------------------------------------------+
