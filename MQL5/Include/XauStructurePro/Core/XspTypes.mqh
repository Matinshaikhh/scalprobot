//+------------------------------------------------------------------+
//|                                                   XspTypes.mqh |
//|              XauStructurePro - Core/Types : enums and structures |
//|                                                                  |
//|   Deliberately NOT reusing SRP's Enums.mqh for anything that names a  |
//|   concept this study measures. A shared enum is a shared definition,   |
//|   and the point of the rebuild is that SRP's definitions are what      |
//|   failed. ENUM_SRP_DATA_SEGMENT is the one exception and is included    |
//|   where it is needed, because the DEV/VAL split is the audit's, not     |
//|   SRP's, and both products must mean the same thing by "DEV".          |
//+------------------------------------------------------------------+
#ifndef XSP_CORE_XSPTYPES_MQH
#define XSP_CORE_XSPTYPES_MQH

#include "XspConstants.mqh"

//--- Which candidate produced an instance. At most two, per audit 8.2:
//--- "no more than two setups". A third would multiply the comparisons
//--- being run against one dataset without multiplying the evidence.
enum ENUM_XSP_SETUP
  {
   XSP_SETUP_NONE=0,
   XSP_SETUP_CONTINUATION,          // S1: M15 displacement, H1-aligned
   XSP_SETUP_REVERSAL               // S2: sweep of a liquidity pool
  };

enum ENUM_XSP_DIR
  {
   XSP_DIR_NONE=0,
   XSP_DIR_BUY,
   XSP_DIR_SELL
  };

//--- Barrier outcome for ONE reward tier under ONE holding cap.
//--- TIME_EXIT is not a synonym for UNRESOLVED: a time exit has a known
//--- mark-to-market and belongs in the expectancy sum, while UNRESOLVED
//--- means the tracker was still watching when the run ended and the
//--- outcome is genuinely unknown. Merging them would silently assign a
//--- value of zero to instances whose value was never observed.
enum ENUM_XSP_OUTCOME
  {
   XSP_OUTCOME_OPEN=0,
   XSP_OUTCOME_TARGET,
   XSP_OUTCOME_STOP,
   XSP_OUTCOME_TIME_EXIT,
   XSP_OUTCOME_UNRESOLVED
  };

//--- H1 structural class. Pure swing labelling, no indicator: an EMA or
//--- ADX threshold here would be one more number chosen off this data.
enum ENUM_XSP_TREND
  {
   XSP_TREND_CHOP=0,
   XSP_TREND_UP,
   XSP_TREND_DOWN
  };

//--- Trading session by server hour. Recorded as a label because the
//--- audit's section 7 found session filtering untested, not because any
//--- session is expected to work.
enum ENUM_XSP_SESSION
  {
   XSP_SESSION_ASIA=0,
   XSP_SESSION_LONDON,
   XSP_SESSION_OVERLAP,             // London afternoon + New York morning
   XSP_SESSION_NEWYORK,
   XSP_SESSION_OFF                  // thin hours either side of the roll
  };

//--- What kind of level a liquidity pool sits on. Kept distinct because
//--- "the prior day's high" and "three equal highs inside one session"
//--- are different claims about where resting orders are, and lumping
//--- them would make the label unable to falsify either one.
enum ENUM_XSP_POOL
  {
   XSP_POOL_NONE=0,
   XSP_POOL_PRIOR_DAY_HIGH,
   XSP_POOL_PRIOR_DAY_LOW,
   XSP_POOL_EQUAL_HIGHS,
   XSP_POOL_EQUAL_LOWS,
   XSP_POOL_SESSION_HIGH,
   XSP_POOL_SESSION_LOW
  };

//+------------------------------------------------------------------+
//| A price level that liquidity is presumed to rest on.               |
//|                                                                    |
//| price + origin_time together are the level's IDENTITY. Not the bar  |
//| index: CSwingDetector rebuilds its arrays on every refresh and a    |
//| shift recorded at detection time points somewhere else two bars     |
//| later. Defect 2 in the old tree is exactly this class of error, and |
//| an identity that drifts is an identity that lets one occurrence be  |
//| counted twice.                                                     |
//+------------------------------------------------------------------+
struct SXspLevel
  {
   bool              valid;
   ENUM_XSP_POOL     kind;
   double            price;
   datetime          origin_time;    // bar time the level was formed on
   int               touches;        // 1 = single extreme, >1 = a cluster

   //--- There is deliberately NO "consumed" flag here. Whether a level has
   //--- already produced an event is CXspStructureEvents' single answer, by
   //--- fingerprint. A second flag on the level would be a second source of
   //--- truth for the same question, and the two would disagree the first
   //--- time the pool list was rebuilt - which is exactly how SRP's
   //--- MarkHighSwept came to have no lasting effect.
   void Reset()
     {
      valid=false;
      kind=XSP_POOL_NONE;
      price=0.0;
      origin_time=0;
      touches=0;
     }
  };

//+------------------------------------------------------------------+
//| L2 regime labels, RECORDED and never enforced.                     |
//|                                                                    |
//| Deciles rather than raw values as the primary cut because a raw ATR |
//| threshold in points is a number that would have to be chosen, and   |
//| choosing it on this data is the section-9 violation the whole study  |
//| is built to avoid. A decile is defined by the sample itself.        |
//+------------------------------------------------------------------+
struct SXspRegime
  {
   bool              valid;
   double            atr_points;     // realised volatility proxy at trigger
   int               vol_decile;     // 0..9 within XSP_VOL_RANK_BARS
   double            spread_points;  // raw spread at trigger
   int               spread_decile;  // 0..9 within XSP_SPREAD_RANK_SAMPLES
   ENUM_XSP_TREND    trend;          // H1 swing-label class
   ENUM_XSP_SESSION  session;
   int               minute_of_day;  // server time, 0..1439

   void Reset()
     {
      valid=false;
      atr_points=0.0;
      vol_decile=-1;
      spread_points=0.0;
      spread_decile=-1;
      trend=XSP_TREND_CHOP;
      session=XSP_SESSION_OFF;
      minute_of_day=-1;
     }
  };

//+------------------------------------------------------------------+
//| L1 higher-timeframe context labels, RECORDED and never enforced.    |
//|                                                                    |
//| aligned is stored as a plain flag rather than used as a gate. The     |
//| audit's section 9.3 wants each component's contribution measured on  |
//| one population; gating here would produce a population from which    |
//| the counterfactual - what the setup does when H1 disagrees - is      |
//| permanently missing, and no later analysis could recover it.        |
//+------------------------------------------------------------------+
struct SXspContext
  {
   bool              valid;
   ENUM_XSP_TREND    h1_trend;
   ENUM_XSP_TREND    h4_trend;
   bool              h1_aligned;     // H1 class agrees with the direction
   bool              h4_aligned;
   double            h1_range_pos;   // 0..1 inside the last H1 swing range

   void Reset()
     {
      valid=false;
      h1_trend=XSP_TREND_CHOP;
      h4_trend=XSP_TREND_CHOP;
      h1_aligned=false;
      h4_aligned=false;
      h1_range_pos=-1.0;
     }
  };

//+------------------------------------------------------------------+
//| L5 confirmation. BROKER TICK VOLUME - a count of quote updates.     |
//|                                                                    |
//| This is NOT order flow, NOT real traded volume and NOT depth of      |
//| market. XAUUSD spot is not centrally cleared, so no venue-wide       |
//| volume exists to read, and no MarketBook* call appears anywhere in   |
//| this codebase. It is a participation proxy and the CSV column names  |
//| it as one so that no downstream reader can mistake it for flow.     |
//+------------------------------------------------------------------+
struct SXspConfirm
  {
   bool              valid;
   long              tick_volume;    // trigger bar, broker tick count
   double            slot_median;    // same minute-of-day, prior sessions
   int               slot_samples;   // how many sessions the median used
   double            ratio;          // tick_volume / slot_median
   bool              passed;         // ratio >= XSP_CONFIRM_MIN_RATIO

   void Reset()
     {
      valid=false;
      tick_volume=0;
      slot_median=0.0;
      slot_samples=0;
      ratio=0.0;
      passed=false;
     }
  };

//+------------------------------------------------------------------+
//| One candidate setup, emitted ONCE per market occurrence.            |
//|                                                                    |
//| fingerprint is the defect-2 fix. In the old tree a break was re-      |
//| stamped on every evaluation for as long as price stayed beyond the    |
//| level, so one occurrence became N rows; n rose, the standard error    |
//| fell, and significance was manufactured out of nothing. Here the      |
//| fingerprint is a hash of (setup, direction, level price, level bar    |
//| time) and CXspStructureEvents refuses a second emission for it.      |
//|                                                                    |
//| "Price is still beyond the level" is a STATE and is exposed as one;  |
//| it never produces a candidate.                                      |
//+------------------------------------------------------------------+
struct SXspCandidate
  {
   bool              valid;
   ENUM_XSP_SETUP    setup;
   ENUM_XSP_DIR      dir;
   string            fingerprint;
   datetime          event_bar_time;   // the CLOSED bar that produced it
   double            invalidation;     // the price that voids the premise
   double            level_price;      // pool swept (S2) or leg origin (S1)
   ENUM_XSP_POOL     pool_kind;        // S2 only; NONE for S1
   double            atr_points;       // ATR at the event bar, for the buffer

   void Reset()
     {
      valid=false;
      setup=XSP_SETUP_NONE;
      dir=XSP_DIR_NONE;
      fingerprint="";
      event_bar_time=0;
      invalidation=0.0;
      level_price=0.0;
      pool_kind=XSP_POOL_NONE;
      atr_points=0.0;
     }
  };

//+------------------------------------------------------------------+
//| One tracked instance. THE MEASUREMENT.                              |
//|                                                                    |
//| REFERENCE SERIES: the BID, for both directions. This is the single    |
//| most consequential convention in the study, so it is stated here.    |
//|                                                                    |
//| A long is entered at ask and exited at bid; a short is entered at    |
//| bid and exited at ask. Relative to the BID PATH both therefore give   |
//| up exactly one spread over the round trip - the asymmetry is         |
//| symmetric. So barriers are measured spread-free on the bid path and   |
//| the whole cost is charged analytically afterwards from the recorded   |
//| spread. Folding spread into the barriers instead (as audit 3.4 does   |
//| algebraically) would give the same verdict but would freeze one cost  |
//| model into the tape, and the section-9.3 pessimistic model - spread   |
//| stressed to 1.5x plus 7pt commission - would then need a whole new    |
//| run rather than a column of arithmetic.                             |
//|                                                                    |
//| The stop is SHARED by all four reward tiers, so sec_to_stop is one    |
//| number and each tier's outcome is DERIVED by comparing times. A per-  |
//| tier outcome field would let the four tiers contradict each other;    |
//| this cannot.                                                        |
//+------------------------------------------------------------------+
struct SXspInstance
  {
   bool              active;
   long              id;
   string            fingerprint;
   ENUM_XSP_SETUP    setup;
   ENUM_XSP_DIR      dir;

   //--- trigger conditions, all recorded
   datetime          event_bar_time;
   datetime          trigger_time;
   double            ref_entry;        // BID at trigger - the reference
   double            fill_price;       // ask for buy, bid for sell (reported)
   double            spread_points;    // raw spread at trigger
   double            invalidation;
   double            stop_points;      // |ref_entry - invalidation| + buffer

   //--- forward tracking, no lookahead: every field below is written by
   //--- a tick that had already arrived when it was written.
   double            mfe_points;       // best favourable excursion
   double            mae_points;       // worst adverse excursion (<= 0)
   int               sec_to_mfe;
   int               sec_to_stop;                  // XSP_NEVER if not hit
   int               sec_to_target[XSP_R_TIERS];   // XSP_NEVER if not hit
   double            move_at_cap[XSP_CAP_TIERS];   // R at 5/15/30/60 min
   bool              cap_stamped[XSP_CAP_TIERS];
   //--- The most recently OBSERVED excursion, in R. Needed because ticks
   //--- are not evenly spaced: after a weekend gap the next tick can land
   //--- at age 5,000s, and the mark-to-market at the 5-minute cap is then
   //--- the last price seen BEFORE the gap, not the price after it.
   //--- Without this the four cap columns would all be stamped with one
   //--- post-gap price and would silently claim to be four measurements.
   double            last_r;
   int               tracked_seconds;
   int               ticks_seen;
   bool              closed;           // stop hit or every tier resolved
  };

//+------------------------------------------------------------------+
//| Tier and cap tables as functions rather than global arrays.          |
//| A global array in an include is initialised at load time in an order  |
//| MQL5 does not guarantee across translation units; a function cannot   |
//| be read before it is defined.                                       |
//+------------------------------------------------------------------+
double XspRTier(const int index)
  {
   switch(index)
     {
      case 0: return(XSP_R_1);
      case 1: return(XSP_R_2);
      case 2: return(XSP_R_3);
      case 3: return(XSP_R_4);
     }
   return(0.0);
  }

int XspCapSeconds(const int index)
  {
   switch(index)
     {
      case 0: return(XSP_CAP_1);
      case 1: return(XSP_CAP_2);
      case 2: return(XSP_CAP_3);
      case 3: return(XSP_CAP_4);
     }
   return(0);
  }

//--- Server-hour session bucket. Server time, NOT broker-local or UTC:
//--- every bar timestamp in this study is server time, so a session label
//--- derived from anything else would not line up with the bars it labels.
ENUM_XSP_SESSION XspSessionOf(const int server_hour)
  {
   if(server_hour>=0  && server_hour<7)  return(XSP_SESSION_ASIA);
   if(server_hour>=7  && server_hour<12) return(XSP_SESSION_LONDON);
   if(server_hour>=12 && server_hour<16) return(XSP_SESSION_OVERLAP);
   if(server_hour>=16 && server_hour<21) return(XSP_SESSION_NEWYORK);
   return(XSP_SESSION_OFF);
  }

//--- Label strings for the CSV. Comma-free by construction: a comma in
//--- any of these would shift every later column by one and the file
//--- would still parse, which is the worst kind of failure.
string XspSetupName(const ENUM_XSP_SETUP v)
  {
   switch(v)
     {
      case XSP_SETUP_CONTINUATION: return("S1_continuation");
      case XSP_SETUP_REVERSAL:     return("S2_reversal");
     }
   return("none");
  }

string XspDirName(const ENUM_XSP_DIR v)
  {
   if(v==XSP_DIR_BUY)  return("buy");
   if(v==XSP_DIR_SELL) return("sell");
   return("none");
  }

string XspTrendName(const ENUM_XSP_TREND v)
  {
   if(v==XSP_TREND_UP)   return("up");
   if(v==XSP_TREND_DOWN) return("down");
   return("chop");
  }

string XspSessionName(const ENUM_XSP_SESSION v)
  {
   switch(v)
     {
      case XSP_SESSION_ASIA:    return("asia");
      case XSP_SESSION_LONDON:  return("london");
      case XSP_SESSION_OVERLAP: return("overlap");
      case XSP_SESSION_NEWYORK: return("newyork");
     }
   return("off");
  }

string XspPoolName(const ENUM_XSP_POOL v)
  {
   switch(v)
     {
      case XSP_POOL_PRIOR_DAY_HIGH: return("prior_day_high");
      case XSP_POOL_PRIOR_DAY_LOW:  return("prior_day_low");
      case XSP_POOL_EQUAL_HIGHS:    return("equal_highs");
      case XSP_POOL_EQUAL_LOWS:     return("equal_lows");
      case XSP_POOL_SESSION_HIGH:   return("session_high");
      case XSP_POOL_SESSION_LOW:    return("session_low");
     }
   return("none");
  }

#endif // XSP_CORE_XSPTYPES_MQH
//+------------------------------------------------------------------+
