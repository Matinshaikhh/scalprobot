//+------------------------------------------------------------------+
//|                                    CTradeTransactionRouter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Trade : interprets OnTradeTransaction and publishes domain events.     |
//|                                                                  |
//|   RESPONSIBILITY (one only): translate raw MqlTradeTransaction traffic   |
//|   into meaningful domain events (position opened, closed, partially      |
//|   closed, stops modified).                                              |
//|                                                                  |
//|   WHY THIS CLASS IS ESSENTIAL                                           |
//|   OnTradeTransaction is the only reliable notification that a position   |
//|   closed because its stop was hit - no polling loop can catch that       |
//|   without a race. But the raw callback is noisy: several transactions    |
//|   arrive per logical event, ordering is not guaranteed, and DEAL_ENTRY   |
//|   must be inspected to tell an open from a close from a reversal.        |
//|   Concentrating that interpretation here means the statistics engine,    |
//|   journal and guards all receive clean, deduplicated events.            |
//|                                                                  |
//|   Deduplication is explicit: processed deal tickets are remembered so a  |
//|   repeated notification cannot double-count a trade in the statistics.   |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_CTRADETRANSACTIONROUTER_MQH
#define SRP_TRADE_CTRADETRANSACTIONROUTER_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IEventPublisher.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CSymbolInfoProvider;

class CTradeTransactionRouter : public IModule
  {
private:
   CModuleIdentity      m_id;
   IEventPublisher     *m_publisher;       // borrowed
   IClock              *m_clock;           // borrowed
   CSymbolInfoProvider *m_symbol_info;     // borrowed
   long                 m_magic;

   //--- Ring of recently processed deal tickets, for deduplication.
   ulong                m_processed_deals[];
   int                  m_dedup_capacity;
   int                  m_dedup_cursor;
   long                 m_transaction_count;
   long                 m_ignored_count;

   bool              IsOurs(const ulong magic,const string symbol) const;
   bool              WasProcessed(const ulong deal_ticket) const;
   void              MarkProcessed(const ulong deal_ticket);

   //--- One handler per transaction meaning.
   void              HandleDealAdd(const MqlTradeTransaction &transaction);
   void              HandleOrderUpdate(const MqlTradeTransaction &transaction);
   void              HandleRequestResult(const MqlTradeRequest &request,
                                         const MqlTradeResult &result);

   //--- Builds and publishes the closed-trade record that feeds the
   //--- statistics engine and the journal.
   void              PublishClosedTrade(const ulong deal_ticket,
                                        const ulong position_ticket);

public:
                     CTradeTransactionRouter(IEventPublisher *publisher,
                                             IClock *clock,
                                             CSymbolInfoProvider *symbol_info,
                                             const long magic,
                                             ILogger *logger);
                    ~CTradeTransactionRouter(void);

   void              SetDedupCapacity(const int capacity);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Terminal entry point, forwarded by CTradingEngine.
   void              Route(const MqlTradeTransaction &transaction,
                           const MqlTradeRequest &request,
                           const MqlTradeResult &result);

   long              TransactionCount(void) const { return(m_transaction_count); }
  };

#endif // SRP_TRADE_CTRADETRANSACTIONROUTER_MQH
//+------------------------------------------------------------------+
