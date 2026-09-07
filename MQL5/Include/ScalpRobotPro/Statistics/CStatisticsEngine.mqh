//+------------------------------------------------------------------+
//|                                          CStatisticsEngine.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Statistics : collects trade records and publishes metrics.              |
//|                                                                  |
//|   RESPONSIBILITY (one only): maintain the trade record collection and     |
//|   the derived metrics. The arithmetic is delegated to                     |
//|   CPerformanceCalculator; the persistence to CTradeJournal.               |
//|                                                                  |
//|   IT IS AN OBSERVER, NOT A PARTICIPANT                                   |
//|   It learns about trades from SRP_EVENT_POSITION_CLOSED. The pipeline      |
//|   does not call it, does not know it exists, and does not slow down for    |
//|   it. Reporting can therefore be extended indefinitely without ever        |
//|   touching the trading path - which is precisely why the event bus         |
//|   exists.                                                               |
//|                                                                  |
//|   The record array is capacity-bounded: an EA running for a year must      |
//|   not grow memory without limit, so the oldest records roll off once       |
//|   their contribution to the aggregates has been folded in.                |
//+------------------------------------------------------------------+
#ifndef SRP_STATISTICS_CSTATISTICSENGINE_MQH
#define SRP_STATISTICS_CSTATISTICSENGINE_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IStateStore.mqh"
#include "../Core/Interfaces/IEventPublisher.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"
#include "CPerformanceCalculator.mqh"

class CTradeJournal;
class CEquityCurveTracker;

class CStatisticsEngine : public IModule
  {
private:
   CModuleIdentity      m_id;
   //--- Borrowed collaborators.
   IStateStore         *m_state;
   IEventPublisher     *m_publisher;
   IClock              *m_clock;
   CTradeJournal       *m_journal;
   CEquityCurveTracker *m_equity_curve;

   STradeRecord         m_records[];
   int                  m_capacity;
   SPerformanceMetrics  m_metrics;
   bool                 m_metrics_dirty;
   //--- Per-strategy attribution, so a user can see which strategy earns
   //--- and which merely trades.
   SPerformanceMetrics  m_by_strategy[5];

   //--- Reconstructs a full STradeRecord from a close event by reading
   //--- deal history for that position.
   bool              BuildRecordFromEvent(const SEventPayload &payload,
                                          STradeRecord &record) const;
   void              AppendRecord(const STradeRecord &record);
   void              RecomputeMetrics(void);

public:
                     CStatisticsEngine(IStateStore *state,
                                       IEventPublisher *publisher,
                                       IClock *clock,
                                       ILogger *logger);
                    ~CStatisticsEngine(void);

   void              SetJournal(CTradeJournal *journal);
   void              SetEquityCurveTracker(CEquityCurveTracker *tracker);
   void              SetCapacity(const int capacity);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;

   //--- Bus entry point via CEventListenerAdapter.
   virtual void      HandleEvent(const SEventPayload &payload) override;

   //--- Metrics are recomputed lazily, so a burst of closes costs one
   //--- recomputation rather than one per trade.
   void              GetMetrics(SPerformanceMetrics &out);
   void              GetMetricsForStrategy(const ENUM_SRP_STRATEGY_ID id,
                                           SPerformanceMetrics &out);

   int               RecordCount(void) const { return(ArraySize(m_records)); }
   bool              GetRecord(const int index,STradeRecord &out) const;

   //--- Consumed by COptimizationCriterion at the end of a tester pass.
   void              GetAllRecords(STradeRecord &out[]) const;
  };

#endif // SRP_STATISTICS_CSTATISTICSENGINE_MQH
//+------------------------------------------------------------------+
