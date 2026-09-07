//+------------------------------------------------------------------+
//|                                                   IIndicator.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Core/Interfaces : technical-indicator contract.                |
//|                                                                  |
//|   Wraps a terminal indicator handle so that no strategy ever      |
//|   calls iCustom/iMA or CopyBuffer directly. Benefits:             |
//|     * handles are created once and released deterministically;    |
//|     * buffers are copied once per bar, not once per strategy;     |
//|     * strategies become unit-testable against fake indicators.    |
//+------------------------------------------------------------------+
#ifndef SRP_CORE_INTERFACES_IINDICATOR_MQH
#define SRP_CORE_INTERFACES_IINDICATOR_MQH

#include "IModule.mqh"

interface IIndicator : public IModule
  {
   ENUM_SRP_INDICATOR_ID IndicatorId(void);
   string            IndicatorName(void);

   //--- Underlying terminal handle, exposed for diagnostics only.
   int               Handle(void);
   bool              IsReady(void);

   //--- Pull fresh buffer data. Called once per pass by
   //--- CIndicatorManager, never by strategies.
   bool              Refresh(void);

   //--- Buffer access. 'shift' 0 == current bar. Returns false when
   //--- the value is unavailable, so callers cannot read garbage.
   bool              GetValue(const int buffer_index,const int shift,double &value);
   bool              GetSeries(const int buffer_index,const int start,
                               const int count,double &out[]);

   int               BufferCount(void);
   int               MinimumBars(void);
  };

#endif // SRP_CORE_INTERFACES_IINDICATOR_MQH
//+------------------------------------------------------------------+
