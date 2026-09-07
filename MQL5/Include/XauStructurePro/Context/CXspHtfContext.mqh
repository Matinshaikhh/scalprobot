//+------------------------------------------------------------------+
//|                                               CXspHtfContext.mqh |
//|      XauStructurePro - Context (L1) : H1/H4 alignment as a LABEL |
//|                                                                  |
//|   RECORDED, NOT GATED. Audit 8.2 puts higher-timeframe context at L1     |
//|   and lets it veto; in Phase A a veto would delete the counterfactual.   |
//|   If H1-disagreeing instances are never recorded, then the question      |
//|   "does H1 alignment help, and by how much relative to its standard      |
//|   error" has no data behind it, and section 9.3's acceptance rule -       |
//|   keep a component only if it improves expectancy by MORE than its SE -   |
//|   cannot be applied to the one component the whole design leans on.       |
//|                                                                  |
//|   So both populations are recorded and the filter is measured once,       |
//|   afterwards, on one sample - instead of one backtest per filter, which   |
//|   is the parameter sweep audit 4.4 already showed buys nothing.           |
//+------------------------------------------------------------------+
#ifndef XSP_CONTEXT_CXSPHTFCONTEXT_MQH
#define XSP_CONTEXT_CXSPHTFCONTEXT_MQH

#include "CXspSwings.mqh"

class CXspHtfContext
  {
private:
   CXspSwings        m_h1;
   CXspSwings        m_h4;
   bool              m_ready;

public:
                     CXspHtfContext(void) { m_ready=false; }

   bool              Initialize(const string symbol)
     {
      //--- Strength 2 on H1/H4, not 3. A strength-3 H4 swing needs three
      //--- closed H4 bars on each side - half a trading week of confirmation
      //--- delay before the context can say anything. At a 5-60 minute
      //--- holding horizon that context would describe a market that has
      //--- already moved on.
      if(!m_h1.Initialize(symbol,XSP_TF_CONTEXT,2,400)) return(false);
      if(!m_h4.Initialize(symbol,XSP_TF_HIGHER,2,300))  return(false);
      m_ready=true;
      return(true);
     }

   bool              Refresh(void)
     {
      if(!m_ready) return(false);
      const bool a=m_h1.Refresh();
      const bool b=m_h4.Refresh();
      return(a && b);
     }

   ENUM_XSP_TREND    H1Trend(void) const { return(m_h1.Classify()); }
   ENUM_XSP_TREND    H4Trend(void) const { return(m_h4.Classify()); }
   int               H1SwingHighs(void) const { return(m_h1.HighCount()); }
   int               H1SwingLows(void)  const { return(m_h1.LowCount()); }

   //--- Does a structural class agree with a trade direction? CHOP agrees
   //--- with neither: it is a third state, not a weak version of trending,
   //--- and folding it into "aligned" would put the population the S1
   //--- hypothesis predicts will fail into the bucket predicted to work.
   static bool       Agrees(const ENUM_XSP_TREND trend,const ENUM_XSP_DIR dir)
     {
      if(dir==XSP_DIR_BUY)  return(trend==XSP_TREND_UP);
      if(dir==XSP_DIR_SELL) return(trend==XSP_TREND_DOWN);
      return(false);
     }

   bool              Snapshot(const ENUM_XSP_DIR dir,const double price,SXspContext &out) const
     {
      out.Reset();
      if(!m_ready) return(false);
      out.h1_trend=H1Trend();
      out.h4_trend=H4Trend();
      out.h1_aligned=Agrees(out.h1_trend,dir);
      out.h4_aligned=Agrees(out.h4_trend,dir);
      out.h1_range_pos=m_h1.RangePosition(price);
      out.valid=true;
      return(true);
     }

   string            Describe(void) const
     {
      return(StringFormat("context %s | %s",m_h1.Describe(),m_h4.Describe()));
     }
  };

#endif // XSP_CONTEXT_CXSPHTFCONTEXT_MQH
//+------------------------------------------------------------------+
