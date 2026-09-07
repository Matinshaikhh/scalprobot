//+------------------------------------------------------------------+
//|                                      CTradeFrequencyFilter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Filters : throttles how often the EA may enter.                        |
//|                                                                  |
//|   Guards against the pathological case where a signal condition stays    |
//|   true for many consecutive ticks and the EA opens a cluster of nearly   |
//|   identical positions - the fastest way to turn one bad idea into        |
//|   twenty correlated losses.                                             |
//|                                                                  |
//|   Enforces a cool-down between trades, an hourly cap and a daily cap.    |
//|   Counts come from the event bus and the session statistics, so this     |
//|   filter never queries trade history itself.                            |
//+------------------------------------------------------------------+
#ifndef SRP_FILTERS_CTRADEFREQUENCYFILTER_MQH
#define SRP_FILTERS_CTRADEFREQUENCYFILTER_MQH

#include "../Core/Base/CFilterBase.mqh"

class CPositionRepository;

class CTradeFrequencyFilter : public CFilterBase
  {
private:
   CPositionRepository *m_positions;       // borrowed
   int               m_min_seconds_between_trades;
   int               m_max_trades_per_hour;
   int               m_max_trades_per_day;
   //--- Rolling hourly window of entry timestamps.
   datetime          m_recent_entries[];
   int               m_entry_capacity;
   int               m_entry_cursor;
   datetime          m_last_entry_time;

   int               CountEntriesWithin(const datetime now,
                                        const int seconds) const;
   void              RecordEntry(const datetime moment);

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const ENUM_SRP_SIGNAL_DIRECTION direction,
                                SFilterVerdict &verdict) override;

public:
                     CTradeFrequencyFilter(CPositionRepository *positions,
                                           ILogger *logger);
                    ~CTradeFrequencyFilter(void);

   void              SetMinSecondsBetweenTrades(const int seconds);
   void              SetHourlyLimit(const int max_trades);
   void              SetDailyLimit(const int max_trades);

   //--- Bus entry point: records entries as they are confirmed.
   virtual void      HandleEvent(const SEventPayload &payload) override;
  };

#endif // SRP_FILTERS_CTRADEFREQUENCYFILTER_MQH
//+------------------------------------------------------------------+
