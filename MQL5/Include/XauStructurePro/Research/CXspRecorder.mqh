//+------------------------------------------------------------------+
//|                                                 CXspRecorder.mqh |
//|      XauStructurePro - Research : ONE ROW PER INSTANCE, and every |
//|                                       label the analysis will cut on |
//|                                                                  |
//|   THIS FILE IS THE FALSIFICATION INSTRUMENT. It did not exist before.    |
//|   Exploration finding 1: SRP's CTradeJournal is reachable only from      |
//|   CStatisticsEngine, CEngineBootstrapper and CTradingEngine, none of      |
//|   which CProductionEngine touches, and SRP_JOURNAL_FILE is defined at    |
//|   Constants.mqh:50 and referenced nowhere. Every number in the audit      |
//|   came from tester summary reports, not from per-instance records - so    |
//|   no previous result could be re-cut, re-costed or re-tested without      |
//|   re-running the tape. Phase A had to BUILD the recorder, not enable one. |
//|                                                                  |
//|   LABELS ARE CAPTURED AT TRIGGER, ROWS ARE WRITTEN AT CLOSE. Those are    |
//|   different instants up to 60 minutes apart, so the labels are parked in  |
//|   a pending table keyed on instance id. A closed instance with no         |
//|   pending entry is an ORPHAN and is reported rather than written with     |
//|   blank labels, because a row whose regime column is empty would silently  |
//|   fall out of every cut the analysis makes.                              |
//+------------------------------------------------------------------+
#ifndef XSP_RESEARCH_CXSPRECORDER_MQH
#define XSP_RESEARCH_CXSPRECORDER_MQH

#include "CXspCsv.mqh"
#include "../Core/XspTypes.mqh"
#include "../Core/CXspStats.mqh"

struct SXspLabels
  {
   bool              used;
   long              id;
   SXspCandidate     cand;
   SXspRegime        regime;
   SXspContext       context;
   SXspConfirm       confirm;
  };

class CXspRecorder
  {
private:
   CXspCsv           m_csv;
   SXspLabels        m_pending[];
   int               m_digits;
   long              m_rows;
   long              m_orphans;
   long              m_label_overflow;

public:
                     CXspRecorder(void)
     {
      m_digits=2;
      m_rows=0;
      m_orphans=0;
      m_label_overflow=0;
      ArrayResize(m_pending,XSP_MAX_LIVE_INSTANCES);
      for(int i=0;i<XSP_MAX_LIVE_INSTANCES;i++) m_pending[i].used=false;
     }

   long              Rows(void)          const { return(m_rows); }
   long              Orphans(void)       const { return(m_orphans); }
   long              LabelOverflow(void) const { return(m_label_overflow); }
   bool              IsOpen(void)        const { return(m_csv.IsOpen()); }
   string            Path(void)          const { return(m_csv.Path()); }
   bool              IsCommon(void)      const { return(m_csv.IsCommon()); }

   bool              Open(const string filename,const int digits,const bool use_common=true)
     {
      m_digits=(digits>0?digits:2);
      return(m_csv.Open(filename,use_common));
     }

   void              Close(void) { m_csv.Close(); }
   void              Flush(void) { m_csv.Flush(); }

   //--- A '#' preamble line. Provenance goes here, so no extract of this
   //--- file can be quoted without the tick model that produced it.
   bool              Comment(const string text) { return(m_csv.WriteComment(text)); }

   bool              WriteHeader(void) { return(m_csv.WriteHeader(Columns())); }

   //+---------------------------------------------------------------+
   //| THE SCHEMA. This string and BuildRow() below must agree column   |
   //| for column. They are adjacent in one file for that reason: a      |
   //| header and a row builder in two files drift, and a CSV whose      |
   //| columns are off by one still parses.                             |
   //+---------------------------------------------------------------+
   static string     Columns(void)
     {
      return("instance_id,fingerprint,setup,direction,"
             "event_bar_epoch,trigger_epoch,trigger_time_server,"
             "ref_entry_bid,fill_price,spread_pts_at_trigger,"
             "invalidation,level_price,pool_kind,stop_pts,atr_pts_at_event,"
             "sec_to_stop,sec_to_tgt_r100,sec_to_tgt_r150,sec_to_tgt_r200,sec_to_tgt_r300,"
             "mfe_pts,mae_pts,mfe_r,mae_r,sec_to_mfe,"
             "r_at_cap_300,r_at_cap_900,r_at_cap_1800,r_at_cap_3600,"
             "tracked_seconds,ticks_seen,"
             "vol_decile,spread_decile,h1_trend,h4_trend,h1_aligned,h4_aligned,"
             "h1_range_pos,session,minute_of_day,"
             "broker_tick_volume,tickvol_slot_median,tickvol_slot_samples,"
             "tickvol_ratio,tickvol_confirm_pass");
     }

   //--- Park the labels for an instance that has just opened.
   bool              Note(const long id,const SXspCandidate &cand,const SXspRegime &regime,
                          const SXspContext &context,const SXspConfirm &confirm)
     {
      for(int i=0;i<XSP_MAX_LIVE_INSTANCES;i++)
        {
         if(m_pending[i].used) continue;
         m_pending[i].used=true;
         m_pending[i].id=id;
         m_pending[i].cand=cand;
         m_pending[i].regime=regime;
         m_pending[i].context=context;
         m_pending[i].confirm=confirm;
         return(true);
        }
      //--- Cannot happen while the table is the same size as the tracker's
      //--- live array, which is why it is reported rather than ignored: if it
      //--- ever fires, the two capacities have drifted apart.
      m_label_overflow++;
      PrintFormat("XSP_REC FAIL label table full - instance %I64d will orphan",id);
      return(false);
     }

   //+---------------------------------------------------------------+
   //| Write one closed instance and release its labels.                |
   //+---------------------------------------------------------------+
   bool              Write(const SXspInstance &ins)
     {
      const int slot=FindPending(ins.id);
      if(slot<0)
        {
         m_orphans++;
         PrintFormat("XSP_REC FAIL orphan instance %I64d (%s) - NOT written",
                     ins.id,ins.fingerprint);
         return(false);
        }
      const string row=BuildRow(ins,m_pending[slot]);
      m_pending[slot].used=false;
      if(!m_csv.WriteRow(row)) return(false);
      m_rows++;
      return(true);
     }

   //--- Labels still parked when the run ends. Non-zero means instances
   //--- were noted but never closed, which the tracker's FlushUnresolved
   //--- should have prevented; reported so the two counts can be reconciled.
   int               PendingLabels(void) const
     {
      int n=0;
      for(int i=0;i<XSP_MAX_LIVE_INSTANCES;i++)
         if(m_pending[i].used) n++;
      return(n);
     }

   string            Describe(void) const
     {
      return(StringFormat("recorder rows=%I64d orphans=%I64d label_overflow=%I64d pending=%d path='%s' common=%s",
                          m_rows,m_orphans,m_label_overflow,PendingLabels(),
                          m_csv.Path(),(m_csv.IsCommon()?"yes":"no")));
     }

   //+---------------------------------------------------------------+
   //| TEST SEAM, and the only reason BuildRow can stay private.        |
   //|                                                                |
   //| XspCheck renders a fully-populated instance through the REAL row |
   //| builder and asserts field-by-field against Columns(). A test     |
   //| that re-implemented the formatting would pass while the shipped   |
   //| builder was off by one column, which is the exact failure this    |
   //| schema is arranged to make impossible.                           |
   //+---------------------------------------------------------------+
   string            RenderTestRow(const SXspInstance &ins,const SXspLabels &lab) const
     {
      return(BuildRow(ins,lab));
     }

private:
   int               FindPending(const long id) const
     {
      for(int i=0;i<XSP_MAX_LIVE_INSTANCES;i++)
         if(m_pending[i].used && m_pending[i].id==id) return(i);
      return(-1);
     }

   string            Px(const double v)  const { return(DoubleToString(v,m_digits)); }
   static string     Pt(const double v)        { return(DoubleToString(v,2)); }
   static string     Rr(const double v)        { return(DoubleToString(v,4)); }
   static string     Ib(const bool v)          { return(v?"1":"0"); }

   //+---------------------------------------------------------------+
   //| Row builder. Assembled in four blocks that mirror the four        |
   //| groups of Columns() above, so a column added to one and not the   |
   //| other is visible as a length mismatch in the same screenful       |
   //| rather than as a silent shift somewhere in a 45-column line.      |
   //+---------------------------------------------------------------+
   string            BuildRow(const SXspInstance &ins,const SXspLabels &lab) const
     {
      //--- 1-15 identity, setup and prices
      string row=StringFormat("%I64d,%s,%s,%s,%I64d,%I64d,%s,",
                              ins.id,
                              CXspCsv::Sanitise(ins.fingerprint),
                              XspSetupName(ins.setup),
                              XspDirName(ins.dir),
                              (long)ins.event_bar_time,
                              (long)ins.trigger_time,
                              TimeToString(ins.trigger_time,TIME_DATE|TIME_SECONDS));
      row+=Px(ins.ref_entry)+","+Px(ins.fill_price)+","+Pt(ins.spread_points)+",";
      row+=Px(ins.invalidation)+","+Px(lab.cand.level_price)+","
           +XspPoolName(lab.cand.pool_kind)+","
           +Pt(ins.stop_points)+","+Pt(lab.cand.atr_points)+",";

      //--- 16-20 barrier times. ONE stop shared by four targets; each
      //--- tier's outcome is derived by comparing these, so the four tiers
      //--- cannot contradict one another. XSP_NEVER (-1) means the barrier
      //--- was not reached inside the tracking window - which is a
      //--- different statement from "reached at second 0".
      row+=IntegerToString(ins.sec_to_stop)+",";
      for(int t=0;t<XSP_R_TIERS;t++)
         row+=IntegerToString(ins.sec_to_target[t])+",";

      //--- 21-31 excursions, cap marks and the tracking census
      const double stop=(ins.stop_points>0.0?ins.stop_points:1.0);
      row+=Pt(ins.mfe_points)+","+Pt(ins.mae_points)+","
           +Rr(ins.mfe_points/stop)+","+Rr(ins.mae_points/stop)+","
           +IntegerToString(ins.sec_to_mfe)+",";
      for(int c=0;c<XSP_CAP_TIERS;c++)
         row+=Rr(ins.move_at_cap[c])+",";
      row+=IntegerToString(ins.tracked_seconds)+","+IntegerToString(ins.ticks_seen)+",";

      return(row+LabelBlock(lab));
     }

   //+---------------------------------------------------------------+
   //| 32-45 THE LABELS. Every one of these is RECORDED, none is GATED.  |
   //| That is the whole reason the study can measure what each filter   |
   //| is worth: the H1-disagreeing rows and the confirmation-failing    |
   //| rows are present in the file, so an alignment or confirmation      |
   //| requirement is a cut applied afterwards and its effect is a        |
   //| difference between two populations from ONE run. Gate any of them  |
   //| here and the deleted population can never be priced again without  |
   //| a second pass over the tape - which is how a filter search turns   |
   //| into the parameter sweep audit 4.4 already showed to be worthless. |
   //|                                                                |
   //| -1 in either decile means the ranking window had too few samples   |
   //| to rank against, NOT decile zero. tickvol_slot_samples < 3 means    |
   //| ratio 0.0 was recorded because no median existed - both are         |
   //| distinguishable in the file, and both must be excluded rather      |
   //| than read as low values.                                          |
   //+---------------------------------------------------------------+
   string            LabelBlock(const SXspLabels &lab) const
     {
      string s=IntegerToString(lab.regime.vol_decile)+","
               +IntegerToString(lab.regime.spread_decile)+",";
      s+=XspTrendName(lab.context.h1_trend)+","+XspTrendName(lab.context.h4_trend)+",";
      s+=Ib(lab.context.h1_aligned)+","+Ib(lab.context.h4_aligned)+",";
      s+=Rr(lab.context.h1_range_pos)+",";
      s+=XspSessionName(lab.regime.session)+","
         +IntegerToString(lab.regime.minute_of_day)+",";

      //--- BROKER TICK VOLUME - a count of quote updates, i.e. a
      //--- participation proxy. Not traded volume, not order flow, not DOM.
      //--- The column names carry that qualification into the analysis so it
      //--- cannot be quietly promoted on the way through.
      s+=IntegerToString(lab.confirm.tick_volume)+","
         +Pt(lab.confirm.slot_median)+","
         +IntegerToString(lab.confirm.slot_samples)+","
         +Rr(lab.confirm.ratio)+","
         +Ib(lab.confirm.passed);
      return(s);
     }
  };

#endif // XSP_RESEARCH_CXSPRECORDER_MQH
//+------------------------------------------------------------------+
