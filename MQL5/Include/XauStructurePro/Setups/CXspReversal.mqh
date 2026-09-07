//+------------------------------------------------------------------+
//|                                                 CXspReversal.mqh |
//|                    XauStructurePro - Setups (L4) : S2, reversal |
//|                                                                  |
//|   THE HYPOTHESIS, stated before the run and copied into CHANGELOG:      |
//|   price that pushes through a liquidity pool - a prior-day extreme or    |
//|   a cluster of equal highs/lows - and then closes back inside within a   |
//|   bounded window has failed at that level, and reverts over 5-60         |
//|   minutes rather than continuing.                                       |
//|                                                                  |
//|   THE INVALIDATION IS THE SWEEP EXTREME. If price exceeds the high the   |
//|   sweep printed, the level did not hold and the premise is gone. The     |
//|   stop follows from that (plus a declared 0.20 ATR buffer).             |
//|                                                                  |
//|   PREDICTED FAILURE MODE: dies when the sweep is the START of a trend    |
//|   day rather than a rejection. That is what the H1 context label is for; |
//|   it is recorded, not gated, so the failure mode is measurable instead   |
//|   of assumed away.                                                     |
//|                                                                  |
//|   TWO-SIDED BARS EMIT NOTHING. A window that swept a pool above AND a    |
//|   pool below and closed between them is a genuinely ambiguous            |
//|   occurrence; choosing a side there would be a coin flip wearing the     |
//|   clothes of a signal. Those are counted as Ambiguous() and reported,    |
//|   not silently dropped.                                                |
//+------------------------------------------------------------------+
#ifndef XSP_SETUPS_CXSPREVERSAL_MQH
#define XSP_SETUPS_CXSPREVERSAL_MQH

#include "CXspSetupBase.mqh"
#include "../Liquidity/CXspPools.mqh"

class CXspReversal : public CXspSetupBase
  {
private:
   CXspPools        *m_pools;      // BORROWED, never owned or deleted
   long              m_ambiguous;

public:
                     CXspReversal(void)
     {
      m_pools=NULL;
      m_ambiguous=0;
     }

   void              SetPools(CXspPools *pools) { m_pools=pools; }
   long              Ambiguous(void) const      { return(m_ambiguous); }

protected:
   virtual bool      Detect(const MqlRates &rates[],const int count,
                            const double atr_points,SXspCandidate &out)
     {
      if(m_pools==NULL) return(false);
      const int window=XSP_SWEEP_WINDOW_BARS;
      if(count<window+2) return(false);

      //--- Shifts 1..window: closed bars only. The forming bar at 0 is not
      //--- read, so a sweep cannot be detected from a high that has not
      //--- finished being made.
      double max_high=rates[1].high;
      double min_low =rates[1].low;
      for(int s=2;s<=window;s++)
        {
         if(rates[s].high>max_high) max_high=rates[s].high;
         if(rates[s].low <min_low)  min_low =rates[s].low;
        }
      const double close=rates[1].close;
      //--- The pool must predate the whole window, or the window's own bars
      //--- would be sweeping a level they created.
      const datetime window_start=rates[window].time;

      SXspLevel sell_pool,buy_pool;
      const bool sell_side=FindSwept(max_high,close,window_start,true, sell_pool);
      const bool buy_side =FindSwept(min_low, close,window_start,false,buy_pool);

      if(sell_side && buy_side)
        {
         m_ambiguous++;
         return(false);
        }
      if(!sell_side && !buy_side) return(false);

      const ENUM_XSP_DIR dir=(sell_side?XSP_DIR_SELL:XSP_DIR_BUY);
      SXspLevel pool;
      if(sell_side) pool=sell_pool; else pool=buy_pool;

      out.valid=true;
      out.setup=XSP_SETUP_REVERSAL;
      out.dir=dir;
      out.event_bar_time=rates[1].time;
      out.invalidation=(sell_side?max_high:min_low);   // the sweep extreme
      out.level_price=pool.price;
      out.pool_kind=pool.kind;
      out.atr_points=atr_points;
      //--- Identity is the POOL, not the sweep bar: a pool retested three
      //--- bars later is the same level failing again, and counting it twice
      //--- is the pseudo-replication defect 2 introduced.
      out.fingerprint=m_events.Fingerprint(out.setup,dir,pool.price,pool.origin_time);
      return(true);
     }

private:
   //+---------------------------------------------------------------+
   //| The DEEPEST pool that was penetrated and then rejected.           |
   //|                                                                |
   //| For a sell: the highest pool whose price the window's high         |
   //| exceeded and which the last close is back below. Highest, not      |
   //| nearest: exceeding a pool at 3450 necessarily exceeded every pool   |
   //| beneath it, so the highest one taken out is the strongest form of   |
   //| the claim - and the weaker forms are not separate occurrences.      |
   //|                                                                |
   //| Strict inequalities on both sides. A high that merely TOUCHED the   |
   //| level did not penetrate it, and a close sitting exactly on it has   |
   //| not come back inside.                                            |
   //+---------------------------------------------------------------+
   bool              FindSwept(const double extreme,const double close,
                               const datetime window_start,const bool high_side,
                               SXspLevel &out) const
     {
      bool found=false;
      double best=0.0;
      const int n=m_pools.Count();
      for(int i=0;i<n;i++)
        {
         SXspLevel p;
         if(!m_pools.Get(i,p)) continue;
         if(!p.valid) continue;
         if(CXspPools::IsHighSide(p.kind)!=high_side) continue;
         if(p.origin_time>=window_start) continue;

         if(high_side)
           {
            if(!(extreme>p.price)) continue;   // never penetrated
            if(!(close<p.price))   continue;   // never came back inside
            if(!found || p.price>best) { best=p.price; out=p; found=true; }
           }
         else
           {
            if(!(extreme<p.price)) continue;
            if(!(close>p.price))   continue;
            if(!found || p.price<best) { best=p.price; out=p; found=true; }
           }
        }
      return(found);
     }
  };

#endif // XSP_SETUPS_CXSPREVERSAL_MQH
//+------------------------------------------------------------------+
