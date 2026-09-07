//+------------------------------------------------------------------+
//|                                       CDashboardViewModel.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard : the read-only snapshot the UI renders from.                  |
//|                                                                  |
//|   RESPONSIBILITY (one only): hold a copy of everything the widgets need.   |
//|                                                                  |
//|   THIS CLASS IS THE UI FIREWALL                                          |
//|   Widgets receive a CONST reference to this object and nothing else. They  |
//|   therefore CANNOT reach the engine, the executor or a position - the      |
//|   dashboard is structurally incapable of affecting trading. That is a      |
//|   safety property, not a style preference: a UI bug can garble a label     |
//|   but can never move a stop loss.                                        |
//|                                                                  |
//|   It also decouples refresh rates. The pipeline updates this model at      |
//|   its own pace; the dashboard reads it on a throttle. Neither waits for    |
//|   the other, so chart rendering can never slow down execution.            |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_CDASHBOARDVIEWMODEL_MQH
#define SRP_DASHBOARD_CDASHBOARDVIEWMODEL_MQH

#include "../Core/Types/Structs.mqh"

class CDashboardViewModel
  {
private:
   //--- Copies, never pointers. A pointer would reintroduce the coupling
   //--- this class exists to prevent.
   SMarketSnapshot     m_market;
   SAccountSnapshot    m_account;
   SPortfolioExposure  m_exposure;
   SNewsBlackoutState  m_news;
   SDailyStatistics    m_daily;
   SPerformanceMetrics m_metrics;
   SSignal             m_last_signal;
   SFilterChainResult  m_filter_result;
   SRiskDecision       m_last_risk_decision;
   SPositionSnapshot   m_positions[];
   SFilterVerdict      m_verdicts[];
   double              m_equity_samples[];

   ENUM_SRP_ENGINE_STATE  m_engine_state;
   ENUM_SRP_HEALTH_STATUS m_health;
   string              m_health_detail;
   string              m_state_reason;
   string              m_symbol;
   string              m_product_version;
   datetime            m_updated_at;
   bool                m_kill_switch_active;
   string              m_guard_veto_detail;
   double              m_average_slippage_points;
   double              m_average_latency_ms;

public:
                     CDashboardViewModel(void);
                    ~CDashboardViewModel(void);

   //--- Writers, called only by CDashboardManager during its refresh.
   void              SetMarket(const SMarketSnapshot &value);
   void              SetAccount(const SAccountSnapshot &value);
   void              SetExposure(const SPortfolioExposure &value);
   void              SetNews(const SNewsBlackoutState &value);
   void              SetDaily(const SDailyStatistics &value);
   void              SetMetrics(const SPerformanceMetrics &value);
   void              SetLastSignal(const SSignal &value);
   void              SetFilterResult(const SFilterChainResult &value);
   void              SetRiskDecision(const SRiskDecision &value);
   void              SetEngineState(const ENUM_SRP_ENGINE_STATE state,
                                    const string reason);
   void              SetHealth(const ENUM_SRP_HEALTH_STATUS status,
                               const string detail);
   void              SetExecutionQuality(const double slippage_points,
                                         const double latency_ms);
   void              SetKillSwitch(const bool active,const string detail);
   void              SetIdentity(const string symbol,const string version);
   void              SetUpdatedAt(const datetime moment);

   bool              SetPositions(const SPositionSnapshot &values[],const int count);
   bool              SetVerdicts(const SFilterVerdict &values[],const int count);
   bool              SetEquitySamples(const double &values[],const int count);

   //--- Readers, used by widgets. All const.
   void              GetMarket(SMarketSnapshot &out) const     { out=m_market; }
   void              GetAccount(SAccountSnapshot &out) const   { out=m_account; }
   void              GetExposure(SPortfolioExposure &out) const{ out=m_exposure; }
   void              GetNews(SNewsBlackoutState &out) const    { out=m_news; }
   void              GetDaily(SDailyStatistics &out) const     { out=m_daily; }
   void              GetMetrics(SPerformanceMetrics &out) const{ out=m_metrics; }
   void              GetLastSignal(SSignal &out) const         { out=m_last_signal; }
   void              GetFilterResult(SFilterChainResult &out) const { out=m_filter_result; }
   void              GetRiskDecision(SRiskDecision &out) const { out=m_last_risk_decision; }

   int               PositionCount(void) const { return(ArraySize(m_positions)); }
   bool              GetPosition(const int index,SPositionSnapshot &out) const;
   int               VerdictCount(void) const { return(ArraySize(m_verdicts)); }
   bool              GetVerdict(const int index,SFilterVerdict &out) const;
   int               EquitySampleCount(void) const { return(ArraySize(m_equity_samples)); }
   bool              GetEquitySample(const int index,double &out) const;

   ENUM_SRP_ENGINE_STATE  EngineState(void) const { return(m_engine_state); }
   ENUM_SRP_HEALTH_STATUS Health(void)      const { return(m_health); }
   string            HealthDetail(void)     const { return(m_health_detail); }
   string            StateReason(void)      const { return(m_state_reason); }
   string            Symbol(void)           const { return(m_symbol); }
   string            ProductVersion(void)   const { return(m_product_version); }
   datetime          UpdatedAt(void)        const { return(m_updated_at); }
   bool              IsKillSwitchActive(void) const { return(m_kill_switch_active); }
   string            GuardVetoDetail(void)  const { return(m_guard_veto_detail); }
   double            AverageSlippagePoints(void) const { return(m_average_slippage_points); }
   double            AverageLatencyMs(void) const { return(m_average_latency_ms); }
  };

#endif // SRP_DASHBOARD_CDASHBOARDVIEWMODEL_MQH
//+------------------------------------------------------------------+
