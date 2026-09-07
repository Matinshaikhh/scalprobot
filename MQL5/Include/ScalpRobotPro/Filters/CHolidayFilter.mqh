//+------------------------------------------------------------------+
//|                                             CHolidayFilter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Filters : blocks trading on illiquid holiday dates.                    |
//|                                                                  |
//|   Holiday liquidity is the quiet account-killer for scalpers: spreads    |
//|   widen, slippage triples, and the strategy's statistical assumptions    |
//|   no longer hold, all without any obvious signal on the chart.           |
//|                                                                  |
//|   Dates are supplied as a configuration string and parsed once at init,  |
//|   so no hard-coded calendar goes stale.                                 |
//+------------------------------------------------------------------+
#ifndef SRP_FILTERS_CHOLIDAYFILTER_MQH
#define SRP_FILTERS_CHOLIDAYFILTER_MQH

#include "../Core/Base/CFilterBase.mqh"

class CHolidayFilter : public CFilterBase
  {
private:
   //--- Parsed holiday dates, stored as day-start timestamps.
   datetime          m_holidays[];
   //--- Optional partial-day blocks (half-days before a holiday).
   int               m_block_minutes_before;
   int               m_block_minutes_after;
   bool              m_block_year_end;      // the illiquid final week

   bool              IsHolidayDate(const datetime moment) const;
   bool              IsYearEndPeriod(const datetime moment) const;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const ENUM_SRP_SIGNAL_DIRECTION direction,
                                SFilterVerdict &verdict) override;

public:
                     CHolidayFilter(ILogger *logger);
                    ~CHolidayFilter(void);

   //--- Accepts "YYYY.MM.DD;YYYY.MM.DD;..." and reports how many parsed,
   //--- so a malformed list is visible at startup rather than silently
   //--- leaving the filter inert.
   int               LoadFromString(const string date_list);
   void              SetSurroundingBlock(const int minutes_before,
                                         const int minutes_after);
   void              SetBlockYearEnd(const bool value);

   int               HolidayCount(void) const { return(ArraySize(m_holidays)); }
  };

#endif // SRP_FILTERS_CHOLIDAYFILTER_MQH
//+------------------------------------------------------------------+
