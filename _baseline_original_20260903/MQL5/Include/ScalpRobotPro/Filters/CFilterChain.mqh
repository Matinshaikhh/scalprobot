//+------------------------------------------------------------------+
//|                                               CFilterChain.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Filters : Composite + Chain of Responsibility over IFilter.            |
//|                                                                  |
//|   RESPONSIBILITY (one only): run the filters in priority order and       |
//|   aggregate their verdicts. It knows nothing about spreads, sessions     |
//|   or news.                                                              |
//|                                                                  |
//|   BLOCKING vs ADVISORY                                                  |
//|   A blocking veto stops the chain immediately - there is no value in     |
//|   evaluating the remaining filters once the trade is dead, and on M1     |
//|   that saved work matters. Advisory filters never stop the chain; they   |
//|   only record a verdict for the dashboard, which lets a user observe a   |
//|   filter's behaviour before trusting it to block real trades.            |
//|                                                                  |
//|   Every verdict is retained, so the UI can show precisely which filter   |
//|   rejected which signal - the difference between a supportable product   |
//|   and a black box.                                                      |
//|                                                                  |
//|   OWNERSHIP: owns its filters and deletes them.                         |
//+------------------------------------------------------------------+
#ifndef SRP_FILTERS_CFILTERCHAIN_MQH
#define SRP_FILTERS_CFILTERCHAIN_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IFilter.mqh"
#include "../Core/Interfaces/IEventPublisher.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CFilterChain : public IModule
  {
private:
   CModuleIdentity   m_id;
   IFilter          *m_filters[];          // OWNED
   IEventPublisher  *m_publisher;          // borrowed

   //--- Last-pass verdicts, parallel to m_filters.
   SFilterVerdict    m_verdicts[];
   int               m_verdict_count;
   SFilterChainResult m_last_result;
   long              m_pass_count;
   long              m_veto_count;

   //--- Sorted once at Initialize(); the hot path never sorts.
   void              SortByPriority(void);

public:
                     CFilterChain(IEventPublisher *publisher,ILogger *logger);
                    ~CFilterChain(void);

   //--- Composition. Takes ownership.
   bool              Add(IFilter *filter);
   int               Count(void) const { return(ArraySize(m_filters)); }
   IFilter          *At(const int index) const;
   IFilter          *FindByName(const string name) const;

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Pipeline stage 9. Short-circuits on the first blocking veto.
   bool              Evaluate(const SDecisionContext &context,
                              const ENUM_SRP_SIGNAL_DIRECTION direction,
                              SFilterChainResult &result);

   //--- Diagnostics for the dashboard -------------------------------
   int               VerdictCount(void) const { return(m_verdict_count); }
   bool              GetVerdict(const int index,SFilterVerdict &out) const;
   void              GetLastResult(SFilterChainResult &out) const { out=m_last_result; }
   void              ResetCounters(void);
  };

#endif // SRP_FILTERS_CFILTERCHAIN_MQH
//+------------------------------------------------------------------+
