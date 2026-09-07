//+------------------------------------------------------------------+
//|                                        CEquityCurveTracker.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Statistics : samples the equity curve for display and drawdown.         |
//|                                                                  |
//|   RESPONSIBILITY (one only): maintain a bounded time series of equity      |
//|   samples plus the running peak.                                         |
//|                                                                  |
//|   The peak is the authoritative input to CDrawdownGuard, which is why      |
//|   it lives in one place and is persisted. Two modules independently        |
//|   tracking "the high water mark" is how a drawdown limit ends up           |
//|   measuring something nobody intended.                                    |
//+------------------------------------------------------------------+
#ifndef SRP_STATISTICS_CEQUITYCURVETRACKER_MQH
#define SRP_STATISTICS_CEQUITYCURVETRACKER_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IStateStore.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"
#include "../Utilities/CCircularBuffer.mqh"

class CEquityCurveTracker : public IModule
  {
private:
   CModuleIdentity   m_id;
   IStateStore      *m_state;              // borrowed
   IClock           *m_clock;              // borrowed
   CCircularBuffer   m_equity_samples;     // owned by value
   CCircularBuffer   m_balance_samples;
   int               m_sample_interval_seconds;
   datetime          m_last_sample;
   double            m_peak_equity;
   double            m_trough_equity;
   double            m_current_drawdown_percent;
   double            m_max_drawdown_percent;

   void              Persist(void);
   void              Restore(void);

public:
                     CEquityCurveTracker(IStateStore *state,
                                         IClock *clock,
                                         ILogger *logger);
                    ~CEquityCurveTracker(void) { }

   void              SetCapacity(const int samples);
   void              SetSampleInterval(const int seconds);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Called once per pass; internally throttled by the interval.
   void              Sample(const SAccountSnapshot &account);

   //--- Queries -------------------------------------------------------
   double            PeakEquity(void)             const { return(m_peak_equity); }
   double            CurrentDrawdownPercent(void) const { return(m_current_drawdown_percent); }
   double            MaxDrawdownPercent(void)     const { return(m_max_drawdown_percent); }
   int               SampleCount(void)            const { return(m_equity_samples.Count()); }
   //--- Chronological copy for the equity-curve widget.
   bool              GetSamples(double &out[]) const;
  };

#endif // SRP_STATISTICS_CEQUITYCURVETRACKER_MQH
//+------------------------------------------------------------------+
