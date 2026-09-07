//+------------------------------------------------------------------+
//|                                    CMovingAverageIndicator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Indicators : iMA wrapper.                                           |
//|                                                                  |
//|   One class, one indicator. The base class already owns the handle    |
//|   lifecycle, so all that remains here is the creation call and the    |
//|   parameters that define this particular average.                     |
//+------------------------------------------------------------------+
#ifndef SRP_INDICATORS_CMOVINGAVERAGEINDICATOR_MQH
#define SRP_INDICATORS_CMOVINGAVERAGEINDICATOR_MQH

#include "../Core/Base/CIndicatorBase.mqh"

class CMovingAverageIndicator : public CIndicatorBase
  {
private:
   int                    m_period;
   int                    m_shift;
   ENUM_MA_METHOD         m_method;
   ENUM_APPLIED_PRICE     m_applied_price;

protected:
   virtual int       OnCreateHandle(void) override;

public:
                     CMovingAverageIndicator(const string name,
                                             const ENUM_SRP_INDICATOR_ID id,
                                             const string symbol,
                                             const ENUM_TIMEFRAMES timeframe,
                                             const int period,
                                             const ENUM_MA_METHOD method,
                                             const ENUM_APPLIED_PRICE applied_price,
                                             ILogger *logger,
                                             const int shift=0);
                    ~CMovingAverageIndicator(void) { }

   //--- Semantic accessors. Strategies read these instead of calling
   //--- GetValue with a magic buffer index, which keeps strategy code
   //--- readable and immune to buffer reordering.
   bool              Value(const int shift,double &out_value);
   bool              Slope(const int lookback,double &out_slope);
   bool              IsPriceAbove(const double price,const int shift=0);

   int               Period(void) const { return(m_period); }
  };

//+------------------------------------------------------------------+
CMovingAverageIndicator::CMovingAverageIndicator(const string name,
                                                 const ENUM_SRP_INDICATOR_ID id,
                                                 const string symbol,
                                                 const ENUM_TIMEFRAMES timeframe,
                                                 const int period,
                                                 const ENUM_MA_METHOD method,
                                                 const ENUM_APPLIED_PRICE applied_price,
                                                 ILogger *logger,
                                                 const int shift)
  : CIndicatorBase(name,id,symbol,timeframe,logger,1,period+2),
    m_period(period),
    m_shift(shift),
    m_method(method),
    m_applied_price(applied_price)
  {
  }
//+------------------------------------------------------------------+
int CMovingAverageIndicator::OnCreateHandle(void)
  {
   return(iMA(m_symbol,m_timeframe,m_period,m_shift,m_method,m_applied_price));
  }
//+------------------------------------------------------------------+
bool CMovingAverageIndicator::Value(const int shift,double &out_value)
  {
   return(GetValue(0,shift,out_value));
  }

#endif // SRP_INDICATORS_CMOVINGAVERAGEINDICATOR_MQH
//+------------------------------------------------------------------+
