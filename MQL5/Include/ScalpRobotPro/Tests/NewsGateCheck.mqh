//+------------------------------------------------------------------+
//|                                            NewsGateCheck.mqh |
//|          Scalping Robot Pro - news gate precedence (P7) |
//|                                                                  |
//|   THE DEFECT THESE TESTS EXIST FOR                                   |
//|                                                                  |
//|   A live run took ZERO trades in five hours of moving market. Every    |
//|   chart reported `declines by reason: NEWS_BLOCKED=<all>` and the      |
//|   accuracy filter showed "never evaluated", i.e. the pipeline stopped   |
//|   at news before any strategy was polled. Four separate faults, each   |
//|   sufficient on its own:                                             |
//|                                                                  |
//|     1. CProductionEngine NEVER CALLED CNewsEngine::SetEnabled, so      |
//|        InpNewsFilterEnabled=false was inert - identical in shape to    |
//|        the session-filter defect fixed just before this one.          |
//|     2. LoadFromCalendar returned `ArraySize(m_events)>0`, so a WORKING  |
//|        calendar with no relevant events reported "unavailable". The    |
//|        live fail-safe then blocked everything. A quiet calendar day    |
//|        was indistinguishable from a broken feed, and the quiet day is  |
//|        exactly when trading should proceed.                           |
//|     3. The blackout windows were never applied, so the engine kept its  |
//|        built-in 60/60 CRITICAL and 30/30 HIGH instead of the           |
//|        configured 20/20 - up to three times too wide.                 |
//|     4. The currency filter was never applied AND SRuntimeConfig never  |
//|        declared the field, so every event in every currency was        |
//|        treated as affecting gold.                                     |
//|                                                                  |
//|   Each assertion targets BEHAVIOUR - "can a refusal occur" - because   |
//|   every one of these values was already being stored correctly.        |
//+------------------------------------------------------------------+
#ifndef SRP_TESTS_NEWSGATECHECK_MQH
#define SRP_TESTS_NEWSGATECHECK_MQH

//--- CTimeUtils first: CNewsEngine uses it for countdown formatting but
//--- does not include it, so it only compiles where something earlier in
//--- the translation unit happened to pull it in. Included explicitly here
//--- rather than relying on that ordering.
#include "../Utilities/CTimeUtils.mqh"
#include "../Decision/News/CNewsEngine.mqh"
#include "../Profiles/CMarketProfile.mqh"
#include "../Runtime/CRuntimeConfig.mqh"

int g_nchecks = 0;
int g_nfailed = 0;

void NCheck(const string label,const bool condition)
  {
   g_nchecks++;
   if(!condition)
     {
      g_nfailed++;
      Print("  FAIL  ",label);
      return;
     }
   Print("  ok    ",label);
  }

//--- A news engine with NO source reachable: no calendar, no CSV. This is
//--- the state the live engine was effectively in.
CNewsEngine *MakeBlindNews(const bool enabled,const bool fail_safe)
  {
   CNewsEngine *n=new CNewsEngine(_Symbol,NULL);
   n.SetEnabled(enabled);
   n.SetSource(false,false,"");        // nothing to load from
   n.SetMinimumSeverity(SRP_NEWS_SEV_HIGH);
   n.SetFailSafeBlock(fail_safe);
   n.Initialize();
   return(n);
  }

#define SRP_N_NOW  D'2025.01.08 09:00:00'

//+------------------------------------------------------------------+
//| 1. THE REPORTED BUG: filter disabled must never block.              |
//+------------------------------------------------------------------+
void TestNewsDisabledNeverBlocks(void)
  {
   Print("=== 1. NEWS FILTER DISABLED => NEWS_BLOCKED IMPOSSIBLE ===");

   //--- Disabled, no source, and the fail-safe set to BLOCK - the most
   //--- hostile combination. Disabled must still win outright.
   CNewsEngine *n=MakeBlindNews(false,true);
   n.Refresh(SRP_N_NOW,true);
   n.Evaluate(SRP_N_NOW);
   SNewsState st;
   n.GetState(st);
   NCheck("disabled + no source + fail-safe BLOCK still permits trading",
          st.trading_permitted);
   NCheck("a disabled filter reports itself as disabled",
          StringFind(st.detail,"disabled")>=0);

   //--- Across a full day, minute by minute: not one refusal.
   int refused=0;
   for(int m=0;m<1440;m++)
     {
      const datetime moment=SRP_N_NOW+m*60;
      n.Refresh(moment,false);
      n.Evaluate(moment);
      if(!n.IsTradingPermitted())
         refused++;
     }
   NCheck(StringFormat("1440 minutes with the filter off, %d refusals",refused),
          refused==0);
   delete n;
  }

//+------------------------------------------------------------------+
//| 2. THE FAIL-SAFE, AND THE EMPTY-CALENDAR BUG.                       |
//+------------------------------------------------------------------+
void TestFailSafeSemantics(void)
  {
   Print("=== 2. FAIL-SAFE AND SOURCE AVAILABILITY ===");

   //--- Enabled, genuinely no source, fail-safe BLOCK: refusing is CORRECT.
   //--- This is the behaviour that must survive the fix.
   CNewsEngine *block=MakeBlindNews(true,true);
   block.Refresh(SRP_N_NOW,true);
   block.Evaluate(SRP_N_NOW);
   NCheck("no source + fail-safe BLOCK refuses (correct, conservative)",
          !block.IsTradingPermitted());
   NCheck("and reports the source as unavailable",
          !block.SourceAvailable());
   delete block;

   //--- Enabled, no source, fail-safe ALLOW: permitted, and said plainly.
   CNewsEngine *allow=MakeBlindNews(true,false);
   allow.Refresh(SRP_N_NOW,true);
   allow.Evaluate(SRP_N_NOW);
   NCheck("no source + fail-safe ALLOW permits, as configured",
          allow.IsTradingPermitted());
   delete allow;

   //--- THE EMPTY-CALENDAR CASE, tested through the CSV path because a
   //--- terminal calendar cannot be synthesised here.
   //---
   //--- A file that opens and parses but contains NO events relevant to
   //--- this symbol must count as AVAILABLE. Before the fix both loaders
   //--- returned ArraySize(m_events)>0, so this exact situation reported
   //--- "unavailable" and the live fail-safe blocked every tick.
   const string path="srp_newsgate_empty.csv";
   int h=FileOpen(path,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h!=INVALID_HANDLE)
     {
      FileWrite(h,"# no events relevant to this symbol");
      //--- A real event, but in a currency the filter excludes.
      FileWrite(h,"2025.01.08 12:00;JPY;3;Some Tokyo Release");
      FileClose(h);

      CNewsEngine *empty=new CNewsEngine(_Symbol,NULL);
      empty.SetEnabled(true);
      empty.SetSource(false,true,path);
      empty.SetMinimumSeverity(SRP_NEWS_SEV_HIGH);
      empty.SetCurrencyFilter("USD");      // excludes the JPY event
      empty.SetFailSafeBlock(true);        // would block if "unavailable"
      empty.Initialize();
      empty.Refresh(SRP_N_NOW,true);
      empty.Evaluate(SRP_N_NOW);

      NCheck("a readable source with no RELEVANT events counts as available",
             empty.SourceAvailable());
      NCheck("and therefore does NOT trip the fail-safe",
             empty.IsTradingPermitted());
      NCheck("no events were retained after currency filtering",
             empty.EventCount()==0);
      delete empty;
      FileDelete(path);
     }
   else
      NCheck("could not create the temporary CSV for the empty-source test",
             false);
  }

//+------------------------------------------------------------------+
//| 3. A REAL BLACKOUT STILL BLOCKS, AND ONLY IN ITS WINDOW.            |
//|                                                                  |
//| The fix must not have removed news protection, only stopped it firing  |
//| permanently. These are the assertions that would catch that.           |
//+------------------------------------------------------------------+
void TestRealBlackoutStillBlocks(void)
  {
   Print("=== 3. A REAL EVENT STILL BLOCKS ===");

   const string path="srp_newsgate_event.csv";
   int h=FileOpen(path,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
     {
      NCheck("could not create the temporary CSV for the blackout test",false);
      return;
     }
   //--- A HIGH-severity USD release at 13:30.
   //---
   //--- GDP, which the name classifier maps to HIGH.
   //---
   //--- Deliberately NOT NFP/FOMC/CPI/rates: those are promoted to CRITICAL
   //--- by name whatever the calendar flag says, and would exercise the
   //--- wider critical window instead of the HIGH one under test. Nor PMI or
   //--- retail sales, which are classified MEDIUM and would be discarded
   //--- below the HIGH minimum severity set on this engine.
   FileWrite(h,"2025.01.08 13:30;USD;3;GDP q/q");
   FileClose(h);

   CNewsEngine *n=new CNewsEngine(_Symbol,NULL);
   n.SetEnabled(true);
   n.SetSource(false,true,path);
   n.SetMinimumSeverity(SRP_NEWS_SEV_HIGH);
   n.SetCurrencyFilter("USD,XAU");
   //--- The gold profile's configured window, which the engine now applies
   //--- instead of its built-in 60/60.
   n.SetCriticalWindow(30,30);
   n.SetHighWindow(20,20);
   n.SetMediumWindow(10,10);
   n.SetFailSafeBlock(true);
   n.Initialize();
   n.Refresh(D'2025.01.08 09:00:00',true);

   NCheck("the event was loaded",n.EventCount()>=1);

   //--- Confirm the severity this case is actually testing, so a future
   //--- change to the name classifier fails HERE with a clear reason rather
   //--- than as an unexplained window-width mismatch below.
   SNewsItem loaded;
   if(n.GetEvent(0,loaded))
      NCheck(StringFormat("the event is HIGH, not promoted to CRITICAL "
                          "(severity=%s)",
                          CNewsEngine::SeverityToString(loaded.severity)),
             loaded.severity==SRP_NEWS_SEV_HIGH);

   //--- Inside the blackout: refused.
   n.Evaluate(D'2025.01.08 13:25:00');
   NCheck("five minutes before a high-impact release, trading is refused",
          !n.IsTradingPermitted());
   n.Evaluate(D'2025.01.08 13:35:00');
   NCheck("five minutes after it, trading is still refused",
          !n.IsTradingPermitted());

   //--- OUTSIDE the blackout: permitted. This is the half that was broken.
   n.Evaluate(D'2025.01.08 09:00:00');
   NCheck("four hours before the release, trading is permitted",
          n.IsTradingPermitted());
   n.Evaluate(D'2025.01.08 18:00:00');
   NCheck("four hours after it, trading is permitted",
          n.IsTradingPermitted());

   //--- THE WINDOW IS THE CONFIGURED ONE, not the built-in default.
   //---
   //--- This is the assertion that pins the third defect. The engine's own
   //--- default HIGH window is 30/30; the configuration asks for 20/20. At
   //--- 25 minutes before the release the configured window has not opened
   //--- but the old hardcoded default would already be blocking, so this
   //--- distinguishes the two directly.
   n.Evaluate(D'2025.01.08 13:05:00');
   NCheck("25 minutes before, the configured 20-minute window has not "
          "started (the unapplied 30-minute default would have blocked)",
          n.IsTradingPermitted());
   n.Evaluate(D'2025.01.08 13:15:00');
   NCheck("15 minutes before, the configured window IS in force",
          !n.IsTradingPermitted());

   //--- Across a whole day, ONE 20/20 event must block ~41 minutes - the
   //--- 20 before, the 20 after, and the release minute itself. The point
   //--- of the bound is that a single event cannot cover a session; before
   //--- the fix the gate refused 100% of the day.
   int refused=0;
   for(int m=0;m<1440;m++)
     {
      const datetime moment=D'2025.01.08 00:00:00'+m*60;
      n.Evaluate(moment);
      if(!n.IsTradingPermitted())
         refused++;
     }
   NCheck(StringFormat("one 20/20 event blocks ~41 of 1440 minutes, not the "
                       "whole day (measured %d)",refused),
          refused>=38 && refused<=45);

   delete n;
   FileDelete(path);
  }

//+------------------------------------------------------------------+
//| 4. THE CONFIGURATION CHAIN.                                        |
//|                                                                  |
//| The currency filter reached the config store and stopped: the runtime  |
//| struct never declared the field. A value that cannot be read is        |
//| indistinguishable from one that was never set.                        |
//+------------------------------------------------------------------+
void TestConfigChainComplete(void)
  {
   Print("=== 4. CONFIGURATION REACHES THE ENGINE ===");

   SSymbolProfile spec;
   spec.resolved=true; spec.asset_class=SRP_ASSET_METAL_GOLD;
   spec.point=0.01; spec.digits=2; spec.tick_size=0.01;
   spec.volume_min=0.01; spec.volume_step=0.01;
   spec.spread_current=41.0; spec.spread_float=1; spec.stops_level=0;

   SMarketProfile gold;
   CMarketProfileFactory::Build(spec,gold);

   NCheck("gold ships a currency filter",
          gold.news_currency_filter!="");
   NCheck("gold's filter names both USD and XAU",
          StringFind(gold.news_currency_filter,"USD")>=0 &&
          StringFind(gold.news_currency_filter,"XAU")>=0);
   NCheck("gold ships a bounded blackout window",
          gold.news_minutes_before>0 && gold.news_minutes_before<=60 &&
          gold.news_minutes_after>0  && gold.news_minutes_after<=60);

   //--- The runtime config must now DECLARE the field, with a usable
   //--- default. Before this fix the name did not compile.
   SRuntimeConfig rc;
   rc.Reset();
   NCheck("SRuntimeConfig declares a news currency filter with a default",
          rc.news_currency_filter!="");

   //--- An engine given the profile's filter must EXCLUDE a foreign event
   //--- and RETAIN a relevant one. Asserted by behaviour, since the filter
   //--- has no getter and a stored value proves nothing.
   const string path="srp_newsgate_ccy.csv";
   int h=FileOpen(path,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE)
     {
      NCheck("could not create the temporary CSV for the currency test",false);
      return;
     }
   FileWrite(h,"2025.01.08 13:30;USD;3;US High Impact Release");
   FileWrite(h,"2025.01.08 14:30;JPY;3;Tokyo High Impact Release");
   FileWrite(h,"2025.01.08 15:30;AUD;3;Sydney High Impact Release");
   FileClose(h);

   CNewsEngine *n=new CNewsEngine(_Symbol,NULL);
   n.SetEnabled(true);
   n.SetSource(false,true,path);
   n.SetMinimumSeverity(SRP_NEWS_SEV_HIGH);
   n.SetCurrencyFilter(gold.news_currency_filter);   // "USD,XAU"
   n.Initialize();
   n.Refresh(SRP_N_NOW,true);
   NCheck(StringFormat("the profile's filter keeps only the relevant event "
                       "(kept %d of 3)",n.EventCount()),
          n.EventCount()==1);
   delete n;
   FileDelete(path);
  }

//+------------------------------------------------------------------+
bool RunNewsGateCheck(void)
  {
   Print("==================================================");
   Print("NEWS GATE PRECEDENCE CHECK  symbol=",_Symbol);
   Print("==================================================");

   TestNewsDisabledNeverBlocks();
   TestFailSafeSemantics();
   TestRealBlackoutStillBlocks();
   TestConfigChainComplete();

   Print("==================================================");
   Print(StringFormat("SRP_NEWSGATE CHECKS=%d FAILED=%d VERDICT=%s",
                      g_nchecks,g_nfailed,(g_nfailed==0 ? "PASS" : "FAIL")));
   Print("==================================================");
   return(g_nfailed==0);
  }

#endif // SRP_TESTS_NEWSGATECHECK_MQH
//+------------------------------------------------------------------+
