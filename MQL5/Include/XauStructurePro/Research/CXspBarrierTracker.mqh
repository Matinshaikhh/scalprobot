//+------------------------------------------------------------------+
//|                                           CXspBarrierTracker.mqh |
//|        XauStructurePro - Research : forward barrier tracking, the |
//|                                              measurement itself. |
//|                                                                  |
//|   NO LOOKAHEAD BY CONSTRUCTION. Every field is written by a tick that   |
//|   had already arrived when it was written. There is no bar indexing     |
//|   here at all, so there is nothing that could reach a future bar even   |
//|   by accident - which is a stronger guarantee than reviewing shift      |
//|   arithmetic and finding no negatives.                                 |
//|                                                                  |
//|   ONE STOP, FOUR TARGETS. The stop is shared by all four reward tiers,  |
//|   so it is one timestamp, and each tier's outcome is DERIVED by         |
//|   comparing its target time against it. Storing a per-tier outcome      |
//|   would let the tiers contradict one another - tier 1 recorded as a     |
//|   stop and tier 3 as a target on the same instance - and nothing in     |
//|   the file would reveal it.                                            |
//|                                                                  |
//|   Combined with the R-at-cap marks, this makes every (reward, holding   |
//|   cap) cell derivable from ONE pass: 4 tiers x 4 caps = 16 geometries   |
//|   from one traversal of the tape, with no second run and no chance to   |
//|   pick the luckiest cell after seeing the others.                       |
//+------------------------------------------------------------------+
#ifndef XSP_RESEARCH_CXSPBARRIERTRACKER_MQH
#define XSP_RESEARCH_CXSPBARRIERTRACKER_MQH

#include "../Core/XspTypes.mqh"

class CXspBarrierTracker
  {
private:
   SXspInstance      m_live[];
   int               m_live_count;

   SXspInstance      m_closed[];
   int               m_closed_count;
   int               m_closed_read;

   double            m_point;
   int               m_max_track;
   long              m_next_id;

   //--- Census counters. Every candidate that does NOT become an instance
   //--- is counted and reported, because a study that silently discards
   //--- awkward cases reports a sample it did not observe.
   long              m_opened;
   long              m_rej_capacity;
   long              m_rej_geometry;
   long              m_closed_stop;
   long              m_closed_targets;
   long              m_closed_timeout;
   long              m_closed_unresolved;

public:
                     CXspBarrierTracker(void)
     {
      m_live_count=0;
      m_closed_count=0;
      m_closed_read=0;
      m_point=0.0;
      m_max_track=XSP_TRACK_MAX_SECONDS;
      m_next_id=1;
      m_opened=0;
      m_rej_capacity=0;
      m_rej_geometry=0;
      m_closed_stop=0;
      m_closed_targets=0;
      m_closed_timeout=0;
      m_closed_unresolved=0;
      ArrayResize(m_live,XSP_MAX_LIVE_INSTANCES);
      ArrayResize(m_closed,XSP_MAX_LIVE_INSTANCES);
     }

   void              Configure(const double point,const int max_track_seconds=XSP_TRACK_MAX_SECONDS)
     {
      m_point=point;
      m_max_track=(max_track_seconds>0?max_track_seconds:XSP_TRACK_MAX_SECONDS);
     }

   int               LiveCount(void)        const { return(m_live_count); }
   long              OpenedTotal(void)      const { return(m_opened); }
   long              RejectedCapacity(void) const { return(m_rej_capacity); }
   long              RejectedGeometry(void) const { return(m_rej_geometry); }
   long              ClosedByStop(void)     const { return(m_closed_stop); }
   long              ClosedByTargets(void)  const { return(m_closed_targets); }
   long              ClosedByTimeout(void)  const { return(m_closed_timeout); }
   long              ClosedUnresolved(void) const { return(m_closed_unresolved); }

   //+---------------------------------------------------------------+
   //| Open an instance on the FIRST TICK after the candidate's bar    |
   //| closed. The caller supplies the tick, so the entry price is the |
   //| first price that actually existed after the signal - not the    |
   //| bar close, which is a price the signal could not have traded.   |
   //|                                                                |
   //| stop_points comes from the setup layer because only the setup   |
   //| knows its own invalidation. The tracker checks it for sanity    |
   //| and refuses rather than clamping: a clamped stop is a different |
   //| hypothesis from the one that was pre-registered.               |
   //+---------------------------------------------------------------+
   bool              Open(const SXspCandidate &cand,const MqlTick &tick,
                          const double stop_points,long &out_id)
     {
      out_id=0;
      if(!cand.valid || cand.dir==XSP_DIR_NONE) return(false);
      if(m_point<=0.0) return(false);

      if(m_live_count>=XSP_MAX_LIVE_INSTANCES)
        {
         m_rej_capacity++;
         return(false);
        }
      //--- A stop of zero or less means the invalidation was on the wrong
      //--- side of the first available price - a gap through the level
      //--- between the bar close and the next tick. That is a real market
      //--- event, not a bug, and it is counted so the census adds up.
      if(!(stop_points>0.0) || !MathIsValidNumber(stop_points))
        {
         m_rej_geometry++;
         return(false);
        }
      return(Emplace(cand,tick,stop_points,out_id));
     }

   //+---------------------------------------------------------------+
   //| Advance every live instance by one tick.                        |
   //|                                                                |
   //| The reference series is the BID for both directions - see the    |
   //| SXspInstance header for why that makes the round-trip cost       |
   //| symmetric and the whole cost model recomputable afterwards.      |
   //|                                                                |
   //| A single tick sits at one price, so it cannot cross the target   |
   //| and the stop at once: one requires a positive excursion and the  |
   //| other a negative one. There is therefore NO intra-tick ordering  |
   //| ambiguity to resolve pessimistically, which is worth stating,    |
   //| because the same measurement taken on BARS would have that       |
   //| ambiguity on every bar that straddled both levels.              |
   //+---------------------------------------------------------------+
   void              OnTick(const MqlTick &tick)
     {
      if(m_live_count<=0 || m_point<=0.0) return;
      if(tick.bid<=0.0) return;

      for(int i=m_live_count-1;i>=0;i--)
        {
         const int elapsed=(int)(tick.time-m_live[i].trigger_time);
         //--- A tick timestamped before the trigger would make elapsed
         //--- negative. Treated as zero rather than dropped: the price is
         //--- still real and the excursion still counts.
         const int age=(elapsed>0?elapsed:0);

         Advance(i,tick,age);

         if(m_live[i].closed)
            Retire(i);
        }
     }

   //+---------------------------------------------------------------+
   //| End of run. Everything still live is retired as UNRESOLVED -     |
   //| never discarded, and never counted as flat.                     |
   //|                                                                |
   //| Discarding them would bias the sample in whichever direction     |
   //| slow instances happen to lean, and calling them break-even would |
   //| assign an outcome to instances whose outcome was not observed.    |
   //| The analysis script reports the unresolved fraction so a study    |
   //| whose window ended mid-position cannot be read as complete.       |
   //+---------------------------------------------------------------+
   void              FlushUnresolved(void)
     {
      for(int i=m_live_count-1;i>=0;i--)
        {
         m_live[i].closed=true;
         m_closed_unresolved++;
         Retire(i);
        }
     }

   //--- Drain queue. The study EA pops rows and hands them to the
   //--- recorder; the tracker never writes files, so it can be tested
   //--- against synthetic tick sequences with no filesystem involved.
   int               PendingClosed(void) const { return(m_closed_count-m_closed_read); }

   bool              PopClosed(SXspInstance &out)
     {
      if(m_closed_read>=m_closed_count) return(false);
      out=m_closed[m_closed_read];
      m_closed_read++;
      if(m_closed_read>=m_closed_count)
        {
         m_closed_count=0;
         m_closed_read=0;
        }
      return(true);
     }

   //--- Test seam. Lets XspCheck assert on a live instance's excursions
   //--- mid-sequence without waiting for it to close.
   bool              PeekLive(const int index,SXspInstance &out) const
     {
      if(index<0 || index>=m_live_count) return(false);
      out=m_live[index];
      return(true);
     }

   void              Reset(void)
     {
      m_live_count=0;
      m_closed_count=0;
      m_closed_read=0;
      m_next_id=1;
      m_opened=0;
      m_rej_capacity=0;
      m_rej_geometry=0;
      m_closed_stop=0;
      m_closed_targets=0;
      m_closed_timeout=0;
      m_closed_unresolved=0;
     }

private:
   bool              Emplace(const SXspCandidate &cand,const MqlTick &tick,
                             const double stop_points,long &out_id)
     {
      //--- A trigger tick with no usable ask cannot produce an honest entry
      //--- record: the fill price for a buy and the spread column both come
      //--- from it. Counted as a geometry refusal rather than papered over
      //--- with a symbol-level ask read, which would be a price from a
      //--- different instant than the one being recorded.
      if(tick.ask<=0.0 || tick.ask<tick.bid)
        {
         m_rej_geometry++;
         return(false);
        }

      const int slot=m_live_count;
      m_live[slot].active=true;
      m_live[slot].id=m_next_id++;
      m_live[slot].fingerprint=cand.fingerprint;
      m_live[slot].setup=cand.setup;
      m_live[slot].dir=cand.dir;
      m_live[slot].event_bar_time=cand.event_bar_time;
      m_live[slot].trigger_time=tick.time;
      m_live[slot].ref_entry=tick.bid;
      m_live[slot].fill_price=(cand.dir==XSP_DIR_BUY?tick.ask:tick.bid);
      m_live[slot].spread_points=(tick.ask-tick.bid)/m_point;
      m_live[slot].invalidation=cand.invalidation;
      m_live[slot].stop_points=stop_points;
      m_live[slot].mfe_points=0.0;
      m_live[slot].mae_points=0.0;
      m_live[slot].sec_to_mfe=0;
      m_live[slot].sec_to_stop=XSP_NEVER;
      m_live[slot].last_r=0.0;
      m_live[slot].tracked_seconds=0;
      m_live[slot].ticks_seen=0;
      m_live[slot].closed=false;
      for(int t=0;t<XSP_R_TIERS;t++)
         m_live[slot].sec_to_target[t]=XSP_NEVER;
      for(int c=0;c<XSP_CAP_TIERS;c++)
        {
         m_live[slot].move_at_cap[c]=XSP_NO_MARK;
         m_live[slot].cap_stamped[c]=false;
        }

      m_live_count++;
      m_opened++;
      out_id=m_live[slot].id;
      return(true);
     }

   //--- Favourable excursion in R. The BID for both directions; the sign
   //--- flip is the only difference between a long and a short here.
   double            MoveR(const int i,const MqlTick &tick) const
     {
      const double delta=(m_live[i].dir==XSP_DIR_BUY
                          ? tick.bid-m_live[i].ref_entry
                          : m_live[i].ref_entry-tick.bid);
      return((delta/m_point)/m_live[i].stop_points);
     }

   void              Advance(const int i,const MqlTick &tick,const int age)
     {
      m_live[i].ticks_seen++;
      const double r_now=MoveR(i,tick);

      //--- 1. Stamp any holding cap the clock has just passed. At the cap
      //--- exactly, this tick IS the mark; past it, the mark is the last
      //--- price observed at or before the cap.
      for(int c=0;c<XSP_CAP_TIERS;c++)
        {
         if(m_live[i].cap_stamped[c]) continue;
         const int cap=XspCapSeconds(c);
         if(age<cap) continue;
         m_live[i].move_at_cap[c]=(age==cap?r_now:m_live[i].last_r);
         m_live[i].cap_stamped[c]=true;
        }

      //--- 2. Past the tracking ceiling nothing can inform any cap that
      //--- will be evaluated. Excursions and barriers are NOT updated from
      //--- this tick: its price lies outside the window being measured, and
      //--- letting it set an MFE would attribute to a 60-minute hold an
      //--- excursion that happened after the hold ended.
      if(age>m_max_track)
        {
         m_live[i].tracked_seconds=m_max_track;
         m_live[i].closed=true;
         m_closed_timeout++;
         return;
        }

      m_live[i].tracked_seconds=age;

      //--- 3. Excursions, in points. MAE is NOT floored at the stop: a gap
      //--- through the level is real and the column is what would reveal it.
      const double move=r_now*m_live[i].stop_points;
      if(move>m_live[i].mfe_points)
        {
         m_live[i].mfe_points=move;
         m_live[i].sec_to_mfe=age;
        }
      if(move<m_live[i].mae_points)
         m_live[i].mae_points=move;

      ResolveBarriers(i,move,age);
      m_live[i].last_r=r_now;
     }

   //--- One stop shared by four targets. A tick sits at one price, so the
   //--- two tests below are mutually exclusive on any single tick and their
   //--- order cannot bias the result. Both use >= / <=, so a touch counts
   //--- as a hit on BOTH sides - identical treatment, no directional bias.
   void              ResolveBarriers(const int i,const double move,const int age)
     {
      if(move<=-m_live[i].stop_points)
        {
         m_live[i].sec_to_stop=age;
         m_live[i].closed=true;
         m_closed_stop++;
         return;
        }

      int resolved=0;
      for(int t=0;t<XSP_R_TIERS;t++)
        {
         if(m_live[i].sec_to_target[t]==XSP_NEVER)
           {
            if(move>=XspRTier(t)*m_live[i].stop_points)
               m_live[i].sec_to_target[t]=age;
           }
         if(m_live[i].sec_to_target[t]!=XSP_NEVER) resolved++;
        }

      //--- Every tier has its target time and the stop can no longer change
      //--- any of them, so there is nothing left to observe.
      if(resolved>=XSP_R_TIERS)
        {
         m_live[i].closed=true;
         m_closed_targets++;
        }
     }

   //--- Move a closed instance to the drain queue and swap-remove it from
   //--- the live array. Live order carries no meaning, so the swap is free.
   void              Retire(const int i)
     {
      m_live[i].active=false;
      //--- m_closed_read is a POSITION, not a count of what is still there.
      //--- Without reclaiming the drained prefix first, the queue would fill
      //--- permanently after 256 LIFETIME retirements and every instance
      //--- after that would be lost - on a run that produces thousands.
      if(m_closed_count>=ArraySize(m_closed))
         Compact();
      if(m_closed_count<ArraySize(m_closed))
        {
         m_closed[m_closed_count]=m_live[i];
         m_closed_count++;
        }
      else
        {
         //--- 256 retirements with not one drain in between. Reported rather
         //--- than overwritten in silence: a lost instance is a missing row,
         //--- and a study with missing rows is not the sample it claims.
         PrintFormat("XSP_TRACK FAIL drain queue full - instance %I64d LOST (id=%I64d)",
                     m_live[i].id,m_live[i].id);
        }
      const int last=m_live_count-1;
      if(i!=last) m_live[i]=m_live[last];
      m_live_count--;
     }

   //--- Drop the already-drained prefix and slide the rest down. FIFO order
   //--- and every public count are preserved: PendingClosed() is the
   //--- difference of the two cursors and both move together.
   void              Compact(void)
     {
      if(m_closed_read<=0) return;
      const int keep=m_closed_count-m_closed_read;
      for(int k=0;k<keep;k++)
         m_closed[k]=m_closed[m_closed_read+k];
      m_closed_count=keep;
      m_closed_read=0;
     }
  };

#endif // XSP_RESEARCH_CXSPBARRIERTRACKER_MQH
//+------------------------------------------------------------------+
