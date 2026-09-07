//+------------------------------------------------------------------+
//|                                               CAlertLogSink.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Logger : raises terminal alerts for severe records only.         |
//|                                                                  |
//|   Rate-limited internally: an error storm must not produce a       |
//|   thousand modal alerts. Threshold defaults to ERROR.              |
//+------------------------------------------------------------------+
#ifndef SRP_LOGGER_CALERTLOGSINK_MQH
#define SRP_LOGGER_CALERTLOGSINK_MQH

#include "../Core/Interfaces/ILogSink.mqh"

class CAlertLogSink : public ILogSink
  {
private:
   ENUM_SRP_LOG_LEVEL m_threshold;
   bool               m_open;
   bool               m_suppress_in_tester;
   int                m_min_interval_seconds;
   datetime           m_last_alert_time;
   long               m_suppressed_count;

public:
                     CAlertLogSink(const ENUM_SRP_LOG_LEVEL threshold=SRP_LOG_ERROR);
                    ~CAlertLogSink(void) { }

   void              SetMinInterval(const int seconds);
   void              SetSuppressInTester(const bool value);

   virtual string                 SinkName(void) override { return("AlertSink"); }
   virtual ENUM_SRP_LOG_SINK_KIND Kind(void)     override { return(SRP_SINK_ALERT); }

   virtual bool      Open(void)  override;
   virtual void      Close(void) override;
   virtual void      Flush(void) override { }

   virtual void      SetThreshold(const ENUM_SRP_LOG_LEVEL level) override { m_threshold=level; }
   virtual bool      Accepts(const ENUM_SRP_LOG_LEVEL level) override;

   virtual void      Write(const ENUM_SRP_LOG_LEVEL level,
                           const string formatted_record) override;

   long              SuppressedCount(void) const { return(m_suppressed_count); }
  };

#endif // SRP_LOGGER_CALERTLOGSINK_MQH
//+------------------------------------------------------------------+
