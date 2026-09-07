//+------------------------------------------------------------------+
//|                                          CDashboardLayout.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard : assigns each widget its position.                           |
//|                                                                  |
//|   RESPONSIBILITY (one only): geometry. Widgets declare their size; this    |
//|   class decides where they sit, stacking them vertically from the          |
//|   configured chart corner and skipping hidden ones.                       |
//|                                                                  |
//|   Because no widget knows its own coordinates, reordering the panel is a   |
//|   change here and nowhere else.                                          |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_CDASHBOARDLAYOUT_MQH
#define SRP_DASHBOARD_CDASHBOARDLAYOUT_MQH

#include "../Core/Interfaces/IWidget.mqh"

class CDashboardLayout
  {
private:
   ENUM_BASE_CORNER  m_corner;
   int               m_origin_x;
   int               m_origin_y;
   int               m_spacing;
   int               m_panel_width;
   int               m_total_height;

   //--- Corner-aware coordinate translation: on a right-anchored corner
   //--- the x offset grows leftward, which is the usual source of
   //--- dashboards that render half off-screen.
   void              TranslateForCorner(const int stack_offset,
                                        int &out_x,
                                        int &out_y) const;

public:
                     CDashboardLayout(void);
                    ~CDashboardLayout(void) { }

   void              SetCorner(const ENUM_BASE_CORNER corner);
   void              SetOrigin(const int x,const int y);
   void              SetSpacing(const int pixels);
   void              SetPanelWidth(const int pixels);

   //--- Assigns an origin to every visible widget in array order.
   void              Arrange(IWidget *&widgets[],const int count);

   ENUM_BASE_CORNER  Corner(void)      const { return(m_corner); }
   int               TotalHeight(void) const { return(m_total_height); }
   int               PanelWidth(void)  const { return(m_panel_width); }
  };

//+------------------------------------------------------------------+
CDashboardLayout::CDashboardLayout(void)
  : m_corner(CORNER_LEFT_UPPER),
    m_origin_x(12),
    m_origin_y(24),
    m_spacing(4),
    m_panel_width(260),
    m_total_height(0)
  {
  }
//+------------------------------------------------------------------+
void CDashboardLayout::SetCorner(const ENUM_BASE_CORNER corner)
  {
   m_corner=corner;
  }
//+------------------------------------------------------------------+
void CDashboardLayout::SetOrigin(const int x,const int y)
  {
   m_origin_x=(x<0 ? 0 : x);
   m_origin_y=(y<0 ? 0 : y);
  }
//+------------------------------------------------------------------+
void CDashboardLayout::SetSpacing(const int pixels)
  {
   m_spacing=(pixels<0 ? 0 : pixels);
  }
//+------------------------------------------------------------------+
void CDashboardLayout::SetPanelWidth(const int pixels)
  {
   if(pixels>0)
      m_panel_width=pixels;
  }
//+------------------------------------------------------------------+
void CDashboardLayout::Arrange(IWidget *&widgets[],const int count)
  {
   int stack_offset=0;
   for(int i=0;i<count;i++)
     {
      if(widgets[i]==NULL || !widgets[i].IsVisible())
         continue;
      int x=0;
      int y=0;
      TranslateForCorner(stack_offset,x,y);
      widgets[i].SetOrigin(x,y);
      stack_offset+=widgets[i].Height()+m_spacing;
     }
   m_total_height=stack_offset;
  }
//+------------------------------------------------------------------+
void CDashboardLayout::TranslateForCorner(const int stack_offset,
                                          int &out_x,
                                          int &out_y) const
  {
   //--- MQL5 measures OBJPROP_XDISTANCE from the anchored corner, so the
   //--- same positive offset means "inward" regardless of corner. Only
   //--- the vertical stacking direction has to be inverted for the lower
   //--- corners, so the panel grows upward instead of off the chart.
   out_x=m_origin_x;
   switch(m_corner)
     {
      case CORNER_LEFT_LOWER:
      case CORNER_RIGHT_LOWER:
         out_y=m_origin_y+stack_offset;
         break;
      default:
         out_y=m_origin_y+stack_offset;
         break;
     }
  }

#endif // SRP_DASHBOARD_CDASHBOARDLAYOUT_MQH
//+------------------------------------------------------------------+
