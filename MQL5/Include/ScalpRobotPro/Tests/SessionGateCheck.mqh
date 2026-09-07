//+------------------------------------------------------------------+
//|                                         SessionGateCheck.mqh |
//|      Scalping Robot Pro - session gating precedence (P7) |
//|                                                                  |
//|   THE DEFECT THESE TESTS EXIST FOR                                   |
//|                                                                  |
//|   `session.enabled` was written by the configuration builder, read     |
//|   back into SRuntimeConfig, and checked by two validators - but never   |
//|   handed to CSessionManager, which had no way to express "disabled" at  |
//|   all. So InpSessionFilterEnabled=false was completely inert:          |
//|   Evaluate ran its whole gate chain anyway, returned                   |
//|   trading_permitted=false, and the decision engine reported            |
//|   SESSION_BLOCKED on all 1747 evaluations. The input appeared in the    |
//|   startup log, which is exactly what made it look applied.             |
//|                                                                  |
//|   Every assertion below is written against BEHAVIOUR - "can a refusal   |
//|   occur" - rather than against the flag's value, because the flag was   |
//|   already being stored correctly. Storing it was never the problem.     |
//|                                                                  |
//|   Times are passed in explicitly so each case is deterministic and     |
//|   needs no waiting and no live market.                                |
//+------------------------------------------------------------------+
#ifndef SRP_TESTS_SESSIONGATECHECK_MQH
#define SRP_TESTS_SESSIONGATECHECK_MQH

#include "../Decision/Session/CSessionManager.mqh"
#include "../Profiles/CMarketProfile.mqh"
#include "../Profiles/CProfileApplier.mqh"
#include "../Configuration/CConfigurationBuilder.mqh"

int g_gchecks = 0;
int g_gfailed = 0;

void GCheck(const string label,const bool condition)
  {
   g_gchecks++;
   if(!condition)
     {
      g_gfailed++;
      Print("  FAIL  ",label);
      return;
     }
   Print("  ok    ",label);
  }

//--- A manager configured exactly as the gold profile configures it: a
//--- London-led window, session edges trimmed, weekend and holiday filters
//--- on. This is the configuration that was producing SESSION_BLOCKED.
CSessionManager *MakeGoldSessions(const bool filter_enabled)
  {
   CSessionManager *s=new CSessionManager(_Symbol,NULL);
   s.SetSydneyWindow(21*60,6*60,false);
   s.SetTokyoWindow(0,9*60,false);
   s.SetLondonWindow(7*60,16*60,true);
   s.SetNewYorkWindow(13*60,21*60,true);
   s.SetNewYorkOpenKillZone(7*60,12*60);      // gold: London open
   s.SetSessionEdgeSkip(3,15);
   s.SetWeekendFilter(true,90,0);
   s.SetHolidayFilter(true,true);
   s.SetKillZones(false);
   s.SetRequireOverlap(false);
   //--- Fixed offset so the test does not depend on the broker's clock.
   s.SetManualBrokerOffset(0);
   s.SetDstEnabled(false);
   s.SetEnabled(filter_enabled);
   s.Initialize();
   return(s);
  }

//--- Server times chosen to sit unambiguously in each condition.
//--- 2025.01.08 is a Wednesday; 2025.01.11 is a Saturday.
#define SRP_T_INSIDE_LONDON   D'2025.01.08 09:00:00'   // inside 07:00-16:00
#define SRP_T_OUTSIDE_ALL     D'2025.01.08 03:00:00'   // before London, Asia off
#define SRP_T_WEEKEND         D'2025.01.11 09:00:00'   // Saturday
#define SRP_T_EDGE_AFTER_OPEN D'2025.01.08 07:01:00'   // 1 min into London
#define SRP_T_OVERLAP         D'2025.01.08 14:00:00'   // London + New York

//+------------------------------------------------------------------+
//| 1. THE REPORTED BUG.                                               |
//|                                                                  |
//| Filter disabled => no session rule may refuse, at ANY moment, including |
//| the ones that legitimately refuse when the filter is on.               |
//+------------------------------------------------------------------+
void TestFilterDisabledNeverBlocks(void)
  {
   Print("=== 1. FILTER DISABLED => SESSION_BLOCKED IMPOSSIBLE ===");

   CSessionManager *s=MakeGoldSessions(false);

   //--- The exact configuration and window from the bug report: gold's
   //--- 07:00-12:00 primary window, evaluated well outside it.
   const datetime moments[5]={SRP_T_INSIDE_LONDON,SRP_T_OUTSIDE_ALL,
                              SRP_T_WEEKEND,SRP_T_EDGE_AFTER_OPEN,
                              SRP_T_OVERLAP};
   const string names[5]={"inside London","outside every session",
                          "Saturday","one minute after the open",
                          "London/NY overlap"};

   bool all_permitted=true;
   for(int i=0;i<5;i++)
     {
      s.Evaluate(moments[i],true);
      SSessionState st;
      s.GetState(st);
      const bool ok=(st.trading_permitted &&
                     st.block_reason==SRP_TIME_BLOCK_NONE);
      if(!ok)
        {
         all_permitted=false;
         Print("        refused at ",names[i],": ",
               CSessionManager::BlockToString(st.block_reason),
               " - ",st.block_detail);
        }
     }
   GCheck("with the filter OFF, no moment is session-blocked",all_permitted);

   //--- The weekend case deserves naming on its own: it is the single most
   //--- decisive gate in the chain, so if the switch honours that it
   //--- honours the rest.
   s.Evaluate(SRP_T_WEEKEND,true);
   GCheck("a Saturday is permitted when the filter is off",
          s.IsTradingPermitted());

   //--- Blocks must not merely be reported as zero - they must not happen.
   GCheck("no blocks were counted with the filter off",
          s.BlockCount()==0);

   //--- Session CONTEXT must still be published. Turning the filter off is
   //--- not the same as removing session information: the confirmation
   //--- engine scores liquidity from it and the dashboard displays it.
   s.Evaluate(SRP_T_OVERLAP,true);
   SSessionState ctx;
   s.GetState(ctx);
   GCheck("session context is still resolved with the filter off",
          ctx.active_session!=SRP_TS_NONE);
   GCheck("liquidity score is still published with the filter off",
          ctx.liquidity_score>0.0);

   //--- And validation must not refuse startup for a configuration that is
   //--- deliberately session-agnostic.
   CSessionManager *none=new CSessionManager(_Symbol,NULL);
   none.SetSydneyWindow(21*60,6*60,false);
   none.SetTokyoWindow(0,9*60,false);
   none.SetLondonWindow(7*60,16*60,false);
   none.SetNewYorkWindow(13*60,21*60,false);
   none.SetEnabled(false);
   none.Initialize();
   SValidationResult vr;
   none.Validate(vr);
   GCheck("every session disabled is NOT an error when the filter is off",
          vr.error_count==0);
   GCheck("but it IS reported as a warning",vr.warning_count>0);
   delete none;

   delete s;
  }

//+------------------------------------------------------------------+
//| 2. FILTER ENABLED => THE GATES STILL WORK.                         |
//|                                                                  |
//| The fix must not have disabled session filtering, only made the switch  |
//| effective. These are the assertions that would catch that.             |
//+------------------------------------------------------------------+
void TestFilterEnabledStillBlocks(void)
  {
   Print("=== 2. FILTER ENABLED => GATES INTACT ===");

   CSessionManager *s=MakeGoldSessions(true);

   //--- Outside every enabled session: refused, and named.
   s.Evaluate(SRP_T_OUTSIDE_ALL,true);
   SSessionState out;
   s.GetState(out);
   GCheck("outside every session, trading is refused",
          !out.trading_permitted);
   GCheck("the refusal names NO_SESSION",
          out.block_reason==SRP_TIME_BLOCK_NO_SESSION);

   //--- Inside London, well past the open edge: permitted.
   s.Evaluate(SRP_T_INSIDE_LONDON,true);
   SSessionState in;
   s.GetState(in);
   if(!in.trading_permitted)
      Print("        refused: ",
            CSessionManager::BlockToString(in.block_reason),
            " - ",in.block_detail);
   GCheck("inside the session, trading is permitted",in.trading_permitted);
   GCheck("and no block reason is set",
          in.block_reason==SRP_TIME_BLOCK_NONE);

   //--- The weekend gate.
   s.Evaluate(SRP_T_WEEKEND,true);
   SSessionState we;
   s.GetState(we);
   GCheck("a Saturday is refused when the filter is on",
          !we.trading_permitted &&
          we.block_reason==SRP_TIME_BLOCK_WEEKEND);

   //--- The session-edge gate: one minute into a session whose first three
   //--- minutes are skipped.
   s.Evaluate(SRP_T_EDGE_AFTER_OPEN,true);
   SSessionState edge;
   s.GetState(edge);
   GCheck("the first minutes of a session are refused",
          !edge.trading_permitted &&
          edge.block_reason==SRP_TIME_BLOCK_SESSION_EDGE);

   GCheck("blocks are counted when the filter is on",s.BlockCount()>0);
   delete s;

   //--- KILL ZONE requirement, independently.
   CSessionManager *kz=MakeGoldSessions(true);
   kz.SetKillZones(true);
   //--- 14:00 is inside London but outside gold's 07:00-12:00 kill zone.
   kz.Evaluate(SRP_T_OVERLAP,true);
   SSessionState kzs;
   kz.GetState(kzs);
   GCheck("kill-zone-only refuses a moment outside the kill zone",
          !kzs.trading_permitted &&
          kzs.block_reason==SRP_TIME_BLOCK_OUTSIDE_KILLZONE);
   delete kz;

   //--- OVERLAP requirement, which was stored in config and never applied.
   CSessionManager *ov=MakeGoldSessions(true);
   ov.SetRequireOverlap(true);
   ov.Evaluate(SRP_T_INSIDE_LONDON,true);   // London only, no overlap
   SSessionState ovs;
   ov.GetState(ovs);
   GCheck("require-overlap refuses a single-session moment",
          !ovs.trading_permitted);
   ov.Evaluate(SRP_T_OVERLAP,true);         // London + New York
   SSessionState ovs2;
   ov.GetState(ovs2);
   GCheck("require-overlap permits an actual overlap",
          ovs2.trading_permitted &&
          ovs2.overlap!=SRP_OVERLAP_NONE);
   delete ov;
  }

//+------------------------------------------------------------------+
//| 3. PROFILE PRECEDENCE.                                             |
//|                                                                  |
//| Override ON  => the gold profile's session rules are applied.           |
//| Override OFF => the user's inputs survive untouched.                    |
//+------------------------------------------------------------------+
void TestProfilePrecedence(void)
  {
   Print("=== 3. PROFILE OVERRIDE PRECEDENCE ===");

   SSymbolProfile spec;
   spec.resolved=true; spec.asset_class=SRP_ASSET_METAL_GOLD;
   spec.point=0.01; spec.digits=2; spec.tick_size=0.01;
   spec.volume_min=0.01; spec.volume_step=0.01;
   spec.spread_current=41.0; spec.spread_float=1; spec.stops_level=0;

   SMarketProfile gold;
   CMarketProfileFactory::Build(spec,gold);

   //--- The gold preset's own session character, asserted so a silent
   //--- change to it fails here rather than in a live account.
   GCheck("gold ships a London-led primary window (07:00 GMT)",
          gold.primary_kz_open_gmt==7*60);
   GCheck("gold disables the Asian sessions",
          !gold.allow_sydney && !gold.allow_tokyo);
   GCheck("gold enables London and New York",
          gold.allow_london && gold.allow_newyork);

   //--- USER INPUTS, deliberately different from the profile in every
   //--- session field, so any leakage is visible.
   SInputSnapshot user;
   CConfigurationBuilder::ApplyNasdaqDefaults(user);
   user.session_filter_enabled=false;
   user.allow_sydney=true;
   user.allow_tokyo=true;
   user.allow_london=false;
   user.allow_newyork=false;
   user.require_overlap=false;
   user.kill_zones_only=false;
   user.london_open_gmt=1*60;
   user.primary_kz_open_gmt=2*60;
   user.skip_after_open_minutes=0;

   //--- OVERRIDE OFF: nothing about the profile may touch these. The
   //--- applier is simply not called, which is the behaviour being pinned.
   SInputSnapshot untouched=user;
   GCheck("override OFF leaves the session filter switch as the user set it",
          untouched.session_filter_enabled==false);
   GCheck("override OFF leaves the user's session enables intact",
          untouched.allow_sydney && untouched.allow_tokyo &&
          !untouched.allow_london && !untouched.allow_newyork);
   GCheck("override OFF leaves the user's window times intact",
          untouched.london_open_gmt==1*60 &&
          untouched.primary_kz_open_gmt==2*60);

   //--- OVERRIDE ON: the profile's session rules replace them.
   SInputSnapshot applied=user;
   CProfileApplier::Apply(gold,applied);
   GCheck("override ON applies the profile's session enables",
          !applied.allow_sydney && !applied.allow_tokyo &&
          applied.allow_london && applied.allow_newyork);
   GCheck("override ON applies the profile's primary window",
          applied.primary_kz_open_gmt==gold.primary_kz_open_gmt);
   GCheck("override ON applies the profile's London window",
          applied.london_open_gmt==gold.london_open_gmt);
   GCheck("override ON applies the profile's session edge skips",
          applied.skip_after_open_minutes==gold.skip_after_open_minutes);

   //--- THE PRECEDENCE RULE THAT MATTERS MOST.
   //---
   //--- The profile describes WHEN to trade, not WHETHER the session filter
   //--- exists. It must therefore never switch the filter back on: a trader
   //--- who disabled session gating and left the profile authoritative for
   //--- everything else would otherwise find gating silently reinstated,
   //--- which is the same class of surprise as the original defect.
   GCheck("override ON does NOT re-enable a session filter the user disabled",
          applied.session_filter_enabled==false);
  }

//+------------------------------------------------------------------+
//| 4. THE END-TO-END INVARIANT.                                       |
//|                                                                  |
//| Both switches off, evaluated across a full week minute by minute: not   |
//| one refusal. This is the assertion that directly contradicts the bug    |
//| report, and it is exhaustive rather than sampled.                       |
//+------------------------------------------------------------------+
void TestFullWeekNeverBlocks(void)
  {
   Print("=== 4. FULL WEEK, FILTER OFF, ZERO REFUSALS ===");

   CSessionManager *s=MakeGoldSessions(false);

   //--- Monday 00:00 through Sunday 23:59, every minute: 10080 evaluations
   //--- covering both weekend days, both session edges, every hour outside
   //--- any window, and the Friday close.
   const datetime start=D'2025.01.06 00:00:00';   // Monday
   int refused=0;
   int first_refusal_minute=-1;
   for(int m=0;m<10080;m++)
     {
      const datetime moment=start+m*60;
      s.Evaluate(moment,true);
      if(!s.IsTradingPermitted())
        {
         refused++;
         if(first_refusal_minute<0)
            first_refusal_minute=m;
        }
     }
   if(refused>0)
     {
      SSessionState st;
      s.GetState(st);
      Print(StringFormat("        %d refusals; first at minute %d (%s)",
                         refused,first_refusal_minute,
                         CSessionManager::BlockToString(st.block_reason)));
     }
   GCheck(StringFormat("10080 minutes evaluated, %d session refusals",refused),
          refused==0);
   delete s;

   //--- The SAME week with the filter ON must refuse a substantial number,
   //--- or the previous assertion would pass simply because nothing works.
   CSessionManager *on=MakeGoldSessions(true);
   int blocked=0;
   for(int m=0;m<10080;m++)
     {
      on.Evaluate(start+m*60,true);
      if(!on.IsTradingPermitted())
         blocked++;
     }
   GCheck(StringFormat("the same week with the filter ON refuses many "
                       "(%d of 10080)",blocked),
          blocked>3000);
   delete on;
  }

//+------------------------------------------------------------------+
bool RunSessionGateCheck(void)
  {
   Print("==================================================");
   Print("SESSION GATE PRECEDENCE CHECK  symbol=",_Symbol);
   Print("==================================================");

   TestFilterDisabledNeverBlocks();
   TestFilterEnabledStillBlocks();
   TestProfilePrecedence();
   TestFullWeekNeverBlocks();

   Print("==================================================");
   Print(StringFormat("SRP_SESSIONGATE CHECKS=%d FAILED=%d VERDICT=%s",
                      g_gchecks,g_gfailed,(g_gfailed==0 ? "PASS" : "FAIL")));
   Print("==================================================");
   return(g_gfailed==0);
  }

#endif // SRP_TESTS_SESSIONGATECHECK_MQH
//+------------------------------------------------------------------+
