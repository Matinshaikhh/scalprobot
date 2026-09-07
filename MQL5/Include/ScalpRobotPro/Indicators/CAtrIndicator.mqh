//+------------------------------------------------------------------+
//|                                                CAtrIndicator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Indicators : iATR wrapper.                                          |
//|                                                                  |
//|   The most widely consumed indicator in the product: the volatility  |
//|   filter, the ATR stop calculator, the ATR take-profit calculator,   |
//|   the volatility-scaled sizer and the regime analyzer all read it.   |
//|   Because they share ONE instance through CIndicatorManager, the     |
//|   terminal computes it once and every consumer sees the same value.  |
//+------------------------------------------------------------------+
#ifndef SRP_INDICATORS_CATRINDICATOR_MQH
#define SRP_INDICATORS_CATRINDICATOR_MQH

#include "../Core/Base/CIndicatorBase.mqh"

class CAtrIndicator : public CIndicatorBase
  {
private:
   int               m_period;

protected:
   virtual int       OnCreateHandle(void) override;

public:
                     CAtrIndicator(const string symbol,
                                   const ENUM_TIMEFRAMES timeframe,
                                   const int period,
                                   ILogger *logger);
                    ~CAtrIndicator(void) { }

   bool              Value(const int shift,double &out_value);
   //--- ATR as a percentage of price: the normalised volatility measure
   //--- the regime analyzer classifies on.
   bool              AsPercentOfPrice(const double price,const int shift,
                                      double &out_percent);
   //--- Average ATR over a lookback, for detecting expansion.
   bool              AverageValue(const int lookback,double &out_value);

   int               Period(void) const { return(m_period); }
  };

//+------------------------------------------------------------------+
CAtrIndicator::CAtrIndicator(const string symbol,
                             const ENUM_TIMEFRAMES timeframe,
                             const int period,
                             ILogger *logger)
  : CIndicatorBase("ATR("+IntegerToString(period)+")",
                   SRP_INDICATOR_ATR,symbol,timeframe,logger,1,period+2),
    m_period(period)
  {
  }
//+------------------------------------------------------------------+
int CAtrIndicator::OnCreateHandle(void)
  {
   return(iATR(m_symbol,m_timeframe,m_period));
  }
//+------------------------------------------------------------------+
bool CAtrIndicator::Value(const int shift,double &out_value)
  {
   return(GetValue(0,shift,out_value));
  }

#endif // SRP_INDICATORS_CATRINDICATOR_MQH
//+------------------------------------------------------------------+
