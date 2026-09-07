//+------------------------------------------------------------------+
//|                                        P3SessionNewsCheck.mq5 |
//|   Phase 3 harness: Session Manager + News Engine.                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"

#include <ScalpRobotPro/Decision/Session/CSessionManager.mqh>
#include <ScalpRobotPro/Decision/News/CNewsEngine.mqh>
#include <ScalpRobotPro/Logger/CLogger.mqh>
#include <ScalpRobotPro/Logger/CTerminalLogSink.mqh>

void OnStart(void)
  {
   CLogger *logger=new CLogger(SRP_LOG_DEBUG);
   logger.AddSink(new CTerminalLogSink(SRP_LOG_DEBUG));
   logger.Open();

   const datetime now=TimeCurrent();
   SValidationResult validation;

   //=== SESSION MANAGER =============================================
   CSessionManager *sessions=new CSessionManager(_Symbol,logger);
   sessions.SetSydneyWindow(21*60,6*60,true);
   sessions.SetTokyoWindow(0,9*60,true);
   sessions.SetLondonWindow(8*60,16*60+30,true);
   sessions.SetNewYorkWindow(13*60,21*60,true);
   sessions.SetKillZones(false);
   sessions.SetAsianKillZone(23*60,2*60);
   sessions.SetLondonOpenKillZone(7*60,10*60);
   sessions.SetNewYorkOpenKillZone(12*60+30,15*60);
   sessions.SetLondonCloseKillZone(15*60,16*60);
   sessions.SetWeekendFilter(true,60,0);
   sessions.SetSessionEdgeSkip(5,5);
   sessions.SetHolidayFilter(true,true);
   sessions.LoadHolidays("2026.12.25;2026.01.01;bogus-date");
   sessions.SetDstEnabled(true);
   sessions.Initialize();
   sessions.Evaluate(now,true);
   sessions.Validate(validation);
   Print(sessions.Describe());

   SSessionState session_state;
   sessions.GetState(session_state);
   Print("permitted=",sessions.IsTradingPermitted(),
         " session=",CSessionManager::SessionToString(sessions.ActiveSession()),
         " kz=",CSessionManager::KillZoneToString(sessions.KillZone()),
         " inKz=",sessions.InKillZone(),
         " liquidity=",DoubleToString(sessions.LiquidityScore(),2));
   Print("offset=",sessions.BrokerOffsetMinutes(),
         " dst=",sessions.IsDstActive(),
         " holidays=",sessions.HolidayCount(),
         " block=",CSessionManager::BlockToString(session_state.block_reason),
         " detail=",session_state.block_detail);
   Print("intoSession=",session_state.minutes_into_session,
         " untilEnd=",session_state.minutes_until_session_end,
         " overlap=",CSessionManager::OverlapToString(session_state.overlap));
   Print("evaluations=",sessions.EvaluationCount()," blocks=",sessions.BlockCount());

   //--- Manual offset path.
   sessions.SetManualBrokerOffset(120);
   sessions.Evaluate(now,true);
   Print("manual offset applied: ",sessions.BrokerOffsetMinutes());

   //=== NEWS ENGINE =================================================
   CNewsEngine *news=new CNewsEngine(_Symbol,logger);
   news.SetEnabled(true);
   news.SetSource(true,true,"srp_news.csv");
   news.SetMinimumSeverity(SRP_NEWS_SEV_MEDIUM);
   news.SetCriticalWindow(60,60);
   news.SetHighWindow(30,30);
   news.SetMediumWindow(15,15);
   news.SetFailSafeBlock(true);
   news.SetFlattenOnCritical(true);
   news.SetRefreshInterval(900);
   news.Initialize();
   news.Refresh(now,true);
   news.Evaluate(now);
   news.Validate(validation);
   Print(news.Describe());

   SNewsState news_state;
   news.GetState(news_state);
   Print("newsPermitted=",news.IsTradingPermitted(),
         " phase=",CNewsEngine::PhaseToString(news.Phase()),
         " flatten=",news.IsFlattenRecommended(),
         " source=",news.SourceAvailable(),
         " events=",news.EventCount());
   Print("untilNext=",news.SecondsUntilNext(),
         "s untilResume=",news.SecondsUntilResume(),"s");
   Print("countdown: ",news.CountdownText());
   Print("detail: ",news_state.detail);
   Print("malformed=",news.MalformedLineCount()," pauses=",news.PauseCount());

   SNewsItem item;
   if(news.GetEvent(0,item))
      Print("event0: ",item.title," [",
            CNewsEngine::KindToString(item.kind),"/",
            CNewsEngine::SeverityToString(item.severity),"] ",
            item.currency," in ",item.minutes_until,"m");

   //--- Currency override path.
   news.SetCurrencyFilter("USD,XAU,EUR");
   news.Refresh(now,true);
   news.Evaluate(now);

   Print("validation errors=",validation.error_count,
         " warnings=",validation.warning_count);
   Print("=== P3 SESSION + NEWS CHECK COMPLETE ===");

   news.Shutdown();     delete news;
   sessions.Shutdown(); delete sessions;
   logger.Close();
   delete logger;
  }
//+------------------------------------------------------------------+
