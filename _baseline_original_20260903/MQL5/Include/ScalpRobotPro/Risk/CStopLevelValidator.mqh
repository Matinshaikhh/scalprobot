//+------------------------------------------------------------------+
//|                                       CStopLevelValidator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : makes computed levels broker-legal.                            |
//|                                                                  |
//|   RESPONSIBILITY (one only): enforce SYMBOL_TRADE_STOPS_LEVEL and       |
//|   freeze level. Calculators express trading intent; this class makes    |
//|   that intent acceptable to the server.                                 |
//|                                                                  |
//|   WHY IT IS ITS OWN CLASS                                              |
//|   "Invalid stops" (retcode 10016) is the single most common rejection   |
//|   in retail EAs, and it is usually because stop-level clamping was      |
//|   copy-pasted into three places and fixed in only two. One class, one   |
//|   rule, applied to every order and every modification.                  |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CSTOPLEVELVALIDATOR_MQH
#define SRP_RISK_CSTOPLEVELVALIDATOR_MQH

#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Types/Structs.mqh"

class CStopLevelValidator
  {
private:
   ILogger          *m_logger;             // borrowed
   int               m_safety_margin_points; // extra buffer over the minimum
   bool              m_clamp_instead_of_reject;

public:
                     CStopLevelValidator(ILogger *logger);
                    ~CStopLevelValidator(void) { }

   void              SetSafetyMargin(const int points);
   //--- true  => push an illegal level to the nearest legal one
   //--- false => reject the trade instead of silently changing risk
   void              SetClampMode(const bool clamp);

   //--- Validates and, when permitted, adjusts both levels together.
   //--- Returns false when the request must be abandoned.
   bool              ValidateAndAdjust(const SSymbolSpec &spec,
                                       const SMarketSnapshot &market,
                                       const ENUM_SRP_SIGNAL_DIRECTION direction,
                                       const double entry_price,
                                       double &stop_loss,
                                       double &take_profit,
                                       string &explanation) const;

   //--- Used before a modification: a level inside the freeze zone
   //--- cannot be changed, so the position manager must skip the update
   //--- rather than retry it forever.
   bool              IsModificationAllowed(const SSymbolSpec &spec,
                                           const SMarketSnapshot &market,
                                           const SPositionSnapshot &position,
                                           string &reason) const;

   //--- Confirms the level sits on the correct side of entry. Catches
   //--- sign errors in custom calculators before the server does.
   bool              IsSideCorrect(const ENUM_SRP_SIGNAL_DIRECTION direction,
                                   const double entry_price,
                                   const double stop_loss,
                                   const double take_profit) const;

   int               MinimumDistancePoints(const SSymbolSpec &spec) const;
  };

#endif // SRP_RISK_CSTOPLEVELVALIDATOR_MQH
//+------------------------------------------------------------------+
