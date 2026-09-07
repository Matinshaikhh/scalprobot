//+------------------------------------------------------------------+
//|                                             CTradeExecutor.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Trade : the only class in the product that calls OrderSend.           |
//|                                                                  |
//|   RESPONSIBILITY (one only): execute a prepared request against the      |
//|   server and report what happened. It makes no trading decisions and     |
//|   never decides WHETHER to trade.                                       |
//|                                                                  |
//|   WHAT IT ADDS OVER A RAW OrderSend                                     |
//|     * retry with backoff, driven by CErrorHandler's classification -     |
//|       a requote is retried, an invalid-stops error is not;               |
//|     * slippage measurement, so execution quality is visible;             |
//|     * latency measurement, for the health monitor;                       |
//|     * event publication, so statistics and journal update themselves;    |
//|     * idempotence care: a retry never fires a second position when the   |
//|       first attempt actually succeeded but the reply was lost.           |
//|                                                                  |
//|   Because everything else depends on ITradeExecutor, substituting a      |
//|   simulating implementation makes the whole pipeline testable offline.   |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_CTRADEEXECUTOR_MQH
#define SRP_TRADE_CTRADEEXECUTOR_MQH

#include "../Core/Interfaces/ITradeExecutor.mqh"
#include "../Core/Interfaces/IEventPublisher.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"
#include "../Core/CErrorHandler.mqh"

class CSymbolInfoProvider;

class CTradeExecutor : public ITradeExecutor
  {
private:
   CModuleIdentity      m_id;
   CSymbolInfoProvider *m_symbol_info;     // borrowed
   CErrorHandler       *m_errors;          // borrowed
   IEventPublisher     *m_publisher;       // borrowed
   IClock              *m_clock;           // borrowed

   int                  m_max_retries;
   int                  m_retry_backoff_ms;
   double               m_max_acceptable_slippage_points;

   //--- Execution telemetry.
   long                 m_send_count;
   long                 m_success_count;
   int                  m_rejection_count;
   double               m_slippage_sum;
   long                 m_slippage_samples;
   double               m_latency_sum;
   long                 m_latency_samples;

   //--- Single low-level send with timing and retcode capture. Every
   //--- public method funnels through this, so telemetry can never be
   //--- bypassed.
   bool              SendWithRetry(MqlTradeRequest &request,
                                   MqlTradeResult &result,
                                   const string operation,
                                   int &attempts_used,
                                   ulong &latency_ms);

   //--- Fills the mechanical MqlTradeRequest fields from our own struct.
   void              MapOpenRequest(const STradeRequest &source,
                                    MqlTradeRequest &target) const;
   //--- Refreshes prices between retries: a stale price guarantees a
   //--- second requote.
   bool              RefreshRequestPrice(MqlTradeRequest &request) const;

   void              RecordExecutionQuality(const double requested_price,
                                            const double executed_price,
                                            const ulong latency_ms);
   void              PublishOutcome(const ENUM_SRP_EVENT event_id,
                                    const STradeResult &result,
                                    const string message);

public:
                     CTradeExecutor(CSymbolInfoProvider *symbol_info,
                                    CErrorHandler *errors,
                                    IEventPublisher *publisher,
                                    IClock *clock,
                                    ILogger *logger);
                    ~CTradeExecutor(void) { }

   void              SetRetryPolicy(const int max_retries,const int backoff_ms);
   void              SetMaxSlippagePoints(const double points);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- ITradeExecutor ------------------------------------------------
   virtual bool      OpenPosition(const STradeRequest &request,
                                  STradeResult &result) override;
   virtual bool      ClosePosition(const ulong ticket,
                                   const ENUM_SRP_EXIT_REASON reason,
                                   STradeResult &result) override;
   virtual bool      ClosePartial(const ulong ticket,
                                  const double volume,
                                  const ENUM_SRP_EXIT_REASON reason,
                                  STradeResult &result) override;
   virtual bool      ModifyStops(const ulong ticket,
                                 const double stop_loss,
                                 const double take_profit,
                                 STradeResult &result) override;
   virtual bool      DeletePendingOrder(const ulong ticket,
                                        STradeResult &result) override;

   virtual double    AverageSlippagePoints(void) override;
   virtual double    AverageLatencyMs(void) override;
   virtual int       RejectionCount(void) override { return(m_rejection_count); }
  };

#endif // SRP_TRADE_CTRADEEXECUTOR_MQH
//+------------------------------------------------------------------+
