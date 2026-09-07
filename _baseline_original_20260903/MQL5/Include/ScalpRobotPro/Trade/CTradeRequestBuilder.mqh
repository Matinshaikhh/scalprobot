//+------------------------------------------------------------------+
//|                                      CTradeRequestBuilder.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Trade : assembles a complete, validated STradeRequest.                |
//|                                                                  |
//|   RESPONSIBILITY (one only): construct the request. It performs no       |
//|   decision-making - the signal decided direction, the risk layer         |
//|   decided size and levels. This class fills in the mechanical fields     |
//|   that the server requires and that are easy to get wrong: magic         |
//|   number, deviation, filling mode, comment, and price selection.         |
//|                                                                  |
//|   FILLING MODE is resolved from the symbol's actual capabilities         |
//|   rather than hard-coded. Assuming FOK is a standard cause of            |
//|   "unsupported filling mode" rejections on ECN accounts.                |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_CTRADEREQUESTBUILDER_MQH
#define SRP_TRADE_CTRADEREQUESTBUILDER_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CSymbolInfoProvider;

class CTradeRequestBuilder : public IModule
  {
private:
   CModuleIdentity      m_id;
   CSymbolInfoProvider *m_symbol_info;     // borrowed
   long                 m_magic;
   string               m_comment_template;
   int                  m_deviation_points;
   ENUM_ORDER_TYPE_FILLING m_filling_mode;
   bool                 m_filling_resolved;

   //--- Queries SYMBOL_FILLING_MODE once and picks a supported value.
   bool              ResolveFillingMode(void);
   //--- Comments are truncated to the broker's limit and stripped of
   //--- characters some servers reject.
   string            BuildComment(const SSignal &signal) const;

public:
                     CTradeRequestBuilder(CSymbolInfoProvider *symbol_info,
                                          ILogger *logger);
                    ~CTradeRequestBuilder(void) { }

   void              SetMagic(const long magic);
   void              SetCommentTemplate(const string template_text);
   void              SetDeviationPoints(const int points);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Pipeline stage 11. Returns false when the inputs are incoherent,
   //--- which is a bug-catching net rather than an expected outcome.
   bool              Build(const SDecisionContext &context,
                           const SSignal &signal,
                           const SRiskDecision &risk,
                           STradeRequest &request);

   long              Magic(void) const { return(m_magic); }
   ENUM_ORDER_TYPE_FILLING FillingMode(void) const { return(m_filling_mode); }
  };

#endif // SRP_TRADE_CTRADEREQUESTBUILDER_MQH
//+------------------------------------------------------------------+
