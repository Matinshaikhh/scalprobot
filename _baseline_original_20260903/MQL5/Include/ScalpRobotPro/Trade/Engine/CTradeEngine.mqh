//+------------------------------------------------------------------+
//|                                                CTradeEngine.mqh |
//|                          Scalping Robot Pro - Core Trading Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): be the single, coherent entry point to   |
//|   trade execution. It owns the five components below, wires them,     |
//|   and exposes one flat API. It makes no trading decisions.           |
//|                                                                  |
//|   COMPOSITION (all OWNED and deleted here)                          |
//|     CMagicNumberManager    identity and ownership                    |
//|     CBrokerManager         environment truth and pre-trade checks     |
//|     CExecutionEngine       the only OrderSend, retry, telemetry       |
//|     COrderManager          market and pending order construction      |
//|     CEnginePositionManager close / partial / modify / reverse         |
//|                                                                  |
//|   Facade pattern: callers get one object with an obvious API, while   |
//|   each component keeps a single responsibility internally. It also    |
//|   implements ITradeExecutor, so it drops straight into the existing    |
//|   architecture wherever that interface is expected.                  |
//|                                                                  |
//|   CONTAINS NO STRATEGY. No signals, no indicators, no entry logic,    |
//|   no sizing. It executes instructions and reports what happened.      |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_ENGINE_CTRADEENGINE_MQH
#define SRP_TRADE_ENGINE_CTRADEENGINE_MQH

#include "../../Core/Interfaces/ITradeExecutor.mqh"
#include "../../Core/Interfaces/IEventPublisher.mqh"
#include "../../Core/Interfaces/IClock.mqh"
#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Core/Base/CModuleIdentity.mqh"
#include "CMagicNumberManager.mqh"
#include "CBrokerManager.mqh"
#include "CExecutionEngine.mqh"
#include "COrderManager.mqh"
#include "CEnginePositionManager.mqh"

//+------------------------------------------------------------------+
//| Everything the engine needs to configure itself. Passing one struct |
//| keeps the constructor stable as options are added.                 |
//+------------------------------------------------------------------+
struct STradeEngineConfig
  {
   string            symbol;
   long              magic_base;
   int               magic_slots;
   string            comment_tag;
   //--- Execution
   int               max_retry_attempts;
   int               retry_backoff_ms;
   bool              progressive_backoff;
   int               deviation_points;
   double            max_slippage_points;
   bool              use_order_check;
   bool              log_execution_speed;
   //--- Protection
   double            max_spread_points;
   double            min_free_margin_percent;
   double            min_margin_level_percent;
   double            margin_safety_factor;

                     STradeEngineConfig(void) { SetDefaults(); }
   void              SetDefaults(void)
     {
      symbol                   = _Symbol;
      magic_base               = 20260806;
      magic_slots              = 16;
      comment_tag              = SRP_PRODUCT_SHORT;
      max_retry_attempts       = SRP_MAX_EXECUTION_RETRIES;
      retry_backoff_ms         = SRP_RETRY_BACKOFF_MS;
      progressive_backoff      = true;
      deviation_points         = SRP_DEFAULT_DEVIATION_POINTS;
      max_slippage_points      = 0.0;
      use_order_check          = true;
      log_execution_speed      = true;
      max_spread_points        = 0.0;
      min_free_margin_percent  = 0.0;
      min_margin_level_percent = 0.0;
      margin_safety_factor     = 1.1;
     }
  };

class CTradeEngine : public ITradeExecutor
  {
private:
   CModuleIdentity         m_id;
   STradeEngineConfig      m_config;

   //--- OWNED components. Constructed in dependency order, destroyed in
   //--- exact reverse.
   CMagicNumberManager    *m_magic;
   CBrokerManager         *m_broker;
   CExecutionEngine       *m_execution;
   COrderManager          *m_orders;
   CEnginePositionManager *m_positions;

   //--- BORROWED infrastructure.
   IClock                 *m_clock;
   IEventPublisher        *m_publisher;
   ILogger                *m_logger;

   bool                    m_built;

   bool              BuildComponents(void);
   void              ReleaseComponents(void);
   //--- Publishes the domain event matching an execution outcome, so
   //--- statistics and journalling update without being called directly.
   void              PublishExecution(const ENUM_SRP_EVENT event_id,
                                      const SExecutionReport &report,
                                      const string message);
   ENUM_SRP_SIGNAL_DIRECTION DirectionOf(const ENUM_POSITION_TYPE type) const;

public:
                     CTradeEngine(const STradeEngineConfig &config,
                                  IClock *clock,
                                  IEventPublisher *publisher,
                                  ILogger *logger);
                    ~CTradeEngine(void);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //=== ITradeExecutor ==============================================
   //--- Adapts the architecture's STradeRequest/STradeResult contract
   //--- onto the richer internal API.
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
   virtual int       RejectionCount(void) override;

   //=== DIRECT API (richer reporting than ITradeExecutor allows) =====
   bool              Buy(const double volume,const double stop_loss,
                         const double take_profit,const string comment_detail,
                         SExecutionReport &report);
   bool              Sell(const double volume,const double stop_loss,
                          const double take_profit,const string comment_detail,
                          SExecutionReport &report);

   bool              BuyLimit(const double volume,const double price,
                              const double sl,const double tp,
                              const string comment_detail,
                              SExecutionReport &report,
                              const datetime expiration=0);
   bool              SellLimit(const double volume,const double price,
                               const double sl,const double tp,
                               const string comment_detail,
                               SExecutionReport &report,
                               const datetime expiration=0);
   bool              BuyStop(const double volume,const double price,
                             const double sl,const double tp,
                             const string comment_detail,
                             SExecutionReport &report,
                             const datetime expiration=0);
   bool              SellStop(const double volume,const double price,
                              const double sl,const double tp,
                              const string comment_detail,
                              SExecutionReport &report,
                              const datetime expiration=0);

   bool              ModifyOrder(const ulong ticket,const double price,
                                 const double sl,const double tp,
                                 SExecutionReport &report);
   bool              DeleteOrder(const ulong ticket,SExecutionReport &report);
   int               DeleteAllOrders(void);

   bool              ClosePositionEx(const ulong ticket,const string reason,
                                     SExecutionReport &report);
   bool              ClosePartialEx(const ulong ticket,const double volume,
                                    const string reason,SExecutionReport &report);
   bool              ClosePartialPercent(const ulong ticket,const double percent,
                                         const string reason,
                                         SExecutionReport &report);
   int               CloseAll(const string reason);
   int               CloseSymbol(const string symbol,const string reason);
   int               CloseBuys(const string reason);
   int               CloseSells(const string reason);
   bool              Reverse(const ulong ticket,const double new_volume,
                             const double sl,const double tp,
                             const string reason,SExecutionReport &report);

   //--- Flattens everything: positions and pending orders together.
   //--- Used by kill switches and emergency stops.
   bool              FlattenAll(const string reason,
                                int &positions_closed,
                                int &orders_deleted);

   //=== QUERIES =====================================================
   void              RefreshAll(void);
   bool              IsHedging(void) const;
   bool              IsNetting(void) const;
   int               PositionCount(void) const;
   int               PendingOrderCount(void) const;
   double            TotalVolume(void) const;
   double            NetVolume(void) const;
   double            FloatingProfit(void) const;
   double            SpreadPoints(void) const;

   //--- Component access for callers needing the detailed API. Returns
   //--- BORROWED pointers: the engine owns these and deletes them.
   CBrokerManager         *Broker(void)    const { return(m_broker); }
   COrderManager          *Orders(void)    const { return(m_orders); }
   CEnginePositionManager *Positions(void) const { return(m_positions); }
   CExecutionEngine       *Execution(void) const { return(m_execution); }
   CMagicNumberManager    *Magic(void)     const { return(m_magic); }

   //--- Diagnostics --------------------------------------------------
   void              GetExecutionStatistics(SExecutionStatistics &out) const;
   string            DescribeStatistics(void) const;
   string            DescribeEnvironment(void) const;
  };

//+------------------------------------------------------------------+
CTradeEngine::CTradeEngine(const STradeEngineConfig &config,
                           IClock *clock,
                           IEventPublisher *publisher,
                           ILogger *logger)
  : m_config(config),
    m_magic(NULL),
    m_broker(NULL),
    m_execution(NULL),
    m_orders(NULL),
    m_positions(NULL),
    m_clock(clock),
    m_publisher(publisher),
    m_logger(logger),
    m_built(false)
  {
   m_id.Configure("CTradeEngine",logger);
  }
//+------------------------------------------------------------------+
CTradeEngine::~CTradeEngine(void)
  {
   ReleaseComponents();
  }
//+------------------------------------------------------------------+
bool CTradeEngine::BuildComponents(void)
  {
   if(m_built)
      return(true);

   //--- Dependency order: identity, then environment, then execution,
   //--- then the two managers that use all three.
   m_magic=new CMagicNumberManager(m_config.magic_base,m_config.magic_slots);
   if(m_magic==NULL)
      return(false);
   m_magic.SetCommentTag(m_config.comment_tag);

   m_broker=new CBrokerManager(m_config.symbol,m_logger);
   if(m_broker==NULL)
      return(false);
   m_broker.SetMaxSpreadPoints(m_config.max_spread_points);
   m_broker.SetMarginRequirements(m_config.min_free_margin_percent,
                                  m_config.min_margin_level_percent);
   m_broker.SetMarginSafetyFactor(m_config.margin_safety_factor);

   m_execution=new CExecutionEngine(m_broker,m_magic,m_clock,m_logger);
   if(m_execution==NULL)
      return(false);
   m_execution.SetRetryPolicy(m_config.max_retry_attempts,
                              m_config.retry_backoff_ms,
                              m_config.progressive_backoff);
   m_execution.SetDeviationPoints(m_config.deviation_points);
   m_execution.SetMaxSlippagePoints(m_config.max_slippage_points);
   m_execution.SetUseOrderCheck(m_config.use_order_check);
   m_execution.SetLogExecutionSpeed(m_config.log_execution_speed);

   m_orders=new COrderManager(m_execution,m_broker,m_magic,m_logger);
   if(m_orders==NULL)
      return(false);

   m_positions=new CEnginePositionManager(m_execution,m_broker,m_magic,
                                          m_orders,m_logger);
   if(m_positions==NULL)
      return(false);

   m_built=true;
   return(true);
  }
//+------------------------------------------------------------------+
void CTradeEngine::ReleaseComponents(void)
  {
   //--- Exact reverse of construction order: later components borrowed
   //--- pointers to earlier ones.
   if(m_positions!=NULL) { delete m_positions; m_positions=NULL; }
   if(m_orders!=NULL)    { delete m_orders;    m_orders=NULL;    }
   if(m_execution!=NULL) { delete m_execution; m_execution=NULL; }
   if(m_broker!=NULL)    { delete m_broker;    m_broker=NULL;    }
   if(m_magic!=NULL)     { delete m_magic;     m_magic=NULL;     }
   m_built=false;
  }
//+------------------------------------------------------------------+
bool CTradeEngine::Initialize(void)
  {
   if(m_id.IsInitialized())
      return(true);

   if(!BuildComponents())
     {
      m_id.Error("component construction failed");
      m_id.SetHealth(SRP_HEALTH_CRITICAL,"construction failed");
      ReleaseComponents();
      return(false);
     }

   //--- Initialise in the same order they were built. Any failure aborts
   //--- startup: a half-initialised execution path is more dangerous
   //--- than no execution path.
   if(!m_broker.Initialize())
     {
      m_id.Error("broker manager initialisation failed");
      return(false);
     }
   if(!m_execution.Initialize())
     {
      m_id.Error("execution engine initialisation failed");
      return(false);
     }
   if(!m_orders.Initialize())
     {
      m_id.Error("order manager initialisation failed");
      return(false);
     }
   if(!m_positions.Initialize())
     {
      m_id.Error("position manager initialisation failed");
      return(false);
     }

   m_id.Info("trade engine ready | "+m_magic.Describe());
   m_id.SetInitialized(true);
   m_id.SetHealth(SRP_HEALTH_OK,"");
   return(true);
  }
//+------------------------------------------------------------------+
void CTradeEngine::Validate(SValidationResult &result)
  {
   if(!m_built)
     {
      result.AddError("CTradeEngine: components not built");
      return;
     }
   if(m_config.magic_base<=0)
      result.AddError("CTradeEngine: magic base must be positive");
   if(m_clock==NULL)
      result.AddWarning("CTradeEngine: no clock injected; latency uses GetTickCount64");

   m_broker.Validate(result);
   m_execution.Validate(result);
   m_orders.Validate(result);
   m_positions.Validate(result);
  }
//+------------------------------------------------------------------+
void CTradeEngine::Shutdown(void)
  {
   if(m_execution!=NULL && m_id.IsInitialized())
      m_id.Info(m_execution.DescribeStatistics());

   //--- Shut down in reverse, then destroy.
   if(m_positions!=NULL) m_positions.Shutdown();
   if(m_orders!=NULL)    m_orders.Shutdown();
   if(m_execution!=NULL) m_execution.Shutdown();
   if(m_broker!=NULL)    m_broker.Shutdown();

   ReleaseComponents();
   m_id.SetInitialized(false);
  }
//+------------------------------------------------------------------+
void CTradeEngine::ReportHealth(SHealthReport &report)
  {
   //--- Aggregate the worst status among components, so one sick
   //--- component cannot hide behind healthy siblings.
   ENUM_SRP_HEALTH_STATUS worst=SRP_HEALTH_OK;
   string detail="";

   SHealthReport component;
   if(m_broker!=NULL)
     {
      m_broker.ReportHealth(component);
      if(component.status>worst) { worst=component.status; detail=component.detail; }
     }
   if(m_execution!=NULL)
     {
      m_execution.ReportHealth(component);
      if(component.status>worst) { worst=component.status; detail=component.detail; }
     }

   m_id.SetHealth(worst,detail);
   m_id.FillReport(report,(m_clock!=NULL ? m_clock.ServerTime() : TimeCurrent()));
  }
//+------------------------------------------------------------------+
ENUM_SRP_SIGNAL_DIRECTION CTradeEngine::DirectionOf(const ENUM_POSITION_TYPE type) const
  {
   return(type==POSITION_TYPE_BUY ? SRP_SIGNAL_BUY : SRP_SIGNAL_SELL);
  }
//+------------------------------------------------------------------+
void CTradeEngine::PublishExecution(const ENUM_SRP_EVENT event_id,
                                    const SExecutionReport &report,
                                    const string message)
  {
   if(m_publisher==NULL)
      return;
   //--- Skip payload construction when nobody is listening; this runs on
   //--- the hot path.
   if(!m_publisher.HasListeners(event_id))
      return;

   SEventPayload payload;
   payload.event_id      = event_id;
   payload.timestamp     = (m_clock!=NULL ? m_clock.ServerTime() : TimeCurrent());
   payload.timestamp_msc = (m_clock!=NULL ? m_clock.TickCountMs() : GetTickCount64());
   payload.source_module = m_id.Name();
   payload.message       = message;
   payload.ticket        = (report.position_ticket!=SRP_INVALID_TICKET
                            ? report.position_ticket : report.order_ticket);
   payload.double_value  = report.executed_volume;
   payload.integer_value = (long)report.retcode;
   m_publisher.Publish(payload);
  }
//+------------------------------------------------------------------+
//| ITradeExecutor adaptation                                          |
//+------------------------------------------------------------------+
bool CTradeEngine::OpenPosition(const STradeRequest &request,
                                STradeResult &result)
  {
   result.Reset();
   SExecutionReport report;

   const bool ok=m_orders.SendMarketOrder(request.direction,
                                          request.volume,
                                          request.stop_loss,
                                          request.take_profit,
                                          request.comment,
                                          report,
                                          request.magic);

   //--- Map the rich internal report onto the architecture's contract.
   result.success         = report.success;
   result.order_ticket    = report.order_ticket;
   result.deal_ticket     = report.deal_ticket;
   result.position_ticket = report.position_ticket;
   result.executed_volume = report.executed_volume;
   result.executed_price  = report.executed_price;
   result.requested_price = report.requested_price;
   result.slippage_points = report.slippage_points;
   result.retcode         = report.retcode;
   result.retcode_text    = report.retcode_text;
   result.attempts        = report.attempts;
   result.latency_ms      = report.latency_ms;

   PublishExecution(ok ? SRP_EVENT_POSITION_OPENED : SRP_EVENT_ORDER_REJECTED,
                    report,
                    ok ? "position opened" : report.failure_detail);
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::ClosePosition(const ulong ticket,
                                 const ENUM_SRP_EXIT_REASON reason,
                                 STradeResult &result)
  {
   result.Reset();
   SExecutionReport report;
   const bool ok=m_positions.ClosePosition(ticket,EnumToString(reason),report);

   result.success         = report.success;
   result.order_ticket    = report.order_ticket;
   result.deal_ticket     = report.deal_ticket;
   result.position_ticket = ticket;
   result.executed_volume = report.executed_volume;
   result.executed_price  = report.executed_price;
   result.slippage_points = report.slippage_points;
   result.retcode         = report.retcode;
   result.retcode_text    = report.retcode_text;
   result.attempts        = report.attempts;
   result.latency_ms      = report.latency_ms;

   PublishExecution(ok ? SRP_EVENT_POSITION_CLOSED : SRP_EVENT_ORDER_REJECTED,
                    report,
                    ok ? "position closed" : report.failure_detail);
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::ClosePartial(const ulong ticket,
                                const double volume,
                                const ENUM_SRP_EXIT_REASON reason,
                                STradeResult &result)
  {
   result.Reset();
   SExecutionReport report;
   const bool ok=m_positions.ClosePartial(ticket,volume,EnumToString(reason),report);

   result.success         = report.success;
   result.deal_ticket     = report.deal_ticket;
   result.position_ticket = ticket;
   result.executed_volume = report.executed_volume;
   result.executed_price  = report.executed_price;
   result.retcode         = report.retcode;
   result.retcode_text    = report.retcode_text;
   result.attempts        = report.attempts;
   result.latency_ms      = report.latency_ms;

   PublishExecution(ok ? SRP_EVENT_POSITION_PARTIALLY_CLOSED
                       : SRP_EVENT_ORDER_REJECTED,
                    report,
                    ok ? "partial close" : report.failure_detail);
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::ModifyStops(const ulong ticket,
                               const double stop_loss,
                               const double take_profit,
                               STradeResult &result)
  {
   result.Reset();
   SExecutionReport report;
   const bool ok=m_positions.ModifyStops(ticket,stop_loss,take_profit,report);

   result.success         = report.success;
   result.position_ticket = ticket;
   result.retcode         = report.retcode;
   result.retcode_text    = report.retcode_text;
   result.attempts        = report.attempts;
   result.latency_ms      = report.latency_ms;

   if(ok)
      PublishExecution(SRP_EVENT_STOP_LEVEL_UPDATED,report,"stops modified");
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::DeletePendingOrder(const ulong ticket,STradeResult &result)
  {
   result.Reset();
   SExecutionReport report;
   const bool ok=m_orders.DeletePendingOrder(ticket,report);

   result.success      = report.success;
   result.order_ticket = ticket;
   result.retcode      = report.retcode;
   result.retcode_text = report.retcode_text;
   result.attempts     = report.attempts;
   result.latency_ms   = report.latency_ms;
   return(ok);
  }
//+------------------------------------------------------------------+
double CTradeEngine::AverageSlippagePoints(void)
  {
   return(m_execution!=NULL ? m_execution.AverageSlippagePoints() : 0.0);
  }
//+------------------------------------------------------------------+
double CTradeEngine::AverageLatencyMs(void)
  {
   return(m_execution!=NULL ? m_execution.AverageLatencyMs() : 0.0);
  }
//+------------------------------------------------------------------+
int CTradeEngine::RejectionCount(void)
  {
   return(m_execution!=NULL ? (int)m_execution.FailureCount() : 0);
  }
//+------------------------------------------------------------------+
//| Direct API                                                         |
//+------------------------------------------------------------------+
bool CTradeEngine::Buy(const double volume,const double stop_loss,
                       const double take_profit,const string comment_detail,
                       SExecutionReport &report)
  {
   const bool ok=m_orders.SendMarketOrder(SRP_SIGNAL_BUY,volume,stop_loss,
                                          take_profit,comment_detail,report);
   PublishExecution(ok ? SRP_EVENT_POSITION_OPENED : SRP_EVENT_ORDER_REJECTED,
                    report,ok ? "buy executed" : report.failure_detail);
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::Sell(const double volume,const double stop_loss,
                        const double take_profit,const string comment_detail,
                        SExecutionReport &report)
  {
   const bool ok=m_orders.SendMarketOrder(SRP_SIGNAL_SELL,volume,stop_loss,
                                          take_profit,comment_detail,report);
   PublishExecution(ok ? SRP_EVENT_POSITION_OPENED : SRP_EVENT_ORDER_REJECTED,
                    report,ok ? "sell executed" : report.failure_detail);
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::BuyLimit(const double volume,const double price,
                            const double sl,const double tp,
                            const string comment_detail,
                            SExecutionReport &report,const datetime expiration)
  {
   const bool ok=m_orders.PlaceBuyLimit(volume,price,sl,tp,comment_detail,
                                        report,expiration);
   if(ok) PublishExecution(SRP_EVENT_ORDER_SUBMITTED,report,"buy limit placed");
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::SellLimit(const double volume,const double price,
                             const double sl,const double tp,
                             const string comment_detail,
                             SExecutionReport &report,const datetime expiration)
  {
   const bool ok=m_orders.PlaceSellLimit(volume,price,sl,tp,comment_detail,
                                         report,expiration);
   if(ok) PublishExecution(SRP_EVENT_ORDER_SUBMITTED,report,"sell limit placed");
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::BuyStop(const double volume,const double price,
                           const double sl,const double tp,
                           const string comment_detail,
                           SExecutionReport &report,const datetime expiration)
  {
   const bool ok=m_orders.PlaceBuyStop(volume,price,sl,tp,comment_detail,
                                       report,expiration);
   if(ok) PublishExecution(SRP_EVENT_ORDER_SUBMITTED,report,"buy stop placed");
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::SellStop(const double volume,const double price,
                            const double sl,const double tp,
                            const string comment_detail,
                            SExecutionReport &report,const datetime expiration)
  {
   const bool ok=m_orders.PlaceSellStop(volume,price,sl,tp,comment_detail,
                                        report,expiration);
   if(ok) PublishExecution(SRP_EVENT_ORDER_SUBMITTED,report,"sell stop placed");
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::ModifyOrder(const ulong ticket,const double price,
                               const double sl,const double tp,
                               SExecutionReport &report)
  {
   return(m_orders.ModifyPendingOrder(ticket,price,sl,tp,report));
  }
//+------------------------------------------------------------------+
bool CTradeEngine::DeleteOrder(const ulong ticket,SExecutionReport &report)
  {
   return(m_orders.DeletePendingOrder(ticket,report));
  }
//+------------------------------------------------------------------+
int CTradeEngine::DeleteAllOrders(void)
  {
   return(m_orders.DeleteAllPendingOrders());
  }
//+------------------------------------------------------------------+
bool CTradeEngine::ClosePositionEx(const ulong ticket,const string reason,
                                   SExecutionReport &report)
  {
   const bool ok=m_positions.ClosePosition(ticket,reason,report);
   PublishExecution(ok ? SRP_EVENT_POSITION_CLOSED : SRP_EVENT_ORDER_REJECTED,
                    report,ok ? "closed: "+reason : report.failure_detail);
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::ClosePartialEx(const ulong ticket,const double volume,
                                  const string reason,SExecutionReport &report)
  {
   const bool ok=m_positions.ClosePartial(ticket,volume,reason,report);
   if(ok)
      PublishExecution(SRP_EVENT_POSITION_PARTIALLY_CLOSED,report,
                       "partial close: "+reason);
   return(ok);
  }
//+------------------------------------------------------------------+
bool CTradeEngine::ClosePartialPercent(const ulong ticket,const double percent,
                                       const string reason,
                                       SExecutionReport &report)
  {
   return(m_positions.ClosePartialByPercent(ticket,percent,reason,report));
  }
//+------------------------------------------------------------------+
int CTradeEngine::CloseAll(const string reason)
  {
   return(m_positions.CloseAll(reason));
  }
//+------------------------------------------------------------------+
int CTradeEngine::CloseSymbol(const string symbol,const string reason)
  {
   return(m_positions.CloseSymbol(symbol,reason));
  }
//+------------------------------------------------------------------+
int CTradeEngine::CloseBuys(const string reason)
  {
   return(m_positions.CloseByType(POSITION_TYPE_BUY,reason));
  }
//+------------------------------------------------------------------+
int CTradeEngine::CloseSells(const string reason)
  {
   return(m_positions.CloseByType(POSITION_TYPE_SELL,reason));
  }
//+------------------------------------------------------------------+
bool CTradeEngine::Reverse(const ulong ticket,const double new_volume,
                           const double sl,const double tp,
                           const string reason,SExecutionReport &report)
  {
   return(m_positions.ReversePosition(ticket,new_volume,sl,tp,reason,report));
  }
//+------------------------------------------------------------------+
bool CTradeEngine::FlattenAll(const string reason,
                              int &positions_closed,
                              int &orders_deleted)
  {
   //--- Pending orders go FIRST. Closing positions first would leave a
   //--- window in which a pending order could trigger and re-establish
   //--- exposure the flatten was meant to remove.
   orders_deleted   = m_orders.DeleteAllPendingOrders();
   positions_closed = m_positions.CloseAll(reason);

   m_orders.Refresh();
   m_positions.Refresh();
   const bool clean=(m_positions.Count()==0 && m_orders.Count()==0);

   if(clean)
      m_id.Info(StringFormat("FLATTEN complete (%s): %d positions, %d orders",
                             reason,positions_closed,orders_deleted));
   else
      m_id.Error(StringFormat(
                 "FLATTEN INCOMPLETE (%s): %d positions and %d orders remain",
                 reason,m_positions.Count(),m_orders.Count()));
   return(clean);
  }
//+------------------------------------------------------------------+
void CTradeEngine::RefreshAll(void)
  {
   if(m_broker!=NULL)    m_broker.RefreshVolatile();
   if(m_orders!=NULL)    m_orders.Refresh();
   if(m_positions!=NULL) m_positions.Refresh();
  }
//+------------------------------------------------------------------+
bool CTradeEngine::IsHedging(void) const
  {
   return(m_broker!=NULL && m_broker.IsHedging());
  }
//+------------------------------------------------------------------+
bool CTradeEngine::IsNetting(void) const
  {
   return(m_broker!=NULL && m_broker.IsNetting());
  }
//+------------------------------------------------------------------+
int CTradeEngine::PositionCount(void) const
  {
   return(m_positions!=NULL ? m_positions.Count() : 0);
  }
//+------------------------------------------------------------------+
int CTradeEngine::PendingOrderCount(void) const
  {
   return(m_orders!=NULL ? m_orders.Count() : 0);
  }
//+------------------------------------------------------------------+
double CTradeEngine::TotalVolume(void) const
  {
   return(m_positions!=NULL ? m_positions.TotalVolume() : 0.0);
  }
//+------------------------------------------------------------------+
double CTradeEngine::NetVolume(void) const
  {
   return(m_positions!=NULL ? m_positions.NetVolume() : 0.0);
  }
//+------------------------------------------------------------------+
double CTradeEngine::FloatingProfit(void) const
  {
   return(m_positions!=NULL ? m_positions.FloatingProfit() : 0.0);
  }
//+------------------------------------------------------------------+
double CTradeEngine::SpreadPoints(void) const
  {
   return(m_broker!=NULL ? m_broker.SpreadPoints() : 0.0);
  }
//+------------------------------------------------------------------+
void CTradeEngine::GetExecutionStatistics(SExecutionStatistics &out) const
  {
   if(m_execution!=NULL)
      m_execution.GetStatistics(out);
  }
//+------------------------------------------------------------------+
string CTradeEngine::DescribeStatistics(void) const
  {
   return(m_execution!=NULL ? m_execution.DescribeStatistics() : "no execution engine");
  }
//+------------------------------------------------------------------+
string CTradeEngine::DescribeEnvironment(void) const
  {
   return(m_broker!=NULL ? m_broker.Describe() : "no broker manager");
  }

#endif // SRP_TRADE_ENGINE_CTRADEENGINE_MQH
//+------------------------------------------------------------------+
