//+------------------------------------------------------------------+
//|                                              CChartOverlay.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   RESPONSIBILITY (one only): draw the price-chart markup.               |
//|                                                                  |
//|   Fifteen layers: Entries, Stop Loss, Take Profit, Trailing Stop,      |
//|   Order Blocks, Fair Value Gaps, Liquidity, BOS, CHoCH, Support,       |
//|   Resistance, Trend Lines, Session Boxes, Trade Labels, Statistics.    |
//|                                                                  |
//|   READS PHASE 2/3 OUTPUT, DRAWS NOTHING ELSE. It consumes the zone     |
//|   registry, swing detector and structure state rather than recomputing |
//|   anything - the overlay is a view, not a second analysis engine.      |
//|                                                                  |
//|   PER-LAYER VISIBILITY. Each layer can be toggled independently and    |
//|   redraws only its own object group, so hiding order blocks does not   |
//|   disturb the session boxes. That granularity is what keeps a busy     |
//|   chart usable.                                                      |
//|                                                                  |
//|   REDRAWN ON NEW BAR ONLY by default. Zones do not move intrabar, and  |
//|   redrawing dozens of rectangles per tick is the single most expensive |
//|   thing a chart UI can do.                                            |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_CHART_CCHARTOVERLAY_MQH
#define SRP_INTERFACE_CHART_CCHARTOVERLAY_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Intelligence/SmartMoney/CZoneRegistry.mqh"
#include "../../Intelligence/Structure/CSwingDetector.mqh"
#include "../../Intelligence/Structure/CMarketStructure.mqh"
#include "../../Utilities/CStringUtils.mqh"
#include "../Dashboard/CObjectPainter.mqh"
#include "../Dashboard/CUiTheme.mqh"
#include "../Types/InterfaceStructs.mqh"

#define SRP_DRAW_LAYER_COUNT 15

class CChartOverlay
  {
private:
   CObjectPainter   *m_painter;           // borrowed
   CUiTheme         *m_theme;             // borrowed
   ILogger          *m_logger;            // borrowed
   //--- Phase 2 sources, all borrowed.
   CZoneRegistry    *m_zones;
   CSwingDetector   *m_swings;
   CMarketStructure *m_structure;

   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   bool              m_layer_enabled[SRP_DRAW_LAYER_COUNT];
   bool              m_enabled;
   //--- Caps: an unbounded overlay eventually fills the chart with
   //--- hundreds of objects and becomes unreadable and slow.
   int               m_max_zones;
   int               m_max_swings;
   int               m_max_labels;
   int               m_zone_extend_bars;
   datetime          m_last_draw_bar;
   long              m_draws;

   int               LayerIndex(const ENUM_SRP_DRAW_LAYER layer) const
     { return((int)layer); }
   bool              IsLayerOn(const ENUM_SRP_DRAW_LAYER layer) const;
   //--- Right edge for an extended zone rectangle.
   datetime          RightEdge(void) const;
   color             ZoneColor(const SPriceZone &zone) const;

   //--- One method per layer group.
   void              DrawZones(void);
   void              DrawLiquidity(void);
   void              DrawStructureEvents(void);
   void              DrawSupportResistance(void);
   void              DrawTrendLines(void);
   void              DrawSessionBox(const SDashboardModel &model);
   void              DrawStatistics(const SDashboardModel &model);
   void              DrawLiveSignalMarker(const SDashboardModel &model);

public:
                     CChartOverlay(CObjectPainter *painter,CUiTheme *theme,
                                   const string symbol,
                                   const ENUM_TIMEFRAMES timeframe,
                                   ILogger *logger);
                    ~CChartOverlay(void);

   void              SetSources(CZoneRegistry *zones,CSwingDetector *swings,
                                CMarketStructure *structure);
   void              SetEnabled(const bool enabled);
   void              SetLayerEnabled(const ENUM_SRP_DRAW_LAYER layer,
                                     const bool enabled);
   bool              ToggleLayer(const ENUM_SRP_DRAW_LAYER layer);
   void              SetLimits(const int max_zones,const int max_swings,
                               const int max_labels);
   void              SetZoneExtendBars(const int bars);

   //--- Analysis overlays. Bar-gated internally, so calling per tick is
   //--- cheap; pass force=true after a settings change.
   bool              DrawAnalysis(const datetime current_bar,
                                  const SDashboardModel &model,
                                  const bool force=false);

   //=== TRADE MARKUP (called per position, redrawn as levels move) ====
   void              DrawEntry(const SManagedPosition &position);
   void              DrawStops(const SManagedPosition &position);
   void              DrawTrailing(const SManagedPosition &position,
                                  const double trail_price);
   void              DrawTradeLabel(const SManagedPosition &position);
   //--- Removes all markup for one ticket, called when it closes.
   void              ClearTrade(const ulong ticket);

   void              ClearAll(void);
   void              ClearLayer(const ENUM_SRP_DRAW_LAYER layer);

   bool              IsEnabled(void) const { return(m_enabled); }
   long              DrawCount(void) const { return(m_draws); }
   string            Describe(void) const;
   static string     LayerToString(const ENUM_SRP_DRAW_LAYER layer);
  };

//+------------------------------------------------------------------+
CChartOverlay::CChartOverlay(CObjectPainter *painter,CUiTheme *theme,
                             const string symbol,
                             const ENUM_TIMEFRAMES timeframe,
                             ILogger *logger)
  : m_painter(painter),
    m_theme(theme),
    m_logger(logger),
    m_zones(NULL),
    m_swings(NULL),
    m_structure(NULL),
    m_symbol(symbol),
    m_timeframe(timeframe),
    m_enabled(true),
    m_max_zones(12),
    m_max_swings(8),
    m_max_labels(10),
    m_zone_extend_bars(20),
    m_last_draw_bar(0),
    m_draws(0)
  {
   for(int i=0;i<SRP_DRAW_LAYER_COUNT;i++)
      m_layer_enabled[i]=true;
  }
//+------------------------------------------------------------------+
CChartOverlay::~CChartOverlay(void)
  {
   ClearAll();
  }
//+------------------------------------------------------------------+
void CChartOverlay::SetSources(CZoneRegistry *zones,CSwingDetector *swings,
                               CMarketStructure *structure)
  {
   m_zones=zones;
   m_swings=swings;
   m_structure=structure;
  }
//+------------------------------------------------------------------+
void CChartOverlay::SetEnabled(const bool enabled)
  {
   m_enabled=enabled;
   if(!enabled)
      ClearAll();
  }
//+------------------------------------------------------------------+
void CChartOverlay::SetLayerEnabled(const ENUM_SRP_DRAW_LAYER layer,
                                    const bool enabled)
  {
   const int index=LayerIndex(layer);
   if(index<0 || index>=SRP_DRAW_LAYER_COUNT)
      return;
   if(m_layer_enabled[index]==enabled)
      return;
   m_layer_enabled[index]=enabled;
   //--- Turning a layer off must remove its objects immediately, or the
   //--- stale markup stays on the chart until the next full redraw.
   if(!enabled)
      ClearLayer(layer);
  }
//+------------------------------------------------------------------+
bool CChartOverlay::ToggleLayer(const ENUM_SRP_DRAW_LAYER layer)
  {
   const int index=LayerIndex(layer);
   if(index<0 || index>=SRP_DRAW_LAYER_COUNT)
      return(false);
   SetLayerEnabled(layer,!m_layer_enabled[index]);
   return(m_layer_enabled[index]);
  }
//+------------------------------------------------------------------+
bool CChartOverlay::IsLayerOn(const ENUM_SRP_DRAW_LAYER layer) const
  {
   const int index=LayerIndex(layer);
   if(index<0 || index>=SRP_DRAW_LAYER_COUNT)
      return(false);
   return(m_enabled && m_layer_enabled[index]);
  }
//+------------------------------------------------------------------+
void CChartOverlay::SetLimits(const int max_zones,const int max_swings,
                              const int max_labels)
  {
   if(max_zones>=0)  m_max_zones=max_zones;
   if(max_swings>=0) m_max_swings=max_swings;
   if(max_labels>=0) m_max_labels=max_labels;
  }
//+------------------------------------------------------------------+
void CChartOverlay::SetZoneExtendBars(const int bars)
  {
   if(bars>=0)
      m_zone_extend_bars=bars;
  }
//+------------------------------------------------------------------+
datetime CChartOverlay::RightEdge(void) const
  {
   //--- Extend zones into the future so they are visible ahead of price,
   //--- which is where they matter. Period seconds x bars.
   const int seconds=PeriodSeconds(m_timeframe);
   const datetime last=(datetime)SeriesInfoInteger(m_symbol,m_timeframe,
                                                   SERIES_LASTBAR_DATE);
   if(last<=0 || seconds<=0)
      return(TimeCurrent());
   return((datetime)((long)last+(long)seconds*m_zone_extend_bars));
  }
//+------------------------------------------------------------------+
color CChartOverlay::ZoneColor(const SPriceZone &zone) const
  {
   //--- Kind decides the palette; bias decides bull vs bear.
   if(zone.kind==SRP_ZONE_FAIR_VALUE_GAP)
      return(m_theme.GapZone());
   if(zone.kind==SRP_ZONE_LIQUIDITY_POOL)
      return(m_theme.Liquidity());
   return(zone.bias==SRP_BIAS_BULLISH ? m_theme.BullZone()
                                      : m_theme.BearZone());
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawZones(void)
  {
   if(m_zones==NULL)
      return;

   const datetime right=RightEdge();
   int drawn_blocks=0;
   int drawn_gaps=0;
   const int total=m_zones.Count();

   for(int i=0;i<total;i++)
     {
      SPriceZone zone;
      if(!m_zones.At(i,zone))
         continue;
      //--- Only live zones are worth drawing. Consumed ones would clutter
      //--- the chart with levels that no longer mean anything.
      if(!zone.IsActionable())
         continue;

      const bool is_gap=(zone.kind==SRP_ZONE_FAIR_VALUE_GAP);
      const bool is_pool=(zone.kind==SRP_ZONE_LIQUIDITY_POOL);
      if(is_pool)
         continue;                        // drawn by DrawLiquidity

      if(is_gap && !IsLayerOn(SRP_DRAW_FAIR_VALUE_GAPS))
         continue;
      if(!is_gap && !IsLayerOn(SRP_DRAW_ORDER_BLOCKS))
         continue;
      if(is_gap && drawn_gaps>=m_max_zones)
         continue;
      if(!is_gap && drawn_blocks>=m_max_zones)
         continue;

      const string group=(is_gap ? "fvg" : "ob");
      const int index=(is_gap ? drawn_gaps : drawn_blocks);
      m_painter.Box(m_painter.NameIndexed(group,"box",index),
                    zone.formed_at,zone.upper,right,zone.lower,
                    ZoneColor(zone),true,1);

      //--- Strength annotation, so a trader can tell a high-quality zone
      //--- from a marginal one without opening the log.
      if(IsLayerOn(SRP_DRAW_TRADE_LABELS))
         m_painter.TextAt(m_painter.NameIndexed(group,"txt",index),
                          zone.formed_at,zone.upper,
                          StringFormat("%s %.2f",
                                       (is_gap ? "FVG" : "OB"),zone.strength),
                          ZoneColor(zone),m_theme.BodySize()-1,m_theme.Font());

      if(is_gap) drawn_gaps++;
      else       drawn_blocks++;
     }
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawLiquidity(void)
  {
   if(m_zones==NULL || !IsLayerOn(SRP_DRAW_LIQUIDITY))
      return;

   const datetime right=RightEdge();
   int drawn=0;
   const int total=m_zones.Count();
   for(int i=0;i<total;i++)
     {
      SPriceZone zone;
      if(!m_zones.At(i,zone))
         continue;
      if(zone.kind!=SRP_ZONE_LIQUIDITY_POOL || !zone.IsActionable())
         continue;
      if(drawn>=m_max_zones)
         break;
      m_painter.Box(m_painter.NameIndexed("liq","pool",drawn),
                    zone.formed_at,zone.upper,right,zone.lower,
                    m_theme.Liquidity(),false,1);
      m_painter.TextAt(m_painter.NameIndexed("liq","txt",drawn),
                       zone.formed_at,zone.upper,
                       "LIQ "+zone.note,
                       m_theme.Liquidity(),m_theme.BodySize()-1,m_theme.Font());
      drawn++;
     }
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawStructureEvents(void)
  {
   if(m_structure==NULL)
      return;

   SStructureState state;
   m_structure.GetState(state);

   //--- BOS and CHoCH are drawn on separate layers because they mean
   //--- opposite things: continuation versus reversal warning.
   const bool is_bos=(state.last_event==SRP_STRUCT_BOS_BULLISH ||
                      state.last_event==SRP_STRUCT_BOS_BEARISH);
   const bool is_choch=(state.last_event==SRP_STRUCT_CHOCH_BULLISH ||
                        state.last_event==SRP_STRUCT_CHOCH_BEARISH);
   if(!is_bos && !is_choch)
      return;
   if(is_bos && !IsLayerOn(SRP_DRAW_BOS))
      return;
   if(is_choch && !IsLayerOn(SRP_DRAW_CHOCH))
      return;

   //--- Anchor at the swing that was broken.
   const bool bullish=(state.last_event==SRP_STRUCT_BOS_BULLISH ||
                       state.last_event==SRP_STRUCT_CHOCH_BULLISH);
   const SSwingPoint anchor=(bullish ? state.last_high : state.last_low);
   if(!anchor.valid)
      return;

   const string group=(is_bos ? "bos" : "choch");
   const color line_color=(is_choch ? m_theme.ForTone(SRP_UI_TONE_WARNING)
                                    : m_theme.Structure());
   m_painter.TrendLine(m_painter.Name(group,"line"),
                       anchor.time,anchor.price,RightEdge(),anchor.price,
                       line_color,STYLE_DASH,2,false);
   m_painter.TextAt(m_painter.Name(group,"txt"),
                    anchor.time,anchor.price,
                    CMarketStructure::EventToString(state.last_event),
                    line_color,m_theme.BodySize(),m_theme.Font());
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawSupportResistance(void)
  {
   if(m_swings==NULL)
      return;

   const datetime right=RightEdge();

   //--- Swing highs are resistance, swing lows are support. Drawing them
   //--- from the confirmed swing set means they never repaint.
   if(IsLayerOn(SRP_DRAW_RESISTANCE))
     {
      const int highs=m_swings.HighCount();
      const int limit=(highs<m_max_swings ? highs : m_max_swings);
      for(int i=0;i<limit;i++)
        {
         SSwingPoint swing;
         if(!m_swings.GetHigh(i,swing) || !swing.valid)
            continue;
         //--- A swept level is no longer resistance, so it is dimmed
         //--- rather than removed - the history still informs context.
         const color line_color=(swing.swept ? m_theme.Muted()
                                             : m_theme.ForTone(SRP_UI_TONE_NEGATIVE));
         m_painter.TrendLine(m_painter.NameIndexed("res","line",i),
                             swing.time,swing.price,right,swing.price,
                             line_color,
                             (swing.swept ? STYLE_DOT : STYLE_SOLID),1,false);
        }
     }

   if(IsLayerOn(SRP_DRAW_SUPPORT))
     {
      const int lows=m_swings.LowCount();
      const int limit=(lows<m_max_swings ? lows : m_max_swings);
      for(int i=0;i<limit;i++)
        {
         SSwingPoint swing;
         if(!m_swings.GetLow(i,swing) || !swing.valid)
            continue;
         const color line_color=(swing.swept ? m_theme.Muted()
                                             : m_theme.ForTone(SRP_UI_TONE_POSITIVE));
         m_painter.TrendLine(m_painter.NameIndexed("sup","line",i),
                             swing.time,swing.price,right,swing.price,
                             line_color,
                             (swing.swept ? STYLE_DOT : STYLE_SOLID),1,false);
        }
     }
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawTrendLines(void)
  {
   if(!IsLayerOn(SRP_DRAW_TREND_LINES) || m_swings==NULL)
      return;

   //--- Connect the two most recent same-kind swings to form the current
   //--- trend channel. Two points is the minimum honest definition; more
   //--- would require a fitting decision this class should not make.
   SSwingPoint high0,high1,low0,low1;
   if(m_swings.GetHigh(0,high0) && m_swings.GetHigh(1,high1) &&
      high0.valid && high1.valid)
      m_painter.TrendLine(m_painter.Name("trend","upper"),
                          high1.time,high1.price,high0.time,high0.price,
                          m_theme.ForTone(SRP_UI_TONE_NEGATIVE),
                          STYLE_SOLID,1,true);
   if(m_swings.GetLow(0,low0) && m_swings.GetLow(1,low1) &&
      low0.valid && low1.valid)
      m_painter.TrendLine(m_painter.Name("trend","lower"),
                          low1.time,low1.price,low0.time,low0.price,
                          m_theme.ForTone(SRP_UI_TONE_POSITIVE),
                          STYLE_SOLID,1,true);
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawSessionBox(const SDashboardModel &model)
  {
   if(!IsLayerOn(SRP_DRAW_SESSION_BOXES))
      return;

   //--- Box the current day's range so session structure is visible at a
   //--- glance. Uses the day's own high/low rather than a fixed window,
   //--- which keeps it meaningful across instruments.
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   const int bars=(int)MathMin(1440,(double)Bars(m_symbol,m_timeframe));
   if(bars<10)
      return;
   if(CopyRates(m_symbol,m_timeframe,0,bars,rates)!=bars)
      return;

   //--- Walk back to the start of the current day.
   MqlDateTime today_parts;
   TimeToStruct(rates[0].time,today_parts);
   double high=rates[0].high;
   double low=rates[0].low;
   datetime start=rates[0].time;
   for(int i=1;i<bars;i++)
     {
      MqlDateTime parts;
      TimeToStruct(rates[i].time,parts);
      if(parts.day!=today_parts.day)
         break;
      if(rates[i].high>high) high=rates[i].high;
      if(rates[i].low<low)   low=rates[i].low;
      start=rates[i].time;
     }
   if(high<=low)
      return;

   m_painter.Box(m_painter.Name("sess","box"),
                 start,high,rates[0].time,low,
                 m_theme.SessionBox(),true,1);
   m_painter.TextAt(m_painter.Name("sess","txt"),
                    start,high,
                    (StringLen(model.session_text)>0 ? model.session_text
                                                     : "session"),
                    m_theme.Accent(),m_theme.BodySize()-1,m_theme.Font());
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawStatistics(const SDashboardModel &model)
  {
   if(!IsLayerOn(SRP_DRAW_STATISTICS))
      return;

   //--- A compact statistics strip anchored to the chart corner, distinct
   //--- from the main panel so it can be shown alone on a clean chart.
   const int x=m_theme.Padding();
   const int y=4;
   const string text=StringFormat("WR %.1f%% | PF %.2f | RR %.2f | %d trades",
                                  model.win_rate,model.profit_factor,
                                  model.average_rr,model.total_trades);
   m_painter.Label(m_painter.Name("stat","strip"),x,y,text,
                   m_theme.Label(),m_theme.BodySize(),m_theme.Font());
   //--- The decision must be visible on the chart itself, not hidden in
   //--- the Experts log. This is a status display only; it cannot place an
   //--- order and deliberately mirrors the dashboard's BUY/SELL/WAIT text.
   //--- Rendered at TITLE size, well above body text, because a signal a
   //--- trader has to squint for is a signal they will miss.
   const string tag=(model.signal_tone==SRP_UI_TONE_POSITIVE ? "BUY ^^  "
                     :model.signal_tone==SRP_UI_TONE_NEGATIVE ? "SELL vv  "
                     :"WAIT  ");
   m_painter.Label(m_painter.Name("stat","signal"),x,y+m_theme.RowHeight(),
                   tag+CStringUtils::Truncate(model.signal_text,64),
                   m_theme.ForTone(model.signal_tone),m_theme.TitleSize(),
                   m_theme.Font());
  }
//+------------------------------------------------------------------+
//| Draws a real chart arrow (not just a corner label) at the current   |
//| bar and current price the moment the pipeline reports an actionable  |
//| BUY or SELL opinion - independent of whether that opinion cleared    |
//| every downstream gate and actually traded. This is what lets a       |
//| trader see the bot's read on the market even while it is refusing to |
//| act on it, which the panel's text-only signal buries in a corner.    |
//|                                                                  |
//| ONE object, reused every call: an unbounded arrow-per-bar history     |
//| would clutter the chart exactly like the entries layer would if it    |
//| were not per-ticket. WAIT removes it rather than leaving a stale      |
//| arrow pointing at a decision that is no longer current.              |
//+------------------------------------------------------------------+
void CChartOverlay::DrawLiveSignalMarker(const SDashboardModel &model)
  {
   if(!IsLayerOn(SRP_DRAW_STATISTICS) || m_painter==NULL)
      return;
   const string name=m_painter.Name("stat","livearrow");
   if(model.signal_tone!=SRP_UI_TONE_POSITIVE &&
      model.signal_tone!=SRP_UI_TONE_NEGATIVE)
     {
      m_painter.Remove(name);
      return;
     }
   const bool is_buy=(model.signal_tone==SRP_UI_TONE_POSITIVE);
   const double price=SymbolInfoDouble(m_symbol,is_buy ? SYMBOL_BID : SYMBOL_ASK);
   if(price<=0.0)
      return;
   const datetime bar=iTime(m_symbol,m_timeframe,0);
   //--- Wingdings 233/234: the same up/down arrows DrawEntry uses for a
   //--- real fill, so a live opinion and an executed trade read the same
   //--- way on the chart.
   m_painter.Arrow(name,bar,price,(uchar)(is_buy ? 233 : 234),
                   m_theme.ForTone(is_buy ? SRP_UI_TONE_POSITIVE
                                          : SRP_UI_TONE_NEGATIVE),2);
  }
//+------------------------------------------------------------------+
bool CChartOverlay::DrawAnalysis(const datetime current_bar,
                                 const SDashboardModel &model,
                                 const bool force)
  {
   if(!m_enabled || m_painter==NULL || m_theme==NULL)
      return(false);

   //--- BAR GATE. Zones and swings do not move intrabar, so redrawing
   //--- them per tick would be pure waste - and it is the most expensive
   //--- thing a chart UI can do.
   if(!force && m_last_draw_bar==current_bar)
      return(false);
   m_last_draw_bar=current_bar;

   DrawZones();
   DrawLiquidity();
   DrawStructureEvents();
   DrawSupportResistance();
   DrawTrendLines();
   DrawSessionBox(model);
   DrawStatistics(model);
   DrawLiveSignalMarker(model);

   m_draws++;
   ChartRedraw(0);
   return(true);
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawEntry(const SManagedPosition &position)
  {
   if(!IsLayerOn(SRP_DRAW_ENTRIES) || m_painter==NULL)
      return;
   const string suffix=IntegerToString((long)position.ticket);
   //--- Arrow at the fill, plus a horizontal line so the entry level
   //--- remains visible as price travels away from it.
   m_painter.Arrow(m_painter.Name("entry","a"+suffix),
                   position.open_time,position.open_price,
                   //--- Wingdings 233/234 are the up/down arrows. The cast
                   //--- is explicit because the painter takes a uchar code.
                   (uchar)(position.is_buy ? 233 : 234),
                   m_theme.ForTone(position.is_buy ? SRP_UI_TONE_POSITIVE
                                                   : SRP_UI_TONE_NEGATIVE),1);
   m_painter.PriceLine(m_painter.Name("entry","l"+suffix),
                       position.open_price,m_theme.Accent(),STYLE_DOT,1,
                       "entry "+suffix);
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawStops(const SManagedPosition &position)
  {
   if(m_painter==NULL)
      return;
   const string suffix=IntegerToString((long)position.ticket);

   if(IsLayerOn(SRP_DRAW_STOP_LOSS) && position.stop_loss>0.0)
      m_painter.PriceLine(m_painter.Name("sl","l"+suffix),
                          position.stop_loss,
                          m_theme.ForTone(SRP_UI_TONE_NEGATIVE),
                          STYLE_DASH,1,"SL "+suffix);
   //--- A removed stop must clear its line, otherwise the chart shows
   //--- protection that no longer exists - actively misleading.
   else
      m_painter.Remove(m_painter.Name("sl","l"+suffix));

   if(IsLayerOn(SRP_DRAW_TAKE_PROFIT) && position.take_profit>0.0)
      m_painter.PriceLine(m_painter.Name("tp","l"+suffix),
                          position.take_profit,
                          m_theme.ForTone(SRP_UI_TONE_POSITIVE),
                          STYLE_DASH,1,"TP "+suffix);
   else
      m_painter.Remove(m_painter.Name("tp","l"+suffix));
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawTrailing(const SManagedPosition &position,
                                 const double trail_price)
  {
   if(!IsLayerOn(SRP_DRAW_TRAILING_STOP) || m_painter==NULL)
      return;
   const string suffix=IntegerToString((long)position.ticket);
   if(trail_price<=0.0 || !position.trailing_active)
     {
      m_painter.Remove(m_painter.Name("trail","l"+suffix));
      return;
     }
   //--- Drawn distinctly from the hard stop so a trader can see that the
   //--- stop is now dynamic.
   m_painter.PriceLine(m_painter.Name("trail","l"+suffix),
                       trail_price,m_theme.ForTone(SRP_UI_TONE_WARNING),
                       STYLE_DOT,2,"trail "+suffix);
  }
//+------------------------------------------------------------------+
void CChartOverlay::DrawTradeLabel(const SManagedPosition &position)
  {
   if(!IsLayerOn(SRP_DRAW_TRADE_LABELS) || m_painter==NULL)
      return;
   const string suffix=IntegerToString((long)position.ticket);
   const string text=StringFormat("%s %.2f  %s%.1f pts",
                                  (position.is_buy ? "BUY" : "SELL"),
                                  position.volume,
                                  (position.profit_points>0.0 ? "+" : ""),
                                  position.profit_points);
   m_painter.TextAt(m_painter.Name("lbl","t"+suffix),
                    position.open_time,position.open_price,text,
                    m_theme.ForValue(position.profit_money),
                    m_theme.BodySize(),m_theme.Font());
  }
//+------------------------------------------------------------------+
void CChartOverlay::ClearTrade(const ulong ticket)
  {
   if(m_painter==NULL)
      return;
   //--- Remove every object belonging to this ticket. Leaving markup for
   //--- a closed trade is worse than drawing nothing.
   const string suffix=IntegerToString((long)ticket);
   m_painter.Remove(m_painter.Name("entry","a"+suffix));
   m_painter.Remove(m_painter.Name("entry","l"+suffix));
   m_painter.Remove(m_painter.Name("sl","l"+suffix));
   m_painter.Remove(m_painter.Name("tp","l"+suffix));
   m_painter.Remove(m_painter.Name("trail","l"+suffix));
   m_painter.Remove(m_painter.Name("lbl","t"+suffix));
  }
//+------------------------------------------------------------------+
void CChartOverlay::ClearLayer(const ENUM_SRP_DRAW_LAYER layer)
  {
   if(m_painter==NULL)
      return;
   //--- Group prefixes mirror the naming used when drawing, so a layer
   //--- can be cleared without disturbing any other.
   switch(layer)
     {
      case SRP_DRAW_ENTRIES:          m_painter.RemoveGroup("entry"); break;
      case SRP_DRAW_STOP_LOSS:        m_painter.RemoveGroup("sl");    break;
      case SRP_DRAW_TAKE_PROFIT:      m_painter.RemoveGroup("tp");    break;
      case SRP_DRAW_TRAILING_STOP:    m_painter.RemoveGroup("trail"); break;
      case SRP_DRAW_ORDER_BLOCKS:     m_painter.RemoveGroup("ob");    break;
      case SRP_DRAW_FAIR_VALUE_GAPS:  m_painter.RemoveGroup("fvg");   break;
      case SRP_DRAW_LIQUIDITY:        m_painter.RemoveGroup("liq");   break;
      case SRP_DRAW_BOS:              m_painter.RemoveGroup("bos");   break;
      case SRP_DRAW_CHOCH:            m_painter.RemoveGroup("choch"); break;
      case SRP_DRAW_SUPPORT:          m_painter.RemoveGroup("sup");   break;
      case SRP_DRAW_RESISTANCE:       m_painter.RemoveGroup("res");   break;
      case SRP_DRAW_TREND_LINES:      m_painter.RemoveGroup("trend"); break;
      case SRP_DRAW_SESSION_BOXES:    m_painter.RemoveGroup("sess");  break;
      case SRP_DRAW_TRADE_LABELS:     m_painter.RemoveGroup("lbl");   break;
      case SRP_DRAW_STATISTICS:       m_painter.RemoveGroup("stat");  break;
     }
  }
//+------------------------------------------------------------------+
void CChartOverlay::ClearAll(void)
  {
   for(int i=0;i<SRP_DRAW_LAYER_COUNT;i++)
      ClearLayer((ENUM_SRP_DRAW_LAYER)i);
   m_last_draw_bar=0;
  }
//+------------------------------------------------------------------+
string CChartOverlay::LayerToString(const ENUM_SRP_DRAW_LAYER layer)
  {
   switch(layer)
     {
      case SRP_DRAW_ENTRIES:         return("Entries");
      case SRP_DRAW_STOP_LOSS:       return("StopLoss");
      case SRP_DRAW_TAKE_PROFIT:     return("TakeProfit");
      case SRP_DRAW_TRAILING_STOP:   return("TrailingStop");
      case SRP_DRAW_ORDER_BLOCKS:    return("OrderBlocks");
      case SRP_DRAW_FAIR_VALUE_GAPS: return("FairValueGaps");
      case SRP_DRAW_LIQUIDITY:       return("Liquidity");
      case SRP_DRAW_BOS:             return("BOS");
      case SRP_DRAW_CHOCH:           return("CHoCH");
      case SRP_DRAW_SUPPORT:         return("Support");
      case SRP_DRAW_RESISTANCE:      return("Resistance");
      case SRP_DRAW_TREND_LINES:     return("TrendLines");
      case SRP_DRAW_SESSION_BOXES:   return("SessionBoxes");
      case SRP_DRAW_TRADE_LABELS:    return("TradeLabels");
      case SRP_DRAW_STATISTICS:      return("Statistics");
     }
   return("Unknown");
  }
//+------------------------------------------------------------------+
string CChartOverlay::Describe(void) const
  {
   int on=0;
   for(int i=0;i<SRP_DRAW_LAYER_COUNT;i++)
      if(m_layer_enabled[i])
         on++;
   return(StringFormat("overlay: %s, %d/%d layers on, %I64d draws",
                       (m_enabled ? "enabled" : "disabled"),
                       on,SRP_DRAW_LAYER_COUNT,m_draws));
  }

#endif // SRP_INTERFACE_CHART_CCHARTOVERLAY_MQH
//+------------------------------------------------------------------+
