//+------------------------------------------------------------------+
//|                                           CCsvNewsProvider.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   News : INewsProvider backed by a user-supplied CSV file.               |
//|                                                                  |
//|   Exists because the terminal calendar is unavailable in the strategy     |
//|   tester. Without a file-based source, every backtest would either        |
//|   ignore news entirely (optimistic and misleading) or block everything    |
//|   (useless). A CSV lets the news filter be tested honestly against       |
//|   historical events.                                                    |
//|                                                                  |
//|   Expected format, one event per line:                                   |
//|     YYYY.MM.DD HH:MM;currency;impact;title                              |
//|   Malformed lines are counted and reported rather than skipped silently.  |
//+------------------------------------------------------------------+
#ifndef SRP_NEWS_CCSVNEWSPROVIDER_MQH
#define SRP_NEWS_CCSVNEWSPROVIDER_MQH

#include "../Core/Interfaces/INewsProvider.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CCsvNewsProvider : public INewsProvider
  {
private:
   CModuleIdentity   m_id;
   IClock           *m_clock;              // borrowed
   string            m_file_path;
   bool              m_common_folder;
   SNewsEvent        m_events[];
   datetime          m_last_refresh;
   bool              m_loaded;
   int               m_malformed_lines;
   string            m_currencies[];
   ENUM_SRP_NEWS_IMPACT m_minimum_impact;

   bool              ParseLine(const string line,SNewsEvent &event) const;
   ENUM_SRP_NEWS_IMPACT ParseImpact(const string text) const;
   bool              IsCurrencyRelevant(const string currency) const;
   //--- Sorted by time so blackout lookups can stop early.
   void              SortByTime(void);

public:
                     CCsvNewsProvider(const string file_path,
                                      IClock *clock,
                                      ILogger *logger);
                    ~CCsvNewsProvider(void);

   void              SetCommonFolder(const bool value);
   void              SetCurrencyFilter(const string csv_currencies);
   void              SetMinimumImpact(const ENUM_SRP_NEWS_IMPACT impact);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   //--- Loads the whole file once: a backtest cannot afford per-tick IO.
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- INewsProvider ------------------------------------------------
   virtual ENUM_SRP_NEWS_SOURCE SourceKind(void) override
     { return(SRP_NEWS_SOURCE_CSV_FILE); }
   virtual string    ProviderName(void) override { return(m_id.Name()); }
   virtual bool      IsAvailable(void) override { return(m_loaded); }
   virtual bool      Refresh(const datetime from,const datetime to) override;
   virtual int       EventCount(void) override { return(ArraySize(m_events)); }
   virtual bool      GetEvent(const int index,SNewsEvent &event) override;
   virtual datetime  LastRefreshTime(void) override { return(m_last_refresh); }

   int               MalformedLineCount(void) const { return(m_malformed_lines); }
  };

#endif // SRP_NEWS_CCSVNEWSPROVIDER_MQH
//+------------------------------------------------------------------+
