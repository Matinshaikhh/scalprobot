//+------------------------------------------------------------------+
//|                                             CLotNormalizer.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : makes a raw volume broker-legal and affordable.                |
//|                                                                  |
//|   RESPONSIBILITY (one only): normalisation. Sizers compute intent;      |
//|   this class makes that intent executable - volume step, min, max,      |
//|   configured cap, and free-margin affordability.                        |
//|                                                                  |
//|   IT ALWAYS ROUNDS DOWN. Rounding up would silently exceed the risk     |
//|   budget the sizer just computed, and on a small account the            |
//|   difference between 0.01 and 0.02 lots is a doubling of risk.          |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CLOTNORMALIZER_MQH
#define SRP_RISK_CLOTNORMALIZER_MQH

#include "../Core/Interfaces/ILogger.mqh"
#include "../Core/Types/Structs.mqh"

class CLotNormalizer
  {
private:
   ILogger          *m_logger;             // borrowed
   double            m_configured_max_lot;
   double            m_configured_min_lot;
   double            m_min_free_margin_percent;

   //--- Largest volume the account can actually afford, given the
   //--- free-margin floor the user configured.
   double            AffordableVolume(const SDecisionContext &context,
                                      const SSymbolSpec &spec,
                                      const ENUM_SRP_SIGNAL_DIRECTION direction) const;

public:
                     CLotNormalizer(ILogger *logger);
                    ~CLotNormalizer(void) { }

   void              SetBounds(const double min_lot,const double max_lot);
   void              SetMinFreeMarginPercent(const double percent);

   //--- Returns a legal volume, or 0.0 when no legal volume exists.
   //--- 'explanation' always states what was clamped and why, so a
   //--- support ticket about "wrong lot size" is answerable from the log.
   double            Normalize(const double raw_volume,
                               const SDecisionContext &context,
                               const SSymbolSpec &spec,
                               const ENUM_SRP_SIGNAL_DIRECTION direction,
                               string &explanation) const;

   //--- Independent margin check, also used before partial closes.
   bool              IsAffordable(const double volume,
                                  const SDecisionContext &context,
                                  const SSymbolSpec &spec,
                                  const ENUM_SRP_SIGNAL_DIRECTION direction,
                                  double &required_margin) const;
  };

#endif // SRP_RISK_CLOTNORMALIZER_MQH
//+------------------------------------------------------------------+
