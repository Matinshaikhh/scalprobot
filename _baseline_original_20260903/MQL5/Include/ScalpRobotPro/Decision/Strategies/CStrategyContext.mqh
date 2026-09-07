//+------------------------------------------------------------------+
//|                                          CStrategyContext.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   RESPONSIBILITY (one only): hold BORROWED pointers to every Phase 2   |
//|   module a strategy might read, so plugins receive one object instead  |
//|   of a dozen constructor parameters.                                  |
//|                                                                  |
//|   WHY THIS EXISTS                                                    |
//|   Ten strategies each needing five different indicators would mean    |
//|   fifty constructor arguments and a signature change every time a new  |
//|   data source appears. With one context, adding a module never        |
//|   touches an existing strategy - the Open/Closed Principle applied to |
//|   the plugin contract.                                              |
//|                                                                  |
//|   OWNERSHIP: every pointer here is BORROWED. This class deletes        |
//|   nothing. Phase 2 modules are owned by whoever created them, and a    |
//|   strategy must never delete anything it reads.                       |
//|                                                                  |
//|   Every convenience reader is null-safe, so a strategy that asks for  |
//|   a module the host did not wire gets a clean false rather than a      |
//|   crash. That is what lets strategies be enabled independently of      |
//|   which indicators the host chose to build.                           |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_STRATEGIES_CSTRATEGYCONTEXT_MQH
#define SRP_DECISION_STRATEGIES_CSTRATEGYCONTEXT_MQH

#include "../../Intelligence/Indicators/CStandardIndicators.mqh"
#include "../../Intelligence/Indicators/CComputedIndicators.mqh"
#include "../../Intelligence/Structure/CSwingDetector.mqh"
#include "../../Intelligence/Structure/CMarketStructure.mqh"
#include "../../Intelligence/SmartMoney/CZoneRegistry.mqh"
#include "../../Intelligence/SmartMoney/CDisplacementDetector.mqh"
#include "../../Intelligence/SmartMoney/CLiquidityDetector.mqh"
#include "../Types/DecisionStructs.mqh"

class CStrategyContext
  {
private:
   //--- All BORROWED. Never deleted by this class.
   CEmaIndicator          *m_ema_fast;
   CEmaIndicator          *m_ema_slow;
   CEmaIndicator          *m_ema_trend;
   CSmaIndicator          *m_sma;
   CAtrIntel              *m_atr;
   CRsiIntel              *m_rsi;
   CAdxIntel              *m_adx;
   CMacdIntel             *m_macd;
   CBollingerIntel        *m_bollinger;
   CCciIntel              *m_cci;
   CStochasticIntel       *m_stochastic;
   CIchimokuIntel         *m_ichimoku;
   CObvIntel              *m_obv;
   CMfiIntel              *m_mfi;
   CVwapIndicator         *m_vwap;
   CVolumeIndicator       *m_volume;
   CSwingDetector         *m_swings;
   CMarketStructure       *m_structure;
   CZoneRegistry          *m_zones;
   CDisplacementDetector  *m_displacement;
   CLiquidityDetector     *m_liquidity;

public:
                     CStrategyContext(void);
                    ~CStrategyContext(void) { }

   //--- Wiring. The host calls whichever apply; unset modules simply
   //--- report unavailable.
   void              SetEmaSet(CEmaIndicator *fast,CEmaIndicator *slow,
                               CEmaIndicator *trend);
   void              SetSma(CSmaIndicator *sma)                 { m_sma=sma; }
   void              SetAtr(CAtrIntel *atr)                     { m_atr=atr; }
   void              SetRsi(CRsiIntel *rsi)                     { m_rsi=rsi; }
   void              SetAdx(CAdxIntel *adx)                     { m_adx=adx; }
   void              SetMacd(CMacdIntel *macd)                  { m_macd=macd; }
   void              SetBollinger(CBollingerIntel *bands)       { m_bollinger=bands; }
   void              SetCci(CCciIntel *cci)                     { m_cci=cci; }
   void              SetStochastic(CStochasticIntel *stoch)     { m_stochastic=stoch; }
   void              SetIchimoku(CIchimokuIntel *ichimoku)      { m_ichimoku=ichimoku; }
   void              SetObv(CObvIntel *obv)                     { m_obv=obv; }
   void              SetMfi(CMfiIntel *mfi)                     { m_mfi=mfi; }
   void              SetVwap(CVwapIndicator *vwap)              { m_vwap=vwap; }
   void              SetVolume(CVolumeIndicator *volume)        { m_volume=volume; }
   void              SetSwings(CSwingDetector *swings)          { m_swings=swings; }
   void              SetStructure(CMarketStructure *structure)  { m_structure=structure; }
   void              SetZones(CZoneRegistry *zones)             { m_zones=zones; }
   void              SetDisplacement(CDisplacementDetector *d)  { m_displacement=d; }
   void              SetLiquidity(CLiquidityDetector *liquidity){ m_liquidity=liquidity; }

   //--- Access. All may return NULL; callers must check.
   CEmaIndicator         *EmaFast(void)      const { return(m_ema_fast); }
   CEmaIndicator         *EmaSlow(void)      const { return(m_ema_slow); }
   CEmaIndicator         *EmaTrend(void)     const { return(m_ema_trend); }
   CSmaIndicator         *Sma(void)          const { return(m_sma); }
   CAtrIntel             *Atr(void)          const { return(m_atr); }
   CRsiIntel             *Rsi(void)          const { return(m_rsi); }
   CAdxIntel             *Adx(void)          const { return(m_adx); }
   CMacdIntel            *Macd(void)         const { return(m_macd); }
   CBollingerIntel       *Bollinger(void)    const { return(m_bollinger); }
   CCciIntel             *Cci(void)          const { return(m_cci); }
   CStochasticIntel      *Stochastic(void)   const { return(m_stochastic); }
   CIchimokuIntel        *Ichimoku(void)     const { return(m_ichimoku); }
   CObvIntel             *Obv(void)          const { return(m_obv); }
   CMfiIntel             *Mfi(void)          const { return(m_mfi); }
   CVwapIndicator        *Vwap(void)         const { return(m_vwap); }
   CVolumeIndicator      *Volume(void)       const { return(m_volume); }
   CSwingDetector        *Swings(void)       const { return(m_swings); }
   CMarketStructure      *Structure(void)    const { return(m_structure); }
   CZoneRegistry         *Zones(void)        const { return(m_zones); }
   CDisplacementDetector *Displacement(void) const { return(m_displacement); }
   CLiquidityDetector    *Liquidity(void)    const { return(m_liquidity); }

   //--- Null-safe convenience readers. These are what strategies actually
   //--- use: each returns false when the module is absent OR not ready,
   //--- so a strategy never has to distinguish the two by hand.
   bool              AtrValue(double &out) const;
   bool              AtrPoints(const double point,double &out) const;
   bool              RsiValue(double &out) const;
   bool              AdxValue(double &out) const;
   bool              AdxDi(double &plus,double &minus) const;
   bool              MacdHistogram(double &out) const;
   bool              VwapValue(double &out) const;
   bool              RelativeVolume(const int lookback,double &out) const;
   bool              EmaValues(double &fast,double &slow) const;
   bool              EmaTrendValue(double &out) const;
   bool              BollingerBands(double &upper,double &middle,double &lower) const;

   bool              Validate(SValidationResult &result) const;
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CStrategyContext::CStrategyContext(void)
  : m_ema_fast(NULL),
    m_ema_slow(NULL),
    m_ema_trend(NULL),
    m_sma(NULL),
    m_atr(NULL),
    m_rsi(NULL),
    m_adx(NULL),
    m_macd(NULL),
    m_bollinger(NULL),
    m_cci(NULL),
    m_stochastic(NULL),
    m_ichimoku(NULL),
    m_obv(NULL),
    m_mfi(NULL),
    m_vwap(NULL),
    m_volume(NULL),
    m_swings(NULL),
    m_structure(NULL),
    m_zones(NULL),
    m_displacement(NULL),
    m_liquidity(NULL)
  {
  }
//+------------------------------------------------------------------+
void CStrategyContext::SetEmaSet(CEmaIndicator *fast,CEmaIndicator *slow,
                                 CEmaIndicator *trend)
  {
   m_ema_fast=fast;
   m_ema_slow=slow;
   m_ema_trend=trend;
  }
//+------------------------------------------------------------------+
bool CStrategyContext::AtrValue(double &out) const
  {
   out=0.0;
   if(m_atr==NULL || !m_atr.IsReady())
      return(false);
   return(m_atr.ValueAt(0,0,out) && out>0.0);
  }
//+------------------------------------------------------------------+
bool CStrategyContext::AtrPoints(const double point,double &out) const
  {
   out=0.0;
   if(point<=0.0)
      return(false);
   double atr=0.0;
   if(!AtrValue(atr))
      return(false);
   out=atr/point;
   return(out>0.0);
  }
//+------------------------------------------------------------------+
bool CStrategyContext::RsiValue(double &out) const
  {
   out=0.0;
   if(m_rsi==NULL || !m_rsi.IsReady())
      return(false);
   return(m_rsi.ValueAt(0,0,out));
  }
//+------------------------------------------------------------------+
bool CStrategyContext::AdxValue(double &out) const
  {
   out=0.0;
   if(m_adx==NULL || !m_adx.IsReady())
      return(false);
   return(m_adx.Main(0,out));
  }
//+------------------------------------------------------------------+
bool CStrategyContext::AdxDi(double &plus,double &minus) const
  {
   plus=0.0;
   minus=0.0;
   if(m_adx==NULL || !m_adx.IsReady())
      return(false);
   return(m_adx.PlusDi(0,plus) && m_adx.MinusDi(0,minus));
  }
//+------------------------------------------------------------------+
bool CStrategyContext::MacdHistogram(double &out) const
  {
   out=0.0;
   if(m_macd==NULL || !m_macd.IsReady())
      return(false);
   return(m_macd.Histogram(0,out));
  }
//+------------------------------------------------------------------+
bool CStrategyContext::VwapValue(double &out) const
  {
   out=0.0;
   if(m_vwap==NULL || !m_vwap.IsReady())
      return(false);
   return(m_vwap.Value(0,out) && out>0.0);
  }
//+------------------------------------------------------------------+
bool CStrategyContext::RelativeVolume(const int lookback,double &out) const
  {
   out=0.0;
   if(m_volume==NULL || !m_volume.IsReady())
      return(false);
   return(m_volume.RelativeVolume(lookback,out));
  }
//+------------------------------------------------------------------+
bool CStrategyContext::EmaValues(double &fast,double &slow) const
  {
   fast=0.0;
   slow=0.0;
   if(m_ema_fast==NULL || m_ema_slow==NULL)
      return(false);
   if(!m_ema_fast.IsReady() || !m_ema_slow.IsReady())
      return(false);
   return(m_ema_fast.ValueAt(0,0,fast) && m_ema_slow.ValueAt(0,0,slow));
  }
//+------------------------------------------------------------------+
bool CStrategyContext::EmaTrendValue(double &out) const
  {
   out=0.0;
   if(m_ema_trend==NULL || !m_ema_trend.IsReady())
      return(false);
   return(m_ema_trend.ValueAt(0,0,out));
  }
//+------------------------------------------------------------------+
bool CStrategyContext::BollingerBands(double &upper,double &middle,
                                      double &lower) const
  {
   upper=0.0;
   middle=0.0;
   lower=0.0;
   if(m_bollinger==NULL || !m_bollinger.IsReady())
      return(false);
   return(m_bollinger.Upper(0,upper) &&
          m_bollinger.Middle(0,middle) &&
          m_bollinger.Lower(0,lower));
  }
//+------------------------------------------------------------------+
bool CStrategyContext::Validate(SValidationResult &result) const
  {
   //--- ATR is the one genuinely universal dependency: sizing, stops,
   //--- displacement and most confirmations all need it.
   if(m_atr==NULL)
      result.AddWarning("CStrategyContext: no ATR wired; volatility-dependent "
                        "strategies and confirmations will abstain");
   if(m_structure==NULL)
      result.AddWarning("CStrategyContext: no market structure wired; "
                        "structure-dependent strategies will abstain");
   if(m_volume==NULL)
      result.AddWarning("CStrategyContext: no volume wired; volume "
                        "confirmation will report unavailable");
   return(true);
  }
//+------------------------------------------------------------------+
string CStrategyContext::Describe(void) const
  {
   //--- Lists what is actually wired, which is the first thing to check
   //--- when a strategy unexpectedly abstains.
   string wired="";
   if(m_ema_fast!=NULL)     wired+="emaFast ";
   if(m_ema_slow!=NULL)     wired+="emaSlow ";
   if(m_ema_trend!=NULL)    wired+="emaTrend ";
   if(m_sma!=NULL)          wired+="sma ";
   if(m_atr!=NULL)          wired+="atr ";
   if(m_rsi!=NULL)          wired+="rsi ";
   if(m_adx!=NULL)          wired+="adx ";
   if(m_macd!=NULL)         wired+="macd ";
   if(m_bollinger!=NULL)    wired+="bb ";
   if(m_cci!=NULL)          wired+="cci ";
   if(m_stochastic!=NULL)   wired+="stoch ";
   if(m_ichimoku!=NULL)     wired+="ichimoku ";
   if(m_obv!=NULL)          wired+="obv ";
   if(m_mfi!=NULL)          wired+="mfi ";
   if(m_vwap!=NULL)         wired+="vwap ";
   if(m_volume!=NULL)       wired+="volume ";
   if(m_swings!=NULL)       wired+="swings ";
   if(m_structure!=NULL)    wired+="structure ";
   if(m_zones!=NULL)        wired+="zones ";
   if(m_displacement!=NULL) wired+="displacement ";
   if(m_liquidity!=NULL)    wired+="liquidity ";
   if(StringLen(wired)==0)
      wired="(nothing wired)";
   return("context: "+wired);
  }

#endif // SRP_DECISION_STRATEGIES_CSTRATEGYCONTEXT_MQH
//+------------------------------------------------------------------+
