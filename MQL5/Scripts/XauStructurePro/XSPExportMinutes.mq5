//+------------------------------------------------------------------+
//|                                             XSPExportMinutes.mq5 |
//|        XauStructurePro - Research : the minute export for B0     |
//|                                                                  |
//|   A SCRIPT, deliberately, and not an Expert in the tester.        |
//|                                                                  |
//|   Inside the Strategy Tester CopyTicksRange for the tested symbol |
//|   returns the TESTER's tick stream, which under any model but 4   |
//|   is synthesised from M1 bars - and nothing in the returned array |
//|   says so. Audit 6.2 measured generated spread at 4.0-4.4 pts     |
//|   against 9.5-33.5 real, so an export contaminated that way would |
//|   understate cost about threefold and read as a real-tick file.   |
//|   A script on a live chart reads the terminal's own tick archive   |
//|   directly for every symbol, which is the same source Phase A     |
//|   inferred as SRP_TICK_MODEL_REAL_TICKS. One manual step buys      |
//|   unambiguous provenance; that is a good trade.                   |
//|                                                                  |
//|   NO TRADING CODE. There is no OrderSend, no position, no signal  |
//|   and no strategy in this file. It aggregates ticks to minutes    |
//|   and writes them out. The hypothesis is tested offline, in        |
//|   _build/xspresidual.py, against CHANGELOG 'XSP 0.2'.             |
//|                                                                  |
//|   BID for both symbols. The study measures on the bid path and     |
//|   charges one spread analytically, so the spread must be exported  |
//|   as a column rather than baked into the price.                    |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict
#property description "Exports 1-minute bid OHLC + tick count + spread quantiles from real ticks."
#property description "No trading code. Reads the terminal tick archive; run on any open chart."

#include <XauStructurePro/Research/CXspCsv.mqh>

//--- Symbols in one run so both files carry the same run stamp and can
//--- be checked for the alignment the study depends on.
input string   InpSymbols  = "XAUUSD,EURUSD";
//--- DEV, and only DEV. Audit 9.1 seals 2026.03.01 onward as VAL: one
//--- look, one frozen candidate, at the end. InpTo is EXCLUSIVE.
input datetime InpFrom     = D'2025.05.27 00:00';
input datetime InpTo       = D'2026.03.01 00:00';
input string   InpPrefix   = "xsp_minutes_";
//--- Spread quantiles need the minute's samples held at once. A minute
//--- with more ticks than this still counts every tick in `ticks`; only
//--- the quantile sample is capped, and the overflow is reported rather
//--- than passed off as a full sample.
input int      InpMaxSpreadSamples = 65536;

#define XSP_EXPORT_SCHEMA "xsp-minute-v1"

//+------------------------------------------------------------------+
//| One minute under construction. Reset() rather than a constructor   |
//| because it is reused across every minute of nine months and a      |
//| fresh struct per minute is 400k allocations for nothing.           |
//+------------------------------------------------------------------+
struct SXspMinute
  {
   long              bucket;      // epoch/60, -1 when empty
   double            o,h,l,c;
   long              ticks;       // EVERY tick in the minute
   int               ns;          // spread samples actually held
   long              ns_dropped;  // samples past the cap

   void Reset(void)
     {
      bucket=-1; o=0.0; h=0.0; l=0.0; c=0.0;
      ticks=0; ns=0; ns_dropped=0;
     }
  };

//--- Held at file scope: a 65536-double local inside the tick loop would
//--- be re-created per minute.
double g_spread[];

//+------------------------------------------------------------------+
//| Quantile by nearest rank on an already sorted array. No            |
//| interpolation: the value returned is one the market actually        |
//| quoted, which is the point of exporting a spread at all.            |
//+------------------------------------------------------------------+
double SortedQuantile(const double &v[],const int n,const double p)
  {
   if(n<=0) return(0.0);
   int i=(int)MathFloor(p*(n-1)+0.5);
   if(i<0) i=0;
   if(i>n-1) i=n-1;
   return(v[i]);
  }

//+------------------------------------------------------------------+
//| Writes the finished minute and returns whether the write worked.   |
//|                                                                  |
//| g_spread is kept at EXACTLY the sample count, not at the cap.      |
//| ArraySort sorts a whole array, so a 65536-long buffer holding 40   |
//| real samples would sort 65496 zeros to the front and every         |
//| quantile below would read one of them. Growing with a reserve      |
//| keeps the logical size honest at no allocation cost.               |
//+------------------------------------------------------------------+
bool FlushMinute(CXspCsv &csv,SXspMinute &m,const int digits)
  {
   if(m.bucket<0 || m.ticks<=0) return(true);
   double med=0.0,p90=0.0;
   const int n=ArraySize(g_spread);
   if(n>0)
     {
      ArraySort(g_spread);
      med=SortedQuantile(g_spread,n,0.50);
      p90=SortedQuantile(g_spread,n,0.90);
     }
   const string row=StringFormat("%I64d,%s,%s,%s,%s,%I64d,%.1f,%.1f,%d",
                                 m.bucket*60,
                                 DoubleToString(m.o,digits),
                                 DoubleToString(m.h,digits),
                                 DoubleToString(m.l,digits),
                                 DoubleToString(m.c,digits),
                                 m.ticks,med,p90,n);
   return(csv.WriteRow(row));
  }

//--- Appends one spread sample, or counts it as dropped once the cap is
//--- reached. Returns nothing: a dropped sample is not an error, it is a
//--- fact about the minute and it is reported per symbol at the end.
void PushSpread(SXspMinute &m,const double pts,const int cap)
  {
   const int n=ArraySize(g_spread);
   if(n>=cap) { m.ns_dropped++; return; }
   if(ArrayResize(g_spread,n+1,cap)!=n+1) { m.ns_dropped++; return; }
   g_spread[n]=pts;
   m.ns=n+1;
  }

//+------------------------------------------------------------------+
//| Exports one symbol. Returns false only on a failure that makes the |
//| file unusable; a day with no ticks is normal (weekend, holiday) and |
//| is counted, not treated as an error.                               |
//+------------------------------------------------------------------+
bool ExportSymbol(const string sym,long &out_ticks,long &out_minutes,
                  long &out_empty_days,long &out_dropped,
                  datetime &out_first,datetime &out_last)
  {
   out_ticks=0; out_minutes=0; out_empty_days=0; out_dropped=0;
   out_first=0; out_last=0;

   if(!SymbolSelect(sym,true))
     {
      PrintFormat("XSP_EXPORT FAIL SymbolSelect('%s') err=%d",sym,GetLastError());
      return(false);
     }
   const int    digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   const double point =SymbolInfoDouble(sym,SYMBOL_POINT);
   if(point<=0.0)
     {
      PrintFormat("XSP_EXPORT FAIL '%s' point=%.10f",sym,point);
      return(false);
     }

   CXspCsv csv;
   if(!csv.Open(InpPrefix+sym+".csv",true)) return(false);
   csv.SetFlushInterval(2000);

   csv.WriteComment(StringFormat("xsp_export: schema=%s; symbol=%s; digits=%d; point=%.10f; "
                                 "price=BID; from=%s; to=%s (exclusive); source=terminal tick archive "
                                 "via CopyTicksRange on a live chart - NOT the strategy tester",
                                 XSP_EXPORT_SCHEMA,sym,digits,point,
                                 TimeToString(InpFrom,TIME_DATE|TIME_MINUTES),
                                 TimeToString(InpTo,TIME_DATE|TIME_MINUTES)));
   csv.WriteComment("xsp_export_caveats: spread_med_pts and spread_p90_pts are quantiles of "
                    "(ask-bid)/point over the ticks of that minute; ticks counts EVERY tick, "
                    "spread_n counts only those with a usable two-sided quote. This is a broker "
                    "quote stream - not traded volume, not order flow, not depth of market.");
   csv.WriteHeader("epoch,o,h,l,c,ticks,spread_med_pts,spread_p90_pts,spread_n");

   //--- Day at a time. One CopyTicksRange for nine months would ask for a
   //--- ~60M-element MqlTick array; a day's worth is a few hundred
   //--- thousand at the February 2026 volatility peak and fits easily.
   const datetime day0=(datetime)((long)InpFrom/86400*86400);
   SXspMinute m; m.Reset();
   ArrayResize(g_spread,0,InpMaxSpreadSamples);

   for(datetime d=day0; d<InpTo; d+=86400)
     {
      MqlTick tk[];
      const ulong from_msc=(ulong)d*1000;
      const ulong to_msc  =(ulong)(d+86400)*1000-1;

      int got=-1;
      for(int attempt=0; attempt<5 && got<0; attempt++)
        {
         ResetLastError();
         got=CopyTicksRange(sym,tk,COPY_TICKS_ALL,from_msc,to_msc);
         //--- -1 on the first days of a symbol usually means the archive is
         //--- still being paged in. Retried, then reported: a silent zero
         //--- here would read as a market holiday.
         if(got<0) Sleep(700);
        }
      if(got<0)
        {
         PrintFormat("XSP_EXPORT FAIL CopyTicksRange('%s',%s) err=%d",
                     sym,TimeToString(d,TIME_DATE),GetLastError());
         csv.Close();
         return(false);
        }
      if(got==0) { out_empty_days++; ArrayFree(tk); continue; }

      for(int i=0; i<got; i++)
        {
         //--- Ticks outside the declared span are dropped even though the
         //--- day containing them was fetched: InpTo is exclusive and VAL
         //--- must not leak in through a partial final day.
         if(tk[i].time<InpFrom || tk[i].time>=InpTo) continue;
         const double bid=tk[i].bid;
         if(bid<=0.0) continue;

         const long bucket=(long)tk[i].time/60;
         if(bucket!=m.bucket)
           {
            if(!FlushMinute(csv,m,digits)) { csv.Close(); return(false); }
            if(m.bucket>=0) { out_minutes++; out_dropped+=m.ns_dropped; }
            m.Reset();
            ArrayResize(g_spread,0,InpMaxSpreadSamples);
            m.bucket=bucket;
            m.o=bid; m.h=bid; m.l=bid;
            if(out_first==0) out_first=(datetime)(bucket*60);
           }
         if(bid>m.h) m.h=bid;
         if(bid<m.l) m.l=bid;
         m.c=bid;
         m.ticks++;
         out_ticks++;
         out_last=(datetime)(bucket*60);

         const double ask=tk[i].ask;
         if(ask>0.0 && ask>=bid) PushSpread(m,(ask-bid)/point,InpMaxSpreadSamples);
        }
      ArrayFree(tk);
     }
   //--- The final minute has no successor to trigger its flush.
   if(!FlushMinute(csv,m,digits)) { csv.Close(); return(false); }
   if(m.bucket>=0) { out_minutes++; out_dropped+=m.ns_dropped; }

   csv.WriteComment(StringFormat("xsp_export_totals: ticks=%I64d; minutes=%I64d; empty_days=%I64d; "
                                 "spread_samples_dropped=%I64d; first=%s; last=%s; rows=%I64d",
                                 out_ticks,out_minutes,out_empty_days,out_dropped,
                                 TimeToString(out_first,TIME_DATE|TIME_MINUTES),
                                 TimeToString(out_last,TIME_DATE|TIME_MINUTES),csv.Rows()));
   csv.Close();
   return(true);
  }

//+------------------------------------------------------------------+
//| Both symbols in one run, so the two files carry the same span and  |
//| the alignment the study depends on can be checked rather than       |
//| assumed. A failure on either symbol fails the whole export: a       |
//| half-written pair is the one outcome that could be mistaken for a   |
//| usable dataset.                                                    |
//|                                                                  |
//| XSP_EXPORT is NOT added to runharness.ps1's verdict pattern. That   |
//| script runs Experts through the tester and can never reach a        |
//| script, so listing the token there would advertise coverage that    |
//| does not exist - the defect already fixed once in that file.        |
//+------------------------------------------------------------------+
void OnStart()
  {
   if(InpTo<=InpFrom)
     {
      Print("XSP_EXPORT FAIL InpTo must be after InpFrom");
      Print("XSP_EXPORT symbols=0 VERDICT=FAIL");
      return;
     }
   //--- Audit 9.1 seals VAL. Refused here rather than trusted to the
   //--- operator, because a single wrong input would spend the one look.
   if(InpTo>D'2026.03.01 00:00')
     {
      PrintFormat("XSP_EXPORT FAIL InpTo=%s crosses into VAL (2026.03.01+). "
                  "VAL is one look at one frozen candidate and this is not it.",
                  TimeToString(InpTo,TIME_DATE|TIME_MINUTES));
      Print("XSP_EXPORT symbols=0 VERDICT=FAIL");
      return;
     }

   string syms[];
   const int n=StringSplit(InpSymbols,',',syms);
   if(n<=0) { Print("XSP_EXPORT FAIL no symbols"); Print("XSP_EXPORT symbols=0 VERDICT=FAIL"); return; }

   int ok=0;
   for(int i=0; i<n; i++)
     {
      const string sym=syms[i];
      if(StringLen(sym)==0) continue;
      long ticks=0,minutes=0,empty=0,dropped=0;
      datetime first=0,last=0;
      const uint t0=GetTickCount();
      if(!ExportSymbol(sym,ticks,minutes,empty,dropped,first,last))
        {
         PrintFormat("XSP_EXPORT FAIL symbol=%s",sym);
         continue;
        }
      ok++;
      PrintFormat("XSP_EXPORT %s ticks=%I64d minutes=%I64d empty_days=%I64d "
                  "spread_dropped=%I64d first=%s last=%s elapsed_ms=%u",
                  sym,ticks,minutes,empty,dropped,
                  TimeToString(first,TIME_DATE|TIME_MINUTES),
                  TimeToString(last,TIME_DATE|TIME_MINUTES),
                  GetTickCount()-t0);
      //--- Phase A recorded 60,541,601 ticks over this exact span. Printed
      //--- as a cross-check, not asserted: the tester counts the ticks it
      //--- was fed and this counts what the archive holds, so they can
      //--- differ at the boundaries without either being wrong.
      if(sym=="XAUUSD")
         PrintFormat("XSP_EXPORT %s cross-check: Phase A saw 60541601 ticks over the same span, "
                     "this export read %I64d (ratio %.4f)",sym,ticks,
                     (ticks>0?(double)ticks/60541601.0:0.0));
     }
   PrintFormat("XSP_EXPORT symbols=%d of %d VERDICT=%s",ok,n,(ok==n?"PASS":"FAIL"));
  }
//+------------------------------------------------------------------+



