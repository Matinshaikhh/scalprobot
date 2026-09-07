//+------------------------------------------------------------------+
//|                                          CPositionsWidget.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard/Widgets : table of open positions owned by this EA.            |
//|                                                                  |
//|   Row objects are created up to a fixed maximum at Create() and then       |
//|   shown or hidden as the position count changes. Creating and deleting     |
//|   objects per refresh would flicker and would slowly fragment the chart's  |
//|   object list on a long-running terminal.                                 |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_WIDGETS_CPOSITIONSWIDGET_MQH
#define SRP_DASHBOARD_WIDGETS_CPOSITIONSWIDGET_MQH

#include "../../Core/Base/CWidgetBase.mqh"
#include "../CChartObjectPainter.mqh"
#include "../CDashboardTheme.mqh"

class CPositionsWidget : public CWidgetBase
  {
private:
   CChartObjectPainter *m_painter;         // borrowed
   CDashboardTheme     *m_theme;           // borrowed
   int                  m_max_rows;
   bool                 m_show_totals_row;

   bool              CreateRow(const int index);
   void              RenderRow(const int index,const SPositionSnapshot &position);
   void              HideRow(const int index);

protected:
   virtual bool      OnCreate(void) override;
   virtual void      OnRender(const CDashboardViewModel &model) override;

public:
                     CPositionsWidget(CChartObjectPainter *painter,
                                      CDashboardTheme *theme,
                                      ILogger *logger,
                                      const int max_rows=6);
                    ~CPositionsWidget(void) { }

   void              SetMaxRows(const int rows);
   void              SetShowTotalsRow(const bool value);
  };

#endif // SRP_DASHBOARD_WIDGETS_CPOSITIONSWIDGET_MQH
//+------------------------------------------------------------------+
