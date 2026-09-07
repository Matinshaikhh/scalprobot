//+------------------------------------------------------------------+
//|                                             CObjectPainter.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   RESPONSIBILITY (one only): create and update chart objects, and own   |
//|   an exact record of which objects it created.                         |
//|                                                                  |
//|   THIS IS THE ONLY CLASS IN PHASE 4 THAT CALLS ObjectCreate.           |
//|                                                                  |
//|   Three properties that matter in practice:                            |
//|                                                                  |
//|   1. IDEMPOTENT. EnsureObject creates only when absent, then applies    |
//|      properties. Repainting therefore reuses objects instead of         |
//|      deleting and recreating them, which is what stops the panel        |
//|      flickering on every refresh and stops the chart's object list      |
//|      fragmenting over a long session.                                  |
//|                                                                  |
//|   2. EXACT OWNERSHIP. Every created name is recorded, so cleanup        |
//|      deletes precisely what this painter made. Deleting by prefix       |
//|      alone risks removing a user's manually drawn objects or another    |
//|      EA's markup - unrecoverable for the user.                         |
//|                                                                  |
//|   3. NON-INTERACTIVE BY DEFAULT. Objects are created unselectable and   |
//|      not hidden from the object list, so a user cannot accidentally     |
//|      drag the dashboard apart but can still inspect it.                |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_DASHBOARD_COBJECTPAINTER_MQH
#define SRP_INTERFACE_DASHBOARD_COBJECTPAINTER_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../Types/InterfaceStructs.mqh"
#include "CUiTheme.mqh"

class CObjectPainter
  {
private:
   long              m_chart_id;
   int               m_sub_window;
   ENUM_BASE_CORNER  m_corner;
   CUiTheme         *m_theme;             // borrowed
   ILogger          *m_logger;            // borrowed
   string            m_prefix;
   //--- Exact ownership record.
   string            m_owned[];
   long              m_created;
   long              m_updated;
   long              m_failed;

   bool              EnsureObject(const string name,const ENUM_OBJECT type,
                                  const int window=0);
   void              ApplyCommon(const string name,const bool selectable=false);
   bool              Track(const string name);

public:
                     CObjectPainter(CUiTheme *theme,ILogger *logger,
                                    const string prefix="SRP4_");
                    ~CObjectPainter(void);

   void              Attach(const long chart_id,const int sub_window,
                            const ENUM_BASE_CORNER corner);
   void              SetTheme(CUiTheme *theme) { m_theme=theme; }

   //=== PANEL PRIMITIVES (screen coordinates) =======================
   bool              Panel(const string name,const int x,const int y,
                           const int width,const int height,
                           const color background,const color border);
   bool              Label(const string name,const int x,const int y,
                           const string text,const color text_color,
                           const int font_size,const string font,
                           const ENUM_ANCHOR_POINT anchor=ANCHOR_LEFT_UPPER);
   //--- Label plus right-aligned value on one row: the most common
   //--- dashboard element, so it is a single call.
   bool              KeyValue(const string base_name,const int x,const int y,
                              const int row_width,
                              const string key,const string value,
                              const color key_color,const color value_color,
                              const int font_size,const string font);
   bool              ProgressBar(const string name,const int x,const int y,
                                 const int width,const int height,
                                 const double fill_ratio,
                                 const color fill,const color track);
   bool              Separator(const string name,const int x,const int y,
                               const int width,const color line_color);

   //=== CHART OVERLAYS (price/time coordinates) =====================
   bool              PriceLine(const string name,const double price,
                               const color line_color,
                               const ENUM_LINE_STYLE style=STYLE_SOLID,
                               const int width=1,const string text="");
   bool              TrendLine(const string name,
                               const datetime time1,const double price1,
                               const datetime time2,const double price2,
                               const color line_color,
                               const ENUM_LINE_STYLE style=STYLE_SOLID,
                               const int width=1,const bool ray=false);
   bool              Box(const string name,
                         const datetime time1,const double price1,
                         const datetime time2,const double price2,
                         const color fill_color,const bool filled=true,
                         const int width=1);
   bool              Arrow(const string name,const datetime time,
                           const double price,const uchar code,
                           const color arrow_color,const int size=1);
   bool              TextAt(const string name,const datetime time,
                            const double price,const string text,
                            const color text_color,const int font_size,
                            const string font);

   //=== MUTATION (no recreate) =====================================
   bool              UpdateText(const string name,const string text);
   bool              UpdateColor(const string name,const color new_color);
   bool              UpdatePosition(const string name,const int x,const int y);
   bool              UpdatePrice(const string name,const double price,
                                 const int index=0);
   bool              SetVisible(const string name,const bool visible);

   //=== CLEANUP =====================================================
   bool              Remove(const string name);
   //--- Deletes only tracked objects. Safe by construction.
   int               RemoveAllOwned(void);
   //--- Deletes tracked objects whose name begins with the given group,
   //--- so one overlay layer can be cleared without touching others.
   int               RemoveGroup(const string group_prefix);

   //--- Namespaced name builder. All object names flow through this.
   string            Name(const string group,const string element) const;
   string            NameIndexed(const string group,const string element,
                                 const int index) const;

   int               OwnedCount(void) const { return(ArraySize(m_owned)); }
   long              CreatedCount(void) const { return(m_created); }
   long              FailedCount(void) const { return(m_failed); }
   string            Prefix(void) const { return(m_prefix); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CObjectPainter::CObjectPainter(CUiTheme *theme,ILogger *logger,
                               const string prefix)
  : m_chart_id(0),
    m_sub_window(0),
    m_corner(CORNER_LEFT_UPPER),
    m_theme(theme),
    m_logger(logger),
    m_prefix(prefix),
    m_created(0),
    m_updated(0),
    m_failed(0)
  {
   ArrayResize(m_owned,0);
  }
//+------------------------------------------------------------------+
CObjectPainter::~CObjectPainter(void)
  {
   //--- RAII: the chart is left clean even if the host forgot to call
   //--- cleanup explicitly.
   RemoveAllOwned();
   ArrayFree(m_owned);
  }
//+------------------------------------------------------------------+
void CObjectPainter::Attach(const long chart_id,const int sub_window,
                            const ENUM_BASE_CORNER corner)
  {
   m_chart_id=chart_id;
   m_sub_window=sub_window;
   m_corner=corner;
  }
//+------------------------------------------------------------------+
string CObjectPainter::Name(const string group,const string element) const
  {
   //--- Deterministic: the same inputs always yield the same name, so a
   //--- widget can find and update its own objects after a profile
   //--- reload rather than orphaning them.
   return(m_prefix+group+"_"+element);
  }
//+------------------------------------------------------------------+
string CObjectPainter::NameIndexed(const string group,const string element,
                                   const int index) const
  {
   return(m_prefix+group+"_"+element+"_"+IntegerToString(index));
  }
//+------------------------------------------------------------------+
bool CObjectPainter::Track(const string name)
  {
   //--- Already tracked? Nothing to do.
   const int total=ArraySize(m_owned);
   for(int i=0;i<total;i++)
      if(m_owned[i]==name)
         return(true);
   if(ArrayResize(m_owned,total+1)!=total+1)
      return(false);
   m_owned[total]=name;
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::EnsureObject(const string name,const ENUM_OBJECT type,
                                  const int window)
  {
   //--- IDEMPOTENCE. ObjectFind returns the window index when present.
   //--- Reusing the object is what keeps repaints flicker-free.
   if(ObjectFind(m_chart_id,name)>=0)
     {
      m_updated++;
      return(true);
     }
   if(!ObjectCreate(m_chart_id,name,type,window,0,0))
     {
      m_failed++;
      if(m_logger!=NULL)
         m_logger.Debug("CObjectPainter",
                        StringFormat("ObjectCreate failed for %s, error %d",
                                     name,GetLastError()));
      return(false);
     }
   m_created++;
   Track(name);
   return(true);
  }
//+------------------------------------------------------------------+
void CObjectPainter::ApplyCommon(const string name,const bool selectable)
  {
   //--- Not selectable and not selected: a user cannot drag the panel
   //--- apart by accident. Left visible in the object list so it can
   //--- still be inspected or removed manually.
   ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTABLE,selectable);
   ObjectSetInteger(m_chart_id,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(m_chart_id,name,OBJPROP_HIDDEN,false);
   ObjectSetInteger(m_chart_id,name,OBJPROP_ZORDER,0);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::Panel(const string name,const int x,const int y,
                           const int width,const int height,
                           const color background,const color border)
  {
   if(!EnsureObject(name,OBJ_RECTANGLE_LABEL))
      return(false);
   ObjectSetInteger(m_chart_id,name,OBJPROP_CORNER,m_corner);
   ObjectSetInteger(m_chart_id,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(m_chart_id,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(m_chart_id,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(m_chart_id,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(m_chart_id,name,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,border);
   ObjectSetInteger(m_chart_id,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(m_chart_id,name,OBJPROP_WIDTH,1);
   ApplyCommon(name);
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::Label(const string name,const int x,const int y,
                           const string text,const color text_color,
                           const int font_size,const string font,
                           const ENUM_ANCHOR_POINT anchor)
  {
   if(!EnsureObject(name,OBJ_LABEL))
      return(false);
   ObjectSetInteger(m_chart_id,name,OBJPROP_CORNER,m_corner);
   ObjectSetInteger(m_chart_id,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(m_chart_id,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(m_chart_id,name,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,text_color);
   ObjectSetInteger(m_chart_id,name,OBJPROP_FONTSIZE,font_size);
   ObjectSetString(m_chart_id,name,OBJPROP_FONT,font);
   ObjectSetString(m_chart_id,name,OBJPROP_TEXT,text);
   ApplyCommon(name);
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::KeyValue(const string base_name,const int x,const int y,
                              const int row_width,
                              const string key,const string value,
                              const color key_color,const color value_color,
                              const int font_size,const string font)
  {
   //--- Key left-aligned, value right-aligned at the row edge. Right
   //--- anchoring keeps numeric columns aligned as values change width,
   //--- which left-aligned values do not.
   const bool key_ok=Label(base_name+"_k",x,y,key,key_color,font_size,font,
                           ANCHOR_LEFT_UPPER);
   const bool value_ok=Label(base_name+"_v",x+row_width,y,value,value_color,
                             font_size,font,ANCHOR_RIGHT_UPPER);
   return(key_ok && value_ok);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::ProgressBar(const string name,const int x,const int y,
                                 const int width,const int height,
                                 const double fill_ratio,
                                 const color fill,const color track)
  {
   //--- Two rectangles: a track and a proportional fill.
   if(!Panel(name+"_t",x,y,width,height,track,track))
      return(false);
   double ratio=fill_ratio;
   if(ratio<0.0) ratio=0.0;
   if(ratio>1.0) ratio=1.0;
   int fill_width=(int)MathRound((double)width*ratio);
   //--- A non-zero ratio must always show at least one pixel, otherwise
   //--- "almost empty" and "empty" look identical.
   if(fill_width<1 && ratio>0.0)
      fill_width=1;
   if(fill_width<1)
     {
      //--- Genuinely zero: hide the fill rather than drawing nothing.
      SetVisible(name+"_f",false);
      return(true);
     }
   if(!Panel(name+"_f",x,y,fill_width,height,fill,fill))
      return(false);
   SetVisible(name+"_f",true);
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::Separator(const string name,const int x,const int y,
                               const int width,const color line_color)
  {
   return(Panel(name,x,y,width,1,line_color,line_color));
  }
//+------------------------------------------------------------------+
bool CObjectPainter::PriceLine(const string name,const double price,
                               const color line_color,
                               const ENUM_LINE_STYLE style,
                               const int width,const string text)
  {
   if(price<=0.0)
      return(false);
   if(!EnsureObject(name,OBJ_HLINE))
      return(false);
   ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,0,price);
   ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,line_color);
   ObjectSetInteger(m_chart_id,name,OBJPROP_STYLE,style);
   ObjectSetInteger(m_chart_id,name,OBJPROP_WIDTH,width);
   if(StringLen(text)>0)
      ObjectSetString(m_chart_id,name,OBJPROP_TEXT,text);
   ApplyCommon(name);
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::TrendLine(const string name,
                               const datetime time1,const double price1,
                               const datetime time2,const double price2,
                               const color line_color,
                               const ENUM_LINE_STYLE style,
                               const int width,const bool ray)
  {
   if(price1<=0.0 || price2<=0.0 || time1<=0 || time2<=0)
      return(false);
   if(!EnsureObject(name,OBJ_TREND))
      return(false);
   ObjectSetInteger(m_chart_id,name,OBJPROP_TIME,0,time1);
   ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,0,price1);
   ObjectSetInteger(m_chart_id,name,OBJPROP_TIME,1,time2);
   ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,1,price2);
   ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,line_color);
   ObjectSetInteger(m_chart_id,name,OBJPROP_STYLE,style);
   ObjectSetInteger(m_chart_id,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(m_chart_id,name,OBJPROP_RAY_RIGHT,ray);
   ApplyCommon(name);
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::Box(const string name,
                         const datetime time1,const double price1,
                         const datetime time2,const double price2,
                         const color fill_color,const bool filled,
                         const int width)
  {
   if(price1<=0.0 || price2<=0.0 || time1<=0 || time2<=0)
      return(false);
   if(!EnsureObject(name,OBJ_RECTANGLE))
      return(false);
   ObjectSetInteger(m_chart_id,name,OBJPROP_TIME,0,time1);
   ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,0,price1);
   ObjectSetInteger(m_chart_id,name,OBJPROP_TIME,1,time2);
   ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,1,price2);
   ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,fill_color);
   ObjectSetInteger(m_chart_id,name,OBJPROP_FILL,filled);
   ObjectSetInteger(m_chart_id,name,OBJPROP_WIDTH,width);
   //--- Behind the price series so candles remain readable through a
   //--- filled zone.
   ObjectSetInteger(m_chart_id,name,OBJPROP_BACK,filled);
   ApplyCommon(name);
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::Arrow(const string name,const datetime time,
                           const double price,const uchar code,
                           const color arrow_color,const int size)
  {
   if(price<=0.0 || time<=0)
      return(false);
   if(!EnsureObject(name,OBJ_ARROW))
      return(false);
   ObjectSetInteger(m_chart_id,name,OBJPROP_TIME,0,time);
   ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,0,price);
   ObjectSetInteger(m_chart_id,name,OBJPROP_ARROWCODE,code);
   ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,arrow_color);
   ObjectSetInteger(m_chart_id,name,OBJPROP_WIDTH,size);
   ApplyCommon(name);
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::TextAt(const string name,const datetime time,
                            const double price,const string text,
                            const color text_color,const int font_size,
                            const string font)
  {
   if(price<=0.0 || time<=0)
      return(false);
   if(!EnsureObject(name,OBJ_TEXT))
      return(false);
   ObjectSetInteger(m_chart_id,name,OBJPROP_TIME,0,time);
   ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,0,price);
   ObjectSetString(m_chart_id,name,OBJPROP_TEXT,text);
   ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,text_color);
   ObjectSetInteger(m_chart_id,name,OBJPROP_FONTSIZE,font_size);
   ObjectSetString(m_chart_id,name,OBJPROP_FONT,font);
   ApplyCommon(name);
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::UpdateText(const string name,const string text)
  {
   if(ObjectFind(m_chart_id,name)<0)
      return(false);
   m_updated++;
   return(ObjectSetString(m_chart_id,name,OBJPROP_TEXT,text));
  }
//+------------------------------------------------------------------+
bool CObjectPainter::UpdateColor(const string name,const color new_color)
  {
   if(ObjectFind(m_chart_id,name)<0)
      return(false);
   return(ObjectSetInteger(m_chart_id,name,OBJPROP_COLOR,new_color));
  }
//+------------------------------------------------------------------+
bool CObjectPainter::UpdatePosition(const string name,const int x,const int y)
  {
   if(ObjectFind(m_chart_id,name)<0)
      return(false);
   ObjectSetInteger(m_chart_id,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(m_chart_id,name,OBJPROP_YDISTANCE,y);
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::UpdatePrice(const string name,const double price,
                                 const int index)
  {
   if(ObjectFind(m_chart_id,name)<0 || price<=0.0)
      return(false);
   return(ObjectSetDouble(m_chart_id,name,OBJPROP_PRICE,index,price));
  }
//+------------------------------------------------------------------+
bool CObjectPainter::SetVisible(const string name,const bool visible)
  {
   if(ObjectFind(m_chart_id,name)<0)
      return(false);
   //--- Timeframe visibility mask is the reliable way to hide an object
   //--- without destroying it, so state survives the toggle.
   ObjectSetInteger(m_chart_id,name,OBJPROP_TIMEFRAMES,
                    (visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS));
   return(true);
  }
//+------------------------------------------------------------------+
bool CObjectPainter::Remove(const string name)
  {
   const bool deleted=ObjectDelete(m_chart_id,name);
   //--- Drop it from the ownership record either way: if it is gone, we
   //--- no longer own it.
   const int total=ArraySize(m_owned);
   for(int i=0;i<total;i++)
     {
      if(m_owned[i]!=name)
         continue;
      for(int j=i;j<total-1;j++)
         m_owned[j]=m_owned[j+1];
      ArrayResize(m_owned,total-1);
      break;
     }
   return(deleted);
  }
//+------------------------------------------------------------------+
int CObjectPainter::RemoveAllOwned(void)
  {
   int deleted=0;
   //--- Reverse order: deletion shifts remaining indices.
   for(int i=ArraySize(m_owned)-1;i>=0;i--)
      if(ObjectDelete(m_chart_id,m_owned[i]))
         deleted++;
   ArrayResize(m_owned,0);
   return(deleted);
  }
//+------------------------------------------------------------------+
int CObjectPainter::RemoveGroup(const string group_prefix)
  {
   const string full=m_prefix+group_prefix;
   const int length=StringLen(full);
   int deleted=0;
   for(int i=ArraySize(m_owned)-1;i>=0;i--)
     {
      if(StringLen(m_owned[i])<length)
         continue;
      if(StringSubstr(m_owned[i],0,length)!=full)
         continue;
      if(ObjectDelete(m_chart_id,m_owned[i]))
         deleted++;
      const int total=ArraySize(m_owned);
      for(int j=i;j<total-1;j++)
         m_owned[j]=m_owned[j+1];
      ArrayResize(m_owned,total-1);
     }
   return(deleted);
  }
//+------------------------------------------------------------------+
string CObjectPainter::Describe(void) const
  {
   return(StringFormat("painter: %d owned, %I64d created, %I64d updated, "
                       "%I64d failed (prefix '%s')",
                       ArraySize(m_owned),m_created,m_updated,m_failed,
                       m_prefix));
  }

#endif // SRP_INTERFACE_DASHBOARD_COBJECTPAINTER_MQH
//+------------------------------------------------------------------+
