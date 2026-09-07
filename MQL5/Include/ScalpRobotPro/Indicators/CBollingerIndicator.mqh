//+------------------------------------------------------------------+
//|                                          CBollingerIndicator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Indicators : iBands wrapper (3 buffers).                            |
//+------------------------------------------------------------------+
#ifndef SRP_INDICATORS_CBOLLINGERINDICATOR_MQH
#define SRP_INDICATORS_CBOLLINGERINDICATOR_MQH

#include "../Core/Base/CIndicatorBase.mqh"

class CBollingerIndicator : public CIndicatorBase
  {
private:
   int                m_period;
   double             m_deviation;
   int                m_shift;
   ENUM_APPLIED_PRICE m_applied_price;

protected:
   virtual int       OnCreateHandle(void) override;

public:
                     CBollingerIndicator(const string symbol,
                                         const ENUM_TIMEFRAMES timeframe,
                                         const int period,
                                         const double deviation,
                                         const ENUM_APPLIED_PRICE applied_price,
                                         ILogger *logger,
                                         const int shift=0);
                    ~CBollingerIndicator(void) { }

   //--- Named buffer accessors: iBands orders buffers base/upper/lower,
   //--- which is easy to get wrong. Naming it once removes the risk.
   bool              Middle(const int shift,double &out_value);
   bool              Upper(const int shift,double &out_value);
   bool              Lower(const int shift,double &out_value);

   //--- Derived measures used by the mean-reversion strategy.
   bool              WidthPoints(const int shift,const double point,
                                 double &out_points);
   bool              PercentB(const double price,const int shift,
                              double &out_percent);
   bool              IsSqueezing(const int lookback);
  };

//+------------------------------------------------------------------+
CBollingerIndicator::CBollingerIndicator(const string symbol,
                                         const ENUM_TIMEFRAMES timeframe,
                                         const int period,
                                         const double deviation,
                                         const ENUM_APPLIED_PRICE applied_price,
                                         ILogger *logger,
                                         const int shift)
  : CIndicatorBase("Bands("+IntegerToString(period)+")",
                   SRP_INDICATOR_BOLLINGER,symbol,timeframe,logger,3,period+2),
    m_period(period),
    m_deviation(deviation),
    m_shift(shift),
    m_applied_price(applied_price)
  {
  }
//+------------------------------------------------------------------+
int CBollingerIndicator::OnCreateHandle(void)
  {
   return(iBands(m_symbol,m_timeframe,m_period,m_shift,m_deviation,m_applied_price));
  }
//+------------------------------------------------------------------+
bool CBollingerIndicator::Middle(const int shift,double &out_value)
  {
   return(GetValue(0,shift,out_value));
  }
//+------------------------------------------------------------------+
bool CBollingerIndicator::Upper(const int shift,double &out_value)
  {
   return(GetValue(1,shift,out_value));
  }
//+------------------------------------------------------------------+
bool CBollingerIndicator::Lower(const int shift,double &out_value)
  {
   return(GetValue(2,shift,out_value));
  }

#endif // SRP_INDICATORS_CBOLLINGERINDICATOR_MQH
//+------------------------------------------------------------------+
