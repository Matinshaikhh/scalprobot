//+------------------------------------------------------------------+
//|                                                   CUiTheme.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   RESPONSIBILITY (one only): supply visual constants.                  |
//|                                                                  |
//|   Widgets ask for a TONE (positive, warning, critical) rather than a    |
//|   literal colour. That indirection is what makes a light or            |
//|   high-contrast variant a configuration change instead of a rewrite,   |
//|   and it keeps colour decisions out of every drawing call site.        |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_DASHBOARD_CUITHEME_MQH
#define SRP_INTERFACE_DASHBOARD_CUITHEME_MQH

#include "../Types/InterfaceStructs.mqh"

class CUiTheme
  {
private:
   ENUM_SRP_UI_THEME m_theme;
   //--- Palette.
   color             m_background;
   color             m_panel;
   color             m_border;
   color             m_title;
   color             m_label;
   color             m_value;
   color             m_positive;
   color             m_negative;
   color             m_neutral;
   color             m_warning;
   color             m_critical;
   color             m_accent;
   color             m_muted;
   //--- Overlay colours, kept separate from panel colours because chart
   //--- drawings sit on the price series and need different contrast.
   color             m_bull_zone;
   color             m_bear_zone;
   color             m_gap_zone;
   color             m_liquidity;
   color             m_structure;
   color             m_session_box;
   //--- Typography and metrics.
   string            m_font;
   string            m_mono_font;
   int               m_title_size;
   int               m_body_size;
   int               m_row_height;
   int               m_padding;
   int               m_panel_width;

   void              ApplyDark(void);
   void              ApplyLight(void);
   void              ApplyContrast(void);

public:
                     CUiTheme(const ENUM_SRP_UI_THEME theme=SRP_UI_THEME_DARK);
                    ~CUiTheme(void) { }

   void              SetTheme(const ENUM_SRP_UI_THEME theme);
   ENUM_SRP_UI_THEME Theme(void) const { return(m_theme); }

   //--- Palette accessors.
   color             Background(void) const { return(m_background); }
   color             Panel(void)      const { return(m_panel); }
   color             Border(void)     const { return(m_border); }
   color             Title(void)      const { return(m_title); }
   color             Label(void)      const { return(m_label); }
   color             Value(void)      const { return(m_value); }
   color             Accent(void)     const { return(m_accent); }
   color             Muted(void)      const { return(m_muted); }

   //--- Overlay accessors.
   color             BullZone(void)   const { return(m_bull_zone); }
   color             BearZone(void)   const { return(m_bear_zone); }
   color             GapZone(void)    const { return(m_gap_zone); }
   color             Liquidity(void)  const { return(m_liquidity); }
   color             Structure(void)  const { return(m_structure); }
   color             SessionBox(void) const { return(m_session_box); }

   //--- SEMANTIC resolution. The only method widgets should normally use.
   color             ForTone(const ENUM_SRP_UI_TONE tone) const;
   //--- Sign-based helper: positive green, negative red, zero neutral.
   color             ForValue(const double value) const;
   ENUM_SRP_UI_TONE  ToneForValue(const double value) const;

   //--- Typography and metrics.
   string            Font(void)      const { return(m_font); }
   string            MonoFont(void)  const { return(m_mono_font); }
   int               TitleSize(void) const { return(m_title_size); }
   int               BodySize(void)  const { return(m_body_size); }
   int               RowHeight(void) const { return(m_row_height); }
   int               Padding(void)   const { return(m_padding); }
   int               PanelWidth(void) const { return(m_panel_width); }
   void              SetPanelWidth(const int width)
     { if(width>=120) m_panel_width=width; }
   void              SetRowHeight(const int height)
     { if(height>=10) m_row_height=height; }
   void              SetFontSizes(const int title,const int body)
     {
      if(title>=6) m_title_size=title;
      if(body>=6)  m_body_size=body;
     }
  };

//+------------------------------------------------------------------+
CUiTheme::CUiTheme(const ENUM_SRP_UI_THEME theme)
  : m_theme(theme),
    m_font("Segoe UI"),
    m_mono_font("Consolas"),
    m_title_size(10),
    m_body_size(8),
    m_row_height(15),
    m_padding(8),
    m_panel_width(268)
  {
   SetTheme(theme);
  }
//+------------------------------------------------------------------+
void CUiTheme::SetTheme(const ENUM_SRP_UI_THEME theme)
  {
   m_theme=theme;
   switch(theme)
     {
      case SRP_UI_THEME_LIGHT:    ApplyLight();    break;
      case SRP_UI_THEME_CONTRAST: ApplyContrast(); break;
      default:                    ApplyDark();     break;
     }
  }
//+------------------------------------------------------------------+
void CUiTheme::ApplyDark(void)
  {
   m_background  = C'18,20,25';
   m_panel       = C'28,32,40';
   m_border      = C'55,62,74';
   m_title       = C'235,238,245';
   m_label       = C'150,158,172';
   m_value       = C'225,230,238';
   m_positive    = C'80,200,120';
   m_negative    = C'225,85,85';
   m_neutral     = C'150,158,172';
   m_warning     = C'235,180,60';
   m_critical    = C'235,70,70';
   m_accent      = C'70,150,235';
   m_muted       = C'95,102,115';
   m_bull_zone   = C'40,120,80';
   m_bear_zone   = C'130,55,55';
   m_gap_zone    = C'90,80,140';
   m_liquidity   = C'190,160,60';
   m_structure   = C'70,150,235';
   m_session_box = C'38,44,56';
  }
//+------------------------------------------------------------------+
void CUiTheme::ApplyLight(void)
  {
   m_background  = C'245,246,250';
   m_panel       = C'255,255,255';
   m_border      = C'205,210,220';
   m_title       = C'25,28,35';
   m_label       = C'95,105,120';
   m_value       = C'35,40,50';
   m_positive    = C'25,140,70';
   m_negative    = C'200,45,45';
   m_neutral     = C'110,118,130';
   m_warning     = C'190,140,20';
   m_critical    = C'200,35,35';
   m_accent      = C'30,110,200';
   m_muted       = C'150,158,170';
   m_bull_zone   = C'180,225,195';
   m_bear_zone   = C'245,200,200';
   m_gap_zone    = C'215,210,240';
   m_liquidity   = C'240,220,150';
   m_structure   = C'30,110,200';
   m_session_box = C'235,238,244';
  }
//+------------------------------------------------------------------+
void CUiTheme::ApplyContrast(void)
  {
   //--- Maximum-contrast variant for accessibility and for traders
   //--- working on low-quality displays.
   m_background  = clrBlack;
   m_panel       = clrBlack;
   m_border      = clrWhite;
   m_title       = clrWhite;
   m_label       = clrWhite;
   m_value       = clrWhite;
   m_positive    = clrLime;
   m_negative    = clrRed;
   m_neutral     = clrSilver;
   m_warning     = clrYellow;
   m_critical    = clrRed;
   m_accent      = clrAqua;
   m_muted       = clrGray;
   m_bull_zone   = clrDarkGreen;
   m_bear_zone   = clrMaroon;
   m_gap_zone    = clrIndigo;
   m_liquidity   = clrOlive;
   m_structure   = clrAqua;
   m_session_box = C'20,20,20';
  }
//+------------------------------------------------------------------+
color CUiTheme::ForTone(const ENUM_SRP_UI_TONE tone) const
  {
   switch(tone)
     {
      case SRP_UI_TONE_POSITIVE: return(m_positive);
      case SRP_UI_TONE_NEGATIVE: return(m_negative);
      case SRP_UI_TONE_WARNING:  return(m_warning);
      case SRP_UI_TONE_CRITICAL: return(m_critical);
      case SRP_UI_TONE_ACCENT:   return(m_accent);
      case SRP_UI_TONE_MUTED:    return(m_muted);
     }
   return(m_neutral);
  }
//+------------------------------------------------------------------+
ENUM_SRP_UI_TONE CUiTheme::ToneForValue(const double value) const
  {
   if(value>SRP_EPSILON)  return(SRP_UI_TONE_POSITIVE);
   if(value<-SRP_EPSILON) return(SRP_UI_TONE_NEGATIVE);
   return(SRP_UI_TONE_NEUTRAL);
  }
//+------------------------------------------------------------------+
color CUiTheme::ForValue(const double value) const
  {
   return(ForTone(ToneForValue(value)));
  }

#endif // SRP_INTERFACE_DASHBOARD_CUITHEME_MQH
//+------------------------------------------------------------------+
