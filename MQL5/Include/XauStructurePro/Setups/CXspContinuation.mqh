//+------------------------------------------------------------------+
//|                                             CXspContinuation.mqh |
//|                XauStructurePro - Setups (L4) : S1, continuation |
//|                                                                  |
//|   THE HYPOTHESIS, stated before the run and copied into CHANGELOG:      |
//|   an M15 bar that expands well beyond its own recent volatility, with   |
//|   a body that dominates its range and a close pinned at the extreme,    |
//|   marks a leg that continues rather than reverts, over 5-60 minutes.     |
//|                                                                  |
//|   THE INVALIDATION IS THE LEG ORIGIN. For a bullish leg that is the      |
//|   displacement bar's LOW: if price returns there the leg did not hold,   |
//|   and there is nothing left of the premise. The stop follows from that   |
//|   level (plus a declared 0.20 ATR buffer) and is not chosen.            |
//|                                                                  |
//|   H1 ALIGNMENT IS NOT TESTED HERE. It is recorded as a label by the      |
//|   study EA. Gating on it would delete the H1-disagreeing population and  |
//|   with it any way to measure what H1 alignment is worth against its own  |
//|   standard error, which is what audit 9.3 requires before a component     |
//|   may be kept.                                                         |
//|                                                                  |
//|   PREDICTED FAILURE MODE: dies in the low realised-volatility deciles,   |
//|   where a bar can clear 1.5x a small ATR without anything having         |
//|   happened, so the "displacement" is noise wearing the right shape.      |
//|                                                                  |
//|   Thresholds are XSP's own re-declaration, not SRP's                    |
//|   CDisplacementDetector defaults - see XspConstants.mqh.                |
//+------------------------------------------------------------------+
#ifndef XSP_SETUPS_CXSPCONTINUATION_MQH
#define XSP_SETUPS_CXSPCONTINUATION_MQH

#include "CXspSetupBase.mqh"

class CXspContinuation : public CXspSetupBase
  {
protected:
   virtual bool      Detect(const MqlRates &rates[],const int count,
                            const double atr_points,SXspCandidate &out)
     {
      //--- Index 1 is the last CLOSED bar. Index 0 is forming and is never
      //--- read: its high, low and close can all still change.
      if(count<3) return(false);
      const double high =rates[1].high;
      const double low  =rates[1].low;
      const double open =rates[1].open;
      const double close=rates[1].close;

      const double range=high-low;
      if(range<=XSP_EPSILON) return(false);

      //--- 1. Expansion against the bar's OWN recent volatility. atr_points
      //--- is read at shift 1 by the caller, i.e. the ATR as it stood on the
      //--- bar under test - not the current ATR, which already contains this
      //--- bar and would make every large bar look ordinary.
      const double range_points=range/m_point;
      if(range_points<XSP_DISP_ATR_MULT*atr_points) return(false);

      //--- 2. The move is directional, not a wick in both directions.
      const double body=MathAbs(close-open);
      if(body/range<XSP_DISP_BODY_RATIO) return(false);

      const ENUM_XSP_DIR dir=(close>open?XSP_DIR_BUY:
                              (close<open?XSP_DIR_SELL:XSP_DIR_NONE));
      if(dir==XSP_DIR_NONE) return(false);

      //--- 3. The close holds the extreme. A bar that expanded and gave it
      //--- all back is a rejection, and reading it as continuation is how a
      //--- reversal bar gets traded in the direction it just failed in.
      const double close_pos=(dir==XSP_DIR_BUY?(close-low):(high-close))/range;
      if(close_pos<XSP_DISP_CLOSE_POS) return(false);

      const double invalidation=(dir==XSP_DIR_BUY?low:high);

      out.valid=true;
      out.setup=XSP_SETUP_CONTINUATION;
      out.dir=dir;
      out.event_bar_time=rates[1].time;
      out.invalidation=invalidation;
      out.level_price=invalidation;      // the leg origin IS the level
      out.pool_kind=XSP_POOL_NONE;       // S1 does not reference a pool
      out.atr_points=atr_points;
      //--- Identity is the leg origin and the bar that made it, so the same
      //--- displacement cannot be claimed on a later evaluation.
      out.fingerprint=m_events.Fingerprint(out.setup,dir,invalidation,rates[1].time);
      return(true);
     }
  };

#endif // XSP_SETUPS_CXSPCONTINUATION_MQH
//+------------------------------------------------------------------+
