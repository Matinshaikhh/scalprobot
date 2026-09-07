//+------------------------------------------------------------------+
//|                                             CHeaderWidget.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard/Widgets : product identity, engine state, health.              |
//|                                                                  |
//|   The first thing a user looks at, so it answers the first question:       |
//|   is the robot running, and is anything wrong? State and health are        |
//|   colour-coded through the theme rather than by literal colours.           |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_WIDGETS_CHEADERWIDGET_MQH
#define SRP_DASHBOARD_WIDGETS_CHEADERWIDGET_MQH

#include "../../Core/Base/CWidgetBase.mqh"
#include "../CChartObjectPainter.mqh"
#include "../CDashboardTheme.mqh"

class CHeaderWidget : public CWidgetBase
  {
private:
   CChartObjectPainter *m_painter;         // borrowed
   CDashboardTheme     *m_theme;           // borrowed

protected:
   virtual bool      OnCreate(void) override;
   virtual void      OnRender(const CDashboardViewModel &model) override;

public:
                     CHeaderWidget(CChartObjectPainter *painter,
                                   CDashboardTheme *theme,
                                   ILogger *logger);
                    ~CHeaderWidget(void) { }

   //--- Clicking the header collapses the rest of the dashboard, which
   //--- is why this widget handles chart events.
   virtual bool      OnChartEvent(const int id,const long &lparam,
                                  const double &dparam,
                                  const string &sparam) override;
  };

#endif // SRP_DASHBOARD_WIDGETS_CHEADERWIDGET_MQH
//+------------------------------------------------------------------+
