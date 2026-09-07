//+------------------------------------------------------------------+
//|                                            CStrategyFactory.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Strategies : builds the enabled strategy set from configuration.     |
//|                                                                  |
//|   RESPONSIBILITY (one only): construct IStrategy instances and tune    |
//|   them from settings. Keeping construction here is what allows         |
//|   CStrategyOrchestrator to remain ignorant of concrete strategy types. |
//+------------------------------------------------------------------+
#ifndef SRP_STRATEGIES_CSTRATEGYFACTORY_MQH
#define SRP_STRATEGIES_CSTRATEGYFACTORY_MQH

#include "CStrategyOrchestrator.mqh"
#include "../Core/Interfaces/IConfigProvider.mqh"
#include "../Indicators/CIndicatorManager.mqh"

class CStrategyFactory
  {
private:
   IConfigProvider   *m_config;            // borrowed
   CIndicatorManager *m_indicators;        // borrowed
   ILogger           *m_logger;            // borrowed

   //--- One creator per strategy; each reads only its own settings.
   IStrategy        *CreateMomentum(void);
   IStrategy        *CreateMeanReversion(void);
   IStrategy        *CreateBreakout(void);
   IStrategy        *CreateVolatilityExpansion(void);

public:
                     CStrategyFactory(IConfigProvider *config,
                                      CIndicatorManager *indicators,
                                      ILogger *logger);
                    ~CStrategyFactory(void) { }

   //--- Adds every ENABLED strategy to the orchestrator and configures
   //--- the aggregation policy. Returns false when nothing is enabled,
   //--- since an EA with no strategy would run but never trade - a
   //--- configuration error worth failing loudly on.
   bool              BuildAll(CStrategyOrchestrator *orchestrator);
  };

#endif // SRP_STRATEGIES_CSTRATEGYFACTORY_MQH
//+------------------------------------------------------------------+
