//+------------------------------------------------------------------+
//|                                        CMarketRegimeAnalyzer.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : classifies trend, volatility and session state.           |
//|                                                                  |
//|   RESPONSIBILITY (one only): interpretation. It enriches an        |
//|   already-captured snapshot with a regime label. Kept apart from   |
//|   CMarketDataService because "what the price is" and "what the     |
//|   price means" change for different reasons - the textbook trigger |
//|   for splitting a class.                                          |
//|                                                                  |
//|   It reads indicators through IIndicator only, so it never creates |
//|   or owns a handle.                                               |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CMARKETREGIMEANALYZER_MQH
#define SRP_CORE_CMARKETREGIMEANALYZER_MQH

#include "Interfaces/IModule.mqh"
#include "Interfaces/IIndicator.mqh"
#include "Interfaces/ILogger.mqh"
#include "Base/CModuleIdentity.mqh"

//--- Forward declarations keep this header free of concrete deps.
class CIndicatorManager;
class CSessionCalendar;

class CMarketRegimeAnalyzer : public IModule
  {
private:
   CModuleIdentity     m_id;
   CIndicatorManager  *m_indicators;      // borrowed
   CSessionCalendar   *m_sessions;        // borrowed
   double              m_high_volatility_atr_percent;
   double              m_low_volatility_atr_percent;
   double              m_extreme_volatility_atr_percent;
   double              m_trend_adx_threshold;

   ENUM_SRP_TREND_STATE      ClassifyTrend(const SMarketSnapshot &snapshot) const;
   ENUM_SRP_VOLATILITY_STATE ClassifyVolatility(const double atr_percent) const;

public:
                     CMarketRegimeAnalyzer(CIndicatorManager *indicators,
                                           CSessionCalendar *sessions,
                                           ILogger *logger);
                    ~CMarketRegimeAnalyzer(void) { }

   void              SetVolatilityThresholds(const double low_percent,
                                             const double high_percent,
                                             const double extreme_percent);
   void              SetTrendThreshold(const double adx_threshold);

   //--- IModule -----------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Enriches the snapshot in place. Called by the pipeline right
   //--- after CMarketDataService and before any strategy runs.
   bool              Annotate(SMarketSnapshot &snapshot);
  };

#endif // SRP_CORE_CMARKETREGIMEANALYZER_MQH
//+------------------------------------------------------------------+
