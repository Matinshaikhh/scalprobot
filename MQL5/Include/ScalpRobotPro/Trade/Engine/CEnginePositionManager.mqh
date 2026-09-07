//+------------------------------------------------------------------+
//|                                      CEnginePositionManager.mqh |
//|                          Scalping Robot Pro - Core Trading Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): operate on POSITIONS that already        |
//|   exist - close, partially close, modify stops, reverse, close all.   |
//|                                                                  |
//|   NAMING NOTE                                                      |
//|   The architecture layer already defines a rule-driven               |
//|   CPositionManager (Trade/CPositionManager.mqh) whose job is to apply |
//|   IPositionRule objects. THIS class is the lower-level execution      |
//|   primitive it will call. Two different responsibilities, so two      |
//|   classes and two names rather than one overloaded god-object.        |
//|                                                                  |
//|   NETTING vs HEDGING - THE CRITICAL DISTINCTION                     |
//|   This is where account mode genuinely changes behaviour, not just    |
//|   configuration:                                                    |
//|                                                                  |
//|     HEDGING  one position per ticket. Closing means an opposing deal  |
//|              addressed to that specific position_ticket. Reversing    |
//|              means close-then-open, two separate deals.              |
//|                                                                  |
//|     NETTING  one aggregate position per symbol. There is no ticket    |
//|              to address. Closing means an opposing deal of equal      |
//|              volume with position=0. Reversing is a SINGLE deal of    |
//|              volume (current + target), which flips the net exposure  |
//|              in one operation - cheaper and with no window in which   |
//|              the account is unintentionally flat.                    |
//|                                                                  |
//|   Getting this wrong is why some EAs "close" a netting position and    |
//|   silently open a reversed one instead.                             |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_ENGINE_CENGINEPOSITIONMANAGER_MQH
#define SRP_TRADE_ENGINE_CENGINEPOSITIONMANAGER_MQH

#include "../../Core/Interfaces/IModule.mqh"
#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Core/Base/CModuleIdentity.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "CExecutionEngine.mqh"
#include "CBrokerManager.mqh"
#include "CMagicNumberManager.mqh"
#include "COrderManager.mqh"

//+------------------------------------------------------------------+
//| Live view of one position owned by this EA.                        |
//+------------------------------------------------------------------+
struct SEnginePosition
  {
   ulong              ticket;
   string             symbol;
   long               magic;
   ENUM_POSITION_TYPE type;
   double             volume;
   double             price_open;
   double             price_current;
   double             stop_loss;
   double             take_profit;
   double             profit;
   double             swap;
   double             commission;
   double             profit_points;
   datetime           time_open;
   int                age_seconds;
   string             comment;
   ulong              identifier;

                     SEnginePosition(void) { Reset(); }
   void              Reset(void)
     {
      ticket=SRP_INVALID_TICKET; symbol=""; magic=0;
      type=POSITION_TYPE_BUY; volume=0.0;
      price_open=0.0; price_current=0.0;
      stop_loss=0.0; take_profit=0.0;
      profit=0.0; swap=0.0; commission=0.0; profit_points=0.0;
      time_open=0; age_seconds=0; comment=""; identifier=0;
     }
   bool              IsBuy(void) const { return(type==POSITION_TYPE_BUY); }
   double            NetProfit(void) const { return(profit+swap+commission); }
  };

class CEnginePositionManager : public IModule
  {
private:
   CModuleIdentity      m_id;
   //--- All borrowed.
   CExecutionEngine    *m_execution;
   CBrokerManager      *m_broker;
   CMagicNumberManager *m_magic;
   COrderManager       *m_orders;

   SEnginePosition      m_positions[];
   datetime             m_last_refresh;
   long                 m_closes;
   long                 m_partial_closes;
   long                 m_modifications;
   long                 m_reversals;

   bool              ReadPosition(const ulong ticket,SEnginePosition &out) const;
   //--- Builds the opposing deal that closes a position, honouring the
   //--- account mode.
   bool              BuildCloseRequest(const SEnginePosition &position,
                                       const double volume,
                                       MqlTradeRequest &request,
                                       const string comment_detail) const;

public:
                     CEnginePositionManager(CExecutionEngine *execution,
                                            CBrokerManager *broker,
                                            CMagicNumberManager *magic,
                                            COrderManager *orders,
                                            ILogger *logger);
                    ~CEnginePositionManager(void);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //=== CLOSE =======================================================
   bool              ClosePosition(const ulong ticket,
                                   const string reason_detail,
                                   SExecutionReport &report);
   //--- Partial close. Refuses to leave a remainder below the broker
   //--- minimum, because that produces an unmanageable stub position.
   bool              ClosePartial(const ulong ticket,
                                  const double volume_to_close,
                                  const string reason_detail,
                                  SExecutionReport &report);
   bool              ClosePartialByPercent(const ulong ticket,
                                           const double percent,
                                           const string reason_detail,
                                           SExecutionReport &report);

   //--- Bulk operations. Each returns how many positions actually closed
   //--- so a partial failure is visible rather than assumed.
   int               CloseAll(const string reason_detail);
   int               CloseSymbol(const string symbol,const string reason_detail);
   int               CloseByType(const ENUM_POSITION_TYPE type,
                                 const string reason_detail);
   int               CloseProfitable(const string reason_detail);
   int               CloseLosing(const string reason_detail);

   //=== MODIFY ======================================================
   //--- Skips no-op changes and respects the freeze level.
   bool              ModifyStops(const ulong ticket,
                                 const double new_stop_loss,
                                 const double new_take_profit,
                                 SExecutionReport &report);
   bool              RemoveStops(const ulong ticket,SExecutionReport &report);

   //=== REVERSE =====================================================
   //--- Flips a position's direction. On netting this is ONE deal; on
   //--- hedging it is close-then-open. 'new_volume' 0 keeps the existing
   //--- volume.
   bool              ReversePosition(const ulong ticket,
                                     const double new_volume,
                                     const double new_stop_loss,
                                     const double new_take_profit,
                                     const string reason_detail,
                                     SExecutionReport &report);

   //=== QUERIES =====================================================
   bool              Refresh(void);
   int               Count(void) const { return(ArraySize(m_positions)); }
   bool              At(const int index,SEnginePosition &out) const;
   bool              FindByTicket(const ulong ticket,SEnginePosition &out) const;
   int               CountByType(const ENUM_POSITION_TYPE type) const;
   double            TotalVolume(void) const;
   double            NetVolume(void) const;      // signed: buy positive
   double            FloatingProfit(void) const;
   bool              HasPosition(void) const { return(ArraySize(m_positions)>0); }
   //--- On netting there is at most one position per symbol; this
   //--- resolves it without the caller needing to know the mode.
   bool              GetNettedPosition(SEnginePosition &out) const;

   //--- Diagnostics --------------------------------------------------
   long              CloseCount(void)        const { return(m_closes); }
   long              PartialCloseCount(void) const { return(m_partial_closes); }
   long              ModifyCount(void)       const { return(m_modifications); }
   long              ReversalCount(void)     const { return(m_reversals); }
  };

//+------------------------------------------------------------------+
CEnginePositionManager::CEnginePositionManager(CExecutionEngine *execution,
                                               CBrokerManager *broker,
                                               CMagicNumberManager *magic,
                                               COrderManager *orders,
                                               ILogger *logger)
  : m_execution(execution),
    m_broker(broker),
    m_magic(magic),
    m_orders(orders),
    m_last_refresh(0),
    m_closes(0),
    m_partial_closes(0),
    m_modifications(0),
    m_reversals(0)
  {
   m_id.Configure("CEnginePositionManager",logger);
   ArrayResize(m_positions,0);
  }
//+------------------------------------------------------------------+
CEnginePositionManager::~CEnginePositionManager(void)
  {
   ArrayFree(m_positions);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::Initialize(void)
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
   m_id.Info(StringFormat("position manager ready in %s mode",
                          (m_broker.IsHedging() ? "HEDGING" : "NETTING")));
   m_id.SetInitialized(true);
   return(true);
  }
//+------------------------------------------------------------------+
void CEnginePositionManager::Validate(SValidationResult &result)
  {
   if(m_execution==NULL) result.AddError("CEnginePositionManager: execution engine not injected");
   if(m_broker==NULL)    result.AddError("CEnginePositionManager: broker manager not injected");
   if(m_magic==NULL)     result.AddError("CEnginePositionManager: magic manager not injected");
  }
//+------------------------------------------------------------------+
void CEnginePositionManager::Shutdown(void)
  {
   ArrayResize(m_positions,0);
   m_id.SetInitialized(false);
  }
//+------------------------------------------------------------------+
void CEnginePositionManager::ReportHealth(SHealthReport &report)
  {
   m_id.FillReport(report,m_last_refresh);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::ReadPosition(const ulong ticket,
                                          SEnginePosition &out) const
  {
   out.Reset();
   if(!PositionSelectByTicket(ticket))
      return(false);

   const long magic=(long)PositionGetInteger(POSITION_MAGIC);
   //--- OWNERSHIP GATE. Never operate on a position we do not own.
   if(!m_magic.IsOurs(magic))
      return(false);

   out.ticket        = ticket;
   out.symbol        = PositionGetString(POSITION_SYMBOL);
   out.magic         = magic;
   out.type          = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   out.volume        = PositionGetDouble(POSITION_VOLUME);
   out.price_open    = PositionGetDouble(POSITION_PRICE_OPEN);
   out.price_current = PositionGetDouble(POSITION_PRICE_CURRENT);
   out.stop_loss     = PositionGetDouble(POSITION_SL);
   out.take_profit   = PositionGetDouble(POSITION_TP);
   out.profit        = PositionGetDouble(POSITION_PROFIT);
   out.swap          = PositionGetDouble(POSITION_SWAP);
   out.comment       = PositionGetString(POSITION_COMMENT);
   out.identifier    = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   out.time_open     = (datetime)PositionGetInteger(POSITION_TIME);
   out.age_seconds   = (int)(TimeCurrent()-out.time_open);

   //--- Profit in points, direction-aware.
   const double delta=(out.IsBuy() ? out.price_current-out.price_open
                                   : out.price_open-out.price_current);
   out.profit_points=m_broker.PriceToPoints(delta);
   return(true);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::Refresh(void)
  {
   ArrayResize(m_positions,0);
   const int total=PositionsTotal();
   for(int i=0;i<total;i++)
     {
      const ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;
      SEnginePosition info;
      if(!ReadPosition(ticket,info))
         continue;
      const int size=ArraySize(m_positions);
      if(ArrayResize(m_positions,size+1)!=size+1)
         return(false);
      m_positions[size]=info;
     }
   m_last_refresh=TimeCurrent();
   return(true);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::BuildCloseRequest(const SEnginePosition &position,
                                               const double volume,
                                               MqlTradeRequest &request,
                                               const string comment_detail) const
  {
   MqlTick tick;
   if(!m_broker.GetTick(tick))
      return(false);
   if(tick.bid<=0.0 || tick.ask<=0.0)
      return(false);

   ZeroMemory(request);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = position.symbol;
   request.volume = volume;

   //--- A long is closed by SELLING at bid; a short by BUYING at ask.
   if(position.IsBuy())
     {
      request.type  = ORDER_TYPE_SELL;
      request.price = m_broker.NormalizePrice(tick.bid);
     }
   else
     {
      request.type  = ORDER_TYPE_BUY;
      request.price = m_broker.NormalizePrice(tick.ask);
     }

   request.deviation    = (ulong)m_broker.StopsLevel();
   request.magic        = position.magic;
   request.type_filling = m_broker.FillingMode();
   request.comment      = m_magic.BuildComment(comment_detail);

   //--- THE ACCOUNT-MODE DISTINCTION.
   //--- Hedging: address the specific position. Omitting this field
   //--- would open an opposing position instead of closing this one.
   //--- Netting: there is no addressable ticket; an opposing deal of
   //--- equal volume nets the exposure to zero.
   if(m_broker.IsHedging())
      request.position=position.ticket;
   else
      request.position=0;

   return(true);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::ClosePosition(const ulong ticket,
                                           const string reason_detail,
                                           SExecutionReport &report)
  {
   report.Reset();

   SEnginePosition position;
   if(!ReadPosition(ticket,position))
     {
      report.failure_detail=StringFormat("position #%I64u not found or not ours",ticket);
      m_id.Warn(report.failure_detail);
      return(false);
     }

   //--- The freeze level makes closing temporarily impossible; retrying
   //--- inside it cannot succeed, so the caller is told to wait.
   const double reference=(position.IsBuy() ? m_broker.Bid() : m_broker.Ask());
   if(position.stop_loss>0.0 &&
      m_broker.IsInsideFreezeLevel(reference,position.stop_loss))
     {
      report.failure_detail="position is inside the broker freeze level";
      m_id.Warn(StringFormat("close #%I64u deferred: %s",ticket,report.failure_detail));
      return(false);
     }

   MqlTradeRequest request;
   if(!BuildCloseRequest(position,position.volume,request,reason_detail))
     {
      report.failure_detail="cannot build close request (no tick data)";
      m_id.Error(report.failure_detail);
      return(false);
     }

   const string operation=StringFormat("CLOSE #%I64u %.4f %s",
                                       ticket,position.volume,
                                       (position.IsBuy() ? "BUY" : "SELL"));
   if(!m_execution.Send(request,operation,report))
      return(false);

   m_closes++;
   Refresh();
   return(true);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::ClosePartial(const ulong ticket,
                                          const double volume_to_close,
                                          const string reason_detail,
                                          SExecutionReport &report)
  {
   report.Reset();

   SEnginePosition position;
   if(!ReadPosition(ticket,position))
     {
      report.failure_detail=StringFormat("position #%I64u not found or not ours",ticket);
      m_id.Warn(report.failure_detail);
      return(false);
     }

   double close_volume=m_broker.NormalizeVolume(volume_to_close);
   if(close_volume<=0.0)
     {
      report.failure_detail=StringFormat("close volume %.4f normalises to zero",
                                         volume_to_close);
      m_id.Warn(report.failure_detail);
      return(false);
     }

   //--- Closing the whole thing is a full close, not a partial one.
   if(close_volume>=position.volume-SRP_EPSILON)
      return(ClosePosition(ticket,reason_detail,report));

   //--- THE REMAINDER MUST REMAIN LEGAL. Leaving a stub below the broker
   //--- minimum creates a position that can never be closed or managed
   //--- normally, which is far worse than declining the partial close.
   const double remainder=position.volume-close_volume;
   if(remainder<m_broker.VolumeMin()-SRP_EPSILON)
     {
      report.failure_detail=StringFormat(
         "partial close would leave %.4f, below broker minimum %.4f; "
         "close fully instead",remainder,m_broker.VolumeMin());
      m_id.Warn(report.failure_detail);
      return(false);
     }

   MqlTradeRequest request;
   if(!BuildCloseRequest(position,close_volume,request,reason_detail))
     {
      report.failure_detail="cannot build partial close request";
      m_id.Error(report.failure_detail);
      return(false);
     }

   const string operation=StringFormat("PARTIAL CLOSE #%I64u %.4f of %.4f",
                                       ticket,close_volume,position.volume);
   if(!m_execution.Send(request,operation,report))
      return(false);

   m_partial_closes++;
   Refresh();
   return(true);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::ClosePartialByPercent(const ulong ticket,
                                                   const double percent,
                                                   const string reason_detail,
                                                   SExecutionReport &report)
  {
   report.Reset();
   if(percent<=0.0 || percent>=100.0)
     {
      report.failure_detail=StringFormat("percent %.2f out of range (0..100)",percent);
      m_id.Warn(report.failure_detail);
      return(false);
     }
   SEnginePosition position;
   if(!ReadPosition(ticket,position))
     {
      report.failure_detail=StringFormat("position #%I64u not found or not ours",ticket);
      return(false);
     }
   return(ClosePartial(ticket,position.volume*percent/100.0,reason_detail,report));
  }
//+------------------------------------------------------------------+
int CEnginePositionManager::CloseAll(const string reason_detail)
  {
   Refresh();
   const int total=ArraySize(m_positions);
   if(total==0)
      return(0);

   //--- Snapshot the tickets first: the live list mutates as closes are
   //--- confirmed, and iterating a mutating collection skips entries.
   ulong tickets[];
   ArrayResize(tickets,total);
   for(int i=0;i<total;i++)
      tickets[i]=m_positions[i].ticket;

   int closed=0;
   for(int i=0;i<total;i++)
     {
      SExecutionReport report;
      if(ClosePosition(tickets[i],reason_detail,report))
         closed++;
     }

   //--- Report honestly. A partial failure here is operationally
   //--- important: the operator must know exposure remains.
   if(closed<total)
      m_id.Warn(StringFormat("CloseAll: closed %d of %d positions; %d remain",
                             closed,total,total-closed));
   else
      m_id.Info(StringFormat("CloseAll: closed all %d positions (%s)",
                             closed,reason_detail));
   return(closed);
  }
//+------------------------------------------------------------------+
int CEnginePositionManager::CloseSymbol(const string symbol,
                                        const string reason_detail)
  {
   Refresh();
   const int total=ArraySize(m_positions);
   ulong tickets[];
   int matched=0;
   ArrayResize(tickets,total);
   for(int i=0;i<total;i++)
     {
      if(m_positions[i].symbol!=symbol)
         continue;
      tickets[matched]=m_positions[i].ticket;
      matched++;
     }

   int closed=0;
   for(int i=0;i<matched;i++)
     {
      SExecutionReport report;
      if(ClosePosition(tickets[i],reason_detail,report))
         closed++;
     }
   if(matched>0)
      m_id.Info(StringFormat("CloseSymbol %s: closed %d of %d",symbol,closed,matched));
   return(closed);
  }
//+------------------------------------------------------------------+
int CEnginePositionManager::CloseByType(const ENUM_POSITION_TYPE type,
                                        const string reason_detail)
  {
   Refresh();
   const int total=ArraySize(m_positions);
   ulong tickets[];
   int matched=0;
   ArrayResize(tickets,total);
   for(int i=0;i<total;i++)
     {
      if(m_positions[i].type!=type)
         continue;
      tickets[matched]=m_positions[i].ticket;
      matched++;
     }

   int closed=0;
   for(int i=0;i<matched;i++)
     {
      SExecutionReport report;
      if(ClosePosition(tickets[i],reason_detail,report))
         closed++;
     }
   return(closed);
  }
//+------------------------------------------------------------------+
int CEnginePositionManager::CloseProfitable(const string reason_detail)
  {
   Refresh();
   const int total=ArraySize(m_positions);
   ulong tickets[];
   int matched=0;
   ArrayResize(tickets,total);
   for(int i=0;i<total;i++)
     {
      if(m_positions[i].NetProfit()<=0.0)
         continue;
      tickets[matched]=m_positions[i].ticket;
      matched++;
     }

   int closed=0;
   for(int i=0;i<matched;i++)
     {
      SExecutionReport report;
      if(ClosePosition(tickets[i],reason_detail,report))
         closed++;
     }
   return(closed);
  }
//+------------------------------------------------------------------+
int CEnginePositionManager::CloseLosing(const string reason_detail)
  {
   Refresh();
   const int total=ArraySize(m_positions);
   ulong tickets[];
   int matched=0;
   ArrayResize(tickets,total);
   for(int i=0;i<total;i++)
     {
      if(m_positions[i].NetProfit()>=0.0)
         continue;
      tickets[matched]=m_positions[i].ticket;
      matched++;
     }

   int closed=0;
   for(int i=0;i<matched;i++)
     {
      SExecutionReport report;
      if(ClosePosition(tickets[i],reason_detail,report))
         closed++;
     }
   return(closed);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::ModifyStops(const ulong ticket,
                                         const double new_stop_loss,
                                         const double new_take_profit,
                                         SExecutionReport &report)
  {
   report.Reset();

   SEnginePosition position;
   if(!ReadPosition(ticket,position))
     {
      report.failure_detail=StringFormat("position #%I64u not found or not ours",ticket);
      m_id.Warn(report.failure_detail);
      return(false);
     }

   double sl=(new_stop_loss>0.0   ? m_broker.NormalizePrice(new_stop_loss)   : 0.0);
   double tp=(new_take_profit>0.0 ? m_broker.NormalizePrice(new_take_profit) : 0.0);

   //--- NO-OP SUPPRESSION. Trailing stops call this on every tick; without
   //--- this check a busy M1 stream issues thousands of pointless
   //--- modifications an hour, which brokers throttle and which shows up
   //--- to the user as unexplained latency.
   const double tolerance=m_broker.TickSize()*0.5;
   if(MathAbs(sl-position.stop_loss)<tolerance &&
      MathAbs(tp-position.take_profit)<tolerance)
     {
      report.success=true;
      report.retcode_text="no change required";
      return(true);
     }

   //--- Validate distance from the CURRENT market price, which is what
   //--- the server measures against.
   const double reference=position.price_current;
   SBrokerCheckResult check;
   if(sl>0.0 && !m_broker.CheckStopDistance(reference,sl,check))
     {
      report.failure_detail="stop loss too close: "+check.detail;
      m_id.Warn(report.failure_detail);
      return(false);
     }
   if(tp>0.0 && !m_broker.CheckStopDistance(reference,tp,check))
     {
      report.failure_detail="take profit too close: "+check.detail;
      m_id.Warn(report.failure_detail);
      return(false);
     }

   //--- Inside the freeze level the server refuses modification, so
   //--- skip rather than burn retries against a certain rejection.
   if(m_broker.IsInsideFreezeLevel(reference,(sl>0.0 ? sl : tp)))
     {
      report.failure_detail="level inside broker freeze zone; modification deferred";
      m_id.Debug(report.failure_detail);
      return(false);
     }

   //--- Verify the levels are on the correct side of the market. This
   //--- catches sign errors in calculators before the server does.
   if(sl>0.0)
     {
      if(position.IsBuy() && sl>=position.price_current)
        {
         report.failure_detail="buy stop loss must be below current price";
         m_id.Error(report.failure_detail);
         return(false);
        }
      if(!position.IsBuy() && sl<=position.price_current)
        {
         report.failure_detail="sell stop loss must be above current price";
         m_id.Error(report.failure_detail);
         return(false);
        }
     }

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action   = TRADE_ACTION_SLTP;
   request.symbol   = position.symbol;
   request.sl       = sl;
   request.tp       = tp;
   //--- Required on hedging accounts to address the specific position.
   //--- Harmless on netting, where there is only one.
   request.position = ticket;
   request.magic    = position.magic;

   const string operation=StringFormat("MODIFY #%I64u SL=%.*f TP=%.*f",
                                       ticket,
                                       m_broker.Digits(),sl,
                                       m_broker.Digits(),tp);
   if(!m_execution.Send(request,operation,report))
      return(false);

   m_modifications++;
   Refresh();
   return(true);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::RemoveStops(const ulong ticket,
                                         SExecutionReport &report)
  {
   report.Reset();
   SEnginePosition position;
   if(!ReadPosition(ticket,position))
     {
      report.failure_detail=StringFormat("position #%I64u not found or not ours",ticket);
      return(false);
     }

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action   = TRADE_ACTION_SLTP;
   request.symbol   = position.symbol;
   request.sl       = 0.0;
   request.tp       = 0.0;
   request.position = ticket;
   request.magic    = position.magic;

   const string operation=StringFormat("REMOVE STOPS #%I64u",ticket);
   if(!m_execution.Send(request,operation,report))
      return(false);

   m_modifications++;
   Refresh();
   return(true);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::ReversePosition(const ulong ticket,
                                             const double new_volume,
                                             const double new_stop_loss,
                                             const double new_take_profit,
                                             const string reason_detail,
                                             SExecutionReport &report)
  {
   report.Reset();

   SEnginePosition position;
   if(!ReadPosition(ticket,position))
     {
      report.failure_detail=StringFormat("position #%I64u not found or not ours",ticket);
      m_id.Warn(report.failure_detail);
      return(false);
     }

   const double target_volume=
      m_broker.NormalizeVolume(new_volume>0.0 ? new_volume : position.volume);
   if(target_volume<=0.0)
     {
      report.failure_detail="target volume normalises to zero";
      m_id.Error(report.failure_detail);
      return(false);
     }

   const ENUM_SRP_SIGNAL_DIRECTION new_direction=
      (position.IsBuy() ? SRP_SIGNAL_SELL : SRP_SIGNAL_BUY);
   const ENUM_ORDER_TYPE new_order_type=
      (position.IsBuy() ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);

   //=== NETTING: a single deal flips the exposure ====================
   if(m_broker.IsNetting())
     {
      //--- Volume must cover closing the existing position AND opening
      //--- the new one. One deal, so there is no window in which the
      //--- account is unintentionally flat, and only one commission.
      const double combined=m_broker.NormalizeVolume(position.volume+target_volume);
      if(combined<=0.0)
        {
         report.failure_detail="combined reversal volume normalises to zero";
         m_id.Error(report.failure_detail);
         return(false);
        }

      MqlTick tick;
      if(!m_broker.GetTick(tick))
        {
         report.failure_detail="no tick data for reversal";
         return(false);
        }
      const double price=m_broker.NormalizePrice(
         new_direction==SRP_SIGNAL_BUY ? tick.ask : tick.bid);

      //--- Margin is checked on the combined volume, which is what the
      //--- server will actually require.
      SBrokerCheckResult check;
      if(!m_broker.CheckCanOpen(new_order_type,combined,price,check))
        {
         report.failure_detail=check.detail;
         m_id.Warn("reversal refused: "+check.detail);
         return(false);
        }

      //--- Reuse the order manager's clamping so both paths apply the
      //--- identical broker rule.
      double sl=new_stop_loss;
      double tp=new_take_profit;
      if(m_orders!=NULL)
         m_orders.ClampProtectiveLevels(new_order_type,price,sl,tp);
      else
        {
         sl=(sl>0.0 ? m_broker.NormalizePrice(sl) : 0.0);
         tp=(tp>0.0 ? m_broker.NormalizePrice(tp) : 0.0);
        }

      MqlTradeRequest request;
      ZeroMemory(request);
      request.action   = TRADE_ACTION_DEAL;
      request.symbol   = position.symbol;
      request.type     = new_order_type;
      request.volume   = combined;
      request.price    = price;
      request.sl       = sl;
      request.tp       = tp;
      request.position = 0;               // netting: no ticket to address
      m_execution.PrepareCommonFields(request,reason_detail);

      const string operation=StringFormat(
         "REVERSE(netting) #%I64u %.4f -> %s %.4f (deal %.4f)",
         ticket,position.volume,
         (new_direction==SRP_SIGNAL_BUY ? "BUY" : "SELL"),
         target_volume,combined);

      if(!m_execution.Send(request,operation,report))
         return(false);

      m_reversals++;
      Refresh();
      return(true);
     }

   //=== HEDGING: close, then open ====================================
   //--- Two deals are unavoidable here, and the order matters: closing
   //--- first frees the margin the new position needs.
   SExecutionReport close_report;
   if(!ClosePosition(ticket,"reverse-close:"+reason_detail,close_report))
     {
      report=close_report;
      report.failure_detail="reversal aborted: close leg failed - "+
                            close_report.failure_detail;
      m_id.Error(report.failure_detail);
      return(false);
     }

   SExecutionReport open_report;
   const bool opened=m_orders!=NULL &&
                     m_orders.SendMarketOrder(new_direction,target_volume,
                                              new_stop_loss,new_take_profit,
                                              "reverse-open:"+reason_detail,
                                              open_report,position.magic);
   if(!opened)
     {
      //--- The close succeeded but the open failed. The account is now
      //--- FLAT, not reversed. That is a materially different state, so
      //--- it is reported loudly rather than silently returning false.
      report=open_report;
      report.failure_detail=
         "REVERSAL INCOMPLETE: position closed but reopen failed - "
         "account is now flat on "+position.symbol+". "+open_report.failure_detail;
      m_id.Error(report.failure_detail);
      return(false);
     }

   report=open_report;
   m_reversals++;
   Refresh();
   m_id.Info(StringFormat("REVERSE(hedging) #%I64u complete -> %s %.4f",
                          ticket,
                          (new_direction==SRP_SIGNAL_BUY ? "BUY" : "SELL"),
                          target_volume));
   return(true);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::At(const int index,SEnginePosition &out) const
  {
   if(index<0 || index>=ArraySize(m_positions))
      return(false);
   out=m_positions[index];
   return(true);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::FindByTicket(const ulong ticket,
                                          SEnginePosition &out) const
  {
   const int total=ArraySize(m_positions);
   for(int i=0;i<total;i++)
      if(m_positions[i].ticket==ticket)
        {
         out=m_positions[i];
         return(true);
        }
   return(false);
  }
//+------------------------------------------------------------------+
bool CEnginePositionManager::GetNettedPosition(SEnginePosition &out) const
  {
   const int total=ArraySize(m_positions);
   for(int i=0;i<total;i++)
      if(m_positions[i].symbol==m_broker.Symbol())
        {
         out=m_positions[i];
         return(true);
        }
   return(false);
  }
//+------------------------------------------------------------------+
int CEnginePositionManager::CountByType(const ENUM_POSITION_TYPE type) const
  {
   int count=0;
   const int total=ArraySize(m_positions);
   for(int i=0;i<total;i++)
      if(m_positions[i].type==type)
         count++;
   return(count);
  }
//+------------------------------------------------------------------+
double CEnginePositionManager::TotalVolume(void) const
  {
   double volume=0.0;
   const int total=ArraySize(m_positions);
   for(int i=0;i<total;i++)
      volume+=m_positions[i].volume;
   return(volume);
  }
//+------------------------------------------------------------------+
double CEnginePositionManager::NetVolume(void) const
  {
   double net=0.0;
   const int total=ArraySize(m_positions);
   for(int i=0;i<total;i++)
      net+=(m_positions[i].IsBuy() ? m_positions[i].volume : -m_positions[i].volume);
   return(net);
  }
//+------------------------------------------------------------------+
double CEnginePositionManager::FloatingProfit(void) const
  {
   double profit=0.0;
   const int total=ArraySize(m_positions);
   for(int i=0;i<total;i++)
      profit+=m_positions[i].NetProfit();
   return(profit);
  }

#endif // SRP_TRADE_ENGINE_CENGINEPOSITIONMANAGER_MQH
//+------------------------------------------------------------------+
