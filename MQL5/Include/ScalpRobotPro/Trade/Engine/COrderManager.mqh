//+------------------------------------------------------------------+
//|                                               COrderManager.mqh |
//|                          Scalping Robot Pro - Core Trading Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): build and submit ORDERS - market and    |
//|   pending - and modify or delete pending orders.                    |
//|                                                                  |
//|   ORDERS vs POSITIONS: the division of labour                      |
//|     COrderManager    works with ORDERS   (things not yet filled,    |
//|                      plus the market orders that create positions)  |
//|     CPositionManager works with POSITIONS (things already filled)   |
//|                                                                  |
//|   That split follows MT5's own object model. Conflating the two is   |
//|   why so many EAs mishandle pending orders on netting accounts.     |
//|                                                                  |
//|   It never calls OrderSend itself - every request goes through      |
//|   CExecutionEngine, so retry, slippage and latency accounting apply |
//|   uniformly and cannot be bypassed.                                |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_ENGINE_CORDERMANAGER_MQH
#define SRP_TRADE_ENGINE_CORDERMANAGER_MQH

#include "../../Core/Interfaces/IModule.mqh"
#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Core/Base/CModuleIdentity.mqh"
#include "CExecutionEngine.mqh"
#include "CBrokerManager.mqh"
#include "CMagicNumberManager.mqh"

//+------------------------------------------------------------------+
//| Normalised view of one pending order owned by this EA.             |
//+------------------------------------------------------------------+
struct SPendingOrderInfo
  {
   ulong             ticket;
   string            symbol;
   long              magic;
   ENUM_ORDER_TYPE   type;
   double            volume_initial;
   double            volume_current;
   double            price_open;
   double            price_stop_limit;
   double            stop_loss;
   double            take_profit;
   datetime          time_setup;
   datetime          time_expiration;
   ENUM_ORDER_STATE  state;
   string            comment;

                     SPendingOrderInfo(void) { Reset(); }
   void              Reset(void)
     {
      ticket=SRP_INVALID_TICKET; symbol=""; magic=0;
      type=ORDER_TYPE_BUY_LIMIT;
      volume_initial=0.0; volume_current=0.0;
      price_open=0.0; price_stop_limit=0.0;
      stop_loss=0.0; take_profit=0.0;
      time_setup=0; time_expiration=0;
      state=ORDER_STATE_STARTED; comment="";
     }
   bool              IsBuySide(void) const
     {
      return(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP ||
             type==ORDER_TYPE_BUY_STOP_LIMIT);
     }
  };

class COrderManager : public IModule
  {
private:
   CModuleIdentity      m_id;
   //--- All borrowed.
   CExecutionEngine    *m_execution;
   CBrokerManager      *m_broker;
   CMagicNumberManager *m_magic;

   //--- Cached pending orders, refreshed on demand.
   SPendingOrderInfo    m_orders[];
   datetime             m_last_refresh;
   long                 m_market_orders_sent;
   long                 m_pending_orders_placed;
   long                 m_orders_modified;
   long                 m_orders_deleted;

   //--- Validates a pending order's price sits on the legal side of the
   //--- market. A buy-stop below price is silently converted or rejected
   //--- depending on broker, so it is caught here instead.
   bool              IsPendingPriceValid(const ENUM_ORDER_TYPE type,
                                         const double price,
                                         string &reason) const;
   bool              ReadOrder(const ulong ticket,SPendingOrderInfo &out) const;

public:
   //--- Clamps SL/TP to the broker's stop level around an entry price.
   //--- PUBLIC because the position manager needs the identical rule
   //--- when reversing. Duplicating this arithmetic is exactly how the
   //--- two paths would eventually disagree, so there is one copy.
   void              ClampProtectiveLevels(const ENUM_ORDER_TYPE type,
                                           const double entry_price,
                                           double &stop_loss,
                                           double &take_profit) const;

                     COrderManager(CExecutionEngine *execution,
                                   CBrokerManager *broker,
                                   CMagicNumberManager *magic,
                                   ILogger *logger);
                    ~COrderManager(void);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //=== MARKET ORDERS ===============================================
   //--- Opens a position at market. 'strategy_id' selects the magic
   //--- slot so statistics can attribute the trade later.
   bool              SendMarketOrder(const ENUM_SRP_SIGNAL_DIRECTION direction,
                                     const double volume,
                                     const double stop_loss,
                                     const double take_profit,
                                     const string comment_detail,
                                     SExecutionReport &report,
                                     const long override_magic=0);

   //=== PENDING ORDERS ==============================================
   bool              PlaceBuyLimit(const double volume,const double price,
                                   const double stop_loss,const double take_profit,
                                   const string comment_detail,
                                   SExecutionReport &report,
                                   const datetime expiration=0);
   bool              PlaceSellLimit(const double volume,const double price,
                                    const double stop_loss,const double take_profit,
                                    const string comment_detail,
                                    SExecutionReport &report,
                                    const datetime expiration=0);
   bool              PlaceBuyStop(const double volume,const double price,
                                  const double stop_loss,const double take_profit,
                                  const string comment_detail,
                                  SExecutionReport &report,
                                  const datetime expiration=0);
   bool              PlaceSellStop(const double volume,const double price,
                                   const double stop_loss,const double take_profit,
                                   const string comment_detail,
                                   SExecutionReport &report,
                                   const datetime expiration=0);
   //--- Stop-limit orders need both a trigger and a limit price.
   bool              PlaceStopLimit(const ENUM_ORDER_TYPE type,
                                    const double volume,
                                    const double trigger_price,
                                    const double limit_price,
                                    const double stop_loss,
                                    const double take_profit,
                                    const string comment_detail,
                                    SExecutionReport &report,
                                    const datetime expiration=0);

   //--- Generic placement, used by all of the above.
   bool              PlacePendingOrder(const ENUM_ORDER_TYPE type,
                                       const double volume,
                                       const double price,
                                       const double stop_limit_price,
                                       const double stop_loss,
                                       const double take_profit,
                                       const string comment_detail,
                                       SExecutionReport &report,
                                       const datetime expiration=0);

   //=== MODIFY / DELETE =============================================
   //--- Modifies a pending order's price and levels. Skips no-op
   //--- changes so the server is never spammed.
   bool              ModifyPendingOrder(const ulong ticket,
                                        const double new_price,
                                        const double new_stop_loss,
                                        const double new_take_profit,
                                        SExecutionReport &report,
                                        const datetime new_expiration=0);
   bool              DeletePendingOrder(const ulong ticket,SExecutionReport &report);
   //--- Bulk deletion, reporting how many actually went.
   int               DeleteAllPendingOrders(void);
   int               DeletePendingOrdersByType(const ENUM_ORDER_TYPE type);

   //=== QUERIES =====================================================
   bool              Refresh(void);
   int               Count(void) const { return(ArraySize(m_orders)); }
   bool              At(const int index,SPendingOrderInfo &out) const;
   bool              FindByTicket(const ulong ticket,SPendingOrderInfo &out) const;
   int               CountByType(const ENUM_ORDER_TYPE type) const;
   bool              IsOurOrder(const ulong ticket) const;
   double            TotalPendingVolume(void) const;

   //--- Diagnostics --------------------------------------------------
   long              MarketOrdersSent(void)    const { return(m_market_orders_sent); }
   long              PendingOrdersPlaced(void) const { return(m_pending_orders_placed); }
   long              OrdersModified(void)      const { return(m_orders_modified); }
   long              OrdersDeleted(void)       const { return(m_orders_deleted); }
  };

//+------------------------------------------------------------------+
COrderManager::COrderManager(CExecutionEngine *execution,
                             CBrokerManager *broker,
                             CMagicNumberManager *magic,
                             ILogger *logger)
  : m_execution(execution),
    m_broker(broker),
    m_magic(magic),
    m_last_refresh(0),
    m_market_orders_sent(0),
    m_pending_orders_placed(0),
    m_orders_modified(0),
    m_orders_deleted(0)
  {
   m_id.Configure("COrderManager",logger);
   ArrayResize(m_orders,0);
  }
//+------------------------------------------------------------------+
COrderManager::~COrderManager(void)
  {
   ArrayFree(m_orders);
  }
//+------------------------------------------------------------------+
bool COrderManager::Initialize(void)
  {
   if(m_id.IsInitialized())
      return(true);
   if(m_execution==NULL || m_broker==NULL || m_magic==NULL)
     {
      m_id.Error("missing collaborator (execution/broker/magic)");
      m_id.SetHealth(SRP_HEALTH_CRITICAL,"wiring incomplete");
      return(false);
     }
   Refresh();
   m_id.SetInitialized(true);
   return(true);
  }
//+------------------------------------------------------------------+
void COrderManager::Validate(SValidationResult &result)
  {
   if(m_execution==NULL) result.AddError("COrderManager: execution engine not injected");
   if(m_broker==NULL)    result.AddError("COrderManager: broker manager not injected");
   if(m_magic==NULL)     result.AddError("COrderManager: magic manager not injected");
  }
//+------------------------------------------------------------------+
void COrderManager::Shutdown(void)
  {
   ArrayResize(m_orders,0);
   m_id.SetInitialized(false);
  }
//+------------------------------------------------------------------+
void COrderManager::ReportHealth(SHealthReport &report)
  {
   m_id.FillReport(report,m_last_refresh);
  }
//+------------------------------------------------------------------+
bool COrderManager::IsPendingPriceValid(const ENUM_ORDER_TYPE type,
                                        const double price,
                                        string &reason) const
  {
   reason="";
   if(price<=0.0)
     {
      reason="price is zero";
      return(false);
     }
   MqlTick tick;
   if(!m_broker.GetTick(tick))
     {
      reason="no tick data";
      return(false);
     }

   //--- The broker requires a minimum distance from the market, and the
   //--- order must be on the correct side. Getting the side wrong is a
   //--- guaranteed rejection (or worse, a silent conversion).
   const double min_distance=m_broker.PointsToPrice((double)m_broker.StopsLevel());

   switch(type)
     {
      case ORDER_TYPE_BUY_LIMIT:
         //--- Buy limit must sit BELOW the ask.
         if(price>tick.ask-min_distance)
           {
            reason=StringFormat("buy limit %.*f must be at least %d points below ask %.*f",
                                m_broker.Digits(),price,m_broker.StopsLevel(),
                                m_broker.Digits(),tick.ask);
            return(false);
           }
         break;

      case ORDER_TYPE_SELL_LIMIT:
         //--- Sell limit must sit ABOVE the bid.
         if(price<tick.bid+min_distance)
           {
            reason=StringFormat("sell limit %.*f must be at least %d points above bid %.*f",
                                m_broker.Digits(),price,m_broker.StopsLevel(),
                                m_broker.Digits(),tick.bid);
            return(false);
           }
         break;

      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_BUY_STOP_LIMIT:
         //--- Buy stop must sit ABOVE the ask.
         if(price<tick.ask+min_distance)
           {
            reason=StringFormat("buy stop %.*f must be at least %d points above ask %.*f",
                                m_broker.Digits(),price,m_broker.StopsLevel(),
                                m_broker.Digits(),tick.ask);
            return(false);
           }
         break;

      case ORDER_TYPE_SELL_STOP:
      case ORDER_TYPE_SELL_STOP_LIMIT:
         //--- Sell stop must sit BELOW the bid.
         if(price>tick.bid-min_distance)
           {
            reason=StringFormat("sell stop %.*f must be at least %d points below bid %.*f",
                                m_broker.Digits(),price,m_broker.StopsLevel(),
                                m_broker.Digits(),tick.bid);
            return(false);
           }
         break;

      default:
         reason="not a pending order type";
         return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
void COrderManager::ClampProtectiveLevels(const ENUM_ORDER_TYPE type,
                                          const double entry_price,
                                          double &stop_loss,
                                          double &take_profit) const
  {
   const double min_distance=m_broker.PointsToPrice((double)m_broker.StopsLevel());
   if(min_distance<=0.0)
     {
      stop_loss  =(stop_loss  >0.0 ? m_broker.NormalizePrice(stop_loss)   : 0.0);
      take_profit=(take_profit>0.0 ? m_broker.NormalizePrice(take_profit) : 0.0);
      return;
     }

   const bool is_buy=(type==ORDER_TYPE_BUY || type==ORDER_TYPE_BUY_LIMIT ||
                      type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT);

   if(stop_loss>0.0)
     {
      //--- Push the stop out to the legal minimum rather than abandoning
      //--- the trade. Widening a stop is the conservative direction: it
      //--- risks more points but keeps protection in place. The risk
      //--- layer re-verifies the money at stake afterwards.
      if(is_buy && stop_loss>entry_price-min_distance)
         stop_loss=entry_price-min_distance;
      else if(!is_buy && stop_loss<entry_price+min_distance)
         stop_loss=entry_price+min_distance;
      stop_loss=m_broker.NormalizePrice(stop_loss);
     }

   if(take_profit>0.0)
     {
      if(is_buy && take_profit<entry_price+min_distance)
         take_profit=entry_price+min_distance;
      else if(!is_buy && take_profit>entry_price-min_distance)
         take_profit=entry_price-min_distance;
      take_profit=m_broker.NormalizePrice(take_profit);
     }
  }
//+------------------------------------------------------------------+
bool COrderManager::SendMarketOrder(const ENUM_SRP_SIGNAL_DIRECTION direction,
                                    const double volume,
                                    const double stop_loss,
                                    const double take_profit,
                                    const string comment_detail,
                                    SExecutionReport &report,
                                    const long override_magic)
  {
   report.Reset();
   if(direction==SRP_SIGNAL_NONE)
     {
      report.failure_detail="no direction supplied";
      m_id.Error(report.failure_detail);
      return(false);
     }

   const double normalized_volume=m_broker.NormalizeVolume(volume);
   if(normalized_volume<=0.0)
     {
      report.failure_detail=StringFormat(
         "volume %.4f normalises to zero (broker min %.4f, step %.4f)",
         volume,m_broker.VolumeMin(),m_broker.VolumeStep());
      m_id.Error(report.failure_detail);
      return(false);
     }

   MqlTick tick;
   if(!m_broker.GetTick(tick))
     {
      report.failure_detail="no tick data available";
      m_id.Error(report.failure_detail);
      return(false);
     }

   const ENUM_ORDER_TYPE order_type=
      (direction==SRP_SIGNAL_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   const double entry_price=
      m_broker.NormalizePrice(direction==SRP_SIGNAL_BUY ? tick.ask : tick.bid);

   //--- Full pre-trade gate: permissions, market state, spread, volume,
   //--- direction restrictions and margin.
   SBrokerCheckResult check;
   if(!m_broker.CheckCanOpen(order_type,normalized_volume,entry_price,check))
     {
      report.failure_detail=check.detail;
      m_id.Warn("market order refused: "+check.detail);
      return(false);
     }

   double sl=stop_loss;
   double tp=take_profit;
   ClampProtectiveLevels(order_type,entry_price,sl,tp);

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_DEAL;
   request.type   = order_type;
   request.volume = normalized_volume;
   request.price  = entry_price;
   request.sl     = sl;
   request.tp     = tp;
   m_execution.PrepareCommonFields(request,comment_detail);
   if(override_magic>0)
      request.magic=override_magic;

   const string operation=StringFormat("MARKET %s %.4f",
                                       (direction==SRP_SIGNAL_BUY ? "BUY" : "SELL"),
                                       normalized_volume);
   if(!m_execution.Send(request,operation,report))
      return(false);

   m_market_orders_sent++;
   return(true);
  }
//+------------------------------------------------------------------+
bool COrderManager::PlacePendingOrder(const ENUM_ORDER_TYPE type,
                                      const double volume,
                                      const double price,
                                      const double stop_limit_price,
                                      const double stop_loss,
                                      const double take_profit,
                                      const string comment_detail,
                                      SExecutionReport &report,
                                      const datetime expiration)
  {
   report.Reset();

   const double normalized_volume=m_broker.NormalizeVolume(volume);
   if(normalized_volume<=0.0)
     {
      report.failure_detail=StringFormat("volume %.4f normalises to zero",volume);
      m_id.Error(report.failure_detail);
      return(false);
     }

   const double normalized_price=m_broker.NormalizePrice(price);
   string reason="";
   if(!IsPendingPriceValid(type,normalized_price,reason))
     {
      report.failure_detail=reason;
      m_id.Warn("pending order refused: "+reason);
      return(false);
     }

   SBrokerCheckResult check;
   if(!m_broker.CheckCanOpen(type,normalized_volume,normalized_price,check))
     {
      report.failure_detail=check.detail;
      m_id.Warn("pending order refused: "+check.detail);
      return(false);
     }

   double sl=stop_loss;
   double tp=take_profit;
   //--- Levels are clamped around the ORDER price, not the market price:
   //--- that is where they will be measured from once triggered.
   ClampProtectiveLevels(type,normalized_price,sl,tp);

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_PENDING;
   request.type   = type;
   request.volume = normalized_volume;
   request.price  = normalized_price;
   request.sl     = sl;
   request.tp     = tp;
   if(stop_limit_price>0.0)
      request.stoplimit=m_broker.NormalizePrice(stop_limit_price);
   m_execution.PrepareCommonFields(request,comment_detail);

   //--- Expiration requires the matching type flag, otherwise the
   //--- server returns "invalid expiration".
   if(expiration>0)
     {
      request.type_time=ORDER_TIME_SPECIFIED;
      request.expiration=expiration;
     }
   else
      request.type_time=ORDER_TIME_GTC;

   const string operation=StringFormat("PENDING %s %.4f @ %.*f",
                                       EnumToString(type),normalized_volume,
                                       m_broker.Digits(),normalized_price);
   if(!m_execution.Send(request,operation,report))
      return(false);

   m_pending_orders_placed++;
   Refresh();
   return(true);
  }
//+------------------------------------------------------------------+
bool COrderManager::PlaceBuyLimit(const double volume,const double price,
                                  const double stop_loss,const double take_profit,
                                  const string comment_detail,
                                  SExecutionReport &report,
                                  const datetime expiration)
  {
   return(PlacePendingOrder(ORDER_TYPE_BUY_LIMIT,volume,price,0.0,
                            stop_loss,take_profit,comment_detail,report,expiration));
  }
//+------------------------------------------------------------------+
bool COrderManager::PlaceSellLimit(const double volume,const double price,
                                   const double stop_loss,const double take_profit,
                                   const string comment_detail,
                                   SExecutionReport &report,
                                   const datetime expiration)
  {
   return(PlacePendingOrder(ORDER_TYPE_SELL_LIMIT,volume,price,0.0,
                            stop_loss,take_profit,comment_detail,report,expiration));
  }
//+------------------------------------------------------------------+
bool COrderManager::PlaceBuyStop(const double volume,const double price,
                                 const double stop_loss,const double take_profit,
                                 const string comment_detail,
                                 SExecutionReport &report,
                                 const datetime expiration)
  {
   return(PlacePendingOrder(ORDER_TYPE_BUY_STOP,volume,price,0.0,
                            stop_loss,take_profit,comment_detail,report,expiration));
  }
//+------------------------------------------------------------------+
bool COrderManager::PlaceSellStop(const double volume,const double price,
                                  const double stop_loss,const double take_profit,
                                  const string comment_detail,
                                  SExecutionReport &report,
                                  const datetime expiration)
  {
   return(PlacePendingOrder(ORDER_TYPE_SELL_STOP,volume,price,0.0,
                            stop_loss,take_profit,comment_detail,report,expiration));
  }
//+------------------------------------------------------------------+
bool COrderManager::PlaceStopLimit(const ENUM_ORDER_TYPE type,
                                   const double volume,
                                   const double trigger_price,
                                   const double limit_price,
                                   const double stop_loss,
                                   const double take_profit,
                                   const string comment_detail,
                                   SExecutionReport &report,
                                   const datetime expiration)
  {
   if(type!=ORDER_TYPE_BUY_STOP_LIMIT && type!=ORDER_TYPE_SELL_STOP_LIMIT)
     {
      report.Reset();
      report.failure_detail="PlaceStopLimit requires a stop-limit order type";
      m_id.Error(report.failure_detail);
      return(false);
     }
   return(PlacePendingOrder(type,volume,trigger_price,limit_price,
                            stop_loss,take_profit,comment_detail,report,expiration));
  }
//+------------------------------------------------------------------+
bool COrderManager::ModifyPendingOrder(const ulong ticket,
                                       const double new_price,
                                       const double new_stop_loss,
                                       const double new_take_profit,
                                       SExecutionReport &report,
                                       const datetime new_expiration)
  {
   report.Reset();

   SPendingOrderInfo existing;
   if(!ReadOrder(ticket,existing))
     {
      report.failure_detail=StringFormat("order #%I64u not found or not ours",ticket);
      m_id.Warn(report.failure_detail);
      return(false);
     }

   const double price=(new_price>0.0 ? m_broker.NormalizePrice(new_price)
                                     : existing.price_open);
   double sl=(new_stop_loss>0.0   ? new_stop_loss   : existing.stop_loss);
   double tp=(new_take_profit>0.0 ? new_take_profit : existing.take_profit);
   ClampProtectiveLevels(existing.type,price,sl,tp);

   //--- NO-OP SUPPRESSION. Sending an unchanged modification wastes a
   //--- round trip and earns retcode 10025 ("no changes"), which then
   //--- pollutes the error statistics and can trip the error-storm
   //--- detector for no reason.
   const double tolerance=m_broker.TickSize()*0.5;
   const bool price_same=(MathAbs(price-existing.price_open)<tolerance);
   const bool sl_same   =(MathAbs(sl-existing.stop_loss)<tolerance);
   const bool tp_same   =(MathAbs(tp-existing.take_profit)<tolerance);
   if(price_same && sl_same && tp_same && new_expiration==existing.time_expiration)
     {
      report.success=true;
      report.retcode_text="no change required";
      m_id.Debug(StringFormat("order #%I64u modification skipped: no change",ticket));
      return(true);
     }

   string reason="";
   if(!IsPendingPriceValid(existing.type,price,reason))
     {
      report.failure_detail=reason;
      m_id.Warn("order modification refused: "+reason);
      return(false);
     }

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_MODIFY;
   request.order  = ticket;
   request.symbol = existing.symbol;
   request.price  = price;
   request.sl     = sl;
   request.tp     = tp;
   if(existing.price_stop_limit>0.0)
      request.stoplimit=existing.price_stop_limit;
   if(new_expiration>0)
     {
      request.type_time=ORDER_TIME_SPECIFIED;
      request.expiration=new_expiration;
     }
   else
      request.type_time=ORDER_TIME_GTC;

   const string operation=StringFormat("MODIFY order #%I64u",ticket);
   if(!m_execution.Send(request,operation,report))
      return(false);

   m_orders_modified++;
   Refresh();
   return(true);
  }
//+------------------------------------------------------------------+
bool COrderManager::DeletePendingOrder(const ulong ticket,SExecutionReport &report)
  {
   report.Reset();

   if(!IsOurOrder(ticket))
     {
      //--- Refusing to touch a foreign order is a hard safety rule, not
      //--- a convenience: deleting another EA's pending order is
      //--- unrecoverable for the user.
      report.failure_detail=StringFormat("order #%I64u is not ours; refusing to delete",ticket);
      m_id.Warn(report.failure_detail);
      return(false);
     }

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_REMOVE;
   request.order  = ticket;

   const string operation=StringFormat("DELETE order #%I64u",ticket);
   if(!m_execution.Send(request,operation,report))
      return(false);

   m_orders_deleted++;
   Refresh();
   return(true);
  }
//+------------------------------------------------------------------+
int COrderManager::DeleteAllPendingOrders(void)
  {
   Refresh();
   int deleted=0;
   //--- Iterate over a snapshot backwards: the live order list mutates
   //--- as deletions are confirmed.
   const int total=ArraySize(m_orders);
   ulong tickets[];
   ArrayResize(tickets,total);
   for(int i=0;i<total;i++)
      tickets[i]=m_orders[i].ticket;

   for(int i=total-1;i>=0;i--)
     {
      SExecutionReport report;
      if(DeletePendingOrder(tickets[i],report))
         deleted++;
     }
   if(deleted>0)
      m_id.Info(StringFormat("deleted %d of %d pending orders",deleted,total));
   return(deleted);
  }
//+------------------------------------------------------------------+
int COrderManager::DeletePendingOrdersByType(const ENUM_ORDER_TYPE type)
  {
   Refresh();
   const int total=ArraySize(m_orders);
   ulong tickets[];
   int matched=0;
   ArrayResize(tickets,total);
   for(int i=0;i<total;i++)
     {
      if(m_orders[i].type!=type)
         continue;
      tickets[matched]=m_orders[i].ticket;
      matched++;
     }

   int deleted=0;
   for(int i=matched-1;i>=0;i--)
     {
      SExecutionReport report;
      if(DeletePendingOrder(tickets[i],report))
         deleted++;
     }
   return(deleted);
  }
//+------------------------------------------------------------------+
bool COrderManager::ReadOrder(const ulong ticket,SPendingOrderInfo &out) const
  {
   out.Reset();
   if(!OrderSelect(ticket))
      return(false);

   const long magic=(long)OrderGetInteger(ORDER_MAGIC);
   //--- Ownership is decided in exactly one place.
   if(!m_magic.IsOurs(magic))
      return(false);
   if(OrderGetString(ORDER_SYMBOL)!=m_broker.Symbol())
      return(false);

   out.ticket           = ticket;
   out.symbol           = OrderGetString(ORDER_SYMBOL);
   out.magic            = magic;
   out.type             = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   out.volume_initial   = OrderGetDouble(ORDER_VOLUME_INITIAL);
   out.volume_current   = OrderGetDouble(ORDER_VOLUME_CURRENT);
   out.price_open       = OrderGetDouble(ORDER_PRICE_OPEN);
   out.price_stop_limit = OrderGetDouble(ORDER_PRICE_STOPLIMIT);
   out.stop_loss        = OrderGetDouble(ORDER_SL);
   out.take_profit      = OrderGetDouble(ORDER_TP);
   out.time_setup       = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
   out.time_expiration  = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
   out.state            = (ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
   out.comment          = OrderGetString(ORDER_COMMENT);
   return(true);
  }
//+------------------------------------------------------------------+
bool COrderManager::Refresh(void)
  {
   ArrayResize(m_orders,0);
   const int total=OrdersTotal();
   for(int i=0;i<total;i++)
     {
      const ulong ticket=OrderGetTicket(i);
      if(ticket==0)
         continue;
      SPendingOrderInfo info;
      if(!ReadOrder(ticket,info))
         continue;
      const int size=ArraySize(m_orders);
      if(ArrayResize(m_orders,size+1)!=size+1)
         return(false);
      m_orders[size]=info;
     }
   m_last_refresh=TimeCurrent();
   return(true);
  }
//+------------------------------------------------------------------+
bool COrderManager::At(const int index,SPendingOrderInfo &out) const
  {
   if(index<0 || index>=ArraySize(m_orders))
      return(false);
   out=m_orders[index];
   return(true);
  }
//+------------------------------------------------------------------+
bool COrderManager::FindByTicket(const ulong ticket,SPendingOrderInfo &out) const
  {
   const int total=ArraySize(m_orders);
   for(int i=0;i<total;i++)
      if(m_orders[i].ticket==ticket)
        {
         out=m_orders[i];
         return(true);
        }
   return(false);
  }
//+------------------------------------------------------------------+
int COrderManager::CountByType(const ENUM_ORDER_TYPE type) const
  {
   int count=0;
   const int total=ArraySize(m_orders);
   for(int i=0;i<total;i++)
      if(m_orders[i].type==type)
         count++;
   return(count);
  }
//+------------------------------------------------------------------+
bool COrderManager::IsOurOrder(const ulong ticket) const
  {
   if(!OrderSelect(ticket))
      return(false);
   return(m_magic.IsOurs((long)OrderGetInteger(ORDER_MAGIC)));
  }
//+------------------------------------------------------------------+
double COrderManager::TotalPendingVolume(void) const
  {
   double volume=0.0;
   const int total=ArraySize(m_orders);
   for(int i=0;i<total;i++)
      volume+=m_orders[i].volume_current;
   return(volume);
  }

#endif // SRP_TRADE_ENGINE_CORDERMANAGER_MQH
//+------------------------------------------------------------------+
