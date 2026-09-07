//+------------------------------------------------------------------+
//|                                               CNewsWidget.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard/Widgets : blackout status and next event countdown.             |
//|                                                                  |
//|   Also surfaces the source-unavailable condition explicitly, so a user     |
//|   can tell "no news due" apart from "cannot read the calendar" - two very  |
//|   different situations that most EAs render identically.                  |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_WIDGETS_CNEWSWIDGET_MQH
#define SRP_DASHBOARD_WIDGETS_CNEWSWIDGET_MQH

#include "../../Core/Base/CWidgetBase.mqh"
#include "../CChartObjectPainter.mqh"
#include "../CDashboardTheme.mqh"

class CNewsWidget : public CWidgetBase
  {
private:
   CChartObjectPainter *m_painter;         // borrowed
   CDashboardTheme     *m_theme;           // borrowed
   int                  m_title_max_length;

protected:
   virtual bool      OnCreate(void) override;
   virtual void      OnRender(const CDashboardViewModel &model) override;

public:
                     CNewsWidget(CChartObjectPainter *painter,
                                 CDashboardTheme *theme,
                                 ILogger *logger);
                    ~CNewsWidget(void) { }
  };

#endif // SRP_DASHBOARD_WIDGETS_CNEWSWIDGET_MQH
//+------------------------------------------------------------------+
