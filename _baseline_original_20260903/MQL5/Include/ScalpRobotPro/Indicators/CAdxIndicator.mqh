//+------------------------------------------------------------------+
//|                                                CAdxIndicator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Indicators : iADX wrapper (main, +DI, -DI).                         |
//|                                                                  |
//|   Consumed by CMarketRegimeAnalyzer to distinguish a trending      |
//|   market from a ranging one, and by CTrendFilter to reject          |
//|   counter-trend entries.                                           |
//+------------------------------------------------------------------+
#ifndef SRP_INDICATORS_CADXINDICATOR_MQH
#define SRP_INDICATORS_CADXINDICATOR_MQH

#include "../Core/Base/CIndicatorBase.mqh"

class CAdxIndicator : public CIndicatorBase
  {
private:
   int               m_period;

protected:
   virtual int       OnCreateHandle(void) override;

public:
                     CAdxIndicator(const string symbol,
                                   const ENUM_TIMEFRAMES timeframe,
                                   const int period,
                                   ILogger *logger);
                    ~CAdxIndicator(void) { }

   bool              Main(const int shift,double &out_value);
   bool              PlusDi(const int shift,double &out_value);
   bool              MinusDi(const int shift,double &out_value);

   //--- Domain queries.
   bool              IsTrending(const double threshold,const int shift=0);
   bool              IsBullishBias(const int shift=0);

   int               Period(void) const { return(m_period); }
  };

//+------------------------------------------------------------------+
CAdxIndicator::CAdxIndicator(const string symbol,
                             const ENUM_TIMEFRAMES timeframe,
                             const int period,
                             ILogger *logger)
  : CIndicatorBase("ADX("+IntegerToString(period)+")",
                   SRP_INDICATOR_ADX,symbol,timeframe,logger,3,period*2+2),
    m_period(period)
  {
  }
//+------------------------------------------------------------------+
int CAdxIndicator::OnCreateHandle(void)
  {
   return(iADX(m_symbol,m_timeframe,m_period));
  }
//+------------------------------------------------------------------+
bool CAdxIndicator::Main(const int shift,double &out_value)
  {
   return(GetValue(0,shift,out_value));
  }
//+------------------------------------------------------------------+
bool CAdxIndicator::PlusDi(const int shift,double &out_value)
  {
   return(GetValue(1,shift,out_value));
  }
//+------------------------------------------------------------------+
bool CAdxIndicator::MinusDi(const int shift,double &out_value)
  {
   return(GetValue(2,shift,out_value));
  }

#endif // SRP_INDICATORS_CADXINDICATOR_MQH
//+------------------------------------------------------------------+
