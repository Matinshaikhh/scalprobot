//+------------------------------------------------------------------+
//|                                       COptimizationGuard.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Optimization : disables expensive subsystems during optimisation.         |
//|                                                                  |
//|   RESPONSIBILITY (one only): detect the execution environment and report    |
//|   which subsystems should be suppressed.                                  |
//|                                                                  |
//|   WHY IT MATTERS COMMERCIALLY                                            |
//|   A genetic optimisation runs thousands of passes. Logging to file,         |
//|   drawing chart objects, writing the journal and sending notifications      |
//|   are all pure waste there, and together they can dominate total runtime.   |
//|   Suppressing them can shorten an optimisation from hours to minutes.      |
//|                                                                  |
//|   It is a POLICY object: it answers questions and changes nothing itself.   |
//|   The bootstrapper consults it while composing the graph, so suppressed     |
//|   subsystems are never even constructed.                                  |
//+------------------------------------------------------------------+
#ifndef SRP_OPTIMIZATION_COPTIMIZATIONGUARD_MQH
#define SRP_OPTIMIZATION_COPTIMIZATIONGUARD_MQH

#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Types/Enums.mqh"

class COptimizationGuard
  {
private:
   IClock           *m_clock;              // borrowed
   bool              m_is_tester;
   bool              m_is_optimization;
   bool              m_is_visual;
   bool              m_resolved;

   void              Resolve(void);

public:
                     COptimizationGuard(IClock *clock);
                    ~COptimizationGuard(void) { }

   //--- Environment queries -----------------------------------------
   bool              IsLive(void);
   bool              IsTester(void);
   bool              IsOptimization(void);
   bool              IsVisualTest(void);

   //--- Subsystem policy. Each answers "should this be built at all?"
   bool              ShouldEnableDashboard(void);
   bool              ShouldEnableFileLogging(void);
   bool              ShouldEnableJournal(void);
   bool              ShouldEnableNotifications(void);
   bool              ShouldEnableStatePersistence(void);
   bool              ShouldEnableNewsProvider(void);

   //--- Log verbosity is forced to a minimum during optimisation, since
   //--- even terminal printing costs measurable time across many passes.
   ENUM_SRP_LOG_LEVEL RecommendedLogLevel(const ENUM_SRP_LOG_LEVEL configured);

   string            DescribeEnvironment(void);
  };

//+------------------------------------------------------------------+
COptimizationGuard::COptimizationGuard(IClock *clock)
  : m_clock(clock),
    m_is_tester(false),
    m_is_optimization(false),
    m_is_visual(false),
    m_resolved(false)
  {
  }
//+------------------------------------------------------------------+
void COptimizationGuard::Resolve(void)
  {
   if(m_resolved || m_clock==NULL)
      return;
   m_is_tester       = m_clock.IsTesting();
   m_is_optimization = m_clock.IsOptimization();
   m_is_visual       = m_clock.IsVisualMode();
   m_resolved        = true;
  }
//+------------------------------------------------------------------+
bool COptimizationGuard::IsTester(void)
  {
   Resolve();
   return(m_is_tester);
  }
//+------------------------------------------------------------------+
bool COptimizationGuard::IsOptimization(void)
  {
   Resolve();
   return(m_is_optimization);
  }
//+------------------------------------------------------------------+
bool COptimizationGuard::IsVisualTest(void)
  {
   Resolve();
   return(m_is_visual);
  }
//+------------------------------------------------------------------+
bool COptimizationGuard::IsLive(void)
  {
   Resolve();
   return(!m_is_tester);
  }
//+------------------------------------------------------------------+
bool COptimizationGuard::ShouldEnableDashboard(void)
  {
   Resolve();
   //--- Visible only live or in a visual test; never in optimisation.
   if(m_is_optimization)
      return(false);
   return(!m_is_tester || m_is_visual);
  }
//+------------------------------------------------------------------+
bool COptimizationGuard::ShouldEnableFileLogging(void)
  {
   Resolve();
   return(!m_is_optimization);
  }
//+------------------------------------------------------------------+
bool COptimizationGuard::ShouldEnableJournal(void)
  {
   Resolve();
   return(!m_is_optimization);
  }
//+------------------------------------------------------------------+
bool COptimizationGuard::ShouldEnableNotifications(void)
  {
   Resolve();
   //--- Never notify from a test: it would spam a real phone with
   //--- historical events.
   return(!m_is_tester);
  }
//+------------------------------------------------------------------+
bool COptimizationGuard::ShouldEnableStatePersistence(void)
  {
   Resolve();
   //--- Each tester pass must start clean, otherwise state from pass N
   //--- silently biases pass N+1 and the optimisation result is invalid.
   return(!m_is_tester);
  }
//+------------------------------------------------------------------+
ENUM_SRP_LOG_LEVEL COptimizationGuard::RecommendedLogLevel(
                                       const ENUM_SRP_LOG_LEVEL configured)
  {
   Resolve();
   if(m_is_optimization)
      return(SRP_LOG_OFF);
   if(m_is_tester && configured<SRP_LOG_INFO)
      return(SRP_LOG_INFO);
   return(configured);
  }
//+------------------------------------------------------------------+
bool COptimizationGuard::ShouldEnableNewsProvider(void)
  {
   Resolve();
   //--- A calendar provider is useless in the tester and actively
   //--- harmful: MQL5's economic calendar returns TODAY's events, not
   //--- the events of the historical bar being simulated. Consulting it
   //--- during a backtest blocks trades using future information and
   //--- produces a result that cannot be reproduced live.
   return(!m_is_tester);
  }
//+------------------------------------------------------------------+
string COptimizationGuard::DescribeEnvironment(void)
  {
   Resolve();
   //--- Written to the log header at startup so a support ticket shows
   //--- which environment produced the behaviour being reported.
   string mode="LIVE";
   if(m_is_optimization)
      mode="OPTIMIZATION";
   else
      if(m_is_tester)
         mode=(m_is_visual ? "VISUAL_TEST" : "BACKTEST");

   string text="Environment: "+mode;
   text+="\n  suppressed: ";
   string off="";
   if(!ShouldEnableDashboard())         off+="dashboard ";
   if(!ShouldEnableFileLogging())       off+="file-logging ";
   if(!ShouldEnableJournal())           off+="journal ";
   if(!ShouldEnableNotifications())     off+="notifications ";
   if(!ShouldEnableStatePersistence())  off+="state-persistence ";
   if(!ShouldEnableNewsProvider())      off+="news-provider ";
   text+=(off=="" ? "nothing (full live configuration)" : off);
   return(text);
  }

#endif // SRP_OPTIMIZATION_COPTIMIZATIONGUARD_MQH
//+------------------------------------------------------------------+
