//+------------------------------------------------------------------+
//|                                                      XspCheck.mqh |
//|        XauStructurePro - Tests : the instrument must be verified |
//|                                          BEFORE it measures anything |
//|                                                                  |
//|   WHY THIS FILE EXISTS AT ALL. Phase A's whole output is one CSV, and   |
//|   every conclusion drawn from it inherits the correctness of the        |
//|   recorder that wrote it. A compile proves the syntax; a backtest       |
//|   proves nothing at all, because a tracker that mis-resolves barriers   |
//|   produces a perfectly plausible file. The audit's 1,221-trade result   |
//|   was wrong for exactly that reason - the numbers looked like numbers.  |
//|                                                                  |
//|   THE FOUR ASSERTIONS THE PLAN REQUIRES, all present below:            |
//|     1. one event -> exactly one instance across repeated evaluations   |
//|        while price stays beyond the level  (the DEFECT-2 REGRESSION)   |
//|     2. barrier resolution on monotone-up, monotone-down and            |
//|        straddling synthetic tick sequences                            |
//|     3. MFE never decreases and MAE never increases                    |
//|     4. buy is filled at ASK and sell at BID                           |
//|                                                                  |
//|   Everything here is DETERMINISTIC where it can be. The tracker, the   |
//|   event registry, the statistics and the row builder are fed synthetic |
//|   inputs, so those assertions need no market at all. Three blocks -    |
//|   pools, S2 and the tick-volume baseline - read live history because   |
//|   they cannot be tested without it; they assert INVARIANTS of whatever |
//|   the tape produced rather than specific values, so they are still     |
//|   deterministic in the only sense that matters: they cannot pass on a  |
//|   broken build and fail on a working one.                             |
//|                                                                  |
//|   NO ORDER FUNCTION IS CALLED OR INCLUDED HERE.                       |
//+------------------------------------------------------------------+
#ifndef XSP_TESTS_XSPCHECK_MQH
#define XSP_TESTS_XSPCHECK_MQH

#include "../Core/XspTypes.mqh"
#include "../Core/CXspStats.mqh"
#include "../Context/CXspHtfContext.mqh"
#include "../Regime/CXspRegime.mqh"
#include "../Liquidity/CXspStructureEvents.mqh"
#include "../Liquidity/CXspPools.mqh"
#include "../Setups/CXspContinuation.mqh"
#include "../Setups/CXspReversal.mqh"
#include "../Setups/CXspTickVolume.mqh"
#include "../Research/CXspBarrierTracker.mqh"
#include "../Research/CXspRecorder.mqh"

int g_xchecks = 0;
int g_xfailed = 0;

void XCheck(const string label,const bool condition)
  {
   g_xchecks++;
   if(!condition)
     {
      g_xfailed++;
      Print("  FAIL  ",label);
      return;
     }
   Print("  ok    ",label);
  }

//--- Shared probes. Live-history objects, warmed by the EA before the
//--- suite runs, so no test has to wait for anything itself.
CXspRegime      *g_xregime = NULL;
CXspSwings      *g_xswings = NULL;
CXspHtfContext  *g_xcontext = NULL;
CXspPools       *g_xpools  = NULL;
double           g_xpoint  = 0.0;

//+------------------------------------------------------------------+
//| Probe lifecycle. Live-history objects only; everything else in the |
//| suite is synthetic.                                               |
//+------------------------------------------------------------------+
bool XspProbeInit(void)
  {
   if(g_xregime!=NULL) return(true);
   g_xpoint=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(g_xpoint<=0.0)
     {
      Print("  FAIL  probe cannot read SYMBOL_POINT");
      return(false);
     }
   g_xregime=new CXspRegime();
   g_xswings=new CXspSwings();
   g_xcontext=new CXspHtfContext();
   g_xpools=new CXspPools();
   if(!g_xregime.Initialize(_Symbol,XSP_TF_SETUP,g_xpoint)) return(false);
   if(!g_xswings.Initialize(_Symbol,XSP_TF_SETUP,3,300))    return(false);
   if(!g_xcontext.Initialize(_Symbol))                      return(false);
   if(!g_xpools.Initialize(_Symbol,g_xpoint))               return(false);
   return(true);
  }

void XspProbeRefresh(const MqlTick &tick)
  {
   if(g_xregime==NULL) return;
   g_xregime.ObserveTick(tick);
   g_xregime.RefreshBars();
   g_xswings.Refresh();
   g_xcontext.Refresh();
   const double atr=g_xregime.AtrPoints(1);
   if(atr>0.0)
      g_xpools.Refresh(g_xswings,XSP_POOL_TOLERANCE_ATR*atr);
  }

//--- Warm enough to assert on: an ATR at shift 1, an H1 class that had
//--- two swings to derive from, and a pool list that at minimum contains
//--- the prior day's two extremes.
bool XspProbeReady(void)
  {
   if(g_xregime==NULL) return(false);
   if(!g_xregime.IsReady())        return(false);
   if(g_xregime.AtrPoints(1)<=0.0) return(false);
   if(g_xswings.HighCount()<2 || g_xswings.LowCount()<2) return(false);
   if(g_xcontext.H1SwingHighs()<2 || g_xcontext.H1SwingLows()<2) return(false);
   if(g_xpools.Count()<2)          return(false);
   return(true);
  }

void XspProbeRelease(void)
  {
   if(g_xpools!=NULL)   { delete g_xpools;   g_xpools=NULL; }
   if(g_xcontext!=NULL) { delete g_xcontext; g_xcontext=NULL; }
   if(g_xswings!=NULL)  { delete g_xswings;  g_xswings=NULL; }
   if(g_xregime!=NULL)  { delete g_xregime;  g_xregime=NULL; }
  }

//--- A synthetic tick. Spread is a parameter because one whole test is
//--- about which side of it a buy and a sell are recorded at.
void XTick(MqlTick &t,const datetime when,const double bid,const double spread_price)
  {
   t.time=when;
   t.bid=bid;
   t.ask=bid+spread_price;
   t.last=bid;
   t.volume=1;
   t.time_msc=(long)when*1000;
   t.flags=0;
   t.volume_real=1.0;
  }

//--- One synthetic bar. Written into a plain (non-series) array whose
//--- index 0 the setups treat as the FORMING bar and index 1 as the last
//--- CLOSED one - the same convention CopyRates delivers with
//--- ArraySetAsSeries(true), reproduced by hand so no test depends on the
//--- flag being set correctly somewhere else.
void XBar(MqlRates &r[],const int i,const datetime when,
          const double open,const double high,const double low,const double close,
          const long tickvol=100)
  {
   r[i].time=when;
   r[i].open=open;
   r[i].high=high;
   r[i].low=low;
   r[i].close=close;
   r[i].tick_volume=tickvol;
   r[i].spread=10;
   r[i].real_volume=0;
  }

//--- Flat filler bars, newest first, so a window has something behind it
//--- that cannot itself trigger anything.
void XFill(MqlRates &r[],const int from,const int to,const datetime newest,
           const int period_secs,const double price)
  {
   for(int i=from;i<=to;i++)
      XBar(r,i,newest-(datetime)(i*period_secs),price,price+1.0*_Point,
           price-1.0*_Point,price);
  }

//+------------------------------------------------------------------+
//| 1. EVENT IDENTITY - the defect-2 regression.                       |
//|                                                                  |
//| The old tree's CMarketStructure re-stamped last_event_time on every |
//| evaluation for as long as price stayed beyond the level, so one      |
//| occurrence became N rows, n rose and SE fell. These assertions are   |
//| the ones that would have caught it: the same occurrence is evaluated |
//| repeatedly and must be emitted exactly once, and the STATE query is  |
//| checked to have no effect on the claim count at all.                |
//+------------------------------------------------------------------+
void TestEventIdentity(void)
  {
   CXspStructureEvents ev;
   ev.Configure(2);

   const string a=ev.Fingerprint(XSP_SETUP_REVERSAL,XSP_DIR_SELL,3400.00,(datetime)1000);
   const string b=ev.Fingerprint(XSP_SETUP_REVERSAL,XSP_DIR_SELL,3400.00,(datetime)1000);
   XCheck("fingerprint is stable for identical inputs",a==b);
   XCheck("fingerprint separates level price",
          a!=ev.Fingerprint(XSP_SETUP_REVERSAL,XSP_DIR_SELL,3400.01,(datetime)1000));
   XCheck("fingerprint separates level bar time",
          a!=ev.Fingerprint(XSP_SETUP_REVERSAL,XSP_DIR_SELL,3400.00,(datetime)1060));
   XCheck("fingerprint separates direction",
          a!=ev.Fingerprint(XSP_SETUP_REVERSAL,XSP_DIR_BUY,3400.00,(datetime)1000));
   XCheck("fingerprint separates setup",
          a!=ev.Fingerprint(XSP_SETUP_CONTINUATION,XSP_DIR_SELL,3400.00,(datetime)1000));
   //--- Sub-digit noise on two reads of one level must NOT be two levels.
   XCheck("fingerprint folds sub-digit price noise into one identity",
          a==ev.Fingerprint(XSP_SETUP_REVERSAL,XSP_DIR_SELL,3400.000000004,(datetime)1000));

   XCheck("first claim on an occurrence succeeds",ev.Claim(a));
   int refused=0;
   for(int i=0;i<64;i++)
      if(!ev.Claim(a)) refused++;
   XCheck("64 re-evaluations of ONE occurrence are all refused",refused==64);
   XCheck("claims counts occurrences not evaluations",ev.Claims()==1);
   XCheck("refusals are counted rather than hidden",ev.Refusals()==64);
   XCheck("an empty fingerprint can never be claimed",!ev.Claim(""));

   //--- STATE, and it must stay state. If IsBeyond could claim, the two
   //--- questions would be one expression again - which is the defect.
   const long before=ev.Claims();
   int beyond=0;
   for(int i=0;i<128;i++)
      if(CXspStructureEvents::IsBeyond(3401.00,3400.00,XSP_DIR_BUY)) beyond++;
   XCheck("IsBeyond answers the state question",beyond==128);
   XCheck("IsBeyond has no side effect on the claim count",ev.Claims()==before);
   XCheck("IsBeyond is strict at the level itself",
          !CXspStructureEvents::IsBeyond(3400.00,3400.00,XSP_DIR_BUY));
   XCheck("IsBeyond respects a buffer",
          !CXspStructureEvents::IsBeyond(3400.50,3400.00,XSP_DIR_BUY,1.00));
   XCheck("IsBeyond flips for the sell side",
          CXspStructureEvents::IsBeyond(3399.00,3400.00,XSP_DIR_SELL));
   XCheck("IsBeyond refuses a directionless question",
          !CXspStructureEvents::IsBeyond(3401.00,3400.00,XSP_DIR_NONE));
  }

//+------------------------------------------------------------------+
//| 2. S1 CONTINUATION, and the same regression through the template    |
//|    method that every setup must pass through.                       |
//|                                                                  |
//| Prices are built from the declared thresholds rather than typed in,  |
//| so if XSP_DISP_* ever change the test still tests the boundary and   |
//| not a stale number. Each rejection case fails exactly ONE gate: a    |
//| bar that failed two would pass this suite even if one gate were      |
//| deleted.                                                            |
//+------------------------------------------------------------------+
void TestSetupS1(void)
  {
   //--- Heap-allocated because a pointer to it is handed to the setup. An
   //--- automatic object would work through GetPointer, but a pointer whose
   //--- lifetime is explicit is one less thing for a reader to verify.
   CXspStructureEvents *ev=new CXspStructureEvents();
   ev.Configure((int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
   CXspContinuation s1;
   XCheck("S1 refuses to initialise without an event registry",
          !s1.Initialize(_Symbol,XSP_TF_SETUP,g_xpoint,NULL));
   XCheck("S1 initialises with one",s1.Initialize(_Symbol,XSP_TF_SETUP,g_xpoint,ev));

   const double atr=100.0;                       // points, synthetic
   const double range=(XSP_DISP_ATR_MULT*atr+50.0)*g_xpoint;
   const double base=3400.0;
   const datetime t1=(datetime)(D'2026.01.05 12:00:00');
   const int secs=PeriodSeconds(XSP_TF_SETUP);

   MqlRates r[];
   ArrayResize(r,8);
   XFill(r,0,7,t1+(datetime)secs,secs,base);

   //--- A clean bullish displacement: wide, body-dominant, close pinned.
   XBar(r,1,t1,base+0.05*range,base+range,base,base+0.95*range);
   SXspCandidate c;
   XCheck("S1 emits on a clean bullish displacement",s1.Evaluate(r,8,atr,c));
   XCheck("S1 direction follows the body",c.dir==XSP_DIR_BUY);
   XCheck("S1 invalidation IS the leg origin",MathAbs(c.invalidation-base)<XSP_EPSILON);
   XCheck("S1 level price IS the invalidation",
          MathAbs(c.level_price-c.invalidation)<XSP_EPSILON);
   XCheck("S1 references no liquidity pool",c.pool_kind==XSP_POOL_NONE);
   XCheck("S1 stamps the event bar time",c.event_bar_time==t1);
   XCheck("S1 carries the ATR it was measured against",
          MathAbs(c.atr_points-atr)<XSP_EPSILON);

   //=== THE DEFECT-2 REGRESSION ====================================
   //--- 200 further evaluations of the SAME closed bar - which is what an
   //--- ungated per-tick caller does, and what the old tree did on every
   //--- evaluation while price stayed beyond the level.
   int emitted_again=0;
   for(int i=0;i<200;i++)
      if(s1.Evaluate(r,8,atr,c)) emitted_again++;
   XCheck("one occurrence emits ONCE across 200 re-evaluations",emitted_again==0);
   XCheck("emitted count is 1, not 201",s1.Emitted()==1);
   XCheck("detected count records all 201 evaluations",s1.Detected()==201);
   XCheck("the 200 duplicates are counted as suppressed",s1.Suppressed()==200);
   XCheck("the registry saw exactly one occurrence",ev.Claims()==1);

   //--- A genuinely NEW occurrence is still tradeable. Without this the
   //--- suppression above could be a class that emits nothing at all.
   XBar(r,1,t1+(datetime)secs,base+0.05*range,base+range,base,base+0.95*range);
   XCheck("a new bar at the same level IS a new occurrence",s1.Evaluate(r,8,atr,c));
   XBar(r,1,t1,base+0.05*range+10*g_xpoint,base+range+10*g_xpoint,
        base+10*g_xpoint,base+0.95*range+10*g_xpoint);
   XCheck("a new level on the same bar IS a new occurrence",s1.Evaluate(r,8,atr,c));

   //--- Rejections, one failed gate each.
   const long before_detected=s1.Detected();
   XBar(r,1,t1,base+0.05*range,base+range*0.5,base,base+0.475*range);
   XCheck("S1 rejects a bar narrower than the ATR multiple",!s1.Evaluate(r,8,atr,c));
   XBar(r,1,t1,base+0.45*range,base+range,base,base+0.55*range);
   XCheck("S1 rejects a two-sided bar whose body does not dominate",
          !s1.Evaluate(r,8,atr,c));
   //--- Body ratio passes (0.61) but the close gave back the extreme (0.66).
   XBar(r,1,t1,base+0.05*range,base+range,base,base+0.66*range);
   XCheck("S1 rejects a bar that expanded and gave the extreme back",
          !s1.Evaluate(r,8,atr,c));
   XBar(r,1,t1,base+0.5*range,base+range,base,base+0.5*range);
   XCheck("S1 rejects a bar whose close equals its open",!s1.Evaluate(r,8,atr,c));
   XBar(r,1,t1,base,base,base,base);
   XCheck("S1 rejects a zero-range bar",!s1.Evaluate(r,8,atr,c));
   XCheck("no rejection reached the fingerprint claim",
          s1.Detected()==before_detected);
   XCheck("S1 refuses a zero ATR rather than dividing by it",
          !s1.Evaluate(r,8,0.0,c));
   XCheck("S1 refuses a rates array too short to hold a closed bar",
          !s1.Evaluate(r,1,atr,c));
   delete ev;
  }

//--- A tick whose BID sits a stated number of POINTS from a reference,
//--- so every tracker expectation below is written in the same unit the
//--- tracker measures in and no test contains a hand-converted price.
void XTickPts(MqlTick &t,const datetime when,const double ref_bid,
              const double points,const double spread_pts)
  {
   XTick(t,when,ref_bid+points*g_xpoint,spread_pts*g_xpoint);
  }

//--- A candidate assembled by hand. The tracker tests must not depend on
//--- a setup class agreeing with them about what a candidate looks like.
void XCand(SXspCandidate &c,const ENUM_XSP_DIR dir,const double invalidation,
           const datetime bar,const string fp)
  {
   c.Reset();
   c.valid=true;
   c.setup=XSP_SETUP_CONTINUATION;
   c.dir=dir;
   c.fingerprint=fp;
   c.event_bar_time=bar;
   c.invalidation=invalidation;
   c.level_price=invalidation;
   c.pool_kind=XSP_POOL_NONE;
   c.atr_points=100.0;
  }

//+------------------------------------------------------------------+
//| 3. S2 REVERSAL, against a pool list of KNOWN prices.               |
//|                                                                  |
//| The pool list is pushed through the test seam rather than taken from |
//| the tape, because every assertion here is about a boundary: swept    |
//| versus merely touched, came back inside versus closed beyond, and    |
//| which of several eligible pools wins. Those need exact prices. The   |
//| LIVE pool list is exercised separately in TestPools, on invariants.  |
//|                                                                  |
//| Four pools, and each one is there to be a different answer:          |
//|   PH      - the highest high-side pool: the one that must win        |
//|   PH-200  - penetrated, but the close never came back inside it      |
//|   PL      - low side, far below: never penetrated at all             |
//|   PH+20   - HIGHER than PH and inside the sweep bar's range, but it   |
//|             did not exist when the window started. A level that was   |
//|             not yet there cannot have been swept, and the assertion   |
//|             that it was excluded is level_price coming back as PH.    |
//+------------------------------------------------------------------+
void TestSetupS2(void)
  {
   CXspStructureEvents *ev=new CXspStructureEvents();
   ev.Configure((int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
   CXspPools *pools=new CXspPools();
   XCheck("S2 pool list initialises",pools.Initialize(_Symbol,g_xpoint));
   pools.ClearForTest();

   CXspReversal s2;
   XCheck("S2 initialises with an event registry",
          s2.Initialize(_Symbol,XSP_TF_SETUP,g_xpoint,ev));

   const double atr=100.0;
   const double base=3400.0;
   const double PH=base+500.0*g_xpoint;
   const double PL=base-500.0*g_xpoint;
   const int    secs=PeriodSeconds(XSP_TF_SETUP);
   const datetime porigin=(datetime)(D'2026.01.02 00:00:00');
   const datetime wnewest=porigin+(datetime)(20*secs);

   MqlRates r[];
   ArrayResize(r,8);
   XFill(r,0,7,wnewest,secs,PH-50.0*g_xpoint);
   //--- The sweep: pushes 30 points through PH and closes 40 back below it.
   XBar(r,1,wnewest-(datetime)secs,PH-10.0*g_xpoint,PH+30.0*g_xpoint,
        PH-60.0*g_xpoint,PH-40.0*g_xpoint);

   XCheck("pool seam accepts the prior-day high",
          pools.PushForTest(XSP_POOL_PRIOR_DAY_HIGH,PH,porigin,1));
   XCheck("pool seam accepts a lower cluster the close stayed above",
          pools.PushForTest(XSP_POOL_EQUAL_HIGHS,PH-200.0*g_xpoint,porigin,3));
   XCheck("pool seam accepts the prior-day low",
          pools.PushForTest(XSP_POOL_PRIOR_DAY_LOW,PL,porigin,1));
   //--- Dated after every window this test builds, so it is never older
   //--- than the window it would have to have been swept by.
   XCheck("pool seam accepts a level younger than the window",
          pools.PushForTest(XSP_POOL_EQUAL_HIGHS,PH+20.0*g_xpoint,
                            wnewest+(datetime)(4*secs),2));
   XCheck("four pools are in the list",pools.Count()==4);

   SXspCandidate c;
   XCheck("S2 emits nothing before it has been given a pool list",
          !s2.Evaluate(r,8,atr,c));
   s2.SetPools(pools);
   XCheck("S2 refuses a window shorter than the sweep window plus two",
          !s2.Evaluate(r,XSP_SWEEP_WINDOW_BARS+1,atr,c));

   XCheck("S2 emits on penetrate-then-reject",s2.Evaluate(r,8,atr,c));
   XCheck("S2 direction is against the swept side",c.dir==XSP_DIR_SELL);
   XCheck("S2 invalidation IS the sweep extreme",
          MathAbs(c.invalidation-(PH+30.0*g_xpoint))<XSP_EPSILON);
   XCheck("S2 level price is the DEEPEST pool actually taken out",
          MathAbs(c.level_price-PH)<XSP_EPSILON);
   XCheck("a pool younger than the window did not win it",
          c.level_price<PH+20.0*g_xpoint);
   XCheck("S2 carries the pool kind",c.pool_kind==XSP_POOL_PRIOR_DAY_HIGH);
   XCheck("S2 stamps the sweep bar time",c.event_bar_time==r[1].time);
   XCheck("S2 setup kind is reversal",c.setup==XSP_SETUP_REVERSAL);

   //=== IDENTITY IS THE POOL, NOT THE SWEEP BAR ====================
   //--- The same pool failing again three bars later is the same level
   //--- failing, and counting it twice is the pseudo-replication that
   //--- inflated n in the old tree. Every bar time here is different and
   //--- the occurrence must still be refused.
   for(int shift=1;shift<=3;shift++)
     {
      XFill(r,0,7,wnewest+(datetime)(shift*secs),secs,PH-50.0*g_xpoint);
      XBar(r,1,wnewest+(datetime)((shift-1)*secs),PH-10.0*g_xpoint,
           PH+30.0*g_xpoint,PH-60.0*g_xpoint,PH-40.0*g_xpoint);
      XCheck("the same pool swept on a LATER bar is not a new occurrence",
             !s2.Evaluate(r,8,atr,c));
     }
   XCheck("S2 emitted once across four sweeps of one pool",s2.Emitted()==1);
   XCheck("S2 counted the three repeats as suppressed",s2.Suppressed()==3);
   XCheck("the registry saw one occurrence",ev.Claims()==1);

   //--- Restore the original window for the boundary cases below.
   XFill(r,0,7,wnewest,secs,PH-50.0*g_xpoint);

   //=== TOUCHED IS NOT SWEPT =======================================
   //--- A high exactly AT the pool did not penetrate it. Strict on both
   //--- sides: the lower cluster is penetrated here but the close never
   //--- came back inside it, so it is not an occurrence either.
   const long amb_before=s2.Ambiguous();
   XBar(r,1,wnewest-(datetime)secs,PH-10.0*g_xpoint,PH,
        PH-60.0*g_xpoint,PH-40.0*g_xpoint);
   XCheck("a high exactly AT the pool is not a sweep",!s2.Evaluate(r,8,atr,c));
   XCheck("a non-sweep is not counted as ambiguous",s2.Ambiguous()==amb_before);

   //=== TWO-SIDED IS AMBIGUOUS, NOT A COIN FLIP ====================
   XCheck("pool seam accepts a low-side cluster inside the sweep bar",
          pools.PushForTest(XSP_POOL_EQUAL_LOWS,PH-50.0*g_xpoint,porigin,2));
   XBar(r,1,wnewest-(datetime)secs,PH-10.0*g_xpoint,PH+30.0*g_xpoint,
        PH-60.0*g_xpoint,PH-40.0*g_xpoint);
   XCheck("a window that swept BOTH sides emits nothing",!s2.Evaluate(r,8,atr,c));
   XCheck("the ambiguous window is counted, not dropped in silence",
          s2.Ambiguous()==amb_before+1);
   delete pools;
   delete ev;
  }

//+------------------------------------------------------------------+
//| 4. THE LIVE POOL LIST - invariants, not values.                    |
//|                                                                  |
//| This block reads real history, so it cannot assert a price. It        |
//| asserts the properties every pool list must have whatever the tape    |
//| printed, which is enough to fail on a broken build and impossible to  |
//| fail on a working one: kinds typed consistently with IsHighSide,      |
//| clusters carrying at least two touches, identities that are dated,    |
//| and the two Nearest* queries returning the true nearest.              |
//+------------------------------------------------------------------+
void TestPools(void)
  {
   SXspLevel probe;
   const int n=g_xpools.Count();
   XCheck("pool list has at least the prior day's two extremes",n>=2);
   XCheck("pool list respects its own ceiling",n<=XSP_MAX_POOLS);
   XCheck("pool list refuses a negative index",!g_xpools.Get(-1,probe));
   XCheck("pool list refuses one past the end",!g_xpools.Get(n,probe));

   int day_high=0,day_low=0,bad_touches=0,bad_price=0,bad_date=0,bad_valid=0;
   double highest_low_side=0.0,lowest_high_side=0.0;
   bool have_hi=false,have_lo=false;
   for(int i=0;i<n;i++)
     {
      SXspLevel p;
      if(!g_xpools.Get(i,p)) { bad_valid++; continue; }
      if(!p.valid)                              bad_valid++;
      if(!(p.price>0.0))                        bad_price++;
      if(p.origin_time<=0)                      bad_date++;
      if(p.kind==XSP_POOL_PRIOR_DAY_HIGH)       day_high++;
      if(p.kind==XSP_POOL_PRIOR_DAY_LOW)        day_low++;
      //--- A cluster is BY DEFINITION two or more swings within tolerance.
      //--- One touch means BuildClusters emitted a level it had no second
      //--- member for, which would make "equal highs" mean nothing.
      if((p.kind==XSP_POOL_EQUAL_HIGHS || p.kind==XSP_POOL_EQUAL_LOWS)
         && p.touches<2)                        bad_touches++;
      if(CXspPools::IsHighSide(p.kind))
        {
         if(!have_hi || p.price<lowest_high_side) { lowest_high_side=p.price; have_hi=true; }
        }
      else
        {
         if(!have_lo || p.price>highest_low_side) { highest_low_side=p.price; have_lo=true; }
        }
     }
   XCheck("every pool in the list is valid",bad_valid==0);
   XCheck("every pool has a positive price",bad_price==0);
   XCheck("every pool carries the bar time it was formed on",bad_date==0);
   XCheck("every cluster has at least two touches",bad_touches==0);
   XCheck("exactly one prior-day high",day_high==1);
   XCheck("exactly one prior-day low",day_low==1);
   XCheck("the list has both sides",have_hi && have_lo);

   //--- NearestAbove/NearestBelow must return the TRUE nearest, so each is
   //--- queried one point away from the extreme the scan above found.
   SXspLevel near;
   XCheck("NearestAbove finds the closest high-side pool",
          g_xpools.NearestAbove(lowest_high_side-g_xpoint,near));
   XCheck("and it is the one the scan says is closest",
          MathAbs(near.price-lowest_high_side)<XSP_EPSILON);
   XCheck("and it is typed as high side",CXspPools::IsHighSide(near.kind));
   XCheck("NearestAbove is strict at the level itself",
          !g_xpools.NearestAbove(lowest_high_side,near)
          || near.price>lowest_high_side);
   XCheck("NearestAbove finds nothing above every pool",
          !g_xpools.NearestAbove(lowest_high_side*10.0,near));

   XCheck("NearestBelow finds the closest low-side pool",
          g_xpools.NearestBelow(highest_low_side+g_xpoint,near));
   XCheck("and it is the one the scan says is closest",
          MathAbs(near.price-highest_low_side)<XSP_EPSILON);
   XCheck("and it is typed as low side",!CXspPools::IsHighSide(near.kind));
   XCheck("NearestBelow finds nothing below every pool",
          !g_xpools.NearestBelow(g_xpoint,near));

   //--- Once per closed bar, not once per call. Two adjacent calls: the
   //--- second must be a no-op, and force must still rebuild - otherwise
   //--- the no-op could be a Refresh that does nothing at all.
   const double tol=XSP_POOL_TOLERANCE_ATR*g_xregime.AtrPoints(1);
   XCheck("pool refresh succeeds on live history",
          g_xpools.Refresh(g_xswings,tol));
   const long rb=g_xpools.Rebuilds();
   XCheck("a second refresh inside the same bar also succeeds",
          g_xpools.Refresh(g_xswings,tol));
   XCheck("but it did not rebuild the list",g_xpools.Rebuilds()==rb);
   XCheck("a forced refresh does rebuild it",
          g_xpools.Refresh(g_xswings,tol,true) && g_xpools.Rebuilds()==rb+1);
   XCheck("the rebuilt list still has both prior-day extremes",
          g_xpools.Count()>=2);
  }

//+------------------------------------------------------------------+
//| 5. THE BARRIER TRACKER - assertions 2, 3 and 4 of the plan.        |
//|                                                                  |
//| Entirely synthetic: no market, no history, no filesystem. Every       |
//| expectation is written in POINTS from one reference price, and the     |
//| tier thresholds are read from XspRTier rather than typed, so a change  |
//| to XSP_R_* changes what is asserted instead of breaking it.           |
//|                                                                  |
//| The sign-flip case is the one worth naming: the SAME descending tick   |
//| sequence must resolve a BUY on its stop and a SELL on its targets.     |
//| A tracker that measured the bid path with one sign for both would      |
//| pass every monotone-up test and be wrong on half the study.            |
//+------------------------------------------------------------------+
void TestTracker(void)
  {
   CXspBarrierTracker tr;
   tr.Configure(g_xpoint);

   const datetime tt=(datetime)(D'2026.02.10 09:00:00');
   const double   base=3400.0;
   const double   stop=200.0;                 // points
   MqlTick        t0;
   XTickPts(t0,tt,base,0.0,20.0);             // bid=base, ask=base+20pts

   SXspCandidate cb,cs;
   XCand(cb,XSP_DIR_BUY, base-stop*g_xpoint,tt-(datetime)900,"fp-buy");
   XCand(cs,XSP_DIR_SELL,base+stop*g_xpoint,tt-(datetime)900,"fp-sell");

   MqlTick      t;
   SXspInstance ins;
   long         id=0;

   //=== ASSERTION 4: WHICH SIDE OF THE SPREAD ======================
   XCheck("tracker opens a buy",tr.Open(cb,t0,stop,id));
   XCheck("instance ids start at one",id==1);
   XCheck("peek returns the live instance",tr.PeekLive(0,ins));
   XCheck("a BUY is filled at the ASK",MathAbs(ins.fill_price-t0.ask)<XSP_EPSILON);
   XCheck("but the reference series is the BID",
          MathAbs(ins.ref_entry-t0.bid)<XSP_EPSILON);
   XCheck("raw spread is recorded in points",
          MathAbs(ins.spread_points-20.0)<0.001);
   XCheck("the stop it was handed is the stop it carries",
          MathAbs(ins.stop_points-stop)<XSP_EPSILON);
   XCheck("nothing is resolved at open",
          ins.sec_to_stop==XSP_NEVER && ins.sec_to_target[0]==XSP_NEVER);
   XCheck("no cap is marked at open",
          !ins.cap_stamped[0] && MathAbs(ins.move_at_cap[0]-XSP_NO_MARK)<XSP_EPSILON);

   XCheck("tracker opens a sell on the same tick",tr.Open(cs,t0,stop,id));
   XCheck("ids are sequential",id==2);
   XCheck("peek returns the second instance",tr.PeekLive(1,ins));
   XCheck("a SELL is filled at the BID",MathAbs(ins.fill_price-t0.bid)<XSP_EPSILON);
   XCheck("a SELL references the BID too",
          MathAbs(ins.ref_entry-t0.bid)<XSP_EPSILON);
   XCheck("two instances are live",tr.LiveCount()==2);
   XCheck("peek refuses a negative index",!tr.PeekLive(-1,ins));
   XCheck("peek refuses one past the end",!tr.PeekLive(2,ins));
   XCheck("both opens are counted",tr.OpenedTotal()==2);

   //=== REFUSALS, EACH COUNTED IN THE CENSUS =======================
   //--- StopPoints returns 0 when price gapped through the invalidation
   //--- before the first tick. The tracker must refuse that rather than
   //--- clamp it: a clamped stop is a different hypothesis, and the
   //--- refusal has to appear in the census or the sample will not add up.
   long rid=0;
   const long geo=tr.RejectedGeometry();
   XCheck("a zero stop is refused, not clamped",!tr.Open(cb,t0,0.0,rid));
   XCheck("a negative stop is refused",!tr.Open(cb,t0,-5.0,rid));
   XCheck("both are counted as geometry refusals",
          tr.RejectedGeometry()==geo+2);
   MqlTick crossed;
   XTick(crossed,tt,base,-5.0*g_xpoint);      // ask BELOW bid
   XCheck("a crossed tick is refused",!tr.Open(cb,crossed,stop,rid));
   MqlTick noask;
   XTick(noask,tt,base,0.0);
   noask.ask=0.0;
   XCheck("a tick with no ask is refused",!tr.Open(cb,noask,stop,rid));
   XCheck("those are counted too",tr.RejectedGeometry()==geo+4);

   SXspCandidate cnone,cinvalid;
   XCand(cnone,XSP_DIR_NONE,base,tt,"fp-none");
   XCand(cinvalid,XSP_DIR_BUY,base-stop*g_xpoint,tt,"fp-invalid");
   cinvalid.valid=false;
   XCheck("a directionless candidate is refused",!tr.Open(cnone,t0,stop,rid));
   XCheck("an invalid candidate is refused",!tr.Open(cinvalid,t0,stop,rid));
   XCheck("neither is miscounted as a geometry refusal",
          tr.RejectedGeometry()==geo+4);
   XCheck("no refusal left an instance behind",tr.LiveCount()==2);
   XCheck("every refusal returned a zero id",rid==0);

   tr.Reset();
   XCheck("reset empties the live array",tr.LiveCount()==0);

   //=== ASSERTION 2a: MONOTONE UP, a BUY ===========================
   //--- Tier prices come from XspRTier, so this tests the boundary the
   //--- product declares rather than a number copied out of it once.
   XCheck("tracker opens the monotone-up buy",tr.Open(cb,t0,stop,id));
   XTickPts(t,tt+(datetime)10,base,0.5*XspRTier(0)*stop,20.0);
   tr.OnTick(t);
   XCheck("half of the first tier resolves nothing",
          tr.PeekLive(0,ins) && ins.sec_to_target[0]==XSP_NEVER);
   for(int k=0;k<XSP_R_TIERS;k++)
     {
      XTickPts(t,tt+(datetime)(20+10*k),base,XspRTier(k)*stop,20.0);
      tr.OnTick(t);
     }
   XCheck("resolving every tier closes the instance",tr.LiveCount()==0);
   XCheck("it closed by targets",tr.ClosedByTargets()==1);
   XCheck("it did not also count as a stop",tr.ClosedByStop()==0);
   XCheck("one instance is waiting to be drained",tr.PendingClosed()==1);
   XCheck("drain yields it",tr.PopClosed(ins));

   int bad_tier=0;
   for(int k=0;k<XSP_R_TIERS;k++)
      if(ins.sec_to_target[k]!=20+10*k) bad_tier++;
   XCheck("each tier is stamped at the tick that reached it",bad_tier==0);
   int out_of_order=0;
   for(int k=1;k<XSP_R_TIERS;k++)
      if(ins.sec_to_target[k]<ins.sec_to_target[k-1]) out_of_order++;
   XCheck("a bigger reward is never reached earlier than a smaller one",
          out_of_order==0);
   XCheck("the stop was never touched",ins.sec_to_stop==XSP_NEVER);
   XCheck("a monotone advance has no adverse excursion",
          MathAbs(ins.mae_points)<XSP_EPSILON);
   XCheck("MFE is the best price seen",
          MathAbs(ins.mfe_points-XspRTier(XSP_R_TIERS-1)*stop)<0.001);
   XCheck("seconds-to-MFE is when that price printed",
          ins.sec_to_mfe==20+10*(XSP_R_TIERS-1));
   XCheck("every tick is counted",ins.ticks_seen==XSP_R_TIERS+1);
   XCheck("tracked seconds is its age at close",
          ins.tracked_seconds==20+10*(XSP_R_TIERS-1));
   XCheck("no holding cap was reached inside a minute",!ins.cap_stamped[0]);
   XCheck("the drain queue is empty again",tr.PendingClosed()==0);
   XCheck("popping an empty queue returns false",!tr.PopClosed(ins));

   //=== ASSERTION 2b: MONOTONE DOWN, the same buy ==================
   tr.Reset();
   XCheck("tracker opens the monotone-down buy",tr.Open(cb,t0,stop,id));
   XTickPts(t,tt+(datetime)10,base,-0.5*stop,20.0);
   tr.OnTick(t);
   XCheck("half the stop distance does not stop it out",tr.LiveCount()==1);
   XTickPts(t,tt+(datetime)20,base,-stop,20.0);
   tr.OnTick(t);
   XCheck("reaching the stop closes it",tr.LiveCount()==0);
   XCheck("it closed by stop",tr.ClosedByStop()==1);
   XCheck("it did not also count as a target",tr.ClosedByTargets()==0);
   XCheck("drain yields the stopped instance",tr.PopClosed(ins));
   XCheck("the stop is stamped at the tick that reached it",ins.sec_to_stop==20);

   int hit_tier=0;
   for(int k=0;k<XSP_R_TIERS;k++)
      if(ins.sec_to_target[k]!=XSP_NEVER) hit_tier++;
   XCheck("no reward tier was reached",hit_tier==0);
   XCheck("MAE is the worst price seen",MathAbs(ins.mae_points+stop)<0.001);
   XCheck("a monotone decline has no favourable excursion",
          MathAbs(ins.mfe_points)<XSP_EPSILON);

   //=== ASSERTION 2c: THE SIGN FLIP ================================
   //--- The SAME descending series, opened as a SELL. Every tier must now
   //--- resolve at the same ages and the stop must never be touched. A
   //--- direction sign dropped anywhere in the excursion arithmetic passes
   //--- 2a and 2b - both of which read a rising price as favourable - and
   //--- fails only here.
   tr.Reset();
   XCheck("tracker opens the mirrored sell",tr.Open(cs,t0,stop,id));
   for(int k=0;k<XSP_R_TIERS;k++)
     {
      XTickPts(t,tt+(datetime)(20+10*k),base,-XspRTier(k)*stop,20.0);
      tr.OnTick(t);
     }
   XCheck("the falling series closes the sell by targets",
          tr.LiveCount()==0 && tr.ClosedByTargets()==1);
   XCheck("and not by stop",tr.ClosedByStop()==0);
   XCheck("drain yields the sell",tr.PopClosed(ins));
   XCheck("the sell's direction survived into the record",ins.dir==XSP_DIR_SELL);

   int bad_sell=0;
   for(int k=0;k<XSP_R_TIERS;k++)
      if(ins.sec_to_target[k]!=20+10*k) bad_sell++;
   XCheck("a sell reaches its tiers on a falling price",bad_sell==0);
   XCheck("the sell's stop was never touched",ins.sec_to_stop==XSP_NEVER);
   XCheck("a falling price is FAVOURABLE to a sell",
          MathAbs(ins.mfe_points-XspRTier(XSP_R_TIERS-1)*stop)<0.001);
   XCheck("and the sell has no adverse excursion",
          MathAbs(ins.mae_points)<XSP_EPSILON);

   //=== ASSERTION 2d: STRADDLE =====================================
   //--- Favourable first, then stopped. The point of this case is that a
   //--- stopped instance still carries the excursion it made BEFORE the
   //--- stop: if MFE were only recorded on resolution, this row would read
   //--- as a loss that never went anywhere, and the "was there a better
   //--- target" question could not be asked of it afterwards.
   tr.Reset();
   XCheck("tracker opens the straddle buy",tr.Open(cb,t0,stop,id));
   XTickPts(t,tt+(datetime)10,base,0.75*stop,20.0);
   tr.OnTick(t);
   XTickPts(t,tt+(datetime)20,base,-stop,20.0);
   tr.OnTick(t);
   XCheck("the straddle resolves as a stop",
          tr.ClosedByStop()==1 && tr.PopClosed(ins));
   XCheck("its favourable excursion is preserved",
          MathAbs(ins.mfe_points-0.75*stop)<0.001);
   XCheck("its adverse excursion is the stop distance",
          MathAbs(ins.mae_points+stop)<0.001);
   XCheck("the best price came before the stop",
          ins.sec_to_mfe==10 && ins.sec_to_stop==20);
   XCheck("three quarters of a stop is not the first reward tier",
          ins.sec_to_target[0]==XSP_NEVER);

   //=== ASSERTION 3: MFE NEVER FALLS, MAE NEVER RISES ==============
   //--- Checked after EVERY tick of a zigzag, not just at the end. An
   //--- excursion field that is overwritten rather than extended agrees
   //--- with the final value on a monotone series, so only a path that
   //--- reverses several times can catch it.
   tr.Reset();
   double zz[10]={50.0,20.0,80.0,10.0,120.0,-30.0,-10.0,-60.0,-20.0,90.0};
   XCheck("tracker opens the zigzag buy",tr.Open(cb,t0,stop,id));

   double seen_mfe=0.0,seen_mae=0.0;
   int mfe_drops=0,mae_rises=0,peek_fail=0;
   for(int i=0;i<10;i++)
     {
      XTickPts(t,tt+(datetime)(10*(i+1)),base,zz[i],20.0);
      tr.OnTick(t);
      if(!tr.PeekLive(0,ins)) { peek_fail++; continue; }
      if(ins.mfe_points<seen_mfe-XSP_EPSILON) mfe_drops++;
      if(ins.mae_points>seen_mae+XSP_EPSILON)  mae_rises++;
      seen_mfe=ins.mfe_points;
      seen_mae=ins.mae_points;
     }
   XCheck("the zigzag never resolved a barrier",peek_fail==0 && tr.LiveCount()==1);
   XCheck("MFE never decreased on any tick",mfe_drops==0);
   XCheck("MAE never increased on any tick",mae_rises==0);
   XCheck("MFE ends at the highest price of the path",
          MathAbs(seen_mfe-120.0)<0.001);
   XCheck("MAE ends at the lowest price of the path",
          MathAbs(seen_mae+60.0)<0.001);
   XCheck("seconds-to-MFE points at the peak, not at the last tick",
          tr.PeekLive(0,ins) && ins.sec_to_mfe==50);

   //=== HOLDING-CAP MARKS, EXACTLY ON THE CAP ======================
   //--- The four caps are what makes 5/15/30/60-minute holds derivable from
   //--- one pass, so the mark has to be the R at the cap and not the R at
   //--- resolution. Here a tick lands ON the first cap: that tick IS the
   //--- mark, and no later cap may be stamped by it.
   tr.Reset();
   XCheck("tracker opens the cap-mark buy",tr.Open(cb,t0,stop,id));
   XTickPts(t,tt+(datetime)100,base,0.2*stop,20.0);
   tr.OnTick(t);
   XCheck("no cap is stamped before the first cap elapses",
          tr.PeekLive(0,ins) && !ins.cap_stamped[0]);
   XTickPts(t,tt+(datetime)XspCapSeconds(0),base,0.5*stop,20.0);
   tr.OnTick(t);
   XCheck("the instance is still live at its first cap",tr.LiveCount()==1);
   XCheck("peek the capped instance",tr.PeekLive(0,ins));
   XCheck("the first cap is stamped",ins.cap_stamped[0]);
   XCheck("its mark is the R of the tick that landed on the cap",
          MathAbs(ins.move_at_cap[0]-0.5)<0.0001);

   int early_cap=0;
   for(int c=1;c<XSP_CAP_TIERS;c++)
      if(ins.cap_stamped[c] || MathAbs(ins.move_at_cap[c]-XSP_NO_MARK)>0.0001)
         early_cap++;
   XCheck("no later cap was stamped by that tick",early_cap==0);
   XCheck("reaching a cap is not a resolution",
          ins.sec_to_stop==XSP_NEVER && ins.sec_to_target[0]==XSP_NEVER);

   //=== A GAP OVER THE CEILING =====================================
   //--- One tick, then silence, then a tick 83 minutes later at +45 R. Two
   //--- things must happen and neither is optional. Every cap is stamped
   //--- with the LAST R observed before the gap, because nothing was
   //--- observed at those instants and the post-gap price is not evidence
   //--- about them. And the post-ceiling price must not touch the
   //--- excursions or the barriers at all: crediting it would report a 45 R
   //--- winner to a 60-minute hold that had already ended flat.
   tr.Reset();
   XCheck("tracker opens the gap buy",tr.Open(cb,t0,stop,id));
   XTickPts(t,tt+(datetime)100,base,0.2*stop,20.0);
   tr.OnTick(t);
   XTickPts(t,tt+(datetime)(XSP_TRACK_MAX_SECONDS+1400),base,45.0*stop,20.0);
   tr.OnTick(t);
   XCheck("a tick past the ceiling closes the instance",tr.LiveCount()==0);
   XCheck("it closed by timeout",tr.ClosedByTimeout()==1);
   XCheck("not by target, despite the price",tr.ClosedByTargets()==0);
   XCheck("drain yields the timed-out instance",tr.PopClosed(ins));

   int gap_bad=0;
   for(int c=0;c<XSP_CAP_TIERS;c++)
      if(!ins.cap_stamped[c] || MathAbs(ins.move_at_cap[c]-0.2)>0.0001) gap_bad++;
   XCheck("every cap is marked at the last R seen before the gap",gap_bad==0);
   XCheck("tracked seconds is the ceiling, not the tick's age",
          ins.tracked_seconds==XSP_TRACK_MAX_SECONDS);
   XCheck("the post-ceiling price did not set the MFE",
          MathAbs(ins.mfe_points-0.2*stop)<0.001);
   XCheck("and did not resolve a single reward tier",
          ins.sec_to_target[0]==XSP_NEVER &&
          ins.sec_to_target[XSP_R_TIERS-1]==XSP_NEVER);
   XCheck("the tick was still counted as observed",ins.ticks_seen==2);

   //=== UNRESOLVED AT THE END OF THE RUN ===========================
   //--- Never discarded and never called flat. Both would be convenient and
   //--- both would be a claim about an outcome nobody observed.
   tr.Reset();
   XCheck("tracker opens the unresolved buy",tr.Open(cb,t0,stop,id));
   XTickPts(t,tt+(datetime)10,base,0.25*stop,20.0);
   tr.OnTick(t);
   tr.FlushUnresolved();
   XCheck("the flush empties the live array",tr.LiveCount()==0);
   XCheck("it is counted as unresolved",tr.ClosedUnresolved()==1);
   XCheck("and not as a stop, a target or a timeout",
          tr.ClosedByStop()==0 && tr.ClosedByTargets()==0 && tr.ClosedByTimeout()==0);
   XCheck("drain yields the unresolved instance",tr.PopClosed(ins));
   XCheck("no barrier is claimed",
          ins.sec_to_stop==XSP_NEVER && ins.sec_to_target[0]==XSP_NEVER);

   int flush_bad=0;
   for(int c=0;c<XSP_CAP_TIERS;c++)
      if(ins.cap_stamped[c] || MathAbs(ins.move_at_cap[c]-XSP_NO_MARK)>0.0001)
         flush_bad++;
   XCheck("no cap is marked, so no time-exit can be priced from it",
          flush_bad==0);
   XCheck("what WAS observed is still reported",
          MathAbs(ins.mfe_points-0.25*stop)<0.001 && ins.tracked_seconds==10);

   //=== TWO INSTANCES, ONE TICK, ONE RETIREMENT ====================
   //--- The live array is swap-removed while being walked. A survivor that
   //--- gets advanced twice by one tick would double-count its ticks and,
   //--- on a resolving tick, could be resolved by a price it saw once. The
   //--- descending walk is what prevents it; this is the regression test.
   tr.Reset();
   long ida=0,idb=0;
   XCheck("tracker opens the tight-stop instance",tr.Open(cb,t0,stop,ida));
   XCheck("tracker opens the wide-stop instance",tr.Open(cb,t0,2.0*stop,idb));
   XCheck("both are live and their ids differ",tr.LiveCount()==2 && ida!=idb);
   XTickPts(t,tt+(datetime)10,base,-stop,20.0);
   tr.OnTick(t);
   XCheck("the tight stop resolved",tr.ClosedByStop()==1);
   XCheck("the wide one did not",tr.LiveCount()==1);
   XCheck("peek the survivor",tr.PeekLive(0,ins));
   XCheck("the survivor is the wide-stop instance",ins.id==idb);
   XCheck("one tick advanced it exactly once",ins.ticks_seen==1);
   XCheck("its adverse excursion is the price, not twice the price",
          MathAbs(ins.mae_points+stop)<0.001);
   XCheck("half a stop is not a stop",ins.sec_to_stop==XSP_NEVER);

   //=== THE DRAIN QUEUE OUTLIVES ITS OWN CAPACITY ==================
   //--- The queue holds 256 entries and the read cursor is a position, not
   //--- a count of what is still in it. A study over nine months retires
   //--- thousands of instances, so unless the drained prefix is reclaimed
   //--- everything after the 256th is lost - and a lost instance is a
   //--- missing row in a file whose whole purpose is to be the sample.
   //--- 300 open-close-drain cycles is the smallest number that proves it.
   tr.Reset();
   int drained=0,open_fail=0;
   for(int k=0;k<300;k++)
     {
      long kid=0;
      if(!tr.Open(cb,t0,stop,kid)) { open_fail++; continue; }
      XTickPts(t,tt+(datetime)10,base,-stop,20.0);
      tr.OnTick(t);
      if(tr.PopClosed(ins)) drained++;
     }
   XCheck("300 instances all opened",open_fail==0);
   XCheck("300 instances all closed",tr.ClosedByStop()==300);
   XCheck("and all 300 were drained, none lost past the 256th",drained==300);
   XCheck("the queue is empty at the end",tr.PendingClosed()==0);
   XCheck("and the live array is empty too",tr.LiveCount()==0);
  }

//+------------------------------------------------------------------+
//| Count separators. A 45-column CSV whose row is off by one still   |
//| parses, so the count is asserted before any field is read.        |
//+------------------------------------------------------------------+
int XCommas(const string s)
  {
   int n=0;
   const int len=StringLen(s);
   for(int i=0;i<len;i++)
      if(StringGetCharacter(s,i)==',') n++;
   return(n);
  }

//+------------------------------------------------------------------+
//| THE SCHEMA. Rendered through the REAL row builder, so a column     |
//| added to Columns() and not to BuildRow (or the reverse) fails      |
//| here rather than shifting every cut the analysis makes.            |
//|                                                                  |
//| Prices are formatted at the recorder's default 2 digits, which is  |
//| XAUUSD's; the expected strings below are therefore digit-specific  |
//| on purpose and would need changing for a 5-digit symbol.           |
//+------------------------------------------------------------------+
void TestRecorderSchema(void)
  {
   Print("--- recorder schema ---");
   CXspRecorder rec;

   //--- Every field set explicitly: SXspInstance deliberately has no
   //--- Reset(), so an unset field here would render whatever the stack
   //--- held and the test would be reading its own garbage.
   SXspInstance ins;
   ins.active=true;
   ins.id=42;
   ins.fingerprint="S2|3405.00|1770714000|sell";
   ins.setup=XSP_SETUP_REVERSAL;
   ins.dir=XSP_DIR_SELL;
   ins.event_bar_time=D'2026.02.10 09:00:00';
   ins.trigger_time=D'2026.02.10 09:15:07';
   ins.ref_entry=3400.00;
   ins.fill_price=3400.20;
   ins.spread_points=20.0;
   ins.invalidation=3405.00;
   ins.stop_points=200.0;
   ins.mfe_points=300.0;
   ins.mae_points=-50.0;
   ins.sec_to_mfe=120;
   ins.sec_to_stop=XSP_NEVER;
   ins.sec_to_target[0]=45;
   ins.sec_to_target[1]=90;
   ins.sec_to_target[2]=XSP_NEVER;
   ins.sec_to_target[3]=XSP_NEVER;
   ins.move_at_cap[0]=0.5;
   ins.move_at_cap[1]=1.25;
   ins.move_at_cap[2]=XSP_NO_MARK;
   ins.move_at_cap[3]=XSP_NO_MARK;
   ins.cap_stamped[0]=true;
   ins.cap_stamped[1]=true;
   ins.cap_stamped[2]=false;
   ins.cap_stamped[3]=false;
   ins.last_r=1.25;
   ins.tracked_seconds=900;
   ins.ticks_seen=417;
   ins.closed=true;

   SXspLabels lab;
   lab.used=true;
   lab.id=42;
   lab.cand.Reset();
   lab.cand.level_price=3405.00;
   lab.cand.pool_kind=XSP_POOL_EQUAL_HIGHS;
   lab.cand.atr_points=100.0;
   lab.regime.Reset();
   lab.regime.vol_decile=7;
   lab.regime.spread_decile=2;
   lab.regime.session=XSP_SESSION_LONDON;
   lab.regime.minute_of_day=555;
   lab.context.Reset();
   lab.context.h1_trend=XSP_TREND_DOWN;
   lab.context.h4_trend=XSP_TREND_UP;
   lab.context.h1_aligned=true;
   lab.context.h4_aligned=false;
   lab.context.h1_range_pos=0.25;
   lab.confirm.Reset();
   lab.confirm.tick_volume=1234;
   lab.confirm.slot_median=800.0;
   lab.confirm.slot_samples=20;
   lab.confirm.ratio=1.5425;
   lab.confirm.passed=true;

   const string hdr=CXspRecorder::Columns();
   const string row=rec.RenderTestRow(ins,lab);
   XCheck("the header declares 45 columns",XCommas(hdr)==44);
   XCheck("and the row builder writes exactly as many",
          XCommas(row)==XCommas(hdr));

   string h[],f[];
   const int nh=StringSplit(hdr,StringGetCharacter(",",0),h);
   const int nf=StringSplit(row,StringGetCharacter(",",0),f);
   XCheck("the header splits into 45 names",nh==45);
   XCheck("the row splits into 45 fields",nf==45);

   if(nh==45)
     {
      //--- The names the analysis script will index by, pinned to their
      //--- positions. Reordering Columns() and BuildRow() together keeps
      //--- both counts right and still breaks every saved cut; only a
      //--- positional assertion catches that.
      XCheck("column 0 is instance_id",h[0]=="instance_id");
      XCheck("column 12 is pool_kind",h[12]=="pool_kind");
      XCheck("column 15 is sec_to_stop",h[15]=="sec_to_stop");
      XCheck("column 22 is mfe_r",h[22]=="mfe_r");
      XCheck("column 25 is r_at_cap_300",h[25]=="r_at_cap_300");
      XCheck("column 31 is vol_decile",h[31]=="vol_decile");
      XCheck("column 40 is broker_tick_volume",h[40]=="broker_tick_volume");
      XCheck("column 44 is tickvol_confirm_pass",h[44]=="tickvol_confirm_pass");
     }

   if(nf==45)
     {
      XCheck("id renders",f[0]=="42");
      XCheck("fingerprint renders",f[1]==ins.fingerprint);
      XCheck("setup renders by name",f[2]=="S2_reversal");
      XCheck("direction renders by name",f[3]=="sell");
      XCheck("event bar epoch renders",
             f[4]==IntegerToString((long)ins.event_bar_time));
      XCheck("trigger epoch renders",
             f[5]==IntegerToString((long)ins.trigger_time));
      XCheck("the human-readable trigger time cannot shift a column",
             XCommas(f[6])==0 && StringLen(f[6])>0);
      XCheck("the reference entry is the bid",f[7]=="3400.00");
      XCheck("the reported fill is the ask for a buy or the bid for a sell",
             f[8]=="3400.20");
      XCheck("raw spread at trigger renders in points",f[9]=="20.00");
      XCheck("invalidation renders",f[10]=="3405.00");
      XCheck("the level that produced the setup renders",f[11]=="3405.00");
      XCheck("pool kind renders by name",f[12]=="equal_highs");
      XCheck("stop distance renders in points",f[13]=="200.00");
      XCheck("ATR at the event bar renders in points",f[14]=="100.00");
      XCheck("an unhit stop renders as -1, not as 0",f[15]=="-1");
      XCheck("the first tier's time renders",f[16]=="45");
      XCheck("the second tier's time renders",f[17]=="90");
      XCheck("unreached tiers render as -1",f[18]=="-1" && f[19]=="-1");
      XCheck("MFE renders in points",f[20]=="300.00");
      XCheck("MAE renders in points and stays negative",f[21]=="-50.00");
      XCheck("MFE in R is MFE over the stop distance",f[22]=="1.5000");
      XCheck("MAE in R keeps its sign",f[23]=="-0.2500");
      XCheck("seconds-to-MFE renders",f[24]=="120");
      XCheck("a stamped cap renders its R",f[25]=="0.5000" && f[26]=="1.2500");
      XCheck("an unstamped cap renders -999, which no excursion can reach",
             f[27]=="-999.0000" && f[28]=="-999.0000");
      XCheck("the tracking census renders",f[29]=="900" && f[30]=="417");
     }

   if(nf==45)
     {
      //--- The label block. Recorded, never gated: these fields are the
      //--- whole reason a filter's worth is measurable from one run.
      XCheck("the volatility decile renders",f[31]=="7");
      XCheck("the spread decile renders",f[32]=="2");
      XCheck("H1 and H4 trends render by name",f[33]=="down" && f[34]=="up");
      XCheck("alignment renders as 1 and 0, not as true and false",
             f[35]=="1" && f[36]=="0");
      XCheck("position in the H1 range renders",f[37]=="0.2500");
      XCheck("session renders by name",f[38]=="london");
      XCheck("minute-of-day renders",f[39]=="555");
      XCheck("broker tick volume renders",f[40]=="1234");
      XCheck("the slot median and its sample count render",
             f[41]=="800.00" && f[42]=="20");
      XCheck("the tick-volume ratio renders",f[43]=="1.5425");
      XCheck("the confirmation verdict renders last",f[44]=="1");
     }

   //--- A comma inside a fingerprint. Fingerprints are assembled from
   //--- strings, so one stray separator in a future format would shift 43
   //--- columns and every row would still parse.
   ins.fingerprint="S2,reversal,3405.00";
   const string row2=rec.RenderTestRow(ins,lab);
   string g[];
   const int ng=StringSplit(row2,StringGetCharacter(",",0),g);
   XCheck("a fingerprint carrying commas still yields 45 fields",ng==45);
   if(ng==45)
     {
      XCheck("its separators were replaced with semicolons",
             g[1]=="S2;reversal;3405.00");
      XCheck("and nothing after it shifted",
             g[2]=="S2_reversal" && g[44]=="1");
     }

   //--- An unset enum must render a NAME, never an empty field: a blank
   //--- would be read as missing by the analysis and would drop the row
   //--- out of a cut it belongs in.
   ins.setup=XSP_SETUP_NONE;
   ins.dir=XSP_DIR_NONE;
   lab.cand.pool_kind=XSP_POOL_NONE;
   lab.regime.session=XSP_SESSION_OFF;
   lab.context.h1_trend=XSP_TREND_CHOP;
   const string row3=rec.RenderTestRow(ins,lab);
   string q[];
   const int nq=StringSplit(row3,StringGetCharacter(",",0),q);
   XCheck("an unset row still yields 45 fields",nq==45);
   if(nq==45)
     {
      XCheck("an unset setup renders 'none'",q[2]=="none");
      XCheck("an unset direction renders 'none'",q[3]=="none");
      XCheck("no pool renders 'none'",q[12]=="none");
      XCheck("a chop trend renders 'chop'",q[33]=="chop");
      XCheck("out-of-session renders 'off'",q[38]=="off");
     }
  }

//--- A minimally valid instance. Used where the test cares about the
//--- recorder's bookkeeping rather than about the rendered text.
void XIns(SXspInstance &ins,const long id,const datetime when)
  {
   ins.active=true;
   ins.id=id;
   ins.fingerprint=StringFormat("S1|3400.00|%I64d|buy",(long)when);
   ins.setup=XSP_SETUP_CONTINUATION;
   ins.dir=XSP_DIR_BUY;
   ins.event_bar_time=when;
   ins.trigger_time=when+60;
   ins.ref_entry=3400.00;
   ins.fill_price=3400.20;
   ins.spread_points=20.0;
   ins.invalidation=3395.00;
   ins.stop_points=200.0;
   ins.mfe_points=120.0;
   ins.mae_points=-40.0;
   ins.sec_to_mfe=75;
   ins.sec_to_stop=XSP_NEVER;
   for(int t=0;t<XSP_R_TIERS;t++) ins.sec_to_target[t]=XSP_NEVER;
   for(int c=0;c<XSP_CAP_TIERS;c++)
     {
      ins.move_at_cap[c]=XSP_NO_MARK;
      ins.cap_stamped[c]=false;
     }
   ins.last_r=0.6;
   ins.tracked_seconds=300;
   ins.ticks_seen=88;
   ins.closed=true;
  }

//+------------------------------------------------------------------+
//| The file path, end to end, against a scratch CSV that is deleted   |
//| again. The one case NOT exercised is the 256-slot label overflow:   |
//| it is reached only by filling the table, and its own failure print  |
//| would put an XSP_REC FAIL line into an otherwise passing log, which |
//| is exactly the string a harness grep looks for.                     |
//+------------------------------------------------------------------+
void TestCsvWriter(void)
  {
   Print("--- csv writer ---");
   CXspRecorder rec;
   XCheck("recorder opens a scratch file in the common folder",
          rec.Open("xsp_selftest.csv",2,true));
   XCheck("and reports itself open",rec.IsOpen());
   XCheck("in the common folder",rec.IsCommon());
   XCheck("the path is inside the product's own data folder",
          StringFind(rec.Path(),XSP_DATA_FOLDER)==0);
   XCheck("a provenance comment is accepted",rec.Comment("xsp selftest"));
   XCheck("the header is accepted",rec.WriteHeader());

   SXspCandidate cand; cand.Reset();
   cand.level_price=3395.00; cand.pool_kind=XSP_POOL_NONE; cand.atr_points=100.0;
   SXspRegime reg; reg.Reset();
   SXspContext ctx; ctx.Reset();
   SXspConfirm conf; conf.Reset();

   SXspInstance ins;
   XIns(ins,7,D'2026.02.11 10:00:00');

   XCheck("labels are parked at trigger",rec.Note(7,cand,reg,ctx,conf));
   XCheck("one set of labels is pending",rec.PendingLabels()==1);
   XCheck("the closed instance is written",rec.Write(ins));
   XCheck("one row is counted",rec.Rows()==1);
   XCheck("and its labels were released",rec.PendingLabels()==0);
   XCheck("no orphan so far",rec.Orphans()==0);

   //--- Writing the same id twice IS the orphan path: the labels are gone,
   //--- so the row would carry blank regime columns and fall silently out
   //--- of every cut. It must be refused and counted, not written.
   XCheck("a second write of the same id is refused",!rec.Write(ins));
   XCheck("it is counted as an orphan",rec.Orphans()==1);
   XCheck("and no row was appended for it",rec.Rows()==1);
   XCheck("the label table did not overflow",rec.LabelOverflow()==0);

   const string path=rec.Path();
   rec.Flush();
   rec.Close();
   XCheck("the recorder reports itself closed",!rec.IsOpen());
   XCheck("the scratch file exists on disk",FileIsExist(path,FILE_COMMON));
   XCheck("and the test removes it again",FileDelete(path,FILE_COMMON));
  }

//+------------------------------------------------------------------+
//| The statistics the deciles are built on. Written because SRP's     |
//| CMathUtils declares the same functions with no bodies, so these    |
//| are new code and get their own assertions.                         |
//+------------------------------------------------------------------+
void TestStats(void)
  {
   Print("--- statistics ---");
   double s[10]={1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0};

   XCheck("a value below the sample ranks at 0",
          MathAbs(CXspStats::RankFraction(0.5,s,10)-0.0)<XSP_EPSILON);
   XCheck("the sample maximum ranks at 1",
          MathAbs(CXspStats::RankFraction(10.0,s,10)-1.0)<XSP_EPSILON);
   XCheck("a value above the sample also ranks at 1",
          MathAbs(CXspStats::RankFraction(99.0,s,10)-1.0)<XSP_EPSILON);
   XCheck("the rank is the fraction at or below, not strictly below",
          MathAbs(CXspStats::RankFraction(5.5,s,10)-0.5)<XSP_EPSILON);
   XCheck("an empty sample has no rank, and says so with -1",
          CXspStats::RankFraction(1.0,s,0)<0.0);

   XCheck("the bottom of the sample is decile 0",
          CXspStats::Decile(0.5,s,10,10)==0);
   XCheck("the middle is decile 5",CXspStats::Decile(5.5,s,10,10)==5);
   XCheck("a full rank is clamped to decile 9, not 10",
          CXspStats::Decile(10.0,s,10,10)==9);
   XCheck("nine observations cannot carry ten buckets",
          CXspStats::Decile(5.0,s,9,5)==-1);
   XCheck("and the caller's own minimum is honoured",
          CXspStats::Decile(5.0,s,10,20)==-1);
   XCheck("-1 is a refusal to rank, and is NOT decile zero",
          CXspStats::Decile(5.0,s,10,20)!=0);

   XCheck("the mean is the mean",MathAbs(CXspStats::Mean(s,10)-5.5)<XSP_EPSILON);
   XCheck("an empty sample has mean 0",
          MathAbs(CXspStats::Mean(s,0))<XSP_EPSILON);

   //--- n-1, not n. Population sd would understate every small label
   //--- bucket, and small buckets are what the exploratory cuts produce.
   const double sd=CXspStats::StdDev(s,10);
   XCheck("the deviation is the SAMPLE deviation",
          MathAbs(sd-MathSqrt(82.5/9.0))<0.000000001);
   XCheck("and is measurably not the population deviation",
          MathAbs(sd-MathSqrt(82.5/10.0))>0.1);
   XCheck("one observation has no sample deviation",
          MathAbs(CXspStats::StdDev(s,1))<XSP_EPSILON);

   XCheck("an even-length median is the midpoint of the middle pair",
          MathAbs(CXspStats::Median(s,10)-5.5)<XSP_EPSILON);
   double odd[3]={3.0,1.0,2.0};
   XCheck("an odd-length median is the middle value",
          MathAbs(CXspStats::Median(odd,3)-2.0)<XSP_EPSILON);
   XCheck("and the caller's rolling window was NOT sorted in place",
          MathAbs(odd[0]-3.0)<XSP_EPSILON);
   XCheck("an empty sample has median 0",
          MathAbs(CXspStats::Median(odd,0))<XSP_EPSILON);

   long lv[4]={10,40,20,30};
   XCheck("a long median sorts by value, not by position",
          MathAbs(CXspStats::MedianLong(lv,4)-25.0)<XSP_EPSILON);
   XCheck("and leaves the tick-volume window in age order",lv[0]==10);

   XCheck("a guarded division divides",
          MathAbs(CXspStats::SafeDiv(3.0,2.0)-1.5)<XSP_EPSILON);
   XCheck("dividing by zero returns the fallback, not an error",
          MathAbs(CXspStats::SafeDiv(1.0,0.0))<XSP_EPSILON);
   XCheck("the fallback is the caller's",
          MathAbs(CXspStats::SafeDiv(1.0,0.0,-1.0)+1.0)<XSP_EPSILON);
   XCheck("a denominator inside epsilon counts as zero",
          MathAbs(CXspStats::SafeDiv(1.0,XSP_EPSILON*0.5,-1.0)+1.0)<XSP_EPSILON);
  }

//+------------------------------------------------------------------+
//| THE STOP IS DERIVED, NOT CHOSEN. This is the single most important |
//| geometric claim in the study: the stop is the distance to the      |
//| structure that invalidates the setup, plus a declared ATR buffer.  |
//| The expected value below is computed FROM XSP_STOP_BUFFER_ATR, so  |
//| changing that constant cannot leave a stale number passing here.   |
//+------------------------------------------------------------------+
void TestStopDerivation(void)
  {
   Print("--- stop derivation ---");
   const double pt=0.01;
   const double atr=100.0;
   const double ref=3400.00;
   const double raw=500.0;                       // 5.00 at 0.01 per point
   const double want=raw+XSP_STOP_BUFFER_ATR*atr;

   XCheck("a buy's stop is the distance below it plus the buffer",
          MathAbs(CXspSetupBase::StopPoints(ref,ref-raw*pt,XSP_DIR_BUY,atr,pt)-want)<0.001);
   XCheck("a sell's stop is the distance above it plus the buffer",
          MathAbs(CXspSetupBase::StopPoints(ref,ref+raw*pt,XSP_DIR_SELL,atr,pt)-want)<0.001);
   XCheck("the buffer is actually added, not merely declared",
          CXspSetupBase::StopPoints(ref,ref-raw*pt,XSP_DIR_BUY,atr,pt)>raw+0.001);

   //--- An invalidation on the wrong side is not a stop that happens to be
   //--- negative - it is a setup that cannot be measured. Refused with 0.0,
   //--- which the tracker then refuses to open.
   XCheck("a buy invalidated ABOVE the entry is refused",
          CXspSetupBase::StopPoints(ref,ref+raw*pt,XSP_DIR_BUY,atr,pt)<=0.0);
   XCheck("a sell invalidated BELOW the entry is refused",
          CXspSetupBase::StopPoints(ref,ref-raw*pt,XSP_DIR_SELL,atr,pt)<=0.0);
   XCheck("an invalidation AT the entry is refused",
          CXspSetupBase::StopPoints(ref,ref,XSP_DIR_BUY,atr,pt)<=0.0);
   XCheck("a zero ATR is refused, since the buffer would be undefined",
          CXspSetupBase::StopPoints(ref,ref-raw*pt,XSP_DIR_BUY,0.0,pt)<=0.0);
   XCheck("a zero point size is refused",
          CXspSetupBase::StopPoints(ref,ref-raw*pt,XSP_DIR_BUY,atr,0.0)<=0.0);

   //--- A wider invalidation must give a wider stop. If it did not, the
   //--- stop would be a chosen number wearing a structural label.
   const double near_stop=CXspSetupBase::StopPoints(ref,ref-100.0*pt,XSP_DIR_BUY,atr,pt);
   const double far_stop =CXspSetupBase::StopPoints(ref,ref-900.0*pt,XSP_DIR_BUY,atr,pt);
   XCheck("a more distant invalidation gives a wider stop",far_stop>near_stop);
   XCheck("and the difference is exactly the difference in distance",
          MathAbs((far_stop-near_stop)-800.0)<0.001);
  }

//+------------------------------------------------------------------+
//| The ONE confirmation, and it is BROKER TICK VOLUME - a count of    |
//| quote updates. Not traded volume, not order flow, not depth. The   |
//| assertions below test the two properties that make it usable at    |
//| all: the bar is not part of the baseline it is ranked against, and |
//| a baseline too thin to have a median records a distinguishable     |
//| refusal instead of a small ratio.                                  |
//+------------------------------------------------------------------+
void TestTickVolume(void)
  {
   Print("--- tick volume confirmation ---");

   SXspConfirm out;
   CXspTickVolume raw;
   XCheck("a non-initialised measure refuses instead of returning zeros",
          !raw.Measure(D'2026.02.11 10:00:00',1000,out));

   CXspTickVolume tv;
   XCheck("tick volume initialises",tv.Initialize(_Symbol,XSP_TF_SETUP));

   MqlRates r[];
   ArraySetAsSeries(r,true);
   XCheck("the closed setup bar is readable",
          CopyRates(_Symbol,XSP_TF_SETUP,1,1,r)==1);
   if(ArraySize(r)<1) return;

   const datetime bt=r[0].time;
   const long bv=(long)r[0].tick_volume;
   SXspConfirm a,b;
   XCheck("measure succeeds on live history",tv.Measure(bt,bv,a));
   XCheck("the result is marked valid",a.valid);
   XCheck("the bar's own tick count is carried through unchanged",
          a.tick_volume==bv);
   XCheck("the baseline never exceeds the declared 20-session window",
          a.slot_samples<=XSP_CONFIRM_SLOT_SESSIONS);

   //--- THE BAR IS NOT IN ITS OWN BASELINE. Measured indirectly, because
   //--- that is the only way it is observable from outside: change the bar
   //--- under test and the median must not move.
   XCheck("the same bar measured with a tripled tick count still succeeds",
          tv.Measure(bt,bv*3,b));
   XCheck("the baseline does not move when the bar under test changes",
          MathAbs(a.slot_median-b.slot_median)<XSP_EPSILON &&
          a.slot_samples==b.slot_samples);

   if(a.slot_samples>=3 && a.slot_median>0.0)
     {
      XCheck("the ratio is the bar over its slot median",
             MathAbs(a.ratio-(double)bv/a.slot_median)<0.0001);
      XCheck("tripling the bar triples the ratio",
             MathAbs(b.ratio-3.0*a.ratio)<0.0001);
      XCheck("the verdict is the declared threshold applied to that ratio",
             a.passed==(a.ratio>=XSP_CONFIRM_MIN_RATIO));

      SXspConfirm hi,lo;
      const long fat =(long)(a.slot_median*10.0);
      const long thin=(long)(a.slot_median*0.5);
      XCheck("a bar at ten times its median measures",tv.Measure(bt,fat,hi));
      XCheck("and confirms",hi.passed);
      XCheck("a bar at half its median measures",tv.Measure(bt,thin,lo));
      XCheck("and does not confirm",!lo.passed);
      XCheck("expansion is counted only where a median existed",
             tv.Measured()>=4);
     }
   else
     {
      //--- Fewer than three prior sessions is not a median. Recorded as
      //--- ratio 0 WITH its sample count, so the analysis can exclude the
      //--- row rather than read it as a quiet bar.
      XCheck("a baseline under three sessions records ratio 0",
             MathAbs(a.ratio)<XSP_EPSILON);
      XCheck("and does not confirm",!a.passed);
      XCheck("and is counted as thin rather than measured",
             tv.ThinBaseline()>0 && tv.Measured()==0);
      XCheck("the sample count is present so the row is excludable",
             a.slot_samples<3);
     }
  }

//+------------------------------------------------------------------+
//| THE ENTRY POINT. One verdict line, greppable by the harness.        |
//|                                                                  |
//| Ordered cheapest-first: the pure-arithmetic blocks run before the   |
//| ones that touch history, so a broken build fails on a statistic     |
//| rather than 200 assertions later on a CopyRates that returned       |
//| nothing. Nothing here places an order or writes to the study file - |
//| the only file touched is a scratch CSV that TestCsvWriter deletes.  |
//+------------------------------------------------------------------+
void RunXspCheck(void)
  {
   //--- The counters are NOT reset here. The EA asserts probe readiness
   //--- before calling this, and those assertions belong in the same
   //--- CHECKS/FAILED totals: a suite that reported PASS while its
   //--- live-history blocks had been skipped for want of a warm probe
   //--- would be the most misleading output this file could produce.

   PrintFormat("XSP_CHECK %s %s schema=%s",
               XSP_PRODUCT_NAME,XSP_PRODUCT_VERSION,XSP_SCHEMA_VERSION);
   PrintFormat("XSP_CHECK symbol=%s digits=%d point=%s",
               _Symbol,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS),
               DoubleToString(g_xpoint,10));

   TestStats();
   TestStopDerivation();
   TestEventIdentity();
   TestSetupS1();
   TestSetupS2();
   TestPools();
   TestTracker();
   TestRecorderSchema();
   TestCsvWriter();
   TestTickVolume();

   //--- Context for anyone reading a failure: what the live components
   //--- actually held while the history-dependent blocks ran.
   Print("--- state ---");
   Print(g_xregime.Describe());
   Print(g_xswings.Describe());
   Print(g_xcontext.Describe());
   Print(g_xpools.Describe());

   PrintFormat("XSP_CHECK CHECKS=%d FAILED=%d VERDICT=%s",
               g_xchecks,g_xfailed,(g_xfailed==0?"PASS":"FAIL"));
  }

#endif // XSP_TESTS_XSPCHECK_MQH
//+------------------------------------------------------------------+
