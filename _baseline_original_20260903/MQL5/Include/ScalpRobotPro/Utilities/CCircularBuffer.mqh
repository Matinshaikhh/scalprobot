//+------------------------------------------------------------------+
//|                                              CCircularBuffer.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Utilities : fixed-capacity rolling window of doubles.              |
//|                                                                  |
//|   Used for rolling spread, rolling ATR, rolling returns and the      |
//|   equity curve sample. Capacity is fixed at construction so the      |
//|   memory profile is constant - important for an EA that must run     |
//|   for months without a restart.                                     |
//+------------------------------------------------------------------+
#ifndef SRP_UTILITIES_CCIRCULARBUFFER_MQH
#define SRP_UTILITIES_CCIRCULARBUFFER_MQH

#include "CMathUtils.mqh"

class CCircularBuffer
  {
private:
   double            m_data[];
   int               m_capacity;
   int               m_cursor;            // next write position
   int               m_count;             // filled slots, <= capacity
   double            m_running_sum;       // maintained incrementally

public:
                     CCircularBuffer(void);
                    ~CCircularBuffer(void);

   bool              Resize(const int capacity);
   void              Clear(void);

   //--- Overwrites the oldest value when full, updating the running
   //--- sum so Mean() stays O(1) rather than O(n) per tick.
   void              Push(const double value);

   int               Capacity(void) const { return(m_capacity); }
   int               Count(void)    const { return(m_count); }
   bool              IsFull(void)   const { return(m_count>=m_capacity); }
   bool              IsEmpty(void)  const { return(m_count==0); }

   //--- 'age' 0 == most recently pushed value.
   bool              At(const int age,double &out_value) const;
   bool              Newest(double &out_value) const;
   bool              Oldest(double &out_value) const;

   //--- Aggregates over the filled portion only.
   double            Sum(void)     const { return(m_running_sum); }
   double            Mean(void)    const;
   double            Maximum(void) const;
   double            Minimum(void) const;
   double            StandardDeviation(void) const;

   //--- Chronological copy (oldest first), for statistics routines.
   bool              ToArray(double &out[]) const;
  };

//+------------------------------------------------------------------+
CCircularBuffer::CCircularBuffer(void)
  : m_capacity(0),
    m_cursor(0),
    m_count(0),
    m_running_sum(0.0)
  {
   ArrayResize(m_data,0);
  }
//+------------------------------------------------------------------+
CCircularBuffer::~CCircularBuffer(void)
  {
   ArrayFree(m_data);
  }
//+------------------------------------------------------------------+
bool CCircularBuffer::Resize(const int capacity)
  {
   if(capacity<1)
      return(false);
   if(ArrayResize(m_data,capacity)!=capacity)
      return(false);
   ArrayInitialize(m_data,0.0);
   m_capacity=capacity;
   Clear();
   return(true);
  }
//+------------------------------------------------------------------+
void CCircularBuffer::Clear(void)
  {
   m_cursor=0;
   m_count=0;
   m_running_sum=0.0;
  }
//+------------------------------------------------------------------+
void CCircularBuffer::Push(const double value)
  {
   if(m_capacity<1)
      return;
   //--- Subtract the value being evicted before overwriting it.
   if(m_count>=m_capacity)
      m_running_sum-=m_data[m_cursor];
   else
      m_count++;
   m_data[m_cursor]=value;
   m_running_sum+=value;
   m_cursor=(m_cursor+1)%m_capacity;
  }
//+------------------------------------------------------------------+
bool CCircularBuffer::At(const int age,double &out_value) const
  {
   out_value=0.0;
   if(age<0 || age>=m_count)
      return(false);
   //--- Walk backwards from the write cursor.
   int index=m_cursor-1-age;
   while(index<0)
      index+=m_capacity;
   out_value=m_data[index];
   return(true);
  }
//+------------------------------------------------------------------+
bool CCircularBuffer::Newest(double &out_value) const
  {
   return(At(0,out_value));
  }
//+------------------------------------------------------------------+
bool CCircularBuffer::Oldest(double &out_value) const
  {
   return(At(m_count-1,out_value));
  }
//+------------------------------------------------------------------+
double CCircularBuffer::Mean(void) const
  {
   return(CMathUtils::SafeDivide(m_running_sum,(double)m_count,0.0));
  }

#endif // SRP_UTILITIES_CCIRCULARBUFFER_MQH
//+------------------------------------------------------------------+
