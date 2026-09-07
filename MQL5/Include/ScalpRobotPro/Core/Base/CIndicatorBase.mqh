//+------------------------------------------------------------------+
//|                                               CIndicatorBase.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Base : abstract base for every indicator wrapper.         |
//|                                                                  |
//|   Owns the terminal handle and its deterministic release, plus    |
//|   readiness checks and buffer copying. Subclasses implement only  |
//|   OnCreateHandle() - the one line that differs between an MA and  |
//|   an ATR. This is where every RAII concern for indicators lives.  |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_BASE_CINDICATORBASE_MQH
#define SRP_CORE_BASE_CINDICATORBASE_MQH

#include "../Interfaces/IIndicator.mqh"
#include "CModuleIdentity.mqh"

class CIndicatorBase : public IIndicator
  {
protected:
   CModuleIdentity        m_id;
   ENUM_SRP_INDICATOR_ID  m_indicator_id;
   string                 m_symbol;
   ENUM_TIMEFRAMES        m_timeframe;
   int                    m_handle;
   int                    m_buffer_count;
   int                    m_minimum_bars;
   bool                   m_ready;
   datetime               m_last_refresh_bar;

   //--- Sole extension point: return a valid terminal handle.
   virtual int       OnCreateHandle(void)=0;

   //--- Optional hook for subclasses needing extra post-copy work.
   virtual bool      OnRefresh(void) { return(true); }

public:
                     CIndicatorBase(const string name,
                                    const ENUM_SRP_INDICATOR_ID id,
                                    const string symbol,
                                    const ENUM_TIMEFRAMES timeframe,
                                    ILogger *logger,
                                    const int buffer_count=1,
                                    const int minimum_bars=50)
     : m_indicator_id(id),
       m_symbol(symbol),
       m_timeframe(timeframe),
       m_handle(SRP_INVALID_HANDLE),
       m_buffer_count(buffer_count),
       m_minimum_bars(minimum_bars),
       m_ready(false),
       m_last_refresh_bar(0)
     {
      m_id.Configure(name,logger);
     }

   //--- Destructor guarantees the handle is released even if the
   //--- kernel never got to call Shutdown().
   virtual          ~CIndicatorBase(void) { ReleaseHandle(); }

   //--- IModule -----------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }

   virtual bool      Initialize(void) override
     {
      if(m_handle!=SRP_INVALID_HANDLE)
         return(true);
      m_handle=OnCreateHandle();
      if(m_handle==SRP_INVALID_HANDLE || m_handle==INVALID_HANDLE)
        {
         m_handle=SRP_INVALID_HANDLE;
         m_id.SetHealth(SRP_HEALTH_CRITICAL,"indicator handle creation failed");
         m_id.Error("failed to create indicator handle");
         return(false);
        }
      m_id.SetInitialized(true);
      return(true);
     }

   virtual void      Validate(SValidationResult &result) override
     {
      if(m_handle==SRP_INVALID_HANDLE)
         result.AddError(m_id.Name()+": indicator handle is invalid");
      if(Bars(m_symbol,m_timeframe)<m_minimum_bars)
         result.AddWarning(m_id.Name()+": history shorter than MinimumBars");
     }

   virtual void      Shutdown(void) override
     {
      ReleaseHandle();
      m_ready=false;
      m_id.SetInitialized(false);
     }

   virtual void      ReportHealth(SHealthReport &report) override
     {
      if(m_handle==SRP_INVALID_HANDLE)
         m_id.SetHealth(SRP_HEALTH_CRITICAL,"handle lost");
      else if(!m_ready)
         m_id.SetHealth(SRP_HEALTH_DEGRADED,"buffers not ready");
      else
         m_id.SetHealth(SRP_HEALTH_OK,"");
      m_id.FillReport(report,m_last_refresh_bar);
     }

   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- IIndicator --------------------------------------------------
   virtual ENUM_SRP_INDICATOR_ID IndicatorId(void) override { return(m_indicator_id); }
   virtual string    IndicatorName(void) override { return(m_id.Name()); }
   virtual int       Handle(void)        override { return(m_handle); }
   virtual bool      IsReady(void)       override { return(m_ready); }
   virtual int       BufferCount(void)   override { return(m_buffer_count); }
   virtual int       MinimumBars(void)   override { return(m_minimum_bars); }

   virtual bool      Refresh(void) override
     {
      if(m_handle==SRP_INVALID_HANDLE)
        {
         m_ready=false;
         return(false);
        }
      //--- BarsCalculated is the authoritative readiness signal; a
      //--- freshly created handle returns -1 for several ticks.
      const int calculated=BarsCalculated(m_handle);
      if(calculated<m_minimum_bars)
        {
         m_ready=false;
         return(false);
        }
      if(!OnRefresh())
        {
         m_ready=false;
         return(false);
        }
      m_ready=true;
      m_last_refresh_bar=(datetime)SeriesInfoInteger(m_symbol,m_timeframe,SERIES_LASTBAR_DATE);
      return(true);
     }

   virtual bool      GetValue(const int buffer_index,const int shift,double &value) override
     {
      value=0.0;
      if(!m_ready || buffer_index<0 || buffer_index>=m_buffer_count || shift<0)
         return(false);
      double buffer[];
      if(CopyBuffer(m_handle,buffer_index,shift,1,buffer)!=1)
         return(false);
      value=buffer[0];
      return(value!=EMPTY_VALUE);
     }

   virtual bool      GetSeries(const int buffer_index,const int start,
                               const int count,double &out[]) override
     {
      ArrayFree(out);
      if(!m_ready || buffer_index<0 || buffer_index>=m_buffer_count || count<1)
         return(false);
      return(CopyBuffer(m_handle,buffer_index,start,count,out)==count);
     }

protected:
   //--- Centralised release so no subclass can leak a handle.
   void              ReleaseHandle(void)
     {
      if(m_handle!=SRP_INVALID_HANDLE)
        {
         IndicatorRelease(m_handle);
         m_handle=SRP_INVALID_HANDLE;
        }
     }
  };

#endif // SRP_CORE_BASE_CINDICATORBASE_MQH
//+------------------------------------------------------------------+
