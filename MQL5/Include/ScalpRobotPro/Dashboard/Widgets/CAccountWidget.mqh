//+------------------------------------------------------------------+
//|                                            CAccountWidget.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard/Widgets : balance, equity, margin, daily P/L.                 |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_WIDGETS_CACCOUNTWIDGET_MQH
#define SRP_DASHBOARD_WIDGETS_CACCOUNTWIDGET_MQH

#include "../../Core/Base/CWidgetBase.mqh"
#include "../CChartObjectPainter.mqh"
#include "../CDashboardTheme.mqh"

class CAccountWidget : public CWidgetBase
  {
private:
   CChartObjectPainter *m_painter;         // borrowed
   CDashboardTheme     *m_theme;           // borrowed
   //--- Shows the daily loss budget as a bar, so the user can see how
   //--- much room is left before the guard trips.
   bool                 m_show_daily_budget_bar;
   double               m_daily_loss_limit_percent;

protected:
   virtual bool      OnCreate(void) override;
   virtual void      OnRender(const CDashboardViewModel &model) override;

public:
                     CAccountWidget(CChartObjectPainter *painter,
                                    CDashboardTheme *theme,
                                    ILogger *logger);
                    ~CAccountWidget(void) { }

   void              SetDailyLossLimit(const double percent);
   void              SetShowDailyBudgetBar(const bool value);
  };

#endif // SRP_DASHBOARD_WIDGETS_CACCOUNTWIDGET_MQH
//+------------------------------------------------------------------+
