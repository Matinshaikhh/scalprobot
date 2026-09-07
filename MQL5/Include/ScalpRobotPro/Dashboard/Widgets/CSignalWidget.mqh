//+------------------------------------------------------------------+
//|                                             CSignalWidget.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard/Widgets : current signal, confidence and rationale.            |
//|                                                                  |
//|   Displays WHY the robot wants to trade, not merely that it does. The      |
//|   rationale string travels from the strategy through the aggregator to     |
//|   here unchanged, which turns the EA from a black box into something a     |
//|   user can reason about and a support agent can debug.                    |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_WIDGETS_CSIGNALWIDGET_MQH
#define SRP_DASHBOARD_WIDGETS_CSIGNALWIDGET_MQH

#include "../../Core/Base/CWidgetBase.mqh"
#include "../CChartObjectPainter.mqh"
#include "../CDashboardTheme.mqh"

class CSignalWidget : public CWidgetBase
  {
private:
   CChartObjectPainter *m_painter;         // borrowed
   CDashboardTheme     *m_theme;           // borrowed
   bool                 m_show_rationale;
   int                  m_rationale_max_length;

protected:
   virtual bool      OnCreate(void) override;
   virtual void      OnRender(const CDashboardViewModel &model) override;

public:
                     CSignalWidget(CChartObjectPainter *painter,
                                   CDashboardTheme *theme,
                                   ILogger *logger);
                    ~CSignalWidget(void) { }

   void              SetShowRationale(const bool value);
  };

#endif // SRP_DASHBOARD_WIDGETS_CSIGNALWIDGET_MQH
//+------------------------------------------------------------------+
