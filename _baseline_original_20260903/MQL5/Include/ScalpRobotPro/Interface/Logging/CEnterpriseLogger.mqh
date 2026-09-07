//+------------------------------------------------------------------+
//|                                        CEnterpriseLogger.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   RESPONSIBILITY (one only): route a structured record to the correct  |
//|   channel. It owns six CLogChannelWriter instances and does no         |
//|   formatting and no file I/O of its own.                              |
//|                                                                  |
//|   SIX CHANNELS, SEPARATE FILES: Errors, Trades, Indicators, Risk       |
//|   Events, Performance, Execution Time. Separation is the entire point. |
//|   A risk audit buried under a million indicator lines is not an audit, |
//|   and indicator tracing must be switchable off without losing the      |
//|   error log.                                                         |
//|                                                                  |
//|   THREE EXPORT FORMATS: CSV, TXT, JOURNAL - selectable per channel.    |
//|   Sensible defaults: numeric channels go to CSV because they are read  |
//|   in a spreadsheet, narrative channels go to TXT, and errors are       |
//|   mirrored to the Journal so a live operator sees them immediately.    |
//|                                                                  |
//|   TYPED FRONT DOOR. Callers use LogTrade / LogRiskEvent /              |
//|   LogExecutionTime rather than assembling records, so the numeric       |
//|   columns always mean the same thing in every row. A CSV where         |
//|   value_a is sometimes a price and sometimes a lot size is useless.    |
//|                                                                  |
//|   IT ALSO IMPLEMENTS ILogger. That lets the whole existing codebase    |
//|   - every Phase 1-3 module already holds an ILogger* - be pointed at   |
//|   this without one line of those modules changing. Severity is mapped  |
//|   to a channel, so legacy Warn/Error calls land in the error log       |
//|   automatically.                                                     |
//|                                                                  |
//|   NEVER THROWS, NEVER BLOCKS TRADING. Every failure is counted and     |
//|   swallowed. A full disk must not stop the EA from managing an open    |
//|   position.                                                          |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_LOGGING_CENTERPRISELOGGER_MQH
#define SRP_INTERFACE_LOGGING_CENTERPRISELOGGER_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Core/Types/Constants.mqh"
#include "../Types/InterfaceStructs.mqh"
#include "CLogChannelWriter.mqh"

#define SRP_LOG4_CHANNEL_COUNT 6
//--- Ring buffer of recent records. Held so the dashboard and the
//--- exporter can show history without re-reading a file that may be
//--- open for writing.
#define SRP_LOG4_HISTORY 256

class CEnterpriseLogger : public ILogger
  {
private:
   CLogChannelWriter *m_channels[SRP_LOG4_CHANNEL_COUNT];   // OWNED
   bool               m_channel_enabled[SRP_LOG4_CHANNEL_COUNT];
   long               m_channel_counts[SRP_LOG4_CHANNEL_COUNT];

   string             m_folder;
   string             m_symbol;
   ENUM_SRP_LOG_LEVEL m_minimum_level;
   bool               m_is_open;
   bool               m_mirror_errors_to_journal;
   bool               m_reentrancy_guard;

   //--- History ring.
   SLogRecord         m_history[SRP_LOG4_HISTORY];
   int                m_history_head;
   int                m_history_size;

   long               m_total_records;
   long               m_dropped_records;
   long               m_failed_writes;

   //--- Rolling execution-time statistics. Kept here because the
   //--- dashboard needs the average latency and re-reading the CSV per
   //--- repaint would be absurd.
   double             m_exec_total_ms;
   double             m_exec_worst_ms;
   long               m_exec_samples;

   int                Index(const ENUM_SRP_LOG4_CHANNEL channel) const
     { return((int)channel); }
   void               BuildChannels(void);
   void               Remember(const SLogRecord &record);
   bool               Emit(SLogRecord &record);
   static ENUM_SRP_LOG4_CHANNEL ChannelForLevel(const ENUM_SRP_LOG_LEVEL level);

public:
                     CEnterpriseLogger(const string symbol,
                                       const string folder="",
                                       const ENUM_SRP_LOG_LEVEL minimum=SRP_LOG_INFO);
                    ~CEnterpriseLogger(void);

   //=== CONFIGURATION ================================================
   void              SetChannelEnabled(const ENUM_SRP_LOG4_CHANNEL channel,
                                       const bool enabled);
   bool              IsChannelEnabled(const ENUM_SRP_LOG4_CHANNEL channel) const;
   void              SetChannelFormat(const ENUM_SRP_LOG4_CHANNEL channel,
                                      const ENUM_SRP_LOG4_FORMAT format);
   void              SetAllFormats(const ENUM_SRP_LOG4_FORMAT format);
   void              SetFolder(const string folder);
   void              SetDailyRotation(const bool enabled);
   void              SetCommonFolder(const bool common);
   void              SetFlushEvery(const int records);
   void              SetMirrorErrorsToJournal(const bool enabled)
     { m_mirror_errors_to_journal=enabled; }

   bool              Open(void);
   void              Close(void);

   bool              Validate(SValidationResult &result) const;

   //=== TYPED CHANNEL API ============================================
   //--- Errors.
   void              LogError(const string context,const string message,
                              const int error_code=0);
   //--- Trades. The three numbers are always price, volume, profit.
   void              LogTrade(const string context,const string message,
                              const ulong ticket,const double price,
                              const double volume,const double profit);
   void              LogTradeOpened(const SManagedPosition &position,
                                    const string strategy);
   void              LogTradeClosed(const SClosedTrade &trade);
   void              LogTradeIntent(const STradeIntent &intent);
   //--- Indicators. Always value, previous, threshold.
   void              LogIndicator(const string indicator_name,
                                  const double value,const double previous,
                                  const double threshold=0.0,
                                  const string note="");
   //--- Risk events. Always used, limit, remaining.
   void              LogRiskEvent(const string context,const string message,
                                 const double used,const double limit,
                                 const double remaining);
   //--- Performance. Always equity, profit factor, drawdown.
   void              LogPerformance(const string context,
                                    const double equity,
                                    const double profit_factor,
                                    const double drawdown_percent,
                                    const string note="");
   void              LogAnalyticsReport(const SAnalyticsReport &report);
   //--- Execution time. Always elapsed ms, retries, slippage points.
   void              LogExecutionTime(const string operation,
                                      const double elapsed_ms,
                                      const int retries=0,
                                      const double slippage_points=0.0,
                                      const ulong ticket=SRP_INVALID_TICKET);

   //=== ILogger ======================================================
   //--- Severity is mapped to a channel, so all Phase 1-3 modules can
   //--- log through this object unchanged.
   virtual void      Log(const ENUM_SRP_LOG_LEVEL level,
                         const string context,
                         const string message) override;
   virtual void      Trace(const string context,const string message) override
     { Log(SRP_LOG_TRACE,context,message); }
   virtual void      Debug(const string context,const string message) override
     { Log(SRP_LOG_DEBUG,context,message); }
   virtual void      Info(const string context,const string message) override
     { Log(SRP_LOG_INFO,context,message); }
   virtual void      Warn(const string context,const string message) override
     { Log(SRP_LOG_WARN,context,message); }
   virtual void      Error(const string context,const string message) override
     { Log(SRP_LOG_ERROR,context,message); }
   virtual void      Fatal(const string context,const string message) override
     { Log(SRP_LOG_FATAL,context,message); }
   virtual void      LogRetcode(const string context,const string operation,
                                const uint retcode) override;
   virtual bool      IsEnabled(const ENUM_SRP_LOG_LEVEL level) override
     { return(m_minimum_level!=SRP_LOG_OFF && level>=m_minimum_level); }
   virtual void      SetMinimumLevel(const ENUM_SRP_LOG_LEVEL level) override
     { m_minimum_level=level; }
   virtual ENUM_SRP_LOG_LEVEL MinimumLevel(void) override
     { return(m_minimum_level); }
   virtual void      Flush(void) override;

   //=== HISTORY AND EXPORT ===========================================
   int               HistoryCount(void) const { return(m_history_size); }
   //--- index 0 is the most recent.
   bool              HistoryAt(const int index,SLogRecord &out) const;
   //--- Writes the whole retained history to one file in one format.
   bool              ExportHistory(const string relative_path,
                                   const ENUM_SRP_LOG4_FORMAT format,
                                   const bool common_folder=false);
   //--- Same, filtered to one channel.
   bool              ExportChannel(const ENUM_SRP_LOG4_CHANNEL channel,
                                   const string relative_path,
                                   const ENUM_SRP_LOG4_FORMAT format,
                                   const bool common_folder=false);
   void              ClearHistory(void);

   //=== DIAGNOSTICS ==================================================
   long              TotalRecords(void)  const { return(m_total_records); }
   long              DroppedRecords(void) const { return(m_dropped_records); }
   long              FailedWrites(void)  const { return(m_failed_writes); }
   long              ChannelCount(const ENUM_SRP_LOG4_CHANNEL channel) const;
   double            AverageExecutionMs(void) const;
   double            WorstExecutionMs(void) const { return(m_exec_worst_ms); }
   long              ExecutionSamples(void) const { return(m_exec_samples); }
   string            ChannelPath(const ENUM_SRP_LOG4_CHANNEL channel) const;
   string            Describe(void) const;

   static string     ChannelToString(const ENUM_SRP_LOG4_CHANNEL channel);
   static string     FormatToString(const ENUM_SRP_LOG4_FORMAT format);
   static string     LevelToString(const ENUM_SRP_LOG_LEVEL level);
  };

//+------------------------------------------------------------------+
CEnterpriseLogger::CEnterpriseLogger(const string symbol,
                                     const string folder,
                                     const ENUM_SRP_LOG_LEVEL minimum)
  : m_folder(folder=="" ? SRP_DATA_FOLDER+"\\Logs" : folder),
    m_symbol(symbol),
    m_minimum_level(minimum),
    m_is_open(false),
    m_mirror_errors_to_journal(true),
    m_reentrancy_guard(false),
    m_history_head(0),
    m_history_size(0),
    m_total_records(0),
    m_dropped_records(0),
    m_failed_writes(0),
    m_exec_total_ms(0.0),
    m_exec_worst_ms(0.0),
    m_exec_samples(0)
  {
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
     {
      m_channels[i]=NULL;
      m_channel_enabled[i]=true;
      m_channel_counts[i]=0;
     }
   BuildChannels();
  }
//+------------------------------------------------------------------+
CEnterpriseLogger::~CEnterpriseLogger(void)
  {
   Close();
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
      if(m_channels[i]!=NULL)
        {
         delete m_channels[i];
         m_channels[i]=NULL;
        }
  }
//+------------------------------------------------------------------+
//| Channel table. Everything channel-specific lives here and nowhere  |
//| else: base file name, display tag, CSV header and default format.   |
//| The per-channel header is what makes the CSVs self-documenting -    |
//| "value_a" tells a support engineer nothing, "price" tells them      |
//| everything.                                                        |
//+------------------------------------------------------------------+
void CEnterpriseLogger::BuildChannels(void)
  {
   m_channels[(int)SRP_LOG4_ERRORS]=new CLogChannelWriter(
      m_folder,"errors","ERRORS",
      "timestamp,channel,context,message,ticket,error_code,reserved,reserved",
      SRP_LOG4_FORMAT_TXT);

   m_channels[(int)SRP_LOG4_TRADES]=new CLogChannelWriter(
      m_folder,"trades","TRADES",
      "timestamp,channel,context,message,ticket,price,volume,profit",
      SRP_LOG4_FORMAT_CSV);

   m_channels[(int)SRP_LOG4_INDICATORS]=new CLogChannelWriter(
      m_folder,"indicators","INDICATORS",
      "timestamp,channel,indicator,note,ticket,value,previous,threshold",
      SRP_LOG4_FORMAT_CSV);

   m_channels[(int)SRP_LOG4_RISK_EVENTS]=new CLogChannelWriter(
      m_folder,"risk_events","RISK",
      "timestamp,channel,context,message,ticket,used,limit,remaining",
      SRP_LOG4_FORMAT_CSV);

   m_channels[(int)SRP_LOG4_PERFORMANCE]=new CLogChannelWriter(
      m_folder,"performance","PERFORMANCE",
      "timestamp,channel,context,note,ticket,equity,profit_factor,drawdown_pct",
      SRP_LOG4_FORMAT_CSV);

   m_channels[(int)SRP_LOG4_EXECUTION_TIME]=new CLogChannelWriter(
      m_folder,"execution_time","EXECUTION",
      "timestamp,channel,operation,note,ticket,elapsed_ms,retries,slippage_pts",
      SRP_LOG4_FORMAT_CSV);
  }
//+------------------------------------------------------------------+
bool CEnterpriseLogger::Open(void)
  {
   bool any=false;
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
     {
      if(m_channels[i]==NULL || !m_channel_enabled[i])
         continue;
      if(m_channels[i].Open())
         any=true;
      else
         m_failed_writes++;
     }
   m_is_open=any;
   //--- Opening is best-effort by design. If the sandbox forbids file
   //--- writes the EA must still trade, with the Journal as fallback.
   if(!any)
      m_mirror_errors_to_journal=true;
   return(any);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::Close(void)
  {
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
      if(m_channels[i]!=NULL)
        {
         m_channels[i].Flush();
         m_channels[i].Close();
        }
   m_is_open=false;
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::Flush(void)
  {
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
      if(m_channels[i]!=NULL)
         m_channels[i].Flush();
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::SetChannelEnabled(const ENUM_SRP_LOG4_CHANNEL channel,
                                          const bool enabled)
  {
   const int i=Index(channel);
   if(i<0 || i>=SRP_LOG4_CHANNEL_COUNT)
      return;
   m_channel_enabled[i]=enabled;
   if(m_channels[i]!=NULL)
      m_channels[i].SetEnabled(enabled);
  }
//+------------------------------------------------------------------+
bool CEnterpriseLogger::IsChannelEnabled(const ENUM_SRP_LOG4_CHANNEL channel) const
  {
   const int i=Index(channel);
   if(i<0 || i>=SRP_LOG4_CHANNEL_COUNT)
      return(false);
   return(m_channel_enabled[i]);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::SetChannelFormat(const ENUM_SRP_LOG4_CHANNEL channel,
                                         const ENUM_SRP_LOG4_FORMAT format)
  {
   const int i=Index(channel);
   if(i<0 || i>=SRP_LOG4_CHANNEL_COUNT || m_channels[i]==NULL)
      return;
   m_channels[i].SetFormat(format);
   if(m_is_open)
      m_channels[i].Open();
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::SetAllFormats(const ENUM_SRP_LOG4_FORMAT format)
  {
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
      if(m_channels[i]!=NULL)
        {
         m_channels[i].SetFormat(format);
         if(m_is_open)
            m_channels[i].Open();
        }
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::SetFolder(const string folder)
  {
   m_folder=folder;
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
      if(m_channels[i]!=NULL)
        {
         m_channels[i].SetFolder(folder);
         if(m_is_open)
            m_channels[i].Open();
        }
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::SetDailyRotation(const bool enabled)
  {
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
      if(m_channels[i]!=NULL)
         m_channels[i].SetDailyRotation(enabled);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::SetCommonFolder(const bool common)
  {
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
      if(m_channels[i]!=NULL)
         m_channels[i].SetCommonFolder(common);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::SetFlushEvery(const int records)
  {
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
      if(m_channels[i]!=NULL)
         m_channels[i].SetFlushEvery(records);
  }
//+------------------------------------------------------------------+
bool CEnterpriseLogger::Validate(SValidationResult &result) const
  {
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
      if(m_channels[i]==NULL)
         result.AddError("log channel not constructed: "+
                         ChannelToString((ENUM_SRP_LOG4_CHANNEL)i));
   if(m_folder=="")
      result.AddWarning("log folder is empty, files land in MQL5\\Files root");
   if(m_minimum_level==SRP_LOG_OFF)
      result.AddWarning("minimum level is OFF, severity-routed logging is muted");
   //--- A configuration with every channel muted is legal but almost
   //--- certainly a mistake, so it is called out.
   bool any=false;
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
      if(m_channel_enabled[i])
         any=true;
   if(!any)
      result.AddWarning("every log channel is disabled");
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
//| The single choke point. Every typed method and the ILogger surface  |
//| funnel through here, so timestamping, history and counting exist    |
//| once.                                                              |
//+------------------------------------------------------------------+
bool CEnterpriseLogger::Emit(SLogRecord &record)
  {
   const int i=Index(record.channel);
   if(i<0 || i>=SRP_LOG4_CHANNEL_COUNT)
     {
      m_dropped_records++;
      return(false);
     }
   if(!m_channel_enabled[i])
     {
      m_dropped_records++;
      return(false);
     }
   //--- A sink failure must never re-enter and recurse.
   if(m_reentrancy_guard)
      return(false);
   m_reentrancy_guard=true;

   if(record.timestamp==0)
      record.timestamp=TimeCurrent();
   if(record.timestamp_ms==0)
      record.timestamp_ms=GetTickCount64();

   bool ok=true;
   if(m_channels[i]!=NULL)
      ok=m_channels[i].Write(record);
   if(!ok)
      m_failed_writes++;

   //--- Errors are mirrored to the Journal unless that channel already
   //--- IS the journal, which would double every line.
   if(m_mirror_errors_to_journal && record.channel==SRP_LOG4_ERRORS &&
      m_channels[i]!=NULL && m_channels[i].Format()!=SRP_LOG4_FORMAT_JOURNAL)
      Print(m_channels[i].Render(record,SRP_LOG4_FORMAT_JOURNAL));

   Remember(record);
   m_channel_counts[i]++;
   m_total_records++;
   m_reentrancy_guard=false;
   return(ok);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::Remember(const SLogRecord &record)
  {
   m_history[m_history_head]=record;
   m_history_head=(m_history_head+1)%SRP_LOG4_HISTORY;
   if(m_history_size<SRP_LOG4_HISTORY)
      m_history_size++;
  }
//+------------------------------------------------------------------+
bool CEnterpriseLogger::HistoryAt(const int index,SLogRecord &out) const
  {
   if(index<0 || index>=m_history_size)
      return(false);
   //--- Walk backwards from the head: index 0 is the newest record.
   int slot=m_history_head-1-index;
   while(slot<0)
      slot+=SRP_LOG4_HISTORY;
   out=m_history[slot];
   return(true);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::ClearHistory(void)
  {
   m_history_head=0;
   m_history_size=0;
  }
//+------------------------------------------------------------------+
//| Severity to channel. Warnings and worse are errors; everything else |
//| is performance-grade information. This is what lets three phases of |
//| existing ILogger calls land somewhere sensible with zero edits.     |
//+------------------------------------------------------------------+
ENUM_SRP_LOG4_CHANNEL CEnterpriseLogger::ChannelForLevel(const ENUM_SRP_LOG_LEVEL level)
  {
   if(level>=SRP_LOG_WARN)
      return(SRP_LOG4_ERRORS);
   return(SRP_LOG4_PERFORMANCE);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::Log(const ENUM_SRP_LOG_LEVEL level,
                            const string context,
                            const string message)
  {
   if(!IsEnabled(level))
     {
      m_dropped_records++;
      return;
     }
   SLogRecord record;
   record.channel=ChannelForLevel(level);
   record.context=context;
   //--- The level is preserved in the text because the channel alone
   //--- cannot distinguish WARN from FATAL.
   record.message="["+LevelToString(level)+"] "+message;
   Emit(record);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogRetcode(const string context,
                                   const string operation,
                                   const uint retcode)
  {
   SLogRecord record;
   record.channel=SRP_LOG4_ERRORS;
   record.context=context;
   record.message=operation+" failed, retcode="+IntegerToString(retcode);
   record.value_a=(double)retcode;
   Emit(record);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogError(const string context,const string message,
                                 const int error_code)
  {
   SLogRecord record;
   record.channel=SRP_LOG4_ERRORS;
   record.context=context;
   record.message=message;
   record.value_a=(double)error_code;
   Emit(record);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogTrade(const string context,const string message,
                                 const ulong ticket,const double price,
                                 const double volume,const double profit)
  {
   SLogRecord record;
   record.channel=SRP_LOG4_TRADES;
   record.context=context;
   record.message=message;
   record.ticket=ticket;
   record.value_a=price;
   record.value_b=volume;
   record.value_c=profit;
   Emit(record);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogTradeOpened(const SManagedPosition &position,
                                       const string strategy)
  {
   string text="OPEN ";
   text+=(position.is_buy ? "BUY " : "SELL ");
   text+=DoubleToString(position.volume,2)+" "+position.symbol;
   text+=" @ "+DoubleToString(position.open_price,_Digits);
   text+=" sl="+DoubleToString(position.stop_loss,_Digits);
   text+=" tp="+DoubleToString(position.take_profit,_Digits);
   if(strategy!="")
      text+=" via "+strategy;
   LogTrade("TradeOpened",text,position.ticket,
            position.open_price,position.volume,0.0);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogTradeClosed(const SClosedTrade &trade)
  {
   string text="CLOSE ";
   text+=(trade.is_buy ? "BUY " : "SELL ");
   text+=DoubleToString(trade.volume,2)+" "+trade.symbol;
   text+=" @ "+DoubleToString(trade.close_price,_Digits);
   text+=" net="+DoubleToString(trade.net_profit,2);
   text+=" R="+DoubleToString(trade.r_multiple,2);
   text+=" held="+IntegerToString(trade.duration_seconds)+"s";
   if(trade.exit_reason!="")
      text+=" reason="+trade.exit_reason;
   if(trade.strategy_name!="")
      text+=" strat="+trade.strategy_name;
   LogTrade("TradeClosed",text,trade.ticket,
            trade.close_price,trade.volume,trade.net_profit);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogTradeIntent(const STradeIntent &intent)
  {
   //--- Logging the intent, not the fill, is what makes a "why did it
   //--- move my stop" question answerable from the log alone.
   string text="INTENT ";
   text+=intent.reason;
   SLogRecord record;
   record.channel=SRP_LOG4_TRADES;
   record.context="TradeManager";
   record.message=text;
   record.ticket=intent.ticket;
   record.value_a=intent.new_stop;
   record.value_b=intent.volume;
   record.value_c=intent.urgency;
   Emit(record);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogIndicator(const string indicator_name,
                                     const double value,const double previous,
                                     const double threshold,
                                     const string note)
  {
   SLogRecord record;
   record.channel=SRP_LOG4_INDICATORS;
   record.context=indicator_name;
   record.message=note;
   record.value_a=value;
   record.value_b=previous;
   record.value_c=threshold;
   Emit(record);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogRiskEvent(const string context,const string message,
                                     const double used,const double limit,
                                     const double remaining)
  {
   SLogRecord record;
   record.channel=SRP_LOG4_RISK_EVENTS;
   record.context=context;
   record.message=message;
   record.value_a=used;
   record.value_b=limit;
   record.value_c=remaining;
   Emit(record);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogPerformance(const string context,
                                       const double equity,
                                       const double profit_factor,
                                       const double drawdown_percent,
                                       const string note)
  {
   SLogRecord record;
   record.channel=SRP_LOG4_PERFORMANCE;
   record.context=context;
   record.message=note;
   record.value_a=equity;
   record.value_b=profit_factor;
   record.value_c=drawdown_percent;
   Emit(record);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogAnalyticsReport(const SAnalyticsReport &report)
  {
   string text="trades="+IntegerToString(report.total_trades);
   text+=" win%="+DoubleToString(report.win_rate,1);
   text+=" net="+DoubleToString(report.net_profit,2);
   text+=" pf="+DoubleToString(report.profit_factor,2);
   text+=" sharpe="+DoubleToString(report.sharpe_ratio,2);
   text+=" sortino="+DoubleToString(report.sortino_ratio,2);
   text+=" recovery="+DoubleToString(report.recovery_factor,2);
   text+=" maxDD%="+DoubleToString(report.max_drawdown_percent,2);
   LogPerformance("Analytics",report.net_profit,report.profit_factor,
                  report.max_drawdown_percent,text);
  }
//+------------------------------------------------------------------+
void CEnterpriseLogger::LogExecutionTime(const string operation,
                                         const double elapsed_ms,
                                         const int retries,
                                         const double slippage_points,
                                         const ulong ticket)
  {
   //--- Rolling stats are updated even when the channel is muted: the
   //--- dashboard latency reading must not depend on logging settings.
   m_exec_total_ms+=elapsed_ms;
   m_exec_samples++;
   if(elapsed_ms>m_exec_worst_ms)
      m_exec_worst_ms=elapsed_ms;

   SLogRecord record;
   record.channel=SRP_LOG4_EXECUTION_TIME;
   record.context=operation;
   record.message=(retries>0
                   ? "completed after "+IntegerToString(retries)+" retr"+
                     (retries==1 ? "y" : "ies")
                   : "completed");
   record.ticket=ticket;
   record.value_a=elapsed_ms;
   record.value_b=(double)retries;
   record.value_c=slippage_points;
   Emit(record);
  }
//+------------------------------------------------------------------+
double CEnterpriseLogger::AverageExecutionMs(void) const
  {
   if(m_exec_samples<=0)
      return(0.0);
   return(m_exec_total_ms/(double)m_exec_samples);
  }
//+------------------------------------------------------------------+
long CEnterpriseLogger::ChannelCount(const ENUM_SRP_LOG4_CHANNEL channel) const
  {
   const int i=Index(channel);
   if(i<0 || i>=SRP_LOG4_CHANNEL_COUNT)
      return(0);
   return(m_channel_counts[i]);
  }
//+------------------------------------------------------------------+
string CEnterpriseLogger::ChannelPath(const ENUM_SRP_LOG4_CHANNEL channel) const
  {
   const int i=Index(channel);
   if(i<0 || i>=SRP_LOG4_CHANNEL_COUNT || m_channels[i]==NULL)
      return("");
   return(m_channels[i].Path());
  }
//+------------------------------------------------------------------+
//| Export is deliberately independent of the live writers: it opens its |
//| own handle, writes, and closes. That way an operator can dump the    |
//| session to CSV without disturbing a single open log file.            |
//+------------------------------------------------------------------+
bool CEnterpriseLogger::ExportHistory(const string relative_path,
                                      const ENUM_SRP_LOG4_FORMAT format,
                                      const bool common_folder)
  {
   if(m_history_size<=0)
      return(false);

   if(format==SRP_LOG4_FORMAT_JOURNAL)
     {
      //--- "Export to Journal" means narrate it to the Experts tab.
      Print(SRP_PRODUCT_SHORT+" === log export begin, ",
            m_history_size," record(s) ===");
      for(int i=m_history_size-1;i>=0;i--)
        {
         SLogRecord record;
         if(!HistoryAt(i,record))
            continue;
         const int c=Index(record.channel);
         if(c>=0 && c<SRP_LOG4_CHANNEL_COUNT && m_channels[c]!=NULL)
            Print(m_channels[c].Render(record,SRP_LOG4_FORMAT_JOURNAL));
        }
      Print(SRP_PRODUCT_SHORT+" === log export end ===");
      return(true);
     }

   int flags=FILE_WRITE|FILE_TXT|FILE_ANSI;
   if(common_folder)
      flags|=FILE_COMMON;
   const int handle=FileOpen(relative_path,flags);
   if(handle==INVALID_HANDLE)
     {
      m_failed_writes++;
      return(false);
     }

   if(format==SRP_LOG4_FORMAT_CSV)
      FileWrite(handle,CLogChannelWriter::CsvHeaderLine());
   else
      FileWrite(handle,"=== "+SRP_PRODUCT_NAME+" log export "+m_symbol+" "+
                TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+" ===");

   //--- Oldest first: a log read top-to-bottom must run forwards in time.
   for(int i=m_history_size-1;i>=0;i--)
     {
      SLogRecord record;
      if(!HistoryAt(i,record))
         continue;
      const int c=Index(record.channel);
      if(c<0 || c>=SRP_LOG4_CHANNEL_COUNT || m_channels[c]==NULL)
         continue;
      FileWrite(handle,m_channels[c].Render(record,format));
     }
   FileFlush(handle);
   FileClose(handle);
   return(true);
  }
//+------------------------------------------------------------------+
bool CEnterpriseLogger::ExportChannel(const ENUM_SRP_LOG4_CHANNEL channel,
                                      const string relative_path,
                                      const ENUM_SRP_LOG4_FORMAT format,
                                      const bool common_folder)
  {
   const int c=Index(channel);
   if(c<0 || c>=SRP_LOG4_CHANNEL_COUNT || m_channels[c]==NULL)
      return(false);

   if(format==SRP_LOG4_FORMAT_JOURNAL)
     {
      int narrated=0;
      for(int i=m_history_size-1;i>=0;i--)
        {
         SLogRecord record;
         if(!HistoryAt(i,record) || record.channel!=channel)
            continue;
         Print(m_channels[c].Render(record,SRP_LOG4_FORMAT_JOURNAL));
         narrated++;
        }
      return(narrated>0);
     }

   int flags=FILE_WRITE|FILE_TXT|FILE_ANSI;
   if(common_folder)
      flags|=FILE_COMMON;
   const int handle=FileOpen(relative_path,flags);
   if(handle==INVALID_HANDLE)
     {
      m_failed_writes++;
      return(false);
     }
   if(format==SRP_LOG4_FORMAT_CSV)
      FileWrite(handle,CLogChannelWriter::CsvHeaderLine());
   else
      FileWrite(handle,"=== "+ChannelToString(channel)+" export "+
                TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+" ===");

   int written=0;
   for(int i=m_history_size-1;i>=0;i--)
     {
      SLogRecord record;
      if(!HistoryAt(i,record) || record.channel!=channel)
         continue;
      FileWrite(handle,m_channels[c].Render(record,format));
      written++;
     }
   FileFlush(handle);
   FileClose(handle);
   return(written>0);
  }
//+------------------------------------------------------------------+
string CEnterpriseLogger::ChannelToString(const ENUM_SRP_LOG4_CHANNEL channel)
  {
   switch(channel)
     {
      case SRP_LOG4_ERRORS:         return("ERRORS");
      case SRP_LOG4_TRADES:         return("TRADES");
      case SRP_LOG4_INDICATORS:     return("INDICATORS");
      case SRP_LOG4_RISK_EVENTS:    return("RISK_EVENTS");
      case SRP_LOG4_PERFORMANCE:    return("PERFORMANCE");
      case SRP_LOG4_EXECUTION_TIME: return("EXECUTION_TIME");
     }
   return("UNKNOWN");
  }
//+------------------------------------------------------------------+
string CEnterpriseLogger::FormatToString(const ENUM_SRP_LOG4_FORMAT format)
  {
   switch(format)
     {
      case SRP_LOG4_FORMAT_CSV:     return("CSV");
      case SRP_LOG4_FORMAT_TXT:     return("TXT");
      case SRP_LOG4_FORMAT_JOURNAL: return("JOURNAL");
     }
   return("UNKNOWN");
  }
//+------------------------------------------------------------------+
string CEnterpriseLogger::LevelToString(const ENUM_SRP_LOG_LEVEL level)
  {
   switch(level)
     {
      case SRP_LOG_TRACE: return("TRACE");
      case SRP_LOG_DEBUG: return("DEBUG");
      case SRP_LOG_INFO:  return("INFO");
      case SRP_LOG_WARN:  return("WARN");
      case SRP_LOG_ERROR: return("ERROR");
      case SRP_LOG_FATAL: return("FATAL");
      case SRP_LOG_OFF:   return("OFF");
     }
   return("?");
  }
//+------------------------------------------------------------------+
string CEnterpriseLogger::Describe(void) const
  {
   string text="CEnterpriseLogger["+m_symbol+"] folder="+m_folder;
   text+=" open="+(m_is_open ? "yes" : "no");
   text+=" min="+LevelToString(m_minimum_level);
   text+=" records="+IntegerToString(m_total_records);
   text+=" dropped="+IntegerToString(m_dropped_records);
   text+=" failed="+IntegerToString(m_failed_writes);
   text+=" history="+IntegerToString(m_history_size);
   for(int i=0;i<SRP_LOG4_CHANNEL_COUNT;i++)
     {
      text+="\n  ";
      if(m_channels[i]==NULL)
        {
         text+=ChannelToString((ENUM_SRP_LOG4_CHANNEL)i)+" <null>";
         continue;
        }
      text+=m_channels[i].Describe();
      text+=" routed="+IntegerToString(m_channel_counts[i]);
     }
   text+="\n  exec: avg="+DoubleToString(AverageExecutionMs(),2)+"ms";
   text+=" worst="+DoubleToString(m_exec_worst_ms,2)+"ms";
   text+=" samples="+IntegerToString(m_exec_samples);
   return(text);
  }

#endif // SRP_INTERFACE_LOGGING_CENTERPRISELOGGER_MQH
//+------------------------------------------------------------------+
