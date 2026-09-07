//+------------------------------------------------------------------+
//|                                     CTradingScheduleFilter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Filters : per-weekday user-defined trading hours.                      |
//|                                                                  |
//|   Distinct from CSessionFilter: sessions are a market fact, a schedule   |
//|   is a user preference. Keeping them apart means a user can trade "only  |
//|   London" AND "only 09:00-17:00 Mon-Thu" without either rule knowing     |
//|   about the other.                                                      |
//|                                                                  |
//|   Also owns the Friday early close, which protects against holding       |
//|   through the weekend gap.                                              |
//+------------------------------------------------------------------+
#ifndef SRP_FILTERS_CTRADINGSCHEDULEFILTER_MQH
#define SRP_FILTERS_CTRADINGSCHEDULEFILTER_MQH

#include "../Core/Base/CFilterBase.mqh"

//+------------------------------------------------------------------+
//| One weekday's trading window.                                     |
//+------------------------------------------------------------------+
struct SDaySchedule
  {
   bool              enabled;
   int               start_minutes;
   int               end_minutes;

                     SDaySchedule(void)
     : enabled(false),
       start_minutes(0),
       end_minutes(1440)
     {
     }
  };

class CTradingScheduleFilter : public CFilterBase
  {
private:
   //--- Indexed 0..6 == Sunday..Saturday, matching MqlDateTime.
   SDaySchedule      m_schedule[7];
   int               m_friday_close_minutes;   // stop N minutes early
   bool              m_block_weekend;

protected:
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const ENUM_SRP_SIGNAL_DIRECTION direction,
                                SFilterVerdict &verdict) override;

public:
                     CTradingScheduleFilter(ILogger *logger);
                    ~CTradingScheduleFilter(void) { }

   //--- 'day_of_week' 0 == Sunday. Windows may wrap midnight.
   void              SetDaySchedule(const int day_of_week,
                                    const bool enabled,
                                    const int start_minutes,
                                    const int end_minutes);
   void              SetFridayCloseMinutes(const int minutes_before_midnight);
   void              SetBlockWeekend(const bool value);

   bool              IsDayEnabled(const int day_of_week) const;
  };

#endif // SRP_FILTERS_CTRADINGSCHEDULEFILTER_MQH
//+------------------------------------------------------------------+
