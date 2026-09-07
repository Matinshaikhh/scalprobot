//+------------------------------------------------------------------+
//|                                                 CFileReader.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Utilities : RAII wrapper around a single read handle.              |
//|                                                                  |
//|   Used by CCsvNewsProvider and CJsonStateStore. Same rationale as   |
//|   CFileWriter: deterministic handle release.                        |
//+------------------------------------------------------------------+
#ifndef SRP_UTILITIES_CFILEREADER_MQH
#define SRP_UTILITIES_CFILEREADER_MQH

class CFileReader
  {
private:
   int               m_handle;
   string            m_path;
   long              m_lines_read;

public:
                     CFileReader(void);
                    ~CFileReader(void);

   bool              Open(const string relative_path,
                          const bool common_folder=false);
   void              Close(void);

   bool              IsOpen(void)     const { return(m_handle!=INVALID_HANDLE); }
   bool              IsEndOfFile(void) const;
   string            Path(void)       const { return(m_path); }

   //--- Sequential reading ------------------------------------------
   bool              ReadLine(string &out_line);
   //--- Reads a CSV row already split on the delimiter.
   bool              ReadCsvRow(string &out_fields[],const string delimiter=",");
   //--- Convenience: whole file into an array of lines.
   bool              ReadAllLines(string &out_lines[]);

   long              LinesRead(void) const { return(m_lines_read); }
  };

//+------------------------------------------------------------------+
CFileReader::CFileReader(void)
  : m_handle(INVALID_HANDLE),
    m_path(""),
    m_lines_read(0)
  {
  }
//+------------------------------------------------------------------+
CFileReader::~CFileReader(void)
  {
   Close();
  }
//+------------------------------------------------------------------+
void CFileReader::Close(void)
  {
   if(m_handle!=INVALID_HANDLE)
     {
      FileClose(m_handle);
      m_handle=INVALID_HANDLE;
     }
  }
//+------------------------------------------------------------------+
bool CFileReader::IsEndOfFile(void) const
  {
   if(m_handle==INVALID_HANDLE)
      return(true);
   return(FileIsEnding(m_handle));
  }

#endif // SRP_UTILITIES_CFILEREADER_MQH
//+------------------------------------------------------------------+
