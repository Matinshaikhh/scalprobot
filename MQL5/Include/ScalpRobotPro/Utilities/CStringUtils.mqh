//+------------------------------------------------------------------+
//|                                                CStringUtils.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Utilities : stateless string helpers.                             |
//+------------------------------------------------------------------+
#ifndef SRP_UTILITIES_CSTRINGUTILS_MQH
#define SRP_UTILITIES_CSTRINGUTILS_MQH

class CStringUtils
  {
public:
   //--- Trimming and casing -----------------------------------------
   static string     Trim(const string text);
   static string     ToUpper(const string text);
   static string     ToLower(const string text);

   //--- Splitting and joining ---------------------------------------
   static int        Split(const string text,const string separator,
                           string &out[]);
   static string     Join(const string &parts[],const string separator);

   //--- Tests --------------------------------------------------------
   static bool       StartsWith(const string text,const string prefix);
   static bool       EndsWith(const string text,const string suffix);
   static bool       Contains(const string text,const string needle);
   static bool       ContainsAnyOf(const string text,const string &needles[]);
   static bool       IsNullOrEmpty(const string text);

   //--- Formatting for the dashboard --------------------------------
   static string     PadLeft(const string text,const int width,
                             const string pad=" ");
   static string     PadRight(const string text,const int width,
                              const string pad=" ");
   static string     Truncate(const string text,const int max_length);

   //--- Domain-specific formatters, centralised so every panel and log
   //--- renders money and volume identically.
   static string     FormatMoney(const double amount,const string currency,
                                 const int digits=2);
   static string     FormatPercent(const double value,const int digits=2);
   static string     FormatVolume(const double volume,const double volume_step);
   static string     FormatPoints(const double points,const int digits=1);
   static string     FormatSigned(const double value,const int digits=2);

   //--- CSV safety: escapes quotes and commas before writing.
   static string     EscapeCsvField(const string text);
  };

//+------------------------------------------------------------------+
bool CStringUtils::IsNullOrEmpty(const string text)
  {
   return(StringLen(text)==0);
  }
//+------------------------------------------------------------------+
string CStringUtils::Trim(const string text)
  {
   string copy=text;
   StringTrimLeft(copy);
   StringTrimRight(copy);
   return(copy);
  }
//+------------------------------------------------------------------+
string CStringUtils::ToUpper(const string text)
  {
   string copy=text;
   StringToUpper(copy);
   return(copy);
  }
//+------------------------------------------------------------------+
string CStringUtils::ToLower(const string text)
  {
   string copy=text;
   StringToLower(copy);
   return(copy);
  }
//+------------------------------------------------------------------+
bool CStringUtils::StartsWith(const string text,const string prefix)
  {
   const int prefix_length=StringLen(prefix);
   if(prefix_length==0 || StringLen(text)<prefix_length)
      return(false);
   return(StringSubstr(text,0,prefix_length)==prefix);
  }
//+------------------------------------------------------------------+
bool CStringUtils::EndsWith(const string text,const string suffix)
  {
   const int suffix_length=StringLen(suffix);
   const int text_length=StringLen(text);
   if(suffix_length==0 || text_length<suffix_length)
      return(false);
   return(StringSubstr(text,text_length-suffix_length,suffix_length)==suffix);
  }
//+------------------------------------------------------------------+
bool CStringUtils::Contains(const string text,const string needle)
  {
   return(StringFind(text,needle)>=0);
  }
//+------------------------------------------------------------------+
string CStringUtils::FormatPercent(const double value,const int digits)
  {
   return(DoubleToString(value,digits)+"%");
  }
//+------------------------------------------------------------------+
string CStringUtils::FormatMoney(const double amount,const string currency,
                                 const int digits)
  {
   return(DoubleToString(amount,digits)+" "+currency);
  }
//+------------------------------------------------------------------+
string CStringUtils::FormatSigned(const double value,const int digits)
  {
   return((value>0.0 ? "+" : "")+DoubleToString(value,digits));
  }
//+------------------------------------------------------------------+
string CStringUtils::Truncate(const string text,const int max_length)
  {
   if(max_length<=0 || StringLen(text)<=max_length)
      return(text);
   if(max_length<=3)
      return(StringSubstr(text,0,max_length));
   return(StringSubstr(text,0,max_length-3)+"...");
  }

#endif // SRP_UTILITIES_CSTRINGUTILS_MQH
//+------------------------------------------------------------------+
