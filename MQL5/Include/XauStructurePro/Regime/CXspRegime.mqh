//+------------------------------------------------------------------+
//|                                                   CXspRegime.mqh |
//|            XauStructurePro - Regime (L2) : volatility and spread |
//|                                     deciles, RECORDED never gated |
//|                                                                  |
//|   DECILES, NOT THRESHOLDS. A rule like "trade only when ATR > 180pt"   |
//|   contains a number that has to come from somewhere, and choosing it    |
//|   on the data this study measures is precisely the section-9 violation  |
//|   the rebuild exists to avoid. A decile is defined by the sample, so    |
//|   there is nothing left to choose - and the question "which deciles     |
//|   does this setup work in" stays answerable AFTERWARDS from one run.     |
//|                                                                  |
//|   NOTHING HERE STANDS DOWN. Audit 8.2 gives L2 stand-down authority in  |
//|   the traded product; in Phase A a stand-down would delete the          |
//|   counterfactual - what the setup does in the regime it is supposed to   |
//|   avoid - and no later analysis could recover it. The authority arrives  |
//|   in Phase C, aimed by what this measures.                             |
//|                                                                  |
//|   iATR direct, not SRP's CAtrIntel. CAtrIntel is sound, but it sits on  |
//|   CIntelIndicator's warm-up state machine with a 256-bar cache, and     |
//|   the vol decile needs 480. A handle and CopyBuffer need no warm-up     |
//|   gate, no cache depth and no frozen-tree dependency.                   |
//+------------------------------------------------------------------+
#ifndef XSP_REGIME_CXSPREGIME_MQH
#define XSP_REGIME_CXSPREGIME_MQH

#include "../Core/XspTypes.mqh"
#include "../Core/CXspStats.mqh"

class CXspRegime
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   double            m_point;
   int               m_atr_handle;

   double            m_atr[];         // series-indexed: 0 = forming bar
   int               m_atr_count;
   double            m_vol_window[];  // the trailing closed-bar ATR sample
   int               m_vol_count;

   double            m_spread_ring[];
   int               m_spread_head;
   int               m_spread_filled;
   long              m_spread_seen;

public:
                     CXspRegime(void)
     {
      m_symbol="";
      m_tf=XSP_TF_SETUP;
      m_point=0.0;
      m_atr_handle=INVALID_HANDLE;
      m_atr_count=0;
      m_vol_count=0;
      m_spread_head=0;
      m_spread_filled=0;
      m_spread_seen=0;
     }

                    ~CXspRegime(void)
     {
      if(m_atr_handle!=INVALID_HANDLE) IndicatorRelease(m_atr_handle);
     }

   bool              Initialize(const string symbol,const ENUM_TIMEFRAMES tf,const double point)
     {
      m_symbol=symbol;
      m_tf=tf;
      m_point=point;
      if(m_point<=0.0)
        {
         Print("XSP_REGIME FAIL point size is zero");
         return(false);
        }
      m_atr_handle=iATR(m_symbol,m_tf,XSP_ATR_PERIOD);
      if(m_atr_handle==INVALID_HANDLE)
        {
         PrintFormat("XSP_REGIME FAIL iATR('%s',%s,%d) err=%d",
                     m_symbol,EnumToString(m_tf),XSP_ATR_PERIOD,GetLastError());
         return(false);
        }
      if(ArrayResize(m_spread_ring,XSP_SPREAD_RANK_SAMPLES)!=XSP_SPREAD_RANK_SAMPLES)
         return(false);
      ArraySetAsSeries(m_atr,true);
      return(true);
     }

   //+---------------------------------------------------------------+
   //| Recopy the ATR series. Called ONCE PER CLOSED SETUP BAR, not per  |
   //| tick: an ATR value cannot change inside a bar in any way that     |
   //| matters, and CopyBuffer per tick would dominate the run cost.     |
   //+---------------------------------------------------------------+
   bool              RefreshBars(void)
     {
      const int want=XSP_VOL_RANK_BARS+XSP_ATR_PERIOD+8;
      const int got=CopyBuffer(m_atr_handle,0,0,want,m_atr);
      if(got<=0)
        {
         m_atr_count=0;
         return(false);
        }
      m_atr_count=got;

      //--- The decile sample is the trailing CLOSED bars only. m_atr[0] is
      //--- the forming bar, whose ATR is still moving; including it would
      //--- put a partially-formed observation into the reference
      //--- distribution its own rank is measured against.
      int n=m_atr_count-1;
      if(n>XSP_VOL_RANK_BARS) n=XSP_VOL_RANK_BARS;
      m_vol_count=0;
      if(n<=0) return(true);
      if(ArrayResize(m_vol_window,n)!=n) return(false);
      for(int i=0;i<n;i++)
         m_vol_window[i]=m_atr[i+1]/m_point;
      m_vol_count=n;
      return(true);
     }

   //--- Every tick's spread joins the rolling sample. Per tick and not per
   //--- bar on purpose: audit 6.2 measured 9.5-33.5pt on real ticks against
   //--- 4.0-4.4pt bar-generated, so the spread distribution IS the cost
   //--- model, and a bar-sampled version of it would understate the toll.
   void              ObserveTick(const MqlTick &tick)
     {
      if(m_point<=0.0) return;
      if(tick.ask<=0.0 || tick.bid<=0.0 || tick.ask<tick.bid) return;
      m_spread_ring[m_spread_head]=(tick.ask-tick.bid)/m_point;
      m_spread_head++;
      if(m_spread_head>=XSP_SPREAD_RANK_SAMPLES) m_spread_head=0;
      if(m_spread_filled<XSP_SPREAD_RANK_SAMPLES) m_spread_filled++;
      m_spread_seen++;
     }

   //--- ATR in POINTS at a bar shift. Points not price: every distance in
   //--- the study is in points, and one conversion site is one place for
   //--- the conversion to be wrong.
   double            AtrPoints(const int shift) const
     {
      if(shift<0 || shift>=m_atr_count) return(0.0);
      if(!MathIsValidNumber(m_atr[shift])) return(0.0);
      return(m_atr[shift]/m_point);
     }

   bool              IsReady(void) const { return(m_atr_count>XSP_ATR_PERIOD); }
   int               VolSampleCount(void)    const { return(m_vol_count); }
   int               SpreadSampleCount(void) const { return(m_spread_filled); }
   long              SpreadTicksSeen(void)   const { return(m_spread_seen); }

   //--- -1 when the sample cannot carry ten buckets. Reported as -1 in the
   //--- CSV rather than defaulted to 0: an unranked instance must be
   //--- excludable by the analysis, and a decile of 0 would read as
   //--- "quietest tenth of the sample" - a claim nothing supports.
   int               VolDecile(const double atr_points) const
     {
      return(CXspStats::Decile(atr_points,m_vol_window,m_vol_count,XSP_VOL_RANK_BARS/4));
     }

   int               SpreadDecile(const double spread_points) const
     {
      return(CXspStats::Decile(spread_points,m_spread_ring,m_spread_filled,
                               XSP_SPREAD_RANK_SAMPLES/8));
     }

   //+---------------------------------------------------------------+
   //| The label block for one instance.                               |
   //|                                                                |
   //| shift is the CLOSED bar the candidate came from, so the ATR and   |
   //| its decile describe the conditions the setup formed in - not the  |
   //| conditions at the moment of writing, which is a later instant.    |
   //|                                                                |
   //| trend is NOT set here. It is H1 structure, which is L1's to       |
   //| measure; the study EA fills it from CXspHtfContext. Computing it   |
   //| twice in two places is how two definitions of "trend" end up in    |
   //| one CSV under one column name.                                    |
   //+---------------------------------------------------------------+
   bool              Snapshot(const MqlTick &tick,const int shift,
                              const datetime bar_time,SXspRegime &out) const
     {
      out.Reset();
      const double atr=AtrPoints(shift);
      if(atr<=0.0) return(false);

      out.atr_points=atr;
      out.vol_decile=VolDecile(atr);
      out.spread_points=(tick.ask>=tick.bid && tick.ask>0.0
                         ? (tick.ask-tick.bid)/m_point : 0.0);
      out.spread_decile=SpreadDecile(out.spread_points);

      MqlDateTime dt;
      TimeToStruct(bar_time,dt);
      out.session=XspSessionOf(dt.hour);
      out.minute_of_day=dt.hour*60+dt.min;
      out.valid=true;
      return(true);
     }

   string            Describe(void) const
     {
      return(StringFormat("regime atr_bars=%d vol_sample=%d spread_sample=%d/%d ticks=%I64d",
                          m_atr_count,m_vol_count,m_spread_filled,
                          XSP_SPREAD_RANK_SAMPLES,m_spread_seen));
     }
  };

#endif // XSP_REGIME_CXSPREGIME_MQH
//+------------------------------------------------------------------+
