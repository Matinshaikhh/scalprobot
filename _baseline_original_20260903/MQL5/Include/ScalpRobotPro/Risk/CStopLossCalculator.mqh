//+------------------------------------------------------------------+
//|                                        CStopLossCalculator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Risk : composite stop-loss resolution.                                |
//|                                                                  |
//|   RESPONSIBILITY (one only): pick the configured SL model and return    |
//|   a price. The individual models are separate IStopLevelCalculator      |
//|   implementations, so this class is a thin selector - not a switch      |
//|   statement that grows every time a model is added.                     |
//|                                                                  |
//|   OWNERSHIP: owns the calculators it is given.                          |
//+------------------------------------------------------------------+
#ifndef SRP_RISK_CSTOPLOSSCALCULATOR_MQH
#define SRP_RISK_CSTOPLOSSCALCULATOR_MQH

#include "../Core/Interfaces/IStopLevelCalculator.mqh"
#include "../Core/Interfaces/ILogger.mqh"

class CStopLossCalculator
  {
private:
   ILogger              *m_logger;         // borrowed
   ENUM_SRP_SL_MODE      m_mode;
   //--- One calculator per mode, indexed by mode. OWNED.
   IStopLevelCalculator *m_fixed;
   IStopLevelCalculator *m_atr;
   IStopLevelCalculator *m_structure;

   IStopLevelCalculator *Selected(void) const;

public:
                     CStopLossCalculator(ILogger *logger);
                    ~CStopLossCalculator(void);

   void              SetMode(const ENUM_SRP_SL_MODE mode);
   //--- Takes ownership of each calculator.
   void              SetFixedCalculator(IStopLevelCalculator *calculator);
   void              SetAtrCalculator(IStopLevelCalculator *calculator);
   void              SetStructureCalculator(IStopLevelCalculator *calculator);

   ENUM_SRP_SL_MODE  Mode(void) const { return(m_mode); }

   //--- Resolves the stop price. Returns false when the mode is NONE or
   //--- the selected model cannot produce a level.
   bool              Resolve(const SDecisionContext &context,
                             const SSymbolSpec &spec,
                             const ENUM_SRP_SIGNAL_DIRECTION direction,
                             const double entry_price,
                             double &stop_price,
                             string &explanation) const;

   //--- Distance in points between entry and the resolved stop; the
   //--- position sizer needs this, not the price.
   bool              ResolveDistancePoints(const SDecisionContext &context,
                                           const SSymbolSpec &spec,
                                           const ENUM_SRP_SIGNAL_DIRECTION direction,
                                           const double entry_price,
                                           double &distance_points,
                                           string &explanation) const;
  };

#endif // SRP_RISK_CSTOPLOSSCALCULATOR_MQH
//+------------------------------------------------------------------+
