//+------------------------------------------------------------------+
//|                                                    CXspPools.mqh |
//|      XauStructurePro - Liquidity (L3) : where resting orders sit |
//|                                                                  |
//|   TWO POOL KINDS, and they are kept distinct on purpose:                |
//|     - prior-day high/low: one level, formed by a session boundary        |
//|     - equal highs/lows:   two or more swings within a tolerance of       |
//|                           each other, formed inside the tape             |
//|                                                                  |
//|   Lumping them would make the label unable to falsify either one. They   |
//|   are different claims about where stops are resting and they can fail   |
//|   independently, so they get separate values in ENUM_XSP_POOL and the    |
//|   analysis can cut on it.                                              |
//|                                                                  |
//|   WHAT IS *NOT* CLAIMED HERE. "Liquidity resting at a level" is an       |
//|   inference from price structure, not an observation. XAUUSD spot is     |
//|   not centrally cleared, no MarketBook* call exists anywhere in this     |
//|   codebase, and no depth-of-market or order-flow data is available to    |
//|   it. These are PRICE LEVELS with a hypothesis attached; the hypothesis   |
//|   is what Phase A tests.                                               |
//|                                                                  |
//|   Identity is (price of the OLDEST member, its bar time) - see           |
//|   BuildClusters for why the oldest and not the extreme.                  |
//+------------------------------------------------------------------+
#ifndef XSP_LIQUIDITY_CXSPPOOLS_MQH
#define XSP_LIQUIDITY_CXSPPOOLS_MQH

#include "../Context/CXspSwings.mqh"

#define XSP_MAX_POOLS                 32

class CXspPools
  {
private:
   string            m_symbol;
   double            m_point;
   SXspLevel         m_pools[];
   int               m_count;
   datetime          m_built_for;
   long              m_rebuilds;

   //--- Scratch for cluster assignment. A member array rather than a local
   //--- so the per-bar rebuild does no allocation.
   bool              m_taken[];

public:
                     CXspPools(void)
     {
      m_symbol="";
      m_point=0.0;
      m_count=0;
      m_built_for=0;
      m_rebuilds=0;
      ArrayResize(m_pools,XSP_MAX_POOLS);
      ArrayResize(m_taken,XSP_MAX_SWINGS);
     }

   bool              Initialize(const string symbol,const double point)
     {
      m_symbol=symbol;
      m_point=point;
      return(m_point>0.0);
     }

   int               Count(void)    const { return(m_count); }
   long              Rebuilds(void) const { return(m_rebuilds); }

   bool              Get(const int index,SXspLevel &out) const
     {
      if(index<0 || index>=m_count) return(false);
      out=m_pools[index];
      return(true);
     }

   //+---------------------------------------------------------------+
   //| Rebuild the pool list from the setup-timeframe swings and the    |
   //| prior completed day. Once per closed setup bar.                  |
   //|                                                                |
   //| tolerance_points is passed in, not computed here: it is           |
   //| XSP_POOL_TOLERANCE_ATR * ATR at the event bar, and the ATR lives  |
   //| in CXspRegime. One owner per measurement.                        |
   //+---------------------------------------------------------------+
   bool              Refresh(const CXspSwings &swings,const double tolerance_points,
                             const bool force=false)
     {
      const datetime bar=iTime(m_symbol,swings.Timeframe(),0);
      if(bar==0) return(false);
      if(!force && bar==m_built_for) return(true);
      if(m_point<=0.0) return(false);

      m_count=0;
      AddPriorDay();
      BuildClusters(swings,tolerance_points,true);
      BuildClusters(swings,tolerance_points,false);

      m_built_for=bar;
      m_rebuilds++;
      return(true);
     }

   //--- The nearest pool ABOVE a price, i.e. the next one a rally would
   //--- reach. Used by S2 to ask "which level did this bar's high sweep".
   bool              NearestAbove(const double price,SXspLevel &out) const
     {
      bool found=false;
      double best=0.0;
      for(int i=0;i<m_count;i++)
        {
         if(!IsHighSide(m_pools[i].kind)) continue;
         if(m_pools[i].price<=price) continue;
         if(!found || m_pools[i].price<best)
           {
            best=m_pools[i].price;
            out=m_pools[i];
            found=true;
           }
        }
      return(found);
     }

   bool              NearestBelow(const double price,SXspLevel &out) const
     {
      bool found=false;
      double best=0.0;
      for(int i=0;i<m_count;i++)
        {
         if(IsHighSide(m_pools[i].kind)) continue;
         if(m_pools[i].price>=price) continue;
         if(!found || m_pools[i].price>best)
           {
            best=m_pools[i].price;
            out=m_pools[i];
            found=true;
           }
        }
      return(found);
     }

   static bool       IsHighSide(const ENUM_XSP_POOL kind)
     {
      return(kind==XSP_POOL_PRIOR_DAY_HIGH ||
             kind==XSP_POOL_EQUAL_HIGHS    ||
             kind==XSP_POOL_SESSION_HIGH);
     }

   string            Describe(void) const
     {
      int eq_hi=0,eq_lo=0,day=0;
      for(int i=0;i<m_count;i++)
        {
         if(m_pools[i].kind==XSP_POOL_EQUAL_HIGHS) eq_hi++;
         else if(m_pools[i].kind==XSP_POOL_EQUAL_LOWS) eq_lo++;
         else day++;
        }
      return(StringFormat("pools total=%d prior_day=%d equal_highs=%d equal_lows=%d rebuilds=%I64d",
                          m_count,day,eq_hi,eq_lo,m_rebuilds));
     }

   //+---------------------------------------------------------------+
   //| TEST SEAM. Lets XspCheck build a pool list at EXACT prices so      |
   //| S2's sweep geometry can be asserted against numbers rather than    |
   //| against whatever the tape happened to print that day.              |
   //|                                                                |
   //| Safe by construction: Refresh() sets m_count=0 before rebuilding,  |
   //| so anything pushed here is discarded the next time the real path   |
   //| runs, and the study EA calls Refresh once per closed bar and never |
   //| calls either of these. The alternative - deriving the test's       |
   //| expected prices from the live pool list - would make S2's          |
   //| assertions conditional on the session, and a test that can be      |
   //| skipped by market conditions is not a test.                        |
   //+---------------------------------------------------------------+
   void              ClearForTest(void) { m_count=0; }
   bool              PushForTest(const ENUM_XSP_POOL kind,const double price,
                                 const datetime origin,const int touches)
     {
      return(Push(kind,price,origin,touches));
     }

private:
   //--- The prior COMPLETED day, shift 1. Shift 0 is today, whose high and
   //--- low are still being made, and a level that can move is not a level.
   void              AddPriorDay(void)
     {
      MqlRates d[];
      ArraySetAsSeries(d,true);
      if(CopyRates(m_symbol,PERIOD_D1,1,1,d)!=1) return;
      Push(XSP_POOL_PRIOR_DAY_HIGH,d[0].high,d[0].time,1);
      Push(XSP_POOL_PRIOR_DAY_LOW, d[0].low, d[0].time,1);
     }

   bool              Push(const ENUM_XSP_POOL kind,const double price,
                          const datetime origin,const int touches)
     {
      if(m_count>=XSP_MAX_POOLS) return(false);
      if(price<=0.0 || !MathIsValidNumber(price)) return(false);
      m_pools[m_count].valid=true;
      m_pools[m_count].kind=kind;
      m_pools[m_count].price=price;
      m_pools[m_count].origin_time=origin;
      m_pools[m_count].touches=touches;
      m_count++;
      return(true);
     }

   //+---------------------------------------------------------------+
   //| Group swings that sit within tolerance of one another.           |
   //|                                                                |
   //| WALKED OLDEST FIRST, and the group is identified by its OLDEST    |
   //| member's price and bar time. That choice is about identity        |
   //| stability, which is the whole subject of the defect-2 fix: if the |
   //| pool were identified by its extreme, a later swing one tick        |
   //| higher inside the tolerance would change the price, change the     |
   //| fingerprint, and let the same pool be claimed a second time. The   |
   //| oldest member cannot change once the cluster exists, because new   |
   //| members are always newer.                                        |
   //|                                                                |
   //| The cost of that choice is real and is stated rather than hidden:  |
   //| resting stops sit at the cluster's EXTREME, which may be up to     |
   //| tolerance_points away from the price recorded here. At 0.15 ATR    |
   //| the gap is a fraction of the stop distance, and the alternative is  |
   //| an identity that drifts.                                         |
   //+---------------------------------------------------------------+
   void              BuildClusters(const CXspSwings &swings,const double tolerance_points,
                                  const bool highs)
     {
      const int n=(highs?swings.HighCount():swings.LowCount());
      if(n<2) return;
      const double tol=tolerance_points*m_point;
      if(!(tol>0.0)) return;

      for(int i=0;i<n && i<XSP_MAX_SWINGS;i++) m_taken[i]=false;

      //--- index n-1 is the OLDEST confirmed swing; index 0 is the newest.
      for(int i=n-1;i>=0;i--)
        {
         if(i>=XSP_MAX_SWINGS || m_taken[i]) continue;
         SXspSwing leader;
         if(highs) { if(!swings.GetHigh(i,leader)) continue; }
         else      { if(!swings.GetLow(i,leader))  continue; }

         int touches=1;
         for(int j=i-1;j>=0;j--)
           {
            if(m_taken[j]) continue;
            SXspSwing other;
            if(highs) { if(!swings.GetHigh(j,other)) continue; }
            else      { if(!swings.GetLow(j,other))  continue; }
            if(MathAbs(other.price-leader.price)>tol) continue;
            m_taken[j]=true;
            touches++;
           }

         m_taken[i]=true;
         if(touches<2) continue;
         Push(highs?XSP_POOL_EQUAL_HIGHS:XSP_POOL_EQUAL_LOWS,
              leader.price,leader.time,touches);
        }
     }
  };

#endif // XSP_LIQUIDITY_CXSPPOOLS_MQH
//+------------------------------------------------------------------+
