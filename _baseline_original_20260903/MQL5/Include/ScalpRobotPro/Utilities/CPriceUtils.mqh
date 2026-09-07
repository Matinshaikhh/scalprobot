//+------------------------------------------------------------------+
//|                                                 CPriceUtils.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Utilities : symbol-aware price arithmetic.                        |
//|                                                                  |
//|   Every function takes an SSymbolSpec, so the same code is correct  |
//|   on 2-digit gold, 3-digit JPY pairs and 5-digit majors. Point vs   |
//|   pip confusion is one of the most common defects in commercial     |
//|   EAs; concentrating the arithmetic here eliminates the class of    |
//|   bug entirely.                                                    |
//+------------------------------------------------------------------+
#ifndef SRP_UTILITIES_CPRICEUTILS_MQH
#define SRP_UTILITIES_CPRICEUTILS_MQH

#include "../Core/Types/Structs.mqh"
#include "CMathUtils.mqh"

class CPriceUtils
  {
public:
   //--- Point/price conversion --------------------------------------
   static double     PointsToPrice(const SSymbolSpec &spec,const double points);
   static double     PriceToPoints(const SSymbolSpec &spec,const double price_delta);
   static double     NormalizePrice(const SSymbolSpec &spec,const double price);
   static double     NormalizeVolume(const SSymbolSpec &spec,const double volume);

   //--- Directional helpers. Passing the direction rather than
   //--- duplicating buy/sell branches at every call site keeps the
   //--- risk and trade layers symmetrical and audit-friendly.
   static double     EntryPrice(const SSymbolSpec &spec,
                                const SMarketSnapshot &market,
                                const ENUM_SRP_SIGNAL_DIRECTION direction);
   static double     ExitPrice(const SSymbolSpec &spec,
                               const SMarketSnapshot &market,
                               const ENUM_SRP_SIGNAL_DIRECTION direction);
   static double     StopLossPrice(const SSymbolSpec &spec,
                                   const double entry_price,
                                   const double distance_points,
                                   const ENUM_SRP_SIGNAL_DIRECTION direction);
   static double     TakeProfitPrice(const SSymbolSpec &spec,
                                     const double entry_price,
                                     const double distance_points,
                                     const ENUM_SRP_SIGNAL_DIRECTION direction);

   //--- Profit measurement -----------------------------------------
   static double     ProfitPoints(const SSymbolSpec &spec,
                                  const double open_price,
                                  const double current_price,
                                  const ENUM_SRP_SIGNAL_DIRECTION direction);
   static double     MoneyFromPoints(const SSymbolSpec &spec,
                                     const double points,
                                     const double volume);
   static double     PointsFromMoney(const SSymbolSpec &spec,
                                     const double money,
                                     const double volume);

   //--- Broker constraint checks -----------------------------------
   static bool       RespectsStopLevel(const SSymbolSpec &spec,
                                       const double reference_price,
                                       const double level_price);
   static double     ClampToStopLevel(const SSymbolSpec &spec,
                                      const double reference_price,
                                      const double level_price,
                                      const ENUM_SRP_SIGNAL_DIRECTION direction,
                                      const bool is_stop_loss);
   static bool       IsWithinFreezeLevel(const SSymbolSpec &spec,
                                         const double reference_price,
                                         const double level_price);

   static double     SpreadPoints(const SSymbolSpec &spec,
                                  const SMarketSnapshot &market);
  };

//+------------------------------------------------------------------+
double CPriceUtils::PointsToPrice(const SSymbolSpec &spec,const double points)
  {
   return(points*spec.point);
  }
//+------------------------------------------------------------------+
double CPriceUtils::PriceToPoints(const SSymbolSpec &spec,const double price_delta)
  {
   return(CMathUtils::SafeDivide(price_delta,spec.point,0.0));
  }
//+------------------------------------------------------------------+
double CPriceUtils::NormalizePrice(const SSymbolSpec &spec,const double price)
  {
   //--- Round to tick size first, then to digits: a broker may use a
   //--- tick size that is a multiple of point (common on metals).
   const double ticked=CMathUtils::RoundToStep(price,spec.tick_size);
   return(NormalizeDouble(ticked,spec.digits));
  }
//+------------------------------------------------------------------+
double CPriceUtils::NormalizeVolume(const SSymbolSpec &spec,const double volume)
  {
   //--- Floor, never round up: rounding up can exceed the risk budget
   //--- that was just approved.
   double stepped=CMathUtils::FloorToStep(volume,spec.volume_step);
   stepped=CMathUtils::Clamp(stepped,spec.volume_min,spec.volume_max);
   //--- Two decimals covers every broker volume step in practice.
   return(NormalizeDouble(stepped,2));
  }
//+------------------------------------------------------------------+
double CPriceUtils::EntryPrice(const SSymbolSpec &spec,
                               const SMarketSnapshot &market,
                               const ENUM_SRP_SIGNAL_DIRECTION direction)
  {
   if(direction==SRP_SIGNAL_BUY)
      return(market.ask);
   if(direction==SRP_SIGNAL_SELL)
      return(market.bid);
   return(SRP_INVALID_PRICE);
  }
//+------------------------------------------------------------------+
double CPriceUtils::ExitPrice(const SSymbolSpec &spec,
                              const SMarketSnapshot &market,
                              const ENUM_SRP_SIGNAL_DIRECTION direction)
  {
   //--- A long is closed at bid, a short at ask.
   if(direction==SRP_SIGNAL_BUY)
      return(market.bid);
   if(direction==SRP_SIGNAL_SELL)
      return(market.ask);
   return(SRP_INVALID_PRICE);
  }
//+------------------------------------------------------------------+
double CPriceUtils::StopLossPrice(const SSymbolSpec &spec,
                                  const double entry_price,
                                  const double distance_points,
                                  const ENUM_SRP_SIGNAL_DIRECTION direction)
  {
   if(distance_points<=0.0 || direction==SRP_SIGNAL_NONE)
      return(SRP_INVALID_PRICE);
   const double distance=PointsToPrice(spec,distance_points);
   const double level=(direction==SRP_SIGNAL_BUY ? entry_price-distance
                                                 : entry_price+distance);
   return(NormalizePrice(spec,level));
  }
//+------------------------------------------------------------------+
double CPriceUtils::TakeProfitPrice(const SSymbolSpec &spec,
                                    const double entry_price,
                                    const double distance_points,
                                    const ENUM_SRP_SIGNAL_DIRECTION direction)
  {
   if(distance_points<=0.0 || direction==SRP_SIGNAL_NONE)
      return(SRP_INVALID_PRICE);
   const double distance=PointsToPrice(spec,distance_points);
   const double level=(direction==SRP_SIGNAL_BUY ? entry_price+distance
                                                 : entry_price-distance);
   return(NormalizePrice(spec,level));
  }
//+------------------------------------------------------------------+
double CPriceUtils::ProfitPoints(const SSymbolSpec &spec,
                                 const double open_price,
                                 const double current_price,
                                 const ENUM_SRP_SIGNAL_DIRECTION direction)
  {
   const double delta=(direction==SRP_SIGNAL_BUY ? current_price-open_price
                                                 : open_price-current_price);
   return(PriceToPoints(spec,delta));
  }
//+------------------------------------------------------------------+
double CPriceUtils::MoneyFromPoints(const SSymbolSpec &spec,
                                    const double points,
                                    const double volume)
  {
   //--- tick_value is money per tick per lot, so convert points to
   //--- ticks before multiplying. Using point instead of tick_size
   //--- here is the classic 10x sizing error on metals.
   const double ticks=CMathUtils::SafeDivide(points*spec.point,spec.tick_size,0.0);
   return(ticks*spec.tick_value*volume);
  }
//+------------------------------------------------------------------+
double CPriceUtils::PointsFromMoney(const SSymbolSpec &spec,
                                    const double money,
                                    const double volume)
  {
   const double money_per_point=MoneyFromPoints(spec,1.0,volume);
   return(CMathUtils::SafeDivide(money,money_per_point,0.0));
  }
//+------------------------------------------------------------------+
double CPriceUtils::SpreadPoints(const SSymbolSpec &spec,
                                 const SMarketSnapshot &market)
  {
   return(PriceToPoints(spec,market.ask-market.bid));
  }
//+------------------------------------------------------------------+
bool CPriceUtils::RespectsStopLevel(const SSymbolSpec &spec,
                                    const double reference_price,
                                    const double level_price)
  {
   if(level_price<=0.0)
      return(true);                       // no level is always legal
   const double distance=MathAbs(PriceToPoints(spec,reference_price-level_price));
   return(distance>=(double)spec.stops_level_points);
  }

#endif // SRP_UTILITIES_CPRICEUTILS_MQH
//+------------------------------------------------------------------+
