//+------------------------------------------------------------------+
//|                                              CRunProvenance.mqh |
//|                  Scalping Robot Pro - Runtime (HARNESS v2, FIX 4) |
//|                                                                  |
//|   WHAT THIS IS FOR.                                              |
//|                                                                  |
//|   Every number this system has ever produced was reported without |
//|   saying how it was produced. The audit found three assumptions   |
//|   doing the most damage, all of them invisible in the output:     |
//|                                                                  |
//|     1. the tick model. A 1-minute-OHLC pass fills stops exactly   |
//|        at the stop price and takes spread from the bar record, so |
//|        it flatters a scalping system by construction.            |
//|     2. the cost model. Commission sat at 0.0, and the measured    |
//|        logs confirm net P/L was the raw price move to the cent.   |
//|     3. in-sample versus out-of-sample. Nothing recorded which a   |
//|        given run was, so every result read as a validation.       |
//|                                                                  |
//|   This class stamps all three into the report at GENERATION time, |
//|   so a figure cannot be separated from the conditions that made   |
//|   it. It observes and formats; it decides nothing and can move    |
//|   no order.                                                      |
//|                                                                  |
//|   THE TICK MODEL IS INFERRED, NOT REPORTED. MQL5 exposes no API   |
//|   for the tester's tick-generation mode, so an operator's word is |
//|   the only alternative and an operator's word is what produced    |
//|   the problem. Two measurements separate the modes; both are      |
//|   printed alongside the verdict so the inference is auditable     |
//|   rather than trusted.                                           |
//+------------------------------------------------------------------+
#ifndef SRP_RUNTIME_CRUNPROVENANCE_MQH
#define SRP_RUNTIME_CRUNPROVENANCE_MQH

#include "../Core/Types/Constants.mqh"
//--- ENUM_SRP_TICK_MODEL and ENUM_SRP_DATA_SEGMENT. They live in the
//--- shared enum header, not here: the EA declares an `input` of the
//--- segment type and CConfigurationBuilder carries it, and neither of
//--- those may take a dependency on Runtime\.
#include "../Core/Types/Enums.mqh"

//--- Histogram bounds. A bucket per observed count, plus one overflow
//--- bucket, so the median is exact inside the range and saturating
//--- above it - which is all that is needed, because every threshold
//--- that matters sits far below the cap.
#define SRP_PROV_TICK_BUCKETS      257   // 0..255 ticks, 256 = "or more"
#define SRP_PROV_SPREAD_BUCKETS     65   // 0..63 distinct, 64 = "or more"
#define SRP_PROV_SPREAD_TRACK       64   // distinct spreads tracked per bar

//+------------------------------------------------------------------+
//| CRunProvenance                                                    |
//|                                                                  |
//| Passive. Holds no pointer to anything that can trade, exposes no  |
//| method that returns a decision, and is safe to call on every tick |
//| because the per-bar work is bounded by SRP_PROV_SPREAD_TRACK.     |
//+------------------------------------------------------------------+
class CRunProvenance
  {
private:
   //--- identity of the run
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   //--- tape observation, current bar
   datetime          m_bar_minute;      // minute bucket being filled
   int               m_bar_ticks;       // ticks seen in it
   int               m_bar_spreads[SRP_PROV_SPREAD_TRACK];
   int               m_bar_spread_count;

   //--- tape observation, run totals
   int               m_tick_hist[SRP_PROV_TICK_BUCKETS];
   int               m_spread_hist[SRP_PROV_SPREAD_BUCKETS];
   long              m_ticks;
   long              m_bars;
   datetime          m_first_tick;
   datetime          m_last_tick;
   int               m_spread_min;      // points, whole run
   int               m_spread_max;
   double            m_spread_sum;

   //--- declared cost model, copied from the controller that uses it
   bool              m_cost_declared;
   double            m_cost_init_spread;
   double            m_cost_commission;
   double            m_cost_execution;
   double            m_cost_reward_ratio;
   double            m_cost_target_min;
   double            m_cost_early_exit_min;

   //--- declared data segment
   ENUM_SRP_DATA_SEGMENT m_segment;

   //--- HARNESS v2, FIX 5. THE DECLARED GEOMETRY ROOT.
   //---
   //--- The sample twelve trading distances descend from, and whether it was
   //--- pinned by input or read from whichever tick happened to be current.
   //--- Held here rather than inferred, because the header's job is to state
   //--- what produced the run and this is the single largest thing that was
   //--- missing: two runs over identical dates, identical inputs and
   //--- identical tick data can trade different stops, and until now nothing
   //--- printed by either run would have shown it.
   bool              m_geom_declared;
   double            m_geom_sample;
   bool              m_geom_pinned;
   int               m_geom_derived_count;

   //--- declared execution evidence. Handed in by the engine rather than
   //--- measured here: fix 2 already counts server-side fills, and a second
   //--- counter would be a second answer to the same question. It lives in
   //--- this class so that ONE object decides whether a run is quotable -
   //--- otherwise the header could print a warning above QUOTABLE: yes.
   bool              m_srv_declared;
   long              m_srv_exits;
   bool              m_srv_exact_fills;

   //--- helpers
   void              CloseBar(void);
   int               MedianOf(const int &hist[],const int buckets) const;

public:
                     CRunProvenance(void);
   void              Configure(const string symbol,
                               const ENUM_TIMEFRAMES timeframe);
   void              Reset(void);
   //--- observation. Called once per tick from the engine, before any
   //--- filter, so the tape is measured as delivered rather than as
   //--- sampled by whatever throttle is active.
   void              ObserveTick(const MqlTick &tick,const double point);

   //--- declarations made by the rest of the system
   void              SetCostModel(const double init_spread,
                                  const double commission,
                                  const double execution,
                                  const double reward_ratio,
                                  const double target_min,
                                  const double early_exit_min);
   void              SetSegment(const ENUM_SRP_DATA_SEGMENT segment);
   //--- HARNESS v2, FIX 5. Declares the root of the trade geometry and how
   //--- many of the twelve distances actually descend from it on this run -
   //--- a profile that presets all twelve is unaffected by the sample, and a
   //--- warning that cannot distinguish the two cases is noise.
   void              SetGeometry(const double sample_points,
                                 const bool pinned,
                                 const int derived_count);
   //--- Fix 2's server-exit aggregates, restated as evidence. `all_exact`
   //--- means every broker-fired exit filled at precisely its trigger price,
   //--- which is the tick model doing it and not the broker.
   void              SetServerFillEvidence(const long exits,
                                           const bool all_exact);

   //--- measurements
   long              Ticks(void)            const { return(m_ticks); }
   long              Bars(void)             const { return(m_bars);  }
   int               MedianTicksPerBar(void)   const;
   int               MedianSpreadsPerBar(void) const;
   double            AverageSpreadPoints(void) const;
   int               SpreadMinPoints(void)  const { return(m_spread_min); }
   int               SpreadMaxPoints(void)  const { return(m_spread_max); }

   //--- verdicts
   ENUM_SRP_TICK_MODEL TickModel(void)      const;
   bool              IsGeneratedTape(void)  const;
   ENUM_SRP_DATA_SEGMENT Segment(void)      const { return(m_segment); }
   bool              SegmentContradicted(void) const;

   //--- formatting
   string            TickModelText(void)    const;
   string            SegmentText(void)      const;
   string            CostModelText(void)    const;
   //--- HARNESS v2, FIX 5. One line: the root, its provenance, and how much
   //--- of the geometry hangs off it.
   string            GeometryText(void)     const;
   //--- `extra_line` is printed INSIDE the block, above the verdict. The
   //--- engine uses it for the execution summary: a fill-quality figure that
   //--- is meaningless unless the tick model is read in the same breath, so
   //--- the two are never allowed to appear in separate places.
   string            Header(const string extra_line="") const;
   string            HeaderCsv(void)        const;
   //--- The same facts as CSV COLUMNS rather than one line, for a file that
   //--- holds one row PER RUN - the optimisation pass export. A preamble
   //--- cannot serve that file: it would describe the first pass and be read
   //--- as describing all of them, which is the confusion this fix exists to
   //--- end. The two must be kept in step; they are adjacent for that reason.
   string            CsvColumns(void)       const;
   string            CsvValues(void)        const;
   string            Warnings(void)         const;
   //--- The single question a reader of a report actually has: may this
   //--- number be quoted? False whenever ANY warning is outstanding, so
   //--- the answer cannot drift away from the warning list.
   bool              IsQuotable(void)       const;
  };

//+------------------------------------------------------------------+
//| Construction. Nothing is inferred from an empty observation set;  |
//| every getter must be safe to call on a run that never ticked.     |
//+------------------------------------------------------------------+
CRunProvenance::CRunProvenance(void) : m_symbol(""),
                                       m_timeframe(PERIOD_CURRENT)
  {
   Reset();
  }

void CRunProvenance::Configure(const string symbol,
                               const ENUM_TIMEFRAMES timeframe)
  {
   m_symbol=symbol;
   m_timeframe=timeframe;
  }

void CRunProvenance::Reset(void)
  {
   ArrayInitialize(m_tick_hist,0);
   ArrayInitialize(m_spread_hist,0);
   ArrayInitialize(m_bar_spreads,0);
   m_bar_minute=0;
   m_bar_ticks=0;
   m_bar_spread_count=0;
   m_ticks=0;
   m_bars=0;
   m_first_tick=0;
   m_last_tick=0;
   m_spread_min=0;
   m_spread_max=0;
   m_spread_sum=0.0;
   m_cost_declared=false;
   m_cost_init_spread=0.0;
   m_cost_commission=0.0;
   m_cost_execution=0.0;
   m_cost_reward_ratio=0.0;
   m_cost_target_min=0.0;
   m_cost_early_exit_min=0.0;
   m_segment=SRP_SEGMENT_UNDECLARED;
   //--- FIX 5. Undeclared until the engine says otherwise, which is what
   //--- makes an un-wired build report "not declared" instead of "live".
   m_geom_declared=false;
   m_geom_sample=0.0;
   m_geom_pinned=false;
   m_geom_derived_count=0;
   m_srv_declared=false;
   m_srv_exits=0;
   m_srv_exact_fills=false;
  }
//+------------------------------------------------------------------+
//| ObserveTick                                                       |
//|                                                                  |
//| The spread is taken from the TICK, not from SYMBOL_SPREAD. In a   |
//| generated pass SYMBOL_SPREAD can be a derived figure, whereas     |
//| ask-bid is what the strategy actually paid, so measuring the tick |
//| is the only way to catch a tape whose spread never moves inside a |
//| bar. Bucketing on tick.time avoids iTime entirely: no history     |
//| call, no dependence on the chart timeframe, no repaint risk.      |
//+------------------------------------------------------------------+
void CRunProvenance::ObserveTick(const MqlTick &tick,const double point)
  {
   m_ticks++;
   if(m_first_tick==0)
      m_first_tick=tick.time;
   m_last_tick=tick.time;

   //--- spread of this tick, in whole points
   int spread_pts=0;
   if(point>0.0 && tick.ask>0.0 && tick.bid>0.0)
      spread_pts=(int)MathRound((tick.ask-tick.bid)/point);
   if(spread_pts<0)
      spread_pts=0;
   if(m_ticks==1)
     {
      m_spread_min=spread_pts;
      m_spread_max=spread_pts;
     }
   else
     {
      if(spread_pts<m_spread_min) m_spread_min=spread_pts;
      if(spread_pts>m_spread_max) m_spread_max=spread_pts;
     }
   m_spread_sum+=(double)spread_pts;

   //--- minute bucket
   const datetime minute=(datetime)(tick.time-(tick.time%60));
   if(m_bar_minute!=minute)
     {
      CloseBar();
      m_bar_minute=minute;
     }
   m_bar_ticks++;

   //--- distinct spreads inside this minute, capped so the cost of the
   //--- scan cannot grow with tick density
   bool seen=false;
   for(int i=0;i<m_bar_spread_count;i++)
      if(m_bar_spreads[i]==spread_pts)
        { seen=true; break; }
   if(!seen && m_bar_spread_count<SRP_PROV_SPREAD_TRACK)
      m_bar_spreads[m_bar_spread_count++]=spread_pts;
  }
//+------------------------------------------------------------------+
//| CloseBar. Files the finished minute into both histograms. The bar |
//| in progress at the end of the run is deliberately NOT filed - a   |
//| partial minute would drag the median down and the run's last      |
//| minute carries no information worth that distortion.              |
//+------------------------------------------------------------------+
void CRunProvenance::CloseBar(void)
  {
   if(m_bar_minute>0 && m_bar_ticks>0)
     {
      int t=m_bar_ticks;
      if(t>SRP_PROV_TICK_BUCKETS-1) t=SRP_PROV_TICK_BUCKETS-1;
      m_tick_hist[t]++;
      int s=m_bar_spread_count;
      if(s>SRP_PROV_SPREAD_BUCKETS-1) s=SRP_PROV_SPREAD_BUCKETS-1;
      m_spread_hist[s]++;
      m_bars++;
     }
   m_bar_ticks=0;
   m_bar_spread_count=0;
  }

//+------------------------------------------------------------------+
//| MedianOf. Lower median by cumulative count. Returns -1 when there |
//| is nothing to take a median of, so callers can distinguish "no    |
//| observation" from "an observed zero".                             |
//+------------------------------------------------------------------+
int CRunProvenance::MedianOf(const int &hist[],const int buckets) const
  {
   long total=0;
   for(int i=0;i<buckets;i++)
      total+=(long)hist[i];
   if(total<=0)
      return(-1);
   const long half=(total+1)/2;
   long seen=0;
   for(int i=0;i<buckets;i++)
     {
      seen+=(long)hist[i];
      if(seen>=half)
         return(i);
     }
   return(buckets-1);
  }

int CRunProvenance::MedianTicksPerBar(void) const
  {
   return(MedianOf(m_tick_hist,SRP_PROV_TICK_BUCKETS));
  }

int CRunProvenance::MedianSpreadsPerBar(void) const
  {
   return(MedianOf(m_spread_hist,SRP_PROV_SPREAD_BUCKETS));
  }
double CRunProvenance::AverageSpreadPoints(void) const
  {
   if(m_ticks<=0)
      return(0.0);
   return(m_spread_sum/(double)m_ticks);
  }

void CRunProvenance::SetCostModel(const double init_spread,
                                  const double commission,
                                  const double execution,
                                  const double reward_ratio,
                                  const double target_min,
                                  const double early_exit_min)
  {
   m_cost_init_spread=init_spread;
   m_cost_commission=commission;
   m_cost_execution=execution;
   m_cost_reward_ratio=reward_ratio;
   m_cost_target_min=target_min;
   m_cost_early_exit_min=early_exit_min;
   m_cost_declared=true;
  }

void CRunProvenance::SetSegment(const ENUM_SRP_DATA_SEGMENT segment)
  {
   m_segment=segment;
  }

//+------------------------------------------------------------------+
//| SetGeometry. HARNESS v2, FIX 5.                                   |
//|                                                                  |
//| Called by the engine once the market profile has been built, so   |
//| the count reflects what the profile actually left for the code to |
//| derive rather than what the code is capable of deriving.          |
//+------------------------------------------------------------------+
void CRunProvenance::SetGeometry(const double sample_points,
                                 const bool pinned,
                                 const int derived_count)
  {
   m_geom_sample=sample_points;
   m_geom_pinned=pinned;
   m_geom_derived_count=derived_count;
   m_geom_declared=true;
  }

//+------------------------------------------------------------------+
//| SetServerFillEvidence. Called immediately before anything is       |
//| printed or exported, so the warning list and the QUOTABLE flag     |
//| both see the final counts rather than the counts as they stood     |
//| when the run started.                                             |
//+------------------------------------------------------------------+
void CRunProvenance::SetServerFillEvidence(const long exits,
                                           const bool all_exact)
  {
   m_srv_exits=exits;
   m_srv_exact_fills=all_exact;
   m_srv_declared=true;
  }

//+------------------------------------------------------------------+
//| TickModel. The inference, in the order that the two measurements  |
//| actually separate the modes.                                      |
//|                                                                  |
//| KNOWN BLIND SPOT, stated here and in the printed output: a real   |
//| tick feed whose spread happens to be fixed reads as GENERATED.    |
//| That direction of error is the safe one - it accuses a good tape  |
//| of being synthetic, never the reverse.                            |
//+------------------------------------------------------------------+
ENUM_SRP_TICK_MODEL CRunProvenance::TickModel(void) const
  {
   if(!(bool)MQLInfoInteger(MQL_TESTER))
      return(SRP_TICK_MODEL_LIVE);
   if(m_bars<30)
      return(SRP_TICK_MODEL_UNKNOWN);
   const int mt=MedianTicksPerBar();
   if(mt<=1)
      return(SRP_TICK_MODEL_OPEN_PRICES);
   if(mt<=8)
      return(SRP_TICK_MODEL_OHLC_M1);
   if(MedianSpreadsPerBar()<=1)
      return(SRP_TICK_MODEL_GENERATED);
   return(SRP_TICK_MODEL_REAL_TICKS);
  }
bool CRunProvenance::IsGeneratedTape(void) const
  {
   const ENUM_SRP_TICK_MODEL m=TickModel();
   return(m==SRP_TICK_MODEL_OPEN_PRICES ||
          m==SRP_TICK_MODEL_OHLC_M1     ||
          m==SRP_TICK_MODEL_GENERATED);
  }

//+------------------------------------------------------------------+
//| SegmentContradicted. MQL_FORWARD is the one piece of segment       |
//| evidence the terminal will actually give up, so it is used to      |
//| catch a declaration that disagrees with the pass itself.           |
//|                                                                   |
//| Only two directions are contradictions. A forward pass labelled    |
//| DEV is one. Declaring OOS inside an optimisation is the other -    |
//| an optimiser searches, and data that has been searched over is by  |
//| definition no longer out of sample. The reverse case, OOS declared |
//| in a plain non-forward pass, is perfectly legitimate: that is what |
//| a separate hold-out run looks like.                                |
//+------------------------------------------------------------------+
bool CRunProvenance::SegmentContradicted(void) const
  {
   const bool forward=(bool)MQLInfoInteger(MQL_FORWARD);
   const bool optimising=(bool)MQLInfoInteger(MQL_OPTIMIZATION);
   if(forward && m_segment==SRP_SEGMENT_DEV)
      return(true);
   if(optimising && m_segment==SRP_SEGMENT_OOS && !forward)
      return(true);
   return(false);
  }

string CRunProvenance::TickModelText(void) const
  {
   switch(TickModel())
     {
      case SRP_TICK_MODEL_LIVE:        return("LIVE (not a tester pass)");
      case SRP_TICK_MODEL_OPEN_PRICES: return("OPEN PRICES ONLY (generated)");
      case SRP_TICK_MODEL_OHLC_M1:     return("1 MINUTE OHLC (generated)");
      case SRP_TICK_MODEL_GENERATED:   return("EVERY TICK (generated)");
      case SRP_TICK_MODEL_REAL_TICKS:  return("EVERY TICK BASED ON REAL TICKS");
     }
   return("UNKNOWN (fewer than 30 minutes observed)");
  }

string CRunProvenance::SegmentText(void) const
  {
   switch(m_segment)
     {
      case SRP_SEGMENT_DEV: return("DEV / IN-SAMPLE");
      case SRP_SEGMENT_OOS: return("OUT-OF-SAMPLE");
     }
   return("UNDECLARED - this result may not be quoted as validation");
  }
//+------------------------------------------------------------------+
//| CostModelText. What the run CHARGED ITSELF, in one line.           |
//|                                                                  |
//| The undeclared case is printed rather than skipped. A report that  |
//| omits the cost model is indistinguishable from one that charged    |
//| nothing, and the second is what actually happened for fifteen      |
//| months of this project's history.                                 |
//+------------------------------------------------------------------+
string CRunProvenance::CostModelText(void) const
  {
   if(!m_cost_declared)
      return("UNDECLARED - no cost model was handed to the reporter, so "
             "nothing here states what a trade was charged");
   string text=StringFormat("commission %.2f pts/round-turn, "
                            "execution %.2f pts, "
                            "startup spread sample %.2f pts",
                            m_cost_commission,m_cost_execution,
                            m_cost_init_spread);
   text+=StringFormat("; target floor %.2f pts, early-exit floor %.2f pts, "
                      "min reward/cost %.2f",
                      m_cost_target_min,m_cost_early_exit_min,
                      m_cost_reward_ratio);
   return(text);
  }
//+------------------------------------------------------------------+
//| GeometryText. HARNESS v2, FIX 5.                                  |
//|                                                                  |
//| The one number the whole trade geometry descends from, and whether |
//| a second run would get the same one. Printed even when it was      |
//| never declared, for the same reason as the cost model above: a     |
//| missing line reads as "not applicable" when it means "nobody       |
//| asked".                                                           |
//+------------------------------------------------------------------+
string CRunProvenance::GeometryText(void) const
  {
   if(!m_geom_declared)
      return("UNDECLARED - the reporter was told nothing about the spread "
             "sample the trade geometry was derived from");
   string text=StringFormat("spread sample %.2f pts, %s",
                            m_geom_sample,
                            (m_geom_pinned
                             ? "PINNED by input - a rerun derives the same "
                               "distances"
                             : "read from the tick current at init - a rerun "
                               "derives different distances"));
   //--- The count is what makes the line actionable. All twelve derived is
   //--- the shipping GOLD profile; zero derived means the profile preset
   //--- every distance and the sample cost the run nothing.
   text+=StringFormat("; %d of 12 distances derived from it",
                      m_geom_derived_count);
   return(text);
  }
//+------------------------------------------------------------------+
//| Warnings. Every reason this run may not be quoted, in one place.   |
//|                                                                  |
//| Written as an APPEND-ONLY list rather than a first-match verdict:  |
//| a generated tape AND a zero commission AND an undeclared segment   |
//| is three separate defects, and reporting only the first would let  |
//| fixing it look like fixing the run.                               |
//+------------------------------------------------------------------+
string CRunProvenance::Warnings(void) const
  {
   string out="";
   const bool tester=(bool)MQLInfoInteger(MQL_TESTER);

   //--- 1. The tape.
   if(IsGeneratedTape())
      out+="\n  ! GENERATED TAPE ("+TickModelText()+"). This tick model "
           "cannot represent a 20-second scalp: it fills every stop at the "
           "stop price and takes the spread from the bar record. Any "
           "profitability here is a property of the simulator.";
   else
      if(tester && TickModel()==SRP_TICK_MODEL_UNKNOWN)
         out+="\n  ! TAPE NOT CLASSIFIED - fewer than 30 minutes of ticks "
              "were observed, so the tick model could not be inferred.";

   //--- 2. The spread, against the figures this feed is known to produce.
   //--- Audit evidence: 1-minute-OHLC generation models XAUUSD at 4.0-4.4
   //--- points where the real tape runs 9.5-33.5. An average below 5 is
   //--- therefore a generated-spread signature in its own right, and it is
   //--- reported separately from the tick-model verdict so the two
   //--- measurements corroborate each other instead of one standing alone.
   if(tester && m_ticks>0 && AverageSpreadPoints()<5.0)
      out+=StringFormat("\n  ! MODELLED SPREAD %.2f pts, below the 9.5-33.5 "
                        "pts this feed actually produces on real ticks. The "
                        "cost side of every trade in this run is fiction.",
                        AverageSpreadPoints());

   //--- 3. The cost model.
   if(!m_cost_declared)
      out+="\n  ! COST MODEL UNDECLARED.";
   else
      if(m_cost_commission<=0.0)
         out+="\n  ! COMMISSION 0.00 - the run models a broker that charges "
              "nothing to trade. On a few-points-wide edge that is not a "
              "neutral default, it widens the set of targets that look "
              "viable.";

   //--- 4. The startup spread sample against the run's own average. This is
   //--- the section-5.5 defect made visible rather than fixed: while every
   //--- stop, target and buffer descends from ONE tick, a sample that is
   //--- unrepresentative of the run silently mis-sizes all twelve derived
   //--- distances. Fix 4 raised this warning; fix 5 added the pin that can
   //--- silence it, and section 4b below is the one that says whether the
   //--- operator used it.
   if(m_cost_declared && m_cost_init_spread>0.0 && m_ticks>0)
     {
      const double avg=AverageSpreadPoints();
      if(avg>0.0 && (m_cost_init_spread>avg*2.0 || m_cost_init_spread*2.0<avg))
         out+=StringFormat("\n  ! STARTUP SPREAD SAMPLE %.2f pts vs run "
                           "average %.2f pts. Every derived distance in this "
                           "run was set from the sample, so the geometry "
                           "does not match the tape it traded.",
                           m_cost_init_spread,avg);
     }

   //=== 4b. HARNESS v2, FIX 5. IS THIS RUN REPEATABLE AT ALL? ==========
   //--- IN THE TESTER ONLY, and that restriction is the point rather than a
   //--- convenience. A live run's geometry SHOULD fit the broker it is
   //--- running on, there is no rerun to be faithful to, and a warning that
   //--- can never be cleared would make QUOTABLE meaningless on exactly the
   //--- results that deserve it most. In the tester the opposite holds: an
   //--- unpinned sample means a rerun over identical dates with identical
   //--- inputs and identical tick data trades measurably different distances,
   //--- so the number this run produced cannot be checked by anyone,
   //--- including its author.
   //---
   //--- The derived count is stated rather than used as a gate. Zero means
   //--- the profile preset all twelve distances, but the scalp controller
   //--- samples the spread independently for its execution cost, target floor
   //--- and early-exit floor - the three gates that turn a signal into an
   //--- entry - so even then a rerun is not guaranteed to agree.
   if(tester && m_geom_declared && !m_geom_pinned)
      out+=StringFormat("\n  ! GEOMETRY NOT PINNED - the trade distances were "
                        "derived from a %.2f pt spread sample read from "
                        "whichever tick was current at init (%d of the 12 "
                        "profile distances, plus the scalp cost floors). A "
                        "rerun of this exact configuration will not reproduce "
                        "this result. Set InpPinSpreadSample to make the run "
                        "repeatable.",
                        m_geom_sample,m_geom_derived_count);

   //--- 5. The segment.
   if(m_segment==SRP_SEGMENT_UNDECLARED)
      out+="\n  ! DATA SEGMENT UNDECLARED - this result may not be quoted as "
           "validation of anything.";
   if(SegmentContradicted())
      out+="\n  ! DATA SEGMENT CONTRADICTED by the pass itself (forward="+
           ((bool)MQLInfoInteger(MQL_FORWARD) ? "y" : "n")+
           " optimisation="+((bool)MQLInfoInteger(MQL_OPTIMIZATION) ? "y" : "n")+
           ") while declaring "+SegmentText()+".";

   //--- 6. Execution. A run whose every broker-fired exit filled at exactly
   //--- its trigger price did not find a flawless broker; the simulator put
   //--- the fill on the barrier. It is listed here, and not only inside the
   //--- execution line itself, so that it counts against IsQuotable() -
   //--- a warning the verdict cannot see is a warning nobody acts on.
   if(m_srv_declared && m_srv_exits>0 && m_srv_exact_fills)
      out+="\n  ! SYNTHETIC FILLS - all "+IntegerToString(m_srv_exits)+
           " server-side exits filled at exactly their trigger price. Stop "
           "and target distances measured on this run carry no slippage "
           "information at all.";

   //--- 7. An optimisation pass is a search. Its best result is a maximum
   //--- over the search, not a measurement, and it is quoted as one often
   //--- enough to be worth saying on every single pass.
   if((bool)MQLInfoInteger(MQL_OPTIMIZATION))
      out+="\n  ! OPTIMISATION PASS - the best figure over a search is not "
           "an out-of-sample expectation.";

   if(out=="")
      return("  none outstanding");
   return(out);
  }
//+------------------------------------------------------------------+
bool CRunProvenance::IsQuotable(void) const
  {
   return(Warnings()=="  none outstanding");
  }
//+------------------------------------------------------------------+
//| Header. The block that opens every report.                        |
//|                                                                  |
//| Ordered so the two things that invalidate a result outright - the |
//| tick model and the segment - are read before any number that they |
//| would invalidate. The measurements the verdict rests on are       |
//| printed beside it, because an inference nobody can check is just  |
//| another assertion.                                                |
//+------------------------------------------------------------------+
string CRunProvenance::Header(const string extra_line) const
  {
   const int mt=MedianTicksPerBar();
   const int ms=MedianSpreadsPerBar();
   string text=
      "=== RUN PROVENANCE ================================================";
   text+="\n  build      : "+SRP_PRODUCT_NAME+" "+SRP_PRODUCT_VERSION+
         " / "+SRP_HARNESS_VERSION;
   text+="\n  instrument : "+m_symbol+" "+EnumToString(m_timeframe);
   //--- THE FOUR RUN FACTS THE TERMINAL WILL ACTUALLY CONFIRM, printed
   //--- immediately above the one that had to be inferred. They are here for
   //--- contrast as much as for content: everything below TICK MODEL is a
   //--- measurement of the tape, while these are assertions by the platform,
   //--- and a reader deciding how much to trust the block needs to see which
   //--- is which. They also make a mislabelled file self-evident - a header
   //--- claiming OUT-OF-SAMPLE with optimisation=yes is a search, not a test.
   text+="\n  terminal   : tester="+
         ((bool)MQLInfoInteger(MQL_TESTER) ? "yes" : "no")+
         " optimisation="+
         ((bool)MQLInfoInteger(MQL_OPTIMIZATION) ? "yes" : "no")+
         " visual="+
         ((bool)MQLInfoInteger(MQL_VISUAL_MODE) ? "yes" : "no")+
         " forward="+
         ((bool)MQLInfoInteger(MQL_FORWARD) ? "yes" : "no");
   text+="\n  tape       : "+IntegerToString(m_ticks)+" ticks over "+
         IntegerToString(m_bars)+" minutes";
   if(m_first_tick>0)
      text+=", "+TimeToString(m_first_tick,TIME_DATE|TIME_MINUTES)+" -> "+
            TimeToString(m_last_tick,TIME_DATE|TIME_MINUTES);
   text+="\n  TICK MODEL : "+TickModelText();
   //--- STATED ON EVERY REPORT, not in the documentation. MQL5 exposes no API
   //--- for the tester's tick-generation mode, so this verdict is arrived at
   //--- from the density of the tape and nothing else. A reader who believes
   //--- the platform reported it would treat REAL TICKS as certainty; the two
   //--- medians on the next line are printed so the inference can be checked
   //--- instead of taken on trust.
   text+="\n               INFERRED, the terminal does not report this";
   text+=StringFormat("\n               [median %s ticks/minute, "
                      "%s distinct spreads/minute]",
                      (mt<0 ? "n/a" : IntegerToString(mt)),
                      (ms<0 ? "n/a" : IntegerToString(ms)));
   text+=StringFormat("\n  spread     : avg %.2f pts, min %d, max %d",
                      AverageSpreadPoints(),m_spread_min,m_spread_max);
   if(extra_line!="")
      text+="\n  EXECUTION  : "+extra_line;
   text+="\n  COST MODEL : "+CostModelText();
   //--- HARNESS v2, FIX 5. Directly under the cost model because the two
   //--- share a root: the startup spread sample the cost line quotes is the
   //--- same quantity this line says whether anyone can reproduce.
   text+="\n  GEOMETRY   : "+GeometryText();
   text+="\n  SEGMENT    : "+SegmentText();
   text+="\n  QUOTABLE   : "+(IsQuotable() ? "yes" : "NO");
   text+="\n  warnings   :"+Warnings();
   text+=
      "\n===================================================================";
   return(text);
  }
//+------------------------------------------------------------------+
//| HeaderCsv. The same facts on one line, for the top of a data file. |
//|                                                                  |
//| COMMA-FREE BY CONSTRUCTION. It is written as a '#'-prefixed first  |
//| line of a CSV, and a comma in it would give that line a different  |
//| field count from the rest of the file - which is exactly the kind  |
//| of breakage that gets a provenance line deleted rather than read.  |
//+------------------------------------------------------------------+
string CRunProvenance::HeaderCsv(void) const
  {
   string text=StringFormat(
                  "# provenance: build=%s %s; harness=%s; symbol=%s; "
                  "timeframe=%s; tester=%s; optimisation=%s; visual=%s; "
                  "forward=%s; "
                  "ticks=%I64d; minutes=%I64d; tick_model_inferred=%s; "
                  "median_ticks_per_min=%d; median_spreads_per_min=%d; "
                  "spread_avg_pts=%.2f; spread_min_pts=%d; spread_max_pts=%d; "
                  "commission_pts=%.2f; execution_pts=%.2f; "
                  "startup_spread_pts=%.2f; cost_declared=%s; segment=%s; "
                  //--- HARNESS v2, FIX 5. Three fields, not one. A consumer
                  //--- comparing two rows needs the sample to see whether they
                  //--- ran the same geometry, `pinned` to know whether that
                  //--- agreement was guaranteed or luck, and the count to know
                  //--- how much of the geometry the sample governed.
                  "geom_spread_pts=%.2f; geom_pinned=%s; geom_derived=%d; "
                  "server_exits=%I64d; server_fills_all_exact=%s; "
                  "quotable=%s",
                  SRP_PRODUCT_NAME,SRP_PRODUCT_VERSION,SRP_HARNESS_VERSION,
                  m_symbol,EnumToString(m_timeframe),
                  //--- The same four platform facts as the printed block. A
                  //--- consumer reading only this line must still be able to
                  //--- tell a search from a test.
                  ((bool)MQLInfoInteger(MQL_TESTER) ? "yes" : "no"),
                  ((bool)MQLInfoInteger(MQL_OPTIMIZATION) ? "yes" : "no"),
                  ((bool)MQLInfoInteger(MQL_VISUAL_MODE) ? "yes" : "no"),
                  ((bool)MQLInfoInteger(MQL_FORWARD) ? "yes" : "no"),
                  m_ticks,m_bars,EnumToString(TickModel()),
                  MedianTicksPerBar(),MedianSpreadsPerBar(),
                  AverageSpreadPoints(),m_spread_min,m_spread_max,
                  m_cost_commission,m_cost_execution,m_cost_init_spread,
                  (m_cost_declared ? "yes" : "no"),
                  EnumToString(m_segment),
                  m_geom_sample,
                  (!m_geom_declared ? "undeclared"
                                    : (m_geom_pinned ? "yes" : "no")),
                  m_geom_derived_count,
                  m_srv_exits,
                  (!m_srv_declared ? "undeclared"
                                   : (m_srv_exact_fills ? "yes" : "no")),
                  (IsQuotable() ? "yes" : "no"));
   //--- Belt and braces: the product name and symbol come from outside this
   //--- class, so the comma-free guarantee is enforced rather than assumed.
   StringReplace(text,",",";");
   return(text);
  }
//+------------------------------------------------------------------+
//| CsvColumns / CsvValues. Seven fields, and only seven.              |
//|                                                                  |
//| This pair is appended to a row of PASS RESULTS, so it carries only |
//| what decides whether that row may be believed: what kind of tape   |
//| produced it, what the tape cost, what the run charged itself,      |
//| whether the row can be reproduced at all, and which half of the    |
//| data it claims to speak for. Everything else in the printed block  |
//| is diagnosis and belongs there, not in a column that would be      |
//| repeated on every one of a thousand rows.                          |
//|                                                                  |
//| The seventh - geom_pinned - was added by fix 5 and earns its place  |
//| on the same test as the other six: an optimisation export is where  |
//| one row out of a thousand gets quoted, and an unpinned row cannot   |
//| be re-run to check it. That is a property of the row, not of the    |
//| search, so it has to travel with the row.                          |
//+------------------------------------------------------------------+
string CRunProvenance::CsvColumns(void) const
  {
   //--- `tick_model_inferred` rather than `tick_model`: the column name is the
   //--- only place a caveat can live in a machine-readable file, and a reader
   //--- sorting a thousand rows by fitness will never see the comment above.
   return("tick_model_inferred,spread_avg_pts,commission_pts,execution_pts,"
          "geom_pinned,data_segment,quotable");
  }

string CRunProvenance::CsvValues(void) const
  {
   //--- EnumToString cannot produce a comma, and the numbers are formatted
   //--- here rather than by the caller, so the field count is fixed by
   //--- construction and matches CsvColumns for every possible run state.
   string row=EnumToString(TickModel());
   row+=","+DoubleToString(AverageSpreadPoints(),2);
   row+=","+DoubleToString(m_cost_commission,2);
   row+=","+DoubleToString(m_cost_execution,2);
   //--- Three states, not two. "undeclared" is not the same claim as "no" and
   //--- collapsing them would let an un-wired build look like a deliberate
   //--- decision to run unpinned.
   row+=","+(!m_geom_declared ? "undeclared" : (m_geom_pinned ? "yes" : "no"));
   row+=","+EnumToString(m_segment);
   row+=","+(IsQuotable() ? "yes" : "no");
   return(row);
  }

#endif // SRP_RUNTIME_CRUNPROVENANCE_MQH
//+------------------------------------------------------------------+
