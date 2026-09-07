//+------------------------------------------------------------------+
//|                                             CZoneRegistry.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): store price zones and maintain their      |
//|   lifecycle state as price interacts with them.                       |
//|                                                                  |
//|   Detection lives in the detector classes; this owns only the          |
//|   collection and the state machine:                                   |
//|                                                                  |
//|     FRESH -> TESTED -> MITIGATED -> INVALIDATED                       |
//|                    \-> EXPIRED (aged out)                             |
//|                                                                  |
//|   WHY THE STATE MACHINE MATTERS                                      |
//|   An order block that price has already consumed is not a level any    |
//|   more, but most implementations keep drawing it. Tracking             |
//|   consumption is the difference between a zone list that decays        |
//|   correctly and one that accumulates stale noise until every price is  |
//|   "inside a zone".                                                    |
//|                                                                  |
//|   Capacity is bounded and eviction is by weakest-then-oldest, so an    |
//|   EA running for months has a constant memory profile.                |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_SMARTMONEY_CZONEREGISTRY_MQH
#define SRP_INTELLIGENCE_SMARTMONEY_CZONEREGISTRY_MQH

#include "../../Core/Interfaces/ILogger.mqh"
#include "../Types/IntelligenceStructs.mqh"

class CZoneRegistry
  {
private:
   ILogger          *m_logger;            // borrowed
   SPriceZone        m_zones[];
   int               m_capacity;
   //--- Lifecycle tuning.
   int               m_max_age_bars;
   double            m_mitigation_fraction; // penetration counted as partial
   long              m_added_count;
   long              m_invalidated_count;
   long              m_expired_count;

   int               FindWeakestIndex(void) const;
   bool              RemoveAt(const int index);

public:
                     CZoneRegistry(ILogger *logger,const int capacity=64);
                    ~CZoneRegistry(void);

   void              SetCapacity(const int capacity);
   void              SetMaxAgeBars(const int bars);
   void              SetMitigationFraction(const double fraction);

   //--- Adds a zone, evicting the weakest when full. Duplicates that
   //--- overlap an existing zone of the same kind are merged rather than
   //--- appended, so repeated detection cannot inflate the list.
   bool              Add(const SPriceZone &zone);
   void              Clear(void);

   //--- Advances every zone's state against the current bar. Called once
   //--- per bar by the SMC engine.
   void              UpdateStates(const double bar_high,const double bar_low,
                                  const double bar_close,
                                  const int current_bar_index);

   //--- Access.
   int               Count(void) const { return(ArraySize(m_zones)); }
   bool              At(const int index,SPriceZone &out) const;
   int               CountByKind(const ENUM_SRP_ZONE_KIND kind) const;
   int               CountActionable(void) const;

   //--- Queries used by consumers. All return BORROWED copies.
   bool              NearestAbove(const double price,SPriceZone &out) const;
   bool              NearestBelow(const double price,SPriceZone &out) const;
   bool              ZoneContaining(const double price,SPriceZone &out) const;
   bool              StrongestOfKind(const ENUM_SRP_ZONE_KIND kind,
                                     SPriceZone &out) const;
   bool              NearestOfKind(const ENUM_SRP_ZONE_KIND kind,
                                   const double price,
                                   const ENUM_SRP_BIAS bias,
                                   SPriceZone &out) const;
   bool              IsPriceInZone(const double price) const;

   //--- Diagnostics.
   long              AddedCount(void)       const { return(m_added_count); }
   long              InvalidatedCount(void) const { return(m_invalidated_count); }
   long              ExpiredCount(void)     const { return(m_expired_count); }
   string            Describe(void) const;
  };

//+------------------------------------------------------------------+
CZoneRegistry::CZoneRegistry(ILogger *logger,const int capacity)
  : m_logger(logger),
    m_capacity(capacity<4 ? 4 : capacity),
    m_max_age_bars(500),
    m_mitigation_fraction(0.5),
    m_added_count(0),
    m_invalidated_count(0),
    m_expired_count(0)
  {
   ArrayResize(m_zones,0);
  }
//+------------------------------------------------------------------+
CZoneRegistry::~CZoneRegistry(void)
  {
   ArrayFree(m_zones);
  }
//+------------------------------------------------------------------+
void CZoneRegistry::SetCapacity(const int capacity)
  {
   if(capacity>=4)
      m_capacity=capacity;
  }
//+------------------------------------------------------------------+
void CZoneRegistry::SetMaxAgeBars(const int bars)
  {
   if(bars>=10)
      m_max_age_bars=bars;
  }
//+------------------------------------------------------------------+
void CZoneRegistry::SetMitigationFraction(const double fraction)
  {
   if(fraction>0.0 && fraction<1.0)
      m_mitigation_fraction=fraction;
  }
//+------------------------------------------------------------------+
void CZoneRegistry::Clear(void)
  {
   ArrayResize(m_zones,0);
  }
//+------------------------------------------------------------------+
int CZoneRegistry::FindWeakestIndex(void) const
  {
   const int total=ArraySize(m_zones);
   if(total==0)
      return(-1);

   //--- Prefer evicting a dead zone; only then fall back to the weakest
   //--- live one. Killing a fresh strong zone to make room would defeat
   //--- the purpose of the registry.
   int weakest=-1;
   double worst_score=0.0;
   for(int i=0;i<total;i++)
     {
      //--- Score dead zones far below any live zone.
      double score=m_zones[i].strength;
      if(m_zones[i].state==SRP_ZONE_INVALIDATED ||
         m_zones[i].state==SRP_ZONE_EXPIRED)
         score=-1.0;
      else if(m_zones[i].state==SRP_ZONE_MITIGATED)
         score*=0.5;

      if(weakest<0 || score<worst_score)
        {
         weakest=i;
         worst_score=score;
        }
     }
   return(weakest);
  }
//+------------------------------------------------------------------+
bool CZoneRegistry::RemoveAt(const int index)
  {
   const int total=ArraySize(m_zones);
   if(index<0 || index>=total)
      return(false);
   for(int i=index;i<total-1;i++)
      m_zones[i]=m_zones[i+1];
   return(ArrayResize(m_zones,total-1)==total-1);
  }
//+------------------------------------------------------------------+
bool CZoneRegistry::Add(const SPriceZone &zone)
  {
   if(zone.upper<=zone.lower)
      return(false);

   //--- MERGE overlapping same-kind, same-bias zones instead of adding a
   //--- near-duplicate. Repeated scans of the same formation would
   //--- otherwise fill the registry with copies of one level.
   const int total=ArraySize(m_zones);
   for(int i=0;i<total;i++)
     {
      if(m_zones[i].kind!=zone.kind || m_zones[i].bias!=zone.bias)
         continue;
      const bool overlaps=(zone.lower<=m_zones[i].upper &&
                           zone.upper>=m_zones[i].lower);
      if(!overlaps)
         continue;
      //--- Keep the stronger definition and the earlier formation time.
      if(zone.strength>m_zones[i].strength)
        {
         const datetime original_time=m_zones[i].formed_at;
         const int original_touches=m_zones[i].touch_count;
         m_zones[i]=zone;
         m_zones[i].formed_at=original_time;
         m_zones[i].touch_count=original_touches;
        }
      return(true);
     }

   if(total>=m_capacity)
     {
      const int weakest=FindWeakestIndex();
      if(weakest>=0 && !RemoveAt(weakest))
         return(false);
     }

   const int size=ArraySize(m_zones);
   if(ArrayResize(m_zones,size+1)!=size+1)
      return(false);
   m_zones[size]=zone;
   //--- Midpoint is the usual entry trigger, so it is computed once here
   //--- rather than by every consumer.
   m_zones[size].midpoint=(zone.upper+zone.lower)*0.5;
   m_added_count++;
   return(true);
  }
//+------------------------------------------------------------------+
void CZoneRegistry::UpdateStates(const double bar_high,const double bar_low,
                                 const double bar_close,
                                 const int current_bar_index)
  {
   const int total=ArraySize(m_zones);
   for(int i=0;i<total;i++)
     {
      //--- Dead zones are left alone; eviction handles them.
      if(m_zones[i].state==SRP_ZONE_INVALIDATED ||
         m_zones[i].state==SRP_ZONE_EXPIRED)
         continue;

      //--- AGE OUT. An old untested zone loses relevance; keeping it
      //--- forever is how zone lists become useless.
      const int age=current_bar_index-m_zones[i].formed_bar;
      if(m_max_age_bars>0 && age>m_max_age_bars)
        {
         m_zones[i].state=SRP_ZONE_EXPIRED;
         m_expired_count++;
         continue;
        }

      //--- Did this bar touch the zone at all?
      const bool touched=(bar_high>=m_zones[i].lower &&
                          bar_low<=m_zones[i].upper);
      if(!touched)
         continue;

      m_zones[i].touch_count++;

      const double height=m_zones[i].Height();
      if(height<=0.0)
         continue;

      //--- INVALIDATION depends on bias. A bullish zone is meant to hold
      //--- price up; a close decisively below it means it failed. Using
      //--- the CLOSE rather than the wick avoids invalidating on a spike
      //--- that immediately reverses - which is precisely the behaviour
      //--- these zones are supposed to capture.
      if(m_zones[i].bias==SRP_BIAS_BULLISH)
        {
         if(bar_close<m_zones[i].lower)
           {
            m_zones[i].state=SRP_ZONE_INVALIDATED;
            m_invalidated_count++;
            continue;
           }
         //--- Penetration depth decides tested vs mitigated.
         const double penetration=(m_zones[i].upper-bar_low)/height;
         m_zones[i].state=(penetration>=m_mitigation_fraction
                           ? SRP_ZONE_MITIGATED : SRP_ZONE_TESTED);
        }
      else if(m_zones[i].bias==SRP_BIAS_BEARISH)
        {
         if(bar_close>m_zones[i].upper)
           {
            m_zones[i].state=SRP_ZONE_INVALIDATED;
            m_invalidated_count++;
            continue;
           }
         const double penetration=(bar_high-m_zones[i].lower)/height;
         m_zones[i].state=(penetration>=m_mitigation_fraction
                           ? SRP_ZONE_MITIGATED : SRP_ZONE_TESTED);
        }
      else
        {
         //--- Neutral zones (liquidity pools) simply record the touch.
         m_zones[i].state=SRP_ZONE_TESTED;
        }
     }
  }
//+------------------------------------------------------------------+
bool CZoneRegistry::At(const int index,SPriceZone &out) const
  {
   out.Reset();
   if(index<0 || index>=ArraySize(m_zones))
      return(false);
   out=m_zones[index];
   return(true);
  }
//+------------------------------------------------------------------+
int CZoneRegistry::CountByKind(const ENUM_SRP_ZONE_KIND kind) const
  {
   int count=0;
   const int total=ArraySize(m_zones);
   for(int i=0;i<total;i++)
      if(m_zones[i].kind==kind)
         count++;
   return(count);
  }
//+------------------------------------------------------------------+
int CZoneRegistry::CountActionable(void) const
  {
   int count=0;
   const int total=ArraySize(m_zones);
   for(int i=0;i<total;i++)
      if(m_zones[i].IsActionable())
         count++;
   return(count);
  }
//+------------------------------------------------------------------+
bool CZoneRegistry::NearestAbove(const double price,SPriceZone &out) const
  {
   out.Reset();
   bool found=false;
   double best_distance=0.0;
   const int total=ArraySize(m_zones);
   for(int i=0;i<total;i++)
     {
      if(!m_zones[i].IsActionable())
         continue;
      if(m_zones[i].lower<=price)
         continue;
      const double distance=m_zones[i].lower-price;
      if(!found || distance<best_distance)
        {
         out=m_zones[i];
         best_distance=distance;
         found=true;
        }
     }
   return(found);
  }
//+------------------------------------------------------------------+
bool CZoneRegistry::NearestBelow(const double price,SPriceZone &out) const
  {
   out.Reset();
   bool found=false;
   double best_distance=0.0;
   const int total=ArraySize(m_zones);
   for(int i=0;i<total;i++)
     {
      if(!m_zones[i].IsActionable())
         continue;
      if(m_zones[i].upper>=price)
         continue;
      const double distance=price-m_zones[i].upper;
      if(!found || distance<best_distance)
        {
         out=m_zones[i];
         best_distance=distance;
         found=true;
        }
     }
   return(found);
  }
//+------------------------------------------------------------------+
bool CZoneRegistry::ZoneContaining(const double price,SPriceZone &out) const
  {
   out.Reset();
   bool found=false;
   double best_strength=0.0;
   const int total=ArraySize(m_zones);
   for(int i=0;i<total;i++)
     {
      if(!m_zones[i].IsActionable() || !m_zones[i].Contains(price))
         continue;
      //--- When zones overlap, report the strongest.
      if(!found || m_zones[i].strength>best_strength)
        {
         out=m_zones[i];
         best_strength=m_zones[i].strength;
         found=true;
        }
     }
   return(found);
  }
//+------------------------------------------------------------------+
bool CZoneRegistry::StrongestOfKind(const ENUM_SRP_ZONE_KIND kind,
                                    SPriceZone &out) const
  {
   out.Reset();
   bool found=false;
   double best=0.0;
   const int total=ArraySize(m_zones);
   for(int i=0;i<total;i++)
     {
      if(m_zones[i].kind!=kind || !m_zones[i].IsActionable())
         continue;
      if(!found || m_zones[i].strength>best)
        {
         out=m_zones[i];
         best=m_zones[i].strength;
         found=true;
        }
     }
   return(found);
  }
//+------------------------------------------------------------------+
bool CZoneRegistry::NearestOfKind(const ENUM_SRP_ZONE_KIND kind,
                                  const double price,
                                  const ENUM_SRP_BIAS bias,
                                  SPriceZone &out) const
  {
   out.Reset();
   bool found=false;
   double best_distance=0.0;
   const int total=ArraySize(m_zones);
   for(int i=0;i<total;i++)
     {
      if(m_zones[i].kind!=kind || !m_zones[i].IsActionable())
         continue;
      if(bias!=SRP_BIAS_NEUTRAL && m_zones[i].bias!=bias)
         continue;
      //--- Distance to the zone edge, zero when price is inside.
      double distance=0.0;
      if(price>m_zones[i].upper)
         distance=price-m_zones[i].upper;
      else if(price<m_zones[i].lower)
         distance=m_zones[i].lower-price;
      if(!found || distance<best_distance)
        {
         out=m_zones[i];
         best_distance=distance;
         found=true;
        }
     }
   return(found);
  }
//+------------------------------------------------------------------+
bool CZoneRegistry::IsPriceInZone(const double price) const
  {
   SPriceZone zone;
   return(ZoneContaining(price,zone));
  }
//+------------------------------------------------------------------+
string CZoneRegistry::Describe(void) const
  {
   return(StringFormat("zones: %d total, %d actionable | OB=%d BB=%d MB=%d FVG=%d LP=%d"
                       " | added=%I64d invalidated=%I64d expired=%I64d",
                       ArraySize(m_zones),CountActionable(),
                       CountByKind(SRP_ZONE_ORDER_BLOCK),
                       CountByKind(SRP_ZONE_BREAKER_BLOCK),
                       CountByKind(SRP_ZONE_MITIGATION_BLOCK),
                       CountByKind(SRP_ZONE_FAIR_VALUE_GAP),
                       CountByKind(SRP_ZONE_LIQUIDITY_POOL),
                       m_added_count,m_invalidated_count,m_expired_count));
  }

#endif // SRP_INTELLIGENCE_SMARTMONEY_CZONEREGISTRY_MQH
//+------------------------------------------------------------------+
