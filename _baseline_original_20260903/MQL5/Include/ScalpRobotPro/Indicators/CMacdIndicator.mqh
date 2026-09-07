//+------------------------------------------------------------------+
//|                                               CMacdIndicator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Indicators : iMACD wrapper (main, signal).                          |
//+------------------------------------------------------------------+
#ifndef SRP_INDICATORS_CMACDINDICATOR_MQH
#define SRP_INDICATORS_CMACDINDICATOR_MQH

#include "../Core/Base/CIndicatorBase.mqh"

class CMacdIndicator : public CIndicatorBase
  {
private:
   int                m_fast_period;
   int                m_slow_period;
   int                m_signal_period;
   ENUM_APPLIED_PRICE m_applied_price;

protected:
   virtual int       OnCreateHandle(void) override;

public:
                     CMacdIndicator(const string symbol,
                                    const ENUM_TIMEFRAMES timeframe,
                                    const int fast_period,
                                    const int slow_period,
                                    const int signal_period,
                                    const ENUM_APPLIED_PRICE applied_price,
                                    ILogger *logger);
                    ~CMacdIndicator(void) { }

   bool              Main(const int shift,double &out_value);
   bool              Signal(const int shift,double &out_value);
   bool              Histogram(const int shift,double &out_value);

   //--- Cross detection compares two consecutive bars, so it is
   //--- implemented once here rather than in each strategy.
   bool              CrossedUp(void);
   bool              CrossedDown(void);
  };

//+------------------------------------------------------------------+
CMacdIndicator::CMacdIndicator(const string symbol,
                               const ENUM_TIMEFRAMES timeframe,
                               const int fast_period,
                               const int slow_period,
                               const int signal_period,
                               const ENUM_APPLIED_PRICE applied_price,
                               ILogger *logger)
  : CIndicatorBase("MACD",SRP_INDICATOR_MACD,symbol,timeframe,logger,2,
                   slow_period+signal_period+2),
    m_fast_period(fast_period),
    m_slow_period(slow_period),
    m_signal_period(signal_period),
    m_applied_price(applied_price)
  {
  }
//+------------------------------------------------------------------+
int CMacdIndicator::OnCreateHandle(void)
  {
   return(iMACD(m_symbol,m_timeframe,m_fast_period,m_slow_period,
                m_signal_period,m_applied_price));
  }
//+------------------------------------------------------------------+
bool CMacdIndicator::Main(const int shift,double &out_value)
  {
   return(GetValue(0,shift,out_value));
  }
//+------------------------------------------------------------------+
bool CMacdIndicator::Signal(const int shift,double &out_value)
  {
   return(GetValue(1,shift,out_value));
  }

#endif // SRP_INDICATORS_CMACDINDICATOR_MQH
//+------------------------------------------------------------------+
