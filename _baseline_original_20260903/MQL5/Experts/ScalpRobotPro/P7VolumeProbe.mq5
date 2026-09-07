//+------------------------------------------------------------------+
//|                                          P7VolumeProbe.mq5 |
//|      Scalping Robot Pro - volume feed probe, tester-launchable |
//|                                                                  |
//|   VERIFICATION ARTEFACT, NOT A PRODUCT FILE. No order is ever sent.  |
//|                                                                  |
//|   Runs in OnTick so the volume cache can warm from real bars, then    |
//|   stops the pass itself. Requires a tick model (-Model 1 or better).  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Reports what volume data this feed provides"

#include <ScalpRobotPro/Tests/VolumeProbe.mqh>

bool g_vdone  = false;
int  g_vticks = 0;

int OnInit(void)
  {
   return(INIT_SUCCEEDED);
  }

void OnTick(void)
  {
   if(g_vdone)
      return;
   //--- A short warm-up so the M15 series has closed bars to report on.
   if(++g_vticks < 500)
      return;

   RunVolumeProbe();
   g_vdone=true;
   TesterStop();
  }
//+------------------------------------------------------------------+
