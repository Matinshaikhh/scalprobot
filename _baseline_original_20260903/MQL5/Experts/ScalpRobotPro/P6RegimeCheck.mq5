//+------------------------------------------------------------------+
//|                                          P6RegimeCheck.mq5 |
//|       Scalping Robot Pro - regime verification, tester-launchable |
//|                                                                  |
//|   VERIFICATION ARTEFACT, NOT A PRODUCT FILE. No order is ever sent.  |
//|                                                                  |
//|   WHY THIS ONE RUNS IN OnTick RATHER THAN OnInit                     |
//|   The other harnesses do all their work in OnInit and then fail        |
//|   initialisation. This one cannot: indicators gate on BarsCalculated,  |
//|   which is still warming up at OnInit, so the interesting half of the  |
//|   regime engine - actually classifying live data - would never be      |
//|   reached. So it ticks until the context indicators report READY,      |
//|   runs the assertions once, and then stops the pass itself.           |
//|                                                                  |
//|   Verifying only the warm-up path would prove almost nothing.         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "Verifies the regime and volatility engine"

#include <ScalpRobotPro/Tests/RegimeCheck.mqh>

//--- Probe indicators used solely to detect readiness before asserting.
CAdxIntel *g_probe_adx = NULL;
CAtrIntel *g_probe_atr = NULL;
bool       g_done      = false;
int        g_ticks     = 0;

int OnInit(void)
  {
   //--- The static, terminal-independent groups can run immediately.
   Print("==================================================");
   Print("REGIME & VOLATILITY CHECK  symbol=",_Symbol);
   Print("==================================================");
   TestPermissionTable();
   TestVolatilityThresholds();

   //--- Readiness probes on the context timeframe of this symbol's profile.
   SSymbolProfile spec;
   SMarketProfile profile;
   CSymbolClassifier::Resolve(_Symbol,spec);
   CMarketProfileFactory::Build(spec,profile);

   g_probe_adx=new CAdxIntel(_Symbol,profile.context_timeframe,
                             profile.adx_period,NULL);
   g_probe_atr=new CAtrIntel(_Symbol,profile.context_timeframe,
                             profile.atr_period,NULL);
   if(g_probe_adx==NULL || g_probe_atr==NULL ||
      !g_probe_adx.Initialize() || !g_probe_atr.Initialize())
     {
      Print("  FAIL  probe indicators could not be created");
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }

void OnTick(void)
  {
   if(g_done)
      return;
   g_ticks++;

   g_probe_adx.Refresh();
   g_probe_atr.Refresh();

   //--- Wait for genuine readiness, then assert once. The cap stops a
   //--- run that never warms up from ticking forever.
   if(!(g_probe_adx.IsReady() && g_probe_atr.IsReady()) && g_ticks<200000)
      return;

   Print("  note  asserting after ",g_ticks," ticks; adx=",
         EnumToString(g_probe_adx.State()),
         " atr=",EnumToString(g_probe_atr.State()));

   TestLiveRegime();

   Print("==================================================");
   Print(StringFormat("SRP_REGIME CHECKS=%d FAILED=%d VERDICT=%s",
                      g_rchecks,g_rfailed,(g_rfailed==0 ? "PASS" : "FAIL")));
   Print("==================================================");

   g_done=true;
   //--- Stop the pass: the assertions are complete and further ticks
   //--- would only add noise.
   TesterStop();
  }

void OnDeinit(const int reason)
  {
   if(g_probe_atr!=NULL) { delete g_probe_atr; g_probe_atr=NULL; }
   if(g_probe_adx!=NULL) { delete g_probe_adx; g_probe_adx=NULL; }
  }
//+------------------------------------------------------------------+
