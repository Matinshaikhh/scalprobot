//+------------------------------------------------------------------+
//|                                                      IWidget.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : one self-contained dashboard panel.          |
//|                                                                  |
//|   The dashboard is a COMPOSITE of widgets. Each widget owns its   |
//|   own chart objects and renders from a read-only view model, so   |
//|   the UI can never mutate trading state. Adding a panel means     |
//|   adding a widget class - CDashboardManager never changes.        |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_IWIDGET_MQH
#define SRP_CORE_INTERFACES_IWIDGET_MQH

#include "../Types/Structs.mqh"

//--- Forward declaration: widgets read the aggregated view model
//--- without depending on how it is assembled.
class CDashboardViewModel;

interface IWidget
  {
   ENUM_SRP_WIDGET_ID WidgetId(void);
   string            WidgetName(void);

   bool              IsVisible(void);
   void              SetVisible(const bool visible);

   //--- Layout, assigned by CDashboardLayout so widgets never
   //--- hard-code screen positions.
   void              SetOrigin(const int x,const int y);
   int               Width(void);
   int               Height(void);

   //--- Object lifecycle. Create() must register every object it
   //--- makes under the SRP_DASHBOARD_PREFIX namespace, and
   //--- Destroy() must remove exactly those objects.
   bool              Create(const long chart_id,const int sub_window);
   void              Destroy(void);

   //--- Repaint from the read-only model. Called on a throttle, not
   //--- every tick.
   void              Render(const CDashboardViewModel &model);

   //--- Returns true when the widget consumed the chart event.
   bool              OnChartEventReceived(const int id,const long &lparam,
                                          const double &dparam,const string &sparam);
  };

#endif // SRP_CORE_INTERFACES_IWIDGET_MQH
//+------------------------------------------------------------------+
