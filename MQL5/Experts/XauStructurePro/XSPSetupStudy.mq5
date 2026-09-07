//+------------------------------------------------------------------+
//|                                                XSPSetupStudy.mq5 |
//|        XauStructurePro - PHASE A : does an edge exist at all here? |
//|                                                                  |
//|   THIS EA CANNOT TRADE. No <Trade/Trade.mqh>, no OrderSend, no CTrade,  |
//|   no position code of any kind is compiled into it. That is deliberate  |
//|   and it is the point of Phase A: SRP 1.11 was measured through its     |
//|   own order path, so every number it produced was entangled with the    |
//|   execution layer, and when the result came out negative there was no   |
//|   way to tell a bad signal from a bad fill. Here the signal is          |
//|   measured alone.                                                      |
//|                                                                  |
//|   WHAT IT DOES. On every closed M15 bar it asks two setups whether the  |
//|   bar produced a candidate. Each candidate is fingerprinted so ONE      |
//|   market occurrence yields ONE instance - the defect-2 fix, and the     |
//|   reason n means what the statistics assume it means. Each instance is  |
//|   then tracked forward tick by tick for up to 60 minutes, and one CSV   |
//|   row is written when it resolves.                                     |
//|                                                                  |
//|   WHAT IT DOES NOT DO. It does not gate on H1 alignment, on the        |
//|   volatility or spread decile, or on the tick-volume confirmation.      |
//|   Every one of those is written as a COLUMN. Gating here would delete   |
//|   the counterfactual and make each filter cost a separate pass over     |
//|   the tape - which is the parameter sweep audit 4.4 already showed      |
//|   buys nothing. Recorded, never enforced.                              |
//|                                                                  |
//|   COSTS ARE NOT SIMULATED, THEY ARE RECORDED AND CHARGED AFTERWARDS.    |
//|   Barriers are measured on the BID for both directions, so the          |
//|   measurement is spread-free; the raw spread at trigger is a column.    |
//|   The section 9.3 pessimistic model - 7 points commission round trip,   |
//|   spread stressed to 1.5x observed - is therefore a RECOMPUTATION over  |
//|   this file and not a second run over the tape.                         |
//|                                                                  |
//|   RUN IT WITH REAL TICKS (Model 4). On generated bars the provenance    |
//|   block will say so and refuse to call the run quotable: audit 6.2      |
//|   measured OHLC-modelled spread at 4.0-4.4 points against 9.5-33.5 on   |
//|   the real tape, so a bar-generated pass understates cost about         |
//|   threefold and flatters every row it writes.                          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property description "XauStructurePro Phase A: records candidate setups and tracks their barriers. Places no orders."

#include <XauStructurePro/Core/XspTypes.mqh>
#include <XauStructurePro/Regime/CXspRegime.mqh>
#include <XauStructurePro/Context/CXspSwings.mqh>
#include <XauStructurePro/Context/CXspHtfContext.mqh>
#include <XauStructurePro/Liquidity/CXspPools.mqh>
#include <XauStructurePro/Liquidity/CXspStructureEvents.mqh>
#include <XauStructurePro/Setups/CXspContinuation.mqh>
#include <XauStructurePro/Setups/CXspReversal.mqh>
#include <XauStructurePro/Setups/CXspTickVolume.mqh>
#include <XauStructurePro/Research/CXspBarrierTracker.mqh>
#include <XauStructurePro/Research/CXspRecorder.mqh>
//--- Reused BY INCLUDE from the frozen tree, which is not modified. It
//--- pulls in only Core/Types/Enums.mqh, so nothing else from SRP comes
//--- with it and the two trees stay independent.
#include <ScalpRobotPro/Runtime/CRunProvenance.mqh>

//--- The segment this pass is allowed to be quoted as. DEV is the 9.1
//--- development slice; the plan's VAL maps onto SRP_SEGMENT_OOS, which is
//--- the same declaration under the older name. UNDECLARED makes the run
//--- unquotable on purpose, and that is the correct setting for a smoke
//--- test over arbitrary dates.
input ENUM_SRP_DATA_SEGMENT InpDataSegment   = SRP_SEGMENT_UNDECLARED;
//--- The literal is written out rather than XSP_STUDY_FILE, and that is
//--- deliberate. makeset.ps1 builds a COMPLETE .set by reading this source
//--- text, so a macro name here would be copied into the .set verbatim and
//--- would arrive as the FILENAME - the study would write to a file called
//--- "XSP_STUDY_FILE" and the analysis would report no data, with nothing in
//--- either log to say why. OnInit asserts the two agree, so the constant
//--- still governs and a divergence is reported rather than discovered later.
input string   InpStudyFile      = "xsp_instances.csv"; // CSV name, in the data folder
input bool     InpUseCommonFolder= true;             // write to the shared Files folder
//--- The cost the ANALYSIS will charge, declared here so the provenance
//--- block records it. Nothing in this EA spends it: there is no order.
input double   InpCommissionPts  = 7.0;              // round-turn commission, points
input bool     InpPrintCensus    = true;             // progress lines to the log

//--- How often the progress line is printed, in closed setup bars. 960 M15
//--- bars is ten trading days, so a nine-month DEV pass prints about thirty
//--- lines: enough to see a stalled run, few enough to leave the log
//--- readable. It is a logging interval and nothing reads it.
#define XSP_STUDY_PROGRESS_BARS       960

CXspRegime            g_regime;
CXspSwings            g_swings;
CXspHtfContext        g_context;
CXspPools            *g_pools  = NULL;
CXspStructureEvents  *g_events = NULL;
CXspContinuation      g_s1;
CXspReversal          g_s2;
CXspTickVolume        g_tickvol;
CXspBarrierTracker    g_tracker;
CXspRecorder          g_recorder;
CRunProvenance        g_prov;

double   g_point      = 0.0;
datetime g_last_bar   = 0;
bool     g_ready      = false;
long     g_bars_seen  = 0;   // closed setup bars actually evaluated
long     g_warmup     = 0;   // bars skipped while history was not there yet
long     g_no_stop    = 0;   // candidates whose invalidation was already gone
long     g_no_confirm = 0;   // candidates whose tick-volume read failed
long     g_no_label   = 0;   // candidates whose regime or context snapshot failed
bool     g_closed_out = false;

//+------------------------------------------------------------------+
//| WHY THE PROVENANCE IS SPLIT BETWEEN THE TOP AND THE BOTTOM.        |
//|                                                                  |
//| Half of what makes a run quotable is DECLARED and known at init -   |
//| build, schema, symbol, segment, the cost the analysis will charge.   |
//| The other half is MEASURED over the pass: the inferred tick model,   |
//| the observed spread range, the quotable verdict that depends on      |
//| them. A CSV cannot be edited at the top after the fact, so the       |
//| declared half is the preamble and the measured half is a trailing    |
//| comment written when the run ends.                                  |
//|                                                                  |
//| That split is a feature rather than a compromise: a pass that died   |
//| mid-run has no trailing block, so the analysis script can refuse the |
//| file instead of quoting a partial sample as a whole one. This is     |
//| exactly the symptom the harness's malformed OOS window showed.       |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(g_point<=0.0)
     {
      Print("XSP_STUDY FAIL cannot read SYMBOL_POINT");
      return(INIT_FAILED);
     }
   const int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);

   //--- The default above is a literal for makeset.ps1's benefit; this is what
   //--- keeps XSP_STUDY_FILE the single source of truth for it. Reported, not
   //--- fatal: naming a different file is a legitimate thing to do on a smoke
   //--- run, and the analysis script is told the path by the caller anyway.
   if(InpStudyFile!=XSP_STUDY_FILE)
      PrintFormat("XSP_STUDY note output '%s' differs from the declared "
                  "XSP_STUDY_FILE '%s' - the analysis must be pointed at it",
                  InpStudyFile,XSP_STUDY_FILE);

   g_events=new CXspStructureEvents();
   g_pools =new CXspPools();
   if(g_events==NULL || g_pools==NULL)
     {
      Print("XSP_STUDY FAIL out of memory");
      return(INIT_FAILED);
     }
   g_events.Configure(digits);

   if(!g_pools.Initialize(_Symbol,g_point)                 ||
      !g_regime.Initialize(_Symbol,XSP_TF_SETUP,g_point)   ||
      !g_swings.Initialize(_Symbol,XSP_TF_SETUP,3,300)     ||
      !g_context.Initialize(_Symbol)                       ||
      !g_tickvol.Initialize(_Symbol,XSP_TF_SETUP)          ||
      !g_s1.Initialize(_Symbol,XSP_TF_SETUP,g_point,g_events) ||
      !g_s2.Initialize(_Symbol,XSP_TF_SETUP,g_point,g_events))
     {
      Print("XSP_STUDY FAIL a component refused to initialise");
      return(INIT_FAILED);
     }
   g_s2.SetPools(g_pools);
   g_tracker.Configure(g_point);

   //--- DECLARED HONESTLY, and each of these three is a claim that can be
   //--- checked against the code:
   //---   startup spread 0.00 - no distance in this run descends from a
   //---     spread sample. Stops come from the invalidation plus an ATR
   //---     buffer, and the barriers are measured on the bid.
   //---   commission - what the ANALYSIS will charge. Nothing here spends
   //---     it; there is no order path to spend it in.
   //---   geometry pinned with zero derived distances - the same statement
   //---     from the other side: a rerun over the same dates and inputs
   //---     measures identical distances because none of them were sampled.
   //--- SetServerFillEvidence is deliberately NOT called: it would report
   //--- on broker-fired exits, and this EA has none.
   g_prov.Configure(_Symbol,XSP_TF_SETUP);
   g_prov.SetSegment(InpDataSegment);
   g_prov.SetCostModel(0.0,InpCommissionPts,0.0,0.0,0.0,0.0);
   g_prov.SetGeometry(0.0,true,0);

   if(!g_recorder.Open(InpStudyFile,digits,InpUseCommonFolder))
     {
      PrintFormat("XSP_STUDY FAIL cannot open '%s' (common=%s)",
                  InpStudyFile,(InpUseCommonFolder?"yes":"no"));
      return(INIT_FAILED);
     }

   //--- The XSP identity line. CRunProvenance belongs to the frozen tree
   //--- and stamps ITS product name and version into every block it writes,
   //--- so a block from this EA would read as "Scalping Robot Pro". Rather
   //--- than edit the baseline, the true build sits on its own adjacent
   //--- line - and it carries the schema version the analysis asserts and
   //--- the DEV/VAL naming, which CRunProvenance has no field for.
   g_recorder.Comment(StringFormat(
                         "xsp: build=%s %s; schema=%s; setup_tf=%s; exec_tf=%s; "
                         "r_tiers=%.2f/%.2f/%.2f/%.2f; caps_sec=%d/%d/%d/%d; "
                         "stop=invalidation+%.2f*ATR%d; pool_tol=%.2f*ATR; "
                         "sweep_window=%d bars; confirm=broker_tick_volume "
                         "vs same-minute median over %d sessions, ratio>=%.2f; "
                         "segment_naming=DEV|VAL where VAL==SRP_SEGMENT_OOS",
                         XSP_PRODUCT_NAME,XSP_PRODUCT_VERSION,XSP_SCHEMA_VERSION,
                         EnumToString(XSP_TF_SETUP),EnumToString(XSP_TF_EXEC),
                         XspRTier(0),XspRTier(1),XspRTier(2),XspRTier(3),
                         XspCapSeconds(0),XspCapSeconds(1),
                         XspCapSeconds(2),XspCapSeconds(3),
                         XSP_STOP_BUFFER_ATR,XSP_ATR_PERIOD,
                         XSP_POOL_TOLERANCE_ATR,XSP_SWEEP_WINDOW_BARS,
                         XSP_CONFIRM_SLOT_SESSIONS,XSP_CONFIRM_MIN_RATIO));

   //--- What the measurement is NOT. Written into the file itself so no
   //--- extract of it can be read as an order-flow study.
   g_recorder.Comment("xsp_caveats: barriers measured on the BID for both "
                      "directions so the measurement is spread-free; costs are "
                      "charged in post-processing from spread_pts_at_trigger. "
                      "broker_tick_volume is a count of QUOTE UPDATES - not "
                      "traded volume; not order flow; not depth of market. "
                      "XAUUSD spot is not centrally cleared and no MarketBook "
                      "call exists in this codebase. Liquidity pools are PRICE "
                      "LEVELS with a hypothesis attached, not observed orders. "
                      "Every label is recorded and NONE is gated.");

   g_recorder.Comment(StringFormat("xsp_declared: %s | %s | segment=%s",
                                   g_prov.CostModelText(),g_prov.GeometryText(),
                                   g_prov.SegmentText()));

   if(!g_recorder.WriteHeader())
     {
      Print("XSP_STUDY FAIL cannot write the schema header");
      return(INIT_FAILED);
     }

   g_ready=true;
   PrintFormat("XSP_STUDY %s %s schema=%s file='%s' common=%s segment=%s",
               XSP_PRODUCT_NAME,XSP_PRODUCT_VERSION,XSP_SCHEMA_VERSION,
               g_recorder.Path(),(g_recorder.IsCommon()?"yes":"no"),
               g_prov.SegmentText());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Drain the tracker's queue into the CSV. Called on EVERY tick.      |
//|                                                                  |
//| Not once at the end: the tracker holds 256 slots and REPORTS a      |
//| lost instance rather than overwriting one, so a study that drained   |
//| only on deinit would either be bounded at 256 rows or print a       |
//| failure line for every instance past that. Draining per tick keeps   |
//| the queue at the handful that resolved on the same tick.            |
//+------------------------------------------------------------------+
void Drain(void)
  {
   SXspInstance ins;
   while(g_tracker.PopClosed(ins))
      g_recorder.Write(ins);
  }

//+------------------------------------------------------------------+
//| One candidate becomes one tracked instance - or one COUNTED refusal.|
//|                                                                  |
//| THE FINGERPRINT IS ALREADY SPENT when this runs. Evaluate() claimed  |
//| it, so any path out of here that does not open an instance has       |
//| consumed a market occurrence without recording it. That is why the    |
//| three refusals below are counted and reported: the census asserts     |
//| that emitted candidates equal opened instances plus refusals, and a   |
//| study that dropped an awkward candidate quietly would break it.       |
//|                                                                  |
//| Checking the stop BEFORE claiming would avoid the spend, and would    |
//| also mean the same occurrence re-detects and re-claims on the next    |
//| bar - which is defect 2 arriving through the back door. Spending the  |
//| fingerprint and reporting the loss is the lesser cost.               |
//+------------------------------------------------------------------+
void TryOpen(const SXspCandidate &cand,const MqlTick &tick,const MqlRates &rates[])
  {
   //--- Derived from the BID, because the barriers are measured on the bid.
   //--- Deriving it from the ask for a buy would place the stop one spread
   //--- further from the series it is compared against, and nothing in the
   //--- file would show it: every column would stay internally consistent
   //--- while measuring a stop nobody declared.
   const double stop=CXspSetupBase::StopPoints(tick.bid,cand.invalidation,
                                               cand.dir,cand.atr_points,g_point);
   if(!(stop>0.0))
     {
      //--- The invalidation is already on the wrong side of the first
      //--- available price: price gapped through the level between the bar
      //--- close and this tick. A real market event, not an error.
      g_no_stop++;
      return;
     }

   SXspRegime  reg;
   SXspContext ctx;
   //--- shift 1 is the CLOSED bar the candidate came from, so the ATR and
   //--- its decile describe the conditions the setup FORMED in rather than
   //--- the conditions at this instant.
   if(!g_regime.Snapshot(tick,1,cand.event_bar_time,reg) ||
      !g_context.Snapshot(cand.dir,tick.bid,ctx))
     {
      g_no_label++;
      return;
     }
   //--- L1 measures trend; L2 only carries it. CXspRegime::Snapshot leaves
   //--- this field alone on purpose, and this is its single owner.
   reg.trend=ctx.h1_trend;

   SXspConfirm conf;
   //--- Bar time and tick count are read from the SAME struct, so they
   //--- cannot end up describing two different bars. rates[1] is the closed
   //--- trigger bar, which is what both setups record as event_bar_time.
   if(!g_tickvol.Measure(rates[1].time,(long)rates[1].tick_volume,conf))
     {
      g_no_confirm++;
      return;
     }

   long id=0;
   //--- A refusal here is already counted by the tracker itself, as
   //--- RejectedCapacity or RejectedGeometry, so it is not counted twice.
   if(!g_tracker.Open(cand,tick,stop,id))
      return;
   g_recorder.Note(id,cand,reg,ctx,conf);
  }

//+------------------------------------------------------------------+
//| A closed setup bar - the ONLY place candidates are asked for.       |
//|                                                                  |
//| Both setups are asked, and both may fire on the same bar. They are   |
//| separate hypotheses with separate fingerprints, so two instances     |
//| from one bar are two instances; the analysis can collapse them by    |
//| bar time if it wants to. Gating one on the other here would delete   |
//| the overlap from the file permanently.                              |
//+------------------------------------------------------------------+
void OnSetupBar(const MqlTick &tick)
  {
   g_bars_seen++;

   //--- All three are refreshed before any is tested, so a bar is skipped
   //--- for a stated reason rather than evaluated against a stale H1 class.
   const bool ok_regime =g_regime.RefreshBars();
   const bool ok_swings =g_swings.Refresh();
   const bool ok_context=g_context.Refresh();
   if(!ok_regime || !ok_swings || !ok_context || !g_regime.IsReady())
     {
      //--- Warming up, or a history gap. Skipped AND COUNTED: a bar that was
      //--- never evaluated must not be indistinguishable from a bar that was
      //--- evaluated and produced nothing.
      g_warmup++;
      return;
     }

   const double atr=g_regime.AtrPoints(1);
   if(!(atr>0.0))
     {
      g_warmup++;
      return;
     }

   //--- The pool tolerance is ATR-scaled and the ATR lives in L2, so it is
   //--- computed here and passed in. One owner per measurement.
   g_pools.Refresh(g_swings,XSP_POOL_TOLERANCE_ATR*atr);

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   //--- S2 reads back to shift XSP_SWEEP_WINDOW_BARS and wants a bar of
   //--- margin beyond it. Index 0 is the FORMING bar; it is copied because
   //--- both setups are written against a series where index 1 is the bar
   //--- that just closed, and no path in either of them reads index 0.
   const int need=XSP_SWEEP_WINDOW_BARS+3;
   if(CopyRates(_Symbol,XSP_TF_SETUP,0,need,rates)<need)
     {
      g_warmup++;
      return;
     }

   SXspCandidate cand;
   if(g_s1.Evaluate(rates,need,atr,cand)) TryOpen(cand,tick,rates);
   if(g_s2.Evaluate(rates,need,atr,cand)) TryOpen(cand,tick,rates);

   if(InpPrintCensus && (g_bars_seen%XSP_STUDY_PROGRESS_BARS)==0)
      PrintFormat("XSP_STUDY progress bars=%I64d skipped=%I64d rows=%I64d "
                  "live=%d emitted s1=%I64d s2=%I64d",
                  g_bars_seen,g_warmup,g_recorder.Rows(),g_tracker.LiveCount(),
                  g_s1.Emitted(),g_s2.Emitted());
  }

//+------------------------------------------------------------------+
//| TICK ORDER, AND WHY IT IS THIS ORDER.                              |
//|                                                                  |
//|   1. provenance and the spread ring observe the tick                |
//|   2. LIVE INSTANCES ADVANCE                                        |
//|   3. resolved instances drain to the CSV                            |
//|   4. only then may a new candidate open on this tick                |
//|                                                                  |
//| Step 2 before step 4 is the load-bearing one. An instance opened at  |
//| step 4 and then advanced by the SAME tick would count its own        |
//| trigger tick as a tick of forward evidence: ticks_seen would start   |
//| at 1 for a price that is by definition its entry, and a zero         |
//| excursion measured at age 0 would be attributed to the future.       |
//| Advancing first makes the first tick that can resolve anything the   |
//| first tick that ARRIVED AFTER the trigger.                          |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   if(!g_ready)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;
   if(tick.bid<=0.0)
      return;

   g_prov.ObserveTick(tick,g_point);
   g_regime.ObserveTick(tick);

   g_tracker.OnTick(tick);
   Drain();

   //--- A NEW setup bar means the previous one has closed. Everything below
   //--- reads shift 1 and higher, so no path here can see the bar that is
   //--- still forming.
   const datetime bar=iTime(_Symbol,XSP_TF_SETUP,0);
   if(bar==0 || bar==g_last_bar)
      return;
   g_last_bar=bar;
   OnSetupBar(tick);
  }

//+------------------------------------------------------------------+
//| THE CENSUS, arranged to be CHECKED rather than read.                |
//|                                                                  |
//| Three identities must hold, and they are asserted here rather than   |
//| left for a reader to add up:                                        |
//|                                                                  |
//|   emitted(S1) + emitted(S2) = opened + refusals                     |
//|   opened                    = stopped + targets + timeouts + unres.  |
//|   rows + orphans            = stopped + targets + timeouts + unres.  |
//|                                                                  |
//| A study that silently dropped an awkward candidate, or lost a row to |
//| a full queue, breaks one of the three. RECONCILED=NO is therefore a  |
//| louder failure than any individual counter looking surprising, and   |
//| it is written into the CSV as well as the log so the analysis can    |
//| refuse the file without being told.                                 |
//+------------------------------------------------------------------+
string CensusLine(const string reason)
  {
   if(g_events==NULL || g_pools==NULL)
      return("xsp_census: unavailable - initialisation did not complete");

   const long emitted=g_s1.Emitted()+g_s2.Emitted();
   const long refused=g_no_stop+g_no_label+g_no_confirm
                      +g_tracker.RejectedCapacity()+g_tracker.RejectedGeometry();
   const long retired=g_tracker.ClosedByStop()+g_tracker.ClosedByTargets()
                      +g_tracker.ClosedByTimeout()+g_tracker.ClosedUnresolved();
   const bool ok=(emitted==g_tracker.OpenedTotal()+refused)
                 && (g_tracker.OpenedTotal()==retired)
                 && (g_recorder.Rows()+g_recorder.Orphans()==retired)
                 && (g_tracker.LiveCount()==0)
                 && (g_recorder.PendingLabels()==0);

   return(StringFormat(
             "xsp_census: end=%s; setup_bars=%I64d; skipped_warmup=%I64d; "
             "s1 detected=%I64d emitted=%I64d suppressed=%I64d; "
             "s2 detected=%I64d emitted=%I64d suppressed=%I64d ambiguous=%I64d; "
             "events claims=%I64d refusals=%I64d remembered=%d; "
             "refused no_stop=%I64d no_label=%I64d no_confirm=%I64d "
             "rej_capacity=%I64d rej_geometry=%I64d; "
             "opened=%I64d stopped=%I64d all_targets=%I64d timeout=%I64d "
             "unresolved=%I64d still_live=%d; "
             "rows=%I64d orphans=%I64d label_overflow=%I64d pending_labels=%d; "
             "tickvol measured=%I64d thin_baseline=%I64d; "
             "pool_rebuilds=%I64d; swing_rebuilds=%I64d; RECONCILED=%s",
             reason,g_bars_seen,g_warmup,
             g_s1.Detected(),g_s1.Emitted(),g_s1.Suppressed(),
             g_s2.Detected(),g_s2.Emitted(),g_s2.Suppressed(),g_s2.Ambiguous(),
             g_events.Claims(),g_events.Refusals(),g_events.Remembered(),
             g_no_stop,g_no_label,g_no_confirm,
             g_tracker.RejectedCapacity(),g_tracker.RejectedGeometry(),
             g_tracker.OpenedTotal(),g_tracker.ClosedByStop(),
             g_tracker.ClosedByTargets(),g_tracker.ClosedByTimeout(),
             g_tracker.ClosedUnresolved(),g_tracker.LiveCount(),
             g_recorder.Rows(),g_recorder.Orphans(),g_recorder.LabelOverflow(),
             g_recorder.PendingLabels(),
             g_tickvol.Measured(),g_tickvol.ThinBaseline(),
             g_pools.Rebuilds(),g_swings.Rebuilds(),
             (ok?"yes":"NO")));
  }

//+------------------------------------------------------------------+
//| End of run. Runs ONCE, from whichever of OnTester / OnDeinit fires   |
//| first, which is why it is guarded rather than idempotent by luck.    |
//|                                                                  |
//| The MEASURED half of the provenance is written here as trailing       |
//| comments, for the reason given at the top of this file: the inferred  |
//| tick model and the observed spread range are not knowable at init,    |
//| and a CSV cannot be edited at the top afterwards.                    |
//+------------------------------------------------------------------+
void Finalise(const string reason)
  {
   if(g_closed_out)
      return;
   g_closed_out=true;

   //--- Everything still live is retired UNRESOLVED and written. Not
   //--- discarded, which would bias the sample toward whatever slow
   //--- instances happen to do, and not called flat, which would assign an
   //--- outcome nobody observed. The analysis reports the fraction.
   g_tracker.FlushUnresolved();
   Drain();

   const string census=CensusLine(reason);

   //--- HeaderCsv() already opens with "# provenance:" and Comment() adds
   //--- its own "# ", so the prefix is stripped rather than doubled.
   string prov=g_prov.HeaderCsv();
   if(StringSubstr(prov,0,2)=="# ")
      prov=StringSubstr(prov,2);
   g_recorder.Comment(prov);
   g_recorder.Comment(census);
   g_recorder.Flush();
   g_recorder.Close();

   //--- The EXECUTION line of the provenance block exists to describe the
   //--- order path. Stating that there is none is more useful than leaving
   //--- it blank, and it is the same claim the file header makes.
   Print(g_prov.Header("none - no order function is compiled into this EA, "
                       "so there are no fills to report"));
   PrintFormat("XSP BUILD  : %s %s schema=%s  (the block above names the frozen "
               "SRP build CRunProvenance belongs to, not this one)",
               XSP_PRODUCT_NAME,XSP_PRODUCT_VERSION,XSP_SCHEMA_VERSION);
   Print("XSP_STUDY ",census);
   PrintFormat("XSP_STUDY file='%s' common=%s rows=%I64d QUOTABLE=%s",
               g_recorder.Path(),(g_recorder.IsCommon()?"yes":"no"),
               g_recorder.Rows(),(g_prov.IsQuotable()?"yes":"NO"));
   Print("--- state ---");
   Print(g_regime.Describe());
   Print(g_swings.Describe());
   Print(g_context.Describe());
   //--- Both are heap objects and both are NULL if OnInit failed before
   //--- allocating them, in which case OnDeinit still runs and still lands
   //--- here. Guarded rather than assumed.
   if(g_pools !=NULL) Print(g_pools.Describe());
   if(g_events!=NULL) Print(g_events.Describe());
   Print(g_recorder.Describe());
  }

//+------------------------------------------------------------------+
//| Returns ZERO on purpose.                                           |
//|                                                                  |
//| A custom criterion is a fitness function, and a fitness function      |
//| over this pass is the parameter sweep audit 4.4 already priced at     |
//| nothing. Phase A has no parameter an optimiser could vary and no      |
//| P&L to rank: it records a population and the arithmetic happens in    |
//| _build/xspstudy.py, where it can be inspected.                       |
//+------------------------------------------------------------------+
double OnTester(void)
  {
   Finalise("OnTester");
   return(0.0);
  }

void OnDeinit(const int reason)
  {
   Finalise(StringFormat("OnDeinit reason=%d",reason));
   //--- Deleted AFTER Finalise: the census reads the event registry, and
   //--- CXspReversal still holds the pool pointer until this returns.
   if(g_events!=NULL) { delete g_events; g_events=NULL; }
   if(g_pools !=NULL) { delete g_pools;  g_pools =NULL; }
  }
//+------------------------------------------------------------------+
