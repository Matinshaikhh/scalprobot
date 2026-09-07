//+------------------------------------------------------------------+
//|                                              VolumeProbe.mqh |
//|        Scalping Robot Pro - what volume does this feed report? |
//|                                                                  |
//|   MEASUREMENT, NOT A TEST. It answers one question before any code    |
//|   depends on the answer: does this broker report REAL volume on        |
//|   XAUUSD, or only tick volume?                                       |
//|                                                                  |
//|   WHY IT MATTERS. Most FX and metals feeds report real volume as       |
//|   zero. Building a volume-confirmed entry filter on a zero series      |
//|   would not fail loudly - CheckVolume would simply return             |
//|   UNAVAILABLE forever, the confirmation denominator would shrink,      |
//|   and the filter would appear to be working while contributing        |
//|   nothing. That is exactly the class of silent inertness this          |
//|   project has already been bitten by twice.                          |
//|                                                                  |
//|   So the series is inspected first and the finding is reported as a    |
//|   fact rather than assumed from documentation.                        |
//+------------------------------------------------------------------+
#ifndef SRP_TESTS_VOLUMEPROBE_MQH
#define SRP_TESTS_VOLUMEPROBE_MQH

#include "../Intelligence/Indicators/CComputedIndicators.mqh"

int g_vchecks = 0;
int g_vfailed = 0;

void VCheck(const string label,const bool condition)
  {
   g_vchecks++;
   if(!condition)
     {
      g_vfailed++;
      Print("  FAIL  ",label);
      return;
     }
   Print("  ok    ",label);
  }

//+------------------------------------------------------------------+
//| Reports the raw series straight from the terminal, per timeframe.   |
//+------------------------------------------------------------------+
void ProbeRawVolume(const ENUM_TIMEFRAMES tf,const string name)
  {
   long   tick_v[];
   long   real_v[];
   const int want=200;

   const int got_tick=CopyTickVolume(_Symbol,tf,0,want,tick_v);
   const int got_real=CopyRealVolume(_Symbol,tf,0,want,real_v);

   long tick_sum=0, real_sum=0;
   int  tick_nonzero=0, real_nonzero=0;
   for(int i=0;i<got_tick;i++)
     {
      tick_sum+=tick_v[i];
      if(tick_v[i]>0) tick_nonzero++;
     }
   for(int i=0;i<got_real;i++)
     {
      real_sum+=real_v[i];
      if(real_v[i]>0) real_nonzero++;
     }

   Print(StringFormat("  %s: tick bars=%d nonzero=%d mean=%.1f | "
                      "real bars=%d nonzero=%d mean=%.1f",
                      name,
                      got_tick,tick_nonzero,
                      (got_tick>0 ? (double)tick_sum/got_tick : 0.0),
                      got_real,real_nonzero,
                      (got_real>0 ? (double)real_sum/got_real : 0.0)));

   //--- Tick volume is the usable proxy and MUST be present, or no volume
   //--- filter of any kind can work on this instrument.
   VCheck(StringFormat("%s reports usable tick volume",name),
          got_tick>0 && tick_nonzero>got_tick/2);
}

//+------------------------------------------------------------------+
//| Exercises the indicator the product actually uses.                 |
//+------------------------------------------------------------------+
void ProbeVolumeIndicator(const ENUM_TIMEFRAMES tf,const string name)
  {
   CVolumeIndicator *v=new CVolumeIndicator(_Symbol,tf,NULL,VOLUME_TICK);
   if(v==NULL)
     {
      VCheck(name+": indicator could not be created",false);
      return;
     }
   if(!v.Initialize())
     {
      VCheck(name+": indicator failed to initialise",false);
      delete v;
      return;
     }
   //--- Warm up: the cache fills from history, so a few refreshes are
   //--- enough on a symbol whose bars already exist.
   for(int i=0;i<5;i++)
      v.Refresh();

   VCheck(name+": volume indicator reports ready",v.IsReady());

   double relative=0.0;
   const bool ok=v.RelativeVolume(20,relative);
   VCheck(StringFormat("%s: relative volume resolves (x%.2f)",name,relative),
          ok && relative>0.0);

   //--- The number the confirmation engine compares against its floor.
   //--- If this sits far below 1.0 on average, a floor of 0.8 would reject
   //--- most bars and the "volume filter" would be a trade blocker rather
   //--- than a quality filter.
   Print(StringFormat("  %s: relative volume now = x%.3f",name,relative));
   delete v;
  }

//+------------------------------------------------------------------+
bool RunVolumeProbe(void)
  {
   Print("==================================================");
   Print("VOLUME FEED PROBE  symbol=",_Symbol);
   Print("==================================================");

   //--- What the broker declares about its own volume support.
   const long calc_mode=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_CALC_MODE);
   Print("  symbol calc mode = ",calc_mode);

   Print("--- raw series ---");
   ProbeRawVolume(PERIOD_M1,"M1");
   ProbeRawVolume(PERIOD_M5,"M5");
   ProbeRawVolume(PERIOD_M15,"M15");

   Print("--- product indicator ---");
   ProbeVolumeIndicator(PERIOD_M1,"M1");
   ProbeVolumeIndicator(PERIOD_M5,"M5");
   ProbeVolumeIndicator(PERIOD_M15,"M15");

   Print("==================================================");
   Print(StringFormat("SRP_VOLUME CHECKS=%d FAILED=%d VERDICT=%s",
                      g_vchecks,g_vfailed,(g_vfailed==0 ? "PASS" : "FAIL")));
   Print("==================================================");
   return(g_vfailed==0);
  }

#endif // SRP_TESTS_VOLUMEPROBE_MQH
//+------------------------------------------------------------------+
