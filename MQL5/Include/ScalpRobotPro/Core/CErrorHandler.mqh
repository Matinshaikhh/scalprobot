//+------------------------------------------------------------------+
//|                                                CErrorHandler.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : centralised policy for terminal/trade-server errors.      |
//|                                                                  |
//|   RESPONSIBILITY (one only): map an error code to an ACTION.       |
//|   It does not retry, log-and-forget or trade; it answers "what     |
//|   should the caller do about code N?" The executor then performs   |
//|   the retry, the engine performs the pause. Policy is separated    |
//|   from mechanism, so error handling is consistent everywhere and   |
//|   tunable in one file.                                            |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CERRORHANDLER_MQH
#define SRP_CORE_CERRORHANDLER_MQH

#include "Interfaces/ILogger.mqh"
#include "Interfaces/IEventPublisher.mqh"

class CErrorHandler
  {
private:
   ILogger          *m_logger;          // borrowed
   IEventPublisher  *m_publisher;       // borrowed
   int               m_error_count;
   int               m_consecutive_errors;
   uint              m_last_retcode;
   datetime          m_last_error_time;
   int               m_consecutive_threshold;

public:
                     CErrorHandler(void);
                    ~CErrorHandler(void) { }

   void              SetCollaborators(ILogger *logger,IEventPublisher *publisher);
   void              SetConsecutiveThreshold(const int threshold);

   //--- The core query: policy decision for a trade-server retcode.
   ENUM_SRP_ERROR_ACTION ClassifyTradeRetcode(const uint retcode) const;

   //--- Policy decision for a runtime (GetLastError) code.
   ENUM_SRP_ERROR_ACTION ClassifyRuntimeError(const int error_code) const;

   //--- Record an occurrence so the health monitor and circuit
   //--- breaker can see error pressure over time.
   void              RecordError(const string context,
                                 const string operation,
                                 const uint retcode,
                                 const datetime now);
   void              RecordSuccess(void);

   //--- True when errors are arriving faster than the threshold
   //--- allows, which the engine treats as a reason to pause.
   bool              IsErrorStormActive(void) const;

   //--- Human-readable decoding for logs and support tickets.
   static string     RetcodeToText(const uint retcode);
   static string     RuntimeErrorToText(const int error_code);

   //--- Diagnostics ------------------------------------------------
   int               ErrorCount(void)        const { return(m_error_count); }
   int               ConsecutiveErrors(void) const { return(m_consecutive_errors); }
   uint              LastRetcode(void)       const { return(m_last_retcode); }
   void              ResetCounters(void);
  };

//+------------------------------------------------------------------+
CErrorHandler::CErrorHandler(void)
  : m_logger(NULL),
    m_publisher(NULL),
    m_error_count(0),
    m_consecutive_errors(0),
    m_last_retcode(0),
    m_last_error_time(0),
    m_consecutive_threshold(5)
  {
  }
//+------------------------------------------------------------------+
void CErrorHandler::SetCollaborators(ILogger *logger,IEventPublisher *publisher)
  {
   m_logger=logger;
   m_publisher=publisher;
  }
//+------------------------------------------------------------------+
void CErrorHandler::SetConsecutiveThreshold(const int threshold)
  {
   if(threshold>0)
      m_consecutive_threshold=threshold;
  }
//+------------------------------------------------------------------+
//| THE RETRY POLICY TABLE                                            |
//|                                                                  |
//| The distinction that matters: a TRANSIENT condition is worth       |
//| retrying, a DETERMINISTIC rejection is not. Retrying "invalid      |
//| stops" forever produces a hung EA and a flood of server traffic;   |
//| failing instantly on a requote wastes a valid trading opportunity. |
//+------------------------------------------------------------------+
ENUM_SRP_ERROR_ACTION CErrorHandler::ClassifyTradeRetcode(const uint retcode) const
  {
   switch(retcode)
     {
      //--- Success codes need no action.
      case TRADE_RETCODE_DONE:
      case TRADE_RETCODE_DONE_PARTIAL:
      case TRADE_RETCODE_PLACED:
         return(SRP_ERROR_ACTION_IGNORE);

      //--- TRANSIENT: the price moved or the server was briefly busy.
      //--- Re-price and try again.
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_ERROR:
         return(SRP_ERROR_ACTION_RETRY);

      //--- Server is throttling or locked. Backing off and retrying is
      //--- correct, but the engine should slow down overall.
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
      case TRADE_RETCODE_LOCKED:
      case TRADE_RETCODE_FROZEN:
         return(SRP_ERROR_ACTION_RETRY);

      //--- DETERMINISTIC request faults. Retrying cannot help because
      //--- the request itself is wrong; it must be rebuilt.
      case TRADE_RETCODE_INVALID:
      case TRADE_RETCODE_INVALID_VOLUME:
      case TRADE_RETCODE_INVALID_PRICE:
      case TRADE_RETCODE_INVALID_STOPS:
      case TRADE_RETCODE_INVALID_EXPIRATION:
      case TRADE_RETCODE_INVALID_ORDER:
      case TRADE_RETCODE_INVALID_FILL:
      case TRADE_RETCODE_ORDER_CHANGED:
      case TRADE_RETCODE_POSITION_CLOSED:
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:
      case TRADE_RETCODE_LIMIT_ORDERS:
      case TRADE_RETCODE_LIMIT_VOLUME:
      case TRADE_RETCODE_REJECT:
         return(SRP_ERROR_ACTION_SKIP_TICK);

      //--- ACCOUNT-LEVEL problems. Continuing to send orders is
      //--- pointless and may look abusive to the broker, so the engine
      //--- pauses rather than skipping a single tick.
      case TRADE_RETCODE_NO_MONEY:
      case TRADE_RETCODE_NO_CHANGES:
      case TRADE_RETCODE_MARKET_CLOSED:
         return(SRP_ERROR_ACTION_PAUSE);

      //--- Trading has been switched off somewhere. Nothing will
      //--- succeed until a human intervenes.
      case TRADE_RETCODE_TRADE_DISABLED:
      case TRADE_RETCODE_SERVER_DISABLES_AT:
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
      case TRADE_RETCODE_LONG_ONLY:
      case TRADE_RETCODE_SHORT_ONLY:
      case TRADE_RETCODE_CLOSE_ONLY:
      case TRADE_RETCODE_FIFO_CLOSE:
      case TRADE_RETCODE_HEDGE_PROHIBITED:
         return(SRP_ERROR_ACTION_HALT);
     }
   //--- Unknown code: treat conservatively. Skipping is safer than
   //--- retrying something we do not understand.
   return(SRP_ERROR_ACTION_SKIP_TICK);
  }
//+------------------------------------------------------------------+
ENUM_SRP_ERROR_ACTION CErrorHandler::ClassifyRuntimeError(const int error_code) const
  {
   switch(error_code)
     {
      case ERR_SUCCESS:
         return(SRP_ERROR_ACTION_IGNORE);

      //--- Data not ready yet. Skipping this tick is exactly right:
      //--- the next one will usually have it.
      case ERR_HISTORY_NOT_FOUND:
      case ERR_INDICATOR_DATA_NOT_FOUND:
      case ERR_MARKET_UNKNOWN_SYMBOL:
      case ERR_CHART_NO_REPLY:
         return(SRP_ERROR_ACTION_SKIP_TICK);

      //--- Transient resource contention.
      case ERR_TOO_MANY_FILES:
         return(SRP_ERROR_ACTION_RETRY);

      //--- Programming faults. These indicate a bug, and continuing to
      //--- trade with a known-broken component is indefensible.
      case ERR_ARRAY_BAD_SIZE:
      case ERR_INVALID_ARRAY:
      case ERR_INVALID_POINTER:
      case ERR_WRONG_INTERNAL_PARAMETER:
      case ERR_INVALID_PARAMETER:
      case ERR_NOT_ENOUGH_MEMORY:
      case ERR_ZEROSIZE_ARRAY:
         return(SRP_ERROR_ACTION_HALT);

      //--- Trade context problems resolve on their own.
      case ERR_TRADE_DISABLED:
         return(SRP_ERROR_ACTION_PAUSE);
     }
   return(SRP_ERROR_ACTION_SKIP_TICK);
  }
//+------------------------------------------------------------------+
void CErrorHandler::RecordError(const string context,
                                const string operation,
                                const uint retcode,
                                const datetime now)
  {
   m_error_count++;
   m_consecutive_errors++;
   m_last_retcode=retcode;
   m_last_error_time=now;

   if(m_logger!=NULL)
      m_logger.Error(context,StringFormat("%s failed: retcode=%u (%s) [consecutive=%d]",
                                          operation,retcode,
                                          RetcodeToText(retcode),
                                          m_consecutive_errors));

   //--- Announce an error storm exactly once, at the crossing point,
   //--- so listeners are not spammed on every subsequent failure.
   if(m_publisher!=NULL && m_consecutive_errors==m_consecutive_threshold)
     {
      SEventPayload payload;
      payload.event_id      = SRP_EVENT_ERROR_RAISED;
      payload.timestamp     = now;
      payload.source_module = "CErrorHandler";
      payload.message       = StringFormat(
         "error storm: %d consecutive failures, last retcode %u",
         m_consecutive_errors,retcode);
      payload.integer_value = (long)retcode;
      m_publisher.Publish(payload);
     }
  }
//+------------------------------------------------------------------+
void CErrorHandler::RecordSuccess(void)
  {
   //--- A success breaks the streak. Only the CONSECUTIVE counter
   //--- resets; the lifetime total is preserved for diagnostics.
   m_consecutive_errors=0;
  }
//+------------------------------------------------------------------+
bool CErrorHandler::IsErrorStormActive(void) const
  {
   return(m_consecutive_errors>=m_consecutive_threshold);
  }
//+------------------------------------------------------------------+
void CErrorHandler::ResetCounters(void)
  {
   m_error_count=0;
   m_consecutive_errors=0;
   m_last_retcode=0;
   m_last_error_time=0;
  }
//+------------------------------------------------------------------+
string CErrorHandler::RetcodeToText(const uint retcode)
  {
   switch(retcode)
     {
      case TRADE_RETCODE_DONE:                  return("done");
      case TRADE_RETCODE_DONE_PARTIAL:          return("partial fill");
      case TRADE_RETCODE_PLACED:                return("order placed");
      case TRADE_RETCODE_REQUOTE:               return("requote");
      case TRADE_RETCODE_REJECT:                return("rejected");
      case TRADE_RETCODE_CANCEL:                return("cancelled by trader");
      case TRADE_RETCODE_ERROR:                 return("common error");
      case TRADE_RETCODE_TIMEOUT:               return("timeout");
      case TRADE_RETCODE_INVALID:               return("invalid request");
      case TRADE_RETCODE_INVALID_VOLUME:        return("invalid volume");
      case TRADE_RETCODE_INVALID_PRICE:         return("invalid price");
      case TRADE_RETCODE_INVALID_STOPS:         return("invalid stops");
      case TRADE_RETCODE_TRADE_DISABLED:        return("trading disabled");
      case TRADE_RETCODE_MARKET_CLOSED:         return("market closed");
      case TRADE_RETCODE_NO_MONEY:              return("insufficient funds");
      case TRADE_RETCODE_PRICE_CHANGED:         return("price changed");
      case TRADE_RETCODE_PRICE_OFF:             return("no quotes");
      case TRADE_RETCODE_INVALID_EXPIRATION:    return("invalid expiration");
      case TRADE_RETCODE_ORDER_CHANGED:         return("order state changed");
      case TRADE_RETCODE_TOO_MANY_REQUESTS:     return("too many requests");
      case TRADE_RETCODE_NO_CHANGES:            return("no changes requested");
      case TRADE_RETCODE_SERVER_DISABLES_AT:    return("autotrading disabled by server");
      case TRADE_RETCODE_CLIENT_DISABLES_AT:    return("autotrading disabled by client");
      case TRADE_RETCODE_LOCKED:                return("request locked");
      case TRADE_RETCODE_FROZEN:                return("order or position frozen");
      case TRADE_RETCODE_INVALID_FILL:          return("unsupported filling type");
      case TRADE_RETCODE_CONNECTION:            return("no connection");
      case TRADE_RETCODE_ONLY_REAL:             return("real accounts only");
      case TRADE_RETCODE_LIMIT_ORDERS:          return("order limit reached");
      case TRADE_RETCODE_LIMIT_VOLUME:          return("volume limit reached");
      case TRADE_RETCODE_INVALID_ORDER:         return("invalid or prohibited order type");
      case TRADE_RETCODE_POSITION_CLOSED:       return("position already closed");
      case TRADE_RETCODE_INVALID_CLOSE_VOLUME:  return("invalid close volume");
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:     return("closing order already exists");
      case TRADE_RETCODE_LIMIT_POSITIONS:       return("position limit reached");
      case TRADE_RETCODE_REJECT_CANCEL:         return("pending activation rejected");
      case TRADE_RETCODE_LONG_ONLY:             return("long positions only allowed");
      case TRADE_RETCODE_SHORT_ONLY:            return("short positions only allowed");
      case TRADE_RETCODE_CLOSE_ONLY:            return("close-only mode");
      case TRADE_RETCODE_FIFO_CLOSE:            return("FIFO close required");
      case TRADE_RETCODE_HEDGE_PROHIBITED:      return("opposite positions prohibited");
     }
   return("unknown retcode "+IntegerToString(retcode));
  }
//+------------------------------------------------------------------+
string CErrorHandler::RuntimeErrorToText(const int error_code)
  {
   switch(error_code)
     {
      case ERR_SUCCESS:                    return("no error");
      case ERR_INTERNAL_ERROR:             return("unexpected internal error");
      case ERR_NOT_ENOUGH_MEMORY:          return("not enough memory");
      case ERR_INVALID_POINTER:            return("invalid pointer");
      case ERR_INVALID_PARAMETER:          return("invalid parameter");
      case ERR_INVALID_ARRAY:              return("invalid array");
      case ERR_ARRAY_BAD_SIZE:             return("array resize failed");
      case ERR_ZEROSIZE_ARRAY:             return("zero-size array");
      case ERR_HISTORY_NOT_FOUND:          return("history not found");
      case ERR_INDICATOR_DATA_NOT_FOUND:   return("indicator data not ready");
      case ERR_MARKET_UNKNOWN_SYMBOL:      return("unknown symbol");
      case ERR_MARKET_NOT_SELECTED:        return("symbol not selected");
      case ERR_TRADE_DISABLED:             return("trading disabled");
      case ERR_TRADE_POSITION_NOT_FOUND:   return("position not found");
      case ERR_TRADE_ORDER_NOT_FOUND:      return("order not found");
      case ERR_TRADE_DEAL_NOT_FOUND:       return("deal not found");
      case ERR_TRADE_SEND_FAILED:          return("trade request send failed");
      case ERR_TOO_MANY_FILES:             return("too many open files");
      case ERR_CHART_NO_REPLY:             return("chart not responding");
     }
   return("runtime error "+IntegerToString(error_code));
  }

#endif // SRP_CORE_CERRORHANDLER_MQH
//+------------------------------------------------------------------+
