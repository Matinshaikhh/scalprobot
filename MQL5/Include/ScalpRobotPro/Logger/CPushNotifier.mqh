//+------------------------------------------------------------------+
//|                                               CPushNotifier.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Logger : INotifier channel using terminal push notifications.    |
//+------------------------------------------------------------------+
#ifndef SRP_LOGGER_CPUSHNOTIFIER_MQH
#define SRP_LOGGER_CPUSHNOTIFIER_MQH

#include "../Core/Interfaces/INotifier.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CPushNotifier : public INotifier
  {
private:
   CModuleIdentity   m_id;
   int               m_min_interval_seconds;
   datetime          m_last_sent;
   long              m_sent_count;
   long              m_throttled_count;
   bool              m_active_in_tester;

public:
                     CPushNotifier(ILogger *logger);
                    ~CPushNotifier(void) { }

   void              SetMinInterval(const int seconds);
   void              SetActiveInTester(const bool value);

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

   long              ThrottledCount(void) const { return(m_throttled_count); }
  };

#endif // SRP_LOGGER_CPUSHNOTIFIER_MQH
//+------------------------------------------------------------------+
