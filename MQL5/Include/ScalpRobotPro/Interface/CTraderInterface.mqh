//+------------------------------------------------------------------+
//|                                          CTraderInterface.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   RESPONSIBILITY (one only): compose the five Phase 4 subsystems and   |
//|   sequence their calls. It contains no UI drawing, no statistics and   |
//|   no file I/O - every line here is delegation.                        |
//|                                                                  |
//|   This is the FACADE the Expert Advisor talks to. Without it the EA    |
//|   would have to construct a theme, a painter, a panel, an overlay, a   |
//|   trade manager, a logger and an analytics engine in the right order   |
//|   and tear them down in the reverse order - seven chances to leak a    |
//|   chart object or a file handle in OnInit alone.                      |
//|                                                                  |
//|   OWNERSHIP IS TOTAL AND EXPLICIT: this class news and deletes theme,  |
//|   painter, panel, overlay, trade manager, logger and analytics. It     |
//|   BORROWS the Phase 2 analysis modules (zones, swings, structure,      |
//|   ATR), which belong to the engine. Destruction is strictly reverse    |
//|   of construction, and the painter is deleted last of the visual       |
//|   objects because panel and overlay reference it.                      |
//|                                                                  |
//|   IT DECIDES NOTHING ABOUT TRADING. Position management produces       |
//|   intents that are handed back to the caller; the Phase 1 trade        |
//|   engine executes them. The interface layer never sends an order.      |
//|                                                                  |
//|   THE LOGGER IS AN ILogger. Because CEnterpriseLogger implements the   |
//|   Phase 1 interface, the EA can pass Interface.Logger() to every       |
//|   Phase 1-3 module and their output lands in the channelled files      |
//|   with zero changes to those modules.                                  |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_CTRADERINTERFACE_MQH
#define SRP_INTERFACE_CTRADERINTERFACE_MQH

#include "Analytics/CPerformanceAnalytics.mqh"
#include "Chart/CChartOverlay.mqh"
#include "Dashboard/CDashboardPanel.mqh"
#include "Dashboard/CObjectPainter.mqh"
#include "Dashboard/CUiTheme.mqh"
#include "Logging/CEnterpriseLogger.mqh"
#include "Manager/CTradeManager.mqh"
#include "Types/InterfaceStructs.mqh"

class CTraderInterface
  {
private:
   //--- OWNED, deleted in reverse construction order.
   CEnterpriseLogger     *m_logger;
   CUiTheme              *m_theme;
   CObjectPainter        *m_painter;
   CDashboardPanel       *m_panel;
   CChartOverlay         *m_overlay;
   CTradeManager         *m_manager;
   CPerformanceAnalytics *m_analytics;

   string                 m_symbol;
   ENUM_TIMEFRAMES        m_timeframe;
   bool                   m_initialized;
   bool                   m_dashboard_enabled;
   bool                   m_overlay_enabled;
   datetime               m_last_bar;
   long                   m_ticks;
   //--- HARNESS v2, FIX 4. One comma-free provenance line, handed down by
   //--- the engine and written as the first line of every exported file.
   //--- Held as a plain string rather than a pointer to the provenance
   //--- object so that the Interface layer takes no dependency on Runtime\.
   string                 m_report_preamble;

   void                   Teardown(void);
   //--- HARNESS v2, FIX 4. The line actually written. Never empty: a data
   //--- file carrying no provenance line at all is indistinguishable from
   //--- one written before this fix existed, so the missing case is stated
   //--- rather than left as an absence for the reader to notice.
   string                 EffectivePreamble(void) const;

public:
                     CTraderInterface(const string symbol,
                                      const ENUM_TIMEFRAMES timeframe,
                                      const double initial_balance,
                                      const ENUM_SRP_UI_THEME theme=SRP_UI_THEME_DARK,
                                      const string object_prefix="SRP_UI_");
                    ~CTraderInterface(void);

   //=== LIFECYCLE ====================================================
   //--- Opens the log channels, attaches the painter and creates the
   //--- panel. Returns false only if a subsystem failed to construct;
   //--- a refused log file is a warning, not a fatal condition.
   bool              Initialize(CAtrIntel *atr,
                                CZoneRegistry *zones,
                                CSwingDetector *swings,
                                CMarketStructure *structure);
   void              Shutdown(void);
   bool              IsInitialized(void) const { return(m_initialized); }
   bool              Validate(SValidationResult &result) const;

   //=== PER-TICK =====================================================
   //--- Repaints the dashboard (throttled internally) and redraws the
   //--- analysis overlay (bar-gated internally). Safe to call per tick.
   void              Render(const SDashboardModel &model);
   //--- Fills the analytics-derived fields of the model from the closed
   //--- trade history, so the caller only has to supply live account and
   //--- market data. This is the seam where analytics reaches the UI.
   void              ApplyAnalytics(SDashboardModel &model);

   //=== POSITION MANAGEMENT ==========================================
   //--- Tracks the position, draws its markup and returns the single
   //--- highest-priority intent. The caller executes it.
   bool              ManagePosition(const SManagedPosition &position,
                                    STradeIntent &intent);
   //--- Confirmations from the trade engine, so tracked stage flags
   //--- reflect what actually happened rather than what was intended.
   void              ConfirmStopMoved(const ulong ticket,const double new_stop,
                                      const ENUM_SRP_TM_TRIGGER trigger);
   void              ConfirmScaledIn(const ulong ticket);
   void              ConfirmScaledOut(const ulong ticket);
   //--- Records the close, updates analytics and clears the chart markup.
   void              OnTradeClosed(const SClosedTrade &trade);
   void              OnTradeOpened(const SManagedPosition &position,
                                   const string strategy);

   //=== VIEW CONTROL =================================================
   void              SetDashboardEnabled(const bool enabled);
   void              SetOverlayEnabled(const bool enabled);
   void              SetLayerEnabled(const ENUM_SRP_DRAW_LAYER layer,
                                     const bool enabled);
   void              SetTheme(const ENUM_SRP_UI_THEME theme);
   void              ToggleCollapsed(void);
   void              RedrawAll(void);
   void              ClearChart(void);

   //=== REPORTING ====================================================
   //--- Writes the session's reports to the Journal and to CSV. Called
   //--- from OnDeinit or on operator demand.
   void              PublishSessionReport(void);
   bool              ExportAll(const string folder="");
   //--- HARNESS v2, FIX 4. Set by the engine before either of the two calls
   //--- above. Empty is legal and means "no provenance was supplied", which
   //--- is itself reported rather than silently producing a bare file.
   void              SetReportPreamble(const string line)
     { m_report_preamble=line; }
   string            ReportPreamble(void) const { return(m_report_preamble); }

   //=== ACCESS =======================================================
   //--- Borrowed pointers. The caller must not delete them.
   CEnterpriseLogger     *Logger(void)    { return(m_logger); }
   CPerformanceAnalytics *Analytics(void) { return(m_analytics); }
   CTradeManager         *Manager(void)   { return(m_manager); }
   CDashboardPanel       *Panel(void)     { return(m_panel); }
   CChartOverlay         *Overlay(void)   { return(m_overlay); }
   CUiTheme              *Theme(void)     { return(m_theme); }
   CObjectPainter        *Painter(void)   { return(m_painter); }

   long              TickCount(void) const { return(m_ticks); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CTraderInterface::CTraderInterface(const string symbol,
                                   const ENUM_TIMEFRAMES timeframe,
                                   const double initial_balance,
                                   const ENUM_SRP_UI_THEME theme,
                                   const string object_prefix)
  : m_logger(NULL),
    m_theme(NULL),
    m_painter(NULL),
    m_panel(NULL),
    m_overlay(NULL),
    m_manager(NULL),
    m_analytics(NULL),
    m_symbol(symbol),
    m_timeframe(timeframe),
    m_initialized(false),
    m_dashboard_enabled(true),
    m_overlay_enabled(true),
    m_last_bar(0),
    m_ticks(0),
    m_report_preamble("")
  {
   //--- Construction order matters: the logger first, because every other
   //--- subsystem takes it by injection.
   m_logger=new CEnterpriseLogger(symbol);
   m_theme=new CUiTheme(theme);
   m_painter=new CObjectPainter(m_theme,m_logger,object_prefix);
   m_panel=new CDashboardPanel(m_painter,m_theme,m_logger);
   m_overlay=new CChartOverlay(m_painter,m_theme,symbol,timeframe,m_logger);
   m_analytics=new CPerformanceAnalytics(symbol,initial_balance,m_logger);
   //--- The trade manager needs an ATR that only the engine owns, so it
   //--- is constructed in Initialize() once that pointer is available.
  }
//+------------------------------------------------------------------+
CTraderInterface::~CTraderInterface(void)
  {
   Teardown();
  }
//+------------------------------------------------------------------+
void CTraderInterface::Teardown(void)
  {
   //--- Strict reverse order. Panel and overlay both hold the painter,
   //--- so they must die before it does.
   if(m_analytics!=NULL) { delete m_analytics; m_analytics=NULL; }
   if(m_manager!=NULL)   { delete m_manager;   m_manager=NULL;   }
   if(m_overlay!=NULL)   { delete m_overlay;   m_overlay=NULL;   }
   if(m_panel!=NULL)     { delete m_panel;     m_panel=NULL;     }
   if(m_painter!=NULL)   { delete m_painter;   m_painter=NULL;   }
   if(m_theme!=NULL)     { delete m_theme;     m_theme=NULL;     }
   //--- Logger last: everything above may log while it shuts down.
   if(m_logger!=NULL)
     {
      m_logger.Close();
      delete m_logger;
      m_logger=NULL;
     }
   m_initialized=false;
  }
//+------------------------------------------------------------------+
bool CTraderInterface::Initialize(CAtrIntel *atr,
                                  CZoneRegistry *zones,
                                  CSwingDetector *swings,
                                  CMarketStructure *structure)
  {
   if(m_logger==NULL || m_theme==NULL || m_painter==NULL ||
      m_panel==NULL || m_overlay==NULL || m_analytics==NULL)
      return(false);

   //--- File logging is best-effort: a sandbox that forbids writes must
   //--- not stop the EA, it falls back to the Journal.
   if(!m_logger.Open())
      m_logger.SetMirrorErrorsToJournal(true);

   if(m_manager==NULL)
      m_manager=new CTradeManager(m_symbol,atr,m_logger);
   if(m_manager==NULL)
      return(false);

   m_painter.Attach(0,0,CORNER_LEFT_UPPER);
   m_overlay.SetSources(zones,swings,structure);

   m_panel.SetEnabled(m_dashboard_enabled);
   m_panel.Create();
   m_overlay.SetEnabled(m_overlay_enabled);

   m_initialized=true;
   m_logger.Info("TraderInterface",
                 "initialised "+m_symbol+" "+EnumToString(m_timeframe));
   return(true);
  }
//+------------------------------------------------------------------+
void CTraderInterface::Shutdown(void)
  {
   if(m_logger!=NULL)
      m_logger.Info("TraderInterface","shutdown, ticks="+
                    IntegerToString(m_ticks));
   //--- Chart objects go first so the chart is clean even if the caller
   //--- keeps the facade alive afterwards.
   ClearChart();
   if(m_logger!=NULL)
      m_logger.Flush();
   m_initialized=false;
  }
//+------------------------------------------------------------------+
bool CTraderInterface::Validate(SValidationResult &result) const
  {
   if(m_logger==NULL)     result.AddError("logger not constructed");
   if(m_theme==NULL)      result.AddError("theme not constructed");
   if(m_painter==NULL)    result.AddError("painter not constructed");
   if(m_panel==NULL)      result.AddError("dashboard panel not constructed");
   if(m_overlay==NULL)    result.AddError("chart overlay not constructed");
   if(m_analytics==NULL)  result.AddError("analytics not constructed");
   if(m_manager==NULL)    result.AddWarning("trade manager not constructed yet, "
                                            "Initialize() has not run");
   if(m_symbol=="")       result.AddError("symbol is empty");

   if(m_logger!=NULL)
      m_logger.Validate(result);
   if(m_analytics!=NULL)
      m_analytics.Validate(result);
   if(m_manager!=NULL)
      m_manager.Validate(result);
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
void CTraderInterface::Render(const SDashboardModel &model)
  {
   m_ticks++;
   if(!m_initialized)
      return;

   //--- Both callees are self-throttling, so this stays cheap per tick.
   if(m_dashboard_enabled && m_panel!=NULL)
      m_panel.Refresh(model,GetTickCount64(),false);

   if(m_overlay_enabled && m_overlay!=NULL)
     {
      const datetime bar=iTime(m_symbol,m_timeframe,0);
      m_overlay.DrawAnalysis(bar,model,false);
      m_last_bar=bar;
     }
  }
//+------------------------------------------------------------------+
void CTraderInterface::ApplyAnalytics(SDashboardModel &model)
  {
   if(m_analytics==NULL)
      return;

   SAnalyticsReport all;
   m_analytics.AllTime(all);
   //--- Only overwrite what analytics owns. Account and market fields
   //--- belong to the caller and are left untouched.
   model.win_rate      = all.win_rate;
   model.profit_factor = all.profit_factor;
   model.total_trades  = all.total_trades;
   model.average_rr    = (all.average_r_multiple!=0.0
                          ? all.average_r_multiple
                          : all.payoff_ratio);
   model.today_profit  = m_analytics.PeriodProfit(SRP_PA_PERIOD_DAY);
   model.week_profit   = m_analytics.PeriodProfit(SRP_PA_PERIOD_WEEK);
   model.month_profit  = m_analytics.PeriodProfit(SRP_PA_PERIOD_MONTH);
   if(model.balance>0.0)
      model.today_profit_percent=model.today_profit*100.0/model.balance;

   //--- Latency comes from the execution-time channel, which is the only
   //--- place that has measured it.
   if(m_logger!=NULL && m_logger.ExecutionSamples()>0)
      model.latency_ms=m_logger.AverageExecutionMs();
  }
//+------------------------------------------------------------------+
bool CTraderInterface::ManagePosition(const SManagedPosition &position,
                                      STradeIntent &intent)
  {
   intent.Reset();
   if(!m_initialized || m_manager==NULL)
      return(false);

   //--- Track before evaluating: the ATR exit and the profit lock both
   //--- measure from the peak excursion, which only tracking knows.
   m_manager.Track(position);

   if(m_overlay_enabled && m_overlay!=NULL)
     {
      m_overlay.DrawEntry(position);
      m_overlay.DrawStops(position);
      m_overlay.DrawTradeLabel(position);
     }

   if(!m_manager.Evaluate(position,intent))
      return(false);

   //--- A moved stop is drawn as the trailing line so the trader sees
   //--- the proposal, not just the fill.
   if(intent.action==SRP_TM_MOVE_STOP && m_overlay_enabled && m_overlay!=NULL)
      m_overlay.DrawTrailing(position,intent.new_stop);

   if(m_logger!=NULL)
      m_logger.LogTradeIntent(intent);
   return(true);
  }
//+------------------------------------------------------------------+
void CTraderInterface::ConfirmStopMoved(const ulong ticket,
                                        const double new_stop,
                                        const ENUM_SRP_TM_TRIGGER trigger)
  {
   if(m_manager!=NULL)
      m_manager.NotifyStopMoved(ticket,new_stop,trigger);
   if(m_logger!=NULL)
      m_logger.LogTrade("TradeManager",
                        "stop moved ("+CTradeManager::TriggerToString(trigger)+")",
                        ticket,new_stop,0.0,0.0);
  }
//+------------------------------------------------------------------+
void CTraderInterface::ConfirmScaledIn(const ulong ticket)
  {
   if(m_manager!=NULL)
      m_manager.NotifyScaledIn(ticket);
   if(m_logger!=NULL)
      m_logger.LogTrade("TradeManager","scaled in",ticket,0.0,0.0,0.0);
  }
//+------------------------------------------------------------------+
void CTraderInterface::ConfirmScaledOut(const ulong ticket)
  {
   if(m_manager!=NULL)
      m_manager.NotifyScaledOut(ticket);
   if(m_logger!=NULL)
      m_logger.LogTrade("TradeManager","scaled out",ticket,0.0,0.0,0.0);
  }
//+------------------------------------------------------------------+
void CTraderInterface::OnTradeOpened(const SManagedPosition &position,
                                     const string strategy)
  {
   if(m_logger!=NULL)
      m_logger.LogTradeOpened(position,strategy);
   if(m_overlay_enabled && m_overlay!=NULL)
     {
      m_overlay.DrawEntry(position);
      m_overlay.DrawStops(position);
      m_overlay.DrawTradeLabel(position);
     }
  }
//+------------------------------------------------------------------+
void CTraderInterface::OnTradeClosed(const SClosedTrade &trade)
  {
   if(m_analytics!=NULL)
      m_analytics.AddTrade(trade);
   if(m_logger!=NULL)
      m_logger.LogTradeClosed(trade);
   //--- Stop tracking and remove the markup; a closed ticket that keeps
   //--- its lines on the chart is the classic dashboard bug.
   if(m_manager!=NULL)
      m_manager.Untrack(trade.ticket);
   if(m_overlay!=NULL)
      m_overlay.ClearTrade(trade.ticket);
  }
//+------------------------------------------------------------------+
void CTraderInterface::SetDashboardEnabled(const bool enabled)
  {
   m_dashboard_enabled=enabled;
   if(m_panel==NULL)
      return;
   m_panel.SetEnabled(enabled);
   if(enabled)
      m_panel.Create();
   else
      m_panel.Destroy();
  }
//+------------------------------------------------------------------+
void CTraderInterface::SetOverlayEnabled(const bool enabled)
  {
   m_overlay_enabled=enabled;
   if(m_overlay==NULL)
      return;
   m_overlay.SetEnabled(enabled);
   if(!enabled)
      m_overlay.ClearAll();
  }
//+------------------------------------------------------------------+
void CTraderInterface::SetLayerEnabled(const ENUM_SRP_DRAW_LAYER layer,
                                       const bool enabled)
  {
   if(m_overlay!=NULL)
      m_overlay.SetLayerEnabled(layer,enabled);
  }
//+------------------------------------------------------------------+
void CTraderInterface::SetTheme(const ENUM_SRP_UI_THEME theme)
  {
   if(m_theme==NULL)
      return;
   m_theme.SetTheme(theme);
   //--- Colours are baked into existing objects, so a theme change means
   //--- a full rebuild rather than a repaint.
   RedrawAll();
  }
//+------------------------------------------------------------------+
void CTraderInterface::ToggleCollapsed(void)
  {
   if(m_panel!=NULL)
      m_panel.ToggleCollapsed();
  }
//+------------------------------------------------------------------+
void CTraderInterface::RedrawAll(void)
  {
   if(m_panel!=NULL)
     {
      m_panel.Destroy();
      if(m_dashboard_enabled)
         m_panel.Create();
     }
   if(m_overlay!=NULL)
      m_overlay.ClearAll();
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
void CTraderInterface::ClearChart(void)
  {
   if(m_overlay!=NULL)
      m_overlay.ClearAll();
   if(m_panel!=NULL)
      m_panel.Destroy();
   //--- Only tracked objects are deleted, so a foreign indicator's
   //--- objects on the same chart survive.
   if(m_painter!=NULL)
      m_painter.RemoveAllOwned();
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
void CTraderInterface::PublishSessionReport(void)
  {
   if(m_analytics==NULL || m_logger==NULL)
      return;

   //--- HARNESS v2, FIX 4. The provenance line precedes the tables in the
   //--- Journal too. The engine already printed the full block, but this is
   //--- the copy that stays attached to the tables themselves when someone
   //--- selects them out of a long journal and pastes them somewhere else.
   //---
   //--- IT IS PRINTED ABOVE THE NO-TRADES RETURN, not after it. "No closed
   //--- trades" is a result: on a filtered scalper it is the difference
   //--- between a session the gates refused and a tape that never set up,
   //--- and it cannot be read at all without knowing the tick model and the
   //--- cost model that produced it. An empty result with no conditions
   //--- stated is the one report that gets misremembered as "it just does
   //--- not trade".
   Print(EffectivePreamble());

   SAnalyticsReport all;
   if(!m_analytics.AllTime(all))
     {
      m_logger.Info("TraderInterface","no closed trades, no session report");
      return;
     }
   //--- Structured row for the performance CSV, then the readable tables
   //--- for the Journal. Both audiences are served from one call.
   m_logger.LogAnalyticsReport(all);
   Print(m_analytics.FormatReport(all));
   Print(m_analytics.FormatMonthlyTable());
   Print(m_analytics.FormatYearlyTable());
  }
//+------------------------------------------------------------------+
string CTraderInterface::EffectivePreamble(void) const
  {
   if(m_report_preamble!="")
      return(m_report_preamble);
   return("# provenance: NOT SUPPLIED - nothing recorded the tick model; "
          "cost model or data segment behind the rows below; "
          "quotable=no");
  }
//+------------------------------------------------------------------+
bool CTraderInterface::ExportAll(const string folder)
  {
   if(m_analytics==NULL || m_logger==NULL)
      return(false);

   const string base=(folder=="" ? SRP_DATA_FOLDER+"\\Reports" : folder);
   const string stamp=TimeToString(TimeCurrent(),TIME_DATE);
   string safe=stamp;
   StringReplace(safe,".","");

   //--- HARNESS v2, FIX 4. Resolved once so all three files carry the
   //--- identical line and cannot be argued to describe different runs.
   const string preamble=EffectivePreamble();

   bool ok=true;
   //--- The explicit `false` is the common-folder flag: these files belong to
   //--- this terminal's data folder, not the shared one.
   if(!m_analytics.ExportTradesCsv(base+"\\trades_"+safe+".csv",
                                   false,preamble))
      ok=false;
   if(!m_analytics.ExportMonthlyCsv(base+"\\monthly_"+safe+".csv",
                                    false,preamble))
      ok=false;
   if(!m_logger.ExportHistory(base+"\\session_log_"+safe+".csv",
                              SRP_LOG4_FORMAT_CSV,false,preamble))
      ok=false;
   if(!ok)
      m_logger.LogError("TraderInterface","one or more exports failed");
   return(ok);
  }
//+------------------------------------------------------------------+
string CTraderInterface::Describe(void) const
  {
   string text="CTraderInterface["+m_symbol+" "+EnumToString(m_timeframe)+"]";
   text+=" init="+(m_initialized ? "yes" : "no");
   text+=" dashboard="+(m_dashboard_enabled ? "on" : "off");
   text+=" overlay="+(m_overlay_enabled ? "on" : "off");
   text+=" ticks="+IntegerToString(m_ticks);
   if(m_panel!=NULL)
      text+="\n  "+m_panel.Describe();
   if(m_overlay!=NULL)
      text+="\n  "+m_overlay.Describe();
   if(m_manager!=NULL)
      text+="\n  "+m_manager.Describe();
   if(m_analytics!=NULL)
      text+="\n  "+m_analytics.Describe();
   if(m_logger!=NULL)
      text+="\n  "+m_logger.Describe();
   return(text);
  }

#endif // SRP_INTERFACE_CTRADERINTERFACE_MQH
//+------------------------------------------------------------------+
