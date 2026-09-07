//+------------------------------------------------------------------+
//|                                                      IModule.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : the universal lifecycle contract.            |
//|                                                                  |
//|   Every long-lived component implements IModule so the kernel    |
//|   can initialise, validate, health-check and dispose the entire  |
//|   object graph uniformly - without knowing any concrete type.    |
//|   This is the backbone of the Dependency Inversion Principle in  |
//|   this codebase.                                                 |
//|                                                                  |
//|   LANGUAGE CONSTRAINT (drives the whole contract layer):         |
//|   MQL5 does not support multiple inheritance - a class or an     |
//|   interface has at most ONE parent. Consequently:                |
//|     * Role interfaces that need a lifecycle inherit IModule      |
//|       singly (IStrategy : IModule, IFilter : IModule, ...), so   |
//|       one concrete class is legally both a role and a module.    |
//|     * Roles that need NO lifecycle (pure calculators such as     |
//|       IPositionSizer) stay parentless and stay cheap.            |
//|     * A module that must also observe the event bus cannot       |
//|       additionally inherit IEventListener; it composes a         |
//|       CEventListenerAdapter instead. See IEventListener.mqh.     |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_IMODULE_MQH
#define SRP_CORE_INTERFACES_IMODULE_MQH

#include "../Types/Structs.mqh"

interface IModule
  {
   //--- Stable unique identity, used in logs and health reports.
   string            ModuleName(void);

   //--- Acquire resources. Returns false to abort engine startup.
   //--- Must be idempotent and must not throw side effects on failure.
   bool              Initialize(void);

   //--- Self-check performed after the whole graph is wired, so a
   //--- module may verify its collaborators are present.
   void              Validate(SValidationResult &result);

   //--- Release resources. Must tolerate being called after a failed
   //--- Initialize and must never fail.
   void              Shutdown(void);

   //--- Runtime liveness probe, polled by CHealthMonitor.
   void              ReportHealth(SHealthReport &report);

   //--- Optional event hook. Declared HERE rather than on
   //--- IEventListener because MQL5 permits only one parent: a class
   //--- that already inherits IStrategy could never also inherit
   //--- IEventListener. CEventListenerAdapter wraps an IModule* and
   //--- forwards bus traffic into this method. Modules that do not
   //--- care simply inherit the no-op from their base class.
   void              HandleEvent(const SEventPayload &payload);
  };

#endif // SRP_CORE_INTERFACES_IMODULE_MQH
//+------------------------------------------------------------------+
