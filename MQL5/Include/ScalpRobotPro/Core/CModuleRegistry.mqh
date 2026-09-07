//+------------------------------------------------------------------+
//|                                              CModuleRegistry.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : owns the lifetime of every IModule in the system.        |
//|                                                                  |
//|   RESPONSIBILITY (one only): construct-order bookkeeping and      |
//|   deterministic destruction. It initialises modules in            |
//|   registration order and shuts them down in exact reverse order,  |
//|   which is what makes teardown safe when module B borrowed a      |
//|   pointer to module A.                                           |
//|                                                                  |
//|   OWNERSHIP CONTRACT                                             |
//|   Modules registered here are OWNED - the registry deletes them.  |
//|   Every other class in the codebase holds borrowed pointers and    |
//|   must never delete a module. One owner, many borrowers.           |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CMODULEREGISTRY_MQH
#define SRP_CORE_CMODULEREGISTRY_MQH

#include "Interfaces/IModule.mqh"
#include "Interfaces/ILogger.mqh"

class CModuleRegistry
  {
private:
   IModule          *m_modules[];          // OWNED
   ILogger          *m_logger;             // borrowed
   int               m_initialized_count;  // how far Initialize() got

public:
                     CModuleRegistry(void);
                    ~CModuleRegistry(void);

   void              SetLogger(ILogger *logger) { m_logger=logger; }

   //--- Takes ownership. Returns false if the table is full, in which
   //--- case the caller must delete the module itself.
   bool              Register(IModule *module);

   //--- Initialise in registration order. On the first failure it
   //--- stops and returns false; ShutdownAll() then unwinds exactly
   //--- the modules that did initialise.
   bool              InitializeAll(void);

   //--- Post-wiring self-checks across all modules.
   void              ValidateAll(SValidationResult &result);

   //--- Reverse-order teardown, then deletion.
   void              ShutdownAll(void);

   //--- Health sweep, used by CHealthMonitor.
   int               Count(void) const { return(ArraySize(m_modules)); }
   IModule          *At(const int index) const;
   IModule          *FindByName(const string name) const;
  };

//+------------------------------------------------------------------+
CModuleRegistry::CModuleRegistry(void)
  : m_logger(NULL),
    m_initialized_count(0)
  {
   ArrayResize(m_modules,0);
  }
//+------------------------------------------------------------------+
CModuleRegistry::~CModuleRegistry(void)
  {
   ShutdownAll();
  }
//+------------------------------------------------------------------+
bool CModuleRegistry::Register(IModule *module)
  {
   if(module==NULL)
      return(false);
   const int total=ArraySize(m_modules);
   if(total>=SRP_MAX_MODULES)
     {
      if(m_logger!=NULL)
         m_logger.Error("CModuleRegistry","module table full: "+module.ModuleName());
      return(false);
     }
   if(ArrayResize(m_modules,total+1)!=total+1)
      return(false);
   m_modules[total]=module;
   return(true);
  }
//+------------------------------------------------------------------+
bool CModuleRegistry::InitializeAll(void)
  {
   const int total=ArraySize(m_modules);
   for(int i=0;i<total;i++)
     {
      if(m_modules[i]==NULL)
         continue;
      if(!m_modules[i].Initialize())
        {
         if(m_logger!=NULL)
            m_logger.Fatal("CModuleRegistry",
                           "initialisation failed: "+m_modules[i].ModuleName());
         return(false);
        }
      m_initialized_count=i+1;
     }
   return(true);
  }
//+------------------------------------------------------------------+
void CModuleRegistry::ValidateAll(SValidationResult &result)
  {
   const int total=ArraySize(m_modules);
   for(int i=0;i<total;i++)
      if(m_modules[i]!=NULL)
         m_modules[i].Validate(result);
  }
//+------------------------------------------------------------------+
void CModuleRegistry::ShutdownAll(void)
  {
   const int total=ArraySize(m_modules);
   //--- Reverse order: a module may depend on an earlier one.
   for(int i=total-1;i>=0;i--)
     {
      if(m_modules[i]==NULL)
         continue;
      if(i<m_initialized_count)
         m_modules[i].Shutdown();
      delete m_modules[i];
      m_modules[i]=NULL;
     }
   ArrayResize(m_modules,0);
   m_initialized_count=0;
  }
//+------------------------------------------------------------------+
IModule *CModuleRegistry::At(const int index) const
  {
   if(index<0 || index>=ArraySize(m_modules))
      return(NULL);
   return(m_modules[index]);
  }
//+------------------------------------------------------------------+
IModule *CModuleRegistry::FindByName(const string name) const
  {
   const int total=ArraySize(m_modules);
   for(int i=0;i<total;i++)
      if(m_modules[i]!=NULL && m_modules[i].ModuleName()==name)
         return(m_modules[i]);
   return(NULL);
  }

#endif // SRP_CORE_CMODULEREGISTRY_MQH
//+------------------------------------------------------------------+
