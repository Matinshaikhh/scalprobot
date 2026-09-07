//+------------------------------------------------------------------+
//|                                            CDashboardPanel.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   RESPONSIBILITY (one only): render the metrics panel from a read-only  |
//|   model.                                                             |
//|                                                                  |
//|   Displays all eighteen required metrics: Balance, Equity, Margin,     |
//|   Floating Profit, Today/Weekly/Monthly Profit, Win Rate, Profit       |
//|   Factor, Average RR, Spread, Latency, Session, News Countdown,        |
//|   Strategy, Open Trades, Risk %, Lot Size.                            |
//|                                                                  |
//|   THROTTLED BY DESIGN. Chart objects are expensive; on an M1 gold tick |
//|   stream a per-tick repaint costs more than the entire trading         |
//|   pipeline. Refresh happens on an interval and the trading path never  |
//|   waits for it.                                                      |
//|                                                                  |
//|   READ-ONLY BY CONSTRUCTION. It receives a const SDashboardModel and   |
//|   holds no pointer to any engine, so it cannot affect trading.        |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_DASHBOARD_CDASHBOARDPANEL_MQH
#define SRP_INTERFACE_DASHBOARD_CDASHBOARDPANEL_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Utilities/CStringUtils.mqh"
#include "CObjectPainter.mqh"
#include "CUiTheme.mqh"

class CDashboardPanel
  {
private:
   CObjectPainter   *m_painter;           // borrowed
   CUiTheme         *m_theme;             // borrowed
   ILogger          *m_logger;            // borrowed

   int               m_origin_x;
   int               m_origin_y;
   bool              m_enabled;
   bool              m_created;
   bool              m_collapsed;
   int               m_refresh_ms;
   ulong             m_last_refresh_ms;
   long              m_repaints;
   //--- Row cursor, advanced as the panel is laid out.
   int               m_cursor_y;
   int               m_row_index;

   //--- Layout helpers. Each returns the next free Y so sections
   //--- compose without hard-coded coordinates.
   int               DrawHeader(const SDashboardModel &model,int y);
   int               DrawSection(const string title,int y);
   int               DrawRow(const string group,const string key,
                             const string value,
                             const ENUM_SRP_UI_TONE tone,int y);
   int               DrawSeparator(const string group,int y);
   int               DrawBar(const string group,const string key,
                             const double ratio,
                             const ENUM_SRP_UI_TONE tone,int y);

   //--- Formatting. Centralised so every number renders consistently.
   string            Money(const double value,const string currency) const;
   string            Signed(const double value,const int digits=2) const;
   string            Percent(const double value,const int digits=2) const;

public:
                     CDashboardPanel(CObjectPainter *painter,CUiTheme *theme,
                                     ILogger *logger);
                    ~CDashboardPanel(void);

   void              SetOrigin(const int x,const int y);
   void              SetEnabled(const bool enabled);
   void              SetRefreshMs(const int ms);
   void              ToggleCollapsed(void) { m_collapsed=!m_collapsed; }
   bool              IsCollapsed(void) const { return(m_collapsed); }

   bool              Create(void);
   void              Destroy(void);
   //--- Repaints only when the interval has elapsed. Safe to call every
   //--- tick; the throttle is internal so callers need not manage it.
   bool              Refresh(const SDashboardModel &model,const ulong now_ms,
                             const bool force=false);

   bool              IsCreated(void) const { return(m_created); }
   long              RepaintCount(void) const { return(m_repaints); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CDashboardPanel::CDashboardPanel(CObjectPainter *painter,CUiTheme *theme,
                                 ILogger *logger)
  : m_painter(painter),
    m_theme(theme),
    m_logger(logger),
    m_origin_x(12),
    m_origin_y(22),
    m_enabled(true),
    m_created(false),
    m_collapsed(false),
    m_refresh_ms(500),
    m_last_refresh_ms(0),
    m_repaints(0),
    m_cursor_y(0),
    m_row_index(0)
  {
  }
//+------------------------------------------------------------------+
CDashboardPanel::~CDashboardPanel(void)
  {
   Destroy();
  }
//+------------------------------------------------------------------+
void CDashboardPanel::SetOrigin(const int x,const int y)
  {
   m_origin_x=(x<0 ? 0 : x);
   m_origin_y=(y<0 ? 0 : y);
  }
//+------------------------------------------------------------------+
void CDashboardPanel::SetEnabled(const bool enabled)
  {
   m_enabled=enabled;
   if(!enabled && m_created)
      Destroy();
  }
//+------------------------------------------------------------------+
void CDashboardPanel::SetRefreshMs(const int ms)
  {
   if(ms>=0)
      m_refresh_ms=ms;
  }
//+------------------------------------------------------------------+
string CDashboardPanel::Money(const double value,const string currency) const
  {
   return(DoubleToString(value,2)+(StringLen(currency)>0 ? " "+currency : ""));
  }
//+------------------------------------------------------------------+
string CDashboardPanel::Signed(const double value,const int digits) const
  {
   //--- Explicit plus sign: a trader scanning the panel should see
   //--- direction without reading the colour, which matters for
   //--- colour-blind users and for screenshots.
   return((value>0.0 ? "+" : "")+DoubleToString(value,digits));
  }
//+------------------------------------------------------------------+
string CDashboardPanel::Percent(const double value,const int digits) const
  {
   return(DoubleToString(value,digits)+"%");
  }
//+------------------------------------------------------------------+
bool CDashboardPanel::Create(void)
  {
   if(!m_enabled || m_painter==NULL || m_theme==NULL)
      return(false);
   m_created=true;
   return(true);
  }
//+------------------------------------------------------------------+
void CDashboardPanel::Destroy(void)
  {
   if(m_painter!=NULL)
      m_painter.RemoveGroup("dash");
   m_created=false;
  }
//+------------------------------------------------------------------+
int CDashboardPanel::DrawSeparator(const string group,int y)
  {
   const int width=m_theme.PanelWidth()-m_theme.Padding()*2;
   m_painter.Separator(m_painter.NameIndexed("dash",group+"sep",m_row_index),
                       m_origin_x+m_theme.Padding(),y,width,m_theme.Border());
   m_row_index++;
   return(y+6);
  }
//+------------------------------------------------------------------+
int CDashboardPanel::DrawSection(const string title,int y)
  {
   m_painter.Label(m_painter.NameIndexed("dash","section",m_row_index),
                   m_origin_x+m_theme.Padding(),y,title,
                   m_theme.Accent(),m_theme.BodySize(),m_theme.Font());
   m_row_index++;
   return(y+m_theme.RowHeight());
  }
//+------------------------------------------------------------------+
int CDashboardPanel::DrawRow(const string group,const string key,
                             const string value,
                             const ENUM_SRP_UI_TONE tone,int y)
  {
   const int width=m_theme.PanelWidth()-m_theme.Padding()*2;
   m_painter.KeyValue(m_painter.NameIndexed("dash",group,m_row_index),
                      m_origin_x+m_theme.Padding(),y,width,
                      key,value,
                      m_theme.Label(),m_theme.ForTone(tone),
                      m_theme.BodySize(),m_theme.Font());
   m_row_index++;
   return(y+m_theme.RowHeight());
  }
//+------------------------------------------------------------------+
int CDashboardPanel::DrawBar(const string group,const string key,
                             const double ratio,
                             const ENUM_SRP_UI_TONE tone,int y)
  {
   const int width=m_theme.PanelWidth()-m_theme.Padding()*2;
   m_painter.Label(m_painter.NameIndexed("dash",group+"lbl",m_row_index),
                   m_origin_x+m_theme.Padding(),y,key,
                   m_theme.Label(),m_theme.BodySize(),m_theme.Font());
   m_row_index++;
   const int bar_y=y+m_theme.RowHeight()-3;
   m_painter.ProgressBar(m_painter.NameIndexed("dash",group+"bar",m_row_index),
                         m_origin_x+m_theme.Padding(),bar_y,width,4,
                         ratio,m_theme.ForTone(tone),m_theme.Muted());
   m_row_index++;
   return(bar_y+9);
  }
//+------------------------------------------------------------------+
int CDashboardPanel::DrawHeader(const SDashboardModel &model,int y)
  {
   const string title=StringFormat("%s  %s",
                                   (StringLen(model.symbol)>0 ? model.symbol : "-"),
                                   (StringLen(model.product_version)>0
                                    ? "v"+model.product_version : ""));
   m_painter.Label(m_painter.Name("dash","title"),
                   m_origin_x+m_theme.Padding(),y,title,
                   m_theme.Title(),m_theme.TitleSize(),m_theme.Font());
   y+=m_theme.RowHeight()+2;

   //--- Engine state and health on one line, colour-coded by health tone.
   const string state_text=StringFormat("%s | %s",
                                        (StringLen(model.engine_state)>0
                                         ? model.engine_state : "UNKNOWN"),
                                        (StringLen(model.health_text)>0
                                         ? model.health_text : "OK"));
   m_painter.Label(m_painter.Name("dash","state"),
                   m_origin_x+m_theme.Padding(),y,state_text,
                   m_theme.ForTone(model.health_tone),
                   m_theme.BodySize(),m_theme.Font());
   y+=m_theme.RowHeight();
   return(y);
  }
//+------------------------------------------------------------------+
bool CDashboardPanel::Refresh(const SDashboardModel &model,const ulong now_ms,
                              const bool force)
  {
   if(!m_enabled || !m_created || m_painter==NULL || m_theme==NULL)
      return(false);

   //--- THROTTLE. The trading path calls this every tick; repainting
   //--- every tick would cost more than the pipeline itself.
   if(!force && m_refresh_ms>0 && m_last_refresh_ms>0 &&
      now_ms-m_last_refresh_ms<(ulong)m_refresh_ms)
      return(false);
   m_last_refresh_ms=now_ms;

   m_row_index=0;
   int y=m_origin_y;

   //--- Background panel sized to content. Height is recomputed each
   //--- repaint so a collapsed panel does not leave a large empty box.
   const int content_height=(m_collapsed ? 66 : 430);
   m_painter.Panel(m_painter.Name("dash","bg"),
                   m_origin_x,m_origin_y-4,
                   m_theme.PanelWidth(),content_height,
                   m_theme.Panel(),m_theme.Border());

   y=DrawHeader(model,y);

   if(m_collapsed)
     {
      //--- Collapsed shows only the single most important number.
      DrawRow("c","Equity",Money(model.equity,model.currency),
              m_theme.ToneForValue(model.floating_profit),y);
      //--- The signal survives collapse too: it is the one line a trader
      //--- glancing at a collapsed panel still needs to see.
      DrawRow("c","Signal",
              CStringUtils::Truncate((StringLen(model.signal_text)>0
                                      ? model.signal_text : "WAITING"),26),
              model.signal_tone,y+m_theme.RowHeight());
      m_repaints++;
      ChartRedraw(0);
      return(true);
     }

   y=DrawSeparator("sig0",y);

   //=== SIGNAL ======================================================
   //--- Placed FIRST, immediately under the header, so the bot's current
   //--- opinion - BUY, SELL, or the named reason it is waiting - is the
   //--- first thing a trader sees rather than a line buried below the
   //--- account and performance blocks.
   y=DrawSection("SIGNAL",y);
   y=DrawRow("sig","Signal",
             CStringUtils::Truncate((StringLen(model.signal_text)>0
                                     ? model.signal_text : "WAITING"),30),
             model.signal_tone,y);
   y=DrawRow("sig","Strategy",
             CStringUtils::Truncate((StringLen(model.strategy_text)>0
                                     ? model.strategy_text : "-"),30),
             SRP_UI_TONE_ACCENT,y);

   y=DrawSeparator("a",y);

   //=== ACCOUNT ====================================================
   y=DrawSection("ACCOUNT",y);
   y=DrawRow("acc","Balance",Money(model.balance,model.currency),
             SRP_UI_TONE_NEUTRAL,y);
   y=DrawRow("acc","Equity",Money(model.equity,model.currency),
             SRP_UI_TONE_NEUTRAL,y);
   y=DrawRow("acc","Margin",Money(model.margin_used,model.currency),
             SRP_UI_TONE_MUTED,y);
   y=DrawRow("acc","Floating",Signed(model.floating_profit),
             m_theme.ToneForValue(model.floating_profit),y);

   y=DrawSeparator("b",y);

   //=== PERIOD RESULTS =============================================
   y=DrawSection("PROFIT",y);
   y=DrawRow("pl","Today",
             StringFormat("%s (%s)",Signed(model.today_profit),
                          Percent(model.today_profit_percent)),
             m_theme.ToneForValue(model.today_profit),y);
   y=DrawRow("pl","This week",Signed(model.week_profit),
             m_theme.ToneForValue(model.week_profit),y);
   y=DrawRow("pl","This month",Signed(model.month_profit),
             m_theme.ToneForValue(model.month_profit),y);

   y=DrawSeparator("c",y);

   //=== PERFORMANCE ================================================
   y=DrawSection("PERFORMANCE",y);
   //--- Win rate as a bar: a proportion reads faster graphically.
   y=DrawBar("wr",StringFormat("Win rate  %s (%d trades)",
                               Percent(model.win_rate,1),model.total_trades),
             model.win_rate/100.0,
             (model.win_rate>=50.0 ? SRP_UI_TONE_POSITIVE
                                   : SRP_UI_TONE_WARNING),y);
   //--- Profit factor above 1.0 is the break-even line, so the tone
   //--- pivots there rather than at an arbitrary threshold.
   y=DrawRow("perf","Profit factor",DoubleToString(model.profit_factor,2),
             (model.profit_factor>=1.0 ? SRP_UI_TONE_POSITIVE
                                       : SRP_UI_TONE_NEGATIVE),y);
   y=DrawRow("perf","Average RR",DoubleToString(model.average_rr,2),
             (model.average_rr>=1.0 ? SRP_UI_TONE_POSITIVE
                                    : SRP_UI_TONE_WARNING),y);

   y=DrawSeparator("d",y);

   //=== EXECUTION ==================================================
   y=DrawSection("EXECUTION",y);
   y=DrawRow("exe","Spread",DoubleToString(model.spread_points,1)+" pts",
             SRP_UI_TONE_NEUTRAL,y);
   y=DrawRow("exe","Latency",DoubleToString(model.latency_ms,0)+" ms",
             //--- Above 500 ms is materially slow for a scalper.
             (model.latency_ms>500.0 ? SRP_UI_TONE_WARNING
                                     : SRP_UI_TONE_NEUTRAL),y);

   y=DrawSeparator("e",y);

   //=== CONTEXT ====================================================
   y=DrawSection("CONTEXT",y);
   y=DrawRow("ctx","Session",
             (StringLen(model.session_text)>0 ? model.session_text : "-"),
             (model.session_blocked ? SRP_UI_TONE_WARNING
                                    : SRP_UI_TONE_NEUTRAL),y);
   y=DrawRow("ctx","News",
             (StringLen(model.news_countdown)>0 ? model.news_countdown : "-"),
             (model.news_paused ? SRP_UI_TONE_CRITICAL
                                : SRP_UI_TONE_NEUTRAL),y);

   y=DrawSeparator("f",y);

   //=== EXPOSURE ===================================================
   y=DrawSection("EXPOSURE",y);
   y=DrawRow("exp","Open trades",IntegerToString(model.open_trades),
             (model.open_trades>0 ? SRP_UI_TONE_ACCENT
                                  : SRP_UI_TONE_MUTED),y);
   y=DrawRow("exp","Risk",Percent(model.risk_percent),
             (model.risk_percent>2.0 ? SRP_UI_TONE_WARNING
                                     : SRP_UI_TONE_NEUTRAL),y);
   y=DrawRow("exp","Lot size",DoubleToString(model.lot_size,2),
             SRP_UI_TONE_NEUTRAL,y);

   m_repaints++;
   //--- One redraw per repaint, not one per object.
   ChartRedraw(0);
   return(true);
  }
//+------------------------------------------------------------------+
string CDashboardPanel::Describe(void) const
  {
   return(StringFormat("panel: %s%s repaints=%I64d every %dms",
                       (m_created ? "created" : "not created"),
                       (m_collapsed ? " (collapsed)" : ""),
                       m_repaints,m_refresh_ms));
  }

#endif // SRP_INTERFACE_DASHBOARD_CDASHBOARDPANEL_MQH
//+------------------------------------------------------------------+
