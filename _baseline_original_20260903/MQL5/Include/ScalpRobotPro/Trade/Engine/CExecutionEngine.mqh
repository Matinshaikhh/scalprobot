//+------------------------------------------------------------------+
//|                                            CExecutionEngine.mqh |
//|                          Scalping Robot Pro - Core Trading Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): send a prepared MqlTradeRequest to the  |
//|   server, retry when the failure is transient, and measure what      |
//|   happened. It decides nothing about trading.                       |
//|                                                                  |
//|   THIS IS THE ONLY PLACE OrderSend IS CALLED IN THE ENTIRE PRODUCT. |
//|   Every other class routes through it, which is what makes the whole |
//|   system testable and what makes execution telemetry impossible to   |
//|   bypass.                                                          |
//|                                                                  |
//|   WHAT IT ADDS OVER A RAW OrderSend                                |
//|     * classified retry: a requote or price-off is retried with a     |
//|       refreshed price; invalid stops or no-money never are, because  |
//|       retrying a deterministic rejection just wastes time            |
//|     * IDEMPOTENCE: before every retry it re-checks whether the       |
//|       previous attempt actually succeeded. A lost reply must never   |
//|       become a second position - the most expensive bug class in     |
//|       automated execution                                           |
//|     * slippage measurement against the intended price                |
//|     * latency measurement in milliseconds                           |
//|     * OrderCheck pre-flight, so predictable rejections never reach   |
//|       the server at all                                             |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_ENGINE_CEXECUTIONENGINE_MQH
#define SRP_TRADE_ENGINE_CEXECUTIONENGINE_MQH

#include "../../Core/Interfaces/IModule.mqh"
#include "../../Core/Interfaces/IClock.mqh"
#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Core/Base/CModuleIdentity.mqh"
#include "../../Core/CErrorHandler.mqh"   // static RetcodeToText decoding
#include "../../Utilities/CMathUtils.mqh"
#include "CBrokerManager.mqh"
#include "CMagicNumberManager.mqh"

//+------------------------------------------------------------------+
//| Rich outcome of one execution attempt sequence.                    |
//+------------------------------------------------------------------+
struct SExecutionReport
  {
   bool              success;
   ulong             order_ticket;
   ulong             deal_ticket;
   ulong             position_ticket;
   double            requested_price;
   double            executed_price;
   double            requested_volume;
   double            executed_volume;
   double            slippage_points;
   uint              retcode;
   string            retcode_text;
   int               attempts;
   ulong             latency_ms;
   ulong             total_elapsed_ms;
   bool              was_retried;
   bool              partial_fill;
   //--- True when the fill succeeded but slippage exceeded the limit.
   //--- Kept separate from 'success' so an executed trade is never
   //--- misreported as a failure.
   bool              excess_slippage;
   string            operation;
   string            failure_detail;

                     SExecutionReport(void) { Reset(); }
   void              Reset(void)
     {
      success=false;
      order_ticket=SRP_INVALID_TICKET;
      deal_ticket=SRP_INVALID_TICKET;
      position_ticket=SRP_INVALID_TICKET;
      requested_price=0.0; executed_price=0.0;
      requested_volume=0.0; executed_volume=0.0;
      slippage_points=0.0;
      retcode=0; retcode_text="";
      attempts=0; latency_ms=0; total_elapsed_ms=0;
      was_retried=false; partial_fill=false; excess_slippage=false;
      operation=""; failure_detail="";
     }
  };

//+------------------------------------------------------------------+
//| Aggregate execution-quality telemetry.                             |
//+------------------------------------------------------------------+
struct SExecutionStatistics
  {
   long              total_sends;
   long              successes;
   long              failures;
   long              retries;
   long              partial_fills;
   long              idempotence_saves;   // duplicate sends prevented
   double            slippage_sum_points;
   double            slippage_worst_points;
   long              slippage_samples;
   double            latency_sum_ms;
   ulong             latency_worst_ms;
   long              latency_samples;
   uint              last_retcode;
   datetime          last_failure_time;

                     SExecutionStatistics(void) { Reset(); }
   void              Reset(void)
     {
      total_sends=0; successes=0; failures=0; retries=0;
      partial_fills=0; idempotence_saves=0;
      slippage_sum_points=0.0; slippage_worst_points=0.0; slippage_samples=0;
      latency_sum_ms=0.0; latency_worst_ms=0; latency_samples=0;
      last_retcode=0; last_failure_time=0;
     }
   double            AverageSlippage(void) const
     {
      return(slippage_samples>0 ? slippage_sum_points/(double)slippage_samples : 0.0);
     }
   double            AverageLatency(void) const
     {
      return(latency_samples>0 ? latency_sum_ms/(double)latency_samples : 0.0);
     }
   double            SuccessRate(void) const
     {
      return(total_sends>0 ? (double)successes/(double)total_sends*100.0 : 0.0);
     }
  };

class CExecutionEngine : public IModule
  {
private:
   CModuleIdentity      m_id;
   CBrokerManager      *m_broker;          // borrowed
   CMagicNumberManager *m_magic;           // borrowed
   IClock              *m_clock;           // borrowed

   //--- Retry policy.
   int                  m_max_attempts;
   int                  m_backoff_ms;
   bool                 m_backoff_progressive;
   //--- Slippage policy.
   int                  m_deviation_points;
   double               m_max_slippage_points;   // 0 == no post-check
   bool                 m_reject_on_excess_slippage;
   //--- Pre-flight.
   bool                 m_use_order_check;
   bool                 m_log_execution_speed;

   SExecutionStatistics m_stats;
   SExecutionReport     m_last_report;

   //--- Retry decision. Kept private and explicit: this table is the
   //--- difference between resilient execution and an order storm.
   bool              IsRetryable(const uint retcode) const;
   //--- Refreshes market price on a market order between attempts. A
   //--- stale price guarantees a second requote.
   bool              RefreshPrice(MqlTradeRequest &request) const;
   //--- Idempotence guard: did the previous attempt actually land?
   bool              DetectPriorSuccess(const MqlTradeRequest &request,
                                        const datetime attempt_start,
                                        SExecutionReport &report);
   void              ApplyBackoff(const int attempt) const;
   //--- Resolves the POSITION a successful deal belongs to.
   //---
   //--- MqlTradeResult carries an order and a deal but no position id, so
   //--- anything that needs to address the resulting position by ticket has
   //--- to look it up. Without this the report's position_ticket stayed at
   //--- its sentinel on the ordinary success path, and only the
   //--- idempotence-recovery path ever filled it in.
   ulong             ResolvePositionTicket(const MqlTradeRequest &request,
                                           const MqlTradeResult &result) const;
   void              RecordSuccess(const MqlTradeRequest &request,
                                   const MqlTradeResult &result,
                                   SExecutionReport &report);
   void              RecordFailure(const MqlTradeResult &result,
                                   SExecutionReport &report);
   double            ComputeSlippage(const MqlTradeRequest &request,
                                     const double executed_price) const;
   void              LogReport(const SExecutionReport &report) const;

public:
                     CExecutionEngine(CBrokerManager *broker,
                                      CMagicNumberManager *magic,
                                      IClock *clock,
                                      ILogger *logger);
                    ~CExecutionEngine(void) { }

   //--- Configuration ------------------------------------------------
   void              SetRetryPolicy(const int max_attempts,
                                    const int backoff_ms,
                                    const bool progressive=true);
   void              SetDeviationPoints(const int points);
   void              SetMaxSlippagePoints(const double points,
                                          const bool reject_on_excess=false);
   void              SetUseOrderCheck(const bool value);
   void              SetLogExecutionSpeed(const bool value);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- THE single send path. Everything funnels through here.
   bool              Send(MqlTradeRequest &request,
                          const string operation,
                          SExecutionReport &report);

   //--- OrderCheck pre-flight, exposed for callers that want to probe
   //--- without sending.
   bool              PreCheck(const MqlTradeRequest &request,
                              string &failure_detail) const;

   //--- Fills the fields every request needs, so no caller forgets one.
   void              PrepareCommonFields(MqlTradeRequest &request,
                                         const string comment_detail) const;

   //--- Telemetry ----------------------------------------------------
   void              GetStatistics(SExecutionStatistics &out) const { out=m_stats; }
   void              GetLastReport(SExecutionReport &out) const { out=m_last_report; }
   double            AverageSlippagePoints(void) const { return(m_stats.AverageSlippage()); }
   double            AverageLatencyMs(void) const { return(m_stats.AverageLatency()); }
   long              FailureCount(void) const { return(m_stats.failures); }
   void              ResetStatistics(void) { m_stats.Reset(); }
   string            DescribeStatistics(void) const;
  };

//+------------------------------------------------------------------+
CExecutionEngine::CExecutionEngine(CBrokerManager *broker,
                                   CMagicNumberManager *magic,
                                   IClock *clock,
                                   ILogger *logger)
  : m_broker(broker),
    m_magic(magic),
    m_clock(clock),
    m_max_attempts(SRP_MAX_EXECUTION_RETRIES),
    m_backoff_ms(SRP_RETRY_BACKOFF_MS),
    m_backoff_progressive(true),
    m_deviation_points(SRP_DEFAULT_DEVIATION_POINTS),
    m_max_slippage_points(0.0),
    m_reject_on_excess_slippage(false),
    m_use_order_check(true),
    m_log_execution_speed(true)
  {
   m_id.Configure("CExecutionEngine",logger);
  }
//+------------------------------------------------------------------+
void CExecutionEngine::SetRetryPolicy(const int max_attempts,
                                      const int backoff_ms,
                                      const bool progressive)
  {
   //--- At least one attempt, or nothing would ever be sent.
   m_max_attempts=(max_attempts<1 ? 1 : max_attempts);
   m_backoff_ms=(backoff_ms<0 ? 0 : backoff_ms);
   m_backoff_progressive=progressive;
  }
//+------------------------------------------------------------------+
void CExecutionEngine::SetDeviationPoints(const int points)
  {
   if(points>=0)
      m_deviation_points=points;
  }
//+------------------------------------------------------------------+
void CExecutionEngine::SetMaxSlippagePoints(const double points,
                                            const bool reject_on_excess)
  {
   m_max_slippage_points=(points<0.0 ? 0.0 : points);
   m_reject_on_excess_slippage=reject_on_excess;
  }
//+------------------------------------------------------------------+
void CExecutionEngine::SetUseOrderCheck(const bool value)
  {
   m_use_order_check=value;
  }
//+------------------------------------------------------------------+
void CExecutionEngine::SetLogExecutionSpeed(const bool value)
  {
   m_log_execution_speed=value;
  }
//+------------------------------------------------------------------+
bool CExecutionEngine::Initialize(void)
  {
   if(m_id.IsInitialized())
      return(true);
   if(m_broker==NULL || m_magic==NULL || m_clock==NULL)
     {
      m_id.Error("missing collaborator (broker/magic/clock)");
      m_id.SetHealth(SRP_HEALTH_CRITICAL,"wiring incomplete");
      return(false);
     }
   if(!m_magic.IsConfigured())
     {
      m_id.Error("magic number not configured");
      m_id.SetHealth(SRP_HEALTH_CRITICAL,"magic unset");
      return(false);
     }
   m_stats.Reset();
   m_id.SetInitialized(true);
   m_id.SetHealth(SRP_HEALTH_OK,"");
   return(true);
  }
//+------------------------------------------------------------------+
void CExecutionEngine::Validate(SValidationResult &result)
  {
   if(m_broker==NULL) result.AddError("CExecutionEngine: broker manager not injected");
   if(m_magic==NULL)  result.AddError("CExecutionEngine: magic manager not injected");
   if(m_clock==NULL)  result.AddError("CExecutionEngine: clock not injected");
   if(m_max_attempts>10)
      result.AddWarning("CExecutionEngine: more than 10 attempts risks an order storm");
   if(m_deviation_points==0 && m_broker!=NULL && m_broker.IsMarketExecution())
      result.AddWarning("CExecutionEngine: zero deviation on market execution invites requotes");
  }
//+------------------------------------------------------------------+
void CExecutionEngine::Shutdown(void)
  {
   if(m_stats.total_sends>0)
      m_id.Info(DescribeStatistics());
   m_id.SetInitialized(false);
  }
//+------------------------------------------------------------------+
void CExecutionEngine::ReportHealth(SHealthReport &report)
  {
   //--- Sustained rejections indicate a broker or configuration problem
   //--- the operator must see, so it is surfaced as degraded health.
   if(m_stats.total_sends>=10 && m_stats.SuccessRate()<50.0)
      m_id.SetHealth(SRP_HEALTH_CRITICAL,
                     StringFormat("success rate %.0f%%",m_stats.SuccessRate()));
   else if(m_stats.total_sends>=10 && m_stats.SuccessRate()<85.0)
      m_id.SetHealth(SRP_HEALTH_DEGRADED,
                     StringFormat("success rate %.0f%%",m_stats.SuccessRate()));
   else
      m_id.SetHealth(SRP_HEALTH_OK,"");
   m_id.FillReport(report,m_stats.last_failure_time);
  }
//+------------------------------------------------------------------+
void CExecutionEngine::PrepareCommonFields(MqlTradeRequest &request,
                                           const string comment_detail) const
  {
   request.symbol    = m_broker.Symbol();
   request.magic     = m_magic.EngineMagic();
   request.deviation = (ulong)m_deviation_points;
   request.comment   = m_magic.BuildComment(comment_detail);
   request.type_filling = m_broker.FillingMode();
  }
//+------------------------------------------------------------------+
bool CExecutionEngine::IsRetryable(const uint retcode) const
  {
   //--- EXPLICIT policy table. Only transient, price-related conditions
   //--- are retried. Everything else is deterministic: retrying it
   //--- cannot succeed and only delays the caller's error handling.
   switch(retcode)
     {
      //--- Transient: worth another attempt with a refreshed price.
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
      case TRADE_RETCODE_LOCKED:
      case TRADE_RETCODE_ERROR:              // generic processing error
         return(true);

      //--- Deterministic: retrying changes nothing.
      case TRADE_RETCODE_INVALID_STOPS:      // fix the stops instead
      case TRADE_RETCODE_INVALID_VOLUME:     // fix the volume instead
      case TRADE_RETCODE_INVALID_PRICE:
      case TRADE_RETCODE_NO_MONEY:           // margin will not appear
      case TRADE_RETCODE_TRADE_DISABLED:
      case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_INVALID_FILL:       // resolve filling mode
      case TRADE_RETCODE_INVALID_EXPIRATION:
      case TRADE_RETCODE_POSITION_CLOSED:    // already gone
      case TRADE_RETCODE_LIMIT_POSITIONS:
      case TRADE_RETCODE_LIMIT_ORDERS:
      case TRADE_RETCODE_ORDER_CHANGED:
      case TRADE_RETCODE_LONG_ONLY:
      case TRADE_RETCODE_SHORT_ONLY:
      case TRADE_RETCODE_CLOSE_ONLY:
      case TRADE_RETCODE_FIFO_CLOSE:
      case TRADE_RETCODE_HEDGE_PROHIBITED:
      case TRADE_RETCODE_REJECT:
      case TRADE_RETCODE_CANCEL:
         return(false);
     }
   return(false);
  }
//+------------------------------------------------------------------+
bool CExecutionEngine::RefreshPrice(MqlTradeRequest &request) const
  {
   //--- Only market operations carry a live price worth refreshing;
   //--- pending orders keep the price the caller chose.
   if(request.action!=TRADE_ACTION_DEAL)
      return(true);

   MqlTick tick;
   if(!m_broker.GetTick(tick))
      return(false);
   if(tick.bid<=0.0 || tick.ask<=0.0)
      return(false);

   if(request.type==ORDER_TYPE_BUY)
      request.price=m_broker.NormalizePrice(tick.ask);
   else if(request.type==ORDER_TYPE_SELL)
      request.price=m_broker.NormalizePrice(tick.bid);
   return(true);
  }
//+------------------------------------------------------------------+
void CExecutionEngine::ApplyBackoff(const int attempt) const
  {
   if(m_backoff_ms<=0)
      return;
   //--- Progressive backoff eases pressure when the server is busy or
   //--- rate-limiting; a fixed tight loop can trigger TOO_MANY_REQUESTS.
   const int delay=(m_backoff_progressive ? m_backoff_ms*attempt : m_backoff_ms);
   Sleep(delay);
  }
//+------------------------------------------------------------------+
bool CExecutionEngine::DetectPriorSuccess(const MqlTradeRequest &request,
                                          const datetime attempt_start,
                                          SExecutionReport &report)
  {
   //--- IDEMPOTENCE GUARD.
   //--- A timeout or dropped connection means the outcome is UNKNOWN,
   //--- not failed. The order may well have executed. Blindly retrying
   //--- would open a second position - so before retrying an entry we
   //--- search recent history for a deal matching this request.
   if(request.action!=TRADE_ACTION_DEAL)
      return(false);
   //--- Only entries are at risk of harmful duplication; a duplicate
   //--- close attempt is refused harmlessly by the server.
   if(request.position!=0)
      return(false);

   //--- Look back a little further than the attempt to tolerate clock
   //--- and server-time skew.
   const datetime from=attempt_start-60;
   if(!HistorySelect(from,TimeCurrent()+1))
      return(false);

   const int deals=HistoryDealsTotal();
   for(int i=deals-1;i>=0;i--)
     {
      const ulong deal=HistoryDealGetTicket(i);
      if(deal==0)
         continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=request.symbol)
         continue;
      if((long)HistoryDealGetInteger(deal,DEAL_MAGIC)!=(long)request.magic)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN)
         continue;
      const datetime deal_time=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      if(deal_time<from)
         continue;

      //--- Direction must match the request.
      const ENUM_DEAL_TYPE deal_type=
         (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      const bool request_is_buy=(request.type==ORDER_TYPE_BUY);
      const bool deal_is_buy=(deal_type==DEAL_TYPE_BUY);
      if(request_is_buy!=deal_is_buy)
         continue;

      //--- Volume must match within one step.
      const double deal_volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
      if(MathAbs(deal_volume-request.volume)>m_broker.VolumeStep()*0.5)
         continue;

      //--- A matching entry deal exists: the previous attempt landed.
      report.success         = true;
      report.deal_ticket     = deal;
      report.position_ticket = (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      report.order_ticket    = (ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
      report.executed_price  = HistoryDealGetDouble(deal,DEAL_PRICE);
      report.executed_volume = deal_volume;
      report.slippage_points = ComputeSlippage(request,report.executed_price);
      report.retcode         = TRADE_RETCODE_DONE;
      report.retcode_text    = "recovered: prior attempt succeeded";

      m_stats.idempotence_saves++;
      m_id.Warn(StringFormat(
                "idempotence guard: prior attempt had executed (deal #%I64u, "
                "position #%I64u) - duplicate send prevented",
                deal,report.position_ticket));
      return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
double CExecutionEngine::ComputeSlippage(const MqlTradeRequest &request,
                                         const double executed_price) const
  {
   if(request.price<=0.0 || executed_price<=0.0)
      return(0.0);
   const double delta=executed_price-request.price;
   //--- Signed so that POSITIVE always means adverse, regardless of side:
   //--- a buy filled above request, or a sell filled below it.
   const double adverse=(request.type==ORDER_TYPE_BUY ? delta : -delta);
   return(m_broker.PriceToPoints(adverse));
  }
//+------------------------------------------------------------------+
bool CExecutionEngine::PreCheck(const MqlTradeRequest &request,
                                string &failure_detail) const
  {
   failure_detail="";
   if(!m_use_order_check)
      return(true);

   MqlTradeCheckResult check;
   ZeroMemory(check);
   MqlTradeRequest local=request;

   //--- OrderCheck validates the request against the server's rules
   //--- without sending it. Catching a predictable rejection here saves
   //--- a network round trip and keeps the rejection counter honest.
   if(!OrderCheck(local,check))
     {
      failure_detail=StringFormat("OrderCheck failed: retcode=%u %s",
                                  check.retcode,check.comment);
      //--- DONE and PLACED mean the request is acceptable; OrderCheck
      //--- returns false for those on some builds, so they are treated
      //--- as success rather than failure.
      if(check.retcode==TRADE_RETCODE_DONE ||
         check.retcode==TRADE_RETCODE_PLACED)
        {
         failure_detail="";
         return(true);
        }
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
//| Which position did this deal produce or affect?                     |
//|                                                                  |
//| Three sources, cheapest first:                                        |
//|                                                                  |
//|   1. request.position - set when the caller already addressed a         |
//|      specific position (a close, a partial close, a reversal leg).     |
//|   2. The deal's own DEAL_POSITION_ID - authoritative for an entry, and  |
//|      correct under both netting and hedging: under netting several      |
//|      deals share one position id, which is exactly what a caller       |
//|      tracking that position needs.                                     |
//|   3. The order's ORDER_POSITION_ID - a fallback for the case where the  |
//|      deal has not yet appeared in history.                             |
//|                                                                  |
//| Returns the sentinel when none resolve, so a caller can tell "unknown"  |
//| from "position zero" rather than silently addressing nothing.           |
//+------------------------------------------------------------------+
ulong CExecutionEngine::ResolvePositionTicket(const MqlTradeRequest &request,
                                             const MqlTradeResult &result) const
  {
   if(request.position!=0)
      return(request.position);

   if(result.deal!=0)
     {
      //--- A deal ticket can be selected directly, but only once it is in
      //--- the terminal's history cache. Immediately after a fill it may
      //--- not be, so the window is requested explicitly on the retry.
      bool selected=HistoryDealSelect(result.deal);
      if(!selected)
        {
         HistorySelect(TimeCurrent()-300,TimeCurrent()+1);
         selected=HistoryDealSelect(result.deal);
        }
      if(selected)
        {
         const ulong id=(ulong)HistoryDealGetInteger(result.deal,
                                                     DEAL_POSITION_ID);
         if(id!=0)
            return(id);
        }
     }

   if(result.order!=0)
     {
      bool order_selected=HistoryOrderSelect(result.order);
      if(!order_selected)
        {
         HistorySelect(TimeCurrent()-300,TimeCurrent()+1);
         order_selected=HistoryOrderSelect(result.order);
        }
      if(order_selected)
        {
         const ulong id=(ulong)HistoryOrderGetInteger(result.order,
                                                      ORDER_POSITION_ID);
         if(id!=0)
            return(id);
        }
      //--- A still-working order (a pending placement) has no position
      //--- yet; its own ticket becomes the position id once it triggers.
      if(OrderSelect(result.order))
        {
         const ulong id=(ulong)OrderGetInteger(ORDER_POSITION_ID);
         if(id!=0)
            return(id);
        }
     }
   return(SRP_INVALID_TICKET);
  }
//+------------------------------------------------------------------+
void CExecutionEngine::RecordSuccess(const MqlTradeRequest &request,
                                     const MqlTradeResult &result,
                                     SExecutionReport &report)
  {
   report.success         = true;
   report.order_ticket    = result.order;
   report.deal_ticket     = result.deal;
   report.position_ticket = ResolvePositionTicket(request,result);
   report.retcode         = result.retcode;
   report.retcode_text    = CErrorHandler::RetcodeToText(result.retcode);
   report.executed_volume = (result.volume>0.0 ? result.volume : request.volume);
   report.executed_price  = (result.price>0.0 ? result.price : request.price);

   //--- Partial fill detection: IOC can legitimately fill less than
   //--- requested, and the caller must know so its exposure model stays
   //--- accurate.
   if(request.volume>0.0 &&
      report.executed_volume < request.volume-m_broker.VolumeStep()*0.5)
     {
      report.partial_fill=true;
      m_stats.partial_fills++;
      m_id.Warn(StringFormat("partial fill: requested %.4f, filled %.4f",
                             request.volume,report.executed_volume));
     }

   //--- Slippage, measured only for market operations where a fill
   //--- price is meaningful.
   if(request.action==TRADE_ACTION_DEAL && report.executed_price>0.0)
     {
      report.slippage_points=ComputeSlippage(request,report.executed_price);
      m_stats.slippage_sum_points+=report.slippage_points;
      m_stats.slippage_samples++;
      if(report.slippage_points>m_stats.slippage_worst_points)
         m_stats.slippage_worst_points=report.slippage_points;

      //--- Slippage protection, post-fill. MQL5's deviation field is the
      //--- primary control, but brokers do not always honour it, so
      //--- excess is detected and reported here regardless.
      if(m_max_slippage_points>0.0 &&
         report.slippage_points>m_max_slippage_points)
        {
         m_id.Warn(StringFormat(
                   "adverse slippage %.1f points exceeds limit %.1f on %s",
                   report.slippage_points,m_max_slippage_points,report.operation));
         if(m_reject_on_excess_slippage)
           {
            //--- FLAGGED, NOT REVERSED. The fill happened and the
            //--- position exists; silently closing it here would hide
            //--- the event from the caller, who owns that decision.
            //--- 'success' therefore stays true - the send DID succeed -
            //--- and the excess is reported through a dedicated flag so
            //--- the caller can react without misreading the outcome.
            report.excess_slippage=true;
           }
        }
     }

   m_stats.successes++;
  }
//+------------------------------------------------------------------+
void CExecutionEngine::RecordFailure(const MqlTradeResult &result,
                                     SExecutionReport &report)
  {
   report.success      = false;
   report.retcode      = result.retcode;
   report.retcode_text = CErrorHandler::RetcodeToText(result.retcode);
   if(StringLen(report.failure_detail)==0)
      report.failure_detail=report.retcode_text;
   m_stats.failures++;
   m_stats.last_retcode=result.retcode;
   m_stats.last_failure_time=(m_clock!=NULL ? m_clock.ServerTime() : TimeCurrent());
  }
//+------------------------------------------------------------------+
bool CExecutionEngine::Send(MqlTradeRequest &request,
                            const string operation,
                            SExecutionReport &report)
  {
   report.Reset();
   report.operation        = operation;
   report.requested_price  = request.price;
   report.requested_volume = request.volume;

   if(!m_id.IsInitialized())
     {
      report.failure_detail="execution engine not initialised";
      m_id.Error(report.failure_detail);
      return(false);
     }

   const ulong sequence_start=(m_clock!=NULL ? m_clock.TickCountMs() : GetTickCount64());
   MqlTradeResult result;

   for(int attempt=1;attempt<=m_max_attempts;attempt++)
     {
      report.attempts=attempt;
      ZeroMemory(result);

      //--- Pre-flight on the first attempt only: after a retry the
      //--- request has already been validated and prices have moved.
      if(attempt==1)
        {
         string precheck_detail="";
         if(!PreCheck(request,precheck_detail))
           {
            report.failure_detail=precheck_detail;
            report.retcode_text=precheck_detail;
            m_stats.total_sends++;
            m_stats.failures++;
            m_id.Warn(operation+" rejected pre-flight: "+precheck_detail);
            m_last_report=report;
            return(false);
           }
        }

      const datetime attempt_start=(m_clock!=NULL ? m_clock.ServerTime() : TimeCurrent());
      const ulong send_start=(m_clock!=NULL ? m_clock.TickCountMs() : GetTickCount64());

      const bool sent=OrderSend(request,result);

      const ulong send_end=(m_clock!=NULL ? m_clock.TickCountMs() : GetTickCount64());
      report.latency_ms=send_end-send_start;

      m_stats.total_sends++;
      m_stats.latency_sum_ms+=(double)report.latency_ms;
      m_stats.latency_samples++;
      if(report.latency_ms>m_stats.latency_worst_ms)
         m_stats.latency_worst_ms=report.latency_ms;

      //--- Success is defined by retcode, not by OrderSend's return
      //--- value. OrderSend can return false while the server still
      //--- accepted the request.
      const bool accepted=(result.retcode==TRADE_RETCODE_DONE ||
                           result.retcode==TRADE_RETCODE_PLACED ||
                           result.retcode==TRADE_RETCODE_DONE_PARTIAL);

      if(accepted)
        {
         RecordSuccess(request,result,report);
         report.total_elapsed_ms=send_end-sequence_start;
         LogReport(report);
         m_last_report=report;
         return(true);
        }

      //--- Not accepted. Decide whether another attempt is justified.
      const bool can_retry=IsRetryable(result.retcode) && attempt<m_max_attempts;
      if(!can_retry)
        {
         RecordFailure(result,report);
         report.total_elapsed_ms=send_end-sequence_start;
         LogReport(report);
         m_last_report=report;
         return(false);
        }

      //--- Retrying. First confirm the previous attempt did not
      //--- actually succeed, which timeouts and dropped connections
      //--- make genuinely possible.
      const bool outcome_unknown=(result.retcode==TRADE_RETCODE_TIMEOUT ||
                                  result.retcode==TRADE_RETCODE_CONNECTION ||
                                  !sent);
      if(outcome_unknown && DetectPriorSuccess(request,attempt_start,report))
        {
         m_stats.successes++;
         report.total_elapsed_ms=
            (m_clock!=NULL ? m_clock.TickCountMs() : GetTickCount64())-sequence_start;
         LogReport(report);
         m_last_report=report;
         return(true);
        }

      m_stats.retries++;
      report.was_retried=true;
      m_id.Debug(StringFormat("%s attempt %d/%d failed (%u %s), retrying",
                              operation,attempt,m_max_attempts,
                              result.retcode,
                              CErrorHandler::RetcodeToText(result.retcode)));

      ApplyBackoff(attempt);
      if(!RefreshPrice(request))
        {
         report.failure_detail="price refresh failed before retry";
         RecordFailure(result,report);
         LogReport(report);
         m_last_report=report;
         return(false);
        }
     }

   //--- Loop exhausted without acceptance.
   RecordFailure(result,report);
   report.total_elapsed_ms=
      (m_clock!=NULL ? m_clock.TickCountMs() : GetTickCount64())-sequence_start;
   LogReport(report);
   m_last_report=report;
   return(false);
  }
//+------------------------------------------------------------------+
void CExecutionEngine::LogReport(const SExecutionReport &report) const
  {
   if(report.success)
     {
      if(m_log_execution_speed)
         m_id.Info(StringFormat(
                   "%s OK | vol=%.4f @ %.*f | slip=%.1fpt | %I64ums | attempt %d%s%s",
                   report.operation,
                   report.executed_volume,
                   m_broker.Digits(),report.executed_price,
                   report.slippage_points,
                   report.latency_ms,
                   report.attempts,
                   (report.partial_fill ? " | PARTIAL" : ""),
                   (report.excess_slippage ? " | EXCESS SLIPPAGE" : "")));
      else
         m_id.Info(report.operation+" OK");
      return;
     }
   m_id.Error(StringFormat("%s FAILED | retcode=%u %s | attempts=%d | %I64ums",
                           report.operation,
                           report.retcode,
                           report.retcode_text,
                           report.attempts,
                           report.total_elapsed_ms));
  }
//+------------------------------------------------------------------+
string CExecutionEngine::DescribeStatistics(void) const
  {
   return(StringFormat(
          "execution: %I64d sends, %.1f%% success, %I64d retries, "
          "%I64d partial, %I64d duplicates prevented | "
          "slippage avg %.1f worst %.1f pt | latency avg %.0f worst %I64u ms",
          m_stats.total_sends,
          m_stats.SuccessRate(),
          m_stats.retries,
          m_stats.partial_fills,
          m_stats.idempotence_saves,
          m_stats.AverageSlippage(),
          m_stats.slippage_worst_points,
          m_stats.AverageLatency(),
          m_stats.latency_worst_ms));
  }

#endif // SRP_TRADE_ENGINE_CEXECUTIONENGINE_MQH
//+------------------------------------------------------------------+
