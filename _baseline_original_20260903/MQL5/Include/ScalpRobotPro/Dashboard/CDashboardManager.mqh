//+------------------------------------------------------------------+
//|                                         CDashboardManager.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard : Composite over IWidget; owns the whole UI.                   |
//|                                                                  |
//|   RESPONSIBILITY (one only): own the widget collection, populate the view   |
//|   model, and repaint on a throttle. It renders nothing itself.             |
//|                                                                  |
//|   THREE PROPERTIES WORTH NOTING                                          |
//|   1. THROTTLED. Chart objects are expensive; on an M1 gold tick stream a   |
//|      per-tick repaint would cost more than the entire trading pipeline.    |
//|      Refresh happens on an interval, and the trading path never waits.     |
//|   2. DISABLED DURING OPTIMISATION. Drawing during a tester optimisation    |
//|      is pure waste, so the dashboard refuses to initialise there.          |
//|   3. READ-ONLY BY CONSTRUCTION. It writes to CDashboardViewModel and       |
//|      hands widgets a const reference. No widget can reach trading state.   |
//|                                                                  |
//|   OWNERSHIP: owns its widgets, the painter, the theme and the layout.      |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_CDASHBOARDMANAGER_MQH
#define SRP_DASHBOARD_CDASHBOARDMANAGER_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IWidget.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"
#include "CDashboardViewModel.mqh"
#include "CDashboardTheme.mqh"
#include "CDashboardLayout.mqh"
#include "CChartObjectPainter.mqh"

class CObjectNameFactory;

class CDashboardManager : public IModule
  {
private:
   CModuleIdentity      m_id;
   IWidget             *m_widgets[];       // OWNED
   //--- OWNED presentation collaborators.
   CDashboardTheme     *m_theme;
   CDashboardLayout    *m_layout;
   CChartObjectPainter *m_painter;
   //--- BORROWED.
   CDashboardViewModel *m_model;
   IClock              *m_clock;

   long                 m_chart_id;
   int                  m_sub_window;
   bool                 m_enabled;
   bool                 m_show_in_tester;
   bool                 m_created;
   bool                 m_collapsed;
   int                  m_refresh_interval_ms;
   ulong                m_last_refresh_ms;
   long                 m_repaint_count;

   //--- Rebuilds layout after a visibility change or chart resize.
   void              Rearrange(void);

public:
                     CDashboardManager(CDashboardViewModel *model,
                                       IClock *clock,
                                       ILogger *logger);
                    ~CDashboardManager(void);

   //--- Composition. Takes ownership of every argument.
   bool              AddWidget(IWidget *widget);
   void              SetTheme(CDashboardTheme *theme);
   void              SetLayout(CDashboardLayout *layout);
   void              SetPainter(CChartObjectPainter *painter);

   void              SetEnabled(const bool value);
   void              SetShowInTester(const bool value);
   void              SetRefreshIntervalMs(const int ms);
   void              SetChart(const long chart_id,const int sub_window);

   CDashboardTheme  *Theme(void)  const { return(m_theme); }
   CDashboardLayout *Layout(void) const { return(m_layout); }
   int               WidgetCount(void) const { return(ArraySize(m_widgets)); }

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   //--- Creates every widget's objects. Returns true even when the
   //--- dashboard is intentionally disabled, since that is not a failure.
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   //--- Destroys every object it created, leaving the chart clean.
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Called every tick by the engine; internally throttled, so the
   //--- trading path pays almost nothing.
   void              RefreshIfDue(void);
   //--- Immediate repaint, used on state changes the user must see now.
   void              ForceRefresh(void);

   //--- Chart event fan-out. Returns true when a widget consumed it.
   bool              RouteChartEvent(const int id,const long &lparam,
                                     const double &dparam,const string &sparam);

   void              ToggleCollapsed(void);
   long              RepaintCount(void) const { return(m_repaint_count); }
  };

#endif // SRP_DASHBOARD_CDASHBOARDMANAGER_MQH
//+------------------------------------------------------------------+
