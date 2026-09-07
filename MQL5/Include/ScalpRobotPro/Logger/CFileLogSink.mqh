//+------------------------------------------------------------------+
//|                                                CFileLogSink.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Logger : persists records to MQL5/Files with rotation.           |
//|                                                                  |
//|   Owns exactly one file handle and closes it in the destructor, so |
//|   an abnormal teardown cannot leave a locked file behind.          |
//+------------------------------------------------------------------+
#ifndef SRP_LOGGER_CFILELOGSINK_MQH
#define SRP_LOGGER_CFILELOGSINK_MQH

#include "../Core/Interfaces/ILogSink.mqh"
#include "../Core/Types/Constants.mqh"

class CFileLogSink : public ILogSink
  {
private:
   ENUM_SRP_LOG_LEVEL m_threshold;
   string             m_folder;
   string             m_file_name;
   int                m_handle;
   bool               m_daily_rotation;
   bool               m_flush_every_record; // immediate flush for crash safety
   datetime           m_current_day;
   long               m_records_written;
   long               m_max_records;

   string            BuildFileName(const datetime for_day) const;
   bool              RotateIfNeeded(void);

public:
                     CFileLogSink(const ENUM_SRP_LOG_LEVEL threshold=SRP_LOG_DEBUG,
                                  const bool daily_rotation=true);
                    ~CFileLogSink(void);

   void              SetFolder(const string folder);
   void              SetMaxRecords(const long max_records);
   void              SetFlushEveryRecord(const bool value);

   virtual string                 SinkName(void) override { return("FileSink"); }
   virtual ENUM_SRP_LOG_SINK_KIND Kind(void)     override { return(SRP_SINK_FILE); }

   virtual bool      Open(void) override;
   virtual void      Close(void) override;
   virtual void      Flush(void) override;

   virtual void      SetThreshold(const ENUM_SRP_LOG_LEVEL level) override { m_threshold=level; }
   virtual bool      Accepts(const ENUM_SRP_LOG_LEVEL level) override;

   virtual void      Write(const ENUM_SRP_LOG_LEVEL level,
                           const string formatted_record) override;

   long              RecordsWritten(void) const { return(m_records_written); }
  };

#endif // SRP_LOGGER_CFILELOGSINK_MQH
//+------------------------------------------------------------------+
