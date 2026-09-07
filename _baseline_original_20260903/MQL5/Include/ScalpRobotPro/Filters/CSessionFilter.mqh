//+------------------------------------------------------------------+
//|                                             CSessionFilter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Filters : restricts trading to permitted market sessions.              |
//|                                                                  |
//|   Delegates all "which session is it?" reasoning to CSessionCalendar     |
//|   and limits itself to "is that session permitted?". Two concerns,       |
//|   two classes: the calendar can be reused by the regime analyzer and     |
//|   the dashboard without dragging permission logic along.                 |
//+------------------------------------------------------------------+
#ifndef SRP_FILTERS_CSESSIONFILTER_MQH
#define SRP_FILTERS_CSESSIONFILTER_MQH

#include "../Core/Base/CFilterBase.mqh"

class CSessionCalendar;

class CSessionFilter : public CFilterBase
  {
private:
   CSessionCalendar *m_calendar;           // borrowed
   bool              m_allow_sydney;
   bool              m_allow_tokyo;
   bool              m_allow_london;
   bool              m_allow_newyork;
   bool              m_allow_overlap_only;
   //--- Session boundaries are volatile; skipping the first minutes
   //--- avoids the widest spreads of the day.
   int               m_skip_minutes_after_open;
   int               m_skip_minutes_before_close;

   bool              IsSessionPermitted(const ENUM_SRP_SESSION session) const;

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const ENUM_SRP_SIGNAL_DIRECTION direction,
                                SFilterVerdict &verdict) override;

public:
                     CSessionFilter(CSessionCalendar *calendar,ILogger *logger);
                    ~CSessionFilter(void) { }

   void              SetPermittedSessions(const bool sydney,const bool tokyo,
                                          const bool london,const bool newyork);
   void              SetOverlapOnly(const bool value);
   void              SetEdgeSkipMinutes(const int after_open,
                                        const int before_close);
  };

#endif // SRP_FILTERS_CSESSIONFILTER_MQH
//+------------------------------------------------------------------+
