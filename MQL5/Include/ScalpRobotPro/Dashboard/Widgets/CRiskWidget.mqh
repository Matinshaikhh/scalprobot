//+------------------------------------------------------------------+
//|                                               CRiskWidget.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard/Widgets : exposure, drawdown and guard status.                 |
//|                                                                  |
//|   Shows what is at stake right now and how close each guard is to          |
//|   tripping, including the kill-switch banner. A tripped guard is           |
//|   rendered prominently: silently declining to trade is the behaviour       |
//|   users most often mistake for a broken robot.                            |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_WIDGETS_CRISKWIDGET_MQH
#define SRP_DASHBOARD_WIDGETS_CRISKWIDGET_MQH

#include "../../Core/Base/CWidgetBase.mqh"
#include "../CChartObjectPainter.mqh"
#include "../CDashboardTheme.mqh"

class CRiskWidget : public CWidgetBase
  {
private:
   CChartObjectPainter *m_painter;         // borrowed
   CDashboardTheme     *m_theme;           // borrowed
   double               m_max_drawdown_limit_percent;
   bool                 m_show_drawdown_bar;

protected:
   virtual bool      OnCreate(void) override;
   virtual void      OnRender(const CDashboardViewModel &model) override;

public:
                     CRiskWidget(CChartObjectPainter *painter,
                                 CDashboardTheme *theme,
                                 ILogger *logger);
                    ~CRiskWidget(void) { }

   void              SetMaxDrawdownLimit(const double percent);
   void              SetShowDrawdownBar(const bool value);
  };

#endif // SRP_DASHBOARD_WIDGETS_CRISKWIDGET_MQH
//+------------------------------------------------------------------+
