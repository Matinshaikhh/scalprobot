//+------------------------------------------------------------------+
//|                                                    CXspStats.mqh |
//|          XauStructurePro - Core : the statistics the study needs |
//|                                                                  |
//|   Written here rather than reused. SRP's CMathUtils DECLARES Sum,      |
//|   Mean, StandardDeviation, Maximum, Minimum and Percentile and gives   |
//|   none of them a body; MQL5 tolerates that only for as long as        |
//|   nothing calls them, which is why the old EA still compiles. The L2   |
//|   regime deciles need exactly the missing half, so XSP supplies it.    |
//|   The frozen tree is not touched: it is the section-9.5 baseline.      |
//+------------------------------------------------------------------+
#ifndef XSP_CORE_CXSPSTATS_MQH
#define XSP_CORE_CXSPSTATS_MQH

#include "XspConstants.mqh"

class CXspStats
  {
public:
   //--- Fraction of the sample at or below value, in [0,1].
   //--- O(n) and no sort: the decile is the only thing needed and a rank
   //--- fraction gives it directly. Sorting a 4,096-element spread buffer
   //--- on every trigger would cost more than the measurement is worth.
   static double     RankFraction(const double value,const double &samples[],const int count)
     {
      if(count<=0) return(-1.0);
      int at_or_below=0;
      for(int i=0;i<count;i++)
         if(samples[i]<=value) at_or_below++;
      return((double)at_or_below/(double)count);
     }

   //--- 0..9, or -1 when the sample is too small to carry ten buckets.
   //--- The minimum is stated by the caller, never assumed: a decile over
   //--- 12 observations is arithmetic, not a regime.
   static int        Decile(const double value,const double &samples[],const int count,
                           const int min_count)
     {
      if(count<min_count || count<10) return(-1);
      const double frac=RankFraction(value,samples,count);
      if(frac<0.0) return(-1);
      int d=(int)MathFloor(frac*10.0);
      if(d>9) d=9;
      if(d<0) d=0;
      return(d);
     }

   static double     Mean(const double &samples[],const int count)
     {
      if(count<=0) return(0.0);
      double sum=0.0;
      for(int i=0;i<count;i++) sum+=samples[i];
      return(sum/(double)count);
     }

   //--- Sample standard deviation (n-1). Population sd would understate
   //--- the spread of any small label bucket, and small buckets are
   //--- exactly what the exploratory cuts will produce.
   static double     StdDev(const double &samples[],const int count)
     {
      if(count<2) return(0.0);
      const double m=Mean(samples,count);
      double acc=0.0;
      for(int i=0;i<count;i++)
        {
         const double d=samples[i]-m;
         acc+=d*d;
        }
      return(MathSqrt(acc/(double)(count-1)));
     }

   //--- Median of a COPY. The caller's buffer is a rolling window that
   //--- other code indexes by age; sorting it in place would silently
   //--- destroy that ordering.
   static double     Median(const double &samples[],const int count)
     {
      if(count<=0) return(0.0);
      double work[];
      if(ArrayResize(work,count)!=count) return(0.0);
      for(int i=0;i<count;i++) work[i]=samples[i];
      ArraySort(work);
      if((count%2)==1) return(work[count/2]);
      return(0.5*(work[count/2-1]+work[count/2]));
     }

   //--- Median of a long series, for broker tick volume. A separate
   //--- overload rather than a cast at the call site: casting 20 tick
   //--- counts to double to find their median is fine, but doing it
   //--- implicitly is how a long silently becomes a float somewhere it
   //--- matters.
   static double     MedianLong(const long &samples[],const int count)
     {
      if(count<=0) return(0.0);
      double work[];
      if(ArrayResize(work,count)!=count) return(0.0);
      for(int i=0;i<count;i++) work[i]=(double)samples[i];
      ArraySort(work);
      if((count%2)==1) return(work[count/2]);
      return(0.5*(work[count/2-1]+work[count/2]));
     }

   //--- Guarded division. Returns fallback instead of raising a zero
   //--- divide, because a study that dies mid-run loses every instance
   //--- it had already recorded.
   static double     SafeDiv(const double num,const double den,const double fallback=0.0)
     {
      if(MathAbs(den)<XSP_EPSILON) return(fallback);
      return(num/den);
     }
  };

#endif // XSP_CORE_CXSPSTATS_MQH
//+------------------------------------------------------------------+
