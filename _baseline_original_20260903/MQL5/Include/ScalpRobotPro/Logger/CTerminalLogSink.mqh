//+------------------------------------------------------------------+
//|                                            CTerminalLogSink.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Logger : writes to the terminal Experts tab.                     |
//+------------------------------------------------------------------+
#ifndef SRP_LOGGER_CTERMINALLOGSINK_MQH
#define SRP_LOGGER_CTERMINALLOGSINK_MQH

#include "../Core/Interfaces/ILogSink.mqh"

class CTerminalLogSink : public ILogSink
  {
private:
   ENUM_SRP_LOG_LEVEL m_threshold;
   bool               m_open;

public:
                     CTerminalLogSink(const ENUM_SRP_LOG_LEVEL threshold=SRP_LOG_INFO)
     : m_threshold(threshold),
       m_open(false)
     {
     }
                    ~CTerminalLogSink(void) { }

   virtual string                 SinkName(void) override { return("TerminalSink"); }
   virtual ENUM_SRP_LOG_SINK_KIND Kind(void)     override { return(SRP_SINK_TERMINAL); }

   virtual bool      Open(void)  override { m_open=true; return(true); }
   virtual void      Close(void) override { m_open=false; }
   virtual void      Flush(void) override { }

   virtual void      SetThreshold(const ENUM_SRP_LOG_LEVEL level) override { m_threshold=level; }
   virtual bool      Accepts(const ENUM_SRP_LOG_LEVEL level) override
     {
      return(m_open && m_threshold!=SRP_LOG_OFF && level>=m_threshold);
     }

   virtual void      Write(const ENUM_SRP_LOG_LEVEL level,
                           const string formatted_record) override
     {
      if(!Accepts(level))
         return;
      Print(formatted_record);
     }
  };

#endif // SRP_LOGGER_CTERMINALLOGSINK_MQH
//+------------------------------------------------------------------+
