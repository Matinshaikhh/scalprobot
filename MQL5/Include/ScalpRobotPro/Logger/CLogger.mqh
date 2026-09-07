//+------------------------------------------------------------------+
//|                                                      CLogger.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Logger : routes records to sinks. Composite over ILogSink.        |
//|                                                                  |
//|   RESPONSIBILITY (one only): decide whether a record passes the     |
//|   global threshold, format it once, and hand it to every sink.      |
//|   It does not know what a file or an alert is.                      |
//|                                                                  |
//|   OWNERSHIP: CLogger OWNS its sinks and deletes them.               |
//|                                                                  |
//|   Note this class is intentionally NOT an IModule. The logger must  |
//|   exist before the module registry does, since the registry itself  |
//|   logs. It is therefore owned directly by CEngineBootstrapper.      |
//+------------------------------------------------------------------+
#ifndef SRP_LOGGER_CLOGGER_MQH
#define SRP_LOGGER_CLOGGER_MQH

#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Interfaces/ILogSink.mqh"
#include "CLogFormatter.mqh"

class CLogger : public ILogger
  {
private:
   ILogSink          *m_sinks[];          // OWNED
   CLogFormatter      m_formatter;        // owned by value
   ENUM_SRP_LOG_LEVEL m_minimum_level;
   long               m_record_count;
   long               m_suppressed_count;
   bool               m_reentrancy_guard; // a sink failure must not recurse

public:
                     CLogger(const ENUM_SRP_LOG_LEVEL minimum=SRP_LOG_INFO);
                    ~CLogger(void);

   //--- Composition -------------------------------------------------
   //--- Takes ownership. Returns false if refused, in which case the
   //--- caller must delete the sink.
   bool              AddSink(ILogSink *sink);
   void              RemoveAllSinks(void);
   int               SinkCount(void) const { return(ArraySize(m_sinks)); }

   CLogFormatter    *Formatter(void) { return(GetPointer(m_formatter)); }

   //--- Opens every sink. Called once by the bootstrapper.
   bool              Open(void);
   void              Close(void);

   //--- ILogger ------------------------------------------------------
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

   virtual void      LogRetcode(const string context,
                                const string operation,
                                const uint retcode) override;

   virtual bool      IsEnabled(const ENUM_SRP_LOG_LEVEL level) override
     {
      return(m_minimum_level!=SRP_LOG_OFF && level>=m_minimum_level);
     }

   virtual void      SetMinimumLevel(const ENUM_SRP_LOG_LEVEL level) override
     { m_minimum_level=level; }
   virtual ENUM_SRP_LOG_LEVEL MinimumLevel(void) override
     { return(m_minimum_level); }

   virtual void      Flush(void) override;

   //--- Diagnostics --------------------------------------------------
   long              RecordCount(void)     const { return(m_record_count); }
   long              SuppressedCount(void) const { return(m_suppressed_count); }
  };

//+------------------------------------------------------------------+
CLogger::CLogger(const ENUM_SRP_LOG_LEVEL minimum)
  : m_minimum_level(minimum),
    m_record_count(0),
    m_suppressed_count(0),
    m_reentrancy_guard(false)
  {
   ArrayResize(m_sinks,0);
  }
//+------------------------------------------------------------------+
CLogger::~CLogger(void)
  {
   Close();
   RemoveAllSinks();
  }
//+------------------------------------------------------------------+
bool CLogger::AddSink(ILogSink *sink)
  {
   if(sink==NULL)
      return(false);
   const int total=ArraySize(m_sinks);
   if(ArrayResize(m_sinks,total+1)!=total+1)
      return(false);
   m_sinks[total]=sink;
   return(true);
  }
//+------------------------------------------------------------------+
void CLogger::RemoveAllSinks(void)
  {
   const int total=ArraySize(m_sinks);
   for(int i=total-1;i>=0;i--)
     {
      if(m_sinks[i]==NULL)
         continue;
      delete m_sinks[i];
      m_sinks[i]=NULL;
     }
   ArrayResize(m_sinks,0);
  }
//+------------------------------------------------------------------+
bool CLogger::Open(void)
  {
   bool any_open=false;
   const int total=ArraySize(m_sinks);
   for(int i=0;i<total;i++)
      if(m_sinks[i]!=NULL && m_sinks[i].Open())
         any_open=true;
   //--- At least one working sink is required, otherwise the product
   //--- would run blind and support would be impossible.
   return(any_open);
  }
//+------------------------------------------------------------------+
void CLogger::Close(void)
  {
   const int total=ArraySize(m_sinks);
   for(int i=0;i<total;i++)
      if(m_sinks[i]!=NULL)
        {
         m_sinks[i].Flush();
         m_sinks[i].Close();
        }
  }
//+------------------------------------------------------------------+
void CLogger::Log(const ENUM_SRP_LOG_LEVEL level,
                  const string context,
                  const string message)
  {
   if(!IsEnabled(level))
     {
      m_suppressed_count++;
      return;
     }
   if(m_reentrancy_guard)
      return;
   m_reentrancy_guard=true;

   //--- Format once, fan out to many. Sinks apply their own threshold.
   const string record=m_formatter.Format(level,context,message);
   const int total=ArraySize(m_sinks);
   for(int i=0;i<total;i++)
      if(m_sinks[i]!=NULL)
         m_sinks[i].Write(level,record);

   m_record_count++;
   m_reentrancy_guard=false;
  }
//+------------------------------------------------------------------+
void CLogger::LogRetcode(const string context,
                         const string operation,
                         const uint retcode)
  {
   //--- Retcode decoding lives in CErrorHandler; the logger only
   //--- composes the message so the two do not duplicate tables.
   Log(SRP_LOG_ERROR,context,
       operation+" failed, retcode="+IntegerToString(retcode));
  }
//+------------------------------------------------------------------+
void CLogger::Flush(void)
  {
   const int total=ArraySize(m_sinks);
   for(int i=0;i<total;i++)
      if(m_sinks[i]!=NULL)
         m_sinks[i].Flush();
  }

#endif // SRP_LOGGER_CLOGGER_MQH
//+------------------------------------------------------------------+
