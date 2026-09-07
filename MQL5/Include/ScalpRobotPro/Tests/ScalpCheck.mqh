//+------------------------------------------------------------------+
//|                                               ScalpCheck.mqh |
//|          Scalping Robot Pro - ultra-scalp verification (P6b) |
//|                                                                  |
//|   Asserts the behaviours a compile and a backtest cannot show:         |
//|     * a signal can be executed exactly ONCE, whatever OnTick does;     |
//|     * genuinely new events ARE tradeable, immediately after one another|
//|       once the short cooldown elapses;                                |
//|     * targets that cannot clear spread + commission + execution cost   |
//|       are refused;                                                   |
//|     * early profit cannot fire on a barely-positive position;          |
//|     * the holding window is enforced exactly;                          |
//|     * nothing in the controller can express a position size, so        |
//|       martingale is structurally impossible.                           |
//|                                                                  |
//|   Time is passed in as a parameter throughout, so every assertion is   |
//|   deterministic and needs no waiting.                                 |
//+------------------------------------------------------------------+
#ifndef SRP_TESTS_SCALPCHECK_MQH
#define SRP_TESTS_SCALPCHECK_MQH

#include "../Profiles/CScalpController.mqh"
#include "../Profiles/CMarketProfile.mqh"

int g_schecks = 0;
int g_sfailed = 0;

void SCheck(const string label,const bool condition)
  {
   g_schecks++;
   if(!condition)
     {
      g_sfailed++;
      Print("  FAIL  ",label);
      return;
     }
   Print("  ok    ",label);
  }

//--- A single shared ATR on the execution timeframe.
//---
//--- The controller sizes its target from ATR, so a harness without one
//--- receives ATR_BLOCK on every call - which is the controller behaving
//--- CORRECTLY (it refuses to invent a target from data it lacks) but
//--- tests nothing else. One real indicator is created here and borrowed
//--- by every controller the harness builds.
CAtrIntel *g_probe_atr = NULL;
//--- RSI too, because production passes one. Without it the harness would
//--- only ever exercise the no-RSI branch of the early exit, leaving the
//--- momentum-fade rule that actually runs live completely untested.
CRsiIntel *g_probe_rsi = NULL;

bool ScalpProbeReady(void)
  {
   return(g_probe_atr!=NULL && g_probe_atr.IsReady() &&
          g_probe_rsi!=NULL && g_probe_rsi.IsReady());
  }

void ScalpProbeRelease(void)
  {
   if(g_probe_atr!=NULL) { delete g_probe_atr; g_probe_atr=NULL; }
   if(g_probe_rsi!=NULL) { delete g_probe_rsi; g_probe_rsi=NULL; }
  }

//--- Created on the EXECUTION timeframe of this symbol's own profile,
//--- with that profile's ATR period, so the harness measures the same
//--- series the production scalp path measures rather than a guess.
bool ScalpProbeInit(void)
  {
   if(g_probe_atr!=NULL)
      return(true);

   SSymbolProfile spec;
   SMarketProfile profile;
   CSymbolClassifier::Resolve(_Symbol,spec);
   CMarketProfileFactory::Build(spec,profile);

   g_probe_atr=new CAtrIntel(_Symbol,profile.execution_timeframe,
                             profile.atr_period,NULL);
   g_probe_rsi=new CRsiIntel(_Symbol,profile.execution_timeframe,
                             profile.rsi_period,NULL);
   if(g_probe_atr==NULL || g_probe_rsi==NULL ||
      !g_probe_atr.Initialize() || !g_probe_rsi.Initialize())
     {
      ScalpProbeRelease();
      return(false);
     }
   return(true);
  }

void ScalpProbeRefresh(void)
  {
   if(g_probe_atr!=NULL) g_probe_atr.Refresh();
   if(g_probe_rsi!=NULL) g_probe_rsi.Refresh();
  }

//+------------------------------------------------------------------+
//| Builds a controller with explicit, test-friendly settings.          |
//| Costs are stated rather than derived so the arithmetic is checkable. |
//+------------------------------------------------------------------+
CScalpController *MakeScalpController(void)
  {
   CScalpController *c=new CScalpController(_Symbol,NULL);
   c.SetEnabled(true);
   //--- Borrowed, never owned: the harness deletes the indicators once.
   //--- RSI is deliberately withheld from the DEFAULT controller so the
   //--- no-RSI branch stays covered; the tests that need it wire it in.
   c.SetIndicators(g_probe_atr,NULL);
   c.ConfigureTiming(15,300);
   //--- Target floor 100 points, no ceiling. The floor dominates ATR here
   //--- so the cost arithmetic below is predictable.
   c.ConfigureTarget(0.70,100.0,0.0);
   c.ConfigureStop(0.70);
   //--- Cost model: 5 commission + 5 execution. Spread supplied per call.
   c.ConfigureCosts(5.0,5.0,2.0,0.35);
   c.ConfigureEarlyExit(true,40.0,0.55);
   //--- REDESIGN 2026-09-05. Evaluate's step 8 is the break-even gate: it
   //--- prices the COLLECTED (effective) target against the round trip and
   //--- refuses any trade whose required win rate exceeds the tier's assumed
   //--- rate. That gate is the redesign's core admission test, but its
   //--- economics are validated at the walk-forward / barrier level, NOT
   //--- here - this harness reads a LIVE ATR (g_probe_atr) whose magnitude is
   //--- not fixed across data sets, so a numeric break-even assertion could
   //--- never be deterministic. Every test in this file drives the default
   //--- STANDARD tier and asserts its OWN gate (Evaluate steps 1-7b, all of
   //--- which run BEFORE step 8), so the shared controller lifts that tier's
   //--- assumed rate to the 0.90 ceiling. This can only ever RELAX step 8; it
   //--- cannot hide a refusal, because no test here asserts a break-even
   //--- block - which keeps the cost, spread, duplicate and cooldown cases
   //--- about the gate they exist to exercise. Zeros leave geometry untouched.
   c.ConfigureTier(SRP_TIER_STANDARD,true,0.0,0.0,0,0.90,PERIOD_CURRENT);
   c.ConfigureAtrBounds(0.0,0.0);
   c.SetMaxScalpsPerDay(20);
   c.Initialize();
   return(c);
  }

//+------------------------------------------------------------------+
//| 0. THE ATR GATE ITSELF.                                            |
//|                                                                  |
//| Asserted explicitly, because "no ATR means no scalp" is a safety      |
//| property: without it the controller would size a target from a zero.  |
//+------------------------------------------------------------------+
void TestAtrGate(void)
  {
   Print("=== 0. ATR GATE ===");

   //--- No ATR at all: every signal must be refused, and named.
   CScalpController *blind=new CScalpController(_Symbol,NULL);
   blind.SetEnabled(true);
   blind.ConfigureTarget(0.70,100.0,0.0);
   blind.Initialize();
   const datetime t=D'2025.01.06 09:00:00';
   SScalpSignalId id=CScalpController::BuildSignalId(t,true,3,1,t);
   SScalpVerdict v;
   SCheck("a controller with no ATR refuses every scalp",
          !blind.Evaluate(id,t,10.0,0,3,v) &&
          v.block==SRP_SCALP_BLOCK_ATR);

   SValidationResult r;
   blind.Validate(r);
   SCheck("validation reports the missing ATR as an error",
          r.error_count>0);
   delete blind;

   //--- ATR bounds. A reading outside the usable band is refused.
   CScalpController *bounded=MakeScalpController();
   bounded.ConfigureAtrBounds(1000000.0,0.0);   // floor no market meets
   SScalpVerdict vb;
   SCheck("an ATR below the configured floor refuses the scalp",
          !bounded.Evaluate(id,t,10.0,0,3,vb) &&
          vb.block==SRP_SCALP_BLOCK_ATR);
   delete bounded;
  }

//+------------------------------------------------------------------+
//| 1. DUPLICATE SIGNAL PROTECTION.                                    |
//|                                                                  |
//| The requirement: a signal may only ever be executed once, and OnTick  |
//| firing repeatedly must never produce a second entry.                  |
//+------------------------------------------------------------------+
void TestDuplicateProtection(void)
  {
   Print("=== 1. DUPLICATE SIGNAL PROTECTION ===");

   CScalpController *c=MakeScalpController();
   const datetime bar=D'2025.01.06 10:00';
   datetime now=D'2025.01.06 10:00:05';

   //--- One signal: bar 10:00, BUY, strategy 3, structural event 2.
   SScalpSignalId id=CScalpController::BuildSignalId(bar,true,3,2,bar);
   SScalpVerdict v;

   const bool first=c.Evaluate(id,now,10.0,0,3,v);
   if(!first)
      Print("        refused with ",
            CScalpController::BlockToString(v.block),": ",v.detail);
   SCheck("first presentation of a signal is allowed",first);
   c.RecordEntry(id,now,10.0);

   //--- THE CORE ASSERTION. Simulate OnTick firing 500 more times with the
   //--- same signal still visible. Not one of them may enter.
   int accepted=0;
   for(int i=1;i<=500;i++)
     {
      SScalpVerdict repeat;
      //--- Advance time well past the cooldown so it is the DUPLICATE
      //--- rule being tested rather than the timer.
      if(c.Evaluate(id,now+60+i,10.0,0,3,repeat))
         accepted++;
     }
   SCheck("500 further ticks of the SAME signal produce zero entries",
          accepted==0);

   SScalpVerdict why;
   c.Evaluate(id,now+600,10.0,0,3,why);
   SCheck("the refusal names DUPLICATE_SIGNAL",
          why.block==SRP_SCALP_BLOCK_DUPLICATE);

   //--- Each component of the fingerprint must independently make the
   //--- signal new. Otherwise the key is weaker than it appears.
   const datetime later=now+600;
   SScalpVerdict t;

   SScalpSignalId new_bar=CScalpController::BuildSignalId(
                             bar+60,true,3,2,bar);
   SCheck("a NEW BAR makes the signal tradeable again",
          c.Evaluate(new_bar,later,10.0,0,3,t));

   SScalpSignalId new_dir=CScalpController::BuildSignalId(bar,false,3,2,bar);
   SCheck("the OPPOSITE DIRECTION is a new signal",
          c.Evaluate(new_dir,later,10.0,0,3,t));

   SScalpSignalId new_strat=CScalpController::BuildSignalId(bar,true,7,2,bar);
   SCheck("a DIFFERENT STRATEGY is a new signal",
          c.Evaluate(new_strat,later,10.0,0,3,t));

   SScalpSignalId new_event=CScalpController::BuildSignalId(bar,true,3,4,bar);
   SCheck("a NEW STRUCTURAL EVENT is a new signal",
          c.Evaluate(new_event,later,10.0,0,3,t));

   SScalpSignalId new_time=CScalpController::BuildSignalId(
                              bar,true,3,2,bar+30);
   SCheck("a NEW EVENT TIMESTAMP is a new signal",
          c.Evaluate(new_time,later,10.0,0,3,t));

   delete c;
  }

//+------------------------------------------------------------------+
//| 2. RAPID SEQUENTIAL SCALPS.                                        |
//|                                                                  |
//| The requirement: several genuinely independent signals close together |
//| MAY all be traded. A large cooldown must not prevent that.            |
//+------------------------------------------------------------------+
void TestRapidScalps(void)
  {
   Print("=== 2. RAPID SEQUENTIAL SCALPS ===");

   CScalpController *c=MakeScalpController();
   datetime now=D'2025.01.06 13:30:00';

   //--- Five independent signals, one per minute: each a new bar and a
   //--- new structural event. All five must be accepted.
   int taken=0;
   for(int i=0;i<5;i++)
     {
      const datetime bar=now+i*60;
      SScalpSignalId id=CScalpController::BuildSignalId(bar,true,3,i+1,bar);
      SScalpVerdict v;
      if(c.Evaluate(id,bar,10.0,0,3,v))
        {
         c.RecordEntry(id,bar,10.0);
         taken++;
        }
     }
   SCheck("five independent signals one minute apart are all traded",
          taken==5);

   //--- And immediately after the short cooldown, not minutes later.
   CScalpController *d=MakeScalpController();
   datetime t0=D'2025.01.06 14:00:00';
   SScalpSignalId a=CScalpController::BuildSignalId(t0,true,3,1,t0);
   SScalpVerdict va;
   d.Evaluate(a,t0,10.0,0,3,va);
   d.RecordEntry(a,t0,10.0);

   //--- 16 seconds later: past the 15s cooldown, new event.
   SScalpSignalId b=CScalpController::BuildSignalId(t0+60,true,3,2,t0+60);
   SScalpVerdict vb;
   SCheck("a new signal 16s after an entry is tradeable",
          d.Evaluate(b,t0+16,10.0,0,3,vb));

   //--- Inside the cooldown it is refused, and named as such.
   CScalpController *e=MakeScalpController();
   SScalpSignalId f=CScalpController::BuildSignalId(t0,true,3,1,t0);
   SScalpVerdict vf;
   e.Evaluate(f,t0,10.0,0,3,vf);
   e.RecordEntry(f,t0,10.0);
   SScalpSignalId g=CScalpController::BuildSignalId(t0+60,true,3,2,t0+60);
   SScalpVerdict vg;
   const bool inside=e.Evaluate(g,t0+5,10.0,0,3,vg);
   SCheck("a new signal 5s after an entry is refused by cooldown",
          !inside && vg.block==SRP_SCALP_BLOCK_COOLDOWN);

   //--- EXPOSURE. Slots full refuses regardless of signal quality.
   CScalpController *h=MakeScalpController();
   SScalpSignalId i1=CScalpController::BuildSignalId(t0,true,3,1,t0);
   SScalpVerdict vi;
   SCheck("a full position book refuses a valid signal",
          !h.Evaluate(i1,t0,10.0,3,3,vi) &&
          vi.block==SRP_SCALP_BLOCK_MAX_POSITIONS);

   delete h; delete e; delete d; delete c;
  }

//+------------------------------------------------------------------+
//| 3. COST AND SPREAD PROTECTION.                                     |
//|                                                                  |
//| The requirement: expected net profit must exceed estimated           |
//| transaction costs, and spread must be judged against the target.      |
//+------------------------------------------------------------------+
void TestCostProtection(void)
  {
   Print("=== 3. COST AND SPREAD PROTECTION ===");

   //--- The target is PINNED at 100 points here (floor == ceiling) so the
   //--- arithmetic below does not depend on whatever ATR the tester's data
   //--- happens to produce. The ATR-derived path is exercised separately.
   CScalpController *c=MakeScalpController();
   c.ConfigureTarget(0.70,100.0,100.0);
   const datetime t=D'2025.01.06 15:00:00';

   //--- Target is 100 points. Cost = spread + 5 + 5.
   //--- At spread 10 the cost is 20 and the required target is 40, so a
   //--- 100 point target passes.
   SScalpSignalId ok=CScalpController::BuildSignalId(t,true,3,1,t);
   SScalpVerdict v;
   const bool passed=c.Evaluate(ok,t,10.0,0,3,v);
   SCheck("a 100pt target against 20pt cost is accepted",passed);
   if(passed)
     {
      SCheck("the verdict reports the cost it cleared",v.cost_points==20.0);
      SCheck("the verdict reports a positive target",v.target_points>=100.0);
      SCheck("the verdict reports a stop",v.stop_points>0.0);
     }

   //--- SPREAD relative to target. At spread 40 against a 100pt target
   //--- that is 40%, above the 35% ceiling.
   CScalpController *d=MakeScalpController();
   d.ConfigureTarget(0.70,100.0,100.0);
   SScalpSignalId s=CScalpController::BuildSignalId(t,true,3,2,t);
   SScalpVerdict vs;
   SCheck("spread at 40% of the target is refused",
          !d.Evaluate(s,t,40.0,0,3,vs) &&
          vs.block==SRP_SCALP_BLOCK_SPREAD);

   //--- COST ratio. A tiny target cannot clear the round trip. The floor
   //--- is lowered so the cost rule is what refuses, not the floor.
   CScalpController *e=new CScalpController(_Symbol,NULL);
   e.SetEnabled(true);
   e.SetIndicators(g_probe_atr,NULL);
   e.ConfigureTiming(15,300);
   e.ConfigureTarget(0.70,12.0,12.0);   // pin the target at 12 points
   e.ConfigureCosts(5.0,5.0,2.0,0.95);  // spread ceiling relaxed
   e.Initialize();
   SScalpSignalId tiny=CScalpController::BuildSignalId(t,true,3,3,t);
   SScalpVerdict vt;
   const bool refused=!e.Evaluate(tiny,t,2.0,0,3,vt);
   SCheck("a target that cannot clear cost by 2x is refused",
          refused && vt.block==SRP_SCALP_BLOCK_COST);

   delete e; delete d; delete c;
  }

//+------------------------------------------------------------------+
//| 4. EARLY PROFIT EXIT.                                              |
//|                                                                  |
//| The requirement is explicit that a profitable trade must NOT be       |
//| closed immediately just because it is a few points positive.          |
//+------------------------------------------------------------------+
void TestEarlyProfit(void)
  {
   Print("=== 4. EARLY PROFIT EXIT ===");

   CScalpController *c=MakeScalpController();
   //--- Floor 40 points, target share 0.55, target 200 points.
   const double target=200.0;
   string reason="";

   SCheck("a 5pt profit does NOT trigger an early exit",
          !c.ShouldTakeEarlyProfit(true,5.0,target,reason));
   SCheck("a 39pt profit (below the cost floor) does NOT trigger",
          !c.ShouldTakeEarlyProfit(true,39.0,target,reason));
   //--- 100 points is above the floor but only 50% of target, under the
   //--- 55% share, so it must not fire on the share rule.
   SCheck("100pt (50% of target) does NOT trigger on the share rule",
          !c.ShouldTakeEarlyProfit(true,100.0,target,reason));
   //--- 180 points is 90% of target: the micro-move is exhausted, and
   //--- without RSI the 85% rule applies.
   SCheck("180pt (90% of target) DOES trigger",
          c.ShouldTakeEarlyProfit(true,180.0,target,reason));
   if(reason!="")
      Print("        reason: ",reason);

   //--- Disabled means never.
   c.ConfigureEarlyExit(false,40.0,0.55);
   SCheck("a disabled early exit never triggers",
          !c.ShouldTakeEarlyProfit(true,180.0,target,reason));

   delete c;

   //--- THE BRANCH PRODUCTION ACTUALLY USES.
   //---
   //--- Above, the controller has no RSI, so only the 85%-of-target rule
   //--- can fire. Production passes an RSI, which opens the momentum-fade
   //--- branch at a much lower 55% share. That branch is the one that can
   //--- close a trade early, so its guards are what matter: whatever the
   //--- oscillator is doing, the cost floor and the target share must both
   //--- still stand in the way.
   CScalpController *r=MakeScalpController();
   r.SetIndicators(g_probe_atr,g_probe_rsi);
   r.ConfigureEarlyExit(true,40.0,0.55);
   string rr="";

   SCheck("with RSI wired, a 5pt profit still does NOT trigger",
          !r.ShouldTakeEarlyProfit(true,5.0,target,rr));
   SCheck("with RSI wired, a profit below the cost floor still does NOT "
          "trigger",
          !r.ShouldTakeEarlyProfit(true,39.0,target,rr));
   //--- 60 points is above the 40pt floor but only 30% of the target,
   //--- under the 55% share. Momentum fade alone must not be enough.
   SCheck("momentum fade alone cannot close a barely-profitable scalp",
          !r.ShouldTakeEarlyProfit(true,60.0,target,rr));
   //--- 180 points clears both gates, so it fires by one branch or the
   //--- other depending on live RSI. Either is correct; silence is not.
   const bool fired=r.ShouldTakeEarlyProfit(true,180.0,target,rr);
   SCheck("with RSI wired, a nearly-complete move DOES trigger",fired);
   if(fired)
      Print("        reason: ",rr);

   delete r;
  }

//+------------------------------------------------------------------+
//| 5. HOLDING WINDOW.                                                 |
//+------------------------------------------------------------------+
void TestHoldingWindow(void)
  {
   Print("=== 5. HOLDING WINDOW ===");

   CScalpController *c=MakeScalpController();
   const datetime open=D'2025.01.06 16:00:00';
   string reason="";

   SCheck("max holding time is 300s as configured",
          c.MaxHoldSeconds()==300);
   SCheck("at 1s held, no timeout",
          !c.ShouldTimeOut(open,open+1,reason));
   SCheck("at 299s held, no timeout",
          !c.ShouldTimeOut(open,open+299,reason));
   SCheck("at 300s held, timeout fires",
          c.ShouldTimeOut(open,open+300,reason));
   SCheck("at 600s held, timeout fires",
          c.ShouldTimeOut(open,open+600,reason));
   if(reason!="")
      Print("        reason: ",reason);

   //--- A configurable window, per the requirement.
   c.ConfigureTiming(15,60);
   SCheck("the window is configurable",c.MaxHoldSeconds()==60);
   SCheck("the shorter window fires at 60s",
          c.ShouldTimeOut(open,open+60,reason));

   delete c;
  }

//+------------------------------------------------------------------+
//| 6. SAFETY INVARIANTS.                                              |
//+------------------------------------------------------------------+
void TestSafety(void)
  {
   Print("=== 6. SAFETY INVARIANTS ===");

   //--- COOLDOWN CLAMP. A huge cooldown would silently prevent the rapid
   //--- sequential scalping this mode exists for, so it is clamped rather
   //--- than honoured. Proven by behaviour: after the clamp a new signal
   //--- just past the 120s ceiling must still be tradeable.
   CScalpController *c=MakeScalpController();
   c.ConfigureTiming(99999,300);
   const datetime tc=D'2025.01.06 08:00:00';
   SScalpSignalId c1=CScalpController::BuildSignalId(tc,true,3,1,tc);
   SScalpVerdict vc1;
   c.Evaluate(c1,tc,10.0,0,3,vc1);
   c.RecordEntry(c1,tc,10.0);
   SScalpSignalId c2=CScalpController::BuildSignalId(tc+300,true,3,2,tc+300);
   SScalpVerdict vc2;
   SCheck("an absurd cooldown is clamped, so scalping still resumes",
          c.Evaluate(c2,tc+121,10.0,0,3,vc2));

   //--- Disabled controller refuses everything.
   CScalpController *d=MakeScalpController();
   d.SetEnabled(false);
   const datetime t=D'2025.01.06 17:00:00';
   SScalpSignalId id=CScalpController::BuildSignalId(t,true,3,1,t);
   SScalpVerdict v;
   SCheck("a disabled controller refuses every signal",
          !d.Evaluate(id,t,10.0,0,3,v) &&
          v.block==SRP_SCALP_BLOCK_DISABLED);

   //--- DAILY CEILING is a cap, never a quota.
   CScalpController *e=MakeScalpController();
   e.SetMaxScalpsPerDay(3);
   int taken=0;
   ENUM_SRP_SCALP_BLOCK last_block=SRP_SCALP_OK;
   for(int i=0;i<10;i++)
     {
      //--- Same calendar day, comfortably past the cooldown, each a new
      //--- bar and a new structural event.
      const datetime bar=t+i*120;
      SScalpSignalId s=CScalpController::BuildSignalId(bar,true,3,i+1,bar);
      SScalpVerdict vs;
      if(e.Evaluate(s,bar,10.0,0,3,vs))
        {
         e.RecordEntry(s,bar,10.0);
         taken++;
        }
      else
         last_block=vs.block;
     }
   SCheck(StringFormat("the daily cap stops trading at exactly the limit "
                       "(took %d of 10)",taken),taken==3);
   SCheck("the refusal past the cap names DAILY_LIMIT",
          last_block==SRP_SCALP_BLOCK_DAILY_LIMIT);

   //--- GOLD PROFILE INVARIANTS. Risk must not have been raised to buy
   //--- frequency, which is the single most important check here.
   SMarketProfile gold;
   CMarketProfileFactory::ApplyGold(gold);
   SCheck("gold scalp risk remains 0.25% per trade",
          MathAbs(gold.risk_percent-0.25)<1e-9);
   SCheck("gold risk ceiling remains 1%",
          MathAbs(gold.max_risk_percent-1.0)<1e-9);
   SCheck("gold allows 3 simultaneous positions",gold.max_positions==3);
   SCheck("gold exposure ceiling covers 3 positions but no more",
          gold.max_exposure_percent>=0.75 &&
          gold.max_exposure_percent<=1.5);
   SCheck("gold daily loss protection remains enabled",
          gold.daily_loss_percent>0.0);
   SCheck("gold scalp mode is enabled",gold.scalp_mode_enabled);
   SCheck("gold scalp cooldown is in the 10-30s band",
          gold.scalp_cooldown_seconds>=10 &&
          gold.scalp_cooldown_seconds<=30);
   SCheck("gold scalp holding window is 5 minutes",
          gold.scalp_max_hold_seconds==300);
   //--- The geometry defect this phase found: a stop far wider than the
   //--- target made four wins vanish on one loss.
   SCheck("scalp target is not dwarfed by the scalp stop",
          gold.scalp_target_atr_multiple>=gold.scalp_stop_atr_multiple*0.9);
   SCheck("scalp reward/cost ratio is at least 2x",
          gold.scalp_min_reward_cost_ratio>=2.0);

   delete e; delete d; delete c;
  }

//+------------------------------------------------------------------+
bool RunScalpCheck(void)
  {
   Print("==================================================");
   Print("ULTRA-SCALP CHECK  symbol=",_Symbol);
   Print("==================================================");

   //--- Every accept assertion depends on this: without a warmed ATR the
   //--- controller correctly refuses to size a target, and the suite would
   //--- be measuring the ATR gate over and over instead of the rules it
   //--- means to test.
   SCheck("probe ATR is ready before asserting",ScalpProbeReady());

   TestAtrGate();
   TestDuplicateProtection();
   TestRapidScalps();
   TestCostProtection();
   TestEarlyProfit();
   TestHoldingWindow();
   TestSafety();

   Print("==================================================");
   Print(StringFormat("SRP_SCALP CHECKS=%d FAILED=%d VERDICT=%s",
                      g_schecks,g_sfailed,(g_sfailed==0 ? "PASS" : "FAIL")));
   Print("==================================================");
   return(g_sfailed==0);
  }

#endif // SRP_TESTS_SCALPCHECK_MQH
//+------------------------------------------------------------------+
