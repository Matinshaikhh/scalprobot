//+------------------------------------------------------------------+
//|                                        COrderFlowStrategy.mqh |
//|                        Scalping Robot Pro - Decision Engine (P3) |
//|                                                                  |
//|   ORDER FLOW / VOLUME DELTA.                                        |
//|                                                                  |
//|   WHAT "ORDER FLOW" MEANS HERE, HONESTLY.                            |
//|   A retail MT5 feed has no exchange order book and no real trade      |
//|   tape for a CFD/spot symbol like XAUUSD - there is no Level 2 to     |
//|   read and no genuine bid/ask executed-volume split. Claiming true    |
//|   institutional order-flow data on this stack would be fiction.       |
//|                                                                  |
//|   What IS real and available everywhere MT5 runs is TICK VOLUME       |
//|   (trade/quote count per bar), and two well-established indicators    |
//|   built from it: On-Balance Volume (cumulative signed volume - a      |
//|   classic accumulation/distribution proxy) and the Money Flow Index   |
//|   (a volume-weighted RSI). Both were already built, initialised and   |
//|   refreshed every tick by CProductionEngine (m_obv, m_mfi) and wired  |
//|   into CStrategyContext - and then never read by anything. This        |
//|   plugin is what finally uses them, combined with the relative-       |
//|   volume reader every other plugin already relies on for              |
//|   participation.                                                      |
//|                                                                  |
//|   THE PREMISE: cumulative volume flowing in the trade's direction      |
//|   (OBV rising for a buy), while the Money Flow Index confirms that     |
//|   flow is neither exhausted (already extreme) nor stalling             |
//|   (falling back toward neutral), and current volume is at least in    |
//|   line with the recent average, is evidence of real participation      |
//|   behind a move rather than a thin, noise-driven tick.                |
//+------------------------------------------------------------------+
#ifndef SRP_DECISION_STRATEGIES_CORDERFLOWSTRATEGY_MQH
#define SRP_DECISION_STRATEGIES_CORDERFLOWSTRATEGY_MQH

#include "CStrategyPlugin.mqh"

//+------------------------------------------------------------------+
class COrderFlowStrategy : public CStrategyPlugin
  {
private:
   int               m_obv_lookback;      // bars OBV slope is measured over
   double            m_mfi_overbought;    // ceiling of the usable bullish zone
   double            m_mfi_oversold;      // floor of the usable bearish zone
   double            m_min_volume_ratio;  // participation floor (x average)
   int               m_volume_lookback;

protected:
   virtual bool      OnEvaluate(const SDecisionInput &snapshot,
                                SStrategySignal &signal) override;
   virtual bool      OnValidate(SValidationResult &result) override;

public:
                     COrderFlowStrategy(CStrategyContext *context,ILogger *logger)
     : CStrategyPlugin("OrderFlow",SRP_STRAT_ORDER_FLOW,context,logger),
       m_obv_lookback(10),
       m_mfi_overbought(80.0),
       m_mfi_oversold(20.0),
       m_min_volume_ratio(0.90),
       m_volume_lookback(20) { }

   void              SetObvLookback(const int bars)
     { if(bars>=2) m_obv_lookback=bars; }
   void              SetMfiBounds(const double oversold,const double overbought)
     {
      if(oversold>0.0 && oversold<50.0)   m_mfi_oversold=oversold;
      if(overbought>50.0 && overbought<100.0) m_mfi_overbought=overbought;
     }
   void              SetMinVolumeRatio(const double ratio)
     { if(ratio>=0.0) m_min_volume_ratio=ratio; }
   void              SetVolumeLookback(const int bars)
     { if(bars>=2) m_volume_lookback=bars; }
  };
//+------------------------------------------------------------------+
bool COrderFlowStrategy::OnValidate(SValidationResult &result)
  {
   if(m_context.Obv()==NULL)
     {
      result.AddError(m_name+": requires On-Balance Volume");
      return(false);
     }
   if(m_context.Mfi()==NULL)
     {
      result.AddError(m_name+": requires Money Flow Index");
      return(false);
     }
   if(m_mfi_oversold>=m_mfi_overbought)
     {
      result.AddError(m_name+": MFI oversold bound must be below the "
                      "overbought bound");
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
bool COrderFlowStrategy::OnEvaluate(const SDecisionInput &snapshot,
                                    SStrategySignal &signal)
  {
   CObvIntel *obv=m_context.Obv();
   CMfiIntel *mfi=m_context.Mfi();
   if(obv==NULL || mfi==NULL || !obv.IsReady() || !mfi.IsReady())
      return(false);

   //--- CUMULATIVE FLOW DIRECTION. The level of OBV is meaningless; only
   //--- its slope over the lookback window says anything.
   double slope=0.0;
   if(!obv.Slope(0,m_obv_lookback,slope) || slope==0.0)
      return(false);

   //--- MFI: current and previous, so the flow can be required to be
   //--- STRENGTHENING in the trade direction, not merely on the right
   //--- side of neutral by accident.
   double mfi_now=0.0,mfi_prev=0.0;
   if(!mfi.ValueAt(0,0,mfi_now) || !mfi.ValueAt(0,1,mfi_prev))
      return(false);

   //--- BULLISH: cumulative volume accumulating, money flow above neutral
   //--- but not already exhausted at the overbought ceiling, and rising.
   const bool bullish_flow=(slope>0.0 && mfi_now>50.0 &&
                            mfi_now<m_mfi_overbought && mfi_now>=mfi_prev);
   //--- BEARISH: the mirror image.
   const bool bearish_flow=(slope<0.0 && mfi_now<50.0 &&
                            mfi_now>m_mfi_oversold && mfi_now<=mfi_prev);
   if(!bullish_flow && !bearish_flow)
      return(false);

   const ENUM_SRP_DECISION decision=(bullish_flow ? SRP_DECISION_BUY
                                                  : SRP_DECISION_SELL);

   //--- PARTICIPATION GATE. Flow direction without volume behind it is
   //--- the thin-tick artifact this whole plugin exists to avoid trading.
   double relative_volume=0.0;
   const bool has_volume=m_context.RelativeVolume(m_volume_lookback,
                                                   relative_volume);
   if(has_volume && m_min_volume_ratio>0.0 &&
      relative_volume<m_min_volume_ratio)
      return(false);

   //--- CONFIDENCE from three independent components, the same pattern
   //--- every other plugin uses so scores stay comparable across the vote.
   double score=0.0;
   int components=0;

   //--- 1. MFI's distance from neutral in the trade's direction. Capped at
   //--- 35 points past 50 (i.e. saturates at MFI 85 or MFI 15), which is
   //--- deliberately inside the overbought/oversold bounds so the score
   //--- never rewards the exhausted extreme this plugin already refuses.
   const double mfi_extension=MathAbs(mfi_now-50.0);
   score+=CMathUtils::Clamp(mfi_extension/35.0,0.0,1.0);
   components++;

   //--- 2. Participation.
   if(has_volume)
     {
      score+=CMathUtils::Clamp(relative_volume/2.0,0.0,1.0);
      components++;
     }

   //--- 3. Structural agreement, when available - the same premise
   //--- CEmaCrossStrategy uses: flow with the structure is worth more than
   //--- flow fighting it.
   if(snapshot.structure_valid)
     {
      const bool structure_agrees=
         (decision==SRP_DECISION_BUY ? snapshot.structure.IsBullish()
                                     : snapshot.structure.IsBearish());
      score+=(structure_agrees ? 1.0 : 0.25);
      components++;
     }

   score+=snapshot.session.liquidity_score;
   components++;

   const double confidence=(components>0 ? score/(double)components : 0.0);
   const string reason=StringFormat(
      "order flow: OBV %s (%.0f/%d bars), MFI %.1f%s%s",
      (bullish_flow ? "accumulating" : "distributing"),
      slope,m_obv_lookback,mfi_now,
      (mfi_now>=mfi_prev ? " rising" : " falling"),
      (has_volume ? StringFormat(", vol x%.2f",relative_volume) : ""));

   Emit(signal,snapshot,decision,confidence,reason,
        RatingFromConfidence(confidence));
   return(true);
  }

#endif // SRP_DECISION_STRATEGIES_CORDERFLOWSTRATEGY_MQH
//+------------------------------------------------------------------+
