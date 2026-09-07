//+------------------------------------------------------------------+
//|                                              CTradeJournal.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Statistics : writes an auditable CSV record of every trade.             |
//|                                                                  |
//|   RESPONSIBILITY (one only): persist trade records. It computes nothing;  |
//|   CStatisticsEngine does the arithmetic.                                 |
//|                                                                  |
//|   WHY A COMMERCIAL PRODUCT NEEDS THIS                                    |
//|   When a customer reports "it took a bad trade", the journal answers      |
//|   what the spread was, which strategy fired, what the confidence was,     |
//|   why the filters allowed it and why it closed. Without that record,      |
//|   support is guesswork. It is an event listener, so the trading path       |
//|   never waits on file IO.                                               |
//+------------------------------------------------------------------+
#ifndef SRP_STATISTICS_CTRADEJOURNAL_MQH
#define SRP_STATISTICS_CTRADEJOURNAL_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"
#include "../Utilities/CFileWriter.mqh"

class CTradeJournal : public IModule
  {
private:
   CModuleIdentity   m_id;
   CFileWriter       m_writer;             // owned by value (RAII)
   IClock           *m_clock;              // borrowed
   string            m_file_path;
   bool              m_header_written;
   bool              m_enabled_in_tester;
   long              m_records_written;

   bool              WriteHeader(void);
   string            BuildRecordLine(const STradeRecord &record) const;

public:
                     CTradeJournal(const string file_path,
                                   IClock *clock,
                                   ILogger *logger);
                    ~CTradeJournal(void);

   void              SetEnabledInTester(const bool value);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   //--- Flushes and closes, so the file is complete even after a crash
   //--- during shutdown.
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;

   //--- Bus entry point via CEventListenerAdapter.
   virtual void      HandleEvent(const SEventPayload &payload) override;

   //--- Direct append, used by the statistics engine when it assembles a
   //--- complete record from a close event.
   bool              Append(const STradeRecord &record);

   //--- Writes a one-line session summary at deinit.
   bool              AppendSessionSummary(const SPerformanceMetrics &metrics);

   long              RecordsWritten(void) const { return(m_records_written); }
  };

#endif // SRP_STATISTICS_CTRADEJOURNAL_MQH
//+------------------------------------------------------------------+
