//+------------------------------------------------------------------+
//|                                              CXspTickVolume.mqh |
//|      XauStructurePro - Setups (L5) : the ONE confirmation, and it |
//|                                        is BROKER TICK VOLUME only |
//|                                                                  |
//|   WHAT THIS IS. A count of QUOTE UPDATES the broker sent inside the      |
//|   trigger bar, compared against the median count for the same            |
//|   minute-of-day over the previous 20 sessions.                           |
//|                                                                  |
//|   WHAT THIS IS NOT. It is not order flow. It is not traded volume. It     |
//|   is not depth of market and not a footprint. XAUUSD spot is not         |
//|   centrally cleared, so no venue-wide volume exists for any code to      |
//|   read, and no MarketBook* call appears anywhere in this codebase - the  |
//|   data is not merely unused, it is unavailable. Tick count is a          |
//|   PARTICIPATION PROXY and the CSV column is named so that no reader can  |
//|   quietly promote it to something stronger.                             |
//|                                                                  |
//|   WHY A SAME-MINUTE BASELINE. Gold's tick rate has a large intraday      |
//|   shape: 14:30 server time carries several times the quote rate of       |
//|   03:00 for reasons that have nothing to do with any setup. Comparing a  |
//|   bar against an all-hours average would therefore confirm nearly every  |
//|   London-session setup and nearly no Asian one - it would be a session   |
//|   filter wearing a volume label. The baseline is the same slot.          |
//|                                                                  |
//|   UNCORRELATED WITH THE TRIGGER, as audit 8.2 L5 requires. Both setups   |
//|   trigger on price structure; this reads neither price nor level.        |
//|                                                                  //|
//|   CAVEAT, stated rather than buried: the slot is SERVER minute-of-day.   |
//|   A broker DST change shifts the underlying session by an hour, so for   |
//|   a few sessions after each change the baseline compares a bar against   |
//|   a different part of the day. Two transitions a year against a 20-      |
//|   session window; slot_samples is recorded so those rows can be found.   |
//+------------------------------------------------------------------+
#ifndef XSP_SETUPS_CXSPTICKVOLUME_MQH
#define XSP_SETUPS_CXSPTICKVOLUME_MQH

#include "../Core/XspTypes.mqh"
#include "../Core/CXspStats.mqh"

class CXspTickVolume
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_scan_bars;
   long              m_measured;
   long              m_thin_baseline;

public:
                     CXspTickVolume(void)
     {
      m_symbol="";
      m_tf=XSP_TF_SETUP;
      m_scan_bars=0;
      m_measured=0;
      m_thin_baseline=0;
     }

   long              Measured(void)      const { return(m_measured); }
   long              ThinBaseline(void)  const { return(m_thin_baseline); }

   bool              Initialize(const string symbol,const ENUM_TIMEFRAMES tf)
     {
      m_symbol=symbol;
      m_tf=tf;
      //--- How far back to look for XSP_CONFIRM_SLOT_SESSIONS matching slots.
      //--- Sized from the timeframe rather than hard-coded at 96, so this
      //--- class does not silently assume M15; and multiplied by 1.6 plus a
      //--- fixed pad because weekends and holidays mean 20 calendar days do
      //--- not contain 20 trading sessions.
      const int secs=PeriodSeconds(m_tf);
      if(secs<=0) return(false);
      const int bars_per_day=86400/secs;
      m_scan_bars=(int)MathCeil(bars_per_day*XSP_CONFIRM_SLOT_SESSIONS*1.6)+bars_per_day;
      if(m_scan_bars<64)   m_scan_bars=64;
      if(m_scan_bars>6000) m_scan_bars=6000;
      return(true);
     }

   //+---------------------------------------------------------------+
   //| Measure the trigger bar against its own slot.                    |
   //|                                                                |
   //| bar_time and bar_volume both come from the CLOSED trigger bar,    |
   //| supplied by the caller, so this function never has to decide       |
   //| which bar it is looking at - and cannot pick up the forming one.   |
   //|                                                                |
   //| Returns false only when the history read fails. A THIN baseline is |
   //| not a failure: it is recorded with its sample count so the         |
   //| analysis can require a minimum, which is a decision for the        |
   //| analysis and not for the recorder.                                |
   //+---------------------------------------------------------------+
   bool              Measure(const datetime bar_time,const long bar_volume,SXspConfirm &out)
     {
      out.Reset();
      if(m_scan_bars<=0) return(false);

      MqlDateTime want;
      TimeToStruct(bar_time,want);

      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      //--- start_pos 2, not 1: shift 1 IS the trigger bar, and a bar must not
      //--- appear in the baseline it is being ranked against.
      const int got=CopyRates(m_symbol,m_tf,2,m_scan_bars,rates);
      if(got<=0) return(false);

      long slot[];
      if(ArrayResize(slot,XSP_CONFIRM_SLOT_SESSIONS)!=XSP_CONFIRM_SLOT_SESSIONS)
         return(false);
      int found=0;
      for(int i=0;i<got && found<XSP_CONFIRM_SLOT_SESSIONS;i++)
        {
         MqlDateTime dt;
         TimeToStruct(rates[i].time,dt);
         if(dt.hour!=want.hour || dt.min!=want.min) continue;
         if(rates[i].tick_volume<=0) continue;
         slot[found]=(long)rates[i].tick_volume;
         found++;
        }

      out.tick_volume=bar_volume;
      out.slot_samples=found;
      out.valid=true;
      if(found<3)
        {
         //--- Fewer than three prior sessions is not a median. Recorded as
         //--- ratio 0 with slot_samples=found so the row is identifiable and
         //--- excludable, rather than carrying a ratio computed from one bar.
         m_thin_baseline++;
         out.slot_median=0.0;
         out.ratio=0.0;
         out.passed=false;
         return(true);
        }

      out.slot_median=CXspStats::MedianLong(slot,found);
      out.ratio=CXspStats::SafeDiv((double)bar_volume,out.slot_median,0.0);
      out.passed=(out.ratio>=XSP_CONFIRM_MIN_RATIO);
      m_measured++;
      return(true);
     }
  };

#endif // XSP_SETUPS_CXSPTICKVOLUME_MQH
//+------------------------------------------------------------------+
