//+------------------------------------------------------------------+
//|                                         CStochasticIndicator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Indicators : iStochastic wrapper (main, signal).                    |
//+------------------------------------------------------------------+
#ifndef SRP_INDICATORS_CSTOCHASTICINDICATOR_MQH
#define SRP_INDICATORS_CSTOCHASTICINDICATOR_MQH

#include "../Core/Base/CIndicatorBase.mqh"

class CStochasticIndicator : public CIndicatorBase
  {
private:
   int               m_k_period;
   int               m_d_period;
   int               m_slowing;
   ENUM_MA_METHOD    m_method;
   ENUM_STO_PRICE    m_price_field;

protected:
   virtual int       OnCreateHandle(void) override;

public:
                     CStochasticIndicator(const string symbol,
                                          const ENUM_TIMEFRAMES timeframe,
                                          const int k_period,
                                          const int d_period,
                                          const int slowing,
                                          const ENUM_MA_METHOD method,
                                          const ENUM_STO_PRICE price_field,
                                          ILogger *logger);
                    ~CStochasticIndicator(void) { }

   bool              Main(const int shift,double &out_value);
   bool              Signal(const int shift,double &out_value);

   bool              IsOverbought(const double threshold,const int shift=0);
   bool              IsOversold(const double threshold,const int shift=0);
  };

//+------------------------------------------------------------------+
CStochasticIndicator::CStochasticIndicator(const string symbol,
                                           const ENUM_TIMEFRAMES timeframe,
                                           const int k_period,
                                           const int d_period,
                                           const int slowing,
                                           const ENUM_MA_METHOD method,
                                           const ENUM_STO_PRICE price_field,
                                           ILogger *logger)
  : CIndicatorBase("Stochastic",SRP_INDICATOR_STOCHASTIC,symbol,timeframe,
                   logger,2,k_period+d_period+slowing+2),
    m_k_period(k_period),
    m_d_period(d_period),
    m_slowing(slowing),
    m_method(method),
    m_price_field(price_field)
  {
  }
//+------------------------------------------------------------------+
int CStochasticIndicator::OnCreateHandle(void)
  {
   return(iStochastic(m_symbol,m_timeframe,m_k_period,m_d_period,
                      m_slowing,m_method,m_price_field));
  }
//+------------------------------------------------------------------+
bool CStochasticIndicator::Main(const int shift,double &out_value)
  {
   return(GetValue(0,shift,out_value));
  }
//+------------------------------------------------------------------+
bool CStochasticIndicator::Signal(const int shift,double &out_value)
  {
   return(GetValue(1,shift,out_value));
  }

#endif // SRP_INDICATORS_CSTOCHASTICINDICATOR_MQH
//+------------------------------------------------------------------+
