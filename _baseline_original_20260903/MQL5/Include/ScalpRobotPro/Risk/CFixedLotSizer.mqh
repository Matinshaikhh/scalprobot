//+------------------------------------------------------------------+
//|                                             CFixedLotSizer.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : constant volume sizing.                                        |
//|                                                                  |
//|   The simplest IPositionSizer, and the default for users who want      |
//|   predictable exposure. Deliberately its own class rather than a       |
//|   branch inside a switch: a sizing mode is a policy, and policies      |
//|   belong in separate types (GoF Strategy pattern).                     |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CFIXEDLOTSIZER_MQH
#define SRP_RISK_CFIXEDLOTSIZER_MQH

#include "../Core/Interfaces/IPositionSizer.mqh"

class CFixedLotSizer : public IPositionSizer
  {
private:
   double            m_fixed_lot;

public:
                     CFixedLotSizer(const double fixed_lot);
                    ~CFixedLotSizer(void) { }

   void              SetFixedLot(const double lot);

   virtual ENUM_SRP_RISK_MODE Mode(void) override { return(SRP_RISK_FIXED_LOT); }
   virtual string    SizerName(void) override { return("FixedLotSizer"); }

   virtual double    CalculateVolume(const SDecisionContext &context,
                                     const SSymbolSpec &spec,
                                     const double stop_distance_points,
                                     string &explanation) override;
  };

//+------------------------------------------------------------------+
CFixedLotSizer::CFixedLotSizer(const double fixed_lot)
  : m_fixed_lot(fixed_lot)
  {
  }
//+------------------------------------------------------------------+
void CFixedLotSizer::SetFixedLot(const double lot)
  {
   if(lot>0.0)
      m_fixed_lot=lot;
  }
//+------------------------------------------------------------------+
double CFixedLotSizer::CalculateVolume(const SDecisionContext &context,
                                       const SSymbolSpec &spec,
                                       const double stop_distance_points,
                                       string &explanation)
  {
   explanation="fixed lot "+DoubleToString(m_fixed_lot,2);
   return(m_fixed_lot);
  }

#endif // SRP_RISK_CFIXEDLOTSIZER_MQH
//+------------------------------------------------------------------+
