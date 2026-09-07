//+------------------------------------------------------------------+
//|                                       CFixedStopCalculator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : fixed-distance protective level model.                         |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CFIXEDSTOPCALCULATOR_MQH
#define SRP_RISK_CFIXEDSTOPCALCULATOR_MQH

#include "../Core/Interfaces/IStopLevelCalculator.mqh"
#include "../Utilities/CPriceUtils.mqh"

class CFixedStopCalculator : public IStopLevelCalculator
  {
private:
   double            m_distance_points;
   bool              m_is_stop_loss;
   //--- Optionally widen by the current spread, which matters on gold
   //--- where a tight fixed stop can sit inside the spread itself.
   bool              m_add_spread;

public:
                     CFixedStopCalculator(const double distance_points,
                                          const bool is_stop_loss);
                    ~CFixedStopCalculator(void) { }

   void              SetDistancePoints(const double points);
   void              SetAddSpread(const bool value);

   virtual string    CalculatorName(void) override
     {
      return(m_is_stop_loss ? "FixedStopLoss" : "FixedTakeProfit");
     }

   virtual bool      Calculate(const SDecisionContext &context,
                               const SSymbolSpec &spec,
                               const ENUM_SRP_SIGNAL_DIRECTION direction,
                               const double entry_price,
                               double &level_price,
                               string &explanation) override;
  };

//+------------------------------------------------------------------+
CFixedStopCalculator::CFixedStopCalculator(const double distance_points,
                                           const bool is_stop_loss)
  : m_distance_points(distance_points),
    m_is_stop_loss(is_stop_loss),
    m_add_spread(false)
  {
  }
//+------------------------------------------------------------------+
void CFixedStopCalculator::SetDistancePoints(const double points)
  {
   if(points>=0.0)
      m_distance_points=points;
  }
//+------------------------------------------------------------------+
void CFixedStopCalculator::SetAddSpread(const bool value)
  {
   m_add_spread=value;
  }
//+------------------------------------------------------------------+
bool CFixedStopCalculator::Calculate(const SDecisionContext &context,
                                     const SSymbolSpec &spec,
                                     const ENUM_SRP_SIGNAL_DIRECTION direction,
                                     const double entry_price,
                                     double &level_price,
                                     string &explanation)
  {
   level_price=SRP_INVALID_PRICE;
   if(m_distance_points<=0.0 || direction==SRP_SIGNAL_NONE)
     {
      explanation="fixed distance not configured";
      return(false);
     }
   double distance=m_distance_points;
   if(m_add_spread)
      distance+=context.market.spread_points;

   level_price=(m_is_stop_loss
                ? CPriceUtils::StopLossPrice(spec,entry_price,distance,direction)
                : CPriceUtils::TakeProfitPrice(spec,entry_price,distance,direction));

   explanation=CalculatorName()+" "+DoubleToString(distance,1)+" points";
   return(level_price>0.0);
  }

#endif // SRP_RISK_CFIXEDSTOPCALCULATOR_MQH
//+------------------------------------------------------------------+
