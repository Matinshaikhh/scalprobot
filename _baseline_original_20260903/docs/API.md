# API Documentation

Public surfaces of the classes you interact with when embedding, extending or testing
Scalping Robot Pro. Private helpers are omitted; read the headers for those.

Conventions used below:

- **owns** — the receiver deletes it
- **borrows** — the caller retains ownership and must outlive the receiver
- Distances are in **points** unless stated otherwise

---

## CProductionEngine

`Runtime\CProductionEngine.mqh` — the composition root. The only class that `new`s on the
trading path, and the only one the .mq5 entry point talks to.

### Lifecycle

```cpp
bool Build(IConfigProvider *config, const string symbol,
           const ENUM_TIMEFRAMES timeframe);
int  Start(void);
void Stop(const int deinit_reason);
```

`Build` constructs every subsystem in dependency order, then validates. On failure it
releases everything and returns `false` rather than leaving a half-built graph running —
call `ValidationReport()` for the reason. `config` is **borrowed** and must outlive the
engine.

`Start` initialises the risk ledger and returns an `INIT_*` code for `OnInit` to propagate
verbatim.

`Stop` publishes the session report, then releases. Safe to call twice.

### Terminal events

```cpp
void   OnTickEvent(void);
void   OnTimerEvent(void);
void   OnTradeTransactionEvent(const MqlTradeTransaction &transaction,
                               const MqlTradeRequest &request,
                               const MqlTradeResult &result);
void   OnChartEventReceived(const int id, const long &lparam,
                            const double &dparam, const string &sparam);
double OnTesterEvent(void);
```

`OnTickEvent` runs the eight-stage pipeline. `OnTimerEvent` carries slow work — news
refresh, limit windows, log flushing — deliberately off the tick path.

`OnTradeTransactionEvent` is the **only** authoritative notification that a stop or target
was hit. Closed trades are recorded here, not by polling.

`OnTesterEvent` feeds the realised trade series to Monte Carlo, then returns the criterion's
fitness. MT5 calls it after the last tick but before `OnDeinit`, so the graph is still alive.

### Operator commands

```cpp
void Halt(const string reason);
void Resume(const string reason);
bool IsRunning(void) const;
int  EmergencyFlatten(const string reason);   // returns positions closed
```

`Halt` stops **new entries only**. Open positions remain managed, because abandoning live
risk is never the safe default.

`EmergencyFlatten` latches the emergency state *first*, then closes. Latching afterwards
would leave a window in which a tick could open a fresh position while closing the old.

### Access and diagnostics

```cpp
CTraderInterface   *Interface(void);      // borrowed, never delete
CTradeEngine       *Trade(void);
CRiskEngine        *Risk(void);
CDecisionEngine    *Decision(void);
COptimizationGuard *Environment(void);
CTesterIntegration *Tester(void);

void   GetConfig(SRuntimeConfig &out) const;
bool   IsBuilt(void) const;
string ValidationReport(void) const;
long   TickCount(void) const;
long   EntryCount(void) const;
string Describe(void) const;
```

Every accessor returns a **borrowed** pointer. Deleting one causes a double free at teardown.

---

## CRiskEngine

`Intelligence\Risk\CRiskEngine.mqh` — sizing, limits and protective levels.

```cpp
CRiskEngine(const string symbol, CAtrIntel *atr, ILogger *logger);

void SetSizer(CSizerBase *sizer);                    // TAKES ownership
void SetLimitGuard(CRiskLimitGuard *guard);          // TAKES ownership
void SetProtectionManager(CProtectionManager *p);    // TAKES ownership
void SetSwingDetector(CSwingDetector *swings);       // borrows
void SetMaxRiskPercentPerTrade(const double percent);
void SetMaxVolume(const double volume);

bool Initialize(const double equity, const datetime now);
void Shutdown(void);
bool Validate(SValidationResult &result);
```

The three ownership-taking setters are the source of a defect worth knowing about — see
`DEVELOPER.md`.

### The primary operation

```cpp
bool EvaluateEntry(const bool is_buy,
                   const double entry_price,
                   const double total_open_lots,
                   const double exposure_risk_percent,
                   SSizingResult   &sizing,
                   SProtectionPlan &plan,
                   SRiskVerdict    &verdict);
```

Five ordered steps, and the order is the design:

1. **Limits first** — no point sizing a barred trade, and a tripped guard costs nothing.
2. **Resolve the stop** — sizing depends on it.
3. **Size** against the resolved stop distance.
4. **Normalise** to broker rules, always downward.
5. **Re-verify** actual risk after normalisation, and cap if it exceeds the ceiling.

Step 5 is the one most EAs omit, and the reason a position sized for 1% can quietly risk
more.

Returns `false` with a populated `verdict` when refused. If `verdict.flatten_required` is
set, a guard is demanding a flatten and that outranks everything.

### The risk conversion

```cpp
double BrokerMoneyPerLot(const double stop_distance_points) const;
```

What one lot loses if the stop is hit, obtained from the terminal's `OrderCalcProfit`.
Returns `0.0` when unavailable, which tells the sizing context to fall back to tick
arithmetic.

Public specifically so a harness can assert it against `OrderCalcProfit`, and so the figure
can be shown to a user questioning a position size. Deriving this from
`SYMBOL_TRADE_TICK_VALUE` understates gold risk tenfold on some brokers.

### Other operations

```cpp
void UpdateAccountState(const double equity, const double floating,
                        const datetime now);
void RecordClosedTrade(const double net_profit, const datetime now);
bool EvaluateStopAdjustment(const bool is_buy, const double entry_price,
                            const double current_price, const double peak_price,
                            const double current_stop,
                            SStopAdjustment &adjustment);

void TriggerEmergencyShutdown(const string reason, const datetime now);
bool ClearEmergencyShutdown(const string acknowledgement);
bool IsEmergencyActive(void) const;
```

---

## CDecisionEngine

`Decision\CDecisionEngine.mqh` — resolves session, news, strategies and confirmation into
one decision.

```cpp
CDecisionEngine(const string symbol, const ENUM_TIMEFRAMES timeframe,
                ILogger *logger);

void SetCollaborators(CSessionManager *sessions, CNewsEngine *news,
                      CStrategyContext *context);              // borrows
bool AddPlugin(CStrategyPlugin *plugin);                       // TAKES ownership
void SetConfirmationEngine(CConfirmationEngine *engine);        // TAKES ownership

void SetVoteMode(const ENUM_SRP_VOTE_MODE mode);
void SetMinFinalConfidence(const double confidence);
void SetRequireConfirmation(const bool require);

bool Evaluate(const datetime now, const bool is_new_bar,
              STradeDecision &decision);
```

`Evaluate` returns `false` when it could not reach a conclusion. When it returns `true`,
check `decision.actionable` — a non-actionable decision carries a `decline_reason`
explaining which gate refused.

### Diagnostics

```cpp
int  PluginCount(void) const;
long EvaluationCount(void) const;
long ActionableCount(void) const;
long DeclinedCount(void) const;

long   DeclineCount(const ENUM_SRP_DECLINE_REASON reason) const;
string DescribeDeclines(void) const;
string Describe(void) const;
```

`DescribeDeclines` names every reason that fired, most frequent first:

```
declines by reason: NO_SIGNAL=98259 SESSION_BLOCKED=6424 LOW_CONFIDENCE=3948
```

This is the answer to "why did it not trade", which is the most common support question.
Without a per-reason tally the only honest answer is a guess.

---

## CTradeEngine

`Trade\Engine\CTradeEngine.mqh` — the only door to the broker. Implements
`ITradeExecutor` and adds a richer direct API.

```cpp
CTradeEngine(const STradeEngineConfig &config, IClock *clock,
             IEventPublisher *bus, ILogger *logger);
bool Initialize(void);
```

### ITradeExecutor (reports through `STradeResult`)

```cpp
bool OpenPosition(const STradeRequest &request, STradeResult &result);
bool ClosePosition(const ulong ticket, const ENUM_SRP_EXIT_REASON reason,
                   STradeResult &result);
bool ClosePartial(const ulong ticket, const double volume,
                  const ENUM_SRP_EXIT_REASON reason, STradeResult &result);
bool ModifyStops(const ulong ticket, const double stop_loss,
                 const double take_profit, STradeResult &result);
bool DeletePendingOrder(const ulong ticket, STradeResult &result);
```

### Direct API (reports through `SExecutionReport`)

```cpp
bool Buy (const double volume, const double stop_loss, const double take_profit,
          const string comment_detail, SExecutionReport &report);
bool Sell(const double volume, const double stop_loss, const double take_profit,
          const string comment_detail, SExecutionReport &report);

bool BuyLimit / SellLimit / BuyStop / SellStop(...);
bool ModifyOrder(const ulong ticket, const double price, const double sl,
                 const double tp, SExecutionReport &report);

bool ClosePositionEx(const ulong ticket, const string reason,
                     SExecutionReport &report);
bool ClosePartialEx(const ulong ticket, const double volume,
                    const string reason, SExecutionReport &report);
bool Reverse(const ulong ticket, const double new_volume,
             const double sl, const double tp,
             const string reason, SExecutionReport &report);

int  CloseAll(const string reason);
bool FlattenAll(const string reason, int &positions_closed, int &orders_deleted);
```

Note `Reverse` takes six arguments including both protective levels.

### Queries

```cpp
void   RefreshAll(void);
bool   IsHedging(void) const;
bool   IsNetting(void) const;
int    PositionCount(void) const;
double TotalVolume(void) const;
double NetVolume(void) const;
double FloatingProfit(void) const;
double SpreadPoints(void) const;
double AverageSlippagePoints(void);
string DescribeStatistics(void) const;
```

Foreign positions are never touched — magic **and** symbol are both filtered.

---

## Configuration

### CInputConfiguration

`Configuration\CInputConfiguration.mqh` — `IConfigProvider` over a keyed store.

```cpp
CInputConfiguration(ILogger *logger);

bool SetBool / SetInt / SetLong / SetDouble / SetString(key, value);
void Seal(void);
bool IsSealed(void) const;

bool   GetBool  (const string key, const bool   fallback) override;
int    GetInt   (const string key, const int    fallback) override;
long   GetLong  (const string key, const long   fallback) override;
double GetDouble(const string key, const double fallback) override;
string GetString(const string key, const string fallback) override;
bool   HasKey(const string key) override;

long   MissCount(void) const;
string FirstMissedKey(void) const;
```

After `Seal()` every write is refused and logged. That is what makes configuration
genuinely immutable at runtime.

`MissCount()` is a diagnostic: a non-zero count after a clean startup means some module is
asking for a key the builder never wrote, silently receiving the fallback.

### CConfigurationBuilder

```cpp
static bool Populate(CInputConfiguration *config, const SInputSnapshot &in);
static void ApplyNasdaqDefaults(SInputSnapshot &in);
```

`Populate` writes every key and seals. The only class permitted to know input names.

`ApplyNasdaqDefaults` fills the snapshot with the shipped preset, so the documented
defaults and the code cannot drift apart.

### CRuntimeConfig

```cpp
static bool   Load(IConfigProvider *config, const string symbol,
                   const ENUM_TIMEFRAMES timeframe, SRuntimeConfig &out);
static string Describe(const SRuntimeConfig &config);
```

Translates keys into the typed struct each constructor needs. A `NULL` provider is legal
and yields documented defaults — that is what makes every module constructible in a test.

---

## Optimization

### COptimizationCriterion

```cpp
COptimizationCriterion(ILogger *logger);

void SetCriterion(const ENUM_SRP_OPTIMIZATION_CRITERION criterion);
void SetMinimumTrades(const int trades);
void SetPenaltyWeights(const double drawdown, const double concentration,
                       const double streak);

double Evaluate(const SPerformanceMetrics &metrics,
                const STradeRecord &records[], const int count);
double RejectionValue(void) const;
string Explain(const SPerformanceMetrics &metrics);
static string CriterionToString(const ENUM_SRP_OPTIMIZATION_CRITERION c);
```

`Evaluate` returns `RejectionValue()` (a large negative) for passes below the minimum trade
count, so a fluke cannot top an optimisation table.

### CTesterIntegration

```cpp
CTesterIntegration(COptimizationCriterion *criterion, ILogger *logger);

void SetMonteCarlo(CMonteCarloSimulator *simulator);   // borrows
void SetExport(const bool enabled, const string folder,
               const string file="optimization_passes.csv");
void SetRunMonteCarlo(const bool enabled);

double Evaluate(void);              // call from OnTester
void   PublishPassReport(void);

bool IsTesting(void) const;
bool IsOptimizing(void) const;
bool IsVisualMode(void) const;
bool ShouldSuppressUi(void) const;
```

Reads the tester's own statistics rather than recomputing from deal history, so fitness
cannot disagree with the report the user is reading.

During an optimisation each agent writes its CSV into its own sandbox — see
`OPTIMIZATION.md`.

### CWalkForwardAnalyzer

```cpp
CWalkForwardAnalyzer(ILogger *logger);

void SetMinimumEfficiency(const double value);
void SetMinimumConsistency(const double value);
void SetMinimumOosTrades(const int trades);

int  PlanWindows(const datetime from, const datetime to,
                 const int is_days, const int oos_days,
                 const bool anchored=false);
void SetWindowResults(const int index, const double is_score,
                      const double oos_score, const double is_net,
                      const double oos_net, const int is_trades,
                      const int oos_trades, const double is_dd_percent,
                      const double oos_dd_percent);

bool   Analyze(SWalkForwardReport &report) const;
string FormatReport(void) const;
bool   ExportCsv(const string relative_path, const bool common_folder=false) const;
static string EfficiencyVerdict(const double efficiency);
```

Windows with too few out-of-sample trades are **excluded**, not averaged in: a
three-trade window tells you nothing and must not dilute the verdict.

### CMonteCarloSimulator

```cpp
CMonteCarloSimulator(ILogger *logger);

void SetStartingBalance(const double balance);
void SetRuns(const int runs);
void SetTradesPerRun(const int trades);
void SetWithReplacement(const bool value);
void SetRuinThreshold(const double percent);
void SetSeed(const int seed);            // fixed seed = reproducible

bool AddResult(const double net_profit);
int  LoadFromRecords(const STradeRecord &records[], const int count);

bool   Run(SMonteCarloReport &report);
string FormatReport(const SMonteCarloReport &report) const;
bool   ExportCsv(const string relative_path) const;
```

### CParameterSetValidator

```cpp
CParameterSetValidator(ILogger *logger);
bool IsWorthTesting(IConfigProvider *config, SValidationResult &result);
long AcceptedCount(void) const;
long RejectedCount(void) const;
```

Returning `false` from `OnInit` as `INIT_PARAMETERS_INCORRECT` makes the tester discard the
pass instead of simulating a combination that was incoherent from the start.

---

## Interfaces

Nineteen contracts in `Core\Interfaces\`. The ones you are most likely to implement:

| Interface | Purpose | Substitute to |
|---|---|---|
| `IClock` | all time reads | replay any historical moment |
| `ITradeExecutor` | order placement | run the pipeline with no broker |
| `IConfigProvider` | settings | test any configuration |
| `IStateStore` | persistence | test restart recovery |
| `ILogger` / `ILogSink` | logging | capture and assert log output |
| `INewsProvider` | economic events | test blackout behaviour |
| `IIndicator` | indicator values | feed synthetic series |

No module calls `TimeCurrent()` directly; they depend on `IClock`. That single rule is what
makes the session, schedule and news subsystems deterministically testable.

---

## Key structures

```cpp
SSizingResult      approved, volume, raw_volume, risk_amount, risk_percent,
                   stop_distance_points, model_used, explanation, rejection_reason

SProtectionPlan    has_stop, has_target, stop_price, target_price,
                   stop_distance_points, target_distance_points,
                   reward_risk_ratio, stop_model, target_model

SRiskVerdict       entries_allowed, flatten_required, breach, detail,
                   measured, limit

STradeDecision     actionable, decision, decline_reason, explanation,
                   risk_rating, signal, session, news

SExecutionReport   success, order_ticket, deal_ticket, position_ticket,
                   requested_price, executed_price, requested_volume,
                   executed_volume, slippage_points, retcode, retcode_text,
                   attempts, latency_ms, total_elapsed_ms, was_retried,
                   partial_fill, excess_slippage, operation, failure_detail

SClosedTrade       ticket, symbol, is_buy, volume, open_price, close_price,
                   open_time, close_time, duration_seconds, gross_profit,
                   commission, swap, net_profit, risk_amount, r_multiple,
                   balance_after, strategy_name, exit_reason
```

Two field-name traps worth flagging, both of which caused real defects:

- `SExecutionReport` has `total_elapsed_ms` and `position_ticket` — not `elapsed_ms` or
  `ticket`.
- `SPerformanceMetrics.max_consecutive_wins` / `max_consecutive_losses` are **counts**,
  from `STAT_MAX_CONPROFIT_TRADES` / `STAT_MAX_CONLOSS_TRADES`. MQL5's `STAT_MAX_CONWINS`
  is the *money* of the longest streak. Using it exported a 56-trade pass as having 360
  consecutive wins.
