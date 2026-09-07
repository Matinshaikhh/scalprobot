//+------------------------------------------------------------------+
//|                                               CLogFormatter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Logger : turns a record into a string. Nothing else.             |
//|                                                                  |
//|   Separated from CLogger because formatting changes for cosmetic   |
//|   reasons while routing changes for functional reasons. Two        |
//|   reasons to change means two classes.                             |
//+------------------------------------------------------------------+
#ifndef SRP_LOGGER_CLOGFORMATTER_MQH
#define SRP_LOGGER_CLOGFORMATTER_MQH

#include "../Core/Types/Enums.mqh"
#include "../Core/Interfaces/IClock.mqh"

class CLogFormatter
  {
private:
   IClock           *m_clock;            // borrowed
   bool              m_include_timestamp;
   bool              m_include_level;
   bool              m_include_context;
   bool              m_include_milliseconds;
   string            m_field_separator;

public:
                     CLogFormatter(void);
                    ~CLogFormatter(void) { }

   void              SetClock(IClock *clock) { m_clock=clock; }
   void              SetLayout(const bool timestamp,
                               const bool level,
                               const bool context,
                               const bool milliseconds);
   void              SetSeparator(const string separator);

   //--- Standard record.
   string            Format(const ENUM_SRP_LOG_LEVEL level,
                            const string context,
                            const string message) const;

   //--- CSV variant for the file sink, so logs load into a spreadsheet.
   string            FormatCsv(const ENUM_SRP_LOG_LEVEL level,
                               const string context,
                               const string message) const;

   static string     LevelToString(const ENUM_SRP_LOG_LEVEL level);
   static string     LevelToShortString(const ENUM_SRP_LOG_LEVEL level);
  };

//+------------------------------------------------------------------+
CLogFormatter::CLogFormatter(void)
  : m_clock(NULL),
    m_include_timestamp(true),
    m_include_level(true),
    m_include_context(true),
    m_include_milliseconds(false),
    m_field_separator(" | ")
  {
  }
//+------------------------------------------------------------------+
void CLogFormatter::SetLayout(const bool timestamp,const bool level,
                              const bool context,const bool milliseconds)
  {
   m_include_timestamp    = timestamp;
   m_include_level        = level;
   m_include_context      = context;
   m_include_milliseconds = milliseconds;
  }
//+------------------------------------------------------------------+
void CLogFormatter::SetSeparator(const string separator)
  {
   m_field_separator=separator;
  }
//+------------------------------------------------------------------+
string CLogFormatter::Format(const ENUM_SRP_LOG_LEVEL level,
                             const string context,
                             const string message) const
  {
   string out="";
   if(m_include_timestamp)
     {
      const datetime now=(m_clock!=NULL ? m_clock.ServerTime() : TimeCurrent());
      out+=TimeToString(now,TIME_DATE|TIME_SECONDS);
      if(m_include_milliseconds && m_clock!=NULL)
         out+="."+IntegerToString((int)(m_clock.TickCountMs()%1000),3,'0');
      out+=m_field_separator;
     }
   if(m_include_level)
      out+=LevelToShortString(level)+m_field_separator;
   if(m_include_context)
      out+=context+m_field_separator;
   out+=message;
   return(out);
  }
//+------------------------------------------------------------------+
string CLogFormatter::FormatCsv(const ENUM_SRP_LOG_LEVEL level,
                                const string context,
                                const string message) const
  {
   const datetime now=(m_clock!=NULL ? m_clock.ServerTime() : TimeCurrent());
   //--- Quote the message: it may legitimately contain a comma.
   return(TimeToString(now,TIME_DATE|TIME_SECONDS)+","+
          LevelToString(level)+","+
          context+",\""+message+"\"");
  }
//+------------------------------------------------------------------+
string CLogFormatter::LevelToString(const ENUM_SRP_LOG_LEVEL level)
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
   return("UNKNOWN");
  }
//+------------------------------------------------------------------+
string CLogFormatter::LevelToShortString(const ENUM_SRP_LOG_LEVEL level)
  {
   switch(level)
     {
      case SRP_LOG_TRACE: return("TRC");
      case SRP_LOG_DEBUG: return("DBG");
      case SRP_LOG_INFO:  return("INF");
      case SRP_LOG_WARN:  return("WRN");
      case SRP_LOG_ERROR: return("ERR");
      case SRP_LOG_FATAL: return("FTL");
      case SRP_LOG_OFF:   return("OFF");
     }
   return("UNK");
  }

#endif // SRP_LOGGER_CLOGFORMATTER_MQH
//+------------------------------------------------------------------+
