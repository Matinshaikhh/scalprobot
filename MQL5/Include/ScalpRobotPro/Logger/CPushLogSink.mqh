//+------------------------------------------------------------------+
//|                                                CPushLogSink.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Logger : sends mobile push notifications for severe records.      |
//|                                                                  |
//|   SendNotification is rate-limited by the terminal itself, so this |
//|   sink additionally throttles to stay well inside that budget and  |
//|   silences itself entirely in the tester.                          |
//+------------------------------------------------------------------+
#ifndef SRP_LOGGER_CPUSHLOGSINK_MQH
#define SRP_LOGGER_CPUSHLOGSINK_MQH

#include "../Core/Interfaces/ILogSink.mqh"

class CPushLogSink : public ILogSink
  {
private:
   ENUM_SRP_LOG_LEVEL m_threshold;
   bool               m_open;
   int                m_min_interval_seconds;
   datetime           m_last_sent;
   int                m_max_length;
   long               m_sent_count;
   long               m_failed_count;

public:
                     CPushLogSink(const ENUM_SRP_LOG_LEVEL threshold=SRP_LOG_ERROR);
                    ~CPushLogSink(void) { }

   void              SetMinInterval(const int seconds);

   virtual string                 SinkName(void) override { return("PushSink"); }
   virtual ENUM_SRP_LOG_SINK_KIND Kind(void)     override { return(SRP_SINK_PUSH); }

   //--- Open() fails when MetaQuotes ID is not configured, which keeps
   //--- the logger from silently attempting undeliverable sends.
   virtual bool      Open(void) override;
   virtual void      Close(void) override;
   virtual void      Flush(void) override { }

   virtual void      SetThreshold(const ENUM_SRP_LOG_LEVEL level) override { m_threshold=level; }
   virtual bool      Accepts(const ENUM_SRP_LOG_LEVEL level) override;

   virtual void      Write(const ENUM_SRP_LOG_LEVEL level,
                           const string formatted_record) override;

   long              SentCount(void)   const { return(m_sent_count); }
   long              FailedCount(void) const { return(m_failed_count); }
  };

#endif // SRP_LOGGER_CPUSHLOGSINK_MQH
//+------------------------------------------------------------------+
