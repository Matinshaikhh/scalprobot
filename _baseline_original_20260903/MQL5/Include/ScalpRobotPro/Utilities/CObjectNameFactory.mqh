//+------------------------------------------------------------------+
//|                                          CObjectNameFactory.mqh |
//|                          Scalping Robot Pro - Architecture Layer |
//|   Utilities : generates unique, namespaced chart object names.        |
//|                                                                  |
//|   Every graphical object in the product is named through this        |
//|   factory. Two consequences: names never collide with another EA's   |
//|   objects, and cleanup can be exhaustive without deleting a user's   |
//|   manually drawn objects. Both are hard requirements for a           |
//|   commercial product that shares a chart.                            |
//+------------------------------------------------------------------+
#ifndef SRP_UTILITIES_COBJECTNAMEFACTORY_MQH
#define SRP_UTILITIES_COBJECTNAMEFACTORY_MQH

#include "../Core/Types/Constants.mqh"

class CObjectNameFactory
  {
private:
   string            m_prefix;
   long              m_counter;

public:
                     CObjectNameFactory(const string prefix=SRP_OBJECT_PREFIX);
                    ~CObjectNameFactory(void) { }

   //--- Deterministic name: same inputs always produce the same name,
   //--- so a widget can find and update its own objects after a
   //--- terminal profile reload.
   string            Build(const string component,const string element) const;
   string            BuildIndexed(const string component,const string element,
                                  const int index) const;
   //--- Non-deterministic name for transient markers (trade arrows).
   string            BuildUnique(const string component);

   string            Prefix(void) const { return(m_prefix); }
   bool              IsOwnedName(const string object_name) const;

   //--- Sweeps every object carrying our prefix. Used at deinit and
   //--- after a failed dashboard build.
   int               DeleteAllOwned(const long chart_id) const;
  };

//+------------------------------------------------------------------+
CObjectNameFactory::CObjectNameFactory(const string prefix)
  : m_prefix(prefix),
    m_counter(0)
  {
  }
//+------------------------------------------------------------------+
string CObjectNameFactory::Build(const string component,const string element) const
  {
   return(m_prefix+component+"_"+element);
  }
//+------------------------------------------------------------------+
string CObjectNameFactory::BuildIndexed(const string component,
                                        const string element,
                                        const int index) const
  {
   return(m_prefix+component+"_"+element+"_"+IntegerToString(index));
  }
//+------------------------------------------------------------------+
string CObjectNameFactory::BuildUnique(const string component)
  {
   m_counter++;
   return(m_prefix+component+"_"+IntegerToString(m_counter));
  }
//+------------------------------------------------------------------+
bool CObjectNameFactory::IsOwnedName(const string object_name) const
  {
   const int prefix_length=StringLen(m_prefix);
   if(StringLen(object_name)<prefix_length)
      return(false);
   return(StringSubstr(object_name,0,prefix_length)==m_prefix);
  }
//+------------------------------------------------------------------+
int CObjectNameFactory::DeleteAllOwned(const long chart_id) const
  {
   int deleted=0;
   //--- Iterate backwards: deleting shifts the remaining indices.
   for(int i=ObjectsTotal(chart_id,-1,-1)-1;i>=0;i--)
     {
      const string name=ObjectName(chart_id,i,-1,-1);
      if(!IsOwnedName(name))
         continue;
      if(ObjectDelete(chart_id,name))
         deleted++;
     }
   return(deleted);
  }

#endif // SRP_UTILITIES_COBJECTNAMEFACTORY_MQH
//+------------------------------------------------------------------+
