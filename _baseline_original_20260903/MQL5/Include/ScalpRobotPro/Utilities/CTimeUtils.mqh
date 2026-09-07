//+------------------------------------------------------------------+
//|                                                  CTimeUtils.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Utilities : stateless calendar arithmetic.                        |
//|                                                                  |
//|   Pure functions only - they take a datetime and return a value.    |
//|   They never call TimeCurrent(), which is IClock's job. That        |
//|   separation is what lets session and schedule logic be tested      |
//|   against arbitrary historical moments.                            |
//+------------------------------------------------------------------+
#ifndef SRP_UTILITIES_CTIMEUTILS_MQH
#define SRP_UTILITIES_CTIMEUTILS_MQH

class CTimeUtils
  {
public:
   //--- Day boundaries ----------------------------------------------
   static datetime   StartOfDay(const datetime moment);
   static datetime   EndOfDay(const datetime moment);
   static datetime   StartOfWeek(const datetime moment);
   static datetime   StartOfMonth(const datetime moment);
   static bool       IsSameDay(const datetime a,const datetime b);
   static bool       IsSameWeek(const datetime a,const datetime b);

   //--- Decomposition -----------------------------------------------
   static int        DayOfWeek(const datetime moment);
   static int        HourOf(const datetime moment);
   static int        MinuteOf(const datetime moment);
   static int        SecondsSinceMidnight(const datetime moment);
   static int        MinutesSinceMidnight(const datetime moment);

   //--- Intraday window test. Correctly handles a window that wraps
   //--- past midnight (e.g. 22:00-02:00), which naive comparisons get
   //--- wrong and which matters for the Sydney session.
   static bool       IsWithinDailyWindow(const datetime moment,
                                         const int start_minutes,
                                         const int end_minutes);

   //--- Conversion helpers ------------------------------------------
   static int        HoursMinutesToMinutes(const int hour,const int minute);
   static string     MinutesToHhMm(const int minutes);
   static bool       ParseHhMm(const string text,int &out_minutes);

   //--- Duration formatting for the dashboard and journal.
   static string     FormatDuration(const int seconds);
   static bool       IsWeekend(const datetime moment);
  };

//+------------------------------------------------------------------+
datetime CTimeUtils::StartOfDay(const datetime moment)
  {
   MqlDateTime parts;
   TimeToStruct(moment,parts);
   parts.hour=0;
   parts.min=0;
   parts.sec=0;
   return(StructToTime(parts));
  }
//+------------------------------------------------------------------+
datetime CTimeUtils::EndOfDay(const datetime moment)
  {
   return(StartOfDay(moment)+86399);
  }
//+------------------------------------------------------------------+
bool CTimeUtils::IsSameDay(const datetime a,const datetime b)
  {
   return(StartOfDay(a)==StartOfDay(b));
  }
//+------------------------------------------------------------------+
int CTimeUtils::DayOfWeek(const datetime moment)
  {
   MqlDateTime parts;
   TimeToStruct(moment,parts);
   return(parts.day_of_week);
  }
//+------------------------------------------------------------------+
int CTimeUtils::HourOf(const datetime moment)
  {
   MqlDateTime parts;
   TimeToStruct(moment,parts);
   return(parts.hour);
  }
//+------------------------------------------------------------------+
int CTimeUtils::MinuteOf(const datetime moment)
  {
   MqlDateTime parts;
   TimeToStruct(moment,parts);
   return(parts.min);
  }
//+------------------------------------------------------------------+
int CTimeUtils::SecondsSinceMidnight(const datetime moment)
  {
   MqlDateTime parts;
   TimeToStruct(moment,parts);
   return(parts.hour*3600+parts.min*60+parts.sec);
  }
//+------------------------------------------------------------------+
int CTimeUtils::MinutesSinceMidnight(const datetime moment)
  {
   MqlDateTime parts;
   TimeToStruct(moment,parts);
   return(parts.hour*60+parts.min);
  }
//+------------------------------------------------------------------+
bool CTimeUtils::IsWithinDailyWindow(const datetime moment,
                                     const int start_minutes,
                                     const int end_minutes)
  {
   const int now=MinutesSinceMidnight(moment);
   //--- Window does not wrap midnight.
   if(start_minutes<=end_minutes)
      return(now>=start_minutes && now<end_minutes);
   //--- Window wraps midnight: inside means "late today OR early
   //--- tomorrow". Handling this here prevents every session filter
   //--- from reinventing it incorrectly.
   return(now>=start_minutes || now<end_minutes);
  }
//+------------------------------------------------------------------+
int CTimeUtils::HoursMinutesToMinutes(const int hour,const int minute)
  {
   return(hour*60+minute);
  }
//+------------------------------------------------------------------+
string CTimeUtils::MinutesToHhMm(const int minutes)
  {
   const int normalized=((minutes%1440)+1440)%1440;
   return(StringFormat("%02d:%02d",normalized/60,normalized%60));
  }
//+------------------------------------------------------------------+
bool CTimeUtils::IsWeekend(const datetime moment)
  {
   const int dow=DayOfWeek(moment);
   return(dow==0 || dow==6);
  }
//+------------------------------------------------------------------+
string CTimeUtils::FormatDuration(const int seconds)
  {
   if(seconds<0)
      return("0s");
   const int hours=seconds/3600;
   const int mins=(seconds%3600)/60;
   const int secs=seconds%60;
   if(hours>0)
      return(StringFormat("%dh %02dm %02ds",hours,mins,secs));
   if(mins>0)
      return(StringFormat("%dm %02ds",mins,secs));
   return(StringFormat("%ds",secs));
  }

#endif // SRP_UTILITIES_CTIMEUTILS_MQH
//+------------------------------------------------------------------+
