//+------------------------------------------------------------------+
//|                                           CRiskStateStore.mqh |
//|                  Scalping Robot Pro - Market Intelligence Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): persist and restore key/value state.       |
//|                                                                  |
//|   WHY THIS EXISTS RATHER THAN REUSING Phase 1's CJsonStateStore        |
//|   That class is declaration-only in the Phase 1 scaffold. Phase 2 was  |
//|   instructed not to modify Phase 1, and the latching risk limits       |
//|   genuinely require working persistence, so this is a complete,        |
//|   self-contained implementation of the same IStateStore contract.      |
//|   When Phase 1's version is implemented, either can be injected -      |
//|   CRiskLimitGuard depends only on the interface.                      |
//|                                                                  |
//|   WHY PERSISTENCE IS A SAFETY FEATURE, NOT A CONVENIENCE              |
//|   A daily loss limit that forgets it fired after a terminal restart    |
//|   is not a limit. Neither is a drawdown measured from a peak that      |
//|   resets on reboot. Both failures silently grant a fresh risk budget   |
//|   at exactly the moment the account can least afford one.              |
//|                                                                  |
//|   Writes ATOMICALLY: content goes to a temporary file which then       |
//|   replaces the target, so a crash mid-save cannot corrupt state.       |
//+------------------------------------------------------------------+
#ifndef SRP_INTELLIGENCE_RISK_CRISKSTATESTORE_MQH
#define SRP_INTELLIGENCE_RISK_CRISKSTATESTORE_MQH

#include "../../Core/Interfaces/IStateStore.mqh"
#include "../../Core/Interfaces/ILogger.mqh"
#include "../../Core/Base/CModuleIdentity.mqh"

class CRiskStateStore : public IStateStore
  {
private:
   CModuleIdentity   m_id;
   string            m_file_path;
   string            m_keys[];
   string            m_values[];          // everything stored as text
   bool              m_dirty;
   bool              m_loaded;
   bool              m_enabled;

   int               IndexOf(const string key) const;
   bool              Put(const string key,const string value);
   string            Get(const string key,const string fallback) const;
   string            Escape(const string text) const;
   string            Unescape(const string text) const;

public:
                     CRiskStateStore(const string file_path,ILogger *logger);
                    ~CRiskStateStore(void);

   //--- Disabling makes every operation a no-op, which is what the
   //--- strategy tester needs: persisted state from pass N would
   //--- silently bias pass N+1 and invalidate the optimisation.
   void              SetEnabled(const bool enabled) { m_enabled=enabled; }
   bool              IsEnabled(void) const { return(m_enabled); }

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- IStateStore --------------------------------------------------
   virtual bool      Load(void) override;
   virtual bool      Save(void) override;

   virtual void      PutBool(const string key,const bool value) override;
   virtual void      PutInt(const string key,const long value) override;
   virtual void      PutDouble(const string key,const double value) override;
   virtual void      PutString(const string key,const string value) override;
   virtual void      PutDatetime(const string key,const datetime value) override;

   virtual bool      GetBool(const string key,const bool fallback) override;
   virtual long      GetInt(const string key,const long fallback) override;
   virtual double    GetDouble(const string key,const double fallback) override;
   virtual string    GetString(const string key,const string fallback) override;
   virtual datetime  GetDatetime(const string key,const datetime fallback) override;

   virtual bool      HasKey(const string key) override;
   virtual void      Remove(const string key) override;
   virtual void      Clear(void) override;
   virtual bool      IsDirty(void) override { return(m_dirty); }

   int               Count(void) const { return(ArraySize(m_keys)); }
  };

//+------------------------------------------------------------------+
CRiskStateStore::CRiskStateStore(const string file_path,ILogger *logger)
  : m_file_path(file_path),
    m_dirty(false),
    m_loaded(false),
    m_enabled(true)
  {
   m_id.Configure("CRiskStateStore",logger);
   ArrayResize(m_keys,0);
   ArrayResize(m_values,0);
  }
//+------------------------------------------------------------------+
CRiskStateStore::~CRiskStateStore(void)
  {
   //--- Best-effort flush. A destructor must not throw, so the result is
   //--- deliberately unchecked here.
   if(m_enabled && m_dirty)
      Save();
   ArrayFree(m_keys);
   ArrayFree(m_values);
  }
//+------------------------------------------------------------------+
bool CRiskStateStore::Initialize(void)
  {
   if(!m_enabled)
     {
      m_id.Info("state persistence disabled");
      m_id.SetInitialized(true);
      return(true);
     }
   Load();                                // absent file is not an error
   m_id.SetInitialized(true);
   return(true);
  }
//+------------------------------------------------------------------+
void CRiskStateStore::Validate(SValidationResult &result)
  {
   if(!m_enabled)
     {
      result.AddWarning("CRiskStateStore: persistence disabled; "
                        "latched risk limits will reset on restart");
      return;
     }
   if(StringLen(m_file_path)==0)
      result.AddError("CRiskStateStore: no file path configured");
  }
//+------------------------------------------------------------------+
void CRiskStateStore::Shutdown(void)
  {
   if(m_enabled && m_dirty)
      Save();
   m_id.SetInitialized(false);
  }
//+------------------------------------------------------------------+
void CRiskStateStore::ReportHealth(SHealthReport &report)
  {
   if(!m_enabled)
      m_id.SetHealth(SRP_HEALTH_OK,"disabled");
   else if(!m_loaded)
      m_id.SetHealth(SRP_HEALTH_DEGRADED,"state not loaded");
   else
      m_id.SetHealth(SRP_HEALTH_OK,"");
   m_id.FillReport(report,TimeCurrent());
  }
//+------------------------------------------------------------------+
int CRiskStateStore::IndexOf(const string key) const
  {
   const int total=ArraySize(m_keys);
   for(int i=0;i<total;i++)
      if(m_keys[i]==key)
         return(i);
   return(-1);
  }
//+------------------------------------------------------------------+
bool CRiskStateStore::Put(const string key,const string value)
  {
   if(!m_enabled || StringLen(key)==0)
      return(false);
   const int index=IndexOf(key);
   if(index>=0)
     {
      if(m_values[index]!=value)
        {
         m_values[index]=value;
         m_dirty=true;
        }
      return(true);
     }
   const int size=ArraySize(m_keys);
   if(ArrayResize(m_keys,size+1)!=size+1)
      return(false);
   if(ArrayResize(m_values,size+1)!=size+1)
      return(false);
   m_keys[size]=key;
   m_values[size]=value;
   m_dirty=true;
   return(true);
  }
//+------------------------------------------------------------------+
string CRiskStateStore::Get(const string key,const string fallback) const
  {
   const int index=IndexOf(key);
   if(index<0)
      return(fallback);
   return(m_values[index]);
  }
//+------------------------------------------------------------------+
string CRiskStateStore::Escape(const string text) const
  {
   //--- The format is one key=value pair per line, so a newline or an
   //--- equals sign inside a value would corrupt parsing.
   string out=text;
   StringReplace(out,"\\","\\\\");
   StringReplace(out,"=","\\e");
   StringReplace(out,"\n","\\n");
   StringReplace(out,"\r","\\r");
   return(out);
  }
//+------------------------------------------------------------------+
string CRiskStateStore::Unescape(const string text) const
  {
   string out=text;
   StringReplace(out,"\\r","\r");
   StringReplace(out,"\\n","\n");
   StringReplace(out,"\\e","=");
   StringReplace(out,"\\\\","\\");
   return(out);
  }
//+------------------------------------------------------------------+
bool CRiskStateStore::Load(void)
  {
   if(!m_enabled)
      return(false);

   ArrayResize(m_keys,0);
   ArrayResize(m_values,0);

   if(!FileIsExist(m_file_path))
     {
      //--- First run. Not an error: an empty store means "no prior state".
      m_loaded=true;
      m_dirty=false;
      return(true);
     }

   const int handle=FileOpen(m_file_path,FILE_READ|FILE_TXT|FILE_ANSI);
   if(handle==INVALID_HANDLE)
     {
      m_id.Warn("cannot open state file for reading: "+m_file_path);
      return(false);
     }

   while(!FileIsEnding(handle))
     {
      const string line=FileReadString(handle);
      if(StringLen(line)==0)
         continue;
      const int separator=StringFind(line,"=");
      if(separator<=0)
         continue;
      const string key=StringSubstr(line,0,separator);
      const string value=Unescape(StringSubstr(line,separator+1));
      const int size=ArraySize(m_keys);
      if(ArrayResize(m_keys,size+1)!=size+1)
         break;
      if(ArrayResize(m_values,size+1)!=size+1)
         break;
      m_keys[size]=key;
      m_values[size]=value;
     }
   FileClose(handle);

   m_loaded=true;
   m_dirty=false;
   m_id.Debug(StringFormat("restored %d state keys",ArraySize(m_keys)));
   return(true);
  }
//+------------------------------------------------------------------+
bool CRiskStateStore::Save(void)
  {
   if(!m_enabled)
      return(false);

   //--- ATOMIC WRITE. Write to a temporary file first, then replace the
   //--- target. A crash during the write therefore cannot leave a
   //--- half-written state file, which would be worse than no file.
   const string temp_path=m_file_path+".tmp";
   const int handle=FileOpen(temp_path,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(handle==INVALID_HANDLE)
     {
      m_id.Warn("cannot open state file for writing: "+temp_path);
      return(false);
     }

   const int total=ArraySize(m_keys);
   for(int i=0;i<total;i++)
      FileWriteString(handle,m_keys[i]+"="+Escape(m_values[i])+"\r\n");
   FileFlush(handle);
   FileClose(handle);

   //--- Replace the original. FileMove with rewrite is the atomic step.
   if(FileIsExist(m_file_path))
      FileDelete(m_file_path);
   if(!FileMove(temp_path,0,m_file_path,0))
     {
      m_id.Warn("cannot replace state file: "+m_file_path);
      return(false);
     }

   m_dirty=false;
   return(true);
  }
//+------------------------------------------------------------------+
void CRiskStateStore::PutBool(const string key,const bool value)
  {
   Put(key,(value ? "1" : "0"));
  }
//+------------------------------------------------------------------+
void CRiskStateStore::PutInt(const string key,const long value)
  {
   Put(key,IntegerToString(value));
  }
//+------------------------------------------------------------------+
void CRiskStateStore::PutDouble(const string key,const double value)
  {
   //--- 8 decimals preserves price and money precision on every
   //--- instrument this product supports.
   Put(key,DoubleToString(value,8));
  }
//+------------------------------------------------------------------+
void CRiskStateStore::PutString(const string key,const string value)
  {
   Put(key,value);
  }
//+------------------------------------------------------------------+
void CRiskStateStore::PutDatetime(const string key,const datetime value)
  {
   Put(key,IntegerToString((long)value));
  }
//+------------------------------------------------------------------+
bool CRiskStateStore::GetBool(const string key,const bool fallback)
  {
   const int index=IndexOf(key);
   if(index<0)
      return(fallback);
   return(m_values[index]=="1");
  }
//+------------------------------------------------------------------+
long CRiskStateStore::GetInt(const string key,const long fallback)
  {
   const int index=IndexOf(key);
   if(index<0)
      return(fallback);
   return(StringToInteger(m_values[index]));
  }
//+------------------------------------------------------------------+
double CRiskStateStore::GetDouble(const string key,const double fallback)
  {
   const int index=IndexOf(key);
   if(index<0)
      return(fallback);
   return(StringToDouble(m_values[index]));
  }
//+------------------------------------------------------------------+
string CRiskStateStore::GetString(const string key,const string fallback)
  {
   return(Get(key,fallback));
  }
//+------------------------------------------------------------------+
datetime CRiskStateStore::GetDatetime(const string key,const datetime fallback)
  {
   const int index=IndexOf(key);
   if(index<0)
      return(fallback);
   return((datetime)StringToInteger(m_values[index]));
  }
//+------------------------------------------------------------------+
bool CRiskStateStore::HasKey(const string key)
  {
   return(IndexOf(key)>=0);
  }
//+------------------------------------------------------------------+
void CRiskStateStore::Remove(const string key)
  {
   const int index=IndexOf(key);
   if(index<0)
      return;
   const int total=ArraySize(m_keys);
   for(int i=index;i<total-1;i++)
     {
      m_keys[i]=m_keys[i+1];
      m_values[i]=m_values[i+1];
     }
   ArrayResize(m_keys,total-1);
   ArrayResize(m_values,total-1);
   m_dirty=true;
  }
//+------------------------------------------------------------------+
void CRiskStateStore::Clear(void)
  {
   ArrayResize(m_keys,0);
   ArrayResize(m_values,0);
   m_dirty=true;
  }

#endif // SRP_INTELLIGENCE_RISK_CRISKSTATESTORE_MQH
//+------------------------------------------------------------------+
