//+------------------------------------------------------------------+
//|                                           CDashboardTheme.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Dashboard : colours, fonts and sizing in one place.                     |
//|                                                                  |
//|   RESPONSIBILITY (one only): supply visual constants. Widgets ask the      |
//|   theme instead of hard-coding clrLime, which is what makes a light or     |
//|   high-contrast variant a configuration choice rather than a rewrite.      |
//|                                                                  |
//|   Semantic accessors (ProfitColor, VetoColor) rather than literal ones     |
//|   (GreenColor) mean a widget expresses meaning and the theme decides        |
//|   appearance.                                                            |
//+------------------------------------------------------------------+
#ifndef SRP_DASHBOARD_CDASHBOARDTHEME_MQH
#define SRP_DASHBOARD_CDASHBOARDTHEME_MQH

#include "../Core/Types/Enums.mqh"

class CDashboardTheme
  {
private:
   ENUM_SRP_THEME    m_theme;
   //--- Palette
   color             m_background;
   color             m_panel_background;
   color             m_border;
   color             m_title_text;
   color             m_label_text;
   color             m_value_text;
   color             m_profit;
   color             m_loss;
   color             m_neutral;
   color             m_warning;
   color             m_critical;
   color             m_accent;
   //--- Typography and metrics
   string            m_font_name;
   string            m_mono_font_name;
   int               m_title_font_size;
   int               m_body_font_size;
   int               m_row_height;
   int               m_padding;
   int               m_panel_width;

   void              ApplyDark(void);
   void              ApplyLight(void);
   void              ApplyHighContrast(void);

public:
                     CDashboardTheme(const ENUM_SRP_THEME theme=SRP_THEME_DARK);
                    ~CDashboardTheme(void) { }

   void              SetTheme(const ENUM_SRP_THEME theme);
   ENUM_SRP_THEME    Theme(void) const { return(m_theme); }

   //--- Palette accessors
   color             Background(void)      const { return(m_background); }
   color             PanelBackground(void) const { return(m_panel_background); }
   color             Border(void)          const { return(m_border); }
   color             TitleText(void)       const { return(m_title_text); }
   color             LabelText(void)       const { return(m_label_text); }
   color             ValueText(void)       const { return(m_value_text); }
   color             ProfitColor(void)     const { return(m_profit); }
   color             LossColor(void)       const { return(m_loss); }
   color             NeutralColor(void)    const { return(m_neutral); }
   color             WarningColor(void)    const { return(m_warning); }
   color             CriticalColor(void)   const { return(m_critical); }
   color             AccentColor(void)     const { return(m_accent); }

   //--- Semantic helpers, so no widget writes a colour conditional.
   color             ColorForValue(const double value) const;
   color             ColorForHealth(const ENUM_SRP_HEALTH_STATUS status) const;
   color             ColorForEngineState(const ENUM_SRP_ENGINE_STATE state) const;
   color             ColorForVerdict(const bool passed) const;

   //--- Typography and metrics
   string            FontName(void)      const { return(m_font_name); }
   string            MonoFontName(void)  const { return(m_mono_font_name); }
   int               TitleFontSize(void) const { return(m_title_font_size); }
   int               BodyFontSize(void)  const { return(m_body_font_size); }
   int               RowHeight(void)     const { return(m_row_height); }
   int               Padding(void)       const { return(m_padding); }
   int               PanelWidth(void)    const { return(m_panel_width); }
  };

//+------------------------------------------------------------------+
CDashboardTheme::CDashboardTheme(const ENUM_SRP_THEME theme)
  : m_theme(theme),
    m_font_name("Segoe UI"),
    m_mono_font_name("Consolas"),
    m_title_font_size(10),
    m_body_font_size(8),
    m_row_height(16),
    m_padding(8),
    m_panel_width(260)
  {
   SetTheme(theme);
  }
//+------------------------------------------------------------------+
void CDashboardTheme::SetTheme(const ENUM_SRP_THEME theme)
  {
   m_theme=theme;
   switch(theme)
     {
      case SRP_THEME_LIGHT:         ApplyLight();        break;
      case SRP_THEME_HIGH_CONTRAST: ApplyHighContrast(); break;
      default:                      ApplyDark();         break;
     }
  }
//+------------------------------------------------------------------+
void CDashboardTheme::ApplyDark(void)
  {
   m_background       = C'18,20,25';
   m_panel_background = C'28,32,40';
   m_border           = C'55,62,74';
   m_title_text       = C'235,238,245';
   m_label_text       = C'150,158,172';
   m_value_text       = C'225,230,238';
   m_profit           = C'80,200,120';
   m_loss             = C'225,85,85';
   m_neutral          = C'150,158,172';
   m_warning          = C'235,180,60';
   m_critical         = C'235,70,70';
   m_accent           = C'70,150,235';
  }
//+------------------------------------------------------------------+
void CDashboardTheme::ApplyLight(void)
  {
   m_background       = C'245,246,250';
   m_panel_background = C'255,255,255';
   m_border           = C'205,210,220';
   m_title_text       = C'25,28,35';
   m_label_text       = C'95,105,120';
   m_value_text       = C'35,40,50';
   m_profit           = C'25,140,70';
   m_loss             = C'200,45,45';
   m_neutral          = C'110,118,130';
   m_warning          = C'190,140,20';
   m_critical         = C'200,35,35';
   m_accent           = C'30,110,200';
  }
//+------------------------------------------------------------------+
void CDashboardTheme::ApplyHighContrast(void)
  {
   m_background       = clrBlack;
   m_panel_background = clrBlack;
   m_border           = clrWhite;
   m_title_text       = clrWhite;
   m_label_text       = clrWhite;
   m_value_text       = clrWhite;
   m_profit           = clrLime;
   m_loss             = clrRed;
   m_neutral          = clrSilver;
   m_warning          = clrYellow;
   m_critical         = clrRed;
   m_accent           = clrAqua;
  }
//+------------------------------------------------------------------+
color CDashboardTheme::ColorForValue(const double value) const
  {
   if(value>0.0) return(m_profit);
   if(value<0.0) return(m_loss);
   return(m_neutral);
  }
//+------------------------------------------------------------------+
color CDashboardTheme::ColorForHealth(const ENUM_SRP_HEALTH_STATUS status) const
  {
   switch(status)
     {
      case SRP_HEALTH_DEGRADED: return(m_warning);
      case SRP_HEALTH_CRITICAL: return(m_critical);
     }
   return(m_profit);
  }
//+------------------------------------------------------------------+
color CDashboardTheme::ColorForVerdict(const bool passed) const
  {
   return(passed ? m_profit : m_loss);
  }

#endif // SRP_DASHBOARD_CDASHBOARDTHEME_MQH
//+------------------------------------------------------------------+
