//+------------------------------------------------------------------+
//|                                        CInputConfiguration.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Configuration : IConfigProvider backed by the EA's input block.    |
//|                                                                  |
//|   RESPONSIBILITY (one only): hold typed key/value settings and       |
//|   answer lookups.                                                    |
//|                                                                  |
//|   THE BOUNDARY THAT MATTERS                                          |
//|   MQL5 `input` variables are global by nature. Referencing them      |
//|   directly from modules would couple every class to the .mq5 file    |
//|   and make unit testing impossible. Instead the .mq5 file copies     |
//|   its inputs into this object ONCE via CConfigurationBuilder, and    |
//|   modules see only IConfigProvider. The inputs stop at the boundary. |
//+------------------------------------------------------------------+
#ifndef SRP_CONFIGURATION_CINPUTCONFIGURATION_MQH
#define SRP_CONFIGURATION_CINPUTCONFIGURATION_MQH

#include "../Core/Interfaces/IConfigProvider.mqh"
#include "../Core/Interfaces/ILogger.mqh"

class CInputConfiguration : public IConfigProvider
  {
private:
   //--- Parallel arrays: MQL5 has no generic dictionary, and a pair of
   //--- arrays is faster and simpler than a hand-rolled hash map for
   //--- the ~120 keys this product uses.
   string            m_keys[];
   string            m_values[];
   ILogger          *m_logger;             // borrowed
   bool              m_sealed;             // true after Build completes

   long              m_miss_count;         // lookups that hit no key
   string            m_first_missed_key;

   int               IndexOf(const string key) const;
   bool              Store(const string key,const string value);
   void              RecordMiss(const string key);

public:
                     CInputConfiguration(ILogger *logger);
                    ~CInputConfiguration(void);

   //--- Population, used only by CConfigurationBuilder ---------------
   bool              SetBool(const string key,const bool value);
   bool              SetInt(const string key,const int value);
   bool              SetLong(const string key,const long value);
   bool              SetDouble(const string key,const double value);
   bool              SetString(const string key,const string value);

   //--- After sealing, every Set* call is refused and logged. This is
   //--- what makes configuration genuinely immutable at runtime.
   void              Seal(void);
   bool              IsSealed(void) const { return(m_sealed); }

   //--- IConfigProvider ----------------------------------------------
   virtual bool      GetBool(const string key,const bool fallback) override;
   virtual int       GetInt(const string key,const int fallback) override;
   virtual long      GetLong(const string key,const long fallback) override;
   virtual double    GetDouble(const string key,const double fallback) override;
   virtual string    GetString(const string key,const string fallback) override;
   virtual bool      HasKey(const string key) override;
   virtual bool      Validate(SValidationResult &result) override;
   virtual string    Describe(void) override;

   int               Count(void) const { return(ArraySize(m_keys)); }

   //--- Diagnostics: how many lookups missed. A non-zero count after a
   //--- clean startup means a module is asking for a key the builder
   //--- never wrote, which silently yields the fallback.
   long              MissCount(void) const { return(m_miss_count); }
   string            FirstMissedKey(void) const { return(m_first_missed_key); }
  };

//+------------------------------------------------------------------+
CInputConfiguration::CInputConfiguration(ILogger *logger)
  : m_logger(logger),
    m_sealed(false),
    m_miss_count(0),
    m_first_missed_key("")
  {
   ArrayResize(m_keys,0);
   ArrayResize(m_values,0);
  }
//+------------------------------------------------------------------+
CInputConfiguration::~CInputConfiguration(void)
  {
   //--- Both members are borrowed; only the arrays are ours and they
   //--- are released by the runtime.
   ArrayFree(m_keys);
   ArrayFree(m_values);
  }
//+------------------------------------------------------------------+
//| Linear scan. With ~230 keys touched once at startup and cached by  |
//| callers, a hash map would add complexity for no measurable gain -   |
//| and MQL5 has no generic dictionary to lean on.                      |
//+------------------------------------------------------------------+
int CInputConfiguration::IndexOf(const string key) const
  {
   const int total=ArraySize(m_keys);
   for(int i=0;i<total;i++)
      if(m_keys[i]==key)
         return(i);
   return(-1);
  }
//+------------------------------------------------------------------+
bool CInputConfiguration::Store(const string key,const string value)
  {
   //--- Sealing is the guarantee that configuration cannot drift at
   //--- runtime. A refused write is logged, never silently dropped.
   if(m_sealed)
     {
      if(m_logger!=NULL)
         m_logger.Error("Config","refused write to sealed configuration: "+key);
      return(false);
     }
   if(key=="")
      return(false);

   const int existing=IndexOf(key);
   if(existing>=0)
     {
      m_values[existing]=value;
      return(true);
     }
   const int total=ArraySize(m_keys);
   if(ArrayResize(m_keys,total+1)!=total+1)
      return(false);
   if(ArrayResize(m_values,total+1)!=total+1)
     {
      ArrayResize(m_keys,total);
      return(false);
     }
   m_keys[total]=key;
   m_values[total]=value;
   return(true);
  }
//+------------------------------------------------------------------+
bool CInputConfiguration::SetBool(const string key,const bool value)
  {
   return(Store(key,value ? "1" : "0"));
  }
//+------------------------------------------------------------------+
bool CInputConfiguration::SetInt(const string key,const int value)
  {
   return(Store(key,IntegerToString(value)));
  }
//+------------------------------------------------------------------+
bool CInputConfiguration::SetLong(const string key,const long value)
  {
   return(Store(key,IntegerToString(value)));
  }
//+------------------------------------------------------------------+
bool CInputConfiguration::SetDouble(const string key,const double value)
  {
   //--- Eight decimals preserves price precision on every instrument
   //--- including JPY crosses and crypto without scientific notation.
   return(Store(key,DoubleToString(value,8)));
  }
//+------------------------------------------------------------------+
bool CInputConfiguration::SetString(const string key,const string value)
  {
   return(Store(key,value));
  }
//+------------------------------------------------------------------+
void CInputConfiguration::Seal(void)
  {
   m_sealed=true;
   if(m_logger!=NULL)
      m_logger.Info("Config","sealed with "+IntegerToString(ArraySize(m_keys))+
                    " keys");
  }
//+------------------------------------------------------------------+
bool CInputConfiguration::GetBool(const string key,const bool fallback)
  {
   const int index=IndexOf(key);
   if(index<0)
     {
      RecordMiss(key);
      return(fallback);
     }
   //--- Accept the several spellings a hand-edited preset file may hold.
   const string value=m_values[index];
   if(value=="1" || value=="true" || value=="TRUE" || value=="yes")
      return(true);
   if(value=="0" || value=="false" || value=="FALSE" || value=="no")
      return(false);
   return(fallback);
  }
//+------------------------------------------------------------------+
int CInputConfiguration::GetInt(const string key,const int fallback)
  {
   const int index=IndexOf(key);
   if(index<0)
     {
      RecordMiss(key);
      return(fallback);
     }
   return((int)StringToInteger(m_values[index]));
  }
//+------------------------------------------------------------------+
long CInputConfiguration::GetLong(const string key,const long fallback)
  {
   const int index=IndexOf(key);
   if(index<0)
     {
      RecordMiss(key);
      return(fallback);
     }
   return(StringToInteger(m_values[index]));
  }
//+------------------------------------------------------------------+
double CInputConfiguration::GetDouble(const string key,const double fallback)
  {
   const int index=IndexOf(key);
   if(index<0)
     {
      RecordMiss(key);
      return(fallback);
     }
   return(StringToDouble(m_values[index]));
  }
//+------------------------------------------------------------------+
string CInputConfiguration::GetString(const string key,const string fallback)
  {
   const int index=IndexOf(key);
   if(index<0)
     {
      RecordMiss(key);
      return(fallback);
     }
   return(m_values[index]);
  }
//+------------------------------------------------------------------+
bool CInputConfiguration::HasKey(const string key)
  {
   return(IndexOf(key)>=0);
  }
//+------------------------------------------------------------------+
void CInputConfiguration::RecordMiss(const string key)
  {
   m_miss_count++;
   if(m_first_missed_key=="")
      m_first_missed_key=key;
   //--- Debug, not warn: a miss is legitimate for optional keys, and a
   //--- warning per lookup would flood the log. The counter is the
   //--- signal; MissCount() is asserted by the integration harness.
   if(m_logger!=NULL && m_logger.IsEnabled(SRP_LOG_DEBUG))
      m_logger.Debug("Config","key not present, using fallback: "+key);
  }
//+------------------------------------------------------------------+
bool CInputConfiguration::Validate(SValidationResult &result)
  {
   if(ArraySize(m_keys)<=0)
     {
      result.AddError("configuration is empty, the builder did not run");
      return(false);
     }
   if(!m_sealed)
      result.AddWarning("configuration is not sealed, runtime writes are "
                        "still possible");

   //--- STRUCTURAL CHECKS ONLY, BY DESIGN.
   //--- Domain coherence ("is 25% risk survivable?") belongs to
   //--- CConfigValidator, which the bootstrapper calls directly. Having
   //--- the container invoke the validator would make storage depend on
   //--- rules and rules depend on storage - a cycle that MQL5's
   //--- single-pass compiler cannot resolve anyway. The container answers
   //--- only "am I populated and locked".
   return(result.is_valid);
  }
//+------------------------------------------------------------------+
string CInputConfiguration::Describe(void)
  {
   //--- Written to the log header at startup. When a user reports odd
   //--- behaviour, this single dump answers "what was it actually
   //--- configured with" without a round of questions.
   string text="Configuration ("+IntegerToString(ArraySize(m_keys))+" keys, "+
               (m_sealed ? "sealed" : "OPEN")+")";
   const int total=ArraySize(m_keys);
   for(int i=0;i<total;i++)
      text+="\n  "+m_keys[i]+" = "+m_values[i];
   if(m_miss_count>0)
      text+="\n  [misses: "+IntegerToString(m_miss_count)+
            ", first: "+m_first_missed_key+"]";
   return(text);
  }

#endif // SRP_CONFIGURATION_CINPUTCONFIGURATION_MQH
//+------------------------------------------------------------------+
