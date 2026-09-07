//+------------------------------------------------------------------+
//|                                                CNewsFilter.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   News : IFilter adapter over the blackout evaluator.                    |
//|                                                                  |
//|   Deliberately trivial. All the reasoning lives in                       |
//|   CNewsBlackoutEvaluator; this class exists so news participates in the   |
//|   normal filter chain like every other veto, with the same diagnostics    |
//|   and the same dashboard treatment.                                      |
//|                                                                  |
//|   That is the Adapter pattern doing real work: one concern (news timing)  |
//|   expressed in two roles (a service and a filter) without duplicating     |
//|   a single line of logic.                                               |
//+------------------------------------------------------------------+
#ifndef SRP_NEWS_CNEWSFILTER_MQH
#define SRP_NEWS_CNEWSFILTER_MQH

#include "../Core/Base/CFilterBase.mqh"

class CNewsBlackoutEvaluator;

class CNewsFilter : public CFilterBase
  {
private:
   CNewsBlackoutEvaluator *m_evaluator;    // borrowed

protected:
   virtual bool      OnInitialize(void) override;
   virtual void      OnValidate(SValidationResult &result) override;
   virtual void      OnEvaluate(const SDecisionContext &context,
                                const ENUM_SRP_SIGNAL_DIRECTION direction,
                                SFilterVerdict &verdict) override;

public:
                     CNewsFilter(CNewsBlackoutEvaluator *evaluator,
                                 ILogger *logger);
                    ~CNewsFilter(void) { }
  };

#endif // SRP_NEWS_CNEWSFILTER_MQH
//+------------------------------------------------------------------+
