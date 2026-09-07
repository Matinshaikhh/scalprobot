//+------------------------------------------------------------------+
//|                                         CSessionStatistics.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Statistics : per-day counters and the day-boundary reset.               |
//|                                                                  |
//|   RESPONSIBILITY (one only): maintain SDailyStatistics.                  |
//|                                                                  |
//|   Separated from CStatisticsEngine because daily figures have a           |
//|   lifecycle that lifetime figures do not - they reset. Mixing the two     |
//|   produces the bug where a reset also clears all-time history, or where   |
//|   the daily loss guard reads a lifetime number and never fires.           |
//|                                                                  |
//|   The day start and its opening balance are persisted, so a restart at    |
//|   midday resumes the same trading day rather than inventing a new one     |
//|   with a fresh loss budget.                                              |
//+------------------------------------------------------------------+
#ifndef SRP_STATISTICS_CSESSIONSTATISTICS_MQH
#define SRP_STATISTICS_CSESSIONSTATISTICS_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/IStateStore.mqh"
#include "../Core/Interfaces/IEventPublisher.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CSessionStatistics : public IModule
  {
private:
   CModuleIdentity   m_id;
   IClock           *m_clock;              // borrowed
   IStateStore      *m_state;              // borrowed
   IEventPublisher  *m_publisher;          // borrowed
   SDailyStatistics  m_daily;
   //--- Server hour at which the trading day rolls over. Configurable
   //--- because brokers differ and because a scalper may prefer to align
   //--- the day with a session rather than with midnight.
   int               m_day_start_hour;

   void              Persist(void);
   void              Restore(void);

public:
                     CSessionStatistics(IClock *clock,
                                        IStateStore *state,
                                        IEventPublisher *publisher,
                                        ILogger *logger);
                    ~CSessionStatistics(void) { }

   void              SetDayStartHour(const int hour);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;

   //--- Bus entry point: counts opens, closes, wins and losses.
   virtual void      HandleEvent(const SEventPayload &payload) override;

   //--- True when the server clock has crossed into a new trading day.
   //--- The engine polls this and rearms the latched guards on true.
   bool              IsNewTradingDay(void) const;

   //--- Starts a new day, capturing the opening balance and equity.
   void              BeginNewDay(const SAccountSnapshot &account);

   //--- Called once per pass to track intraday equity peak and trough.
   void              UpdateEquityTracking(const SAccountSnapshot &account);

   void              GetDaily(SDailyStatistics &out) const { out=m_daily; }
   datetime          DayStart(void) const { return(m_daily.day_start); }
  };

#endif // SRP_STATISTICS_CSESSIONSTATISTICS_MQH
//+------------------------------------------------------------------+
