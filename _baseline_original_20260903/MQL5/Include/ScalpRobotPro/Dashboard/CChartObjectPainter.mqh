//+------------------------------------------------------------------+
//|                                       CChartObjectPainter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard : the only class that creates chart objects.                  |
//|                                                                  |
//|   RESPONSIBILITY (one only): wrap ObjectCreate/ObjectSet* behind a small   |
//|   drawing vocabulary (panel, label, value row, bar, separator, sparkline). |
//|                                                                  |
//|   WHY THIS PAYS FOR ITSELF                                               |
//|   Raw chart-object code is verbose and repetitive: every label needs six   |
//|   ObjectSet calls, and forgetting OBJPROP_SELECTABLE=false lets a user     |
//|   drag the dashboard apart. Centralising it means every widget gets those  |
//|   details right for free, and an update reuses an existing object instead  |
//|   of deleting and recreating it - which is what stops the panel from       |
//|   flickering on every refresh.                                           |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_CCHARTOBJECTPAINTER_MQH
#define SRP_DASHBOARD_CCHARTOBJECTPAINTER_MQH

#include "CDashboardTheme.mqh"

class CChartObjectPainter
  {
private:
   long              m_chart_id;
   int               m_sub_window;
   ENUM_BASE_CORNER  m_corner;
   CDashboardTheme  *m_theme;              // borrowed
   long              m_objects_created;
   long              m_objects_updated;

   //--- Creates the object only if absent, then applies properties.
   //--- This idempotence is what makes repaint cheap and flicker-free.
   bool              EnsureObject(const string name,
                                  const ENUM_OBJECT type);
   void              ApplyCommonProperties(const string name);

public:
                     CChartObjectPainter(CDashboardTheme *theme);
                    ~CChartObjectPainter(void) { }

   void              Attach(const long chart_id,const int sub_window,
                            const ENUM_BASE_CORNER corner);
   void              SetTheme(CDashboardTheme *theme) { m_theme=theme; }

   //--- Drawing vocabulary ------------------------------------------
   bool              DrawPanel(const string name,const int x,const int y,
                               const int width,const int height,
                               const color background,const color border);
   bool              DrawLabel(const string name,const int x,const int y,
                               const string text,const color text_color,
                               const int font_size,const string font_name,
                               const ENUM_ANCHOR_POINT anchor=ANCHOR_LEFT_UPPER);
   //--- Label plus right-aligned value on one row, the most common
   //--- dashboard element.
   bool              DrawKeyValue(const string name_prefix,
                                  const int x,const int y,const int row_width,
                                  const string label,const string value,
                                  const color label_color,const color value_color,
                                  const int font_size,const string font_name);
   bool              DrawProgressBar(const string name,const int x,const int y,
                                     const int width,const int height,
                                     const double fill_ratio,
                                     const color fill_color,
                                     const color track_color);
   bool              DrawSeparator(const string name,const int x,const int y,
                                   const int width,const color line_color);
   //--- Simple polyline sparkline for the equity curve widget.
   bool              DrawSparkline(const string name_prefix,
                                   const int x,const int y,
                                   const int width,const int height,
                                   const double &values[],
                                   const color line_color,
                                   string &created_names[]);

   //--- Mutation of an existing object, avoiding recreation.
   bool              UpdateText(const string name,const string text);
   bool              UpdateColor(const string name,const color new_color);
   bool              UpdatePosition(const string name,const int x,const int y);
   bool              SetVisible(const string name,const bool visible);
   bool              Remove(const string name);

   long              ObjectsCreated(void) const { return(m_objects_created); }
  };

#endif // SRP_DASHBOARD_CCHARTOBJECTPAINTER_MQH
//+------------------------------------------------------------------+
