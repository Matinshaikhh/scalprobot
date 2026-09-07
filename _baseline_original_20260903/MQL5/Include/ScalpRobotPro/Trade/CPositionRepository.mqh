//+------------------------------------------------------------------+
//|                                        CPositionRepository.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Trade : read-only view of the EA's own open positions.                |
//|                                                                  |
//|   RESPONSIBILITY (one only): query the terminal once per pass and        |
//|   expose normalised snapshots plus aggregate exposure. It never           |
//|   modifies anything - "repository" here means read model.                |
//|                                                                  |
//|   TWO PROPERTIES THAT MATTER                                            |
//|   1. It filters by MAGIC and SYMBOL, so the EA is blind to positions     |
//|      it does not own. Manual trades and other EAs are never touched.     |
//|   2. It caches per pass. PositionsTotal/PositionSelect in a loop is       |
//|      both slow and racy; every consumer reading one cached snapshot set  |
//|      removes an entire class of intermittent bug.                        |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_CPOSITIONREPOSITORY_MQH
#define SRP_TRADE_CPOSITIONREPOSITORY_MQH

#include "../Core/Interfaces/IModule.mqh"
#include "../Core/Interfaces/IClock.mqh"
#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Base/CModuleIdentity.mqh"

class CSymbolInfoProvider;

class CPositionRepository : public IModule
  {
private:
   CModuleIdentity      m_id;
   CSymbolInfoProvider *m_symbol_info;     // borrowed
   IClock              *m_clock;           // borrowed
   long                 m_magic;
   string               m_symbol;
   bool                 m_restrict_to_symbol;

   SPositionSnapshot    m_positions[];
   SPortfolioExposure   m_exposure;
   ulong                m_refresh_sequence;
   datetime             m_last_refresh;

   bool              IsOwnedPosition(const ulong ticket) const;
   bool              ReadPosition(const ulong ticket,SPositionSnapshot &out) const;
   void              ComputeExposure(void);

public:
                     CPositionRepository(CSymbolInfoProvider *symbol_info,
                                         IClock *clock,
                                         const long magic,
                                         ILogger *logger);
                    ~CPositionRepository(void);

   void              SetRestrictToSymbol(const bool value);

   //--- IModule ------------------------------------------------------
   virtual string    ModuleName(void) override { return(m_id.Name()); }
   virtual bool      Initialize(void) override;
   virtual void      Validate(SValidationResult &result) override;
   virtual void      Shutdown(void) override;
   virtual void      ReportHealth(SHealthReport &report) override;
   virtual void      HandleEvent(const SEventPayload &payload) override;

   //--- Pipeline stage 5. One terminal sweep per pass.
   bool              Refresh(const ulong snapshot_sequence);

   //--- Queries -------------------------------------------------------
   int               Count(void) const { return(ArraySize(m_positions)); }
   bool              At(const int index,SPositionSnapshot &out) const;
   bool              FindByTicket(const ulong ticket,SPositionSnapshot &out) const;
   void              GetExposure(SPortfolioExposure &out) const { out=m_exposure; }

   int               CountByType(const ENUM_POSITION_TYPE type) const;
   bool              HasAnyPosition(void) const { return(ArraySize(m_positions)>0); }
   bool              OldestPosition(SPositionSnapshot &out) const;
   bool              MostProfitablePosition(SPositionSnapshot &out) const;
   bool              LeastProfitablePosition(SPositionSnapshot &out) const;

   //--- Used by the frequency filter to enforce a cool-down.
   datetime          MostRecentOpenTime(void) const;

   long              Magic(void) const { return(m_magic); }
  };

#endif // SRP_TRADE_CPOSITIONREPOSITORY_MQH
//+------------------------------------------------------------------+
