//+------------------------------------------------------------------+
//|                                             P4PanelCheck.mq5 |
//|   Phase 4 harness: theme + painter + dashboard panel.              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Interface/Dashboard/CDashboardPanel.mqh>
#include <ScalpRobotPro/Logger/CLogger.mqh>
#include <ScalpRobotPro/Logger/CTerminalLogSink.mqh>

void OnStart(void)
  {
   CLogger *logger=new CLogger(SRP_LOG_DEBUG);
   logger.AddSink(new CTerminalLogSink(SRP_LOG_DEBUG));
   logger.Open();

   //=== THEME ========================================================
   CUiTheme *theme=new CUiTheme(SRP_UI_THEME_DARK);
   theme.SetPanelWidth(268);
   theme.SetRowHeight(15);
   theme.SetFontSizes(10,8);
   Print("theme=",EnumToString(theme.Theme()),
         " panelWidth=",theme.PanelWidth(),
         " rowHeight=",theme.RowHeight());
   Print("tones: pos=",theme.ForTone(SRP_UI_TONE_POSITIVE),
         " neg=",theme.ForTone(SRP_UI_TONE_NEGATIVE),
         " warn=",theme.ForTone(SRP_UI_TONE_WARNING));
   Print("forValue(+5)=",theme.ForValue(5.0),
         " forValue(-5)=",theme.ForValue(-5.0),
         " tone(0)=",EnumToString(theme.ToneForValue(0.0)));
   //--- All three variants must resolve.
   theme.SetTheme(SRP_UI_THEME_LIGHT);
   theme.SetTheme(SRP_UI_THEME_CONTRAST);
   theme.SetTheme(SRP_UI_THEME_DARK);
   Print("overlays: bull=",theme.BullZone()," bear=",theme.BearZone(),
         " gap=",theme.GapZone()," liq=",theme.Liquidity(),
         " struct=",theme.Structure()," session=",theme.SessionBox());

   //=== PAINTER ======================================================
   CObjectPainter *painter=new CObjectPainter(theme,logger,"SRP4T_");
   painter.Attach(0,0,CORNER_LEFT_UPPER);

   //--- Panel primitives.
   painter.Panel(painter.Name("t","panel"),10,20,200,80,
                 theme.Panel(),theme.Border());
   painter.Label(painter.Name("t","label"),14,24,"test label",
                 theme.Title(),9,theme.Font());
   painter.KeyValue(painter.Name("t","kv"),14,40,180,"Key","Value",
                    theme.Label(),theme.Value(),8,theme.Font());
   painter.ProgressBar(painter.Name("t","bar"),14,56,180,4,0.65,
                       theme.ForTone(SRP_UI_TONE_POSITIVE),theme.Muted());
   painter.ProgressBar(painter.Name("t","bar0"),14,64,180,4,0.0,
                       theme.ForTone(SRP_UI_TONE_POSITIVE),theme.Muted());
   painter.Separator(painter.Name("t","sep"),14,72,180,theme.Border());

   //--- Chart overlays.
   const double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   const datetime now=TimeCurrent();
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   datetime t0=now, t1=now;
   double p0=bid, p1=bid;
   if(CopyRates(_Symbol,PERIOD_M1,0,10,rates)==10)
     {
      t0=rates[9].time; t1=rates[0].time;
      p0=rates[9].low;  p1=rates[0].high;
     }
   painter.PriceLine(painter.Name("t","hline"),bid,theme.Accent(),
                     STYLE_DOT,1,"entry");
   painter.TrendLine(painter.Name("t","trend"),t0,p0,t1,p1,
                     theme.Structure(),STYLE_SOLID,1,true);
   painter.Box(painter.Name("t","box"),t0,p0,t1,p1,theme.BullZone(),true,1);
   painter.Arrow(painter.Name("t","arrow"),t1,p1,233,theme.ForTone(SRP_UI_TONE_POSITIVE),1);
   painter.TextAt(painter.Name("t","text"),t1,p1,"label",theme.Title(),8,theme.Font());

   //--- Mutation without recreate.
   painter.UpdateText(painter.Name("t","label"),"updated label");
   painter.UpdateColor(painter.Name("t","label"),theme.Accent());
   painter.UpdatePosition(painter.Name("t","label"),16,24);
   painter.UpdatePrice(painter.Name("t","hline"),bid,0);
   painter.SetVisible(painter.Name("t","text"),false);
   painter.SetVisible(painter.Name("t","text"),true);
   Print(painter.Describe());
   Print("owned=",painter.OwnedCount()," created=",painter.CreatedCount(),
         " failed=",painter.FailedCount()," prefix=",painter.Prefix());

   //--- Group removal must not touch other groups.
   const int removed_group=painter.RemoveGroup("t");
   Print("removedGroup=",removed_group," remaining=",painter.OwnedCount());

   //=== DASHBOARD PANEL =============================================
   CDashboardPanel *panel=new CDashboardPanel(painter,theme,logger);
   panel.SetOrigin(12,22);
   panel.SetEnabled(true);
   panel.SetRefreshMs(0);              // no throttle in the harness
   panel.Create();

   //--- Populate every one of the 18 required metrics.
   SDashboardModel model;
   model.symbol          = _Symbol;
   model.product_version = "1.00";
   model.currency        = AccountInfoString(ACCOUNT_CURRENCY);
   model.balance         = AccountInfoDouble(ACCOUNT_BALANCE);
   model.equity          = AccountInfoDouble(ACCOUNT_EQUITY);
   model.margin_used     = AccountInfoDouble(ACCOUNT_MARGIN);
   model.margin_free     = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   model.floating_profit = 12.34;
   model.today_profit    = 45.67;
   model.today_profit_percent = 0.46;
   model.week_profit     = -12.10;
   model.month_profit    = 210.55;
   model.win_rate        = 62.5;
   model.profit_factor   = 1.85;
   model.average_rr      = 1.42;
   model.total_trades    = 48;
   model.spread_points   = 21.0;
   model.latency_ms      = 87.0;
   model.session_text    = "LONDON +NY";
   model.news_countdown  = "next: CPI in 2h 14m";
   model.strategy_text   = "TrendContinuation";
   model.open_trades     = 2;
   model.risk_percent    = 1.25;
   model.lot_size        = 0.10;
   model.total_volume    = 0.20;
   model.engine_state    = "TRADING";
   model.health_text     = "OK";
   model.health_tone     = SRP_UI_TONE_POSITIVE;
   model.updated_at      = now;
   model.is_valid        = true;

   panel.Refresh(model,GetTickCount64(),true);
   Print(panel.Describe());

   //--- Collapsed mode and the warning/critical tone paths.
   panel.ToggleCollapsed();
   panel.Refresh(model,GetTickCount64(),true);
   Print("collapsed=",panel.IsCollapsed());
   panel.ToggleCollapsed();

   model.news_paused     = true;
   model.session_blocked = true;
   model.latency_ms      = 850.0;
   model.risk_percent    = 3.5;
   model.profit_factor   = 0.75;
   model.win_rate        = 33.0;
   model.health_tone     = SRP_UI_TONE_CRITICAL;
   panel.Refresh(model,GetTickCount64(),true);
   Print("repaints=",panel.RepaintCount());

   Print("=== P4 PANEL CHECK COMPLETE ===");

   panel.Destroy();
   delete panel;
   //--- Painter destructor must leave the chart clean.
   delete painter;
   delete theme;
   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
