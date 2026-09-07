//+------------------------------------------------------------------+
//|                                                CRsiIndicator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Indicators : iRSI wrapper.                                          |
//+------------------------------------------------------------------+
#ifndef SRP_INDICATORS_CRSIINDICATOR_MQH
#define SRP_INDICATORS_CRSIINDICATOR_MQH

#include "../Core/Base/CIndicatorBase.mqh"

class CRsiIndicator : public CIndicatorBase
  {
private:
   int                m_period;
   ENUM_APPLIED_PRICE m_applied_price;

protected:
   virtual int       OnCreateHandle(void) override;

public:
                     CRsiIndicator(const string symbol,
                                   const ENUM_TIMEFRAMES timeframe,
                                   const int period,
                                   const ENUM_APPLIED_PRICE applied_price,
                                   ILogger *logger);
                    ~CRsiIndicator(void) { }

   bool              Value(const int shift,double &out_value);
   //--- Threshold queries expressed in domain terms, so strategies read
   //--- like intent rather than arithmetic.
   bool              IsOverbought(const double threshold,const int shift=0);
   bool              IsOversold(const double threshold,const int shift=0);
   bool              CrossedAbove(const double level);
   bool              CrossedBelow(const double level);

   int               Period(void) const { return(m_period); }
  };

//+------------------------------------------------------------------+
CRsiIndicator::CRsiIndicator(const string symbol,
                             const ENUM_TIMEFRAMES timeframe,
                             const int period,
                             const ENUM_APPLIED_PRICE applied_price,
                             ILogger *logger)
  : CIndicatorBase("RSI("+IntegerToString(period)+")",
                   SRP_INDICATOR_RSI,symbol,timeframe,logger,1,period+2),
    m_period(period),
    m_applied_price(applied_price)
  {
  }
//+------------------------------------------------------------------+
int CRsiIndicator::OnCreateHandle(void)
  {
   return(iRSI(m_symbol,m_timeframe,m_period,m_applied_price));
  }
//+------------------------------------------------------------------+
bool CRsiIndicator::Value(const int shift,double &out_value)
  {
   return(GetValue(0,shift,out_value));
  }

#endif // SRP_INDICATORS_CRSIINDICATOR_MQH
//+------------------------------------------------------------------+
