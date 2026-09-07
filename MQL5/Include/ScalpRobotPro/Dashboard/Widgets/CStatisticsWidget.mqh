//+------------------------------------------------------------------+
//|                                         CStatisticsWidget.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard/Widgets : performance metrics panel.                           |
//|                                                                  |
//|   Renders win rate, profit factor, expectancy, average R and drawdown      |
//|   from the view model's metrics copy. Purely presentational: it never       |
//|   computes a metric, because CPerformanceCalculator already did and two    |
//|   implementations of the same formula would eventually disagree.           |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_WIDGETS_CSTATISTICSWIDGET_MQH
#define SRP_DASHBOARD_WIDGETS_CSTATISTICSWIDGET_MQH

#include "../../Core/Base/CWidgetBase.mqh"
#include "../CChartObjectPainter.mqh"
#include "../CDashboardTheme.mqh"

class CStatisticsWidget : public CWidgetBase
  {
private:
   CChartObjectPainter *m_painter;         // borrowed
   CDashboardTheme     *m_theme;           // borrowed
   bool                 m_show_execution_quality; // slippage and latency

protected:
   virtual bool      OnCreate(void) override;
   virtual void      OnRender(const CDashboardViewModel &model) override;

public:
                     CStatisticsWidget(CChartObjectPainter *painter,
                                       CDashboardTheme *theme,
                                       ILogger *logger);
                    ~CStatisticsWidget(void) { }

   void              SetShowExecutionQuality(const bool value);
  };

#endif // SRP_DASHBOARD_WIDGETS_CSTATISTICSWIDGET_MQH
//+------------------------------------------------------------------+
