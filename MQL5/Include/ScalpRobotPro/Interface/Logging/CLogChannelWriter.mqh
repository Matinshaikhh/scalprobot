//+------------------------------------------------------------------+
//|                                         CLogChannelWriter.mqh |
//|                    Scalping Robot Pro - Trader Interface (P4) |
//|                                                                  |
//|   RESPONSIBILITY (one only): persist the records of ONE channel in     |
//|   ONE format.                                                        |
//|                                                                  |
//|   It knows nothing about channel semantics. The caller supplies the    |
//|   base file name, the display tag and the CSV header, so adding a      |
//|   seventh channel never touches this class (Open/Closed).             |
//|                                                                  |
//|   THREE FORMATS:                                                     |
//|     CSV     - one row per record, real columns, Excel-ready.          |
//|     TXT     - one aligned human-readable line per record.             |
//|     JOURNAL - no file at all; the record is narrated into the MT5     |
//|               Experts Journal. This is what "Journal" means in the     |
//|               terminal, and it is the only export that survives a      |
//|               sandbox with file writing disabled.                     |
//|                                                                  |
//|   RAII: the destructor closes the handle. A leaked MQL5 file handle    |
//|   keeps the file locked until the terminal restarts, which in          |
//|   production shows up as "logs silently stopped".                     |
//|                                                                  |
//|   DAILY ROTATION is on by default. One unbounded log file is          |
//|   unusable after a week of tick-level records.                        |
//+------------------------------------------------------------------+
#ifndef SRP_INTERFACE_LOGGING_CLOGCHANNELWRITER_MQH
#define SRP_INTERFACE_LOGGING_CLOGCHANNELWRITER_MQH

#include "../../Core/Types/Constants.mqh"
#include "../Types/InterfaceStructs.mqh"

class CLogChannelWriter
  {
private:
   //--- Identity, supplied by the router.
   string            m_folder;         // relative to MQL5\Files
   string            m_base_name;      // "errors"
   string            m_channel_tag;    // "ERRORS"
   string            m_csv_header;

   ENUM_SRP_LOG4_FORMAT m_format;
   bool              m_enabled;
   bool              m_daily_rotation;
   bool              m_common_folder;

   int               m_handle;
   string            m_path;
   datetime          m_open_day;       // day stamp of the open file

   //--- Buffered flushing: flushing every record makes tick-rate
   //--- logging measurably slow, never flushing loses the tail on a
   //--- crash. A small count is the honest compromise.
   int               m_flush_every;
   int               m_pending;

   long              m_written;
   long              m_failed;

   static datetime   DayStamp(const datetime when);
   string            Extension(void) const;
   string            BuildPath(const datetime when) const;
   bool              OpenFor(const datetime when);
   bool              WriteRaw(const string line);
   string            FormatCsv(const SLogRecord &record) const;
   string            FormatTxt(const SLogRecord &record) const;
   string            FormatJournal(const SLogRecord &record) const;

public:
                     CLogChannelWriter(const string folder,
                                       const string base_name,
                                       const string channel_tag,
                                       const string csv_header,
                                       const ENUM_SRP_LOG4_FORMAT format);
                    ~CLogChannelWriter(void);

   //--- Configuration. A format or folder change closes the current
   //--- file so the next write lands in the right place.
   void              SetFormat(const ENUM_SRP_LOG4_FORMAT format);
   void              SetFolder(const string folder);
   void              SetEnabled(const bool enabled);
   void              SetDailyRotation(const bool enabled);
   void              SetCommonFolder(const bool common);
   void              SetFlushEvery(const int records);
   void              SetCsvHeader(const string header) { m_csv_header=header; }

   bool              Open(void);
   void              Close(void);
   void              Flush(void);

   //--- Returns false only on a real failure, not when the channel is
   //--- disabled: a muted channel is a configuration choice, not an error.
   bool              Write(const SLogRecord &record);

   //--- One-shot render used by the exporter, which must be able to
   //--- produce a CSV line for a record whose channel writes TXT.
   string            Render(const SLogRecord &record,
                            const ENUM_SRP_LOG4_FORMAT format) const;

   bool              IsOpen(void)      const { return(m_handle!=INVALID_HANDLE); }
   bool              IsEnabled(void)   const { return(m_enabled); }
   string            Path(void)        const { return(m_path); }
   string            Tag(void)         const { return(m_channel_tag); }
   string            BaseName(void)    const { return(m_base_name); }
   ENUM_SRP_LOG4_FORMAT Format(void)   const { return(m_format); }
   long              WrittenCount(void) const { return(m_written); }
   long              FailedCount(void) const { return(m_failed); }
   string            Describe(void) const;

   //--- Shared text helpers, used by the exporter too.
   static string     CsvEscape(const string text);
   static string     Stamp(const datetime when,const ulong milliseconds);
   static string     CsvHeaderLine(void);
  };

//+------------------------------------------------------------------+
CLogChannelWriter::CLogChannelWriter(const string folder,
                                     const string base_name,
                                     const string channel_tag,
                                     const string csv_header,
                                     const ENUM_SRP_LOG4_FORMAT format)
  : m_folder(folder),
    m_base_name(base_name),
    m_channel_tag(channel_tag),
    m_csv_header(csv_header),
    m_format(format),
    m_enabled(true),
    m_daily_rotation(true),
    m_common_folder(false),
    m_handle(INVALID_HANDLE),
    m_path(""),
    m_open_day(0),
    m_flush_every(8),
    m_pending(0),
    m_written(0),
    m_failed(0)
  {
  }
//+------------------------------------------------------------------+
CLogChannelWriter::~CLogChannelWriter(void)
  {
   //--- The whole reason this is a class and not a free function.
   Close();
  }
//+------------------------------------------------------------------+
datetime CLogChannelWriter::DayStamp(const datetime when)
  {
   MqlDateTime parts;
   TimeToStruct(when,parts);
   parts.hour=0; parts.min=0; parts.sec=0;
   return(StructToTime(parts));
  }
//+------------------------------------------------------------------+
string CLogChannelWriter::Extension(void) const
  {
   return(m_format==SRP_LOG4_FORMAT_CSV ? ".csv" : ".txt");
  }
//+------------------------------------------------------------------+
string CLogChannelWriter::BuildPath(const datetime when) const
  {
   string name=m_base_name;
   if(m_daily_rotation)
     {
      MqlDateTime parts;
      TimeToStruct(when,parts);
      name+=StringFormat("_%04d%02d%02d",parts.year,parts.mon,parts.day);
     }
   name+=Extension();
   if(m_folder=="")
      return(name);
   return(m_folder+"\\"+name);
  }
//+------------------------------------------------------------------+
void CLogChannelWriter::SetFormat(const ENUM_SRP_LOG4_FORMAT format)
  {
   if(format==m_format)
      return;
   //--- The extension changes with the format, so the old handle is
   //--- no longer the right destination.
   Close();
   m_format=format;
  }
//+------------------------------------------------------------------+
void CLogChannelWriter::SetFolder(const string folder)
  {
   if(folder==m_folder)
      return;
   Close();
   m_folder=folder;
  }
//+------------------------------------------------------------------+
void CLogChannelWriter::SetEnabled(const bool enabled)
  {
   m_enabled=enabled;
   if(!enabled)
      Close();
  }
//+------------------------------------------------------------------+
void CLogChannelWriter::SetDailyRotation(const bool enabled)
  {
   if(enabled==m_daily_rotation)
      return;
   Close();
   m_daily_rotation=enabled;
  }
//+------------------------------------------------------------------+
void CLogChannelWriter::SetCommonFolder(const bool common)
  {
   if(common==m_common_folder)
      return;
   Close();
   m_common_folder=common;
  }
//+------------------------------------------------------------------+
void CLogChannelWriter::SetFlushEvery(const int records)
  {
   m_flush_every=(records<1 ? 1 : records);
  }
//+------------------------------------------------------------------+
bool CLogChannelWriter::Open(void)
  {
   return(OpenFor(TimeCurrent()));
  }
//+------------------------------------------------------------------+
bool CLogChannelWriter::OpenFor(const datetime when)
  {
   //--- JOURNAL keeps no file; reporting success here lets the router
   //--- treat all channels uniformly.
   if(m_format==SRP_LOG4_FORMAT_JOURNAL)
      return(true);
   if(!m_enabled)
      return(false);

   const datetime day=DayStamp(when);
   if(m_handle!=INVALID_HANDLE)
     {
      if(!m_daily_rotation || day==m_open_day)
         return(true);
      Close();                            // rolled past midnight
     }

   const string path=BuildPath(when);
   const bool existed=FileIsExist(path,m_common_folder ? FILE_COMMON : 0);

   int flags=FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ;
   if(m_common_folder)
      flags|=FILE_COMMON;

   m_handle=FileOpen(path,flags);
   if(m_handle==INVALID_HANDLE)
     {
      m_failed++;
      return(false);
     }
   m_path=path;
   m_open_day=day;
   //--- Append rather than truncate: a restart mid-session must not
   //--- destroy the morning's audit trail.
   FileSeek(m_handle,0,SEEK_END);

   if(!existed && m_format==SRP_LOG4_FORMAT_CSV && m_csv_header!="")
      WriteRaw(m_csv_header);
   else
      if(!existed && m_format==SRP_LOG4_FORMAT_TXT)
         WriteRaw("=== "+SRP_PRODUCT_NAME+" "+m_channel_tag+
                  " log opened "+TimeToString(when,TIME_DATE|TIME_SECONDS)+
                  " ===");
   return(true);
  }
//+------------------------------------------------------------------+
void CLogChannelWriter::Close(void)
  {
   if(m_handle==INVALID_HANDLE)
      return;
   FileFlush(m_handle);
   FileClose(m_handle);
   m_handle=INVALID_HANDLE;
   m_pending=0;
  }
//+------------------------------------------------------------------+
void CLogChannelWriter::Flush(void)
  {
   if(m_handle==INVALID_HANDLE)
      return;
   FileFlush(m_handle);
   m_pending=0;
  }
//+------------------------------------------------------------------+
bool CLogChannelWriter::WriteRaw(const string line)
  {
   if(m_handle==INVALID_HANDLE)
      return(false);
   //--- FILE_TXT appends the line break for us; building the delimiter
   //--- by hand keeps CSV quoting under our control.
   if(FileWrite(m_handle,line)<=0)
     {
      m_failed++;
      return(false);
     }
   m_pending++;
   if(m_pending>=m_flush_every)
      Flush();
   return(true);
  }
//+------------------------------------------------------------------+
bool CLogChannelWriter::Write(const SLogRecord &record)
  {
   if(!m_enabled)
      return(true);                       // muted on purpose

   if(m_format==SRP_LOG4_FORMAT_JOURNAL)
     {
      //--- Straight to the Experts tab. No handle, no rotation.
      Print(FormatJournal(record));
      m_written++;
      return(true);
     }

   const datetime when=(record.timestamp==0 ? TimeCurrent() : record.timestamp);
   if(!OpenFor(when))
      return(false);

   const string line=(m_format==SRP_LOG4_FORMAT_CSV
                      ? FormatCsv(record)
                      : FormatTxt(record));
   if(!WriteRaw(line))
      return(false);
   m_written++;
   return(true);
  }
//+------------------------------------------------------------------+
string CLogChannelWriter::Render(const SLogRecord &record,
                                 const ENUM_SRP_LOG4_FORMAT format) const
  {
   switch(format)
     {
      case SRP_LOG4_FORMAT_CSV:     return(FormatCsv(record));
      case SRP_LOG4_FORMAT_JOURNAL: return(FormatJournal(record));
      default:                      break;
     }
   return(FormatTxt(record));
  }
//+------------------------------------------------------------------+
string CLogChannelWriter::FormatCsv(const SLogRecord &record) const
  {
   //--- Column order must match CsvHeaderLine() exactly.
   string row=Stamp(record.timestamp,record.timestamp_ms);
   row+=","+CsvEscape(m_channel_tag);
   row+=","+CsvEscape(record.context);
   row+=","+CsvEscape(record.message);
   row+=","+(record.ticket==SRP_INVALID_TICKET
             ? "" : IntegerToString((long)record.ticket));
   row+=","+DoubleToString(record.value_a,5);
   row+=","+DoubleToString(record.value_b,5);
   row+=","+DoubleToString(record.value_c,5);
   return(row);
  }
//+------------------------------------------------------------------+
string CLogChannelWriter::FormatTxt(const SLogRecord &record) const
  {
   string line=Stamp(record.timestamp,record.timestamp_ms);
   line+=" ["+m_channel_tag+"]";
   if(record.context!="")
      line+=" "+record.context+":";
   line+=" "+record.message;
   if(record.ticket!=SRP_INVALID_TICKET)
      line+="  #"+IntegerToString((long)record.ticket);
   //--- The numeric payload is only appended when it carries something,
   //--- otherwise every line would end in three zeroes.
   if(record.value_a!=0.0 || record.value_b!=0.0 || record.value_c!=0.0)
      line+="  ("+DoubleToString(record.value_a,5)+
            " | "+DoubleToString(record.value_b,5)+
            " | "+DoubleToString(record.value_c,5)+")";
   return(line);
  }
//+------------------------------------------------------------------+
string CLogChannelWriter::FormatJournal(const SLogRecord &record) const
  {
   //--- Narrative, because a human reads the Journal in real time.
   string line=SRP_PRODUCT_SHORT+" "+m_channel_tag;
   if(record.context!="")
      line+=" ("+record.context+")";
   line+=": "+record.message;
   if(record.ticket!=SRP_INVALID_TICKET)
      line+=" [ticket "+IntegerToString((long)record.ticket)+"]";
   return(line);
  }
//+------------------------------------------------------------------+
string CLogChannelWriter::CsvEscape(const string text)
  {
   if(text=="")
      return("");
   const bool needs=(StringFind(text,",")>=0 ||
                     StringFind(text,"\"")>=0 ||
                     StringFind(text,"\n")>=0);
   if(!needs)
      return(text);
   string escaped=text;
   StringReplace(escaped,"\"","\"\"");
   StringReplace(escaped,"\n"," ");
   StringReplace(escaped,"\r","");
   return("\""+escaped+"\"");
  }
//+------------------------------------------------------------------+
string CLogChannelWriter::Stamp(const datetime when,const ulong milliseconds)
  {
   const datetime effective=(when==0 ? TimeCurrent() : when);
   string text=TimeToString(effective,TIME_DATE|TIME_SECONDS);
   //--- Sub-second resolution matters for execution-time analysis, where
   //--- two fills inside the same second are common.
   text+=StringFormat(".%03d",(int)(milliseconds%1000));
   return(text);
  }
//+------------------------------------------------------------------+
string CLogChannelWriter::CsvHeaderLine(void)
  {
   return("timestamp,channel,context,message,ticket,value_a,value_b,value_c");
  }
//+------------------------------------------------------------------+
string CLogChannelWriter::Describe(void) const
  {
   string text=m_channel_tag;
   text+=" fmt=";
   switch(m_format)
     {
      case SRP_LOG4_FORMAT_CSV:     text+="CSV";     break;
      case SRP_LOG4_FORMAT_TXT:     text+="TXT";     break;
      case SRP_LOG4_FORMAT_JOURNAL: text+="JOURNAL"; break;
     }
   text+=" enabled="+(m_enabled ? "yes" : "no");
   text+=" open="+(IsOpen() ? "yes" : "no");
   text+=" written="+IntegerToString(m_written);
   text+=" failed="+IntegerToString(m_failed);
   if(m_path!="")
      text+=" path="+m_path;
   return(text);
  }

#endif // SRP_INTERFACE_LOGGING_CLOGCHANNELWRITER_MQH
//+------------------------------------------------------------------+
