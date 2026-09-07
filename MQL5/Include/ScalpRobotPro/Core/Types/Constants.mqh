//+------------------------------------------------------------------+
//|                                                    Constants.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|                    Core/Types : immutable compile-time constants |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_TYPES_CONSTANTS_MQH
#define SRP_CORE_TYPES_CONSTANTS_MQH

//--- Product identity -----------------------------------------------
#define SRP_PRODUCT_NAME              "Scalping Robot Pro"
#define SRP_PRODUCT_SHORT             "SRP"
//--- 1.10: the audit fixes. 1 (daily stand-down against a drawdown latch),
//--- 2 (server-side fill slippage), 3 (commission as a parameter) all change
//--- what a run does through their defaults, so results from 1.00 and 1.10
//--- are not comparable and the version has to say so.
//--- 1.11: the strategy redesign of 2026-09-05. The break-even gate now
//--- prices the target the early-profit exit actually collects (target*share)
//--- rather than the full target; tier geometry was widened from cost algebra
//--- so the collected target clears a ~46.5pt round trip; break-of-structure
//--- is disabled as an entry (it resolved its own barriers worse than a
//--- driftless walk on the July 2026 XAUUSD run); the signal's own structural
//--- stop is now consumed; and the weighted vote resolves the carrier by
//--- confidence*weight. Every one of these changes what a run DOES, so 1.11
//--- is not comparable with 1.10 and the version says so. The measurement
//--- harness (SRP_HARNESS_VERSION) is unchanged.
#define SRP_PRODUCT_VERSION           "1.11"
#define SRP_PRODUCT_BUILD             3
#define SRP_PRODUCT_COPYRIGHT         "Copyright 2026"

//--- HARNESS v2, FIX 4. The MEASUREMENT harness, versioned separately from
//--- the product. Two different things change at two different rates: the
//--- strategy will be revised many times against an unchanged harness, and
//--- the harness can gain a measurement without the strategy moving at all.
//--- Overloading one version string on both would make every report header
//--- ambiguous about which of the two it is describing.
//---
//--- v1 was the implicit harness before the audit: no tick-model inference,
//--- no declared cost model, no segment, no provenance in any report. v2 is
//--- what fix 4 installs. A number quoted from a v1 report cannot be
//--- reproduced, because nothing recorded the conditions that produced it.
#define SRP_HARNESS_VERSION           "harness-v2"

//--- Chart object namespace (every graphical object is prefixed) -----
#define SRP_OBJECT_PREFIX             "SRP_"
#define SRP_DASHBOARD_PREFIX          "SRP_DASH_"

//--- Persistence ----------------------------------------------------
#define SRP_DATA_FOLDER               "ScalpRobotPro"
#define SRP_STATE_FILE                "state.json"
#define SRP_JOURNAL_FILE              "trade_journal.csv"
#define SRP_LOG_FILE_PATTERN          "log_%s.txt"
#define SRP_NEWS_CACHE_FILE           "news_cache.csv"

//--- Global variable namespace (terminal GlobalVariables) ------------
#define SRP_GLOBAL_VAR_PREFIX         "SRP::"

//--- Engine timing --------------------------------------------------
#define SRP_TIMER_INTERVAL_MS         250      // OnTimer heartbeat
#define SRP_DASHBOARD_REFRESH_MS      500      // UI repaint throttle
#define SRP_HEALTH_CHECK_INTERVAL_SEC 60
#define SRP_NEWS_REFRESH_INTERVAL_SEC 900

//--- Execution defaults ---------------------------------------------
#define SRP_MAX_EXECUTION_RETRIES     3
#define SRP_RETRY_BACKOFF_MS          150
#define SRP_DEFAULT_DEVIATION_POINTS  20
#define SRP_MAX_MODULES               64
#define SRP_MAX_EVENT_LISTENERS       128
#define SRP_MAX_SIGNAL_CONTRIBUTORS   16

//--- Numeric tolerances ---------------------------------------------
#define SRP_EPSILON                   0.0000001
#define SRP_PRICE_EPSILON             0.00000001

//--- Sentinel values ------------------------------------------------
#define SRP_INVALID_HANDLE            (-1)
#define SRP_INVALID_TICKET            (0)
#define SRP_INVALID_PRICE             (0.0)
#define SRP_INVALID_INDEX             (-1)

#endif // SRP_CORE_TYPES_CONSTANTS_MQH
//+------------------------------------------------------------------+
