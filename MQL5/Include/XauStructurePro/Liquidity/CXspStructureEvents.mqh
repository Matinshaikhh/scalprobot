//+------------------------------------------------------------------+
//|                                          CXspStructureEvents.mqh |
//|          XauStructurePro - Liquidity : EVENT IDENTITY, the fix to |
//|                                        defect 2 of the SRP audit. |
//|                                                                  |
//|   THE DEFECT, VERBATIM FROM THE OLD TREE                              |
//|   CMarketStructure.mqh lines 238-286 test level STATE:                |
//|                                                                  |
//|       const bool broke_high=(current_price>m_state.last_high.price+buf);
//|       ...                                                             |
//|       m_state.last_event_time=TimeCurrent();                          |
//|                                                                  |
//|   broke_high stays true for as long as price remains beyond the level,  |
//|   and last_event_time is re-stamped on every evaluation. ONE market     |
//|   occurrence therefore produced N records. n rose, SE = sqrt(p(1-p)/n)  |
//|   fell, and statistical significance was manufactured out of a single   |
//|   event observed repeatedly. That is not a rounding error in the old    |
//|   results; it is the mechanism by which they could look decisive.       |
//|                                                                  |
//|   THE FIX                                                             |
//|   A level is claimed ONCE, by fingerprint, at the first CLOSED bar      |
//|   beyond it. A second claim on the same fingerprint is refused, for as  |
//|   long as the registry remembers it. "Price is still beyond the level"  |
//|   is available as IsBeyond() - a STATE query that can never emit an     |
//|   event, so the two concepts cannot be confused at a call site.         |
//|                                                                  |
//|   The old class is NOT patched. SRP 1.11 is the section-9.5 comparison  |
//|   baseline and must stay byte-identical.                               |
//+------------------------------------------------------------------+
#ifndef XSP_LIQUIDITY_CXSPSTRUCTUREEVENTS_MQH
#define XSP_LIQUIDITY_CXSPSTRUCTUREEVENTS_MQH

#include "../Core/XspTypes.mqh"

//--- Ring capacity. A fingerprint that falls out of the ring could be
//--- re-claimed, so the ring must outlive any level that is still tradable.
//--- 4,096 claims at the observed rate of a few per session is months of
//--- history, and a level from months ago is not the level that was swept.
#define XSP_EVENT_RING                4096

class CXspStructureEvents
  {
private:
   string            m_ring[];
   int               m_head;          // next write position
   int               m_filled;
   int               m_digits;
   long              m_claims;
   long              m_refusals;

public:
                     CXspStructureEvents(void)
     {
      m_head=0;
      m_filled=0;
      m_digits=2;
      m_claims=0;
      m_refusals=0;
      ArrayResize(m_ring,XSP_EVENT_RING);
      for(int i=0;i<XSP_EVENT_RING;i++) m_ring[i]="";
     }

   void              Configure(const int digits) { m_digits=(digits>0?digits:2); }

   long              Claims(void)   const { return(m_claims); }
   long              Refusals(void) const { return(m_refusals); }
   int               Remembered(void) const { return(m_filled); }

   //+---------------------------------------------------------------+
   //| The identity of a structural occurrence.                        |
   //|                                                                |
   //| (setup, direction, level price, level ORIGIN BAR TIME). Not the  |
   //| bar index: CSwingDetector rebuilds its arrays on every refresh,  |
   //| so a shift recorded at detection time points at a different bar  |
   //| two bars later, and an identity that drifts lets one occurrence  |
   //| be claimed twice. Not the current time either - that is what the |
   //| old tree used, and it is why every evaluation looked new.        |
   //|                                                                |
   //| Price is formatted to symbol digits so that two reads of the     |
   //| same level differing in the sixteenth decimal are one identity.  |
   //+---------------------------------------------------------------+
   string            Fingerprint(const ENUM_XSP_SETUP setup,const ENUM_XSP_DIR dir,
                                 const double level_price,const datetime level_time) const
     {
      return(StringFormat("%s|%s|%s|%I64d",
                          XspSetupName(setup),
                          XspDirName(dir),
                          DoubleToString(level_price,m_digits),
                          (long)level_time));
     }

   //--- Has this occurrence already been recorded?
   bool              IsClaimed(const string fingerprint) const
     {
      for(int i=0;i<m_filled;i++)
         if(m_ring[i]==fingerprint) return(true);
      return(false);
     }

   //+---------------------------------------------------------------+
   //| Claim an occurrence. TRUE exactly once per fingerprint.          |
   //|                                                                |
   //| This is the whole defect-2 fix in one function: a caller that    |
   //| evaluates the same level on every bar, or every tick, still gets |
   //| one true. The n that reaches the statistics is therefore a count |
   //| of market occurrences and not a count of evaluations.           |
   //+---------------------------------------------------------------+
   bool              Claim(const string fingerprint)
     {
      if(StringLen(fingerprint)==0) return(false);
      if(IsClaimed(fingerprint))
        {
         m_refusals++;
         return(false);
        }
      m_ring[m_head]=fingerprint;
      m_head++;
      if(m_head>=XSP_EVENT_RING) m_head=0;
      if(m_filled<XSP_EVENT_RING) m_filled++;
      m_claims++;
      return(true);
     }

   //+---------------------------------------------------------------+
   //| STATE, not an event. Deliberately a separate function with a     |
   //| separate name and no side effects at all.                       |
   //|                                                                |
   //| The old tree's failure was not a typo, it was that one predicate |
   //| served both questions: "is price beyond the level" and "did a    |
   //| break just happen" were the same expression, so every caller     |
   //| that wanted the first got the second. Here the state query       |
   //| cannot claim, and the claim cannot be reached by asking about    |
   //| state. Confusing them now requires calling the wrong function by |
   //| name.                                                           |
   //+---------------------------------------------------------------+
   static bool       IsBeyond(const double price,const double level,
                              const ENUM_XSP_DIR beyond_dir,const double buffer_price=0.0)
     {
      if(beyond_dir==XSP_DIR_BUY)  return(price>level+buffer_price);
      if(beyond_dir==XSP_DIR_SELL) return(price<level-buffer_price);
      return(false);
     }

   //--- For the self-test and the run summary. A high refusal count is
   //--- EXPECTED and healthy: it is the number of re-evaluations that
   //--- would have become duplicate rows in the old tree.
   string            Describe(void) const
     {
      return(StringFormat("events claimed=%I64d refused_duplicate=%I64d remembered=%d/%d",
                          m_claims,m_refusals,m_filled,XSP_EVENT_RING));
     }
  };

#endif // XSP_LIQUIDITY_CXSPSTRUCTUREEVENTS_MQH
//+------------------------------------------------------------------+
