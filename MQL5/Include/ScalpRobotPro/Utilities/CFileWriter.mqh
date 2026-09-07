//+------------------------------------------------------------------+
//|                                                 CFileWriter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Utilities : RAII wrapper around a single write handle.             |
//|                                                                  |
//|   Guarantees the handle is closed in the destructor. Every file      |
//|   consumer (log sink, journal, state store, CSV export) uses this    |
//|   instead of raw FileOpen, so a leaked handle - which silently       |
//|   locks a file until the terminal restarts - becomes impossible.     |
//+------------------------------------------------------------------+
#ifndef SRP_UTILITIES_CFILEWRITER_MQH
#define SRP_UTILITIES_CFILEWRITER_MQH

#include "../Core/Types/Constants.mqh"

class CFileWriter
  {
private:
   int               m_handle;
   string            m_path;
   bool              m_is_common;
   int               m_flags;
   long              m_lines_written;

public:
                     CFileWriter(void);
                    ~CFileWriter(void);

   //--- Open modes. Both create the folder path as needed.
   bool              OpenForAppend(const string relative_path,
                                   const bool common_folder=false);
   bool              OpenForOverwrite(const string relative_path,
                                      const bool common_folder=false);
   void              Close(void);

   bool              IsOpen(void) const { return(m_handle!=INVALID_HANDLE); }
   string            Path(void)   const { return(m_path); }

   //--- Writing ------------------------------------------------------
   bool              WriteLine(const string text);
   bool              WriteCsvRow(const string &fields[]);
   void              Flush(void);

   long              LinesWritten(void) const { return(m_lines_written); }

   //--- Static helpers so callers need not open a file just to check.
   static bool       Exists(const string relative_path,
                            const bool common_folder=false);
   static bool       Delete(const string relative_path,
                            const bool common_folder=false);
   static bool       EnsureFolder(const string relative_folder,
                                  const bool common_folder=false);
  };

//+------------------------------------------------------------------+
CFileWriter::CFileWriter(void)
  : m_handle(INVALID_HANDLE),
    m_path(""),
    m_is_common(false),
    m_flags(0),
    m_lines_written(0)
  {
  }
//+------------------------------------------------------------------+
CFileWriter::~CFileWriter(void)
  {
   //--- The whole point of this class.
   Close();
  }
//+------------------------------------------------------------------+
void CFileWriter::Close(void)
  {
   if(m_handle!=INVALID_HANDLE)
     {
      FileFlush(m_handle);
      FileClose(m_handle);
      m_handle=INVALID_HANDLE;
     }
  }
//+------------------------------------------------------------------+
void CFileWriter::Flush(void)
  {
   if(m_handle!=INVALID_HANDLE)
      FileFlush(m_handle);
  }
//+------------------------------------------------------------------+
bool CFileWriter::WriteLine(const string text)
  {
   if(m_handle==INVALID_HANDLE)
      return(false);
   if(FileWrite(m_handle,text)<=0)
      return(false);
   m_lines_written++;
   return(true);
  }
//+------------------------------------------------------------------+
bool CFileWriter::Exists(const string relative_path,const bool common_folder)
  {
   return(FileIsExist(relative_path,common_folder ? FILE_COMMON : 0));
  }

#endif // SRP_UTILITIES_CFILEWRITER_MQH
//+------------------------------------------------------------------+
