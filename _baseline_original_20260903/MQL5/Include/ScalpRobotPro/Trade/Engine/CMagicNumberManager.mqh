//+------------------------------------------------------------------+
//|                                         CMagicNumberManager.mqh |
//|                          Scalping Robot Pro - Core Trading Engine |
//|                                                                  |
//|   RESPONSIBILITY (one only): decide which orders and positions      |
//|   belong to this EA, and stamp outgoing requests so that decision   |
//|   remains possible later.                                          |
//|                                                                  |
//|   WHY THIS IS A CLASS AND NOT A CONSTANT                           |
//|   "magic == InpMagic" scattered across a codebase is how an EA      |
//|   eventually closes a position it does not own - a manual trade, or |
//|   another EA's position on the same symbol. That is unrecoverable   |
//|   for the user and indefensible in a commercial product.            |
//|                                                                  |
//|   This class centralises ownership so there is exactly ONE          |
//|   definition of "ours", and supports a magic RANGE so several       |
//|   strategies can be told apart while all remaining ours:            |
//|                                                                  |
//|       base + 0   reserved for the engine itself                    |
//|       base + 1.. per-strategy slots (attribution in statistics)    |
//|                                                                  |
//|   Slot 0 is reserved deliberately: a position opened before         |
//|   per-strategy attribution existed still resolves as ours.          |
//+------------------------------------------------------------------+
#ifndef SRP_TRADE_ENGINE_CMAGICNUMBERMANAGER_MQH
#define SRP_TRADE_ENGINE_CMAGICNUMBERMANAGER_MQH

#include "../../Core/Types/Constants.mqh"
#include "../../Core/Types/Enums.mqh"

class CMagicNumberManager
  {
private:
   long              m_base_magic;
   int               m_slot_count;        // size of the reserved range
   string            m_comment_tag;       // short prefix for order comments
   int               m_max_comment_length;

public:
                     CMagicNumberManager(const long base_magic=0,
                                         const int slot_count=16);
                    ~CMagicNumberManager(void) { }

   //--- Configuration ------------------------------------------------
   void              SetBaseMagic(const long base_magic);
   void              SetSlotCount(const int slot_count);
   void              SetCommentTag(const string tag);
   void              SetMaxCommentLength(const int length);

   //--- Allocation ---------------------------------------------------
   long              BaseMagic(void)   const { return(m_base_magic); }
   long              EngineMagic(void) const { return(m_base_magic); }
   long              RangeStart(void)  const { return(m_base_magic); }
   long              RangeEnd(void)    const { return(m_base_magic+m_slot_count-1); }

   //--- Magic for a specific strategy. Falls back to the engine magic
   //--- when the id would fall outside the reserved range, so an
   //--- out-of-range id can never collide with a foreign EA.
   long              MagicForStrategy(const ENUM_SRP_STRATEGY_ID strategy_id) const;
   long              MagicForSlot(const int slot) const;

   //--- Ownership ----------------------------------------------------
   //--- The single authority. Every filter on magic goes through this.
   bool              IsOurs(const long magic) const;
   //--- Reverses the mapping for statistics attribution.
   bool              ResolveSlot(const long magic,int &out_slot) const;
   bool              ResolveStrategy(const long magic,
                                     ENUM_SRP_STRATEGY_ID &out_strategy) const;

   //--- Comment stamping ---------------------------------------------
   //--- Brokers truncate and some reject unusual characters, so the
   //--- comment is sanitised here rather than at each call site.
   string            BuildComment(const string detail) const;
   string            Sanitize(const string text) const;

   //--- Diagnostics --------------------------------------------------
   string            Describe(void) const;
   bool              IsConfigured(void) const { return(m_base_magic>0); }
  };

//+------------------------------------------------------------------+
CMagicNumberManager::CMagicNumberManager(const long base_magic,
                                         const int slot_count)
  : m_base_magic(base_magic),
    m_slot_count(slot_count<1 ? 1 : slot_count),
    m_comment_tag(SRP_PRODUCT_SHORT),
    m_max_comment_length(31)
  {
  }
//+------------------------------------------------------------------+
void CMagicNumberManager::SetBaseMagic(const long base_magic)
  {
   if(base_magic>0)
      m_base_magic=base_magic;
  }
//+------------------------------------------------------------------+
void CMagicNumberManager::SetSlotCount(const int slot_count)
  {
   if(slot_count>=1)
      m_slot_count=slot_count;
  }
//+------------------------------------------------------------------+
void CMagicNumberManager::SetCommentTag(const string tag)
  {
   m_comment_tag=Sanitize(tag);
  }
//+------------------------------------------------------------------+
void CMagicNumberManager::SetMaxCommentLength(const int length)
  {
   //--- 31 characters is the widely safe ceiling across brokers.
   if(length>0 && length<=63)
      m_max_comment_length=length;
  }
//+------------------------------------------------------------------+
long CMagicNumberManager::MagicForSlot(const int slot) const
  {
   if(slot<=0 || slot>=m_slot_count)
      return(m_base_magic);
   return(m_base_magic+(long)slot);
  }
//+------------------------------------------------------------------+
long CMagicNumberManager::MagicForStrategy(const ENUM_SRP_STRATEGY_ID strategy_id) const
  {
   //--- +1 keeps slot 0 reserved for the engine.
   return(MagicForSlot((int)strategy_id+1));
  }
//+------------------------------------------------------------------+
bool CMagicNumberManager::IsOurs(const long magic) const
  {
   if(m_base_magic<=0)
      return(false);
   return(magic>=RangeStart() && magic<=RangeEnd());
  }
//+------------------------------------------------------------------+
bool CMagicNumberManager::ResolveSlot(const long magic,int &out_slot) const
  {
   out_slot=SRP_INVALID_INDEX;
   if(!IsOurs(magic))
      return(false);
   out_slot=(int)(magic-m_base_magic);
   return(true);
  }
//+------------------------------------------------------------------+
bool CMagicNumberManager::ResolveStrategy(const long magic,
                                          ENUM_SRP_STRATEGY_ID &out_strategy) const
  {
   out_strategy=SRP_STRATEGY_MOMENTUM;
   int slot=SRP_INVALID_INDEX;
   if(!ResolveSlot(magic,slot))
      return(false);
   //--- Slot 0 is the engine itself: ours, but not attributable.
   if(slot<=0)
      return(false);
   out_strategy=(ENUM_SRP_STRATEGY_ID)(slot-1);
   return(true);
  }
//+------------------------------------------------------------------+
string CMagicNumberManager::Sanitize(const string text) const
  {
   //--- Strip characters that some servers reject or that would break
   //--- CSV journalling downstream.
   string out="";
   const int length=StringLen(text);
   for(int i=0;i<length;i++)
     {
      const ushort ch=StringGetCharacter(text,i);
      const bool is_digit = (ch>='0' && ch<='9');
      const bool is_upper = (ch>='A' && ch<='Z');
      const bool is_lower = (ch>='a' && ch<='z');
      const bool is_safe  = (ch=='_' || ch=='-' || ch=='.' || ch==' ');
      if(is_digit || is_upper || is_lower || is_safe)
         out+=ShortToString(ch);
     }
   return(out);
  }
//+------------------------------------------------------------------+
string CMagicNumberManager::BuildComment(const string detail) const
  {
   string comment=m_comment_tag;
   const string clean_detail=Sanitize(detail);
   if(StringLen(clean_detail)>0)
      comment+="-"+clean_detail;
   if(StringLen(comment)>m_max_comment_length)
      comment=StringSubstr(comment,0,m_max_comment_length);
   return(comment);
  }
//+------------------------------------------------------------------+
string CMagicNumberManager::Describe(void) const
  {
   return(StringFormat("magic range %I64d..%I64d (%d slots), tag '%s'",
                       RangeStart(),RangeEnd(),m_slot_count,m_comment_tag));
  }

#endif // SRP_TRADE_ENGINE_CMAGICNUMBERMANAGER_MQH
//+------------------------------------------------------------------+
