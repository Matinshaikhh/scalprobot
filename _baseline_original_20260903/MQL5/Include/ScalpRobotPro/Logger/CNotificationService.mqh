//+------------------------------------------------------------------+
//|                                        CNotificationService.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Logger : operator alerting driven by domain events.               |
//|                                                                  |
//|   RESPONSIBILITY (one only): translate significant domain events   |
//|   into human notifications through INotifier channels. It is an     |
//|   event OBSERVER, so nothing in the trading path calls it - the     |
//|   pipeline stays free of notification code entirely.               |
//|                                                                  |
//|   OWNERSHIP: owns its INotifier channels.                           |
//+------------------------------------------------------------------+
#ifndef SRP_LOGGER_CNOTIFICATIONSERVICE_MQH
#define SRP_LOGGER_CNOTIFICATIONSERVICE_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/INotifier.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CNotificationService : public IModule
  {
private:
   CModuleIdentity   m_id;
   INotifier        *m_channels[];        // OWNED
   //--- Which events warrant interrupting a human. Configured, not
   //--- hard-coded, so a scalper on M1 is not buried in messages.
   ENUM_SRP_EVENT    m_subscribed_events[];
   long              m_sent_count;

   bool              IsSubscribed(const ENUM_SRP_EVENT event_id) const;
   //--- Builds the notification text for a given event.
   bool              ComposeMessage(const SEventPayload &payload,
                                    ENUM_SRP_LOG_LEVEL &severity,
                                    string &subject,
                                    string &body) const;

public:
                     CNotificationService(ILogger *logger);
                    ~CNotificationService(void);

   //--- Takes ownership of the channel.
   bool              AddChannel(INotifier *channel);
   bool              SubscribeEvent(const ENUM_SRP_EVENT event_id);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;

   //--- Bus entry point, invoked via CEventListenerAdapter.
   virtual void      HandleEvent(const SEventPayload &payload) override;

   long              SentCount(void) const { return(m_sent_count); }
  };

#endif // SRP_LOGGER_CNOTIFICATIONSERVICE_MQH
//+------------------------------------------------------------------+
