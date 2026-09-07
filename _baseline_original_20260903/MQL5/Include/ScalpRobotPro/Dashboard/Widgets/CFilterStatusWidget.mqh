//+------------------------------------------------------------------+
//|                                       CFilterStatusWidget.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard/Widgets : per-filter pass/veto indicators.                     |
//|                                                                  |
//|   The most support-valuable panel in the product. When a customer asks     |
//|   "why is it not trading?", this shows the exact filter that vetoed and    |
//|   its detail text - turning a day of email exchanges into a glance.        |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_WIDGETS_CFILTERSTATUSWIDGET_MQH
#define SRP_DASHBOARD_WIDGETS_CFILTERSTATUSWIDGET_MQH

#include "../../Core/Base/CWidgetBase.mqh"
#include "../CChartObjectPainter.mqh"
#include "../CDashboardTheme.mqh"

class CFilterStatusWidget : public CWidgetBase
  {
private:
   CChartObjectPainter *m_painter;         // borrowed
   CDashboardTheme     *m_theme;           // borrowed
   int                  m_max_rows;
   //--- Collapsed mode shows only the blocking filter; expanded shows all.
   bool                 m_show_only_vetoes;

   bool              CreateRow(const int index);
   void              RenderRow(const int index,const SFilterVerdict &verdict);
   void              HideRow(const int index);

protected:
   virtual bool      OnCreate(void) override;
   virtual void      OnRender(const CDashboardViewModel &model) override;

public:
                     CFilterStatusWidget(CChartObjectPainter *painter,
                                         CDashboardTheme *theme,
                                         ILogger *logger,
                                         const int max_rows=8);
                    ~CFilterStatusWidget(void) { }

   void              SetMaxRows(const int rows);
   void              SetShowOnlyVetoes(const bool value);
  };

#endif // SRP_DASHBOARD_WIDGETS_CFILTERSTATUSWIDGET_MQH
//+------------------------------------------------------------------+
