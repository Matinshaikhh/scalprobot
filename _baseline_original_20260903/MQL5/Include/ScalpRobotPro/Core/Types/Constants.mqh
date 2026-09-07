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
#define SRP_PRODUCT_VERSION           "1.00"
#define SRP_PRODUCT_BUILD             1
#define SRP_PRODUCT_COPYRIGHT         "Copyright 2026"

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
