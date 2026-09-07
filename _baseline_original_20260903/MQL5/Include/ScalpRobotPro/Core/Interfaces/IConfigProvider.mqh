//+------------------------------------------------------------------+
//|                                              IConfigProvider.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : read-only settings access.                   |
//|                                                                  |
//|   Modules receive a CONST provider, so configuration is           |
//|   immutable at runtime from a module's point of view. Only the     |
//|   bootstrapper populates it, once, before the graph is wired.     |
//|   This eliminates the classic MQL5 problem of `input` variables    |
//|   being referenced from everywhere.                               |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_ICONFIGPROVIDER_MQH
#define SRP_CORE_INTERFACES_ICONFIGPROVIDER_MQH

#include "../Types/Structs.mqh"

interface IConfigProvider
  {
   //--- Typed lookups. Every getter takes a default so a missing key
   //--- can never produce an undefined value.
   bool              GetBool(const string key,const bool fallback);
   int               GetInt(const string key,const int fallback);
   long              GetLong(const string key,const long fallback);
   double            GetDouble(const string key,const double fallback);
   string            GetString(const string key,const string fallback);

   bool              HasKey(const string key);

   //--- Whole-configuration coherence check, executed at startup.
   //--- Returns false to abort initialisation.
   bool              Validate(SValidationResult &result);

   //--- Human-readable dump for the log header and support tickets.
   string            Describe(void);
  };

#endif // SRP_CORE_INTERFACES_ICONFIGPROVIDER_MQH
//+------------------------------------------------------------------+
