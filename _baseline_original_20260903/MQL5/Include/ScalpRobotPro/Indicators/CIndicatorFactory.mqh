//+------------------------------------------------------------------+
//|                                           CIndicatorFactory.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Indicators : builds the indicator set from configuration.           |
//|                                                                  |
//|   RESPONSIBILITY (one only): construct IIndicator instances.          |
//|   Separating creation from management means CIndicatorManager never   |
//|   mentions a concrete indicator type, and adding a new indicator      |
//|   touches this factory plus one new class - Open/Closed in practice.  |
//+------------------------------------------------------------------+
#ifndef SRP_INDICATORS_CINDICATORFACTORY_MQH
#define SRP_INDICATORS_CINDICATORFACTORY_MQH

#include "CIndicatorManager.mqh"
#include "../Core/Interfaces/IConfigProvider.mqh"

class CIndicatorFactory
  {
private:
   IConfigProvider  *m_config;            // borrowed
   ILogger          *m_logger;            // borrowed
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

   //--- One creator per indicator. Each returns an owned pointer that
   //--- the caller hands to the manager.
   IIndicator       *CreateFastMa(void);
   IIndicator       *CreateSlowMa(void);
   IIndicator       *CreateTrendMa(const ENUM_TIMEFRAMES timeframe);
   IIndicator       *CreateRsi(void);
   IIndicator       *CreateAtr(void);
   IIndicator       *CreateAdx(void);
   IIndicator       *CreateBollinger(void);
   IIndicator       *CreateMacd(void);
   IIndicator       *CreateStochastic(void);

public:
                     CIndicatorFactory(IConfigProvider *config,
                                       ILogger *logger,
                                       const string symbol,
                                       const ENUM_TIMEFRAMES timeframe);
                    ~CIndicatorFactory(void) { }

   //--- Populates the manager with every indicator the enabled
   //--- strategies and filters require. Only what is needed is built,
   //--- so a disabled strategy costs no terminal handle.
   bool              BuildAll(CIndicatorManager *manager);
  };

#endif // SRP_INDICATORS_CINDICATORFACTORY_MQH
//+------------------------------------------------------------------+
