//+------------------------------------------------------------------+
//|                                             CFilterFactory.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Filters : builds the enabled filter set from configuration.            |
//|                                                                  |
//|   RESPONSIBILITY (one only): construct IFilter instances and assign      |
//|   their priorities. Priorities are set HERE rather than hard-coded in     |
//|   each filter, so the evaluation order is visible in one place and can   |
//|   be tuned without editing filter logic.                                |
//+------------------------------------------------------------------+
#ifndef SRP_FILTERS_CFILTERFACTORY_MQH
#define SRP_FILTERS_CFILTERFACTORY_MQH

#include "CFilterChain.mqh"
#include "../Core/Interfaces/IConfigProvider.mqh"
#include "../Core/Interfaces/IClock.mqh"

class CIndicatorManager;
class CSessionCalendar;
class CPositionRepository;
class CNewsBlackoutEvaluator;

class CFilterFactory
  {
private:
   IConfigProvider        *m_config;       // borrowed
   ILogger                *m_logger;       // borrowed
   IClock                 *m_clock;        // borrowed
   CIndicatorManager      *m_indicators;   // borrowed
   CSessionCalendar       *m_calendar;     // borrowed
   CPositionRepository    *m_positions;    // borrowed
   CNewsBlackoutEvaluator *m_news;         // borrowed

   //--- Evaluation order. Cheapest and most-rejecting first, so the
   //--- chain short-circuits as early as possible on a busy M1 stream.
   static const int PRIORITY_SPREAD;
   static const int PRIORITY_SCHEDULE;
   static const int PRIORITY_SESSION;
   static const int PRIORITY_HOLIDAY;
   static const int PRIORITY_FREQUENCY;
   static const int PRIORITY_NEWS;
   static const int PRIORITY_VOLATILITY;
   static const int PRIORITY_TREND;

   IFilter          *CreateSpreadFilter(void);
   IFilter          *CreateSessionFilter(void);
   IFilter          *CreateScheduleFilter(void);
   IFilter          *CreateHolidayFilter(void);
   IFilter          *CreateNewsFilter(void);
   IFilter          *CreateVolatilityFilter(void);
   IFilter          *CreateTrendFilter(void);
   IFilter          *CreateFrequencyFilter(void);

public:
                     CFilterFactory(IConfigProvider *config,
                                    ILogger *logger,
                                    IClock *clock,
                                    CIndicatorManager *indicators,
                                    CSessionCalendar *calendar,
                                    CPositionRepository *positions,
                                    CNewsBlackoutEvaluator *news);
                    ~CFilterFactory(void) { }

   //--- Adds every enabled filter to the chain.
   bool              BuildAll(CFilterChain *chain);
  };

//--- Priority definitions.
const int CFilterFactory::PRIORITY_SPREAD     = 10;
const int CFilterFactory::PRIORITY_SCHEDULE   = 20;
const int CFilterFactory::PRIORITY_SESSION    = 30;
const int CFilterFactory::PRIORITY_HOLIDAY    = 40;
const int CFilterFactory::PRIORITY_FREQUENCY  = 50;
const int CFilterFactory::PRIORITY_NEWS       = 60;
const int CFilterFactory::PRIORITY_VOLATILITY = 70;
const int CFilterFactory::PRIORITY_TREND      = 80;

#endif // SRP_FILTERS_CFILTERFACTORY_MQH
//+------------------------------------------------------------------+
