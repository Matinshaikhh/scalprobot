//+------------------------------------------------------------------+
//|                                       CStandardIndicators.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   The eleven indicators backed by MQL5 built-ins. Each subclass       |
//|   implements ONLY OnCreateHandle() plus semantic accessors, because    |
//|   CIntelIndicator already owns caching, validation, warm-up gating,    |
//|   error handling and the generic read API.                            |
//|                                                                  |
//|   Semantic accessors matter: a strategy reading `IsOverbought(70)`     |
//|   is readable and immune to buffer reordering, whereas                 |
//|   `ValueAt(0,0,v)` is neither.                                       |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_INDICATORS_CSTANDARDINDICATORS_MQH
#define SRP_INTELLIGENCE_INDICATORS_CSTANDARDINDICATORS_MQH

#include "CIndicatorBase.mqh"

//+------------------------------------------------------------------+
//| EMA                                                               |
//+------------------------------------------------------------------+
class CEmaIndicator : public CIntelIndicator
  {
private:
   int                m_period;
   ENUM_APPLIED_PRICE m_price;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iMA(m_symbol,m_timeframe,m_period,0,MODE_EMA,m_price)); }
public:
                     CEmaIndicator(const string symbol,const ENUM_TIMEFRAMES tf,
                                   const int period,ILogger *logger,
                                   const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
     : CIntelIndicator("EMA("+IntegerToString(period)+")",SRP_IND_EMA,
                       symbol,tf,logger,1,period+2),
       m_period(period),m_price(price) { }

   int               Period(void) const { return(m_period); }
   //--- True when price closed above the average on the given bar.
   bool              IsPriceAbove(const double price,const int shift=0) const
     {
      double value=0.0;
      if(!ValueAt(0,shift,value)) return(false);
      return(price>value);
     }
  };

//+------------------------------------------------------------------+
//| SMA                                                               |
//+------------------------------------------------------------------+
class CSmaIndicator : public CIntelIndicator
  {
private:
   int                m_period;
   ENUM_APPLIED_PRICE m_price;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iMA(m_symbol,m_timeframe,m_period,0,MODE_SMA,m_price)); }
public:
                     CSmaIndicator(const string symbol,const ENUM_TIMEFRAMES tf,
                                   const int period,ILogger *logger,
                                   const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
     : CIntelIndicator("SMA("+IntegerToString(period)+")",SRP_IND_SMA,
                       symbol,tf,logger,1,period+2),
       m_period(period),m_price(price) { }

   int               Period(void) const { return(m_period); }
   bool              IsPriceAbove(const double price,const int shift=0) const
     {
      double value=0.0;
      if(!ValueAt(0,shift,value)) return(false);
      return(price>value);
     }
  };

//+------------------------------------------------------------------+
//| ATR - the volatility reference used across risk and SMC.            |
//+------------------------------------------------------------------+
class CAtrIntel : public CIntelIndicator
  {
private:
   int               m_period;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iATR(m_symbol,m_timeframe,m_period)); }
public:
                     CAtrIntel(const string symbol,const ENUM_TIMEFRAMES tf,
                               const int period,ILogger *logger)
     : CIntelIndicator("ATR("+IntegerToString(period)+")",SRP_IND_ATR,
                       symbol,tf,logger,1,period+2),
       m_period(period) { }

   int               Period(void) const { return(m_period); }

   //--- ATR expressed in points, which is what stop calculators need.
   bool              Points(const int shift,const double point,double &out) const
     {
      out=0.0;
      double value=0.0;
      if(!ValueAt(0,shift,value) || point<=0.0) return(false);
      out=value/point;
      return(true);
     }
   //--- Normalised volatility: ATR as a percentage of price. Comparable
   //--- across instruments and across price regimes.
   bool              PercentOfPrice(const double price,const int shift,
                                    double &out) const
     {
      out=0.0;
      double value=0.0;
      if(!ValueAt(0,shift,value) || price<=0.0) return(false);
      out=value/price*100.0;
      return(true);
     }
   //--- Current ATR relative to its own recent average: the expansion
   //--- ratio that identifies a volatility breakout.
   bool              ExpansionRatio(const int lookback,double &out) const
     {
      out=0.0;
      double current=0.0,mean=0.0;
      if(!ValueAt(0,0,current)) return(false);
      if(!Average(0,1,lookback,mean) || mean<=0.0) return(false);
      out=current/mean;
      return(true);
     }
  };

//+------------------------------------------------------------------+
//| RSI                                                               |
//+------------------------------------------------------------------+
class CRsiIntel : public CIntelIndicator
  {
private:
   int                m_period;
   ENUM_APPLIED_PRICE m_price;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iRSI(m_symbol,m_timeframe,m_period,m_price)); }
public:
                     CRsiIntel(const string symbol,const ENUM_TIMEFRAMES tf,
                               const int period,ILogger *logger,
                               const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
     : CIntelIndicator("RSI("+IntegerToString(period)+")",SRP_IND_RSI,
                       symbol,tf,logger,1,period+2),
       m_period(period),m_price(price) { }

   bool              IsOverbought(const double threshold=70.0,const int shift=0) const
     {
      double value=0.0;
      if(!ValueAt(0,shift,value)) return(false);
      return(value>=threshold);
     }
   bool              IsOversold(const double threshold=30.0,const int shift=0) const
     {
      double value=0.0;
      if(!ValueAt(0,shift,value)) return(false);
      return(value<=threshold);
     }
   //--- Divergence needs price context, so it is left to the structure
   //--- engine; this only reports the momentum direction.
   bool              IsRising(const int lookback=3) const
     {
      double slope=0.0;
      if(!Slope(0,lookback,slope)) return(false);
      return(slope>0.0);
     }
  };

//+------------------------------------------------------------------+
//| ADX - buffer 0 main, 1 +DI, 2 -DI                                  |
//+------------------------------------------------------------------+
class CAdxIntel : public CIntelIndicator
  {
private:
   int               m_period;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iADX(m_symbol,m_timeframe,m_period)); }
public:
                     CAdxIntel(const string symbol,const ENUM_TIMEFRAMES tf,
                               const int period,ILogger *logger)
     : CIntelIndicator("ADX("+IntegerToString(period)+")",SRP_IND_ADX,
                       symbol,tf,logger,3,period*2+2),
       m_period(period) { }

   bool              Main(const int shift,double &out) const    { return(ValueAt(0,shift,out)); }
   bool              PlusDi(const int shift,double &out) const  { return(ValueAt(1,shift,out)); }
   bool              MinusDi(const int shift,double &out) const { return(ValueAt(2,shift,out)); }

   //--- ADX measures trend STRENGTH, not direction; the DI pair supplies
   //--- direction. Conflating them is a common misreading.
   bool              IsTrending(const double threshold=25.0,const int shift=0) const
     {
      double value=0.0;
      if(!Main(shift,value)) return(false);
      return(value>=threshold);
     }
   bool              IsBullishBias(const int shift=0) const
     {
      double plus=0.0,minus=0.0;
      if(!PlusDi(shift,plus) || !MinusDi(shift,minus)) return(false);
      return(plus>minus);
     }
   //--- Normalised 0..1 strength for the structure engine's score.
   bool              StrengthScore(double &out) const
     {
      out=0.0;
      double value=0.0;
      if(!Main(0,value)) return(false);
      //--- ADX above 50 is exceptional; clamp so the score stays bounded.
      out=(value>50.0 ? 1.0 : value/50.0);
      return(true);
     }
  };

//+------------------------------------------------------------------+
//| MACD - buffer 0 main, 1 signal                                     |
//+------------------------------------------------------------------+
class CMacdIntel : public CIntelIndicator
  {
private:
   int                m_fast,m_slow,m_signal;
   ENUM_APPLIED_PRICE m_price;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iMACD(m_symbol,m_timeframe,m_fast,m_slow,m_signal,m_price)); }
public:
                     CMacdIntel(const string symbol,const ENUM_TIMEFRAMES tf,
                                const int fast,const int slow,const int signal,
                                ILogger *logger,
                                const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
     : CIntelIndicator("MACD",SRP_IND_MACD,symbol,tf,logger,2,slow+signal+2),
       m_fast(fast),m_slow(slow),m_signal(signal),m_price(price) { }

   bool              Main(const int shift,double &out) const   { return(ValueAt(0,shift,out)); }
   bool              Signal(const int shift,double &out) const { return(ValueAt(1,shift,out)); }
   bool              Histogram(const int shift,double &out) const
     {
      out=0.0;
      double main=0.0,signal=0.0;
      if(!Main(shift,main) || !Signal(shift,signal)) return(false);
      out=main-signal;
      return(true);
     }
   bool              CrossedUp(void) const   { return(BufferCrossedAbove(0,1)); }
   bool              CrossedDown(void) const { return(BufferCrossedBelow(0,1)); }
  };

//+------------------------------------------------------------------+
//| Bollinger Bands - buffer 0 base, 1 upper, 2 lower                  |
//+------------------------------------------------------------------+
class CBollingerIntel : public CIntelIndicator
  {
private:
   int                m_period;
   double             m_deviation;
   ENUM_APPLIED_PRICE m_price;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iBands(m_symbol,m_timeframe,m_period,0,m_deviation,m_price)); }
public:
                     CBollingerIntel(const string symbol,const ENUM_TIMEFRAMES tf,
                                     const int period,const double deviation,
                                     ILogger *logger,
                                     const ENUM_APPLIED_PRICE price=PRICE_CLOSE)
     : CIntelIndicator("BB("+IntegerToString(period)+")",SRP_IND_BOLLINGER,
                       symbol,tf,logger,3,period+2),
       m_period(period),m_deviation(deviation),m_price(price) { }

   //--- iBands orders buffers base/upper/lower, which is easy to get
   //--- wrong. Naming them once removes the risk.
   bool              Middle(const int shift,double &out) const { return(ValueAt(0,shift,out)); }
   bool              Upper(const int shift,double &out) const  { return(ValueAt(1,shift,out)); }
   bool              Lower(const int shift,double &out) const  { return(ValueAt(2,shift,out)); }

   bool              WidthPoints(const int shift,const double point,double &out) const
     {
      out=0.0;
      double upper=0.0,lower=0.0;
      if(!Upper(shift,upper) || !Lower(shift,lower) || point<=0.0) return(false);
      out=(upper-lower)/point;
      return(true);
     }
   //--- %B: where price sits within the bands. 0 = lower, 1 = upper.
   bool              PercentB(const double price,const int shift,double &out) const
     {
      out=0.0;
      double upper=0.0,lower=0.0;
      if(!Upper(shift,upper) || !Lower(shift,lower)) return(false);
      const double width=upper-lower;
      if(width<=0.0) return(false);
      out=(price-lower)/width;
      return(true);
     }
   //--- Squeeze: current width below its own recent average, the
   //--- precondition for a volatility expansion.
   bool              IsSqueezing(const int lookback,const double ratio=0.8) const
     {
      double upper=0.0,lower=0.0;
      if(!Upper(0,upper) || !Lower(0,lower)) return(false);
      const double current=upper-lower;
      double upper_avg=0.0,lower_avg=0.0;
      if(!Average(1,1,lookback,upper_avg)) return(false);
      if(!Average(2,1,lookback,lower_avg)) return(false);
      const double average=upper_avg-lower_avg;
      if(average<=0.0) return(false);
      return(current<average*ratio);
     }
  };

//+------------------------------------------------------------------+
//| CCI                                                               |
//+------------------------------------------------------------------+
class CCciIntel : public CIntelIndicator
  {
private:
   int                m_period;
   ENUM_APPLIED_PRICE m_price;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iCCI(m_symbol,m_timeframe,m_period,m_price)); }
public:
                     CCciIntel(const string symbol,const ENUM_TIMEFRAMES tf,
                               const int period,ILogger *logger,
                               const ENUM_APPLIED_PRICE price=PRICE_TYPICAL)
     : CIntelIndicator("CCI("+IntegerToString(period)+")",SRP_IND_CCI,
                       symbol,tf,logger,1,period+2),
       m_period(period),m_price(price) { }

   bool              IsOverbought(const double threshold=100.0,const int shift=0) const
     {
      double value=0.0;
      if(!ValueAt(0,shift,value)) return(false);
      return(value>=threshold);
     }
   bool              IsOversold(const double threshold=-100.0,const int shift=0) const
     {
      double value=0.0;
      if(!ValueAt(0,shift,value)) return(false);
      return(value<=threshold);
     }
  };

//+------------------------------------------------------------------+
//| Stochastic - buffer 0 main (%K), 1 signal (%D)                     |
//+------------------------------------------------------------------+
class CStochasticIntel : public CIntelIndicator
  {
private:
   int               m_k,m_d,m_slowing;
protected:
   virtual int       OnCreateHandle(void) override
     {
      return(iStochastic(m_symbol,m_timeframe,m_k,m_d,m_slowing,
                         MODE_SMA,STO_LOWHIGH));
     }
public:
                     CStochasticIntel(const string symbol,const ENUM_TIMEFRAMES tf,
                                      const int k_period,const int d_period,
                                      const int slowing,ILogger *logger)
     : CIntelIndicator("Stoch",SRP_IND_STOCHASTIC,symbol,tf,logger,2,
                       k_period+d_period+slowing+2),
       m_k(k_period),m_d(d_period),m_slowing(slowing) { }

   bool              Main(const int shift,double &out) const   { return(ValueAt(0,shift,out)); }
   bool              Signal(const int shift,double &out) const { return(ValueAt(1,shift,out)); }

   bool              IsOverbought(const double threshold=80.0,const int shift=0) const
     {
      double value=0.0;
      if(!Main(shift,value)) return(false);
      return(value>=threshold);
     }
   bool              IsOversold(const double threshold=20.0,const int shift=0) const
     {
      double value=0.0;
      if(!Main(shift,value)) return(false);
      return(value<=threshold);
     }
   bool              CrossedUp(void) const   { return(BufferCrossedAbove(0,1)); }
   bool              CrossedDown(void) const { return(BufferCrossedBelow(0,1)); }
  };

//+------------------------------------------------------------------+
//| Ichimoku - 0 Tenkan, 1 Kijun, 2 SenkouA, 3 SenkouB, 4 Chikou       |
//+------------------------------------------------------------------+
class CIchimokuIntel : public CIntelIndicator
  {
private:
   int               m_tenkan,m_kijun,m_senkou;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iIchimoku(m_symbol,m_timeframe,m_tenkan,m_kijun,m_senkou)); }
public:
                     CIchimokuIntel(const string symbol,const ENUM_TIMEFRAMES tf,
                                    const int tenkan,const int kijun,
                                    const int senkou,ILogger *logger)
     : CIntelIndicator("Ichimoku",SRP_IND_ICHIMOKU,symbol,tf,logger,5,senkou+kijun+2),
       m_tenkan(tenkan),m_kijun(kijun),m_senkou(senkou) { }

   bool              Tenkan(const int shift,double &out) const  { return(ValueAt(0,shift,out)); }
   bool              Kijun(const int shift,double &out) const   { return(ValueAt(1,shift,out)); }
   bool              SenkouA(const int shift,double &out) const { return(ValueAt(2,shift,out)); }
   bool              SenkouB(const int shift,double &out) const { return(ValueAt(3,shift,out)); }
   bool              Chikou(const int shift,double &out) const  { return(ValueAt(4,shift,out)); }

   //--- Cloud boundaries, ordered regardless of which span is on top.
   bool              CloudTop(const int shift,double &out) const
     {
      out=0.0;
      double a=0.0,b=0.0;
      if(!SenkouA(shift,a) || !SenkouB(shift,b)) return(false);
      out=(a>b ? a : b);
      return(true);
     }
   bool              CloudBottom(const int shift,double &out) const
     {
      out=0.0;
      double a=0.0,b=0.0;
      if(!SenkouA(shift,a) || !SenkouB(shift,b)) return(false);
      out=(a<b ? a : b);
      return(true);
     }
   bool              IsPriceAboveCloud(const double price,const int shift=0) const
     {
      double top=0.0;
      if(!CloudTop(shift,top)) return(false);
      return(price>top);
     }
   bool              IsPriceBelowCloud(const double price,const int shift=0) const
     {
      double bottom=0.0;
      if(!CloudBottom(shift,bottom)) return(false);
      return(price<bottom);
     }
  };

//+------------------------------------------------------------------+
//| OBV - cumulative volume flow                                       |
//+------------------------------------------------------------------+
class CObvIntel : public CIntelIndicator
  {
private:
   ENUM_APPLIED_VOLUME m_volume_kind;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iOBV(m_symbol,m_timeframe,m_volume_kind)); }
public:
                     CObvIntel(const string symbol,const ENUM_TIMEFRAMES tf,
                               ILogger *logger,
                               const ENUM_APPLIED_VOLUME volume_kind=VOLUME_TICK)
     : CIntelIndicator("OBV",SRP_IND_OBV,symbol,tf,logger,1,32),
       m_volume_kind(volume_kind) { }

   //--- OBV's absolute level is meaningless; only its direction is.
   bool              IsRising(const int lookback=5) const
     {
      double slope=0.0;
      if(!Slope(0,lookback,slope)) return(false);
      return(slope>0.0);
     }
  };

//+------------------------------------------------------------------+
//| Money Flow Index                                                   |
//+------------------------------------------------------------------+
class CMfiIntel : public CIntelIndicator
  {
private:
   int                 m_period;
   ENUM_APPLIED_VOLUME m_volume_kind;
protected:
   virtual int       OnCreateHandle(void) override
     { return(iMFI(m_symbol,m_timeframe,m_period,m_volume_kind)); }
public:
                     CMfiIntel(const string symbol,const ENUM_TIMEFRAMES tf,
                               const int period,ILogger *logger,
                               const ENUM_APPLIED_VOLUME volume_kind=VOLUME_TICK)
     : CIntelIndicator("MFI("+IntegerToString(period)+")",SRP_IND_MFI,
                       symbol,tf,logger,1,period+2),
       m_period(period),m_volume_kind(volume_kind) { }

   bool              IsOverbought(const double threshold=80.0,const int shift=0) const
     {
      double value=0.0;
      if(!ValueAt(0,shift,value)) return(false);
      return(value>=threshold);
     }
   bool              IsOversold(const double threshold=20.0,const int shift=0) const
     {
      double value=0.0;
      if(!ValueAt(0,shift,value)) return(false);
      return(value<=threshold);
     }
  };

#endif // SRP_INTELLIGENCE_INDICATORS_CSTANDARDINDICATORS_MQH
//+------------------------------------------------------------------+
