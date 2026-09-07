//+------------------------------------------------------------------+
//|                                           CMarketDataService.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : builds the single authoritative SMarketSnapshot.          |
//|                                                                  |
//|   RESPONSIBILITY (one only): read prices and bars, detect the new  |
//|   bar, and publish one coherent snapshot per pass. It performs no  |
//|   interpretation - regime classification belongs to               |
//|   CMarketRegimeAnalyzer.                                          |
//|                                                                  |
//|   WHY THIS MATTERS                                                |
//|   Without a snapshot, strategy A reads bid at microsecond X and    |
//|   filter B reads it at X+n. On M1 gold those differ, so a trade    |
//|   can be approved against prices that no longer exist. One read,   |
//|   one truth, for the whole pass.                                   |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CMARKETDATASERVICE_MQH
#define SRP_CORE_CMARKETDATASERVICE_MQH

#include "Interfaces/IModule.mqh"
#include "Interfaces/IClock.mqh"
#include "Interfaces/ILogger.mqh"
#include "Interfaces/IEventPublisher.mqh"
#include "Base/CModuleIdentity.mqh"

class CMarketDataService : public IModule
  {
private:
   CModuleIdentity   m_id;
   IClock           *m_clock;             // borrowed
   IEventPublisher  *m_publisher;         // borrowed
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   SMarketSnapshot   m_snapshot;
   datetime          m_last_bar_time;
   ulong             m_sequence;
   int               m_required_bars;
   //--- Rolling spread window, used for the spread average that the
   //--- spread filter compares against.
   double            m_spread_window[];
   int               m_spread_window_size;
   int               m_spread_cursor;

   bool              ReadTick(void);
   bool              ReadBars(void);
   bool              DetectNewBar(void);
   void              UpdateSpreadStatistics(void);

public:
                     CMarketDataService(const string symbol,
                                        const ENUM_TIMEFRAMES timeframe,
                                        IClock *clock,
                                        ILogger *logger,
                                        IEventPublisher *publisher);
                    ~CMarketDataService(void);

   void              SetRequiredBars(const int bars);
   void              SetSpreadWindow(const int size);

   //--- IModule -----------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Pipeline entry point. Returns false when data is unusable,
   //--- which aborts the pass rather than trading on bad prices.
   bool              CaptureSnapshot(void);

   void              GetSnapshot(SMarketSnapshot &out) const { out=m_snapshot; }
   bool              IsNewBar(void)      const { return(m_snapshot.is_new_bar); }
   ulong             SequenceId(void)    const { return(m_sequence); }
   bool              HasSufficientHistory(void) const;
  };

#endif // SRP_CORE_CMARKETDATASERVICE_MQH
//+------------------------------------------------------------------+
