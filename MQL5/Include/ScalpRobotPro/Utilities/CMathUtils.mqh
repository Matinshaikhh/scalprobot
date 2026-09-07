//+------------------------------------------------------------------+
//|                                                  CMathUtils.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Utilities : stateless numeric helpers.                           |
//|                                                                  |
//|   All members are static: this is a namespace, not an object. It    |
//|   exists so that float comparison and statistical formulas are      |
//|   written ONCE and are identically correct everywhere. Duplicated   |
//|   epsilon logic is a classic source of silent trading bugs.         |
//+------------------------------------------------------------------+
#ifndef SRP_UTILITIES_CMATHUTILS_MQH
#define SRP_UTILITIES_CMATHUTILS_MQH

#include "../Core/Types/Constants.mqh"

class CMathUtils
  {
public:
   //--- Safe floating-point comparison ------------------------------
   static bool       IsEqual(const double a,const double b,
                             const double epsilon=SRP_EPSILON);
   static bool       IsZero(const double value,
                            const double epsilon=SRP_EPSILON);
   static bool       IsGreater(const double a,const double b,
                              const double epsilon=SRP_EPSILON);
   static bool       IsLess(const double a,const double b,
                           const double epsilon=SRP_EPSILON);

   //--- Division that cannot produce inf/nan. Every ratio in the
   //--- statistics layer goes through this.
   static double     SafeDivide(const double numerator,
                                const double denominator,
                                const double fallback=0.0);

   //--- Clamping and rounding ---------------------------------------
   static double     Clamp(const double value,const double minimum,
                           const double maximum);
   static int        ClampInt(const int value,const int minimum,
                              const int maximum);
   static double     RoundToStep(const double value,const double step);
   static double     FloorToStep(const double value,const double step);

   //--- Descriptive statistics --------------------------------------
   static double     Sum(const double &values[]);
   static double     Mean(const double &values[]);
   static double     StandardDeviation(const double &values[]);
   static double     DownsideDeviation(const double &values[],
                                       const double threshold);
   static double     Maximum(const double &values[]);
   static double     Minimum(const double &values[]);
   static double     Percentile(const double &values[],const double percentile);

   //--- Percent helpers used by risk and statistics ------------------
   static double     PercentOf(const double value,const double percent);
   static double     PercentChange(const double from,const double to);
  };

//+------------------------------------------------------------------+
bool CMathUtils::IsEqual(const double a,const double b,const double epsilon)
  {
   return(MathAbs(a-b)<=epsilon);
  }
//+------------------------------------------------------------------+
bool CMathUtils::IsZero(const double value,const double epsilon)
  {
   return(MathAbs(value)<=epsilon);
  }
//+------------------------------------------------------------------+
bool CMathUtils::IsGreater(const double a,const double b,const double epsilon)
  {
   return(a-b>epsilon);
  }
//+------------------------------------------------------------------+
bool CMathUtils::IsLess(const double a,const double b,const double epsilon)
  {
   return(b-a>epsilon);
  }
//+------------------------------------------------------------------+
double CMathUtils::SafeDivide(const double numerator,
                              const double denominator,
                              const double fallback)
  {
   if(IsZero(denominator))
      return(fallback);
   return(numerator/denominator);
  }
//+------------------------------------------------------------------+
double CMathUtils::Clamp(const double value,const double minimum,
                         const double maximum)
  {
   if(value<minimum) return(minimum);
   if(value>maximum) return(maximum);
   return(value);
  }
//+------------------------------------------------------------------+
int CMathUtils::ClampInt(const int value,const int minimum,const int maximum)
  {
   if(value<minimum) return(minimum);
   if(value>maximum) return(maximum);
   return(value);
  }
//+------------------------------------------------------------------+
double CMathUtils::RoundToStep(const double value,const double step)
  {
   if(IsZero(step))
      return(value);
   return(MathRound(value/step)*step);
  }
//+------------------------------------------------------------------+
double CMathUtils::FloorToStep(const double value,const double step)
  {
   if(IsZero(step))
      return(value);
   return(MathFloor(value/step)*step);
  }
//+------------------------------------------------------------------+
double CMathUtils::PercentOf(const double value,const double percent)
  {
   return(value*percent/100.0);
  }
//+------------------------------------------------------------------+
double CMathUtils::PercentChange(const double from,const double to)
  {
   return(SafeDivide((to-from)*100.0,MathAbs(from),0.0));
  }

#endif // SRP_UTILITIES_CMATHUTILS_MQH
//+------------------------------------------------------------------+
