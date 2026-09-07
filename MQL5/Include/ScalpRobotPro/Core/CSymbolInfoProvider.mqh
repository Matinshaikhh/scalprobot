//+------------------------------------------------------------------+
//|                                           CSymbolInfoProvider.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core : resolves and caches the instrument specification.         |
//|                                                                  |
//|   RESPONSIBILITY (one only): produce a trustworthy SSymbolSpec.    |
//|   Every SymbolInfoDouble/Integer call in the entire product lives  |
//|   here. Downstream code reads a plain struct, which means broker   |
//|   quirks (5-digit gold, unusual tick value, netting vs hedging)    |
//|   are handled in ONE place instead of being rediscovered in each   |
//|   calculator.                                                     |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_CSYMBOLINFOPROVIDER_MQH
#define SRP_CORE_CSYMBOLINFOPROVIDER_MQH

#include "Interfaces/IModule.mqh"
#include "Interfaces/ILogger.mqh"
#include "Base/CModuleIdentity.mqh"

class CSymbolInfoProvider : public IModule
  {
private:
   CModuleIdentity   m_id;
   string            m_symbol;
   SSymbolSpec       m_spec;
   datetime          m_last_refresh;

   //--- Reads every field from the terminal into m_spec.
   bool              ResolveSpec(void);
   //--- Confirms the broker allows full trading on this symbol.
   bool              IsTradeModeAcceptable(void) const;

public:
                     CSymbolInfoProvider(const string symbol,ILogger *logger);
                    ~CSymbolInfoProvider(void) { }

   //--- IModule -----------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override { }

   //--- Queries -----------------------------------------------------
   void              GetSpec(SSymbolSpec &out) const { out=m_spec; }
   string            Symbol(void)              const { return(m_symbol); }
   bool              IsResolved(void)          const { return(m_spec.is_resolved); }

   //--- Values that can legitimately change intraday (variable spread
   //--- brokers widen stop levels), so they are re-read on demand.
   bool              RefreshVolatileFields(void);

   //--- Conversions used by risk and trade layers. Centralised here so
   //--- no module reimplements point arithmetic.
   double            PointsToPrice(const double points) const;
   double            PriceToPoints(const double price_delta) const;
   double            NormalizePrice(const double price) const;
   double            MoneyPerPointPerLot(void) const;
  };

#endif // SRP_CORE_CSYMBOLINFOPROVIDER_MQH
//+------------------------------------------------------------------+
