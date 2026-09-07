//+------------------------------------------------------------------+
//|                                        CEquityCurveWidget.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard/Widgets : sparkline of the recent equity curve.                 |
//|                                                                  |
//|   The polyline segments are created once at Create() up to a fixed         |
//|   maximum and then repositioned on refresh. Recreating them each repaint   |
//|   would be the single most expensive thing the dashboard does.             |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_WIDGETS_CEQUITYCURVEWIDGET_MQH
#define SRP_DASHBOARD_WIDGETS_CEQUITYCURVEWIDGET_MQH

#include "../../Core/Base/CWidgetBase.mqh"
#include "../CChartObjectPainter.mqh"
#include "../CDashboardTheme.mqh"

class CEquityCurveWidget : public CWidgetBase
  {
private:
   CChartObjectPainter *m_painter;         // borrowed
   CDashboardTheme     *m_theme;           // borrowed
   int                  m_max_segments;
   bool                 m_show_min_max_labels;

   //--- Maps sample values into widget pixel space.
   bool              ComputeScale(const CDashboardViewModel &model,
                                  double &out_min,
                                  double &out_max) const;

protected:
   virtual bool      OnCreate(void) override;
   virtual void      OnRender(const CDashboardViewModel &model) override;

public:
                     CEquityCurveWidget(CChartObjectPainter *painter,
                                        CDashboardTheme *theme,
                                        ILogger *logger,
                                        const int max_segments=60);
                    ~CEquityCurveWidget(void) { }

   void              SetShowMinMaxLabels(const bool value);
  };

#endif // SRP_DASHBOARD_WIDGETS_CEQUITYCURVEWIDGET_MQH
//+------------------------------------------------------------------+
