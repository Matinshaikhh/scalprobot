//+------------------------------------------------------------------+
//|                                                      CXspCsv.mqh |
//|            XauStructurePro - Research : the per-instance CSV sink |
//|                                                                  |
//|   Written here rather than reused. SRP's CFileWriter declares          |
//|   OpenForAppend, OpenForOverwrite, WriteCsvRow, Delete and             |
//|   EnsureFolder with NO BODIES, so its handle can never leave           |
//|   INVALID_HANDLE and IsOpen() is false for the life of the object.     |
//|   It has never been compiler-tested because the only two files that    |
//|   reach it are the umbrella header the shipping EA does not include    |
//|   and CTradeJournal, which nothing constructs. Naming it in the plan   |
//|   was a mistake; this is the correction.                              |
//|                                                                  |
//|   COMMON FOLDER BY DEFAULT. Inside the strategy tester an ordinary     |
//|   FileOpen lands in <terminal>\Tester\<agent-N>\MQL5\Files, a          |
//|   different directory per agent that is wiped between runs. The study  |
//|   would then produce a file the analysis script cannot find, or worse  |
//|   find a stale one. FILE_COMMON resolves to one stable path for both   |
//|   tester and live.                                                    |
//+------------------------------------------------------------------+
#ifndef XSP_RESEARCH_CXSPCSV_MQH
#define XSP_RESEARCH_CXSPCSV_MQH

#include "../Core/XspConstants.mqh"

class CXspCsv
  {
private:
   int               m_handle;
   string            m_path;
   bool              m_common;
   long              m_rows;
   long              m_since_flush;
   int               m_flush_every;

public:
                     CXspCsv(void)
     {
      m_handle=INVALID_HANDLE;
      m_path="";
      m_common=true;
      m_rows=0;
      m_since_flush=0;
      //--- Flushed often on purpose. A tester run that is stopped by hand,
      //--- or that hits TesterStop, does not guarantee the tail of an
      //--- unflushed buffer reaches disk - and a truncated study file is
      //--- indistinguishable from a study that recorded fewer instances.
      m_flush_every=25;
     }

                    ~CXspCsv(void) { Close(); }

   bool              IsOpen(void) const { return(m_handle!=INVALID_HANDLE); }
   string            Path(void)   const { return(m_path); }
   long              Rows(void)   const { return(m_rows); }
   bool              IsCommon(void) const { return(m_common); }
   void              SetFlushInterval(const int rows) { m_flush_every=(rows>0?rows:1); }

   //+---------------------------------------------------------------+
   //| Open for OVERWRITE. One study run produces one file and         |
   //| replaces it wholly.                                            |
   //|                                                                |
   //| Deliberately not append. Appending across runs would let two    |
   //| different configurations, or two different tick models, share   |
   //| one file with only the provenance preamble of the FIRST run at  |
   //| the top - and every row after that would be quoted under        |
   //| provenance that did not produce it.                            |
   //+---------------------------------------------------------------+
   bool              Open(const string filename,const bool use_common=true)
     {
      Close();
      m_common=use_common;
      m_path=XSP_DATA_FOLDER+"\\"+filename;

      int flags=FILE_WRITE|FILE_TXT|FILE_ANSI;
      if(m_common) flags|=FILE_COMMON;

      //--- FolderCreate returns true when the folder already exists, so a
      //--- false here is a real permissions or path failure, not a re-run.
      if(!FolderCreate(XSP_DATA_FOLDER,(m_common?FILE_COMMON:0)))
        {
         const int fe=GetLastError();
         //--- 5019 = the folder is already there on some builds. Anything
         //--- else is reported and the open is still attempted, because
         //--- FileOpen creates missing folders on its own in most builds
         //--- and refusing here would fail a run that would have worked.
         if(fe!=0 && fe!=5019)
            PrintFormat("XSP_CSV WARN FolderCreate('%s') err=%d - attempting open anyway",
                        XSP_DATA_FOLDER,fe);
         ResetLastError();
        }

      m_handle=FileOpen(m_path,flags);
      if(m_handle==INVALID_HANDLE)
        {
         PrintFormat("XSP_CSV FAIL FileOpen('%s' common=%s) err=%d",
                     m_path,(m_common?"yes":"no"),GetLastError());
         return(false);
        }
      m_rows=0;
      m_since_flush=0;
      return(true);
     }

   void              Close(void)
     {
      if(m_handle==INVALID_HANDLE) return;
      FileFlush(m_handle);
      FileClose(m_handle);
      m_handle=INVALID_HANDLE;
     }

   //--- A '#'-prefixed preamble line: provenance, cost model, schema
   //--- version. Not counted as a row, so a row count in the log can be
   //--- compared against a line count on disk minus the preamble.
   bool              WriteComment(const string text)
     {
      if(m_handle==INVALID_HANDLE) return(false);
      return(WriteRaw("# "+Sanitise(text)));
     }

   //--- The column header. Written verbatim: it is authored comma-
   //--- separated and must not be sanitised, or every comma in it would
   //--- become a semicolon and the file would have one column.
   bool              WriteHeader(const string csv_columns)
     {
      if(m_handle==INVALID_HANDLE) return(false);
      return(WriteRaw(csv_columns));
     }

   //--- A data row, already comma-separated by the caller. Counted.
   bool              WriteRow(const string csv_row)
     {
      if(m_handle==INVALID_HANDLE) return(false);
      if(!WriteRaw(csv_row)) return(false);
      m_rows++;
      m_since_flush++;
      if(m_since_flush>=m_flush_every)
        {
         FileFlush(m_handle);
         m_since_flush=0;
        }
      return(true);
     }

   void              Flush(void)
     {
      if(m_handle!=INVALID_HANDLE) FileFlush(m_handle);
      m_since_flush=0;
     }

   //--- Field-level guard for any string that did not come from a
   //--- controlled label table - a symbol name, a broker string. A comma
   //--- inside one field shifts every later column by one and the file
   //--- still parses, so this cannot be left to inspection.
   static string     Sanitise(const string text)
     {
      string out=text;
      StringReplace(out,",",";");
      StringReplace(out,"\r"," ");
      StringReplace(out,"\n"," ");
      return(out);
     }

private:
   bool              WriteRaw(const string line)
     {
      const uint written=FileWriteString(m_handle,line+"\r\n");
      if(written==0)
        {
         PrintFormat("XSP_CSV FAIL FileWriteString err=%d",GetLastError());
         return(false);
        }
      return(true);
     }
  };

#endif // XSP_RESEARCH_CXSPCSV_MQH
//+------------------------------------------------------------------+
