//+------------------------------------------------------------------+
//|                                              XspConstants.mqh |
//|             XauStructurePro - Core/Types : compile-time constants |
//|                                                                  |
//|   XauStructurePro (XSP) is a SEPARATE PRODUCT from Scalping Robot     |
//|   Pro. It exists because SRP 1.11 failed its pre-registered           |
//|   validation and the audit's section 11 step 5 authorised a rebuild   |
//|   as new code with the old EA left intact for comparison.             |
//|                                                                  |
//|   EVERY NAMESPACE HERE IS DISTINCT FROM SRP's. Object prefix, global  |
//|   variable prefix and data folder are all different, so the two EAs   |
//|   can run on the same terminal without one clearing the other's       |
//|   chart objects or reading the other's persisted state. That is not   |
//|   tidiness: SRP is the section-9.5 comparison baseline, and a         |
//|   baseline that XSP can perturb is not a baseline.                    |
//+------------------------------------------------------------------+
#ifndef XSP_CORE_XSPCONSTANTS_MQH
#define XSP_CORE_XSPCONSTANTS_MQH

//--- Product identity ------------------------------------------------
#define XSP_PRODUCT_NAME              "XauStructurePro"
#define XSP_PRODUCT_SHORT             "XSP"
//--- 0.1: Phase A only. There is NO order path in this version and no
//--- claim of tradability. It records candidate setups and tracks their
//--- barriers forward so the question "is there an edge at all" can be
//--- answered before an execution layer is written.
#define XSP_PRODUCT_VERSION           "0.1-phaseA"
#define XSP_PRODUCT_COPYRIGHT         "Copyright 2026"

//--- Distinct namespaces (see the header note) ------------------------
#define XSP_OBJECT_PREFIX             "XSP_"
#define XSP_GLOBAL_VAR_PREFIX         "XSP::"
#define XSP_DATA_FOLDER               "XauStructurePro"

//--- The study output, and the version of its column layout.
//---
//--- The schema version is written into the file's preamble and ASSERTED by
//--- the analysis script. It exists because the failure mode of a 45-column
//--- CSV is silent: add a column here, forget the script, and every cut
//--- afterwards reads the wrong field with no error anywhere. A version
//--- string turns that into a refusal to run.
#define XSP_STUDY_FILE                "xsp_instances.csv"
#define XSP_SCHEMA_VERSION            "xsp-instance-v1"

//--- Barrier geometry under test -------------------------------------
//--- FOUR reward multiples of ONE stop, all tracked on every instance.
//--- One pass therefore yields the whole target/stop surface. The audit's
//--- section 4.4 measured corr(win_rate, payoff) = -0.982 across 1,078
//--- optimiser passes: geometry slides along a fixed tradeoff and cannot
//--- manufacture accuracy. Sweeping it in separate runs would have bought
//--- nothing except a chance to pick the luckiest cell.
#define XSP_R_TIERS                   4
#define XSP_R_1                       1.0
#define XSP_R_2                       1.5
#define XSP_R_3                       2.0
#define XSP_R_4                       3.0

//--- Holding-horizon caps in SECONDS, per audit section 8.1: the product
//--- stops being a 22-second scalper. Recorded, never enforced - see
//--- CXspBarrierTracker for why every cap is derivable from one pass.
#define XSP_CAP_TIERS                 4
#define XSP_CAP_1                     300     //  5 minutes
#define XSP_CAP_2                     900     // 15 minutes
#define XSP_CAP_3                     1800    // 30 minutes
#define XSP_CAP_4                     3600    // 60 minutes, the ceiling

//--- Tracking ceiling. Equal to the largest cap: nothing beyond it can
//--- inform any cap that will be evaluated, so tracking past it would
//--- cost memory and buy no measurement.
#define XSP_TRACK_MAX_SECONDS         XSP_CAP_4
//--- Concurrent live instances. Setups fire on closed M15 bars and are
//--- fingerprinted, so the true concurrency is small; this is a ceiling
//--- against a pathological run rather than an expected working size.
#define XSP_MAX_LIVE_INSTANCES        256

//--- Declared, NOT optimised. Every one of these is a pre-registered
//--- constant: the audit's section 9 forbids selecting them on the data
//--- this study measures, so they are stated here once and quoted in the
//--- changelog hypothesis table before the run.
#define XSP_STOP_BUFFER_ATR           0.20    // beyond the invalidation
#define XSP_POOL_TOLERANCE_ATR        0.15    // equal-highs cluster width
#define XSP_SWEEP_WINDOW_BARS         3       // penetrate then reject within
#define XSP_CONFIRM_MIN_RATIO         1.50    // tick-volume expansion
#define XSP_CONFIRM_SLOT_SESSIONS     20      // same-minute-of-day baseline
#define XSP_VOL_RANK_BARS             480     // 5 days of M15 for the decile
#define XSP_SPREAD_RANK_SAMPLES       4096    // rolling tick-spread window

//--- ATR period and the S1 displacement definition. These four numbers
//--- are XSP's OWN, deliberately re-declared rather than inherited from
//--- SRP's CDisplacementDetector: the point of a rebuild is that SRP's
//--- definitions are the ones that failed, so reusing its thresholds
//--- unexamined would carry the failure across. They are pre-registered
//--- here and quoted in the changelog hypothesis table before the run.
#define XSP_ATR_PERIOD                14
#define XSP_DISP_ATR_MULT             1.50    // bar range vs ATR
#define XSP_DISP_BODY_RATIO           0.60    // |close-open| / range
#define XSP_DISP_CLOSE_POS            0.70    // close inside the range, 0..1

//--- Timeframes for the 5-60 minute horizon --------------------------
#define XSP_TF_EXEC                   PERIOD_M5
#define XSP_TF_SETUP                  PERIOD_M15
#define XSP_TF_CONTEXT                PERIOD_H1
#define XSP_TF_HIGHER                 PERIOD_H4

//--- Numeric tolerance. Independent of SRP_EPSILON so a change there
//--- cannot silently alter a measurement here.
#define XSP_EPSILON                   0.0000001

//--- Sentinels. -1 means "did not happen inside the tracking window",
//--- which is a DIFFERENT statement from "happened at second 0".
#define XSP_NEVER                     (-1)

//--- "No mark was taken at this holding cap", for the R-at-cap columns.
//--- A distinct impossible value rather than -1: the stop sits at exactly
//--- -1.0 R, so -1 as a sentinel would collide with a real excursion at
//--- the one place the collision matters. -999 R cannot occur, because an
//--- instance whose adverse excursion reached -1 R has already stopped and
//--- stopped tracking. This is what separates a TIME EXIT with a known
//--- mark-to-market from an UNRESOLVED instance the run ended underneath.
#define XSP_NO_MARK                   (-999.0)

#endif // XSP_CORE_XSPCONSTANTS_MQH
//+------------------------------------------------------------------+
