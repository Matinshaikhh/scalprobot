//+------------------------------------------------------------------+
//|                                              CEmailNotifier.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Logger : INotifier channel using terminal SMTP settings.          |
//|                                                                  |
//|   Email is slow, so this channel is reserved for low-frequency,     |
//|   high-importance messages (daily summary, kill switch, guard       |
//|   trips) and refuses to open when SMTP is not configured.           |
//+------------------------------------------------------------------+
#ifndef SRP_LOGGER_CEMAILNOTIFIER_MQH
#define SRP_LOGGER_CEMAILNOTIFIER_MQH

#include "../Core/Interfaces/INotifier.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CEmailNotifier : public INotifier
  {
private:
   CModuleIdentity   m_id;
   ENUM_SRP_LOG_LEVEL m_minimum_severity;
   int               m_min_interval_seconds;
   datetime          m_last_sent;
   long              m_sent_count;
   long              m_failed_count;
   bool              m_smtp_available;

public:
                     CEmailNotifier(ILogger *logger);
                    ~CEmailNotifier(void) { }

   void              SetMinimumSeverity(const ENUM_SRP_LOG_LEVEL level);
   void              SetMinInterval(const int seconds);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- INotifier ----------------------------------------------------
   virtual string    ChannelName(void) override { return(m_id.Name()); }
   virtual bool      IsEnabled(void) override { return(m_id.IsEnabled()); }
   virtual void      SetEnabled(const bool enabled) override { m_id.SetEnabled(enabled); }
   virtual bool      Notify(const ENUM_SRP_LOG_LEVEL severity,
                            const string subject,
                            const string body) override;

   long              FailedCount(void) const { return(m_failed_count); }
  };

#endif // SRP_LOGGER_CEMAILNOTIFIER_MQH
//+------------------------------------------------------------------+
