//+------------------------------------------------------------------+
//|                                           CRiskLimitGuard.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): maintain the P&L ledger across time        |
//|   windows and report whether any configured limit has been breached.    |
//|                                                                  |
//|   IT DETECTS, IT DOES NOT ACT. It returns an SRiskVerdict; closing      |
//|   positions is the trade engine's job. Keeping detection and reaction   |
//|   apart means the limits can be unit-tested without a broker.          |
//|                                                                  |
//|   TWO DESIGN DECISIONS WORTH STATING                                 |
//|                                                                  |
//|   1. LATCHING. Once a daily limit trips it STAYS tripped until the      |
//|      next day, even across a terminal restart, because the trip is      |
//|      persisted through IStateStore. A limit that forgets it fired       |
//|      after a reboot is not a limit.                                    |
//|                                                                  |
//|   2. FLOATING P&L COUNTS. An open loss is a real loss for the purpose   |
//|      of a daily cap. Excluding it lets an account bleed past its        |
//|      stated limit while technically complying, which is the failure     |
//|      mode this class exists to prevent.                                |
//|                                                                  |
//|   Drawdown is measured from a PERSISTED all-time equity peak. Using a   |
//|   session high instead would silently reset the measurement on every    |
//|   restart, turning a "20% max drawdown" promise into fiction.           |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_RISK_CRISKLIMITGUARD_MQH
#define SRP_INTELLIGENCE_RISK_CRISKLIMITGUARD_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Core/Interfaces/IStateStore.mqh"
#include "../../Utilities/CMathUtils.mqh"
#include "../../Utilities/CTimeUtils.mqh"
#include "../Types/IntelligenceStructs.mqh"

class CRiskLimitGuard
  {
private:
   ILogger          *m_logger;            // borrowed
   IStateStore      *m_state;             // borrowed, may be NULL

   SRiskLedger       m_ledger;
   //--- Configured limits. Zero disables a limit.
   double            m_max_daily_loss_percent;
   double            m_max_weekly_loss_percent;
   double            m_max_monthly_loss_percent;
   double            m_max_drawdown_percent;
   double            m_max_exposure_percent;   // total volume risk exposure
   double            m_max_exposure_lots;
   //--- Behaviour on breach.
   bool              m_flatten_on_daily;
   bool              m_flatten_on_drawdown;
   bool              m_emergency_enabled;
   double            m_emergency_equity_floor;
   //--- Latched breach state.
   bool              m_daily_tripped;
   bool              m_weekly_tripped;
   bool              m_monthly_tripped;
   bool              m_drawdown_tripped;
   bool              m_emergency_tripped;
   string            m_trip_detail;
   datetime          m_tripped_at;
   //--- Diagnostics.
   long              m_breach_count;

   //--- Persistence keys, namespaced to avoid collision.
   string            Key(const string suffix) const { return("risk."+suffix); }
   void              Persist(void);
   void              Restore(void);

public:
                     CRiskLimitGuard(ILogger *logger,IStateStore *state);
                    ~CRiskLimitGuard(void) { }

   //--- Configuration ------------------------------------------------
   void              SetDailyLossLimit(const double percent,const bool flatten);
   void              SetWeeklyLossLimit(const double percent);
   void              SetMonthlyLossLimit(const double percent);
   void              SetMaxDrawdown(const double percent,const bool flatten);
   void              SetMaxExposure(const double percent,const double lots);
   void              SetEmergencyShutdown(const bool enabled,
                                          const double equity_floor);

   //--- Lifecycle ----------------------------------------------------
   bool              Initialize(const double current_equity,const datetime now);
   void              Shutdown(void);
   bool              Validate(SValidationResult &result) const;

   //--- Window management. Called every pass; internally detects
   //--- boundary crossings and rearms the matching latches.
   void              UpdateWindows(const double current_equity,const datetime now);
   //--- Records the live account state before limits are evaluated.
   void              UpdateEquity(const double equity,const double floating);
   //--- Folds a closed trade into the ledger.
   void              RecordClosedTrade(const double net_profit,const datetime now);

   //--- THE evaluation. Returns false when entries must stop.
   bool              Evaluate(const double equity,
                              const double total_lots,
                              const double exposure_risk_percent,
                              SRiskVerdict &verdict);

   //--- Emergency shutdown is unconditional and does not auto-rearm.
   void              TriggerEmergency(const string reason,const datetime now);
   bool              ClearEmergency(const string acknowledgement);

   //--- Queries ------------------------------------------------------
   void              GetLedger(SRiskLedger &out) const { out=m_ledger; }
   bool              IsAnyTripped(void) const;
   bool              IsEmergencyTripped(void) const { return(m_emergency_tripped); }
   //--- HARNESS v2. The caller needs to know WHICH latch is set, because
   //--- the latches do not have the same lifetime: the daily one rearms at
   //--- the next day boundary inside UpdateWindows, the drawdown one and the
   //--- emergency one do not rearm at all. A caller that can only ask
   //--- "is anything tripped?" is forced to treat a routine losing day and
   //--- a terminal drawdown breach identically. These are pure reads; they
   //--- change no state and make no decision.
   bool              IsDailyTripped(void) const    { return(m_daily_tripped); }
   bool              IsWeeklyTripped(void) const   { return(m_weekly_tripped); }
   bool              IsMonthlyTripped(void) const  { return(m_monthly_tripped); }
   bool              IsDrawdownTripped(void) const { return(m_drawdown_tripped); }
   datetime          TrippedAt(void) const         { return(m_tripped_at); }
   datetime          DayStart(void) const          { return(m_ledger.day_start); }
   double            DailyLossPercent(void) const;
   double            WeeklyLossPercent(void) const;
   double            MonthlyLossPercent(void) const;
   double            DrawdownPercent(void) const;
   double            RemainingDailyBudget(void) const;
   string            TripDetail(void) const { return(m_trip_detail); }
   long              BreachCount(void) const { return(m_breach_count); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CRiskLimitGuard::CRiskLimitGuard(ILogger *logger,IStateStore *state)
  : m_logger(logger),
    m_state(state),
    m_max_daily_loss_percent(0.0),
    m_max_weekly_loss_percent(0.0),
    m_max_monthly_loss_percent(0.0),
    m_max_drawdown_percent(0.0),
    m_max_exposure_percent(0.0),
    m_max_exposure_lots(0.0),
    m_flatten_on_daily(false),
    m_flatten_on_drawdown(false),
    m_emergency_enabled(false),
    m_emergency_equity_floor(0.0),
    m_daily_tripped(false),
    m_weekly_tripped(false),
    m_monthly_tripped(false),
    m_drawdown_tripped(false),
    m_emergency_tripped(false),
    m_trip_detail(""),
    m_tripped_at(0),
    m_breach_count(0)
  {
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::SetDailyLossLimit(const double percent,const bool flatten)
  {
   m_max_daily_loss_percent=(percent<0.0 ? 0.0 : percent);
   m_flatten_on_daily=flatten;
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::SetWeeklyLossLimit(const double percent)
  {
   m_max_weekly_loss_percent=(percent<0.0 ? 0.0 : percent);
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::SetMonthlyLossLimit(const double percent)
  {
   m_max_monthly_loss_percent=(percent<0.0 ? 0.0 : percent);
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::SetMaxDrawdown(const double percent,const bool flatten)
  {
   m_max_drawdown_percent=(percent<0.0 ? 0.0 : percent);
   m_flatten_on_drawdown=flatten;
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::SetMaxExposure(const double percent,const double lots)
  {
   m_max_exposure_percent=(percent<0.0 ? 0.0 : percent);
   m_max_exposure_lots=(lots<0.0 ? 0.0 : lots);
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::SetEmergencyShutdown(const bool enabled,
                                           const double equity_floor)
  {
   m_emergency_enabled=enabled;
   m_emergency_equity_floor=(equity_floor<0.0 ? 0.0 : equity_floor);
  }
//+------------------------------------------------------------------+
bool CRiskLimitGuard::Initialize(const double current_equity,const datetime now)
  {
   m_ledger.Reset();
   m_ledger.day_start   = CTimeUtils::StartOfDay(now);
   //--- Explicit cast: datetime arithmetic promotes to long, and the
   //--- implicit narrowing back is a compiler warning.
   m_ledger.week_start  = (datetime)((long)CTimeUtils::StartOfDay(now)-
                                     (long)CTimeUtils::DayOfWeek(now)*86400);
   //--- Month start: first day of the current month.
   MqlDateTime parts;
   TimeToStruct(now,parts);
   parts.day=1; parts.hour=0; parts.min=0; parts.sec=0;
   m_ledger.month_start=StructToTime(parts);

   m_ledger.day_open_equity   = current_equity;
   m_ledger.week_open_equity  = current_equity;
   m_ledger.month_open_equity = current_equity;
   m_ledger.peak_equity       = current_equity;
   m_ledger.trough_equity     = current_equity;

   //--- Restore persisted state AFTER seeding defaults, so a missing
   //--- store degrades to a clean start rather than to zeros.
   Restore();
   return(true);
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::Shutdown(void)
  {
   Persist();
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::Persist(void)
  {
   if(m_state==NULL)
      return;
   m_state.PutDatetime(Key("day_start"),m_ledger.day_start);
   m_state.PutDatetime(Key("week_start"),m_ledger.week_start);
   m_state.PutDatetime(Key("month_start"),m_ledger.month_start);
   m_state.PutDouble(Key("day_open"),m_ledger.day_open_equity);
   m_state.PutDouble(Key("week_open"),m_ledger.week_open_equity);
   m_state.PutDouble(Key("month_open"),m_ledger.month_open_equity);
   m_state.PutDouble(Key("day_realized"),m_ledger.day_realized);
   m_state.PutDouble(Key("week_realized"),m_ledger.week_realized);
   m_state.PutDouble(Key("month_realized"),m_ledger.month_realized);
   //--- The peak is the critical value: losing it resets drawdown.
   m_state.PutDouble(Key("peak_equity"),m_ledger.peak_equity);
   m_state.PutInt(Key("consecutive_losses"),m_ledger.consecutive_losses);
   m_state.PutBool(Key("daily_tripped"),m_daily_tripped);
   m_state.PutBool(Key("drawdown_tripped"),m_drawdown_tripped);
   m_state.PutBool(Key("emergency_tripped"),m_emergency_tripped);
   m_state.PutString(Key("trip_detail"),m_trip_detail);
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::Restore(void)
  {
   if(m_state==NULL)
      return;

   const datetime stored_day=m_state.GetDatetime(Key("day_start"),0);
   //--- Only restore the day's figures when it is still the SAME day.
   //--- Restoring yesterday's ledger would either grant a fresh budget
   //--- or wrongly carry a spent one.
   if(stored_day==m_ledger.day_start)
     {
      m_ledger.day_open_equity = m_state.GetDouble(Key("day_open"),
                                                   m_ledger.day_open_equity);
      m_ledger.day_realized    = m_state.GetDouble(Key("day_realized"),0.0);
      m_daily_tripped          = m_state.GetBool(Key("daily_tripped"),false);
     }

   const datetime stored_week=m_state.GetDatetime(Key("week_start"),0);
   if(stored_week==m_ledger.week_start)
     {
      m_ledger.week_open_equity = m_state.GetDouble(Key("week_open"),
                                                    m_ledger.week_open_equity);
      m_ledger.week_realized    = m_state.GetDouble(Key("week_realized"),0.0);
     }

   const datetime stored_month=m_state.GetDatetime(Key("month_start"),0);
   if(stored_month==m_ledger.month_start)
     {
      m_ledger.month_open_equity = m_state.GetDouble(Key("month_open"),
                                                     m_ledger.month_open_equity);
      m_ledger.month_realized    = m_state.GetDouble(Key("month_realized"),0.0);
     }

   //--- The peak is restored unconditionally: it is an all-time value and
   //--- must survive every boundary and every restart.
   const double stored_peak=m_state.GetDouble(Key("peak_equity"),0.0);
   if(stored_peak>m_ledger.peak_equity)
      m_ledger.peak_equity=stored_peak;

   m_ledger.consecutive_losses=(int)m_state.GetInt(Key("consecutive_losses"),0);
   m_drawdown_tripped =m_state.GetBool(Key("drawdown_tripped"),false);
   m_emergency_tripped=m_state.GetBool(Key("emergency_tripped"),false);
   m_trip_detail      =m_state.GetString(Key("trip_detail"),"");

   if(m_emergency_tripped && m_logger!=NULL)
      m_logger.Warn("CRiskLimitGuard",
                    "emergency shutdown restored from persisted state: "+m_trip_detail);
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::UpdateWindows(const double current_equity,const datetime now)
  {
   const datetime today=CTimeUtils::StartOfDay(now);

   //--- DAY BOUNDARY: reset the day's figures and rearm the daily latch.
   if(today!=m_ledger.day_start)
     {
      m_ledger.day_start       = today;
      m_ledger.day_open_equity = current_equity;
      m_ledger.day_realized    = 0.0;
      m_ledger.day_trades      = 0;
      if(m_daily_tripped && m_logger!=NULL)
         m_logger.Info("CRiskLimitGuard","new day: daily loss limit rearmed");
      m_daily_tripped=false;
     }

   //--- WEEK BOUNDARY.
   const datetime week_start=
      (datetime)((long)today-(long)CTimeUtils::DayOfWeek(now)*86400);
   if(week_start!=m_ledger.week_start)
     {
      m_ledger.week_start       = week_start;
      m_ledger.week_open_equity = current_equity;
      m_ledger.week_realized    = 0.0;
      m_ledger.week_trades      = 0;
      m_weekly_tripped=false;
     }

   //--- MONTH BOUNDARY.
   MqlDateTime parts;
   TimeToStruct(now,parts);
   parts.day=1; parts.hour=0; parts.min=0; parts.sec=0;
   const datetime month_start=StructToTime(parts);
   if(month_start!=m_ledger.month_start)
     {
      m_ledger.month_start       = month_start;
      m_ledger.month_open_equity = current_equity;
      m_ledger.month_realized    = 0.0;
      m_ledger.month_trades      = 0;
      m_monthly_tripped=false;
     }
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::UpdateEquity(const double equity,const double floating)
  {
   m_ledger.floating=floating;

   //--- HIGH-WATER MARK. Only ever moves up, and is persisted.
   if(equity>m_ledger.peak_equity)
      m_ledger.peak_equity=equity;
   if(m_ledger.trough_equity<=0.0 || equity<m_ledger.trough_equity)
      m_ledger.trough_equity=equity;
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::RecordClosedTrade(const double net_profit,const datetime now)
  {
   m_ledger.day_realized   += net_profit;
   m_ledger.week_realized  += net_profit;
   m_ledger.month_realized += net_profit;
   m_ledger.day_trades++;
   m_ledger.week_trades++;
   m_ledger.month_trades++;

   if(net_profit<0.0)
     {
      m_ledger.consecutive_losses++;
      m_ledger.consecutive_wins=0;
     }
   else if(net_profit>0.0)
     {
      m_ledger.consecutive_wins++;
      m_ledger.consecutive_losses=0;
     }

   Persist();
  }
//+------------------------------------------------------------------+
double CRiskLimitGuard::DailyLossPercent(void) const
  {
   if(m_ledger.day_open_equity<=0.0)
      return(0.0);
   const double total=m_ledger.DayTotal();
   if(total>=0.0)
      return(0.0);                        // in profit, no loss to report
   return(MathAbs(total)/m_ledger.day_open_equity*100.0);
  }
//+------------------------------------------------------------------+
double CRiskLimitGuard::WeeklyLossPercent(void) const
  {
   if(m_ledger.week_open_equity<=0.0)
      return(0.0);
   const double total=m_ledger.WeekTotal();
   if(total>=0.0)
      return(0.0);
   return(MathAbs(total)/m_ledger.week_open_equity*100.0);
  }
//+------------------------------------------------------------------+
double CRiskLimitGuard::MonthlyLossPercent(void) const
  {
   if(m_ledger.month_open_equity<=0.0)
      return(0.0);
   const double total=m_ledger.MonthTotal();
   if(total>=0.0)
      return(0.0);
   return(MathAbs(total)/m_ledger.month_open_equity*100.0);
  }
//+------------------------------------------------------------------+
double CRiskLimitGuard::DrawdownPercent(void) const
  {
   if(m_ledger.peak_equity<=0.0)
      return(0.0);
   //--- Current equity is peak plus the running total; using the ledger
   //--- keeps this consistent with the loss figures above.
   const double current=m_ledger.peak_equity+m_ledger.floating;
   const double reference=m_ledger.peak_equity;
   if(current>=reference)
      return(0.0);
   return((reference-current)/reference*100.0);
  }
//+------------------------------------------------------------------+
double CRiskLimitGuard::RemainingDailyBudget(void) const
  {
   if(m_max_daily_loss_percent<=0.0 || m_ledger.day_open_equity<=0.0)
      return(0.0);
   const double allowed=m_ledger.day_open_equity*m_max_daily_loss_percent/100.0;
   const double used=MathAbs(MathMin(m_ledger.DayTotal(),0.0));
   const double remaining=allowed-used;
   return(remaining>0.0 ? remaining : 0.0);
  }
//+------------------------------------------------------------------+
bool CRiskLimitGuard::Evaluate(const double equity,
                               const double total_lots,
                               const double exposure_risk_percent,
                               SRiskVerdict &verdict)
  {
   verdict.Reset();

   //--- EMERGENCY first: it outranks everything and does not auto-rearm.
   if(m_emergency_tripped)
     {
      verdict.Deny(SRP_BREACH_EMERGENCY,
                   "emergency shutdown active: "+m_trip_detail,
                   equity,m_emergency_equity_floor,true);
      return(false);
     }
   if(m_emergency_enabled && m_emergency_equity_floor>0.0 &&
      equity<m_emergency_equity_floor)
     {
      TriggerEmergency(StringFormat("equity %.2f below floor %.2f",
                                    equity,m_emergency_equity_floor),
                       TimeCurrent());
      verdict.Deny(SRP_BREACH_EMERGENCY,m_trip_detail,
                   equity,m_emergency_equity_floor,true);
      return(false);
     }

   //--- DRAWDOWN next: the most severe non-emergency limit.
   if(m_max_drawdown_percent>0.0)
     {
      const double drawdown=DrawdownPercent();
      if(m_drawdown_tripped || drawdown>=m_max_drawdown_percent)
        {
         if(!m_drawdown_tripped)
           {
            m_drawdown_tripped=true;
            m_trip_detail=StringFormat("drawdown %.2f%% reached limit %.2f%%",
                                       drawdown,m_max_drawdown_percent);
            m_tripped_at=TimeCurrent();
            m_breach_count++;
            if(m_logger!=NULL)
               m_logger.Error("CRiskLimitGuard",m_trip_detail);
            Persist();
           }
         verdict.Deny(SRP_BREACH_MAX_DRAWDOWN,m_trip_detail,
                      drawdown,m_max_drawdown_percent,m_flatten_on_drawdown);
         return(false);
        }
     }

   //--- DAILY.
   if(m_max_daily_loss_percent>0.0)
     {
      const double loss=DailyLossPercent();
      if(m_daily_tripped || loss>=m_max_daily_loss_percent)
        {
         if(!m_daily_tripped)
           {
            m_daily_tripped=true;
            m_trip_detail=StringFormat("daily loss %.2f%% reached limit %.2f%%",
                                       loss,m_max_daily_loss_percent);
            m_tripped_at=TimeCurrent();
            m_breach_count++;
            if(m_logger!=NULL)
               m_logger.Warn("CRiskLimitGuard",m_trip_detail);
            Persist();
           }
         verdict.Deny(SRP_BREACH_DAILY_LOSS,m_trip_detail,
                      loss,m_max_daily_loss_percent,m_flatten_on_daily);
         return(false);
        }
     }

   //--- WEEKLY.
   if(m_max_weekly_loss_percent>0.0)
     {
      const double loss=WeeklyLossPercent();
      if(m_weekly_tripped || loss>=m_max_weekly_loss_percent)
        {
         if(!m_weekly_tripped)
           {
            m_weekly_tripped=true;
            m_trip_detail=StringFormat("weekly loss %.2f%% reached limit %.2f%%",
                                       loss,m_max_weekly_loss_percent);
            m_breach_count++;
            if(m_logger!=NULL)
               m_logger.Warn("CRiskLimitGuard",m_trip_detail);
           }
         verdict.Deny(SRP_BREACH_WEEKLY_LOSS,m_trip_detail,
                      loss,m_max_weekly_loss_percent,false);
         return(false);
        }
     }

   //--- MONTHLY.
   if(m_max_monthly_loss_percent>0.0)
     {
      const double loss=MonthlyLossPercent();
      if(m_monthly_tripped || loss>=m_max_monthly_loss_percent)
        {
         if(!m_monthly_tripped)
           {
            m_monthly_tripped=true;
            m_trip_detail=StringFormat("monthly loss %.2f%% reached limit %.2f%%",
                                       loss,m_max_monthly_loss_percent);
            m_breach_count++;
            if(m_logger!=NULL)
               m_logger.Warn("CRiskLimitGuard",m_trip_detail);
           }
         verdict.Deny(SRP_BREACH_MONTHLY_LOSS,m_trip_detail,
                      loss,m_max_monthly_loss_percent,false);
         return(false);
        }
     }

   //--- EXPOSURE. Non-latching: exposure falls as positions close, so
   //--- this is re-evaluated fresh every pass rather than latched.
   if(m_max_exposure_lots>0.0 && total_lots>=m_max_exposure_lots)
     {
      verdict.Deny(SRP_BREACH_EXPOSURE,
                   StringFormat("open volume %.2f reached limit %.2f lots",
                                total_lots,m_max_exposure_lots),
                   total_lots,m_max_exposure_lots,false);
      return(false);
     }
   if(m_max_exposure_percent>0.0 &&
      exposure_risk_percent>=m_max_exposure_percent)
     {
      verdict.Deny(SRP_BREACH_EXPOSURE,
                   StringFormat("aggregate risk %.2f%% reached limit %.2f%%",
                                exposure_risk_percent,m_max_exposure_percent),
                   exposure_risk_percent,m_max_exposure_percent,false);
      return(false);
     }

   return(true);
  }
//+------------------------------------------------------------------+
void CRiskLimitGuard::TriggerEmergency(const string reason,const datetime now)
  {
   if(m_emergency_tripped)
      return;
   m_emergency_tripped=true;
   m_trip_detail="EMERGENCY: "+reason;
   m_tripped_at=now;
   m_breach_count++;
   if(m_logger!=NULL)
      m_logger.Fatal("CRiskLimitGuard",m_trip_detail);
   Persist();
  }
//+------------------------------------------------------------------+
bool CRiskLimitGuard::ClearEmergency(const string acknowledgement)
  {
   //--- Deliberately requires a non-empty human acknowledgement. No
   //--- automation path calls this: an emergency stop that clears itself
   //--- is not a stop.
   if(StringLen(acknowledgement)==0)
      return(false);
   m_emergency_tripped=false;
   m_trip_detail="";
   m_tripped_at=0;
   if(m_logger!=NULL)
      m_logger.Warn("CRiskLimitGuard",
                    "emergency cleared by operator: "+acknowledgement);
   Persist();
   return(true);
  }
//+------------------------------------------------------------------+
bool CRiskLimitGuard::IsAnyTripped(void) const
  {
   return(m_daily_tripped || m_weekly_tripped || m_monthly_tripped ||
          m_drawdown_tripped || m_emergency_tripped);
  }
//+------------------------------------------------------------------+
bool CRiskLimitGuard::Validate(SValidationResult &result) const
  {
   //--- Cross-limit coherence: a daily cap wider than the weekly cap can
   //--- never bind, which is almost certainly a configuration mistake.
   if(m_max_daily_loss_percent>0.0 && m_max_weekly_loss_percent>0.0 &&
      m_max_daily_loss_percent>m_max_weekly_loss_percent)
      result.AddWarning("CRiskLimitGuard: daily loss limit exceeds weekly limit");
   if(m_max_weekly_loss_percent>0.0 && m_max_monthly_loss_percent>0.0 &&
      m_max_weekly_loss_percent>m_max_monthly_loss_percent)
      result.AddWarning("CRiskLimitGuard: weekly loss limit exceeds monthly limit");
   if(m_max_drawdown_percent>0.0 && m_max_drawdown_percent>50.0)
      result.AddWarning("CRiskLimitGuard: drawdown limit above 50% offers little protection");
   if(m_state==NULL)
      result.AddWarning("CRiskLimitGuard: no state store; limits will reset on restart");
   if(m_max_daily_loss_percent<=0.0 && m_max_drawdown_percent<=0.0)
      result.AddWarning("CRiskLimitGuard: no daily or drawdown limit configured");
   return(true);
  }
//+------------------------------------------------------------------+
string CRiskLimitGuard::Describe(void) const
  {
   return(StringFormat("risk: day %.2f%%/%.2f%% week %.2f%%/%.2f%% "
                       "month %.2f%%/%.2f%% dd %.2f%%/%.2f%% | "
                       "tripped=%s breaches=%I64d losses=%d",
                       DailyLossPercent(),m_max_daily_loss_percent,
                       WeeklyLossPercent(),m_max_weekly_loss_percent,
                       MonthlyLossPercent(),m_max_monthly_loss_percent,
                       DrawdownPercent(),m_max_drawdown_percent,
                       (IsAnyTripped() ? "YES" : "no"),
                       m_breach_count,m_ledger.consecutive_losses));
  }

#endif // SRP_INTELLIGENCE_RISK_CRISKLIMITGUARD_MQH
//+------------------------------------------------------------------+
