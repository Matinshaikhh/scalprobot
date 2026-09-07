//+------------------------------------------------------------------+
//|                                                CXspSetupBase.mqh |
//|             XauStructurePro - Setups (L4) : the template method |
//|                                                                  |
//|   AT MOST TWO SETUPS EVER. Audit 8.2 caps it there, and the reason is   |
//|   arithmetic rather than taste: every additional setup multiplies the    |
//|   comparisons run against one 9.1-month DEV sample without multiplying   |
//|   the evidence in it. Two hypotheses on 9 months is a study; six is a    |
//|   search, and a search over one sample finds whatever that sample        |
//|   happens to contain.                                                  |
//|                                                                  |
//|   THE SHAPE. Evaluate() is the template method and is FINAL in spirit:   |
//|   subclasses override Detect() only. Every candidate therefore passes    |
//|   through the SAME fingerprint claim on its way out, so a subclass       |
//|   cannot - even by omission - emit an occurrence twice. Defect 2 was     |
//|   possible because the check lived at the call site; here there is no    |
//|   call site that can skip it.                                          |
//+------------------------------------------------------------------+
#ifndef XSP_SETUPS_CXSPSETUPBASE_MQH
#define XSP_SETUPS_CXSPSETUPBASE_MQH

#include "../Core/XspTypes.mqh"
#include "../Liquidity/CXspStructureEvents.mqh"

class CXspSetupBase
  {
protected:
   string                m_symbol;
   ENUM_TIMEFRAMES       m_tf;
   double                m_point;
   CXspStructureEvents  *m_events;    // BORROWED, never owned or deleted
   long                  m_detected;
   long                  m_emitted;
   long                  m_suppressed;

public:
                     CXspSetupBase(void)
     {
      m_symbol="";
      m_tf=XSP_TF_SETUP;
      m_point=0.0;
      m_events=NULL;
      m_detected=0;
      m_emitted=0;
      m_suppressed=0;
     }

   virtual          ~CXspSetupBase(void) { }

   bool              Initialize(const string symbol,const ENUM_TIMEFRAMES tf,
                                const double point,CXspStructureEvents *events)
     {
      m_symbol=symbol;
      m_tf=tf;
      m_point=point;
      m_events=events;
      if(m_point<=0.0) return(false);
      if(m_events==NULL)
        {
         Print("XSP_SETUP FAIL event registry is NULL - one occurrence could be emitted twice");
         return(false);
        }
      return(true);
     }

   long              Detected(void)   const { return(m_detected); }
   long              Emitted(void)    const { return(m_emitted); }
   long              Suppressed(void) const { return(m_suppressed); }

   //+---------------------------------------------------------------+
   //| THE TEMPLATE METHOD. Subclasses override Detect() and nothing     |
   //| else, so every candidate is fingerprinted on the way out.         |
   //|                                                                |
   //| rates is series-indexed with index 0 the FORMING bar, so every     |
   //| subclass reads index 1 and higher. There is no path in this file   |
   //| that reads index 0, and none that indexes negatively, which is a   |
   //| stronger lookahead guarantee than auditing arithmetic for signs.   |
   //+---------------------------------------------------------------+
   bool              Evaluate(const MqlRates &rates[],const int count,
                              const double atr_points,SXspCandidate &out)
     {
      out.Reset();
      if(m_events==NULL || m_point<=0.0) return(false);
      if(count<2 || atr_points<=0.0) return(false);

      if(!Detect(rates,count,atr_points,out) || !out.valid)
        {
         out.Reset();
         return(false);
        }
      m_detected++;

      //--- One occurrence, one emission. A refusal here is the normal case
      //--- while price stays beyond a level, not an error: it is the exact
      //--- duplicate that inflated n in the old tree.
      if(!m_events.Claim(out.fingerprint))
        {
         m_suppressed++;
         out.Reset();
         return(false);
        }
      m_emitted++;
      return(true);
     }

   //+---------------------------------------------------------------+
   //| Stop distance in POINTS, derived from the invalidation - never    |
   //| chosen. Audit 8.2 L3: the invalidation is located first and the    |
   //| stop follows from it, because a stop picked to fit a target is a    |
   //| number selected on the data.                                     |
   //|                                                                |
   //| Returns 0 when the invalidation is already on the wrong side of    |
   //| the first available price - a gap through the level between the     |
   //| bar close and the next tick. NOT clamped: a clamped stop is a       |
   //| different hypothesis from the pre-registered one, and the tracker    |
   //| counts the refusal so the census still adds up.                     |
   //+---------------------------------------------------------------+
   static double     StopPoints(const double ref_entry,const double invalidation,
                                const ENUM_XSP_DIR dir,const double atr_points,
                                const double point)
     {
      if(point<=0.0 || atr_points<=0.0) return(0.0);
      if(dir==XSP_DIR_BUY  && !(invalidation<ref_entry)) return(0.0);
      if(dir==XSP_DIR_SELL && !(invalidation>ref_entry)) return(0.0);
      const double raw=MathAbs(ref_entry-invalidation)/point;
      return(raw+XSP_STOP_BUFFER_ATR*atr_points);
     }

protected:
   virtual bool      Detect(const MqlRates &rates[],const int count,
                            const double atr_points,SXspCandidate &out)
     {
      return(false);
     }
  };

#endif // XSP_SETUPS_CXSPSETUPBASE_MQH
//+------------------------------------------------------------------+
