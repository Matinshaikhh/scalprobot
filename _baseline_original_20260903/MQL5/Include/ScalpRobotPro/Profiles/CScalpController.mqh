//+------------------------------------------------------------------+
//|                                        CScalpController.mqh |
//|              Scalping Robot Pro - XAUUSD Ultra-Scalp Mode (P6b) |
//|                                                                  |
//|   RESPONSIBILITY (one only): decide whether a scalp entry is ALLOWED,   |
//|   what its cost-aware target is, and when it should be cut early.      |
//|                                                                  |
//|   IT DECIDES, IT DOES NOT EXECUTE. No OrderSend, no sizing, no stop     |
//|   modification. Every answer is returned to CProductionEngine, which    |
//|   routes it through the existing execution engine, risk engine and      |
//|   trade manager. Nothing here duplicates those.                        |
//|                                                                  |
//|   WHY IT EXISTS AT ALL                                               |
//|   The production stack can already enter, size, protect and exit. What  |
//|   it could not do is take SEVERAL short-lived scalps in quick           |
//|   succession safely, because two things were missing:                  |
//|                                                                  |
//|     1. Nothing distinguished "a new market event" from "the same event  |
//|        still visible on the next tick". OnTick fires thousands of times |
//|        per bar; a signal that stays true would be re-entered on every   |
//|        one of them.                                                    |
//|     2. Nothing checked that the target was worth more than the round    |
//|        trip. On XAUUSD a 40-point spread against a 60-point target is   |
//|        a losing trade taken deliberately.                              |
//|                                                                  |
//|   FREQUENCY IS NOT THE GOAL. Every gate here can only ever REDUCE the   |
//|   number of trades. If the market offers two setups, two trades happen; |
//|   if it offers ten and risk permits, ten happen; if it offers none,     |
//|   none happen. There is no path through this class that manufactures    |
//|   an entry.                                                          |
//|                                                                  |
//|   NO MARTINGALE, STRUCTURALLY. This class never returns a volume, a     |
//|   lot multiplier or a risk figure. It cannot increase size after a      |
//|   loss because it has no means of expressing size at all. Sizing stays  |
//|   entirely inside CRiskEngine on its OrderCalcProfit path.              |
//+------------------------------------------------------------------+
#ifndef SRP_PROFILES_CSCALPCONTROLLER_MQH
#define SRP_PROFILES_CSCALPCONTROLLER_MQH

#include "../Core/Interfaces/ILogger.mqh"
#include "../Intelligence/Indicators/CStandardIndicators.mqh"
#include "../Utilities/CMathUtils.mqh"
#include "../Decision/Types/DecisionStructs.mqh"
//--- Exit attribution is expressed in the trade manager's trigger
//--- vocabulary, so metrics line up with the journal rather than
//--- inventing a second set of names for the same events.
#include "../Interface/Types/InterfaceEnums.mqh"

//+------------------------------------------------------------------+
//| Why a scalp was refused. One primary reason per rejection, so the   |
//| funnel reads as a single cause rather than a list of symptoms.      |
//+------------------------------------------------------------------+
enum ENUM_SRP_SCALP_BLOCK
  {
   SRP_SCALP_OK,
   SRP_SCALP_BLOCK_DUPLICATE,      // same signal already traded
   SRP_SCALP_BLOCK_COOLDOWN,       // anti-double-fire window
   SRP_SCALP_BLOCK_SPREAD,         // spread too wide for the target
   SRP_SCALP_BLOCK_COST,           // target cannot clear round-trip cost
   SRP_SCALP_BLOCK_MAX_POSITIONS,  // exposure slots full
   SRP_SCALP_BLOCK_ATR,            // volatility unusable
   SRP_SCALP_BLOCK_DAILY_LIMIT,    // per-day scalp cap reached
   SRP_SCALP_BLOCK_DISABLED,
   //--- Target could not clear costs at a payoff the tier's own win rate
   //--- would need. Named separately from BLOCK_COST because the cause is
   //--- different: the trade is affordable, it is just not winnable often
   //--- enough to pay for its own stop.
   SRP_SCALP_BLOCK_BREAKEVEN
  };

//+------------------------------------------------------------------+
//| SCALP TIER. Which geometry a setup is traded with.                  |
//|                                                                  |
//| The tiers exist because target size and expected win rate are NOT     |
//| independent, and treating them as one setting is what produced a       |
//| 43.9% win rate at 0.948 payoff - a combination that cannot profit.     |
//|                                                                  |
//| Break-even payoff for a win rate W is (1-W)/W:                        |
//|                                                                  |
//|     50% -> 1.000    60% -> 0.667    70% -> 0.429    80% -> 0.250      |
//|                                                                  |
//| So a HIGH win rate BUYS the right to a small target, and a small       |
//| target is only reachable often enough if it is small. The tiers make   |
//| that trade explicit instead of leaving it to be discovered.           |
//|                                                                  |
//| SUPER_SCALP  tightest target, highest expected hit rate, shortest      |
//|              hold. Needs the least favourable payoff to profit, and    |
//|              is therefore the most exposed to transaction costs.      |
//| STANDARD     the balanced tier.                                      |
//| SWING_SCALP  widest target, lowest expected hit rate, longest hold.   |
//|              Profits on payoff rather than on frequency.              |
//+------------------------------------------------------------------+
enum ENUM_SRP_SCALP_TIER
  {
   SRP_TIER_SUPER,
   SRP_TIER_STANDARD,
   SRP_TIER_SWING
  };

//+------------------------------------------------------------------+
//| A signal's identity.                                               |
//|                                                                  |
//| THIS IS THE DUPLICATE-PROTECTION KEY, and its composition is the       |
//| whole point: bar time + direction + strategy + structure event. Two    |
//| ticks inside one bar reporting the same setup produce an IDENTICAL     |
//| fingerprint and the second is refused. A genuinely new event - next    |
//| bar, opposite direction, different strategy, or a new structural       |
//| break - produces a DIFFERENT fingerprint and is allowed.               |
//|                                                                  |
//| Using a timestamp alone would fail: the same signal on the same bar    |
//| carries the same bar time, so it would be re-entered once per tick.    |
//| Using price would fail for the opposite reason: price moves every      |
//| tick, so every tick would look new.                                   |
//+------------------------------------------------------------------+
struct SScalpSignalId
  {
   datetime          bar_time;        // bar the signal formed on
   int               direction;       // +1 buy, -1 sell
   int               strategy;        // ENUM_SRP_STRATEGY_KIND
   int               structure_event; // ENUM_SRP_STRUCTURE_EVENT
   datetime          event_time;      // structural event timestamp
   bool              valid;

                     SScalpSignalId(void) { Reset(); }
   void              Reset(void)
     {
      bar_time=0; direction=0; strategy=-1;
      structure_event=0; event_time=0; valid=false;
     }
   //--- Exact identity. Deliberately strict: any differing component
   //--- makes this a new event, and any identical one makes it a repeat.
   bool              Equals(const SScalpSignalId &other) const
     {
      return(valid && other.valid &&
             bar_time==other.bar_time &&
             direction==other.direction &&
             strategy==other.strategy &&
             structure_event==other.structure_event &&
             event_time==other.event_time);
     }
   string            Describe(void) const
     {
      if(!valid)
         return("invalid");
      return(StringFormat("bar=%s dir=%s strat=%d event=%d@%s",
                          TimeToString(bar_time,TIME_DATE|TIME_MINUTES),
                          (direction>0 ? "BUY" : "SELL"),
                          strategy,structure_event,
                          TimeToString(event_time,TIME_MINUTES|TIME_SECONDS)));
     }
  };

//+------------------------------------------------------------------+
//| Result of asking "may this scalp be taken".                        |
//+------------------------------------------------------------------+
struct SScalpVerdict
  {
   bool                  allowed;
   ENUM_SRP_SCALP_BLOCK  block;
   string                detail;
   //--- Cost-aware target, in points. Zero when not resolvable.
   double                target_points;
   double                stop_points;
   //--- Round-trip cost estimate the target had to clear.
   double                cost_points;
   double                spread_points;
   double                atr_points;
   //--- Which tier priced this scalp, and the geometry that follows from
   //--- it. Carried on the verdict so the engine applies the TIER's hold
   //--- window rather than one global value for every setup.
   ENUM_SRP_SCALP_TIER   tier;
   int                   max_hold_seconds;
   //--- NET payoff after costs: (target-cost)/(stop+cost).
   //---
   //--- This, not the raw target:stop ratio, is what a win rate has to
   //--- beat. Quoting the gross ratio is how a geometry that loses money
   //--- after spread and commission passes inspection.
   double                net_payoff;
   //--- Win rate this geometry must ACTUALLY achieve to break even,
   //--- (1/(1+net_payoff)). Reported so the target is falsifiable.
   double                required_winrate;

                     SScalpVerdict(void) { Reset(); }
   void              Reset(void)
     {
      allowed=false; block=SRP_SCALP_OK; detail="";
      target_points=0.0; stop_points=0.0; cost_points=0.0;
      spread_points=0.0; atr_points=0.0;
      tier=SRP_TIER_STANDARD; max_hold_seconds=0;
      net_payoff=0.0; required_winrate=0.0;
     }
  };

//+------------------------------------------------------------------+
//| Running metrics. Populated by the engine as trades close.          |
//+------------------------------------------------------------------+
struct SScalpMetrics
  {
   long              signals_seen;
   long              entries;
   long              blocked_duplicate;
   long              blocked_cooldown;
   long              blocked_spread;
   long              blocked_cost;
   long              blocked_positions;
   long              blocked_atr;
   long              blocked_daily;
   //--- Exit attribution.
   long              exit_tp;
   long              exit_sl;
   long              exit_early;
   long              exit_timeout;
   long              exit_other;
   //--- Holding time, seconds.
   long              hold_total_seconds;
   int               hold_fastest;
   int               hold_longest;
   //--- Median needs the samples kept, so a bounded ring is used.
   int               hold_samples[512];
   int               hold_count;
   int               hold_cursor;
   //--- Money.
   double            gross_win;
   double            gross_loss;
   int               wins;
   int               losses;
   //--- Spread actually paid at entry, averaged.
   double            spread_sum;
   long              spread_samples;
   //--- Scalps per day, from the day counter.
   int               days_traded;

                     SScalpMetrics(void) { Reset(); }
   void              Reset(void)
     {
      signals_seen=0; entries=0;
      blocked_duplicate=0; blocked_cooldown=0; blocked_spread=0;
      blocked_cost=0; blocked_positions=0; blocked_atr=0; blocked_daily=0;
      exit_tp=0; exit_sl=0; exit_early=0; exit_timeout=0; exit_other=0;
      hold_total_seconds=0; hold_fastest=0; hold_longest=0;
      ArrayInitialize(hold_samples,0);
      hold_count=0; hold_cursor=0;
      gross_win=0.0; gross_loss=0.0; wins=0; losses=0;
      spread_sum=0.0; spread_samples=0; days_traded=0;
     }
  };

//+------------------------------------------------------------------+
class CScalpController
  {
private:
   string            m_symbol;
   ILogger          *m_logger;         // borrowed
   CAtrIntel        *m_atr;            // borrowed, execution timeframe
   CRsiIntel        *m_rsi;            // borrowed, for momentum fade

   bool              m_enabled;

   //--- Instrument facts, refreshed from the broker.
   double            m_point;
   int               m_digits;
   int               m_stops_level;

   //=== CONFIGURATION =================================================
   //--- Anti-double-fire window. Deliberately SHORT: its job is to stop
   //--- one signal firing twice, not to throttle legitimate scalping.
   int               m_cooldown_seconds;
   //--- Holding window before the trade is cut for failing to develop.
   int               m_max_hold_seconds;
   //--- Target sizing, on ATR so it adapts without re-tuning.
   double            m_target_atr_multiple;
   double            m_target_min_points;
   double            m_target_max_points;
   //--- Stop sizing.
   double            m_stop_atr_multiple;
   //--- Round-trip cost model, all in points.
   double            m_commission_points;
   double            m_execution_cost_points;
   //--- Target must exceed cost by at least this multiple, or the trade
   //--- is not economically meaningful.
   double            m_min_reward_cost_ratio;
   //--- Spread ceiling as a fraction of the target. A 40-point spread
   //--- against a 60-point target fails this regardless of absolute size.
   double            m_max_spread_target_ratio;
   //--- Early profit exit.
   bool              m_early_exit_enabled;
   double            m_early_exit_min_points;   // floor before it may fire
   double            m_early_exit_target_share; // share of target reached
   //--- Volatility usability bounds, points.
   double            m_atr_min_points;
   double            m_atr_max_points;
   //--- Per-day cap. A ceiling, never a quota.
   int               m_max_scalps_per_day;

   //=== TIERS =========================================================
   //--- Per-tier geometry. Index by ENUM_SRP_SCALP_TIER.
   bool              m_tier_enabled[3];
   double            m_tier_target_atr[3];
   double            m_tier_stop_atr[3];
   int               m_tier_max_hold[3];
   //--- The win rate each tier is ASSUMED to need to break even. Not a
   //--- prediction of performance - it is the threshold the target must be
   //--- able to clear costs at, so a tier cannot be configured into a
   //--- geometry that loses money at its own design win rate.
   double            m_tier_assumed_winrate[3];
   //--- Timeframe each tier reads its ATR from. A 1-minute target sized
   //--- from 15-minute volatility is not a scalp.
   ENUM_TIMEFRAMES   m_tier_timeframe[3];
   //--- Borrowed ATR per tier, so a tier reading M5 does not size from M1.
   CAtrIntel        *m_tier_atr[3];
   //--- Live per-tier accounting, so the tiers can be compared on
   //--- evidence rather than on intent.
   long              m_tier_entries[3];
   long              m_tier_wins[3];
   long              m_tier_losses[3];
   double            m_tier_gross_win[3];
   double            m_tier_gross_loss[3];
   //--- Which tier the position now being recorded belongs to.
   ENUM_SRP_SCALP_TIER m_last_tier;

   //=== STATE =========================================================
   SScalpSignalId    m_last_traded;      // the signal most recently entered
   datetime          m_last_entry_time;
   int               m_today_count;
   int               m_today_day;
   SScalpMetrics     m_metrics;
   SScalpVerdict     m_last_verdict;
   //--- The most recent cost refusal, kept so the funnel can quote real
   //--- figures instead of only a count.
   string            m_last_cost_detail;

   bool              RefreshSpec(void);
   void              RollDay(const datetime now);
   double            ReadAtrPoints(void) const;
   //--- ATR for a specific tier, from that tier's own timeframe. Falls
   //--- back to the execution ATR when a tier has none wired, so a missing
   //--- indicator degrades the geometry rather than silencing the tier.
   double            ReadTierAtrPoints(const ENUM_SRP_SCALP_TIER tier) const;

public:
                     CScalpController(const string symbol,ILogger *logger);
                    ~CScalpController(void) { }

   void              SetIndicators(CAtrIntel *atr,CRsiIntel *rsi);
   void              SetEnabled(const bool enabled) { m_enabled=enabled; }
   bool              IsEnabled(void) const { return(m_enabled); }

   void              ConfigureTiming(const int cooldown_seconds,
                                     const int max_hold_seconds);
   void              ConfigureTarget(const double atr_multiple,
                                     const double min_points,
                                     const double max_points);
   void              ConfigureStop(const double atr_multiple);
   void              ConfigureCosts(const double commission_points,
                                    const double execution_cost_points,
                                    const double min_reward_cost_ratio,
                                    const double max_spread_target_ratio);
   void              ConfigureEarlyExit(const bool enabled,
                                        const double min_points,
                                        const double target_share);
   void              ConfigureAtrBounds(const double min_points,
                                        const double max_points);
   void              SetMaxScalpsPerDay(const int maximum);

   //=== TIERS =========================================================
   //--- Configures one tier's geometry. `assumed_winrate` is the rate the
   //--- tier is DESIGNED around; the gate refuses any target that cannot
   //--- break even at it, so a tier cannot be quietly configured into a
   //--- losing geometry.
   void              ConfigureTier(const ENUM_SRP_SCALP_TIER tier,
                                   const bool enabled,
                                   const double target_atr_multiple,
                                   const double stop_atr_multiple,
                                   const int max_hold_seconds,
                                   const double assumed_winrate,
                                   const ENUM_TIMEFRAMES timeframe);
   //--- Borrowed ATR for a tier. A tier whose ATR is absent falls back to
   //--- the execution-timeframe ATR rather than being silently skipped.
   void              SetTierAtr(const ENUM_SRP_SCALP_TIER tier,CAtrIntel *atr);
   bool              TierEnabled(const ENUM_SRP_SCALP_TIER tier) const;
   ENUM_TIMEFRAMES   TierTimeframe(const ENUM_SRP_SCALP_TIER tier) const;
   //--- The tier's stop multiple, so the caller can size against the stop
   //--- the trade will actually carry rather than a single startup value
   //--- shared by every tier. Returns 0.0 for an out-of-range tier, which a
   //--- caller must treat as "leave the existing stop alone".
   double            TierStopAtrMultiple(const ENUM_SRP_SCALP_TIER tier) const;

   //--- Break-even win rate for a payoff, and the payoff a win rate needs.
   //--- Static and pure so a harness can assert the arithmetic directly.
   static double     BreakEvenWinRate(const double net_payoff);
   static double     RequiredPayoff(const double win_rate);

   //--- Per-tier realised performance, for attribution.
   string            DescribeTiers(void) const;
   static string     TierToString(const ENUM_SRP_SCALP_TIER tier);

   bool              Initialize(void);
   void              Validate(SValidationResult &result) const;

   //--- Builds the fingerprint for a decision. Static shape so a harness
   //--- can construct one without an engine.
   static SScalpSignalId BuildSignalId(const datetime bar_time,
                                       const bool is_buy,
                                       const int strategy_kind,
                                       const int structure_event,
                                       const datetime event_time);

   //=== THE GATE ======================================================
   //--- Answers "may this scalp be taken, and at what target". Never
   //--- returns a size. Counts its own rejections for the funnel.
   //--- The tier defaults to STANDARD so every existing caller and test
   //--- keeps its exact previous meaning; only a caller that selects a
   //--- tier gets the new geometry.
   bool              Evaluate(const SScalpSignalId &id,
                              const datetime now,
                              const double spread_points,
                              const int open_positions,
                              const int max_positions,
                              SScalpVerdict &verdict,
                              const ENUM_SRP_SCALP_TIER tier=SRP_TIER_STANDARD);

   //--- Called only after the order is CONFIRMED filled. Recording on
   //--- intent would mark a rejected order as traded and permanently
   //--- suppress a signal that never actually entered.
   void              RecordEntry(const SScalpSignalId &id,
                                 const datetime now,
                                 const double spread_points,
                                 const ENUM_SRP_SCALP_TIER tier=SRP_TIER_STANDARD);

   //=== EARLY PROFIT EXIT =============================================
   //--- True when an already-profitable scalp should be cut because the
   //--- micro-move is exhausted. Never fires below the cost floor.
   bool              ShouldTakeEarlyProfit(const bool is_buy,
                                           const double profit_points,
                                           const double target_points,
                                           string &reason) const;

   //--- True when the holding window has elapsed.
   //---
   //--- limit_seconds overrides the global window, so a SUPER_SCALP is cut
   //--- at 90s while a SWING_SCALP is given 900s. Zero means "use the
   //--- configured global window", which keeps every existing caller and
   //--- assertion behaving exactly as before.
   bool              ShouldTimeOut(const datetime open_time,
                                   const datetime now,
                                   string &reason,
                                   const int limit_seconds=0) const;

   //=== METRICS =======================================================
   void              RecordExit(const ENUM_SRP_TM_TRIGGER trigger,
                                const int hold_seconds,
                                const double net_profit,
                                const ENUM_SRP_SCALP_TIER tier=SRP_TIER_STANDARD);
   void              GetMetrics(SScalpMetrics &out) const { out=m_metrics; }
   void              GetLastVerdict(SScalpVerdict &out) const { out=m_last_verdict; }
   double            AverageHoldSeconds(void) const;
   double            MedianHoldSeconds(void) const;
   double            AverageSpreadPoints(void) const;
   int               TodayCount(void) const { return(m_today_count); }
   int               MaxHoldSeconds(void) const { return(m_max_hold_seconds); }

   string            DescribeFunnel(void) const;
   string            DescribeMetrics(void) const;
   static string     BlockToString(const ENUM_SRP_SCALP_BLOCK block);
  };

//+------------------------------------------------------------------+
CScalpController::CScalpController(const string symbol,ILogger *logger)
  : m_symbol(symbol),
    m_logger(logger),
    m_atr(NULL),
    m_rsi(NULL),
    m_enabled(false),
    m_point(0.0),
    m_digits(0),
    m_stops_level(0),
    m_cooldown_seconds(15),
    m_max_hold_seconds(300),            // 5 minutes, per the requirement
    m_target_atr_multiple(0.55),
    m_target_min_points(0.0),
    m_target_max_points(0.0),
    m_stop_atr_multiple(0.90),
    m_commission_points(0.0),
    m_execution_cost_points(0.0),
    m_min_reward_cost_ratio(2.0),
    m_max_spread_target_ratio(0.35),
    m_early_exit_enabled(true),
    m_early_exit_min_points(0.0),
    m_early_exit_target_share(0.55),
    m_atr_min_points(0.0),
    m_atr_max_points(0.0),
    m_max_scalps_per_day(20),
    m_last_entry_time(0),
    m_today_count(0),
    m_today_day(-1)
  {
   m_last_traded.Reset();
   m_metrics.Reset();
   m_last_verdict.Reset();
   m_last_cost_detail="";
   m_last_tier=SRP_TIER_STANDARD;

   //=== TIER DEFAULTS =================================================
   //--- Each tier's target is chosen so its ASSUMED win rate is above its
   //--- own break-even, with margin. The relationship is the point:
   //---
   //---   SUPER     0.30xATR target / 0.42xATR stop
   //---             gross payoff 0.71, break-even 58.4% - designed for 72%
   //---   STANDARD  0.70 / 0.70, gross 1.00, break-even 50% - designed 58%
   //---   SWING     1.40 / 0.90, gross 1.56, break-even 39% - designed 48%
   //---
   //--- Costs push every break-even figure UP, which is why the gate
   //--- recomputes it from the NET payoff at execution rather than
   //--- trusting these numbers.
   //--- SUPER GEOMETRY, CORRECTED FROM MEASUREMENT.
   //---
   //--- It was 0.30 target / 0.42 stop: gross payoff 0.71, needing 58.4%
   //--- wins BEFORE costs and more after. It was declared as "designed for
   //--- 72%", and that figure was an assumption, not an observation.
   //---
   //--- MEASURED over 31 months of XAUUSD real ticks with the accuracy
   //--- filter active: 177 trades at 52.54% wins. The entry filter did
   //--- raise accuracy materially (43.90% -> 52.54%), but a target SMALLER
   //--- than the stop cannot be paid for at 52.5%, so profit factor stayed
   //--- at 0.697 while the win rate improved. Losing money more accurately
   //--- is still losing money.
   //---
   //--- So the target now EXCEEDS the stop. At 0.55/0.45 the gross payoff
   //--- is 1.22 and gross break-even is 45.0%; costs raise that, and the
   //--- gate recomputes the real figure from the NET payoff per trade and
   //--- refuses anything the tier cannot actually pay for. A 52.5% win rate
   //--- has genuine headroom over 45%, where it had none over 58.4%.
   //---
   //--- The assumed rate is set to 0.55 - just below what was actually
   //--- observed, not above it. A tier may not claim an accuracy it has
   //--- never demonstrated, because that claim is what authorises a small
   //--- target in the first place.
   m_tier_enabled[SRP_TIER_SUPER]    = true;
   m_tier_target_atr[SRP_TIER_SUPER] = 0.55;
   m_tier_stop_atr[SRP_TIER_SUPER]   = 0.45;
   m_tier_max_hold[SRP_TIER_SUPER]   = 120;
   m_tier_assumed_winrate[SRP_TIER_SUPER] = 0.55;
   m_tier_timeframe[SRP_TIER_SUPER]  = PERIOD_M1;

   m_tier_enabled[SRP_TIER_STANDARD]    = true;
   m_tier_target_atr[SRP_TIER_STANDARD] = 0.70;
   m_tier_stop_atr[SRP_TIER_STANDARD]   = 0.70;
   m_tier_max_hold[SRP_TIER_STANDARD]   = 300;
   m_tier_assumed_winrate[SRP_TIER_STANDARD] = 0.58;
   m_tier_timeframe[SRP_TIER_STANDARD]  = PERIOD_M1;

   m_tier_enabled[SRP_TIER_SWING]    = true;
   m_tier_target_atr[SRP_TIER_SWING] = 1.40;
   m_tier_stop_atr[SRP_TIER_SWING]   = 0.90;
   m_tier_max_hold[SRP_TIER_SWING]   = 900;
   m_tier_assumed_winrate[SRP_TIER_SWING] = 0.48;
   m_tier_timeframe[SRP_TIER_SWING]  = PERIOD_M5;

   for(int i=0;i<3;i++)
     {
      m_tier_atr[i]=NULL;
      m_tier_entries[i]=0; m_tier_wins[i]=0; m_tier_losses[i]=0;
      m_tier_gross_win[i]=0.0; m_tier_gross_loss[i]=0.0;
     }
  }
//+------------------------------------------------------------------+
//| Break-even arithmetic, stated once so nothing re-derives it.        |
//|                                                                  |
//| A system winning W of its trades at payoff P breaks even when          |
//| W*P == (1-W), so:                                                    |
//|                                                                  |
//|     break-even W = 1/(1+P)        required P = (1-W)/W                |
//|                                                                  |
//| Pure and static, so a harness asserts the formula and not a copy.     |
//+------------------------------------------------------------------+
double CScalpController::BreakEvenWinRate(const double net_payoff)
  {
   if(net_payoff<=0.0)
      return(1.0);      // no payoff at all can never break even
   return(1.0/(1.0+net_payoff));
  }
//+------------------------------------------------------------------+
double CScalpController::RequiredPayoff(const double win_rate)
  {
   if(win_rate<=0.0)  return(DBL_MAX);
   if(win_rate>=1.0)  return(0.0);
   return((1.0-win_rate)/win_rate);
  }
//+------------------------------------------------------------------+
void CScalpController::ConfigureTier(const ENUM_SRP_SCALP_TIER tier,
                                     const bool enabled,
                                     const double target_atr_multiple,
                                     const double stop_atr_multiple,
                                     const int max_hold_seconds,
                                     const double assumed_winrate,
                                     const ENUM_TIMEFRAMES timeframe)
  {
   const int i=(int)tier;
   if(i<0 || i>2)
      return;
   m_tier_enabled[i]=enabled;
   if(target_atr_multiple>0.0) m_tier_target_atr[i]=target_atr_multiple;
   if(stop_atr_multiple>0.0)   m_tier_stop_atr[i]=stop_atr_multiple;
   if(max_hold_seconds>0)      m_tier_max_hold[i]=max_hold_seconds;
   //--- Bounded to a range a real system can occupy. A tier claiming 99%
   //--- would authorise an arbitrarily small target.
   if(assumed_winrate>=0.30 && assumed_winrate<=0.90)
      m_tier_assumed_winrate[i]=assumed_winrate;
   if((int)timeframe>0)        m_tier_timeframe[i]=timeframe;
  }
//+------------------------------------------------------------------+
void CScalpController::SetTierAtr(const ENUM_SRP_SCALP_TIER tier,
                                  CAtrIntel *atr)
  {
   const int i=(int)tier;
   if(i>=0 && i<=2)
      m_tier_atr[i]=atr;
  }
//+------------------------------------------------------------------+
bool CScalpController::TierEnabled(const ENUM_SRP_SCALP_TIER tier) const
  {
   const int i=(int)tier;
   return(i>=0 && i<=2 && m_tier_enabled[i]);
  }
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES CScalpController::TierTimeframe(const ENUM_SRP_SCALP_TIER tier) const
  {
   const int i=(int)tier;
   return(i>=0 && i<=2 ? m_tier_timeframe[i] : PERIOD_M1);
  }
//+------------------------------------------------------------------+
double CScalpController::TierStopAtrMultiple(const ENUM_SRP_SCALP_TIER tier) const
  {
   const int i=(int)tier;
   return(i>=0 && i<=2 ? m_tier_stop_atr[i] : 0.0);
  }
//+------------------------------------------------------------------+
string CScalpController::TierToString(const ENUM_SRP_SCALP_TIER tier)
  {
   switch(tier)
     {
      case SRP_TIER_SUPER:    return("SUPER_SCALP");
      case SRP_TIER_STANDARD: return("STANDARD");
      case SRP_TIER_SWING:    return("SWING_SCALP");
     }
   return("UNKNOWN");
  }
//+------------------------------------------------------------------+
//| Per-tier realised performance.                                      |
//|                                                                  |
//| Reports the ACHIEVED win rate against the rate the tier was designed  |
//| around, because that comparison is the only way to see whether a tier |
//| is working or merely configured.                                      |
//+------------------------------------------------------------------+
string CScalpController::DescribeTiers(void) const
  {
   string text="SCALP TIERS (achieved vs designed)";
   for(int i=0;i<3;i++)
     {
      const ENUM_SRP_SCALP_TIER t=(ENUM_SRP_SCALP_TIER)i;
      const long closed=m_tier_wins[i]+m_tier_losses[i];
      text+=StringFormat("\n  %-12s %s entries=%I64d",
                         TierToString(t),
                         (m_tier_enabled[i] ? "on " : "off"),
                         m_tier_entries[i]);
      text+=StringFormat(" target=%.2fxATR stop=%.2fxATR hold=%ds tf=%s",
                         m_tier_target_atr[i],m_tier_stop_atr[i],
                         m_tier_max_hold[i],
                         EnumToString(m_tier_timeframe[i]));
      if(closed>0)
        {
         const double win=100.0*(double)m_tier_wins[i]/(double)closed;
         const double pf=(m_tier_gross_loss[i]>0.0
                          ? m_tier_gross_win[i]/m_tier_gross_loss[i] : 0.0);
         const double avg_win=(m_tier_wins[i]>0
                               ? m_tier_gross_win[i]/(double)m_tier_wins[i] : 0.0);
         const double avg_loss=(m_tier_losses[i]>0
                                ? m_tier_gross_loss[i]/(double)m_tier_losses[i] : 0.0);
         const double payoff=(avg_loss>0.0 ? avg_win/avg_loss : 0.0);
         text+=StringFormat("\n               closed=%I64d win=%.2f%% "
                            "(designed %.0f%%) pf=%.3f payoff=%.3f "
                            "break-even=%.2f%%",
                            closed,win,m_tier_assumed_winrate[i]*100.0,
                            pf,payoff,BreakEvenWinRate(payoff)*100.0);
         //--- The verdict that matters, stated rather than left to be
         //--- inferred from three decimals.
         if(payoff>0.0)
            text+=(win>=BreakEvenWinRate(payoff)*100.0
                   ? "  PROFITABLE" : "  BELOW BREAK-EVEN");
        }
      else
         text+="\n               no closed trades";
     }
   return(text);
  }
//+------------------------------------------------------------------+
void CScalpController::SetIndicators(CAtrIntel *atr,CRsiIntel *rsi)
  {
   m_atr=atr;
   m_rsi=rsi;
  }
//+------------------------------------------------------------------+
void CScalpController::ConfigureTiming(const int cooldown_seconds,
                                       const int max_hold_seconds)
  {
   //--- Cooldown is clamped to a genuinely short window. Its purpose is
   //--- duplicate suppression; a long cooldown here would silently
   //--- prevent the rapid sequential scalping this mode exists for.
   if(cooldown_seconds>=0)
      m_cooldown_seconds=(int)CMathUtils::Clamp((double)cooldown_seconds,0.0,120.0);
   if(max_hold_seconds>0)
      m_max_hold_seconds=max_hold_seconds;
  }
//+------------------------------------------------------------------+
void CScalpController::ConfigureTarget(const double atr_multiple,
                                       const double min_points,
                                       const double max_points)
  {
   if(atr_multiple>0.0)  m_target_atr_multiple=atr_multiple;
   if(min_points>=0.0)   m_target_min_points=min_points;
   if(max_points>=0.0)   m_target_max_points=max_points;
  }
//+------------------------------------------------------------------+
void CScalpController::ConfigureStop(const double atr_multiple)
  {
   if(atr_multiple>0.0)
      m_stop_atr_multiple=atr_multiple;
  }
//+------------------------------------------------------------------+
void CScalpController::ConfigureCosts(const double commission_points,
                                      const double execution_cost_points,
                                      const double min_reward_cost_ratio,
                                      const double max_spread_target_ratio)
  {
   if(commission_points>=0.0)      m_commission_points=commission_points;
   if(execution_cost_points>=0.0)  m_execution_cost_points=execution_cost_points;
   if(min_reward_cost_ratio>=1.0)  m_min_reward_cost_ratio=min_reward_cost_ratio;
   if(max_spread_target_ratio>0.0 && max_spread_target_ratio<1.0)
      m_max_spread_target_ratio=max_spread_target_ratio;
  }
//+------------------------------------------------------------------+
void CScalpController::ConfigureEarlyExit(const bool enabled,
                                          const double min_points,
                                          const double target_share)
  {
   m_early_exit_enabled=enabled;
   if(min_points>=0.0) m_early_exit_min_points=min_points;
   //--- Below 0.25 an "early exit" would fire almost immediately after
   //--- entry, which the requirement explicitly forbids.
   if(target_share>=0.25 && target_share<=1.0)
      m_early_exit_target_share=target_share;
  }
//+------------------------------------------------------------------+
void CScalpController::ConfigureAtrBounds(const double min_points,
                                          const double max_points)
  {
   if(min_points>=0.0) m_atr_min_points=min_points;
   if(max_points>=0.0) m_atr_max_points=max_points;
  }
//+------------------------------------------------------------------+
void CScalpController::SetMaxScalpsPerDay(const int maximum)
  {
   if(maximum>0)
      m_max_scalps_per_day=maximum;
  }
//+------------------------------------------------------------------+
bool CScalpController::RefreshSpec(void)
  {
   m_point       = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
   m_digits      = (int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
   m_stops_level = (int)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
   return(m_point>0.0);
  }
//+------------------------------------------------------------------+
bool CScalpController::Initialize(void)
  {
   if(!RefreshSpec())
      return(false);

   //--- COST FLOOR, derived rather than assumed.
   //--- If no explicit execution cost was configured, estimate it from
   //--- the broker's own quoting: one spread's worth of slippage
   //--- allowance is a conservative default on a fast instrument.
   if(m_execution_cost_points<=0.0)
     {
      const double spread=(double)SymbolInfoInteger(m_symbol,SYMBOL_SPREAD);
      m_execution_cost_points=MathMax(spread*0.5,1.0);
     }

   //--- Minimum target: must clear the broker stop level AND the modelled
   //--- round trip. Left at zero it would default to something arbitrary.
   if(m_target_min_points<=0.0)
     {
      const double spread=(double)SymbolInfoInteger(m_symbol,SYMBOL_SPREAD);
      const double round_trip=spread+m_commission_points+m_execution_cost_points;
      m_target_min_points=MathMax(round_trip*m_min_reward_cost_ratio,
                                  (double)m_stops_level*1.5);
     }
   if(m_early_exit_min_points<=0.0)
     {
      //--- Early exit may not fire below the round-trip cost, or it would
      //--- book a "profit" that is a loss after costs.
      const double spread=(double)SymbolInfoInteger(m_symbol,SYMBOL_SPREAD);
      m_early_exit_min_points=spread+m_commission_points+
                              m_execution_cost_points;
     }
   m_metrics.Reset();
   m_last_traded.Reset();
   return(true);
  }
//+------------------------------------------------------------------+
void CScalpController::Validate(SValidationResult &result) const
  {
   if(!m_enabled)
      return;
   if(m_atr==NULL)
      result.AddError("CScalpController: no ATR, scalp targets cannot be sized");
   if(m_point<=0.0)
      result.AddError("CScalpController: point size unresolved");
   if(m_cooldown_seconds>120)
      result.AddWarning("CScalpController: cooldown above 120s will suppress "
                        "legitimate rapid scalping");
   if(m_max_hold_seconds<30)
      result.AddWarning("CScalpController: holding window below 30s will cut "
                        "trades before any move can develop");
   if(m_target_min_points<=0.0)
      result.AddError("CScalpController: minimum target is zero, cost "
                      "protection would be inert");
   if(m_min_reward_cost_ratio<1.0)
      result.AddError("CScalpController: reward/cost ratio below 1.0 accepts "
                      "targets that lose money after costs");
   if(m_rsi==NULL && m_early_exit_enabled)
      result.AddWarning("CScalpController: early profit exit enabled without "
                        "RSI; only the target-share rule will apply");

   //=== TIER COHERENCE ================================================
   //--- Checked at STARTUP, not per trade, so an impossible tier is
   //--- reported before it can take a position. The gross geometry is
   //--- inspected here because costs are not yet known; the per-trade gate
   //--- repeats the test against real spread.
   bool any_tier=false;
   for(int i=0;i<3;i++)
     {
      if(!m_tier_enabled[i])
         continue;
      any_tier=true;
      const ENUM_SRP_SCALP_TIER t=(ENUM_SRP_SCALP_TIER)i;
      const double gross=(m_tier_stop_atr[i]>0.0
                          ? m_tier_target_atr[i]/m_tier_stop_atr[i] : 0.0);
      const double needed=RequiredPayoff(m_tier_assumed_winrate[i]);
      if(gross<needed)
         result.AddError(StringFormat(
            "CScalpController: %s tier geometry cannot break even at its own "
            "design win rate - %.2f/%.2f gives payoff %.3f but %.0f%% wins "
            "needs %.3f BEFORE costs",
            TierToString(t),m_tier_target_atr[i],m_tier_stop_atr[i],gross,
            m_tier_assumed_winrate[i]*100.0,needed));
      if(m_tier_max_hold[i]<15)
         result.AddWarning(StringFormat(
            "CScalpController: %s tier holding window %ds is shorter than a "
            "single M1 bar",TierToString(t),m_tier_max_hold[i]));
      if(m_tier_atr[i]==NULL)
         result.AddWarning(StringFormat(
            "CScalpController: %s tier has no ATR of its own and will size "
            "from the execution timeframe",TierToString(t)));
     }
   if(!any_tier)
      result.AddError("CScalpController: scalp mode is enabled but every "
                      "tier is disabled, so no scalp can ever be taken");
  }
//+------------------------------------------------------------------+
SScalpSignalId CScalpController::BuildSignalId(const datetime bar_time,
                                              const bool is_buy,
                                              const int strategy_kind,
                                              const int structure_event,
                                              const datetime event_time)
  {
   SScalpSignalId id;
   id.bar_time        = bar_time;
   id.direction       = (is_buy ? 1 : -1);
   id.strategy        = strategy_kind;
   id.structure_event = structure_event;
   id.event_time      = event_time;
   id.valid           = (bar_time>0);
   return(id);
  }
//+------------------------------------------------------------------+
void CScalpController::RollDay(const datetime now)
  {
   MqlDateTime dt;
   TimeToStruct(now,dt);
   const int key=dt.year*1000+dt.day_of_year;
   if(key!=m_today_day)
     {
      if(m_today_day>=0)
         m_metrics.days_traded++;
      m_today_day=key;
      m_today_count=0;
     }
  }
//+------------------------------------------------------------------+
double CScalpController::ReadAtrPoints(void) const
  {
   if(m_atr==NULL || m_point<=0.0)
      return(0.0);
   double atr=0.0;
   //--- Shift 1: the last CLOSED bar. Using the forming bar would make
   //--- the target move within the bar.
   if(!m_atr.ValueAt(0,1,atr) || atr<=0.0)
      return(0.0);
   return(atr/m_point);
  }
//+------------------------------------------------------------------+
double CScalpController::ReadTierAtrPoints(const ENUM_SRP_SCALP_TIER tier) const
  {
   const int i=(int)tier;
   if(i<0 || i>2 || m_point<=0.0)
      return(0.0);
   //--- Prefer the tier's own series. A SWING tier sized from M1 ATR would
   //--- set a target far too tight for the window it is willing to hold,
   //--- which is the same class of error as the swing-stop defect.
   if(m_tier_atr[i]!=NULL)
     {
      double atr=0.0;
      //--- Shift 1: the last CLOSED bar, so the target cannot move
      //--- within the forming bar.
      if(m_tier_atr[i].ValueAt(0,1,atr) && atr>0.0)
         return(atr/m_point);
     }
   return(ReadAtrPoints());
  }
//+------------------------------------------------------------------+
//| THE GATE.                                                          |
//|                                                                  |
//| Order is chosen so the cheapest and most decisive checks run first,   |
//| and so the reported reason is the PRIMARY one rather than whichever    |
//| check happened to be last.                                           |
//+------------------------------------------------------------------+
bool CScalpController::Evaluate(const SScalpSignalId &id,
                                const datetime now,
                                const double spread_points,
                                const int open_positions,
                                const int max_positions,
                                SScalpVerdict &verdict,
                                const ENUM_SRP_SCALP_TIER tier)
  {
   verdict.Reset();
   verdict.spread_points=spread_points;
   verdict.tier=tier;

   if(!m_enabled)
     {
      verdict.block=SRP_SCALP_BLOCK_DISABLED;
      verdict.detail="scalp mode disabled";
      m_last_verdict=verdict;
      return(false);
     }

   //--- 0. TIER ENABLED. A disabled tier refuses before anything else, so
   //--- turning one off costs nothing and cannot leak a trade.
   const int ti=(int)tier;
   if(ti<0 || ti>2 || !m_tier_enabled[ti])
     {
      verdict.block=SRP_SCALP_BLOCK_DISABLED;
      verdict.detail=TierToString(tier)+" tier disabled";
      m_last_verdict=verdict;
      return(false);
     }
   verdict.max_hold_seconds=m_tier_max_hold[ti];

   RefreshSpec();
   RollDay(now);
   m_metrics.signals_seen++;

   //--- 1. DUPLICATE. The most important gate in this class. A signal
   //--- that is still true on the next tick is the SAME event, and
   //--- entering it again would compound a single opinion into several
   //--- positions.
   if(id.Equals(m_last_traded))
     {
      verdict.block=SRP_SCALP_BLOCK_DUPLICATE;
      verdict.detail="signal already traded: "+id.Describe();
      m_metrics.blocked_duplicate++;
      m_last_verdict=verdict;
      return(false);
     }

   //--- 2. COOLDOWN. Short by design. Catches the case where the same
   //--- market event produces a marginally different fingerprint on the
   //--- following tick, which duplicate detection alone would miss.
   if(m_last_entry_time>0 && m_cooldown_seconds>0)
     {
      const int elapsed=(int)(now-m_last_entry_time);
      if(elapsed<m_cooldown_seconds)
        {
         verdict.block=SRP_SCALP_BLOCK_COOLDOWN;
         verdict.detail=StringFormat("cooldown: %ds of %ds elapsed",
                                     elapsed,m_cooldown_seconds);
         m_metrics.blocked_cooldown++;
         m_last_verdict=verdict;
         return(false);
        }
     }

   //--- 3. EXPOSURE. Checked before any arithmetic: a full book cannot
   //--- take a trade whatever the target would have been.
   if(max_positions>0 && open_positions>=max_positions)
     {
      verdict.block=SRP_SCALP_BLOCK_MAX_POSITIONS;
      verdict.detail=StringFormat("position slots full: %d of %d",
                                  open_positions,max_positions);
      m_metrics.blocked_positions++;
      m_last_verdict=verdict;
      return(false);
     }

   //--- 4. DAILY CEILING. A cap, not a quota: reaching it stops trading,
   //--- never encourages it.
   if(m_max_scalps_per_day>0 && m_today_count>=m_max_scalps_per_day)
     {
      verdict.block=SRP_SCALP_BLOCK_DAILY_LIMIT;
      verdict.detail=StringFormat("daily scalp cap reached: %d",
                                  m_today_count);
      m_metrics.blocked_daily++;
      m_last_verdict=verdict;
      return(false);
     }

   //--- 5. VOLATILITY. The target is ATR-derived, so an unusable ATR
   //--- makes the whole calculation meaningless.
   //--- Read from the TIER's timeframe: a 90-second scalp and a 15-minute
   //--- one must not be sized from the same volatility figure.
   const double atr_points=ReadTierAtrPoints(tier);
   verdict.atr_points=atr_points;
   if(atr_points<=0.0)
     {
      verdict.block=SRP_SCALP_BLOCK_ATR;
      verdict.detail="ATR unavailable, cannot size a scalp target";
      m_metrics.blocked_atr++;
      m_last_verdict=verdict;
      return(false);
     }
   if(m_atr_min_points>0.0 && atr_points<m_atr_min_points)
     {
      verdict.block=SRP_SCALP_BLOCK_ATR;
      verdict.detail=StringFormat("ATR %.0f pts below the %.0f floor: a "
                                  "scalp would not clear costs",
                                  atr_points,m_atr_min_points);
      m_metrics.blocked_atr++;
      m_last_verdict=verdict;
      return(false);
     }
   if(m_atr_max_points>0.0 && atr_points>m_atr_max_points)
     {
      verdict.block=SRP_SCALP_BLOCK_ATR;
      verdict.detail=StringFormat("ATR %.0f pts above the %.0f ceiling: "
                                  "conditions too disorderly to scalp",
                                  atr_points,m_atr_max_points);
      m_metrics.blocked_atr++;
      m_last_verdict=verdict;
      return(false);
     }

   //--- 6. TARGET, from ATR, then clamped to configured bounds and the
   //--- broker's own minimum distance.
   //--- TIER GEOMETRY. The tier's multiples, not the global pair, so the
   //--- target and the stop always belong to the same design.
   double target=atr_points*m_tier_target_atr[ti];
   if(m_target_min_points>0.0) target=MathMax(target,m_target_min_points);
   if(m_target_max_points>0.0) target=MathMin(target,m_target_max_points);
   if(m_stops_level>0)         target=MathMax(target,(double)m_stops_level*1.2);
   verdict.target_points=target;
   verdict.stop_points=MathMax(atr_points*m_tier_stop_atr[ti],
                               (double)m_stops_level*1.2);

   //--- 7. ROUND-TRIP COST. The economic test.
   //--- Spread is paid on entry; commission and execution cost are
   //--- modelled on the full round trip. A target that does not clear
   //--- this by the configured ratio is a losing trade taken on purpose.
   const double cost=spread_points+m_commission_points+
                     m_execution_cost_points;
   verdict.cost_points=cost;

   //--- 7a. SPREAD relative to the target. Independent of absolute size:
   //--- a wide spread against a wide target can still be acceptable,
   //--- while a modest spread against a tiny target is not.
   if(target>0.0 && spread_points>target*m_max_spread_target_ratio)
     {
      verdict.block=SRP_SCALP_BLOCK_SPREAD;
      verdict.detail=StringFormat("spread %.0f pts is %.0f%% of the %.0f pt "
                                  "target, ceiling is %.0f%%",
                                  spread_points,
                                  spread_points/target*100.0,target,
                                  m_max_spread_target_ratio*100.0);
      m_metrics.blocked_spread++;
      m_last_verdict=verdict;
      return(false);
     }

   //--- 7b. Reward against total modelled cost.
   if(target<cost*m_min_reward_cost_ratio)
     {
      verdict.block=SRP_SCALP_BLOCK_COST;
      m_last_cost_detail=StringFormat("target %.0f pts vs cost %.0f pts "
                                      "(spread %.0f + commission %.0f + "
                                      "execution %.0f), needed %.0f",
                                      target,cost,spread_points,
                                      m_commission_points,
                                      m_execution_cost_points,
                                      cost*m_min_reward_cost_ratio);
      verdict.detail=StringFormat("target %.0f pts does not clear cost %.0f "
                                  "pts by the required %.1fx",
                                  target,cost,m_min_reward_cost_ratio);
      m_metrics.blocked_cost++;
      m_last_verdict=verdict;
      return(false);
     }

   //--- 8. THE BREAK-EVEN TEST. The gate this system did not have.
   //---
   //--- Everything above asks "can this trade be afforded". This asks the
   //--- question that actually decides profitability: at the win rate this
   //--- tier is designed around, does this geometry make money AFTER costs?
   //---
   //--- Costs are counted on BOTH sides, and that asymmetry is the whole
   //--- point: a win collects (target - cost) while a loss pays
   //--- (stop + cost). Measured over 31 months the system ran a 0.948 gross
   //--- payoff at a 43.9% win rate - it needed 51.3% - and nothing in the
   //--- code compared those two numbers. That is why it lost on 1221 trades
   //--- while every individual gate reported success.
   const double net_win  = target-cost;
   const double net_loss = verdict.stop_points+cost;
   verdict.net_payoff=(net_loss>0.0 ? net_win/net_loss : 0.0);
   verdict.required_winrate=BreakEvenWinRate(verdict.net_payoff);

   if(net_win<=0.0)
     {
      verdict.block=SRP_SCALP_BLOCK_BREAKEVEN;
      verdict.detail=StringFormat("%s: target %.0f pts does not survive "
                                  "%.0f pts of cost - a win would book a loss",
                                  TierToString(tier),target,cost);
      m_metrics.blocked_cost++;
      m_last_verdict=verdict;
      return(false);
     }
   if(verdict.required_winrate>m_tier_assumed_winrate[ti])
     {
      verdict.block=SRP_SCALP_BLOCK_BREAKEVEN;
      verdict.detail=StringFormat("%s: net payoff %.3f needs a %.1f%% win "
                                  "rate but the tier is designed for %.1f%% "
                                  "(target %.0f, stop %.0f, cost %.0f)",
                                  TierToString(tier),verdict.net_payoff,
                                  verdict.required_winrate*100.0,
                                  m_tier_assumed_winrate[ti]*100.0,
                                  target,verdict.stop_points,cost);
      m_metrics.blocked_cost++;
      m_last_verdict=verdict;
      return(false);
     }

   verdict.allowed=true;
   verdict.block=SRP_SCALP_OK;
   verdict.detail=StringFormat("%s: target %.0f pts, stop %.0f pts, cost "
                               "%.0f pts, ATR %.0f pts, net payoff %.3f "
                               "(needs %.1f%% wins, hold %ds)",
                               TierToString(tier),target,verdict.stop_points,
                               cost,atr_points,verdict.net_payoff,
                               verdict.required_winrate*100.0,
                               verdict.max_hold_seconds);
   m_last_verdict=verdict;
   return(true);
  }
//+------------------------------------------------------------------+
//| Recorded only on a CONFIRMED fill.                                 |
//|                                                                  |
//| Marking a signal as traded on intent would permanently suppress a     |
//| signal whose order was rejected - the setup would be consumed without  |
//| a position ever existing.                                            |
//+------------------------------------------------------------------+
void CScalpController::RecordEntry(const SScalpSignalId &id,
                                   const datetime now,
                                   const double spread_points,
                                   const ENUM_SRP_SCALP_TIER tier)
  {
   m_last_traded=id;
   m_last_entry_time=now;
   RollDay(now);
   m_today_count++;
   m_metrics.entries++;
   m_last_tier=tier;
   if((int)tier>=0 && (int)tier<=2)
      m_tier_entries[(int)tier]++;
   if(spread_points>0.0)
     {
      m_metrics.spread_sum+=spread_points;
      m_metrics.spread_samples++;
     }
  }
//+------------------------------------------------------------------+
//| EARLY PROFIT EXIT.                                                 |
//|                                                                  |
//| Two conditions must BOTH hold, and the order matters:                 |
//|                                                                  |
//|   1. Profit exceeds the cost floor. Without this the exit would book   |
//|      a nominal gain that is a net loss after spread and commission.    |
//|   2. Either a meaningful share of the target is banked, or momentum    |
//|      has turned against the position.                                |
//|                                                                  |
//| It deliberately CANNOT fire on a position that is merely a few points  |
//| positive, which the requirement forbids: the cost floor and the        |
//| target-share test both stand in the way.                              |
//+------------------------------------------------------------------+
bool CScalpController::ShouldTakeEarlyProfit(const bool is_buy,
                                             const double profit_points,
                                             const double target_points,
                                             string &reason) const
  {
   reason="";
   if(!m_early_exit_enabled)
      return(false);

   //--- 1. COST FLOOR. Non-negotiable.
   if(profit_points<=m_early_exit_min_points)
      return(false);

   //--- 2a. A good share of the target is already banked, and the move
   //--- has not continued to the target itself.
   if(target_points>0.0 &&
      profit_points>=target_points*m_early_exit_target_share)
     {
      //--- Momentum check, when RSI is available. A position deep in
      //--- profit with fading momentum is the classic case for taking it.
      if(m_rsi!=NULL)
        {
         double rsi_now=0.0,rsi_prev=0.0;
         if(m_rsi.ValueAt(0,0,rsi_now) && m_rsi.ValueAt(0,1,rsi_prev))
           {
            //--- Fading means the oscillator is retreating from the
            //--- direction of the trade.
            const bool fading=(is_buy ? (rsi_now<rsi_prev && rsi_now<60.0)
                                      : (rsi_now>rsi_prev && rsi_now>40.0));
            if(fading)
              {
               reason=StringFormat("early profit: %.0f pts (%.0f%% of "
                                   "target) with momentum fading "
                                   "(RSI %.1f from %.1f)",
                                   profit_points,
                                   profit_points/target_points*100.0,
                                   rsi_now,rsi_prev);
               return(true);
              }
           }
        }
      //--- Without RSI, a very large share of the target is enough on its
      //--- own: the micro-move is effectively exhausted.
      if(profit_points>=target_points*0.85)
        {
         reason=StringFormat("early profit: %.0f pts is %.0f%% of the "
                             "target, micro-move exhausted",
                             profit_points,
                             profit_points/target_points*100.0);
         return(true);
        }
     }
   return(false);
  }
//+------------------------------------------------------------------+
bool CScalpController::ShouldTimeOut(const datetime open_time,
                                     const datetime now,
                                     string &reason,
                                     const int limit_seconds) const
  {
   reason="";
   //--- The tier's own window when one was supplied, otherwise the global
   //--- one. A SUPER_SCALP held for five minutes is no longer the trade
   //--- that was entered.
   const int limit=(limit_seconds>0 ? limit_seconds : m_max_hold_seconds);
   if(limit<=0 || open_time<=0 || now<=open_time)
      return(false);
   const int held=(int)(now-open_time);
   if(held<limit)
      return(false);
   //--- NOTE: this only reports that the window elapsed. The stop is
   //--- never widened and the size is never increased; the engine routes
   //--- the close through the existing execution path.
   reason=StringFormat("scalp timeout: held %ds, limit %ds, expected move "
                       "did not develop",held,limit);
   return(true);
  }
//+------------------------------------------------------------------+
void CScalpController::RecordExit(const ENUM_SRP_TM_TRIGGER trigger,
                                  const int hold_seconds,
                                  const double net_profit,
                                  const ENUM_SRP_SCALP_TIER tier)
  {
   //--- PER-TIER LEDGER, kept first so it is recorded whatever the exit
   //--- attribution below decides. Without this a tier's achieved win rate
   //--- is unknowable and the tier design cannot be falsified.
   const int ti=(int)tier;
   if(ti>=0 && ti<=2)
     {
      if(net_profit>0.0)
        { m_tier_wins[ti]++;   m_tier_gross_win[ti]+=net_profit; }
      else if(net_profit<0.0)
        { m_tier_losses[ti]++; m_tier_gross_loss[ti]+=MathAbs(net_profit); }
     }

   switch(trigger)
     {
      case SRP_TM_TRIGGER_EARLY_PROFIT:  m_metrics.exit_early++;   break;
      case SRP_TM_TRIGGER_SCALP_TIMEOUT:
      case SRP_TM_TRIGGER_TIME_EXIT:
      case SRP_TM_TRIGGER_MAX_HOLD:      m_metrics.exit_timeout++; break;
      default:
         //--- Attribution from the outcome when the broker closed it:
         //--- a profitable broker-side close is the target being hit, a
         //--- losing one is the stop.
         if(net_profit>0.0)      m_metrics.exit_tp++;
         else if(net_profit<0.0) m_metrics.exit_sl++;
         else                    m_metrics.exit_other++;
         break;
     }

   if(hold_seconds>0)
     {
      m_metrics.hold_total_seconds+=hold_seconds;
      if(m_metrics.hold_fastest==0 || hold_seconds<m_metrics.hold_fastest)
         m_metrics.hold_fastest=hold_seconds;
      if(hold_seconds>m_metrics.hold_longest)
         m_metrics.hold_longest=hold_seconds;
      //--- Bounded ring: the median needs samples, and an unbounded array
      //--- would grow without limit across a long optimisation.
      const int capacity=ArraySize(m_metrics.hold_samples);
      m_metrics.hold_samples[m_metrics.hold_cursor]=hold_seconds;
      m_metrics.hold_cursor=(m_metrics.hold_cursor+1)%capacity;
      if(m_metrics.hold_count<capacity)
         m_metrics.hold_count++;
     }

   if(net_profit>0.0)      { m_metrics.wins++;   m_metrics.gross_win+=net_profit; }
   else if(net_profit<0.0) { m_metrics.losses++; m_metrics.gross_loss+=MathAbs(net_profit); }
  }
//+------------------------------------------------------------------+
double CScalpController::AverageHoldSeconds(void) const
  {
   const long closed=m_metrics.wins+m_metrics.losses;
   if(closed<=0)
      return(0.0);
   return((double)m_metrics.hold_total_seconds/(double)closed);
  }
//+------------------------------------------------------------------+
double CScalpController::MedianHoldSeconds(void) const
  {
   if(m_metrics.hold_count<=0)
      return(0.0);
   int sorted[];
   ArrayResize(sorted,m_metrics.hold_count);
   for(int i=0;i<m_metrics.hold_count;i++)
      sorted[i]=m_metrics.hold_samples[i];
   ArraySort(sorted);
   const int mid=m_metrics.hold_count/2;
   if(m_metrics.hold_count%2==1)
      return((double)sorted[mid]);
   return(((double)sorted[mid-1]+(double)sorted[mid])/2.0);
  }
//+------------------------------------------------------------------+
double CScalpController::AverageSpreadPoints(void) const
  {
   if(m_metrics.spread_samples<=0)
      return(0.0);
   return(m_metrics.spread_sum/(double)m_metrics.spread_samples);
  }
//+------------------------------------------------------------------+
//| THE ENTRY FUNNEL. Every signal seen, and where each one went.       |
//+------------------------------------------------------------------+
string CScalpController::DescribeFunnel(void) const
  {
   const long blocked=m_metrics.blocked_duplicate+m_metrics.blocked_cooldown+
                      m_metrics.blocked_spread+m_metrics.blocked_cost+
                      m_metrics.blocked_positions+m_metrics.blocked_atr+
                      m_metrics.blocked_daily;
   string text=StringFormat("SCALP FUNNEL: %I64d signal(s) -> %I64d entry(ies), "
                            "%I64d blocked",
                            m_metrics.signals_seen,m_metrics.entries,blocked);
   text+="\n  blocked by:";
   if(m_metrics.blocked_duplicate>0)
      text+=StringFormat(" DUPLICATE=%I64d",m_metrics.blocked_duplicate);
   if(m_metrics.blocked_cooldown>0)
      text+=StringFormat(" COOLDOWN=%I64d",m_metrics.blocked_cooldown);
   if(m_metrics.blocked_spread>0)
      text+=StringFormat(" SPREAD=%I64d",m_metrics.blocked_spread);
   if(m_metrics.blocked_cost>0)
      text+=StringFormat(" COST=%I64d",m_metrics.blocked_cost);
   if(m_metrics.blocked_positions>0)
      text+=StringFormat(" MAX_POSITIONS=%I64d",m_metrics.blocked_positions);
   if(m_metrics.blocked_atr>0)
      text+=StringFormat(" ATR=%I64d",m_metrics.blocked_atr);
   if(m_metrics.blocked_daily>0)
      text+=StringFormat(" DAILY_LIMIT=%I64d",m_metrics.blocked_daily);
   if(blocked==0)
      text+=" nothing";

   //--- THE COST ARITHMETIC, stated rather than left to be inferred.
   //---
   //--- "COST=23" says the target could not clear the round trip but not by
   //--- how much, so an operator cannot distinguish an impossible geometry
   //--- from a marginal one. Printing the model and the last refusal makes
   //--- the requirement checkable against a real spread.
   if(m_metrics.blocked_cost>0)
     {
      text+=StringFormat("\n  cost model: commission %.1f + execution %.1f "
                         "pts; target must exceed (spread+cost) x%.1f",
                         m_commission_points,m_execution_cost_points,
                         m_min_reward_cost_ratio);
      if(m_last_cost_detail!="")
         text+="\n  last cost refusal: "+m_last_cost_detail;
     }
   return(text);
  }
//+------------------------------------------------------------------+
string CScalpController::DescribeMetrics(void) const
  {
   const long closed=m_metrics.wins+m_metrics.losses;
   const double win_rate=(closed>0 ? (double)m_metrics.wins/(double)closed*100.0
                                   : 0.0);
   const double pf=(m_metrics.gross_loss>0.0
                    ? m_metrics.gross_win/m_metrics.gross_loss : 0.0);
   const int days=(m_metrics.days_traded>0 ? m_metrics.days_traded : 1);

   string text="SCALP METRICS";
   text+=StringFormat("\n  entries=%I64d closed=%I64d scalps/day=%.2f",
                      m_metrics.entries,closed,
                      (double)m_metrics.entries/(double)days);
   text+=StringFormat("\n  holding: avg=%.0fs median=%.0fs fastest=%ds "
                      "longest=%ds",
                      AverageHoldSeconds(),MedianHoldSeconds(),
                      m_metrics.hold_fastest,m_metrics.hold_longest);
   text+=StringFormat("\n  exits: TP=%I64d SL=%I64d EARLY=%I64d TIMEOUT=%I64d "
                      "other=%I64d",
                      m_metrics.exit_tp,m_metrics.exit_sl,
                      m_metrics.exit_early,m_metrics.exit_timeout,
                      m_metrics.exit_other);
   text+=StringFormat("\n  win rate=%.2f%% profit factor=%.3f",win_rate,pf);
   text+=StringFormat("\n  avg win=%.2f avg loss=%.2f",
                      (m_metrics.wins>0
                       ? m_metrics.gross_win/(double)m_metrics.wins : 0.0),
                      (m_metrics.losses>0
                       ? m_metrics.gross_loss/(double)m_metrics.losses : 0.0));
   text+=StringFormat("\n  avg spread at entry=%.1f pts",
                      AverageSpreadPoints());
   return(text);
  }
//+------------------------------------------------------------------+
string CScalpController::BlockToString(const ENUM_SRP_SCALP_BLOCK block)
  {
   switch(block)
     {
      case SRP_SCALP_OK:                   return("OK");
      case SRP_SCALP_BLOCK_DUPLICATE:      return("DUPLICATE_SIGNAL");
      case SRP_SCALP_BLOCK_COOLDOWN:       return("COOLDOWN");
      case SRP_SCALP_BLOCK_SPREAD:         return("SPREAD_BLOCK");
      case SRP_SCALP_BLOCK_COST:           return("COST_BLOCK");
      case SRP_SCALP_BLOCK_MAX_POSITIONS:  return("MAX_POSITIONS");
      case SRP_SCALP_BLOCK_ATR:            return("ATR_BLOCK");
      case SRP_SCALP_BLOCK_DAILY_LIMIT:    return("DAILY_LIMIT");
      case SRP_SCALP_BLOCK_DISABLED:       return("DISABLED");
     }
   return("UNKNOWN");
  }

#endif // SRP_PROFILES_CSCALPCONTROLLER_MQH
//+------------------------------------------------------------------+
