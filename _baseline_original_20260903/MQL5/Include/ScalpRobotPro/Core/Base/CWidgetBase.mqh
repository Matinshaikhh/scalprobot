//+------------------------------------------------------------------+
//|                                                  CWidgetBase.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Base : abstract base for dashboard widgets.               |
//|                                                                  |
//|   Owns geometry, visibility and - critically - the list of chart  |
//|   object names the widget created, so Destroy() can be exact      |
//|   rather than deleting by prefix and hitting a neighbour's        |
//|   objects. Subclasses implement OnCreate and OnRender only.       |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_BASE_CWIDGETBASE_MQH
#define SRP_CORE_BASE_CWIDGETBASE_MQH

#include "../Interfaces/IWidget.mqh"
#include "CModuleIdentity.mqh"

class CWidgetBase : public IWidget
  {
protected:
   CModuleIdentity     m_id;
   ENUM_SRP_WIDGET_ID  m_widget_id;
   long                m_chart_id;
   int                 m_sub_window;
   int                 m_x;
   int                 m_y;
   int                 m_width;
   int                 m_height;
   bool                m_visible;
   bool                m_created;
   string              m_owned_objects[];   // exact ownership record

   //--- Extension points.
   virtual bool      OnCreate(void)=0;
   virtual void      OnRender(const CDashboardViewModel &model)=0;
   virtual bool      OnChartEvent(const int id,const long &lparam,
                                  const double &dparam,const string &sparam)
     {
      return(false);
     }

   //--- Every object a subclass creates must be registered here.
   void              RegisterObject(const string object_name)
     {
      const int size=ArraySize(m_owned_objects);
      ArrayResize(m_owned_objects,size+1);
      m_owned_objects[size]=object_name;
     }

   //--- Namespaced name builder, prevents collisions between widgets.
   string            BuildName(const string element) const
     {
      return(SRP_DASHBOARD_PREFIX+m_id.Name()+"_"+element);
     }

public:
                     CWidgetBase(const string name,
                                 const ENUM_SRP_WIDGET_ID id,
                                 ILogger *logger,
                                 const int width=240,
                                 const int height=100)
     : m_widget_id(id),
       m_chart_id(0),
       m_sub_window(0),
       m_x(0),
       m_y(0),
       m_width(width),
       m_height(height),
       m_visible(true),
       m_created(false)
     {
      m_id.Configure(name,logger);
      ArrayResize(m_owned_objects,0);
     }

   virtual          ~CWidgetBase(void) { Destroy(); }

   //--- IWidget -----------------------------------------------------
   virtual ENUM_SRP_WIDGET_ID WidgetId(void) override { return(m_widget_id); }
   virtual string    WidgetName(void) override { return(m_id.Name()); }

   virtual bool      IsVisible(void) override { return(m_visible); }
   virtual void      SetVisible(const bool visible) override { m_visible=visible; }

   virtual void      SetOrigin(const int x,const int y) override { m_x=x; m_y=y; }
   virtual int       Width(void)  override { return(m_width); }
   virtual int       Height(void) override { return(m_height); }

   virtual bool      Create(const long chart_id,const int sub_window) override
     {
      if(m_created)
         return(true);
      m_chart_id   = chart_id;
      m_sub_window = sub_window;
      if(!OnCreate())
        {
         m_id.Error("widget creation failed");
         Destroy();
         return(false);
        }
      m_created=true;
      return(true);
     }

   //--- Deletes exactly what this widget made, nothing else.
   virtual void      Destroy(void) override
     {
      const int total=ArraySize(m_owned_objects);
      for(int i=total-1;i>=0;i--)
         ObjectDelete(m_chart_id,m_owned_objects[i]);
      ArrayResize(m_owned_objects,0);
      m_created=false;
     }

   virtual void      Render(const CDashboardViewModel &model) override
     {
      if(!m_created || !m_visible)
         return;
      OnRender(model);
     }

   virtual bool      OnChartEventReceived(const int id,const long &lparam,
                                          const double &dparam,
                                          const string &sparam) override
     {
      if(!m_created || !m_visible)
         return(false);
      return(OnChartEvent(id,lparam,dparam,sparam));
     }
  };

#endif // SRP_CORE_BASE_CWIDGETBASE_MQH
//+------------------------------------------------------------------+
