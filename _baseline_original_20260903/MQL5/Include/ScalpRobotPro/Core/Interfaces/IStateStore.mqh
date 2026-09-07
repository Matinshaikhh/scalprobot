//+------------------------------------------------------------------+
//|                                                  IStateStore.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : durable key/value persistence.               |
//|                                                                  |
//|   Survives terminal restarts, so latched risk guards, daily       |
//|   counters and equity peaks are not silently reset by a reboot -   |
//|   a common and expensive failure in commercial EAs.                |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_ISTATESTORE_MQH
#define SRP_CORE_INTERFACES_ISTATESTORE_MQH

#include "IModule.mqh"

interface IStateStore : public IModule
  {
   bool              Load(void);
   bool              Save(void);

   void              PutBool(const string key,const bool value);
   void              PutInt(const string key,const long value);
   void              PutDouble(const string key,const double value);
   void              PutString(const string key,const string value);
   void              PutDatetime(const string key,const datetime value);

   bool              GetBool(const string key,const bool fallback);
   long              GetInt(const string key,const long fallback);
   double            GetDouble(const string key,const double fallback);
   string            GetString(const string key,const string fallback);
   datetime          GetDatetime(const string key,const datetime fallback);

   bool              HasKey(const string key);
   void              Remove(const string key);
   void              Clear(void);

   //--- True when the in-memory image differs from storage.
   bool              IsDirty(void);
  };

#endif // SRP_CORE_INTERFACES_ISTATESTORE_MQH
//+------------------------------------------------------------------+
